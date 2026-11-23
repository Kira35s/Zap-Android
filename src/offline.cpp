#include "offline.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStorageInfo>
#include <QUrl>
#include <algorithm>

namespace {

// Lost connections are tried again this many times, this far apart.
constexpr int MaxAttempts = 5;
constexpr int RetryDelay = 15000;
// Room left on the device after a download, for everything else.
constexpr qint64 SpareSpace = 200LL * 1024 * 1024;

QString stateName(Download::State state) {
    switch (state) {
    case Download::Done: return QStringLiteral("done");
    case Download::Failed: return QStringLiteral("failed");
    default: return QStringLiteral("queued");
    }
}

} // namespace

Offline::Offline(const QString &directory, QObject *parent) : QObject(parent), m_directory(directory) {
    QDir().mkpath(m_directory);
    m_retryTimer.setSingleShot(true);
    m_retryTimer.setInterval(RetryDelay);
    connect(&m_retryTimer, &QTimer::timeout, this, &Offline::next);
    load();
    QTimer::singleShot(0, this, &Offline::next);
}

Offline::~Offline() {
    stop();
}

bool Offline::canDownload(const Entry &entry) {
    if (entry.kind != Entry::Movie && entry.kind != Entry::Episode)
        return false;
    const QString scheme = QUrl(entry.url).scheme();
    return scheme == "http" || scheme == "https";
}

QString Offline::path(const Download &item) const { return m_directory + "/" + item.file; }

const Download *Offline::find(const QString &key) const {
    const auto it = m_items.constFind(key);
    return it == m_items.cend() ? nullptr : &*it;
}

QString Offline::localFile(const QString &key) const {
    const Download *item = find(key);
    if (!item || item->state != Download::Done)
        return {};
    const QString file = path(*item);
    return QFile::exists(file) ? file : QString();
}

QList<Download> Offline::list() const {
    QList<Download> list = m_items.values();
    std::sort(list.begin(), list.end(), [](const Download &a, const Download &b) {
        return a.added != b.added ? a.added > b.added : a.entry.key < b.entry.key;
    });
    return list;
}

void Offline::add(const Entry &entry, const QString &seriesName) {
    if (!canDownload(entry))
        return;
    if (const Download *existing = find(entry.key)) {
        if (existing->state == Download::Failed)
            retry(entry.key);
        return;
    }
    Download item;
    item.entry = entry;
    item.seriesName = seriesName;
    // The provider's extension, so the player knows the container.
    QString extension = QFileInfo(QUrl(entry.url).path()).suffix().toLower();
    if (!QRegularExpression("^[a-z0-9]{2,4}$").match(extension).hasMatch())
        extension = "mp4";
    item.file = QString::fromLatin1(QCryptographicHash::hash(entry.key.toUtf8(), QCryptographicHash::Sha1).toHex().left(20))
                + "." + extension;
    item.added = QDateTime::currentSecsSinceEpoch();
    m_items.insert(entry.key, item);
    save();
    emit changed();
    next();
}

void Offline::retry(const QString &key) {
    auto it = m_items.find(key);
    if (it == m_items.end() || it->state != Download::Failed)
        return;
    it->state = Download::Queued;
    it->error.clear();
    m_attempts = 0;
    save();
    emit changed();
    next();
}

void Offline::remove(const QString &key) {
    const auto it = m_items.constFind(key);
    if (it == m_items.cend())
        return;
    if (m_current == key) {
        stop();
        m_current.clear();
    }
    const QString file = path(*it);
    QFile::remove(file);
    QFile::remove(file + ".part");
    m_items.remove(key);
    save();
    emit changed();
    next();
}

void Offline::next() {
    if (!m_current.isEmpty())
        return;
    // Oldest first, in the order they were asked for.
    Download *pick = nullptr;
    for (auto &item : m_items)
        if (item.state == Download::Queued && (!pick || item.added < pick->added))
            pick = &item;
    if (!pick || m_retryTimer.isActive()) {
        emit activeChanged(false);
        return;
    }
    start(*pick);
    emit activeChanged(true);
}

