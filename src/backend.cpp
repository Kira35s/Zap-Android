#include "backend.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QMap>
#include <QProcess>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUrl>
#include <QUuid>
#include <QtConcurrent>
#include <algorithm>
#include <memory>

#ifdef Q_OS_ANDROID
#include <QCoreApplication>
#include <QJniEnvironment>
#include <QJniObject>
#endif

namespace {

// Lists change rarely; guides cover a few days and are refreshed twice a day.
constexpr qint64 CatalogAge = 24 * 3600;
constexpr qint64 GuideAge = 12 * 3600;

QString xdg(const char *variable, const QString &fallback) {
    const QString value = qEnvironmentVariable(variable);
    return (value.isEmpty() ? QDir::homePath() + fallback : value) + "/zap";
}

bool writeJson(const QString &path, const QJsonObject &object, bool privateFile) {
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    if (privateFile)
        file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    file.write(QJsonDocument(object).toJson(QJsonDocument::Indented));
    if (!file.commit())
        return false;
    if (privateFile)
        QFile::setPermissions(path, QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    return true;
}

QJsonObject readJson(const QString &path) {
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? QJsonDocument::fromJson(file.readAll()).object() : QJsonObject();
}

QVariantMap programmeMap(const Programme &p) {
    return {{"start", double(p.start)}, {"stop", double(p.stop)}, {"title", p.title}, {"desc", p.desc}};
}

} // namespace

template <typename T, typename F> void Backend::watch(QFuture<T> future, F then) {
    auto *watcher = new QFutureWatcher<T>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [watcher, then] {
        then(watcher->result());
        watcher->deleteLater();
    });
    watcher->setFuture(future);
}

Backend::Backend(const QString &configDir, const QString &dataDir, const QString &cacheDir, QObject *parent)
    : QObject(parent),
      m_configDir(configDir.isEmpty() ? xdg("XDG_CONFIG_HOME", "/.config") : configDir),
      m_dataDir(dataDir.isEmpty() ? xdg("XDG_DATA_HOME", "/.local/share") : dataDir),
      m_cacheDir(cacheDir.isEmpty() ? xdg("XDG_CACHE_HOME", "/.cache") : cacheDir),
      m_entries(new EntryModel(this, this)),
      m_episodes(new EntryModel(this, this)) {
    m_now = QDateTime::currentSecsSinceEpoch();
    m_tick.setInterval(30000);
    connect(&m_tick, &QTimer::timeout, this, [this] {
        m_now = QDateTime::currentSecsSinceEpoch();
        m_entries->touch();
        m_episodes->touch();
        bump();
    });
    m_tick.start();
    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(800);
    connect(&m_saveTimer, &QTimer::timeout, this, &Backend::saveState);

    loadSources();
    loadState();
    rebuildIndex();
    rebuildCategories();
    rebuild();
    QTimer::singleShot(0, this, [this] {
        for (const auto &source : std::as_const(m_sources))
            loadSource(source, false);
    });
}

Backend::~Backend() {
    if (m_saveTimer.isActive())
        saveState();
}

// Sources and state

QString Backend::sourceDirectory(const QString &id) const { return m_cacheDir + "/sources/" + id; }

Source Backend::sourceById(const QString &id) const {
    for (const auto &source : m_sources)
        if (source.id == id)
            return source;
    return {};
}

void Backend::loadSources() {
    for (const auto &value : readJson(m_configDir + "/sources.json").value("sources").toArray()) {
        const Source source = Source::fromJson(value.toObject());
        if (!source.id.isEmpty())
            m_sources.append(source);
    }
}

bool Backend::writeSources() {
    QJsonArray list;
    for (const auto &source : std::as_const(m_sources))
        list.append(source.toJson());
    // Passwords live here, so only the user may read it.
    return writeJson(m_configDir + "/sources.json", {{"sources", list}}, true);
}

