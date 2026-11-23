// zap — watch IPTV: live channels with their TV guide, movies and series,
// from Xtream Codes accounts and M3U playlists.

#include <QDir>
#include <QGuiApplication>
#include <QIcon>
#include <QNetworkAccessManager>
#include <QNetworkDiskCache>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlNetworkAccessManagerFactory>
#include <QQuickStyle>
#include <QUrl>

#include "backend.h"
#include "theme.h"
#include "translator.h"

namespace {

// Channel logos and posters come from the provider on every scroll otherwise.
class ImageCacheFactory : public QQmlNetworkAccessManagerFactory {
public:
    QNetworkAccessManager *create(QObject *parent) override {
        auto *manager = new QNetworkAccessManager(parent);
        auto *cache = new QNetworkDiskCache(manager);
        const QString base = qEnvironmentVariable("XDG_CACHE_HOME", QDir::homePath() + "/.cache");
        cache->setCacheDirectory(base + "/zap/images");
        cache->setMaximumCacheSize(256 * 1024 * 1024);
        manager->setCache(cache);
        return manager;
    }
};

} // namespace

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    app.setApplicationName("zap");
    app.setApplicationVersion("0.2.0");

    // Matches the window to zap.desktop, so the compositor (Wayland app_id)
    // and the launcher pick up the installed icon.
    app.setDesktopFileName("zap");
    app.setWindowIcon(QIcon::fromTheme("zap"));

    QQuickStyle::setStyle("Material");

    // Installed before anything is translated, and every qsTr() binding is
    // re-evaluated when the Omarchy language changes.
    Translator translator;
    app.installTranslator(&translator);

    Theme theme;
    Backend backend;
    ImageCacheFactory images;

    QQmlApplicationEngine engine;
    engine.setNetworkAccessManagerFactory(&images);
    QObject::connect(&translator, &Translator::changed, &engine, &QQmlEngine::retranslate);
    QObject::connect(&translator, &Translator::changed, &backend, &Backend::retranslate);
    translator.setOverride(backend.language());
    QObject::connect(&backend, &Backend::languageChanged, &translator,
                     [&] { translator.setOverride(backend.language()); });
    engine.rootContext()->setContextProperty("translator", &translator);
    engine.rootContext()->setContextProperty("theme", &theme);
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.load(QUrl("qrc:/Main.qml"));
    if (engine.rootObjects().isEmpty())
        return 1;

    return app.exec();
}
