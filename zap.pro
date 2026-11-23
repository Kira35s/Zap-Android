QT += core gui network concurrent qml quick quickcontrols2 multimedia

CONFIG += c++17 release
TARGET = zap
TEMPLATE = app

# XMLTV guides usually come gzipped; zlib inflates them while they're parsed.
LIBS += -lz

HEADERS += \
    src/backend.h \
    src/catalog.h \
    src/downloader.h \
    src/entrymodel.h \
    src/guide.h \
    src/offline.h \
    src/theme.h \
    src/translator.h

SOURCES += \
    src/main.cpp \
    src/backend.cpp \
    src/catalog.cpp \
    src/downloader.cpp \
    src/entrymodel.cpp \
    src/guide.cpp \
    src/offline.cpp \
    src/theme.cpp \
    src/translator.cpp

RESOURCES += src/resources.qrc

android {
    ANDROID_PACKAGE_SOURCE_DIR = $$PWD/android
    ANDROID_VERSION_NAME = 0.3.0
    ANDROID_VERSION_CODE = 3
    ANDROID_MIN_SDK_VERSION = 28
    ANDROID_TARGET_SDK_VERSION = 36
    # Posters and https streams need OpenSSL, which Android doesn't ship to apps
    # (https://github.com/KDAB/android_openssl, cloned into ~/Android; bin/apk points here).
    ANDROID_OPENSSL = $$(ANDROID_OPENSSL)
    !isEmpty(ANDROID_OPENSSL): include($$ANDROID_OPENSSL/openssl.pri)
}