void Backend::loadState() {
    const QJsonObject state = readJson(m_dataDir + "/state.json");
    for (const auto &value : state.value("favorites").toArray())
        m_favorites.append(value.toString());
    for (const auto &value : state.value("resume").toArray()) {
        const QJsonObject o = value.toObject();
        Resume resume;
        resume.position = qint64(o.value("position").toDouble());
        resume.duration = qint64(o.value("duration").toDouble());
        resume.updated = qint64(o.value("updated").toDouble());
        resume.entry = Entry::fromJson(o.value("entry").toObject());
        if (!resume.entry.key.isEmpty())
            m_resume.insert(resume.entry.key, resume);
    }
    m_language = state.value("language").toString();
    m_audioLanguage = state.value("audioLanguage").toString();
    m_subtitleLanguage = state.value("subtitleLanguage").toString();
    if (state.contains("volume"))
        m_volume = std::clamp(state.value("volume").toDouble(), 0.0, 1.0);
}

void Backend::saveState() {
    m_saveTimer.stop();
    QJsonArray resume;
    for (const auto &r : std::as_const(m_resume))
        resume.append(QJsonObject{{"position", double(r.position)},
                                  {"duration", double(r.duration)},
                                  {"updated", double(r.updated)},
                                  {"entry", r.entry.toJson()}});
    if (!writeJson(m_dataDir + "/state.json",
                   {{"favorites", QJsonArray::fromStringList(m_favorites)}, {"resume", resume}, {"volume", m_volume}, {"language", m_language},
                    {"audioLanguage", m_audioLanguage}, {"subtitleLanguage", m_subtitleLanguage}},
                   false)) {
        m_problems << tr("Favourites and resume points couldn't be saved to %1.").arg(m_dataDir);
        emit statusChanged();
    }
}

void Backend::scheduleSave() { m_saveTimer.start(); }

QVariantList Backend::sources() const {
    QVariantList list;
    for (const auto &source : m_sources)
        list.append(source.toJson().toVariantMap());
    return list;
}

QString Backend::saveSource(const QVariantMap &values) {
    Source source;
    source.id = values.value("id").toString();
    source.name = values.value("name").toString().trimmed();
    source.type = values.value("type").toString() == "m3u" ? "m3u" : "xtream";
    source.server = values.value("server").toString().trimmed();
    source.username = values.value("username").toString().trimmed();
    source.password = values.value("password").toString();
    source.playlist = values.value("playlist").toString().trimmed();
    source.epg = values.value("epg").toString().trimmed();

    if (source.name.isEmpty())
        return tr("Give the source a name.");
    if (source.isXtream()) {
        if (source.server.isEmpty() || source.username.isEmpty() || source.password.isEmpty())
            return tr("An Xtream Codes source needs a server, a username and a password.");
        source.playlist.clear();
    } else {
        if (source.playlist.isEmpty())
            return tr("An M3U source needs a playlist address or file.");
        source.server.clear();
        source.username.clear();
        source.password.clear();
    }

    const QList<Source> before = m_sources;
    bool replaced = false;
    if (source.id.isEmpty())
        source.id = QUuid::createUuid().toString(QUuid::Id128).left(8);
    for (auto &existing : m_sources)
        if (existing.id == source.id) {
            existing = source;
            replaced = true;
        }
    if (!replaced)
        m_sources.append(source);
    if (!writeSources()) {
        m_sources = before;
        return tr("The sources couldn't be saved in %1.").arg(m_configDir);
    }

    // New details mean the cached lists may belong to another account.
    QDir(sourceDirectory(source.id)).removeRecursively();
    emit sourcesChanged();
    rebuildIndex();
    rebuildCategories();
    loadSource(source, true);
    return {};
}

void Backend::removeSource(const QString &id) {
    ++m_generations[id];
    m_sources.erase(std::remove_if(m_sources.begin(), m_sources.end(), [&](const Source &s) { return s.id == id; }),
                    m_sources.end());
    writeSources();
    m_catalogs.remove(id);
    m_guide.remove(id);
    QDir(sourceDirectory(id)).removeRecursively();
    const QString prefix = id + ':';
    m_favorites.erase(std::remove_if(m_favorites.begin(), m_favorites.end(),
                                     [&](const QString &key) { return key.startsWith(prefix); }),
                      m_favorites.end());
    m_resume.removeIf([&](QHash<QString, Resume>::iterator it) { return it.key().startsWith(prefix); });
    scheduleSave();
    if (m_series.sourceId == id)
        closeSeries();
    if (m_movie.sourceId == id)
        closeMovie();
    emit sourcesChanged();
    rebuildIndex();
    rebuildCategories();
    rebuild();
    bump();
}

