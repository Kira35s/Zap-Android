import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Rectangle {
    id: overlay
    color: "#e6000000"

    readonly property var shortcuts: [
        ["1 – 8", qsTr("Live TV, TV guide, movies, series, favourites, continue watching, sources, settings")],
        ["/", qsTr("Search")],
        ["↑ ↓ ← →", qsTr("Move; Left goes back to the categories")],
        [qsTr("Enter"), qsTr("Play, or open a movie's sheet or a series; on a playing channel, full screen")],
        [qsTr("Esc"), qsTr("Back: leave full screen, close the sheet or the series, clear the search")],
        [qsTr("Space"), qsTr("Pause and resume")],
        ["↑ ↓  " + qsTr("PgUp PgDn"), qsTr("Previous and next channel while watching")],
        ["← →  Shift+← →", qsTr("Skip 10 seconds or 1 minute in a movie or an episode")],
        ["F", qsTr("Add to or remove from favourites")],
        ["9", qsTr("Downloads: movies and episodes kept for watching offline")],
        ["D", qsTr("Download a movie or an episode for watching offline")],
        ["A", qsTr("Change the audio language while watching")],
        ["S", qsTr("Subtitles: off, or the next language")],
        ["M", qsTr("Mute")],
        ["+ −", qsTr("Volume")],
        ["X", qsTr("Stop playing")],
        ["O", qsTr("Open in mpv")],
        ["R", qsTr("Refresh the lists and the TV guide")],
        [qsTr("Del"), qsTr("Remove from continue watching")],
        ["F11", qsTr("Full-screen window")],
        ["?", qsTr("Show or hide this help")],
        ["Q", qsTr("Quit")]
    ]

    MouseArea {
        anchors.fill: parent
        onClicked: win.helpVisible = false
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 760)
        height: Math.min(parent.height - 48, content.implicitHeight + 56)
        color: win.panel
        radius: theme.radius

        Flickable {
            anchors.fill: parent
            anchors.margins: 28
            contentHeight: content.implicitHeight
            clip: true

            ColumnLayout {
                id: content
                width: parent.width
                spacing: 14

                Label {
                    text: qsTr("Keyboard shortcuts")
                    font.pixelSize: 22
                    font.bold: true
                    color: win.ink
                }

                GridLayout {
                    columns: 2
                    columnSpacing: 24
                    rowSpacing: 10
                    Layout.fillWidth: true

                    Repeater {
                        model: overlay.shortcuts
                        delegate: Label {
                            required property var modelData
                            required property int index
                            Layout.row: index
                            Layout.column: 0
                            text: modelData[0]
                            color: win.accent
                            font.bold: true
                        }
                    }
                    Repeater {
                        model: overlay.shortcuts
                        delegate: Label {
                            required property var modelData
                            required property int index
                            Layout.row: index
                            Layout.column: 1
                            Layout.fillWidth: true
                            text: modelData[1]
                            color: win.ink
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }
    }
}
