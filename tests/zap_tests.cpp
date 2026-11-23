#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QtTest>
#include <zlib.h>

#include "backend.h"
#include "catalog.h"
#include "guide.h"
#include "offline.h"
#include "theme.h"
#include "translator.h"

namespace {

QByteArray gzip(const QByteArray &data) {
    z_stream stream{};
    deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 16 + MAX_WBITS, 8, Z_DEFAULT_STRATEGY);
    QByteArray out(int(deflateBound(&stream, uLong(data.size()))), Qt::Uninitialized);
    stream.next_in = reinterpret_cast<Bytef *>(const_cast<char *>(data.data()));
    stream.avail_in = uInt(data.size());
    stream.next_out = reinterpret_cast<Bytef *>(out.data());
    stream.avail_out = uInt(out.size());
    deflate(&stream, Z_FINISH);
    out.resize(int(stream.total_out));
    deflateEnd(&stream);
    return out;
}

QString xmltvTime(qint64 seconds) {
    // Written an hour ahead with a +0100 offset, as French guides are.
    return QDateTime::fromSecsSinceEpoch(seconds + 3600, QTimeZone::UTC).toString("yyyyMMddHHmmss") + " +0100";
}

QByteArray guideXml(qint64 now) {
    QByteArray xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<tv>\n"
                     "<channel id=\"one.fr\"><display-name>Chaîne Une</display-name></channel>\n"
                     "<channel id=\"two.fr\"><display-name>Deux</display-name></channel>\n";
    auto programme = [&](const char *channel, qint64 start, qint64 stop, const char *title) {
        xml += "<programme start=\"" + xmltvTime(start).toUtf8() + "\" stop=\"" + xmltvTime(stop).toUtf8() +
               "\" channel=\"" + channel + "\"><title lang=\"fr\">" + title + "</title><desc>About " + title +
               "</desc></programme>\n";
    };
    programme("one.fr", now - 1800, now + 1800, "News");
    programme("one.fr", now + 1800, now + 5400, "Film");
    programme("one.fr", now - 30 * 86400, now - 30 * 86400 + 3600, "Long ago");
    programme("two.fr", now - 600, now + 600, "Weather");
    return xml + "</tv>\n";
}

const char *playlist =
    "#EXTM3U url-tvg=\"http://example.com/guide.xml.gz\"\n"
    "#EXTINF:-1 tvg-id=\"one.fr\" tvg-logo=\"http://logo/1.png\" group-title=\"TNT\",Chaîne Une HD\n"
    "http://example.com/live/u/p/1.ts\n"
    "#EXTINF:-1 group-title=\"TNT\",FR: Deux, la chaîne\n"
    "http://example.com/live/u/p/2.ts\n"
    "#EXTINF:-1 group-title=\"Films\",Le Film (2020)\n"
    "http://example.com/movie/u/p/10.mkv\n"
    "#EXTINF:-1 group-title=\"Séries\",Ma Série S01 E02\n"
    "http://example.com/series/u/p/20.mp4\n"
    "#EXTINF:-1 group-title=\"Séries\",Ma Série S01E01\n"
    "http://example.com/series/u/p/21.mp4\n";

void writeFile(const QString &path, const QByteArray &contents) {
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write(contents);
}

} // namespace

class ZapTests : public QObject {
    Q_OBJECT

private slots:
    void m3uSortsChannelsMoviesAndSeries()
    {
        const Catalog c = CatalogParser::parseM3u(playlist, "src");
        QCOMPARE(c.epgHint, QString("http://example.com/guide.xml.gz"));
        QCOMPARE(c.live.size(), 2);
        QCOMPARE(c.live[0].name, QString("Chaîne Une HD"));
        QCOMPARE(c.live[0].epgId, QString("one.fr"));
        QCOMPARE(c.live[0].logo, QString("http://logo/1.png"));
        QCOMPARE(c.live[1].name, QString("FR: Deux, la chaîne"));
        QCOMPARE(c.live[1].number, 2);
        QCOMPARE(c.movies.size(), 1);
        QCOMPARE(c.series.size(), 1);
        QCOMPARE(c.series[0].name, QString("Ma Série"));
        const auto episodes = c.episodes.value(c.series[0].key);
        QCOMPARE(episodes.size(), 2);
        QCOMPARE(episodes[0].episode, 1); // sorted
        QCOMPARE(episodes[1].season, 1);
        QCOMPARE(c.categories.size(), 3);
        // Keys don't change between loads, so favourites survive a refresh.
        QCOMPARE(CatalogParser::parseM3u(playlist, "src").live[0].key, c.live[0].key);
    }