// Loading

void Backend::fetchAll(const QList<QPair<QString, QString>> &files, qint64 maxAge,
                       std::function<void(const QStringList &)> done) {
    struct Pending {
        int remaining = 0;
        QStringList errors;
    };
    auto pending = std::make_shared<Pending>();
    QList<QPair<QString, QString>> needed;
    const QDateTime now = QDateTime::currentDateTime();
    for (const auto &file : files) {
        const QFileInfo info(file.second);
        if (maxAge > 0 && info.exists() && info.size() > 0 && info.lastModified().secsTo(now) < maxAge)
            continue;
        needed.append(file);
    }
    if (needed.isEmpty()) {
        QTimer::singleShot(0, this, [done] { done({}); });
        return;
    }
    pending->remaining = int(needed.size());
    for (const auto &file : std::as_const(needed))
        m_downloader.fetch(file.first, file.second, [pending, done](const QString &error) {
            if (!error.isEmpty() && !pending->errors.contains(error))
                pending->errors << error;
            if (--pending->remaining == 0)
                done(pending->errors);
        });
}

void Backend::loadSource(const Source &source, bool force) {
    const int generation = ++m_generations[source.id];
    const QString directory = sourceDirectory(source.id);
    QList<QPair<QString, QString>> files;
    if (source.isXtream()) {
        for (const auto &action : CatalogParser::xtreamActions())
            files.append({source.xtreamApi(action), directory + '/' + action + ".json"});
    } else {
        files.append({source.playlist, directory + "/playlist.m3u"});
    }

    begin(tr("Updating %1…").arg(source.name));
    fetchAll(files, force ? 0 : CatalogAge, [this, source, directory, force, generation](const QStringList &errors) {
        if (generation != m_generations.value(source.id))
            return end();
        for (const auto &error : errors)
            addProblem(source, tr("download failed (%1)").arg(error));
        watch(QtConcurrent::run([source, directory] { return CatalogParser::load(source, directory); }),
              [this, source, force, generation](Catalog catalog) {
                  if (generation == m_generations.value(source.id)) {
                      for (const auto &error : std::as_const(catalog.errors))
                          addProblem(source, error);
                      const QString hint = catalog.epgHint;
                      applyCatalog(source.id, std::move(catalog));
                      loadGuide(source, hint, force, generation);
                  }
                  end();
              });
    });
}

void Backend::loadGuide(const Source &source, const QString &hint, bool force, int generation) {
    const QString address = source.guideUrl(hint);
    if (address.isEmpty())
        return;
    const QString path = sourceDirectory(source.id) + "/guide.xml";
    begin(tr("Loading the TV guide for %1…").arg(source.name));
    fetchAll({{address, path}}, force ? 0 : GuideAge, [this, source, path, generation](const QStringList &errors) {
        if (generation != m_generations.value(source.id))
            return end();
        for (const auto &error : errors)
            addProblem(source, tr("TV guide download failed (%1)").arg(error));
        if (!QFileInfo::exists(path))
            return end();
        const qint64 now = m_now;
        watch(QtConcurrent::run([path, now] { return Xmltv::parse(path, now - 6 * 3600, now + 4 * 86400); }),
              [this, source, generation](EpgData data) {
                  if (generation == m_generations.value(source.id)) {
                      for (const auto &error : std::as_const(data.errors))
                          addProblem(source, error);
                      m_guide.set(source.id, std::move(data));
                      m_entries->touch();
                      bump();
                  }
                  end();
              });
    });
}

void Backend::applyCatalog(const QString &sourceId, Catalog catalog) {
    m_catalogs.insert(sourceId, std::move(catalog));
    rebuildIndex();
    rebuildCategories();
    rebuild();
    bump();
}

void Backend::rebuildIndex() {
    m_live.clear();
    m_movies.clear();
    m_shows.clear();
    m_index.clear();
    m_categories.clear();
    m_categoryNames.clear();
    m_categoryCounts.clear();
    for (const auto &source : std::as_const(m_sources)) {
        const auto catalog = m_catalogs.constFind(source.id);
        if (catalog == m_catalogs.cend())
            continue;
        m_live += catalog->live;
        m_movies += catalog->movies;
        m_shows += catalog->series;
        for (const auto &category : catalog->categories) {
            m_categories.append(category);
            m_categoryNames.insert(category.id, category.name);
        }
        for (const auto *list : {&catalog->live, &catalog->movies, &catalog->series})
            for (const auto &e : *list) {
                m_index.insert(e.key, e);
                ++m_categoryCounts[e.group];
            }
        for (const auto &episodes : catalog->episodes)
            for (const auto &e : episodes)
                m_index.insert(e.key, e);
    }
    for (const auto &e : std::as_const(m_seriesEpisodes))
        m_index.insert(e.key, e);
}

