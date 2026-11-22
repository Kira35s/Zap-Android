#pragma once

#include <QFuture>
#include <QMediaMetaData>
#include <QHash>
#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QVariant>

#include "catalog.h"
#include "downloader.h"
#include "entrymodel.h"
#include "guide.h"

struct Resume {
    qint64 position = 0; // milliseconds
    qint64 duration = 0;
    qint64 updated = 0;  // seconds since the epoch
    Entry entry;         // a snapshot, so "Continue watching" works before the lists load
};

// The app's state: sources and their cached lists, the programme guide, what
// the window is showing, favourites and resume points.
class Backend : public QObject, public EntryContext {
    Q_OBJECT
    Q_PROPERTY(QString section READ section WRITE setSection NOTIFY sectionChanged)
    Q_PROPERTY(QVariantList categories READ categories NOTIFY categoriesChanged)
    Q_PROPERTY(QString category READ category WRITE setCategory NOTIFY categoryChanged)
    Q_PROPERTY(QString query READ query WRITE setQuery NOTIFY queryChanged)
    Q_PROPERTY(EntryModel *entries READ entries CONSTANT)
    Q_PROPERTY(EntryModel *episodes READ episodes CONSTANT)
    Q_PROPERTY(bool seriesOpen READ seriesOpen NOTIFY seriesChanged)
    Q_PROPERTY(bool seriesLoading READ seriesLoading NOTIFY seriesChanged)
    Q_PROPERTY(QVariantMap series READ series NOTIFY seriesChanged)
    Q_PROPERTY(QVariantList seasons READ seasons NOTIFY seriesChanged)
    Q_PROPERTY(int season READ season WRITE setSeason NOTIFY seriesChanged)
    Q_PROPERTY(bool movieOpen READ movieOpen NOTIFY movieChanged)
    Q_PROPERTY(bool movieLoading READ movieLoading NOTIFY movieChanged)
    Q_PROPERTY(QVariantMap movie READ movie NOTIFY movieChanged)
    Q_PROPERTY(QString audioLanguage READ audioLanguage WRITE setAudioLanguage NOTIFY tracksPreferenceChanged)
    Q_PROPERTY(QString subtitleLanguage READ subtitleLanguage WRITE setSubtitleLanguage NOTIFY tracksPreferenceChanged)
    Q_PROPERTY(QVariantList sources READ sources NOTIFY sourcesChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY statusChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QStringList problems READ problems NOTIFY statusChanged)
    Q_PROPERTY(double now READ nowValue NOTIFY revisionChanged)
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)
    Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY languageChanged)

public:
    explicit Backend(const QString &configDir = {}, const QString &dataDir = {}, const QString &cacheDir = {},
                     QObject *parent = nullptr);
    ~Backend() override;

    QString section() const { return m_section; }
    void setSection(const QString &section);
    QVariantList categories() const { return m_categoryList; }
    QString category() const { return m_category; }
    void setCategory(const QString &category);
    QString query() const { return m_query; }
    void setQuery(const QString &query);
    EntryModel *entries() const { return m_entries; }
    EntryModel *episodes() const { return m_episodes; }
    bool seriesOpen() const { return !m_series.key.isEmpty(); }
    bool seriesLoading() const { return m_seriesLoading; }
    QVariantMap series() const;
    QVariantList seasons() const;
    int season() const { return m_season; }
    void setSeason(int season);
    bool movieOpen() const { return !m_movie.key.isEmpty(); }
    bool movieLoading() const { return m_movieLoading; }
    QVariantMap movie() const;
    // The languages last picked in the player, tried first on whatever plays
    // next; an empty subtitle language means subtitles off.
    QString audioLanguage() const { return m_audioLanguage; }
    void setAudioLanguage(const QString &language);
    QString subtitleLanguage() const { return m_subtitleLanguage; }
    void setSubtitleLanguage(const QString &language);
    QVariantList sources() const;
    bool busy() const { return m_busy > 0; }
    QString status() const { return m_status; }
    QStringList problems() const { return m_problems; }
    double nowValue() const { return double(m_now); }
    int revision() const { return m_revision; }
    double volume() const { return m_volume; }
    void setVolume(double volume);
    // Zap's own language; empty follows Omarchy. Omarchy's setting is never touched.
    QString language() const { return m_language; }
    void setLanguage(const QString &language);

    Q_INVOKABLE QVariantMap entry(const QString &key) const;
    Q_INVOKABLE QVariantList programmes(const QString &key, double from, double to) const;
    Q_INVOKABLE QVariantMap programmeAt(const QString &key, double time) const;
    Q_INVOKABLE void toggleFavorite(const QString &key);
    Q_INVOKABLE void openSeries(const QString &key);
    Q_INVOKABLE void closeSeries();
    Q_INVOKABLE void openMovie(const QString &key);
    Q_INVOKABLE void closeMovie();
    // A player track's language code and a name to show for it.
    Q_INVOKABLE QVariantMap describeTrack(const QMediaMetaData &track, int index) const;
    Q_INVOKABLE double resumePosition(const QString &key) const;
    Q_INVOKABLE void savePosition(const QString &key, double position, double duration);
    Q_INVOKABLE void forget(const QString &key);
    Q_INVOKABLE void played(const QString &key);
    Q_INVOKABLE QString neighbor(const QString &key, int delta) const;
    Q_INVOKABLE QString nextEpisode(const QString &key) const;
    Q_INVOKABLE bool openExternally(const QString &key, double position = 0);
    // Android only: stops the screen going to sleep while a video plays.
    Q_INVOKABLE void keepScreenOn(bool on);
    Q_INVOKABLE void refresh();
    Q_INVOKABLE QString saveSource(const QVariantMap &values);
    Q_INVOKABLE void removeSource(const QString &id);
    Q_INVOKABLE void dismissProblems();
    // Category names like "All channels" come from C++, so a language switch rebuilds them.
    void retranslate();

    // EntryContext
    qint64 now() const override { return m_now; }
    bool isFavorite(const QString &key) const override { return m_favorites.contains(key); }
    double progress(const QString &key) const override;
    NowNext nowNext(const Entry &entry) const override { return m_guide.at(entry, m_now); }
    QString categoryName(const QString &id) const override;
    QString seriesName(const Entry &episode) const override { return lookup(episode.seriesKey).name; }

