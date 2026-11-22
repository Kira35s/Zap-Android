import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtMultimedia

Rectangle {
    id: view
    color: "black"
    radius: win.expanded ? 0 : theme.radius
    clip: true

    property alias output: video

    component OsdButton: ToolButton {
        property string iconName
        property int size: 56
        implicitWidth: size
        implicitHeight: size
        icon.source: "qrc:/icons/" + iconName + ".svg"
        icon.color: "white"
        icon.width: size * 0.55
        icon.height: size * 0.55
        background: Rectangle { radius: width / 2; color: "#66000000" }
    }
    property bool osd: false
    readonly property var live: win.isLive ? (backend.revision, backend.entry(win.playingKey)) : ({})
    readonly property bool waiting: player.error === MediaPlayer.NoError
        && (player.mediaStatus === MediaPlayer.LoadingMedia || player.mediaStatus === MediaPlayer.StalledMedia)

    property string noticeText: ""
    readonly property bool menuOpen: audioMenu.opened || subtitleMenu.opened
    readonly property bool osdShown: win.expanded && (osd || menuOpen || player.playbackState !== MediaPlayer.PlayingState)
    // A notch or rounded corners can cover the edges while the bars are hidden.
    readonly property var safe: win.contentItem.SafeArea.margins

    function showOsd() {
        osd = true
        osdTimer.restart()
    }
    // A short message over the picture, like the track just picked.
    function notice(text) {
        noticeText = text
        noticeTimer.restart()
        showOsd()
    }

    Timer {
        id: osdTimer
        interval: 4000
        onTriggered: view.menuOpen ? restart() : (view.osd = false)
    }
    Timer {
        id: noticeTimer
        interval: 2500
        onTriggered: view.noticeText = ""
    }

    VideoOutput {
        id: video
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }

    // Under the OSD, so its buttons and slider get their own clicks.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: win.expanded
        cursorShape: win.expanded && !view.osd ? Qt.BlankCursor : Qt.ArrowCursor
        onPositionChanged: if (win.expanded) view.showOsd()
        // A tap shows the controls, or hides them when they're up.
        onClicked: !win.expanded ? win.setExpanded(true)
                 : win.touch && view.osd ? (view.osd = false) : view.showOsd()
        onDoubleClicked: if (win.expanded && !win.touch) win.setExpanded(false)
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: view.waiting
        visible: view.waiting
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 560)
        visible: player.error !== MediaPlayer.NoError
        spacing: 6
        Label {
            text: qsTr("This stream can't be played.")
            color: win.ink
            font.pixelSize: win.expanded ? 22 : 15
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }
        Label {
            text: player.errorString
            color: win.muted
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }
        Label {
            visible: !win.android
            text: qsTr("Press O to try it in mpv.")
            color: win.muted
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }
        Button {
            visible: win.android
            text: qsTr("Open in another app")
            Material.roundedScale: theme.radius
            Layout.alignment: Qt.AlignHCenter
            onClicked: backend.openExternally(win.playingKey, player.position)
        }
    }

    Label {
        anchors.centerIn: parent
        visible: player.playbackState === MediaPlayer.PausedState && !(win.touch && view.osdShown)
        text: "❚❚"
        color: "white"
        font.pixelSize: win.expanded ? 56 : 32
        opacity: 0.85
    }

    Label {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: win.expanded ? 28 : 10
        visible: audio.muted || (view.osd && win.expanded && !win.touch)
        text: audio.muted ? qsTr("Muted") : qsTr("Volume %1%").arg(Math.round(backend.volume * 100))
        color: "white"
        padding: 6
        background: Rectangle { color: "#aa000000"; radius: win.small }
    }

    Label {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: win.expanded ? 28 : 10
        visible: view.noticeText !== ""
        text: view.noticeText
        color: "white"
        font.pixelSize: win.expanded ? 18 : 13
        padding: 8
        background: Rectangle { color: "#cc000000"; radius: win.small }
    }

    // Touch: back, favourite and "another app" along the top, and the
    // transport buttons in the middle.
    Rectangle {
        visible: win.touch && view.osdShown
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: topControls.implicitHeight + 32 + view.safe.top
        gradient: Gradient {
            GradientStop { position: 0; color: "#cc000000" }
            GradientStop { position: 1; color: "transparent" }
        }
        RowLayout {
            id: topControls
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 8 + view.safe.top
            anchors.leftMargin: 8 + view.safe.left
            anchors.rightMargin: 8 + view.safe.right
            ToolButton {
                icon.source: "qrc:/icons/back.svg"
                icon.color: "white"
                onClicked: win.back()
            }
            Item { Layout.fillWidth: true }
            ToolButton {
                icon.source: (backend.revision, backend.entry(win.playingKey).favorite)
                             ? "qrc:/icons/star.svg" : "qrc:/icons/star-outline.svg"
                icon.color: (backend.revision, backend.entry(win.playingKey).favorite) ? win.accent : "white"
                onClicked: {
                    win.toggleFavorite(win.playingKey)
                    view.showOsd()
                }
            }
            ToolButton {
                visible: win.android
                icon.source: "qrc:/icons/open-external.svg"
                icon.color: "white"
                onClicked: {
                    if (backend.openExternally(win.playingKey, player.position)) {
                        win.saveProgress()
                        player.pause()
                    }
                }
            }
        }
    }

    Row {
        visible: win.touch && view.osdShown
        anchors.centerIn: parent
        spacing: 36

        OsdButton {
            anchors.verticalCenter: parent.verticalCenter
            iconName: win.isLive ? "previous" : "rewind"
            enabled: win.isLive || player.seekable
            onClicked: win.isLive ? win.zap(-1) : win.seek(-10000)
        }
        OsdButton {
            iconName: player.playbackState === MediaPlayer.PlayingState ? "pause" : "play"
            size: 76
            onClicked: {
                player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
                view.showOsd()
            }
        }
        OsdButton {
            anchors.verticalCenter: parent.verticalCenter
            iconName: win.isLive ? "next" : "forward"
            enabled: win.isLive || player.seekable
            onClicked: win.isLive ? win.zap(1) : win.seek(10000)
        }
    }

    // What's on, shown for a few seconds after anything changes.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: osdColumn.implicitHeight + (win.compact ? 40 : 72) + view.safe.bottom
        visible: view.osdShown
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.35; color: "#cc000000" }
            GradientStop { position: 1; color: "#f0000000" }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onPositionChanged: view.showOsd()
        }

        ColumnLayout {
            id: osdColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: win.compact ? 16 : 36
            anchors.bottomMargin: (win.compact ? 16 : 36) + view.safe.bottom
            anchors.leftMargin: (win.compact ? 16 : 36) + view.safe.left
            anchors.rightMargin: (win.compact ? 16 : 36) + view.safe.right
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                Image {
                    source: win.playing.logo || ""
                    visible: win.isLive && status === Image.Ready
                    fillMode: Image.PreserveAspectFit
                    sourceSize.height: 96
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 48
                }
                Label {
                    text: (win.isLive && win.playing.number > 0 ? win.playing.number + "  " : "")
                          + (win.playing.kind === "episode" && win.playing.seriesName
                             ? win.playing.seriesName + " — " : "")
                          + (win.playing.name || "")
                          + ((backend.revision, backend.entry(win.playingKey).favorite) ? "  ★" : "")
                    color: "white"
                    font.pixelSize: win.compact ? 18 : 26
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Label {
                    text: win.clock(backend.now)
                    color: "#d0d0d6"
                    font.pixelSize: win.compact ? 15 : 20
                }
            }

            // Live: what's on now and next.
            Label {
                visible: win.isLive
                text: view.live.nowTitle
                      ? win.clock(view.live.nowStart) + " – " + win.clock(view.live.nowStop) + "   " + view.live.nowTitle
                      : qsTr("No programme information")
                color: "white"
                font.pixelSize: win.compact ? 14 : 18
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            ProgressBar {
                visible: win.isLive && !!view.live.nowTitle
                from: 0
                to: 1
                value: view.live.nowStop > view.live.nowStart
                       ? (backend.now - view.live.nowStart) / (view.live.nowStop - view.live.nowStart) : 0
                Layout.fillWidth: true
            }
            Label {
                visible: win.isLive && !!view.live.nextTitle
                text: qsTr("Next at %1: %2").arg(win.clock(view.live.nextStart || 0)).arg(view.live.nextTitle || "")
                color: "#b9b9c2"
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            // Movies and episodes: where we are.
            RowLayout {
                visible: !win.isLive
                Layout.fillWidth: true
                spacing: 14
                Label {
                    text: win.duration(player.position)
                    color: "white"
                }
                Slider {
                    from: 0
                    to: Math.max(1, player.duration)
                    value: player.position
                    enabled: player.seekable
                    Layout.fillWidth: true
                    onMoved: player.setPosition(value)
                }
                Label {
                    text: win.duration(player.duration)
                    color: "white"
                }
            }

            // Language and subtitles, when the stream has a choice.
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: player.audioTracks.length > 1 || player.subtitleTracks.length > 0

                Button {
                    id: audioButton
                    visible: player.audioTracks.length > 1
                    focusPolicy: Qt.NoFocus
                    flat: true
                    Material.foreground: "white"
                    Material.roundedScale: theme.radius
                    text: {
                        win.trackRevision
                        const track = win.tracks("audio")[Math.max(0, player.activeAudioTrack)]
                        return qsTr("Audio: %1").arg(track ? track.label : "—") + "  ▾"
                    }
                    onClicked: audioMenu.open()
                    Menu {
                        id: audioMenu
                        y: -height
                        Repeater {
                            model: audioMenu.opened ? win.tracks("audio") : []
                            delegate: MenuItem {
                                required property var modelData
                                required property int index
                                text: modelData.label
                                checkable: true
                                checked: (win.trackRevision, index === Math.max(0, player.activeAudioTrack))
                                onTriggered: win.chooseAudio(index)
                            }
                        }
                    }
                }
                Button {
                    id: subtitleButton
                    visible: player.subtitleTracks.length > 0
                    focusPolicy: Qt.NoFocus
                    flat: true
                    Material.foreground: "white"
                    Material.roundedScale: theme.radius
                    text: {
                        win.trackRevision
                        const track = win.tracks("subtitle")[player.activeSubtitleTrack]
                        return (track ? qsTr("Subtitles: %1").arg(track.label) : qsTr("Subtitles off")) + "  ▾"
                    }
                    onClicked: subtitleMenu.open()
                    Menu {
                        id: subtitleMenu
                        y: -height
                        MenuItem {
                            text: qsTr("Off")
                            checkable: true
                            checked: (win.trackRevision, player.activeSubtitleTrack < 0)
                            onTriggered: win.chooseSubtitle(-1)
                        }
                        Repeater {
                            model: subtitleMenu.opened ? win.tracks("subtitle") : []
                            delegate: MenuItem {
                                required property var modelData
                                required property int index
                                text: modelData.label
                                checkable: true
                                checked: (win.trackRevision, index === player.activeSubtitleTrack)
                                onTriggered: win.chooseSubtitle(index)
                            }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
            }

            Label {
                visible: !win.touch
                text: win.isLive
                      ? qsTr("↑ ↓ change channel · Space pause · A audio · S subtitles · F favourite · Esc back to the list · ? shortcuts")
                      : qsTr("← → 10 seconds · Shift+← → 1 minute · Space pause · A audio · S subtitles · Esc stop · ? shortcuts")
                color: "#8b8b96"
                font.pixelSize: 13
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }

}