QString Backend::categoryName(const QString &id) const {
    QString name = m_categoryNames.value(id);
    if (name.isEmpty())
        name = tr("Other");
    if (m_sources.size() > 1)
        name = sourceById(id.section('|', 0, 0)).name + " · " + name;
    return name;
}

void Backend::rebuildCategories() {
    QVariantList list;
    auto add = [&](const QString &id, const QString &name, qsizetype count) {
        list.append(QVariantMap{{"id", id}, {"name", name}, {"count", int(count)}});
    };
    auto addKind = [&](Entry::Kind kind) {
        for (const auto &category : std::as_const(m_categories))
            if (category.kind == kind && m_categoryCounts.value(category.id) > 0)
                add(category.id, categoryName(category.id), m_categoryCounts.value(category.id));
    };
    if (m_section == "live" || m_section == "guide") {
        add({}, tr("All channels"), m_live.size());
        addKind(Entry::Live);
    } else if (m_section == "movies") {
        add({}, tr("All movies"), m_movies.size());
        addKind(Entry::Movie);
    } else if (m_section == "series") {
        add({}, tr("All series"), m_shows.size());
        addKind(Entry::Series);
    } else if (m_section == "favorites") {
        QHash<int, int> counts;
        int total = 0;
        for (const auto &key : std::as_const(m_favorites)) {
            const auto it = m_index.constFind(key);
            if (it != m_index.cend()) {
                ++counts[it->kind];
                ++total;
            }
        }
        add({}, tr("All favourites"), total);
        add("live", tr("Channels"), counts.value(Entry::Live));
        add("movie", tr("Movies"), counts.value(Entry::Movie));
        add("series", tr("Series"), counts.value(Entry::Series));
    }

    bool found = m_category.isEmpty();
    for (const auto &item : std::as_const(list))
        found = found || item.toMap().value("id").toString() == m_category;
    if (!found) {
        m_category.clear();
        emit categoryChanged();
    }
    m_categoryList = list;
    emit categoriesChanged();
}

void Backend::rebuild() {
    QVector<Entry> list;
    auto inCategory = [&](const Entry &e) { return m_category.isEmpty() || e.group == m_category; };
    auto addFrom = [&](const QVector<Entry> &source) {
        for (const auto &e : source)
            if (inCategory(e))
                list.append(e);
    };

    if (m_section == "live" || m_section == "guide") {
        addFrom(m_live);
    } else if (m_section == "movies") {
        addFrom(m_movies);
    } else if (m_section == "series") {
        addFrom(m_shows);
    } else if (m_section == "favorites") {
        for (const auto &key : std::as_const(m_favorites)) {
            const auto it = m_index.constFind(key);
            if (it != m_index.cend() && (m_category.isEmpty() || Entry::kindName(it->kind) == m_category))
                list.append(*it);
        }
    } else if (m_section == "continue") {
        QList<Resume> resumes = m_resume.values();
        std::sort(resumes.begin(), resumes.end(), [](const Resume &a, const Resume &b) { return a.updated > b.updated; });
        for (const auto &r : std::as_const(resumes))
            list.append(m_index.value(r.entry.key, r.entry));
    } else if (m_section == "search") {
        const QString query = foldText(m_query.trimmed());
        if (query.size() >= 2) {
            // Names that start with the query come first.
            QVector<Entry> starts, contains;
            for (const auto *source : {&m_live, &m_movies, &m_shows})
                for (const auto &e : *source) {
                    if (starts.size() + contains.size() >= 500)
                        break;
                    if (e.search.startsWith(query))
                        starts.append(e);
                    else if (e.search.contains(query))
                        contains.append(e);
                }
            list = starts + contains;
        }
    }
    m_entries->setEntries(list);
}