    void m3uThatIsNotOneSaysSo()
    {
        const Catalog c = CatalogParser::parseM3u("<html>Not found</html>", "src");
        QVERIFY(c.live.isEmpty());
        QCOMPARE(c.errors.size(), 1);
    }

    void xtreamBuildsStreamAddresses()
    {
        Source s;
        s.id = "x";
        s.server = "http://host:8080/get.php?username=a&password=b";
        s.username = "user name";
        s.password = "p@ss/word";
        QCOMPARE(s.baseUrl(), QString("http://host:8080"));
        QCOMPARE(s.xtreamStream("live", "7", "ts"), QString("http://host:8080/live/user%20name/p%40ss%2Fword/7.ts"));
        QVERIFY(s.guideUrl().startsWith("http://host:8080/xmltv.php?username=user%20name"));
        s.epg = "http://other/guide.xml";
        QCOMPARE(s.guideUrl(), QString("http://other/guide.xml"));

        QHash<QString, QByteArray> files{
            {"get_live_categories", R"([{"category_id":"1","category_name":"News"}])"},
            {"get_live_streams", R"([{"num":3,"name":"Info","stream_id":42,"epg_channel_id":"info.fr","category_id":"1","stream_icon":"i.png"}])"},
            {"get_vod_streams", R"([{"name":"Movie","stream_id":"9","category_id":null,"container_extension":"mkv","rating":"7.5"}])"},
            {"get_series", R"([{"series_id":5,"name":"Show","cover":"c.png","releaseDate":"2019-01-01"}])"}};
        const Catalog c = CatalogParser::parseXtream(s, files);
        QCOMPARE(c.live.size(), 1);
        QCOMPARE(c.live[0].number, 3);
        QCOMPARE(c.live[0].key, QString("x:l:42"));
        QCOMPARE(c.live[0].epgId, QString("info.fr"));
        QVERIFY(c.live[0].url.endsWith("/live/user%20name/p%40ss%2Fword/42.ts"));
        QVERIFY(c.movies[0].url.endsWith("/9.mkv"));
        QCOMPARE(c.series[0].year, QString("2019"));
        QVERIFY(c.errors.isEmpty());
    }

    void xtreamRefusedLoginIsReported()
    {
        Source s;
        s.id = "x";
        const Catalog c = CatalogParser::parseXtream(s, {{"get_live_streams", R"({"user_info":{"auth":0}})"}});
        QCOMPARE(c.errors.size(), 1);
    }