void Offline::start(Download &item) {
    m_current = item.entry.key;
    item.state = Download::Running;
    m_out.setFileName(path(item) + ".part");
    if (!m_out.open(QIODevice::WriteOnly | QIODevice::Append)) {
        item.state = Download::Failed;
        item.error = tr("the file can't be written: %1").arg(m_out.errorString());
        m_current.clear();
        save();
        emit changed();
        QTimer::singleShot(0, this, &Offline::next);
        return;
    }
    // Carries on from whatever an earlier attempt left.
    m_offset = m_out.size();
    item.received = m_offset;

    QNetworkRequest request{QUrl(item.entry.url)};
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("zap/0.2"));
    // Gives up after a minute without data, not after a minute overall.
    request.setTransferTimeout(60000);
    if (m_offset > 0)
        request.setRawHeader("Range", "bytes=" + QByteArray::number(m_offset) + "-");

    QNetworkReply *reply = m_manager.get(request);
    m_reply = reply;
    m_lastProgress.start();
    auto failure = std::make_shared<QString>();

    connect(reply, &QNetworkReply::metaDataChanged, this, [this, reply, failure] {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        auto it = m_items.find(m_current);
        if (reply != m_reply || it == m_items.end() || status < 200 || status >= 300)
            return;
        if (status != 206 && m_offset > 0) {
            // The server ignored the range: start over.
            m_out.resize(0);
            m_offset = 0;
            it->received = 0;
        }
        const QString range = QString::fromLatin1(reply->rawHeader("Content-Range"));
        const qint64 length = reply->header(QNetworkRequest::ContentLengthHeader).toLongLong();
        if (status == 206 && range.contains('/'))
            it->total = range.section('/', 1).toLongLong();
        else if (length > 0)
            it->total = m_offset + length;
        const qint64 left = it->total - it->received;
        if (it->total > 0 && QStorageInfo(m_directory).bytesAvailable() - SpareSpace < left) {
            *failure = tr("not enough space on this device (%1 needed)")
                           .arg(QLocale().formattedDataSize(left, 1, QLocale::DataSizeTraditionalFormat));
            reply->abort();
        }
    });
    connect(reply, &QNetworkReply::readyRead, this, [this, reply] {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        auto it = m_items.find(m_current);
        if (reply != m_reply || it == m_items.end() || status >= 300)
            return;
        it->received += m_out.write(reply->readAll());
        if (m_lastProgress.elapsed() > 500) {
            m_lastProgress.restart();
            emit progressed();
        }
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, failure] {
        reply->deleteLater();
        if (reply != m_reply)
            return;
        m_reply = nullptr;
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        auto it = m_items.find(m_current);
        if (it != m_items.end() && status >= 200 && status < 300 && reply->error() == QNetworkReply::NoError)
            it->received += m_out.write(reply->readAll());
        m_out.close();

        QString error = *failure;
        bool again = false;
        if (error.isEmpty()) {
            if (status == 416 && m_offset > 0) {
                // Asked for more than there is: the earlier attempt got it all.
            } else if (status >= 400) {
                error = tr("the server answered %1").arg(status);
            } else if (reply->error() != QNetworkReply::NoError) {
                error = reply->errorString();
                again = ++m_attempts < MaxAttempts;
            } else if (it != m_items.end() && it->received == 0) {
                error = tr("the server sent nothing");
            }
        }
        if (again) {
            // Lost the connection: wait a little, then carry on from here.
            m_current.clear();
            if (it != m_items.end()) {
                it->state = Download::Queued;
                it->error = error;
            }
            m_retryTimer.start();
        } else {
            finish(error);
        }
        save();
        emit changed();
        next();
    });
}

void Offline::finish(const QString &error) {
    auto it = m_items.find(m_current);
    m_current.clear();
    if (it == m_items.end())
        return;
    if (!error.isEmpty()) {
        it->state = Download::Failed;
        it->error = error;
        return;
    }
    const QString file = path(*it);
    QFile::remove(file);
    if (!QFile::rename(file + ".part", file)) {
        it->state = Download::Failed;
        it->error = tr("the file can't be written");
        return;
    }
    it->state = Download::Done;
    it->error.clear();
    it->total = it->received = QFileInfo(file).size();
    m_attempts = 0;
}

void Offline::stop() {
    if (m_reply) {
        QNetworkReply *reply = m_reply;
        m_reply = nullptr;
        reply->disconnect(this);
        reply->abort();
        reply->deleteLater();
    }
    m_out.close();
    if (auto it = m_items.find(m_current); it != m_items.end() && it->state == Download::Running)
        it->state = Download::Queued;
}

void Offline::load() {
    QFile file(m_directory + "/downloads.json");
    if (!file.open(QIODevice::ReadOnly))
        return;
    for (const auto &value : QJsonDocument::fromJson(file.readAll()).object().value("downloads").toArray()) {
        const QJsonObject o = value.toObject();
        Download item;
        item.entry = Entry::fromJson(o.value("entry").toObject());
        item.seriesName = o.value("seriesName").toString();
        item.file = QFileInfo(o.value("file").toString()).fileName();
        item.total = qint64(o.value("total").toDouble());
        item.added = qint64(o.value("added").toDouble());
        item.error = o.value("error").toString();
        const QString state = o.value("state").toString();
        item.state = state == "done" ? Download::Done : state == "failed" ? Download::Failed : Download::Queued;
        if (item.entry.key.isEmpty() || item.file.isEmpty())
            continue;
        if (item.state == Download::Done) {
            // Deleted behind our back: forget it.
            const QFileInfo info(path(item));
            if (!info.exists())
                continue;
            item.received = item.total = info.size();
        } else {
            item.received = QFileInfo(path(item) + ".part").size();
        }
        m_items.insert(item.entry.key, item);
    }
}

void Offline::save() {
    QJsonArray list;
    for (const auto &item : std::as_const(m_items))
        list.append(QJsonObject{{"entry", item.entry.toJson()},
                                {"seriesName", item.seriesName},
                                {"file", item.file},
                                {"state", stateName(item.state)},
                                {"total", double(item.total)},
                                {"added", double(item.added)},
                                {"error", item.error}});
    QSaveFile file(m_directory + "/downloads.json");
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(QJsonObject{{"downloads", list}}).toJson(QJsonDocument::Indented));
        file.commit();
    }
}