void Backend::bump() {
    ++m_revision;
    emit revisionChanged();
}

void Backend::begin(const QString &status) {
    ++m_busy;
    m_status = status;
    emit statusChanged();
}

void Backend::end() {
    if (--m_busy <= 0) {
        m_busy = 0;
        m_status.clear();
    }
    emit statusChanged();
}

void Backend::addProblem(const Source &source, const QString &problem) {
    QString text = tr("%1: %2").arg(source.name, problem);
    // Error messages can quote the address, and Xtream addresses carry the password.
    if (!source.password.isEmpty()) {
        text.replace(source.password, "•••");
        text.replace(QString::fromUtf8(QUrl::toPercentEncoding(source.password)), "•••");
    }
    if (m_problems.contains(text))
        return;
    m_problems << text;
    while (m_problems.size() > 5)
        m_problems.removeFirst();
    emit statusChanged();
}

void Backend::retranslate() {
    rebuildCategories();
    m_entries->touch();
    bump();
}

void Backend::dismissProblems() {
    m_problems.clear();
    emit statusChanged();
}

void Backend::refresh() {
    for (const auto &source : std::as_const(m_sources))
        loadSource(source, true);
}

// Navigation

void Backend::setSection(const QString &section) {
    if (section == m_section)
        return;
    m_categoryBySection.insert(m_section, m_category);
    m_section = section;
    m_category = m_categoryBySection.value(section);
    closeSeries();
    closeMovie();
    rebuildCategories();
    rebuild();
    emit sectionChanged();
    emit categoryChanged();
}

void Backend::setCategory(const QString &category) {
    if (category == m_category)
        return;
    m_category = category;
    rebuild();
    emit categoryChanged();
}

void Backend::setQuery(const QString &query) {
    if (query == m_query)
        return;
    m_query = query;
    if (m_section == "search")
        rebuild();
    emit queryChanged();
}

void Backend::setLanguage(const QString &language) {
    if (language == m_language)
        return;
    m_language = language;
    scheduleSave();
    emit languageChanged();
}

void Backend::setAudioLanguage(const QString &language) {
    if (language == m_audioLanguage)
        return;
    m_audioLanguage = language;
    scheduleSave();
    emit tracksPreferenceChanged();
}

void Backend::setSubtitleLanguage(const QString &language) {
    if (language == m_subtitleLanguage)
        return;
    m_subtitleLanguage = language;
    scheduleSave();
    emit tracksPreferenceChanged();
}

QVariantMap Backend::describeTrack(const QMediaMetaData &track, int index) const {
    const auto language = track.value(QMediaMetaData::Language).value<QLocale::Language>();
    const QString title = track.stringValue(QMediaMetaData::Title).trimmed();
    QString code, name;
    if (language != QLocale::AnyLanguage && language != QLocale::C) {
        code = QLocale::languageToCode(language, QLocale::ISO639Part1);
        if (code.isEmpty())
            code = QLocale::languageToCode(language);
        // Each language in its own words, as players usually list them; Qt
        // calls English "American English" after its default territory.
        name = language == QLocale::English ? QStringLiteral("English") : QLocale(language).nativeLanguageName();
        if (name.isEmpty())
            name = QLocale::languageToString(language);
        if (!name.isEmpty())
            name[0] = name[0].toUpper();
    }
    QString label = name;
    if (!title.isEmpty() && title.compare(name, Qt::CaseInsensitive) != 0)
        label = label.isEmpty() ? title : label + " — " + title;
    if (label.isEmpty())
        label = tr("Track %1").arg(index + 1);
    return {{"language", code}, {"label", label}};
}

void Backend::setVolume(double volume) {
    volume = std::clamp(volume, 0.0, 1.0);
    if (qFuzzyCompare(volume, m_volume))
        return;
    m_volume = volume;
    scheduleSave();
    emit volumeChanged();
}

// Entries

Entry Backend::lookup(const QString &key) const {
    const auto it = m_index.constFind(key);
    if (it != m_index.cend())
        return *it;
    return m_resume.value(key).entry;
}

