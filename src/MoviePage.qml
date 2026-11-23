import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// A movie's sheet: poster, synopsis, director and cast, and the buttons to
// play it. Enter on a movie anywhere but "Continue watching" opens it.
FocusScope {
    id: page
    readonly property var info: (backend.revision, backend.movie)
    readonly property bool resumable: (info.position || 0) > 0
    property alias videoHost: preview

    function hours(seconds) {
        const m = Math.round(seconds / 60)
        return m >= 60 ? qsTr("%1 h %2").arg(Math.floor(m / 60)).arg(String(m % 60).padStart(2, "0"))
                       : qsTr("%1 min").arg(m)
    }
    function playFromStart() {
        backend.forget(info.key)
        win.activate(info.key, true)
    }

    Component.onCompleted: {
        win.selectedKey = info.key || ""
        playButton.forceActiveFocus()
    }
    onActiveFocusChanged: if (activeFocus) playButton.forceActiveFocus()

    // The provider's backdrop, faded behind everything.
    Image {
        id: backdrop
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: parent.height * 0.6
        source: page.info.backdrop || ""
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 1280
        opacity: 0.35
    }
    Rectangle {
        anchors.fill: backdrop
        visible: backdrop.status === Image.Ready
        gradient: Gradient {
            GradientStop { position: 0; color: "#600e0e10" }
            GradientStop { position: 1; color: "#0e0e10" }
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: win.compact ? 12 : 24
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: body
            width: flick.width
            spacing: 20

            RowLayout {
                Layout.fillWidth: true
                spacing: win.compact ? 14 : 24

                Rectangle {
                    Layout.preferredWidth: win.compact ? 110 : 220
                    Layout.preferredHeight: win.compact ? 165 : 330
                    Layout.alignment: Qt.AlignTop
                    color: win.raised
                    radius: win.small
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: page.info.logo || ""
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 440
                    }
                    Rectangle {
                        visible: (page.info.progress || 0) > 0
                        anchors.bottom: parent.bottom
                        width: parent.width * (page.info.progress || 0)
                        height: 4
                        color: win.accent
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 10

                    Label {
                        text: (page.info.name || "") + (page.info.favorite ? "  ★" : "")
                        color: win.ink
                        font.pixelSize: win.compact ? 22 : 30
                        font.bold: true
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                    Label {
                        text: [page.info.year,
                               page.info.runtime > 0 ? page.hours(page.info.runtime) : "",
                               page.info.genre,
                               page.info.country,
                               page.info.rating ? "★ " + page.info.rating : ""].filter(s => s).join(" · ")
                        visible: text !== ""
                        color: win.muted
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    // Wraps on a phone, where four buttons don't fit on one line.
                    Flow {
                        spacing: 8
                        Layout.topMargin: 6
                        Layout.fillWidth: true
                        Button {
                            id: playButton
                            text: page.resumable ? qsTr("▶  Resume at %1").arg(win.duration(page.info.position))
                                                 : qsTr("▶  Play")
                            highlighted: true
                            Material.roundedScale: theme.radius
                            onClicked: win.activate(page.info.key, true)
                            Keys.onReturnPressed: clicked()
                            Keys.onEnterPressed: clicked()
                            KeyNavigation.right: startButton.visible ? startButton : favoriteButton
                        }
                        Button {
                            id: startButton
                            visible: page.resumable
                            text: qsTr("From the start")
                            flat: !activeFocus
                            Material.roundedScale: theme.radius
                            onClicked: page.playFromStart()
                            Keys.onReturnPressed: clicked()
                            Keys.onEnterPressed: clicked()
                            KeyNavigation.left: playButton
                            KeyNavigation.right: favoriteButton
                        }
                        Button {
                            id: favoriteButton
                            text: page.info.favorite ? qsTr("★  In favourites") : qsTr("☆  Add to favourites")
                            flat: !activeFocus
                            Material.roundedScale: theme.radius
                            onClicked: backend.toggleFavorite(page.info.key)
                            Keys.onReturnPressed: clicked()
                            Keys.onEnterPressed: clicked()
                            KeyNavigation.left: startButton.visible ? startButton : playButton
                            KeyNavigation.right: downloadButton.visible ? downloadButton : mpvButton
                        }
                        // Keeps a copy on the device, to watch without a connection.
                        Button {
                            id: downloadButton
                            readonly property var d: (backend.downloads, backend.download(page.info.key || ""))
                            visible: backend.canDownload(page.info.key || "")
                            text: win.downloadLabel(d)
                            flat: !activeFocus && d.state !== "done"
                            Material.roundedScale: theme.radius
                            onClicked: win.downloadAction(page.info.key, downloadButton)
                            Keys.onReturnPressed: clicked()
                            Keys.onEnterPressed: clicked()
                            KeyNavigation.left: favoriteButton
                            KeyNavigation.right: mpvButton
                        }
                        Button {
                            id: mpvButton
                            text: win.android ? qsTr("Open in another app") : qsTr("Open in mpv")
                            flat: !activeFocus
                            Material.roundedScale: theme.radius
                            onClicked: backend.openExternally(page.info.key, page.info.position || 0)
                            Keys.onReturnPressed: clicked()
                            Keys.onEnterPressed: clicked()
                            KeyNavigation.left: downloadButton.visible ? downloadButton : favoriteButton
                        }
                    }

                    BusyIndicator {
                        running: backend.movieLoading
                        visible: running
                    }

                    Label {
                        text: page.info.plot || (backend.movieLoading ? "" : qsTr("No synopsis for this movie."))
                        color: page.info.plot ? "#d4d4da" : win.muted
                        font.pixelSize: 15
                        lineHeight: 1.15
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                    }

                    GridLayout {
                        columns: 2
                        columnSpacing: 14
                        rowSpacing: 6
                        Layout.fillWidth: true
                        Layout.topMargin: 6

                        Label {
                            visible: !!page.info.director
                            text: qsTr("Director")
                            color: win.muted
                        }
                        Label {
                            visible: !!page.info.director
                            text: page.info.director || ""
                            color: win.ink
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                        Label {
                            visible: !!page.info.released
                            text: qsTr("Released")
                            color: win.muted
                        }
                        Label {
                            visible: !!page.info.released
                            text: page.info.released || ""
                            color: win.ink
                            Layout.fillWidth: true
                        }
                        Label {
                            visible: !!page.info.groupName
                            text: qsTr("Category")
                            color: win.muted
                        }
                        Label {
                            visible: !!page.info.groupName
                            text: page.info.groupName || ""
                            color: win.ink
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }
                }

                // What's playing keeps showing here while the sheet is open.
                Rectangle {
                    id: preview
                    visible: win.playingKey !== "" && !win.expanded && !win.compact
                    Layout.preferredWidth: 320
                    Layout.preferredHeight: 180
                    Layout.alignment: Qt.AlignTop
                    color: "#0b0b0d"
                    radius: theme.radius
                    clip: true
                }
            }

            ColumnLayout {
                visible: (page.info.cast || []).length > 0
                Layout.fillWidth: true
                spacing: 10
                Label {
                    text: qsTr("Cast")
                    color: win.accent
                    font.pixelSize: 12
                    font.bold: true
                    font.capitalization: Font.AllUppercase
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: (page.info.cast || []).slice(0, 20)
                        delegate: Rectangle {
                            required property string modelData
                            width: actor.implicitWidth + 24
                            height: actor.implicitHeight + 14
                            radius: height / 2 > theme.radius ? theme.radius : height / 2
                            color: win.raised
                            Label {
                                id: actor
                                anchors.centerIn: parent
                                text: parent.modelData
                                color: win.ink
                            }
                        }
                    }
                }
            }

            Label {
                visible: !win.touch
                text: qsTr("Enter: play · ← →: choose · F: favourite · D: download · Esc: back")
                color: win.muted
                font.pixelSize: 12
            }
        }
    }
}
