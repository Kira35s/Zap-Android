#pragma once

#include <QElapsedTimer>
#include <QFile>
#include <QHash>
#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QTimer>

#include "catalog.h"

class QNetworkReply;

// A movie or an episode saved to watch without a connection.
struct Download {
    enum State { Queued, Running, Done, Failed };

    Entry entry;          // a snapshot, so it plays when the lists can't load
    QString seriesName;
    QString file;         // the file name inside the downloads directory
    State state = Queued;
    qint64 received = 0;  // bytes
    qint64 total = 0;     // 0 while the server hasn't said
    qint64 added = 0;     // seconds since the epoch
    QString error;
};

// Downloads one file at a time into a directory, keeping what's there across
// restarts: an interrupted download carries on where it stopped.
class Offline : public QObject {
    Q_OBJECT

public:
    explicit Offline(const QString &directory, QObject *parent = nullptr);
    ~Offline() override;

    void add(const Entry &entry, const QString &seriesName);
    void retry(const QString &key);
    // Cancels it if it's under way, and deletes what was downloaded.
    void remove(const QString &key);

    const Download *find(const QString &key) const;
    // The finished file's path, or an empty string.
    QString localFile(const QString &key) const;
    // Newest first.
    QList<Download> list() const;
    bool active() const { return !m_current.isEmpty(); }
    QString directory() const { return m_directory; }
    // How long to wait before trying again after a lost connection.
    void setRetryDelay(int milliseconds) { m_retryTimer.setInterval(milliseconds); }

    static bool canDownload(const Entry &entry);

signals:
    // Something was added, removed, finished or failed.
    void changed();
    // Bytes arrived; at most a couple of times a second.
    void progressed();
    void activeChanged(bool active);

private:
    void load();
    void save();
    void next();
    void start(Download &item);
    void finish(const QString &error);
    void stop();
    QString path(const Download &item) const;

    QString m_directory;
    QHash<QString, Download> m_items;
    QNetworkAccessManager m_manager;
    QPointer<QNetworkReply> m_reply;
    QString m_current;
    QFile m_out;
    qint64 m_offset = 0;
    int m_attempts = 0;
    QElapsedTimer m_lastProgress;
    QTimer m_retryTimer;
};