QVariantMap Backend::entry(const QString &key) const {
    const Entry e = lookup(key);
    if (e.key.isEmpty())
        return {};
    QVariantMap map = EntryModel::toMap(e);
    map.insert("groupName", e.group.isEmpty() ? QString() : categoryName(e.group));
    map.insert("favorite", isFavorite(key));
    map.insert("progress", progress(key));
    map.insert("position", double(m_resume.value(key).position));
    if (e.kind == Entry::Episode)
        map.insert("seriesName", lookup(e.seriesKey).name);
    if (e.kind == Entry::Live) {
        const NowNext guide = m_guide.at(e, m_now);
        if (guide.now) {
            map.insert("nowTitle", guide.now->title);
            map.insert("nowDesc", guide.now->desc);
            map.insert("nowStart", double(guide.now->start));
            map.insert("nowStop", double(guide.now->stop));
        }
        if (guide.next) {
            map.insert("nextTitle", guide.next->title);
            map.insert("nextStart", double(guide.next->start));
        }
    }
    return map;
}

QVariantList Backend::programmes(const QString &key, double from, double to) const {
    QVariantList list;
    for (const auto &p : m_guide.between(lookup(key), qint64(from), qint64(to)))
        list.append(programmeMap(p));
    return list;
}

QVariantMap Backend::programmeAt(const QString &key, double time) const {
    const NowNext found = m_guide.at(lookup(key), qint64(time));
    return found.now ? programmeMap(*found.now) : QVariantMap();
}

void Backend::toggleFavorite(const QString &key) {
    if (lookup(key).key.isEmpty())
        return;
    if (!m_favorites.removeOne(key))
        m_favorites.append(key);
    scheduleSave();
    if (m_section == "favorites") {
        rebuildCategories();
        rebuild();
    } else {
        m_entries->touch();
    }
    m_episodes->touch();
    bump();
}

double Backend::progress(const QString &key) const {
    const auto it = m_resume.constFind(key);
    return it != m_resume.cend() && it->duration > 0 ? double(it->position) / double(it->duration) : 0.0;
}

double Backend::resumePosition(const QString &key) const { return double(m_resume.value(key).position); }

void Backend::savePosition(const QString &key, double position, double duration) {
    const Entry e = lookup(key);
    if (e.key.isEmpty() || e.kind == Entry::Live)
        return;
    if (duration > 0 && position >= duration * 0.95) {
        // Finished: it leaves "Continue watching".
        if (!m_resume.remove(key))
            return;
    } else if (position >= 30000) {
        Resume &r = m_resume[key];
        r.position = qint64(position);
        r.duration = qint64(duration);
        r.updated = QDateTime::currentSecsSinceEpoch();
        r.entry = e;
    } else {
        return;
    }
    scheduleSave();
    m_entries->touch();
    m_episodes->touch();
    bump();
}

void Backend::forget(const QString &key) {
    if (!m_resume.remove(key))
        return;
    scheduleSave();
    if (m_section == "continue")
        rebuild();
    bump();
}

void Backend::played(const QString &key) {
    const Entry e = lookup(key);
    if (e.kind != Entry::Live)
        return;
    // Channel up and down walk the list the channel was picked from.
    if (m_entries->indexOf(key) >= 0) {
        m_zapList.clear();
        for (const auto &item : m_entries->entries())
            if (item.kind == Entry::Live)
                m_zapList << item.key;
    } else if (!m_zapList.contains(key)) {
        m_zapList.clear();
        for (const auto &item : std::as_const(m_live))
            m_zapList << item.key;
    }
}

QString Backend::neighbor(const QString &key, int delta) const {
    const qsizetype index = m_zapList.indexOf(key);
    if (index < 0 || m_zapList.isEmpty())
        return {};
    const qsizetype size = m_zapList.size();
    return m_zapList.at(((index + delta) % size + size) % size);
}

QString Backend::nextEpisode(const QString &key) const {
    const Entry e = lookup(key);
    if (e.kind != Entry::Episode)
        return {};
    QVector<Entry> episodes = m_seriesEpisodes;
    if (episodes.isEmpty() || episodes.first().seriesKey != e.seriesKey)
        episodes = m_catalogs.value(e.sourceId).episodes.value(e.seriesKey);
    for (qsizetype i = 0; i + 1 < episodes.size(); ++i)
        if (episodes.at(i).key == key)
            return episodes.at(i + 1).key;
    return {};
}

