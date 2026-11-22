import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Rectangle {
    id: rail
    color: "#111114"

    readonly property var sections: [
        { id: "live", label: qsTr("Live TV"), key: "1" },
        { id: "guide", label: qsTr("TV guide"), key: "2" },
        { id: "movies", label: qsTr("Movies"), key: "3" },
        { id: "series", label: qsTr("Series"), key: "4" },
        { id: "favorites", label: qsTr("Favourites"), key: "5" },
        { id: "continue", label: qsTr("Continue watching"), key: "6" },
        { id: "search", label: qsTr("Search"), key: "/" },
        { id: "sources", label: qsTr("Sources"), key: "7" },
        { id: "settings", label: qsTr("Settings"), key: "8" }
    ]

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 2

        RowLayout {
            Layout.bottomMargin: 18
            Layout.leftMargin: 6
            spacing: 8
            Image {
                source: "qrc:/zap.svg"
                sourceSize.width: 28
                sourceSize.height: 28
            }
            Label {
                text: "Zap"
                font.pixelSize: 22
                font.bold: true
                color: win.ink
            }
        }

        Repeater {
            model: rail.sections
            delegate: ItemDelegate {
                id: item
                required property var modelData
                readonly property bool current: backend.section === modelData.id
                Layout.fillWidth: true
                implicitHeight: win.touch ? 50 : 42
                onClicked: {
                    win.closeDrawers()
                    modelData.id === "search" ? win.startSearch() : win.goSection(modelData.id)
                }
                background: Rectangle {
                    radius: win.small
                    color: item.current ? win.tint(0.18) : item.hovered ? "#1a1a1f" : "transparent"
                    Rectangle {
                        visible: item.current
                        width: 3
                        height: parent.height - 14
                        anchors.verticalCenter: parent.verticalCenter
                        color: win.accent
                        radius: 1
                    }
                }
                contentItem: RowLayout {
                    spacing: 8
                    Label {
                        text: item.modelData.label
                        color: item.current ? win.ink : "#b9b9c2"
                        font.bold: item.current
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Label {
                        visible: !win.touch
                        text: item.modelData.key
                        color: win.muted
                        font.pixelSize: 12
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            visible: backend.busy
            Layout.fillWidth: true
            spacing: 8
            BusyIndicator {
                running: backend.busy
                implicitWidth: 24
                implicitHeight: 24
            }
            Label {
                text: backend.status
                color: win.muted
                font.pixelSize: 12
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }

        Label {
            visible: !win.touch
            text: qsTr("? shows every shortcut")
            color: win.muted
            font.pixelSize: 12
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Layout.topMargin: 6
        }
    }
}
