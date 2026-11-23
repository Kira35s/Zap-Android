import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

FocusScope {
    id: page
    readonly property var info: (backend.revision, backend.series)

    function seasonIndex() {
        for (let i = 0; i < backend.seasons.length; ++i)
            if (backend.seasons[i].season === backend.season)
                return i
        return -1
    }
    function changeSeason(delta) {
        const i = seasonIndex() + delta
        if (i >= 0 && i < backend.seasons.length)
            backend.season = backend.seasons[i].season
    }
    function seasonName(number) {
        return number === 0 ? qsTr("Specials") : qsTr("Season %1").arg(number)
    }

    // Start on the episode watched last, else the first one.
    function reselect() {
        let index = backend.episodes.indexOf(win.playingKey)
        if (index < 0) {
            index = 0
            for (let i = 0; i < backend.episodes.count; ++i) {
                const e = backend.entry(backend.episodes.keyAt(i))
                if (e.progress > 0)
                    index = i
            }
        }
        episodes.currentIndex = backend.episodes.count > 0 ? index : -1
        episodes.positionViewAtIndex(Math.max(0, index), ListView.Center)
        win.selectedKey = backend.episodes.keyAt(episodes.currentIndex)
    }
    Connections {
        target: backend.episodes
        function onModelReset() { page.reselect() }
    }
    Component.onCompleted: reselect()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: win.compact ? 10 : 16
        spacing: win.compact ? 10 : 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 18

            Rectangle {
                Layout.preferredWidth: win.compact ? 90 : 130
                Layout.preferredHeight: win.compact ? 135 : 195
                Layout.alignment: Qt.AlignTop
                color: win.raised
                radius: win.small
                clip: true
                Image {
                    anchors.fill: parent
                    source: page.info.logo || ""
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 260
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 6
                Label {
                    text: (page.info.name || "") + (page.info.favorite ? "  ★" : "")
                    color: win.ink
                    font.pixelSize: win.compact ? 20 : 26
                    font.bold: true
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
                Label {
                    text: [page.info.year, page.info.genre, page.info.rating ? "★ " + page.info.rating : "",
                           qsTr("%n seasons", "", backend.seasons.length)].filter(s => s).join(" · ")
                    color: win.muted
                    visible: !backend.seriesLoading
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
                Label {
                    text: page.info.plot || ""
                    color: "#c4c4cc"
                    wrapMode: Text.Wrap
                    maximumLineCount: win.compact ? 3 : 4
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Label {
                    visible: !!page.info.director
                    text: qsTr("Director: %1").arg(page.info.director || "")
                    color: win.muted
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Label {
                    visible: (page.info.cast || []).length > 0
                    text: qsTr("With %1").arg((page.info.cast || []).slice(0, 8).join(", "))
                    color: win.muted
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Label {
                    visible: !win.touch
                    text: qsTr("← → or click: change season · ↑ ↓ choose an episode · Enter: play · D: download · Esc: back")
                    color: win.muted
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
        }

        ListView {
            id: seasonBar
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            orientation: ListView.Horizontal
            spacing: 6
            clip: true
            model: backend.seasons
            currentIndex: page.seasonIndex()
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
            delegate: Button {
                required property var modelData
                text: page.seasonName(modelData.season) + "  ·  " + modelData.count
                flat: modelData.season !== backend.season
                highlighted: modelData.season === backend.season
                Material.roundedScale: theme.radius
                onClicked: {
                    backend.season = modelData.season
                    episodes.forceActiveFocus()
                }
            }
        }

        ListView {
            id: episodes
            Layout.fillWidth: true
            Layout.fillHeight: true
            focus: true
            clip: true
            model: backend.episodes
            highlightMoveDuration: 0
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: true
            ScrollBar.vertical: ScrollBar {}
            onCurrentIndexChanged: win.selectedKey = backend.episodes.keyAt(currentIndex)
            onActiveFocusChanged: if (activeFocus) win.selectedKey = backend.episodes.keyAt(currentIndex)

            highlight: Rectangle {
                color: win.tint(episodes.activeFocus ? 0.22 : 0.09)
                radius: win.small
            }

            Keys.onReturnPressed: win.activate(backend.episodes.keyAt(currentIndex))
            Keys.onEnterPressed: win.activate(backend.episodes.keyAt(currentIndex))
            Keys.onLeftPressed: page.changeSeason(-1)
            Keys.onRightPressed: page.changeSeason(1)

            delegate: Item {
                id: row
                required property int index
                required property string key
                required property string name
                required property string logo
                required property string plot
                required property int episode
                required property real progress
                required property bool favorite
                width: ListView.view.width
                height: 78

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        episodes.currentIndex = row.index
                        episodes.forceActiveFocus()
                        if (win.touch)
                            win.activate(row.key)
                    }
                    onDoubleClicked: if (!win.touch) win.activate(row.key)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 12
                    Label {
                        text: row.episode > 0 ? row.episode : ""
                        color: win.muted
                        font.pixelSize: 18
                        horizontalAlignment: Text.AlignRight
                        Layout.preferredWidth: 30
                    }
                    Rectangle {
                        Layout.preferredWidth: win.compact ? 88 : 106
                        Layout.preferredHeight: win.compact ? 50 : 60
                        color: win.raised
                        radius: win.small
                        clip: true
                        Image {
                            anchors.fill: parent
                            source: row.logo
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 212
                        }
                        Rectangle {
                            visible: row.progress > 0
                            anchors.bottom: parent.bottom
                            width: parent.width * row.progress
                            height: 3
                            color: win.accent
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        Label {
                            text: (row.key === win.playingKey ? "▶ " : "") + row.name + (row.favorite ? "  ★" : "")
                            color: win.ink
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Label {
                            text: row.plot
                            visible: row.plot !== ""
                            color: win.muted
                            font.pixelSize: 13
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                    // Download for watching offline, or how far it's got.
                    ToolButton {
                        id: downloadButton
                        readonly property var d: (backend.downloads, backend.download(row.key))
                        visible: backend.canDownload(row.key)
                        text: win.downloadGlyph(d)
                        font.pixelSize: d.state === "running" ? 13 : 18
                        Material.foreground: d.state === "done" ? win.accent : d.state === "failed" ? "#ff8a80" : win.ink
                        focusPolicy: Qt.NoFocus
                        Layout.preferredWidth: 56
                        onClicked: win.downloadAction(row.key, downloadButton)
                    }
                }
            }

            BusyIndicator {
                anchors.centerIn: parent
                running: backend.seriesLoading
            }
            Label {
                anchors.centerIn: parent
                visible: !backend.seriesLoading && episodes.count === 0
                text: qsTr("No episodes found.")
                color: win.muted
            }
        }
    }
}