bool Backend::openExternally(const QString &key, double position) {
    const Entry e = lookup(key);
    if (e.url.isEmpty())
        return false;
#ifdef Q_OS_ANDROID
    // Offers the stream to whichever video player is installed (VLC, MX Player…).
    Q_UNUSED(position)
    const QJniObject uri = QJniObject::callStaticObjectMethod(
        "android/net/Uri", "parse", "(Ljava/lang/String;)Landroid/net/Uri;",
        QJniObject::fromString(e.url).object<jstring>());
    QJniObject intent("android/content/Intent", "(Ljava/lang/String;)V",
                      QJniObject::fromString("android.intent.action.VIEW").object<jstring>());
    intent.callObjectMethod("setDataAndType", "(Landroid/net/Uri;Ljava/lang/String;)Landroid/content/Intent;",
                            uri.object(), QJniObject::fromString("video/*").object<jstring>());
    intent.callObjectMethod("putExtra", "(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;",
                            QJniObject::fromString("title").object<jstring>(),
                            QJniObject::fromString(e.name).object<jstring>());
    const QJniObject chooser = QJniObject::callStaticObjectMethod(
        "android/content/Intent", "createChooser",
        "(Landroid/content/Intent;Ljava/lang/CharSequence;)Landroid/content/Intent;",
        intent.object(), QJniObject::fromString(e.name).object<jstring>());
    QJniObject context = QNativeInterface::QAndroidApplication::context();
    context.callMethod<void>("startActivity", "(Landroid/content/Intent;)V", chooser.object());
    QJniEnvironment env;
    if (env.checkAndClearExceptions()) {
        m_problems << tr("No other app on this device can play this stream.");
        emit statusChanged();
        return false;
    }
    return true;
#else
    const QString mpv = QStandardPaths::findExecutable("mpv");
    if (mpv.isEmpty()) {
        m_problems << tr("mpv isn't installed. Install it with: omarchy-pkg-add mpv");
        emit statusChanged();
        return false;
    }
    QStringList arguments{"--force-media-title=" + e.name};
    if (position > 0)
        arguments << "--start=" + QString::number(qint64(position / 1000));
    arguments << e.url;
    return QProcess::startDetached(mpv, arguments);
#endif
}

void Backend::keepScreenOn(bool on) {
#ifdef Q_OS_ANDROID
    QNativeInterface::QAndroidApplication::runOnAndroidMainThread([on] {
        const QJniObject activity = QNativeInterface::QAndroidApplication::context();
        const QJniObject window = activity.callObjectMethod("getWindow", "()Landroid/view/Window;");
        constexpr jint FLAG_KEEP_SCREEN_ON = 0x80;
        if (on)
            window.callMethod<void>("addFlags", "(I)V", FLAG_KEEP_SCREEN_ON);
        else
            window.callMethod<void>("clearFlags", "(I)V", FLAG_KEEP_SCREEN_ON);
    });
#else
    Q_UNUSED(on)
#endif
}

// Series

void Backend::openSeries(const QString &key) {
    const Entry series = lookup(key);
    if (series.kind != Entry::Series)
        return;
    closeMovie();
    m_series = series;
    m_seriesDetails = Details();
    m_seriesEpisodes.clear();
    m_season = 0;
    m_episodes->setEntries({});

    const Source source = sourceById(series.sourceId);
    if (!source.isXtream()) {
        m_seriesLoading = false;
        setEpisodes(m_catalogs.value(series.sourceId).episodes.value(key));
        return;
    }
    m_seriesLoading = true;
    emit seriesChanged();
    const QString path = sourceDirectory(source.id) + "/series/" + series.id + ".json";
    fetchAll({{source.xtreamApi("get_series_info", "&series_id=" + series.id), path}}, CatalogAge,
             [this, source, key, path](const QStringList &errors) {
                 if (m_series.key != key)
                     return;
                 for (const auto &error : errors)
                     addProblem(source, tr("download failed (%1)").arg(error));
                 QFile file(path);
                 const QByteArray data = file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
                 const auto episodes = CatalogParser::parseXtreamSeriesInfo(source, m_series, data, &m_seriesDetails);
                 if (m_series.plot.isEmpty())
                     m_series.plot = m_seriesDetails.plot;
                 m_seriesLoading = false;
                 setEpisodes(episodes);
             });
}

