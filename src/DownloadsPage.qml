import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Movies and episodes kept on the device, to watch without a connection.
FocusScope {
    id: page

    // Progress updates the downloads many times a second; the list itself
    // only rebuilds when one is added or removed, so it keeps its place.
    property var keys: []
    function refreshKeys() {
        const fresh = backend.downloads.map(d => d.key)
        if (JSON.stringify(fresh) !== JSON.stringify(keys)) {
            const selected = list.currentIndex >= 0 ? keys[list.currentIndex] : ""
            keys = fresh
            list.currentIndex = Math.max(0, Math.min(fresh.indexOf(selected) >= 0 ? fresh.indexOf(selected) : list.currentIndex,
                                                     fresh.length - 1))
            if (fresh.length === 0)
                list.currentIndex = -1
            win.selectedKey = list.currentIndex >= 0 ? fresh[list.currentIndex] : ""
        }
    }
    Connections {
        target: backend
        function onDownloadsChanged() { page.refreshKeys() }
    }
    Component.onCompleted: refreshKeys()

    function open(key) {
        const d = backend.download(key)
        if (d.state === "done")
            win.activate(key, true)
        else if (d.state === "failed")
            backend.retryDownload(key)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: win.compact ? 10 : 16
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Label {
                visible: !win.compact
                text: win.sectionTitle("downloads")
                font.pixelSize: 22
                font.bold: true
                color: win.ink
                Layout.fillWidth: true
            }
            Label {
                text: (page.keys.length > 0 ? qsTr("%n items", "", page.keys.length) + " · " : "")
                      + qsTr("%1 free on this device").arg(backend.freeSpace)
                color: win.muted
                font.pixelSize: win.compact ? 13 : 14
                Layout.fillWidth: win.compact
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            focus: true
            clip: true
            model: page.keys
            spacing: 4
            highlightMoveDuration: 0
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: true
            ScrollBar.vertical: ScrollBar {}
            onCurrentIndexChanged: win.selectedKey = currentIndex >= 0 ? (page.keys[currentIndex] || "") : ""

            highlight: Rectangle {
                color: win.tint(list.activeFocus && !win.touch ? 0.22 : 0.0)
                radius: win.small
            }

            Keys.onReturnPressed: page.open(page.keys[currentIndex])
            Keys.onEnterPressed: page.open(page.keys[currentIndex])
            Keys.onDeletePressed: if (currentIndex >= 0) backend.removeDownload(page.keys[currentIndex])
            Keys.onLeftPressed: {}

            delegate: Item {
                id: row
                required property string modelData
                required property int index
                readonly property var d: (backend.downloads, backend.download(modelData))
                readonly property bool episode: d.kind === "episode"
                width: ListView.view.width
                height: win.compact ? 96 : 108

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        list.currentIndex = row.index
                        list.forceActiveFocus()
                        if (win.touch)
                            page.open(row.modelData)
                    }
                    onDoubleClicked: if (!win.touch) page.open(row.modelData)
                    onPressAndHold: win.downloadMenuFor(row.modelData, more)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: row.episode ? (win.compact ? 112 : 136) : (win.compact ? 54 : 61)
                        Layout.preferredHeight: win.compact ? 80 : 92
                        color: win.raised
                        radius: win.small
                        clip: true
                        Image {
                            anchors.fill: parent
                            source: row.d.logo || ""
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 272
                        }
                        Rectangle {
                            visible: (row.d.watched || 0) > 0
                            anchors.bottom: parent.bottom
                            width: parent.width * (row.d.watched || 0)
                            height: 3
                            color: win.accent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        Label {
                            text: row.episode && row.d.seriesName ? row.d.seriesName : (row.d.name || "")
                            color: win.ink
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Label {
                            visible: row.episode
                            text: (row.d.season > 0 || row.d.episode > 0
                                   ? qsTr("S%1 E%2").arg(row.d.season).arg(row.d.episode) + " · " : "") + (row.d.name || "")
                            color: "#c4c4cc"
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        ProgressBar {
                            visible: row.d.state === "running" || row.d.state === "queued"
                            from: 0
                            to: 1
                            value: Math.max(0, row.d.progress)
                            indeterminate: row.d.state === "running" && row.d.progress < 0
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                        }
                        Label {
                            text: win.downloadStatus(row.d)
                            color: row.d.state === "failed" ? "#ff8a80" : win.muted
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    ToolButton {
                        id: more
                        text: "⋮"
                        font.pixelSize: 20
                        onClicked: win.downloadMenuFor(row.modelData, more)
                    }
                }
            }

            Label {
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 440)
                visible: list.count === 0
                text: qsTr("Nothing to watch offline yet. Open a movie or a series and choose Download to keep it on this device.")
                color: win.muted
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
        }

        Label {
            visible: !win.touch && list.count > 0
            text: qsTr("Enter: play · Del: delete the download")
            color: win.muted
            font.pixelSize: 12
        }
    }
}