signals:
    void sectionChanged();
    void categoriesChanged();
    void categoryChanged();
    void queryChanged();
    void seriesChanged();
    void movieChanged();
    void tracksPreferenceChanged();
    void sourcesChanged();
    void statusChanged();
    void revisionChanged();
    void volumeChanged();
    void languageChanged();

private:
    void loadSources();
    bool writeSources();
    void loadState();
    void saveState();
    void scheduleSave();
    void loadSource(const Source &source, bool force);
    void loadGuide(const Source &source, const QString &hint, bool force, int generation);
    void applyCatalog(const QString &sourceId, Catalog catalog);
    void rebuildIndex();
    void rebuildCategories();
    void rebuild();
    void setEpisodes(const QVector<Entry> &episodes);
    void bump();
    void begin(const QString &status);
    void end();
    void addProblem(const Source &source, const QString &problem);
    Entry lookup(const QString &key) const;
    Source sourceById(const QString &id) const;
    QString sourceDirectory(const QString &id) const;
    // Downloads each (address, path) that's missing or older than maxAge
    // seconds, then calls back with whatever went wrong.
    void fetchAll(const QList<QPair<QString, QString>> &files, qint64 maxAge,
                  std::function<void(const QStringList &)> done);
    template <typename T, typename F> void watch(QFuture<T> future, F then);

    QString m_configDir, m_dataDir, m_cacheDir;
    QList<Source> m_sources;
    QHash<QString, Catalog> m_catalogs;
    QHash<QString, int> m_generations;
    QVector<Entry> m_live, m_movies, m_shows;
    QHash<QString, Entry> m_index;
    QHash<QString, QString> m_categoryNames;
    QHash<QString, int> m_categoryCounts;
    QVector<Category> m_categories;
    Guide m_guide;
    Downloader m_downloader;

    QString m_section = "live";
    QString m_category;
    QHash<QString, QString> m_categoryBySection;
    QString m_query;
    QVariantList m_categoryList;
    EntryModel *m_entries;
    EntryModel *m_episodes;

    Entry m_series;
    QVector<Entry> m_seriesEpisodes;
    int m_season = 0;
    bool m_seriesLoading = false;
    Details m_seriesDetails;

    Entry m_movie;
    Details m_movieDetails;
    bool m_movieLoading = false;
    QString m_audioLanguage;
    QString m_subtitleLanguage;

    QStringList m_favorites;
    QHash<QString, Resume> m_resume;
    QStringList m_zapList;
    double m_volume = 0.8;
    QString m_language;

    int m_busy = 0;
    QString m_status;
    QStringList m_problems;
    qint64 m_now = 0;
    int m_revision = 0;
    QTimer m_tick;
    QTimer m_saveTimer;
};