void Backend::setEpisodes(const QVector<Entry> &episodes) {
    m_seriesEpisodes = episodes;
    for (const auto &e : episodes)
        m_index.insert(e.key, e);
    // Open on the season watched last, or the first one.
    int season = episodes.isEmpty() ? 0 : episodes.first().season;
    qint64 latest = 0;
    for (const auto &e : episodes) {
        const auto r = m_resume.constFind(e.key);
        if (r != m_resume.cend() && r->updated > latest) {
            latest = r->updated;
            season = e.season;
        }
    }
    m_season = -1;
    setSeason(season);
}

void Backend::setSeason(int season) {
    if (season == m_season)
        return;
    m_season = season;
    QVector<Entry> list;
    for (const auto &e : std::as_const(m_seriesEpisodes))
        if (e.season == season)
            list.append(e);
    m_episodes->setEntries(list);
    emit seriesChanged();
}

void Backend::closeSeries() {
    if (!seriesOpen())
        return;
    m_series = Entry();
    m_seriesDetails = Details();
    m_seriesEpisodes.clear();
    m_seriesLoading = false;
    m_season = 0;
    m_episodes->setEntries({});
    emit seriesChanged();
}

QVariantMap Backend::series() const {
    if (!seriesOpen())
        return {};
    QVariantMap map = m_seriesDetails.toMap();
    map.insert(EntryModel::toMap(m_series));
    map.insert("favorite", isFavorite(m_series.key));
    map.insert("groupName", m_series.group.isEmpty() ? QString() : categoryName(m_series.group));
    if (m_series.rating.isEmpty())
        map.insert("rating", m_seriesDetails.rating);
    if (m_series.logo.isEmpty())
        map.insert("logo", m_seriesDetails.cover);
    return map;
}

// Movies

void Backend::openMovie(const QString &key) {
    const Entry movie = lookup(key);
    if (movie.kind != Entry::Movie)
        return;
    m_movie = movie;
    m_movieDetails = Details();
    const Source source = sourceById(movie.sourceId);
    m_movieLoading = source.isXtream() && !movie.id.isEmpty();
    emit movieChanged();
    if (!m_movieLoading)
        return;
    const QString path = sourceDirectory(source.id) + "/movies/" + movie.id + ".json";
    fetchAll({{source.xtreamApi("get_vod_info", "&vod_id=" + movie.id), path}}, CatalogAge,
             [this, source, key, path](const QStringList &errors) {
                 if (m_movie.key != key)
                     return;
                 for (const auto &error : errors)
                     addProblem(source, tr("download failed (%1)").arg(error));
                 QFile file(path);
                 m_movieDetails = CatalogParser::parseXtreamVodInfo(file.open(QIODevice::ReadOnly) ? file.readAll()
                                                                                                  : QByteArray());
                 m_movieLoading = false;
                 emit movieChanged();
             });
}

void Backend::closeMovie() {
    if (!movieOpen())
        return;
    m_movie = Entry();
    m_movieDetails = Details();
    m_movieLoading = false;
    emit movieChanged();
}

QVariantMap Backend::movie() const {
    if (!movieOpen())
        return {};
    QVariantMap map = m_movieDetails.toMap();
    map.insert(EntryModel::toMap(m_movie));
    map.insert("plot", m_movieDetails.plot.isEmpty() ? m_movie.plot : m_movieDetails.plot);
    map.insert("favorite", isFavorite(m_movie.key));
    map.insert("position", double(m_resume.value(m_movie.key).position));
    map.insert("progress", progress(m_movie.key));
    map.insert("groupName", m_movie.group.isEmpty() ? QString() : categoryName(m_movie.group));
    if (m_movie.year.isEmpty())
        map.insert("year", m_movieDetails.released.left(4));
    if (m_movie.rating.isEmpty())
        map.insert("rating", m_movieDetails.rating);
    if (m_movie.logo.isEmpty())
        map.insert("logo", m_movieDetails.cover);
    return map;
}

QVariantList Backend::seasons() const {
    QMap<int, int> counts;
    for (const auto &e : m_seriesEpisodes)
        ++counts[e.season];
    QVariantList list;
    for (auto it = counts.cbegin(); it != counts.cend(); ++it)
        list.append(QVariantMap{{"season", it.key()}, {"count", it.value()}});
    return list;
}
