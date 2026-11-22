import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

FocusScope {
    id: page

    // Esc in the search field clears it first, then hands focus to the results.
    function back() {
        if (!field.activeFocus)
            return false
        if (field.text)
            backend.query = ""
        else
            list.forceActiveFocus()
        return true
    }

    function focusSearch() {
        field.forceActiveFocus()
        field.selectAll()
    }

    readonly property string emptyText: {
        if (backend.sources.length === 0)
            return (win.touch ? qsTr("No sources yet. Open Sources from the menu to add an Xtream Codes account or an M3U playlist.")
                                 : qsTr("No sources yet. Press 7 to add an Xtream Codes account or an M3U playlist."))
        if (backend.busy && backend.section !== "favorites" && backend.section !== "continue")
            return qsTr("Loading…")
        switch (backend.section) {
        case "favorites": return win.touch ? qsTr("Press and hold a channel, a movie or a series to keep it here.")
                                           : qsTr("Press F on a channel, a movie or a series to keep it here.")
        case "continue": return qsTr("Movies and episodes you start watching show up here.")
        case "search":
            return backend.query.trim().length < 2 ? qsTr("Type at least two letters.")
                                                   : qsTr("Nothing matches “%1”.").arg(backend.query.trim())
        }
        return qsTr("Nothing in this category.")
    }

    // Keep the selection on the channel that's playing when the list is rebuilt.
    function reselect() {
        const index = backend.entries.indexOf(win.playingKey)
        list.currentIndex = index >= 0 ? index : (backend.entries.count > 0 ? 0 : -1)
        list.positionViewAtIndex(Math.max(0, list.currentIndex), ListView.Center)
        win.selectedKey = backend.entries.keyAt(list.currentIndex)
    }
    Connections {
        target: backend.entries
        function onModelReset() { page.reselect() }
    }
    Component.onCompleted: {
        reselect()
        if (backend.section === "search")
            Qt.callLater(focusSearch)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: win.compact ? 8 : 16
        spacing: 10

        // The phone's top bar already says where we are.
        RowLayout {
            visible: !win.compact
            Layout.fillWidth: true
            Label {
                text: win.sectionTitle(backend.section)
                font.pixelSize: 22
                font.bold: true
                color: win.ink
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Label {
                text: qsTr("%n items", "", backend.entries.count)
                color: win.muted
                visible: backend.entries.count > 0
            }
        }

        TextField {

            Material.roundedScale: theme.radius
            id: field
            visible: backend.section === "search"
            Layout.fillWidth: true
            placeholderText: qsTr("Search channels, movies and series")
            text: backend.query
            onTextEdited: backend.query = text
            Keys.onDownPressed: list.forceActiveFocus()
            Keys.onReturnPressed: list.forceActiveFocus()
            Keys.onEnterPressed: list.forceActiveFocus()
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            focus: true
            clip: true
            model: backend.entries
            highlightMoveDuration: 0
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: true
            ScrollBar.vertical: ScrollBar {}
            onCurrentIndexChanged: win.selectedKey = backend.entries.keyAt(currentIndex)
            onActiveFocusChanged: if (activeFocus) win.selectedKey = backend.entries.keyAt(currentIndex)

            highlight: Rectangle {
                color: win.tint(list.activeFocus ? 0.22 : 0.09)
                radius: win.small
            }

            Keys.onReturnPressed: win.activate(backend.entries.keyAt(currentIndex))
            Keys.onEnterPressed: win.activate(backend.entries.keyAt(currentIndex))
            Keys.onLeftPressed: win.focusCategories()
            Keys.onUpPressed: event => {
                if (currentIndex <= 0 && field.visible)
                    field.forceActiveFocus()
                else
                    decrementCurrentIndex()
            }

            delegate: Item {
                id: row
                required property int index
                required property string key
                required property string kind
                required property string name
                required property string logo
                required property int number
                required property string groupName
                required property string plot
                required property string year
                required property int season
                required property int episode
                required property bool favorite
                required property real progress
                required property string nowTitle
                required property real nowStart
                required property real nowStop
                required property string nextTitle
                required property string seriesName
                required property real nextStart

                width: ListView.view.width
                height: 66

                readonly property real liveProgress: nowStop > nowStart
                    ? Math.max(0, Math.min(1, (backend.now - nowStart) / (nowStop - nowStart))) : 0
                readonly property string kindLabel: kind === "live" ? qsTr("Channel")
                    : kind === "movie" ? qsTr("Movie") : kind === "series" ? qsTr("TV series") : qsTr("Episode")

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        list.currentIndex = row.index
                        list.forceActiveFocus()
                        if (win.touch)
                            win.activate(row.key)
                    }
                    onDoubleClicked: if (!win.touch) win.activate(row.key)
                    onPressAndHold: if (win.touch) win.toggleFavorite(row.key)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 12
                    spacing: 12

                    Label {
                        visible: row.kind === "live" && backend.section === "live"
                        text: row.number > 0 ? row.number : ""
                        color: win.muted
                        horizontalAlignment: Text.AlignRight
                        Layout.preferredWidth: 34
                    }

                    Rectangle {
                        Layout.preferredWidth: row.kind === "live" ? 76 : 44
                        Layout.preferredHeight: row.kind === "live" ? 46 : 60
                        color: row.kind === "live" ? "#202026" : "#18181d"
                        radius: win.small
                        clip: true
                        Image {
                            id: logoImage
                            anchors.fill: parent
                            anchors.margins: row.kind === "live" ? 6 : 0
                            source: row.logo
                            asynchronous: true
                            fillMode: row.kind === "live" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                            sourceSize.height: 120
                        }
                        Label {
                            anchors.centerIn: parent
                            visible: logoImage.status !== Image.Ready
                            text: row.name.trim().slice(0, 2).toUpperCase()
                            color: win.muted
                            font.bold: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Label {
                                text: "▶"
                                visible: row.key === win.playingKey
                                color: win.accent
                                font.pixelSize: 11
                            }
                            Label {
                                text: row.kind === "episode" && row.episode > 0
                                      ? qsTr("S%1 E%2 · %3").arg(row.season).arg(row.episode).arg(row.name) : row.name
                                color: win.ink
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Label {
                                text: "★"
                                visible: row.favorite
                                color: win.accent
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: win.muted
                            font.pixelSize: 13
                            text: row.kind === "live"
                                ? (row.nowTitle ? win.clock(row.nowStart) + "  " + row.nowTitle : qsTr("No programme information"))
                                : row.kind === "episode" ? [row.kindLabel, row.seriesName].filter(s => s).join(" · ")
                                : [row.kindLabel, row.groupName, row.year].filter(s => s).join(" · ")
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 3
                            radius: 1
                            color: "#2a2a31"
                            visible: row.kind === "live" ? row.nowTitle !== "" : row.progress > 0
                            Rectangle {
                                width: parent.width * (row.kind === "live" ? row.liveProgress : row.progress)
                                height: parent.height
                                radius: 1
                                color: win.accent
                            }
                        }
                    }
                }
            }

            Label {
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 420)
                visible: list.count === 0
                text: page.emptyText
                color: win.muted
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