    void xtreamSeriesInfoListsEpisodes()
    {
        Source s;
        s.id = "x";
        s.server = "h";
        Entry show;
        show.key = "x:s:5";
        show.name = "Show";
        const QByteArray json = R"({"info":{"plot":"A plot","cast":"Ann, Bob,Ann","genre":"Drama","backdrop_path":["b/1.jpg"],"episode_run_time":"42"},"episodes":{"2":[{"id":"22","episode_num":1,"season":2,"title":"Show - S02E01 - Return","container_extension":"mp4"}],
                                    "1":[{"id":"12","episode_num":"2","title":"Show - S01E02","container_extension":"mkv","info":{"duration_secs":1500}},
                                         {"id":"11","episode_num":1,"title":"Pilot","container_extension":"mkv"}]}})";
        Details details;
        const auto episodes = CatalogParser::parseXtreamSeriesInfo(s, show, json, &details);
        QCOMPARE(details.plot, QString("A plot"));
        QCOMPARE(details.genre, QString("Drama"));
        QCOMPARE(details.backdrop, QString("b/1.jpg"));
        QCOMPARE(details.duration, 42 * 60);
        QCOMPARE(details.toMap().value("cast").toStringList(), QStringList({"Ann", "Bob"}));
        QCOMPARE(episodes.size(), 3);
        QCOMPARE(episodes[0].name, QString("Pilot"));
        QCOMPARE(episodes[1].name, QString("Show - S01E02")); // nothing left after stripping: kept whole
        QCOMPARE(episodes[1].duration, 1500);
        QCOMPARE(episodes[2].name, QString("Return"));
        QCOMPARE(episodes[2].season, 2);
        QVERIFY(episodes[2].url.endsWith("/22.mp4"));
    }

    void xtreamVodInfoGivesTheMovieSheet()
    {
        const Details d = CatalogParser::parseXtreamVodInfo(
            R"({"info":{"description":"Heist","actors":"Ann, Bob","director":"Cid","genre":"Crime","releasedate":"2019-05-01",)"
            R"("duration":"01:52:30","rating":"7.5","backdrop_path":[],"youtube_trailer":"abc"},"movie_data":{}})");
        QCOMPARE(d.plot, QString("Heist"));
        QCOMPARE(d.cast, QString("Ann, Bob"));
        QCOMPARE(d.director, QString("Cid"));
        QCOMPARE(d.duration, 6750);
        QCOMPARE(d.backdrop, QString());
        QCOMPARE(d.trailer, QString("abc"));
        QVERIFY(CatalogParser::parseXtreamVodInfo("[]").isEmpty());
    }

    void xmltvTimesHonourTheOffset()
    {
        QCOMPARE(Xmltv::parseTime(u"20240101120000 +0100"), QDateTime(QDate(2024, 1, 1), QTime(11, 0), QTimeZone::UTC).toSecsSinceEpoch());
        QCOMPARE(Xmltv::parseTime(u"20240101120000 -0230"), QDateTime(QDate(2024, 1, 1), QTime(14, 30), QTimeZone::UTC).toSecsSinceEpoch());
        QCOMPARE(Xmltv::parseTime(u"202401011200"), QDateTime(QDate(2024, 1, 1), QTime(12, 0), QTimeZone::UTC).toSecsSinceEpoch());
        QCOMPARE(Xmltv::parseTime(u"garbage"), 0);
    }

    void namesNormalizeAcrossProviders()
    {
        QCOMPARE(Xmltv::normalize("FR: TF1 HD"), Xmltv::normalize("TF1"));
        QCOMPARE(Xmltv::normalize("|FR| Télé Matin FHD"), Xmltv::normalize("tele matin"));
        QCOMPARE(Xmltv::normalize("TF1.fr"), Xmltv::normalize("TF1"));
        QVERIFY(Xmltv::normalize("CNN International") != Xmltv::normalize("International"));
    }

    void guideReadsGzipAndPlainAndFindsChannels()
    {
        QTemporaryDir dir;
        const qint64 now = QDateTime::currentSecsSinceEpoch();
        write(dir.filePath("plain.xml"), guideXml(now));
        write(dir.filePath("packed.xml"), gzip(guideXml(now)));

        for (const char *name : {"plain.xml", "packed.xml"}) {
            const EpgData data = Xmltv::parse(dir.filePath(name), now - 6 * 3600, now + 86400);
            QVERIFY2(data.errors.isEmpty(), qPrintable(data.errors.join(", ")));
            QCOMPARE(data.channels.value("one.fr").size(), 2); // "Long ago" falls outside the window

            Guide guide;
            guide.set("s", data);
            Entry byId;
            byId.sourceId = "s";
            byId.epgId = "ONE.FR"; // ids match without regard to case
            NowNext found = guide.at(byId, now);
            QVERIFY(found.now);
            QCOMPARE(found.now->title, QString("News"));
            QCOMPARE(found.now->desc, QString("About News"));
            QCOMPARE(found.next->title, QString("Film"));

            Entry byName;
            byName.sourceId = "s";
            byName.name = "FR: Chaine Une HD";
            QVERIFY(guide.find(byName));
            QCOMPARE(guide.at(byName, now).now->title, QString("News"));
            QCOMPARE(guide.between(byName, now + 2000, now + 3000).size(), 1);

            Entry unknown;
            unknown.sourceId = "s";
            unknown.name = "Nope";
            QVERIFY(!guide.find(unknown));
        }
    }

    void damagedGuideIsReported()
    {
        QTemporaryDir dir;
        write(dir.filePath("bad.xml"), "<tv><programme start=\"2024");
        QVERIFY(!Xmltv::parse(dir.filePath("bad.xml"), 0, 1).errors.isEmpty());
        QVERIFY(!Xmltv::parse(dir.filePath("missing.xml"), 0, 1).errors.isEmpty());
    }

    void backendLoadsAPlaylistAndKeepsState()
    {
        QTemporaryDir dir;
        const qint64 now = QDateTime::currentSecsSinceEpoch();
        write(dir.filePath("list.m3u"), playlist);
        write(dir.filePath("guide.xml"), gzip(guideXml(now)));

        {
            Backend backend(dir.filePath("config"), dir.filePath("data"), dir.filePath("cache"));
            QCOMPARE(backend.saveSource({{"type", "m3u"}, {"name", ""}}), QString("Give the source a name."));
            QVERIFY(!backend.saveSource({{"type", "m3u"}, {"name", "Local"}}).isEmpty());
            QCOMPARE(backend.saveSource({{"type", "m3u"}, {"name", "Local"}, {"playlist", dir.filePath("list.m3u")},
                                         {"epg", "file://" + dir.filePath("guide.xml")}}),
                     QString());
            QCOMPARE(QFile::permissions(dir.filePath("config/sources.json")) & QFileDevice::ReadOther, QFileDevice::Permissions());

            QTRY_COMPARE(backend.entries()->count(), 2);
            QTRY_VERIFY(!backend.busy());
            QVERIFY2(backend.problems().isEmpty(), qPrintable(backend.problems().join(", ")));
            const QString channel = backend.entries()->keyAt(0);
            QCOMPARE(backend.entry(channel).value("nowTitle").toString(), QString("News"));
            QCOMPARE(backend.categories().size(), 2); // all channels, TNT

            backend.setSection("movies");
            QCOMPARE(backend.entries()->count(), 1);
            const QString movie = backend.entries()->keyAt(0);
            backend.openMovie(movie);
            QVERIFY(backend.movieOpen());
            QVERIFY(!backend.movieLoading()); // M3U movies have no sheet to download
            QCOMPARE(backend.movie().value("key").toString(), movie);
            backend.toggleFavorite(movie);
            QVERIFY(backend.movie().value("favorite").toBool());
            backend.savePosition(movie, 60000, 600000);

            backend.setSection("series");
            QVERIFY(!backend.movieOpen()); // changing section closes the sheet
            backend.openSeries(backend.entries()->keyAt(0));
            QVERIFY(backend.seriesOpen());
            QCOMPARE(backend.episodes()->count(), 2);
            QCOMPARE(backend.nextEpisode(backend.episodes()->keyAt(0)), backend.episodes()->keyAt(1));

            backend.setSection("search");
            backend.setQuery("chaine");
            QCOMPARE(backend.entries()->count(), 2); // accents don't matter
            backend.setQuery("deux");
            QCOMPARE(backend.entries()->count(), 1);
        }

        // A new start reads favourites and resume points back.
        Backend backend(dir.filePath("config"), dir.filePath("data"), dir.filePath("cache"));
        backend.setSection("continue");
        QCOMPARE(backend.entries()->count(), 1);
        const QString movie = backend.entries()->keyAt(0);
        QCOMPARE(backend.resumePosition(movie), 60000.0);
        QCOMPARE(backend.progress(movie), 0.1);
        backend.setSection("favorites");
        QTRY_COMPARE(backend.entries()->count(), 1);

        // Watching to the end takes it off "Continue watching".
        backend.savePosition(movie, 590000, 600000);
        backend.setSection("continue");
        QCOMPARE(backend.entries()->count(), 0);
    }

    void zappingWrapsAroundTheList()
    {
        QTemporaryDir dir;
        write(dir.filePath("list.m3u"), playlist);
        Backend backend(dir.filePath("config"), dir.filePath("data"), dir.filePath("cache"));
        backend.saveSource({{"type", "m3u"}, {"name", "Local"}, {"playlist", dir.filePath("list.m3u")}});
        QTRY_COMPARE(backend.entries()->count(), 2);
        const QString first = backend.entries()->keyAt(0), second = backend.entries()->keyAt(1);
        backend.played(first);
        QCOMPARE(backend.neighbor(first, 1), second);
        QCOMPARE(backend.neighbor(first, -1), second);
        QCOMPARE(backend.neighbor(second, 1), first);
    }

    void missingPlaylistIsReported()
    {
        QTemporaryDir dir;
        Backend backend(dir.filePath("config"), dir.filePath("data"), dir.filePath("cache"));
        backend.saveSource({{"type", "m3u"}, {"name", "Gone"}, {"playlist", dir.filePath("nope.m3u")}});
        QTRY_VERIFY(!backend.problems().isEmpty());
        QVERIFY(backend.problems().first().startsWith("Gone: "));
    }

    void passwordsNeverReachProblems()
    {
        QTemporaryDir dir;
        Backend backend(dir.filePath("config"), dir.filePath("data"), dir.filePath("cache"));
        // Nothing listens on port 9; the error mentions the address.
        backend.saveSource({{"type", "xtream"}, {"name", "X"}, {"server", "http://127.0.0.1:9"},
                            {"username", "u"}, {"password", "hunter2"}});
        QTRY_VERIFY_WITH_TIMEOUT(!backend.problems().isEmpty(), 10000);
        for (const auto &problem : backend.problems())
            QVERIFY2(!problem.contains("hunter2"), qPrintable(problem));
    }

    void languageCanBeOverridden()
    {
        QTemporaryDir dir;
        write(dir.path() + "/language", "fr\n");
        write(dir.path() + "/fr.json", R"({"Save": "Enregistrer"})");
        Translator translator(dir.path() + "/language", dir.path());
        QSignalSpy changed(&translator, &Translator::changed);
        QCOMPARE(translator.translate("Main", "Save"), QString("Enregistrer"));

        translator.setOverride("en");
        QCOMPARE(translator.language(), QString("en"));
        QCOMPARE(translator.systemLanguage(), QString("fr"));
        QVERIFY(translator.translate("Main", "Save").isNull());
        QCOMPARE(changed.size(), 1);

        translator.setOverride("not a code");
        QCOMPARE(translator.language(), QString("fr"));

        // The choice is Zap's own, kept with the other preferences.
        {
            Backend backend(dir.filePath("config"), dir.filePath("data"), dir.filePath("cache"));
            QCOMPARE(backend.language(), QString());
            backend.setLanguage("en");
        }
        Backend backend(dir.filePath("config"), dir.filePath("data"), dir.filePath("cache"));
        QCOMPARE(backend.language(), QString("en"));
        QCOMPARE(QFile(dir.path() + "/language").size(), qint64(3)); // Omarchy's file untouched
    }

    void themeFallsBack()
    {
        QTemporaryDir dir;
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#FFD60A"));
        QCOMPARE(theme.accentForeground(), QString("black"));
    }

    void themeReadsAccent()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("theme");
        QFile colors(dir.path() + "/theme/colors.toml");
        QVERIFY(colors.open(QIODevice::WriteOnly));
        colors.write("accent = \"#112233\"\n");
        colors.close();

        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QString("#112233"));
        QCOMPARE(theme.accentForeground(), QString("white"));
    }

    void themeFollowsHyprlandRounding()
    {
        QTemporaryDir dir;
        const QString response = dir.filePath("response.json"), command = dir.filePath("hyprctl");
        auto write = [](const QString &path, const QByteArray &data) {
            QFile file(path);
            return file.open(QIODevice::WriteOnly) && file.write(data) == data.size();
        };
        QVERIFY(write(command, "#!/bin/sh\ncat '" + response.toUtf8() + "'\n"));
        QVERIFY(QFile::setPermissions(command, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
        QVERIFY(write(response, "{\"int\":0}"));

        Theme theme(dir.path(), nullptr, command);
        QCOMPARE(theme.radius(), 0);
        QVERIFY(write(response, "{\"int\":6}"));
        QTRY_COMPARE(theme.radius(), 6);
    }

    void translatorFallsBackToEnglish()
    {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("en"));
        QVERIFY(translator.translate("Main", "Save").isNull());
    }

    void translatorFollowsTheLanguageFile()
    {
        QTemporaryDir dir;
        write(dir.path() + "/language", "pt-BR\n");
        write(dir.path() + "/pt.json", R"({"Save": "Guardar", "Open": "Abrir"})");
        write(dir.path() + "/pt-BR.json", R"({"Save": "Salvar"})");

        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("pt-BR"));
        QCOMPARE(translator.translate("Main", "Save"), QString("Salvar"));
        QCOMPARE(translator.translate("Main", "Open"), QString("Abrir"));
        QVERIFY(translator.translate("Main", "Quit").isNull());
    }

    void translatorPicksPluralForms()
    {
        QTemporaryDir dir;
        write(dir.path() + "/language", "ru\n");
        write(dir.path() + "/en.json", R"({"%n clips": {"one": "%n clip", "other": "%n clips"}})");
        write(dir.path() + "/ru.json", R"({"%n clips": {"one": "%n клип", "few": "%n клипа", "many": "%n клипов", "other": "%n клипа"}})");

        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.translate("Main", "%n clips", nullptr, 21), QString("%n клип"));
        QCOMPARE(translator.translate("Main", "%n clips", nullptr, 22), QString("%n клипа"));
        QCOMPARE(translator.translate("Main", "%n clips", nullptr, 25), QString("%n клипов"));
        QCOMPARE(Translator::pluralCategory("ar", 11), QString("many"));
        QCOMPARE(Translator::pluralCategory("ja", 1), QString("other"));
    }

    // A download that loses its connection half way carries on from there,
    // ends up whole, and goes away with its file when removed.
    void offlineResumesAndRemoves()
    {
        QByteArray video(300000, Qt::Uninitialized);
        for (int i = 0; i < video.size(); ++i)
            video[i] = char(i * 7 % 251);
        QTcpServer server;
        QVERIFY(server.listen(QHostAddress::LocalHost));
        QList<QByteArray> ranges;
        connect(&server, &QTcpServer::newConnection, this, [&] {
            QTcpSocket *socket = server.nextPendingConnection();
            connect(socket, &QTcpSocket::readyRead, socket, [&, socket] {
                const QByteArray request = socket->readAll();
                qint64 start = 0;
                const int at = request.indexOf("Range: bytes=");
                if (at >= 0)
                    start = request.mid(at + 13, request.indexOf('-', at + 13) - at - 13).toLongLong();
                ranges << QByteArray::number(start);
                const QByteArray body = video.mid(start);
                QByteArray head = at >= 0 ? "HTTP/1.1 206 Partial Content\r\nContent-Range: bytes "
                                              + QByteArray::number(start) + "-" + QByteArray::number(video.size() - 1)
                                              + "/" + QByteArray::number(video.size()) + "\r\n"
                                          : "HTTP/1.1 200 OK\r\n";
                head += "Content-Length: " + QByteArray::number(body.size()) + "\r\nConnection: close\r\n\r\n";
                socket->write(head);
                // The first answer stops a third of the way.
                socket->write(ranges.size() == 1 ? body.left(100000) : body);
                socket->disconnectFromHost();
            });
        });

        QTemporaryDir dir;
        Entry movie;
        movie.kind = Entry::Movie;
        movie.key = "s:m:1";
        movie.name = "Film";
        movie.url = QString("http://127.0.0.1:%1/movie/u/p/1.mkv").arg(server.serverPort());
        {
            Offline offline(dir.path());
            offline.setRetryDelay(10);
            QSignalSpy changed(&offline, &Offline::changed);
            offline.add(movie, {});
            QTRY_VERIFY_WITH_TIMEOUT(offline.find(movie.key)->state == Download::Done, 10000);
            QCOMPARE(ranges, (QList<QByteArray>{"0", "100000"}));
            QVERIFY(offline.localFile(movie.key).endsWith(".mkv"));
            QFile file(offline.localFile(movie.key));
            QVERIFY(file.open(QIODevice::ReadOnly));
            QCOMPARE(file.readAll(), video);
        }
        // It's still there after a restart, then deleting it removes the file.
        Offline offline(dir.path());
        const QString path = offline.localFile(movie.key);
        QVERIFY(QFile::exists(path));
        QCOMPARE(offline.find(movie.key)->entry.name, QString("Film"));
        offline.remove(movie.key);
        QVERIFY(!offline.find(movie.key));
        QVERIFY(!QFile::exists(path));
        QVERIFY(Offline(dir.path()).list().isEmpty());

        // Live channels and local files aren't downloadable.
        Entry live = movie;
        live.kind = Entry::Live;
        QVERIFY(!Offline::canDownload(live));
        Entry local = movie;
        local.url = "/tmp/film.mkv";
        QVERIFY(!Offline::canDownload(local));
    }

private:
    static void write(const QString &path, const QByteArray &contents)
    {
        writeFile(path, contents);
    }
};

QTEST_MAIN(ZapTests)
#include "zap_tests.moc"
