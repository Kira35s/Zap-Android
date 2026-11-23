import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Window
import QtMultimedia

ApplicationWindow {
    id: win
    width: 1360
    height: 820
    minimumWidth: touch ? 0 : 960
    minimumHeight: touch ? 0 : 580
    visible: true
    title: playing.name ? playing.name + " — Zap" : "Zap"
    color: "#0e0e10"

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    readonly property color accent: theme.accent
    readonly property color ink: "#e8e8ec"
    readonly property color muted: "#8b8b96"
    readonly property color panel: "#141417"
    readonly property color raised: "#1c1c21"
    readonly property int small: Math.min(4, theme.radius)

    // Android: a tap plays, there's no keyboard to hint at, and Back steps back.
    // On a phone (or a narrow tablet) the side panels fold into drawers and
    // everything plays full screen. --touch tries it on the desktop.
    readonly property bool android: Qt.platform.os === "android"
    readonly property bool touch: android || Qt.application.arguments.indexOf("--touch") >= 0
    readonly property bool compact: touch && width < 900

    property string selectedKey: ""
    property string playingKey: ""
    property var playing: ({})
    property bool expanded: false
    property bool helpVisible: false
    property real pendingSeek: 0
    readonly property bool isLive: playing.kind === "live"

    function tint(alpha) { return Qt.rgba(accent.r, accent.g, accent.b, alpha) }

    // Bindings that format times read the language, so they re-render on a switch.
    function clock(seconds) {
        translator.language
        return new Date(seconds * 1000).toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
    }
    function day(seconds) {
        translator.language
        return new Date(seconds * 1000).toLocaleDateString(Qt.locale(), "dddd d MMMM")
    }
    function duration(ms) {
        const s = Math.max(0, Math.floor(ms / 1000))
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60
        return (h > 0 ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(x).padStart(2, "0")
    }
    function sectionTitle(id) {
        switch (id) {
        case "live": return qsTr("Live TV")
        case "guide": return qsTr("TV guide")
        case "movies": return qsTr("Movies")
        case "series": return qsTr("Series")
        case "favorites": return qsTr("Favourites")
        case "continue": return qsTr("Continue watching")
        case "downloads": return qsTr("Downloads")
        case "search": return qsTr("Search")
        case "sources": return qsTr("Sources")
        case "settings": return qsTr("Settings")
        }
        return ""
    }

    // Playback

    function play(key, expand) {
        const e = backend.entry(key)
        if (!e.url)
            return
        saveProgress()
        playing = e
        playingKey = key
        pendingSeek = e.kind === "live" ? 0 : (e.position || 0)
        player.source = e.url
        player.play()
        backend.played(key)
        if (expand)
            setExpanded(true)
    }
    // direct skips a movie's sheet; "Continue watching" always resumes straight away.
    function activate(key, direct) {
        if (!key)
            return
        const e = backend.entry(key)
        if (e.kind === "series") {
            backend.openSeries(key)
            return
        }
        if (e.kind === "movie" && !direct && backend.section !== "continue") {
            backend.openMovie(key)
            return
        }
        if (e.kind === "live") {
            // The first Enter previews the channel, the second fills the screen.
            // A phone has no room for the preview, so a tap goes straight to it.
            if (playingKey === key && player.playbackState !== MediaPlayer.StoppedState)
                setExpanded(true)
            else
                play(key, compact)
            return
        }
        play(key, true)
    }
    function stop() {
        saveProgress()
        player.stop()
        player.source = ""
        playingKey = ""
        playing = ({})
        setExpanded(false)
    }
    function saveProgress() {
        if (playingKey && playing.kind !== "live" && player.duration > 0)
            backend.savePosition(playingKey, player.position, player.duration)
    }
    function applyPendingSeek() {
        if (pendingSeek > 0 && player.seekable
                && (player.mediaStatus === MediaPlayer.LoadedMedia || player.mediaStatus === MediaPlayer.BufferedMedia
                    || player.mediaStatus === MediaPlayer.BufferingMedia)) {
            player.setPosition(pendingSeek)
            pendingSeek = 0
        }
    }
    function seek(deltaMs) {
        if (!player.seekable)
            return
        player.setPosition(Math.max(0, Math.min(player.duration, player.position + deltaMs)))
        playerView.showOsd()
    }
    function zap(delta) {
        if (!isLive)
            return
        const key = backend.neighbor(playingKey, delta)
        if (key && key !== playingKey) {
            play(key, false)
            playerView.showOsd()
        }
    }
    function setExpanded(on) {
        if (on === expanded)
            return
        expanded = on
        if (on) {
            win.showFullScreen()
            playerView.showOsd()
        } else {
            win.showNormal()
            Qt.callLater(restoreFocus)
        }
    }

    // Audio and subtitle tracks. The language picked last is tried first on
    // whatever plays next; "*" means subtitles on in whatever language there is.

    // Qt doesn't always signal a track switch, so the labels follow this.
    property int trackRevision: 0
    function tracks(kind) {
        const list = kind === "audio" ? player.audioTracks : player.subtitleTracks
        const described = []
        for (let i = 0; i < list.length; ++i)
            described.push(backend.describeTrack(list[i], i))
        return described
    }
    function applyTrackPreferences() {
        const audio = tracks("audio")
        for (let i = 0; i < audio.length; ++i)
            if (backend.audioLanguage && audio[i].language === backend.audioLanguage) {
                if (player.activeAudioTrack !== i)
                    player.activeAudioTrack = i
                break
            }
        const subtitles = tracks("subtitle")
        let subtitle = -1
        if (backend.subtitleLanguage === "*" && subtitles.length > 0)
            subtitle = 0
        for (let j = 0; j < subtitles.length && subtitle < 0; ++j)
            if (backend.subtitleLanguage && subtitles[j].language === backend.subtitleLanguage)
                subtitle = j
        if (player.activeSubtitleTrack !== subtitle)
            player.activeSubtitleTrack = subtitle
        ++trackRevision
    }
    function chooseAudio(index) {
        const track = tracks("audio")[index]
        if (!track)
            return
        player.activeAudioTrack = index
        ++trackRevision
        if (track.language)
            backend.audioLanguage = track.language
        playerView.notice(qsTr("Audio: %1").arg(track.label))
    }
    function chooseSubtitle(index) {
        const track = tracks("subtitle")[index]
        player.activeSubtitleTrack = track ? index : -1
        ++trackRevision
        backend.subtitleLanguage = track ? (track.language || "*") : ""
        playerView.notice(track ? qsTr("Subtitles: %1").arg(track.label) : qsTr("Subtitles off"))
    }
    function cycleAudio() {
        const count = player.audioTracks.length
        if (count < 2)
            playerView.notice(count === 0 ? qsTr("No audio track to choose from") : qsTr("Only one audio track"))
        else
            chooseAudio((Math.max(0, player.activeAudioTrack) + 1) % count)
    }
    function cycleSubtitles() {
        const count = player.subtitleTracks.length
        if (count === 0)
            playerView.notice(qsTr("No subtitles in this stream"))
        else
            chooseSubtitle(player.activeSubtitleTrack + 1 < count ? player.activeSubtitleTrack + 1 : -1)
    }

    // Downloads for watching offline. d is backend.download(key).

    function downloadLabel(d) {
        switch (d.state) {
        case "queued": return qsTr("Waiting to download…")
        case "running": return d.progress >= 0 ? qsTr("Downloading… %1 %").arg(Math.floor(d.progress * 100))
                                                : qsTr("Downloading… %1").arg(d.size)
        case "done": return qsTr("✓  Downloaded")
        case "failed": return qsTr("Download failed")
        }
        return qsTr("↓  Download")
    }
    function downloadGlyph(d) {
        switch (d.state) {
        case "queued": return "…"
        case "running": return d.progress >= 0 ? Math.floor(d.progress * 100) + " %" : "↓"
        case "done": return "✓"
        case "failed": return "!"
        }
        return "↓"
    }
    function downloadStatus(d) {
        switch (d.state) {
        case "queued": return d.error ? qsTr("Connection lost, trying again shortly…") : qsTr("Waiting to download…")
        case "running": return d.totalSize ? qsTr("%1 of %2").arg(d.size).arg(d.totalSize) : d.size
        case "done": return qsTr("Ready to watch offline · %1").arg(d.size)
        case "failed": return qsTr("Download failed: %1").arg(d.error)
        }
        return ""
    }
    // Starts it, or offers what can be done with it.
    function downloadAction(key, anchor) {
        if (!key || !backend.canDownload(key))
            return
        if (!backend.download(key).state) {
            backend.startDownload(key)
            toast.show(qsTr("Downloading — find it under Downloads"))
        } else {
            downloadMenuFor(key, anchor)
        }
    }
    function downloadMenuFor(key, anchor) {
        if (!backend.download(key).state)
            return
        downloadMenu.key = key
        downloadMenu.parent = anchor || root
        downloadMenu.x = anchor ? anchor.width - downloadMenu.width : (root.width - downloadMenu.width) / 2
        downloadMenu.y = anchor ? anchor.height : (root.height - downloadMenu.height) / 2
        downloadMenu.open()
    }

    function toggleFavorite(key) {
        backend.toggleFavorite(key)
        toast.show(backend.entry(key).favorite ? qsTr("Added to favourites") : qsTr("Removed from favourites"))
    }

    // Navigation

    function goSection(id) {
        backend.section = id
        Qt.callLater(restoreFocus)
    }
    readonly property var currentPage: detailLoader.item || contentLoader.item
    function restoreFocus() {
        if (currentPage)
            currentPage.forceActiveFocus()
    }
    function focusCategories() {
        if (compact)
            return
        if (categoryList.visible)
            categoryList.focusList()
    }
    function startSearch() {
        setExpanded(false)
        backend.section = "search"
        Qt.callLater(() => { if (contentLoader.item && contentLoader.item.focusSearch) contentLoader.item.focusSearch() })
    }
    function closeDrawers() {
        navDrawer.close()
        categoryDrawer.close()
    }
    function back() {
        if (downloadMenu.opened)
            downloadMenu.close()
        else if (navDrawer.opened || categoryDrawer.opened)
            closeDrawers()
        else if (helpVisible)
            helpVisible = false
        else if (expanded)
            // Without a preview to keep playing in, leaving full screen stops.
            isLive && !compact ? setExpanded(false) : stop()
        else if (backend.movieOpen) {
            backend.closeMovie()
            Qt.callLater(restoreFocus)
        } else if (!detailLoader.item && contentLoader.item && contentLoader.item.back && contentLoader.item.back())
            return
        else if (backend.seriesOpen) {
            backend.closeSeries()
            Qt.callLater(restoreFocus)
        } else if (backend.section === "search" && backend.query)
            backend.query = ""
        else if (android && backend.section !== "live" && backend.sources.length > 0)
            goSection("live")
        else if (android) {
            saveProgress()
            Qt.quit()
        } else
            restoreFocus()
    }

    MediaPlayer {
        id: player
        audioOutput: AudioOutput {
            id: audio
            volume: backend.volume
        }
        videoOutput: playerView.output
        onMediaStatusChanged: {
            win.applyPendingSeek()
            // Series play on: the next episode starts when one ends.
            if (mediaStatus === MediaPlayer.EndOfMedia && win.playingKey) {
                win.saveProgress()
                const next = backend.nextEpisode(win.playingKey)
                if (next)
                    win.play(next, true)
                else if (!win.isLive)
                    win.stop()
            }
        }
        onSeekableChanged: win.applyPendingSeek()
        onPlaybackStateChanged: backend.keepScreenOn(playbackState === MediaPlayer.PlayingState)
        onTracksChanged: win.applyTrackPreferences()
    }

    Timer {
        interval: 10000
        repeat: true
        running: win.playingKey !== "" && !win.isLive && player.playbackState === MediaPlayer.PlayingState
        onTriggered: win.saveProgress()
    }

    onClosing: saveProgress()

    Shortcut { sequence: "?"; context: Qt.ApplicationShortcut; onActivated: win.helpVisible = !win.helpVisible }
    Shortcut { sequence: "Q"; context: Qt.ApplicationShortcut; onActivated: { win.saveProgress(); Qt.quit() } }
    Shortcut { sequences: ["Esc", "Back"]; context: Qt.ApplicationShortcut; onActivated: win.back() }
    Shortcut {
        sequence: "Space"
        context: Qt.ApplicationShortcut
        enabled: win.playingKey !== ""
        onActivated: {
            player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
            playerView.showOsd()
        }
    }
    Shortcut {
        sequence: "F11"
        context: Qt.ApplicationShortcut
        onActivated: win.visibility === Window.FullScreen ? win.showNormal() : win.showFullScreen()
    }
    Shortcut { sequences: ["/", "Ctrl+F"]; context: Qt.ApplicationShortcut; onActivated: win.startSearch() }
    Shortcut { sequence: "1"; context: Qt.ApplicationShortcut; enabled: !win.expanded; onActivated: win.goSection("live") }
    Shortcut { sequence: "2"; context: Qt.ApplicationShortcut; enabled: !win.expanded; onActivated: win.goSection("guide") }
    Shortcut { sequence: "3"; context: Qt.ApplicationShortcut; enabled: !win.expanded; onActivated: win.goSection("movies") }
    Shortcut { sequence: "4"; context: Qt.ApplicationShortcut; enabled: !win.expanded; onActivated: win.goSection("series") }
    Shortcut { sequence: "5"; context: Qt.ApplicationShortcut; enabled: !win.expanded; onActivated: win.goSection("favorites") }
    Shortcut { sequence: "6"; context: Qt.ApplicationShortcut; enabled: !win.expanded; onActivated: win.goSection("continue") }
    Shortcut { sequence: "7"; context: Qt.ApplicationShortcut; enabled: !win.expanded; onActivated: win.goSection("sources") }
    Shortcut { sequence: "8"; context: Qt.ApplicationShortcut; enabled: !win.expanded; onActivated: win.goSection("settings") }
    Shortcut { sequence: "9"; context: Qt.ApplicationShortcut; enabled: !win.expanded; onActivated: win.goSection("downloads") }
    Shortcut {
        sequence: "D"
        context: Qt.ApplicationShortcut
        enabled: !win.expanded
        onActivated: win.downloadAction(backend.movieOpen ? backend.movie.key : win.selectedKey, null)
    }
    Shortcut {
        sequence: "F"
        context: Qt.ApplicationShortcut
        onActivated: {
            const key = win.expanded ? win.playingKey : (backend.seriesOpen && !win.selectedKey ? backend.series.key : win.selectedKey)
            if (key) {
                backend.toggleFavorite(key)
                playerView.showOsd()
            }
        }
    }
    Shortcut { sequence: "R"; context: Qt.ApplicationShortcut; enabled: !win.expanded; onActivated: backend.refresh() }
    Shortcut {
        sequence: "O"
        context: Qt.ApplicationShortcut
        onActivated: {
            const key = win.expanded || !win.selectedKey ? win.playingKey : win.selectedKey
            const position = key === win.playingKey ? player.position : backend.resumePosition(key)
            if (key && backend.openExternally(key, position) && win.playingKey) {
                win.saveProgress()
                player.pause()
            }
        }
    }
    Shortcut { sequence: "A"; context: Qt.ApplicationShortcut; enabled: win.playingKey !== ""; onActivated: win.cycleAudio() }
    Shortcut { sequence: "S"; context: Qt.ApplicationShortcut; enabled: win.playingKey !== ""; onActivated: win.cycleSubtitles() }
    Shortcut { sequence: "M"; context: Qt.ApplicationShortcut; onActivated: { audio.muted = !audio.muted; playerView.showOsd() } }
    Shortcut { sequence: "X"; context: Qt.ApplicationShortcut; enabled: win.playingKey !== ""; onActivated: win.stop() }
    Shortcut { sequences: ["+", "="]; context: Qt.ApplicationShortcut; onActivated: { backend.volume = backend.volume + 0.1; playerView.showOsd() } }
    Shortcut { sequence: "-"; context: Qt.ApplicationShortcut; onActivated: { backend.volume = backend.volume - 0.1; playerView.showOsd() } }
    Shortcut { sequences: ["Up", "PgUp"]; context: Qt.ApplicationShortcut; enabled: win.expanded && win.isLive; onActivated: win.zap(-1) }
    Shortcut { sequences: ["Down", "PgDown"]; context: Qt.ApplicationShortcut; enabled: win.expanded && win.isLive; onActivated: win.zap(1) }
    Shortcut { sequence: "PgUp"; context: Qt.ApplicationShortcut; enabled: !win.expanded && win.isLive && backend.section !== "guide"; onActivated: win.zap(-1) }
    Shortcut { sequence: "PgDown"; context: Qt.ApplicationShortcut; enabled: !win.expanded && win.isLive && backend.section !== "guide"; onActivated: win.zap(1) }
    Shortcut { sequence: "Left"; context: Qt.ApplicationShortcut; enabled: win.expanded && !win.isLive; onActivated: win.seek(-10000) }
    Shortcut { sequence: "Right"; context: Qt.ApplicationShortcut; enabled: win.expanded && !win.isLive; onActivated: win.seek(10000) }
    Shortcut { sequence: "Shift+Left"; context: Qt.ApplicationShortcut; enabled: win.expanded && !win.isLive; onActivated: win.seek(-60000) }
    Shortcut { sequence: "Shift+Right"; context: Qt.ApplicationShortcut; enabled: win.expanded && !win.isLive; onActivated: win.seek(60000) }
    Shortcut { sequences: ["Return", "Enter", "I"]; context: Qt.ApplicationShortcut; enabled: win.expanded; onActivated: playerView.showOsd() }
    Shortcut {
        sequence: "Del"
        context: Qt.ApplicationShortcut
        enabled: !win.expanded && backend.section === "continue" && win.selectedKey !== ""
        onActivated: backend.forget(win.selectedKey)
    }

    Component.onCompleted: {
        if (backend.sources.length === 0)
            backend.section = "sources"
        Qt.callLater(restoreFocus)
    }

    // Right-to-left languages mirror the window; the Translator sets the
    // application's layout direction.
    Item {
        id: root
        anchors.fill: parent
        // Android draws under the status and navigation bars; video alone may.
        anchors.topMargin: win.expanded ? 0 : win.contentItem.SafeArea.margins.top
        anchors.bottomMargin: win.expanded ? 0 : win.contentItem.SafeArea.margins.bottom
        anchors.leftMargin: win.expanded ? 0 : win.contentItem.SafeArea.margins.left
        anchors.rightMargin: win.expanded ? 0 : win.contentItem.SafeArea.margins.right
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            visible: !win.expanded

            TopBar {
                visible: win.compact
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                NavRail {
                    visible: !win.compact
                    Layout.fillHeight: true
                    Layout.preferredWidth: 210
                }

                CategoryList {
                    id: categoryList
                    Layout.fillHeight: true
                    Layout.preferredWidth: 260
                    visible: !win.compact && backend.categories.length > 0 && !backend.seriesOpen && !backend.movieOpen
                }

                // A movie's sheet or a series' episodes open over the list, which
                // keeps its place underneath for when they close.
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 0
                    Layout.preferredHeight: 0

                    Loader {
                        id: contentLoader
                        anchors.fill: parent
                        visible: !detailLoader.item
                        sourceComponent: backend.section === "settings" ? settingsPage
                                       : backend.section === "sources" ? sourcesPage
                                       : backend.section === "guide" ? guidePage
                                       : backend.section === "downloads" ? downloadsPage
                                       : backend.section === "movies" || backend.section === "series" ? gridPage
                                       : listPage
                        onLoaded: Qt.callLater(win.restoreFocus)
                    }
                    Loader {
                        id: detailLoader
                        anchors.fill: parent
                        sourceComponent: backend.movieOpen ? moviePage : backend.seriesOpen ? seriesPage : null
                        onLoaded: Qt.callLater(win.restoreFocus)
                        onItemChanged: if (!item) Qt.callLater(win.restoreFocus)
                    }
                }

                InfoPane {
                    id: infoPane
                    Layout.fillHeight: true
                    Layout.preferredWidth: Math.round(root.width * 0.3)
                    Layout.preferredHeight: 0
                    visible: !win.compact && backend.section !== "guide" && backend.section !== "sources"
                             && backend.section !== "settings" && !backend.movieOpen
                }
            }
        }

        Rectangle {
            id: expandedHost
            anchors.fill: parent
            color: "black"
            visible: win.expanded
        }

        PlayerView {
            id: playerView
            parent: win.expanded ? expandedHost
                  : win.currentPage && win.currentPage.videoHost ? win.currentPage.videoHost : infoPane.videoHost
            anchors.fill: parent
            visible: win.playingKey !== ""
        }

        ProblemBanner {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            width: Math.min(parent.width - 32, 720)
        }

        HelpOverlay {
            anchors.fill: parent
            visible: win.helpVisible
        }

        // A short confirmation, for what a long press did.
        Label {
            id: toast
            function show(message) {
                text = message
                toastTimer.restart()
            }
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 72
            visible: toastTimer.running
            color: win.ink
            padding: 12
            background: Rectangle { color: "#ee26262c"; radius: theme.radius }
            Timer { id: toastTimer; interval: 1800 }
        }
    }

    Drawer {
        id: navDrawer
        edge: Qt.LeftEdge
        width: Math.min(300, win.width * 0.8)
        height: win.height
        interactive: win.compact && !win.expanded
        NavRail { anchors.fill: parent }
    }
    Drawer {
        id: categoryDrawer
        edge: Qt.RightEdge
        width: Math.min(340, win.width * 0.85)
        height: win.height
        interactive: false
        CategoryList { anchors.fill: parent }
    }

    Menu {
        id: downloadMenu
        property string key
        readonly property var d: (backend.downloads, backend.download(key))
        modal: true
        onClosed: Qt.callLater(win.restoreFocus)

        MenuItem {
            text: qsTr("Play")
            visible: downloadMenu.d.state === "done"
            height: visible ? implicitHeight : 0
            onTriggered: win.activate(downloadMenu.key, true)
        }
        MenuItem {
            text: qsTr("Try again")
            visible: downloadMenu.d.state === "failed"
            height: visible ? implicitHeight : 0
            onTriggered: backend.retryDownload(downloadMenu.key)
        }
        MenuItem {
            text: qsTr("See downloads")
            visible: backend.section !== "downloads"
            height: visible ? implicitHeight : 0
            onTriggered: {
                backend.closeMovie()
                backend.closeSeries()
                win.goSection("downloads")
            }
        }
        MenuItem {
            text: downloadMenu.d.state === "done" || downloadMenu.d.state === "failed"
                  ? qsTr("Delete the download") : qsTr("Cancel the download")
            onTriggered: backend.removeDownload(downloadMenu.key)
        }
    }

    Component { id: listPage; EntryPage {} }
    Component { id: downloadsPage; DownloadsPage {} }
    Component { id: gridPage; PosterGrid {} }
    Component { id: guidePage; GuideGrid {} }
    Component { id: seriesPage; SeriesPage {} }
    Component { id: moviePage; MoviePage {} }
    Component { id: sourcesPage; SourcesPage {} }
    Component { id: settingsPage; SettingsPage {} }
}
