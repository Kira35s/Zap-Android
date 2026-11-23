import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

FocusScope {
    id: page

    function reselect() {
        grid.currentIndex = backend.entries.count > 0 ? 0 : -1
        grid.positionViewAtBeginning()
        win.selectedKey = backend.entries.keyAt(grid.currentIndex)
    }
    Connections {
        target: backend.entries
        function onModelReset() { page.reselect() }
    }
    Component.onCompleted: reselect()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: win.compact ? 8 : 16
        spacing: 10

        RowLayout {
            visible: !win.compact
            Layout.fillWidth: true
            Label {
                text: win.sectionTitle(backend.section)
                font.pixelSize: 22
                font.bold: true
                color: win.ink
                Layout.fillWidth: true
            }
            Label {
                text: qsTr("%n items", "", backend.entries.count)
                color: win.muted
                visible: backend.entries.count > 0
            }
        }

        // The provider's sections (New, Netflix, …) as a row of chips above the
        // posters, a quicker way in than the category column.
        ListView {
            id: chips
            visible: backend.categories.length > 1
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            orientation: ListView.Horizontal
            spacing: 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: backend.categories

            function syncIndex() {
                for (let i = 0; i < backend.categories.length; ++i)
                    if (backend.categories[i].id === backend.category) {
                        currentIndex = i
                        positionViewAtIndex(i, ListView.Contain)
                        return
                    }
                currentIndex = 0
                positionViewAtBeginning()
            }
            Connections {
                target: backend
                function onCategoriesChanged() { Qt.callLater(chips.syncIndex) }
                function onCategoryChanged() { Qt.callLater(chips.syncIndex) }
            }
            Component.onCompleted: syncIndex()

            delegate: ItemDelegate {
                id: chip
                required property var modelData
                readonly property bool current: modelData.id === backend.category
                height: ListView.view.height
                leftPadding: 14
                rightPadding: 14
                // The keyboard stays on the posters.
                focusPolicy: Qt.NoFocus
                onClicked: backend.category = modelData.id
                background: Rectangle {
                    radius: height / 2
                    color: chip.current ? win.tint(0.24) : win.raised
                    border.width: chip.current ? 1 : 0
                    border.color: win.accent
                }
                contentItem: Label {
                    text: chip.modelData.name
                    color: chip.current ? win.ink : "#b9b9c2"
                    font.bold: chip.current
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            focus: true
            clip: true
            model: backend.entries
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 0
            keyNavigationEnabled: true
            ScrollBar.vertical: ScrollBar {}

            readonly property int columns: Math.max(1, Math.floor(width / (win.compact ? 120 : 168)))
            cellWidth: Math.floor(width / columns)
            cellHeight: Math.round((cellWidth - 16) * 1.5) + 52

            onCurrentIndexChanged: win.selectedKey = backend.entries.keyAt(currentIndex)
            onActiveFocusChanged: if (activeFocus) win.selectedKey = backend.entries.keyAt(currentIndex)

            Keys.onReturnPressed: win.activate(backend.entries.keyAt(currentIndex))
            Keys.onEnterPressed: win.activate(backend.entries.keyAt(currentIndex))
            Keys.onLeftPressed: event => {
                if (currentIndex % columns === 0)
                    win.focusCategories()
                else
                    moveCurrentIndexLeft()
            }

            delegate: Item {
                id: cell
                required property int index
                required property string key
                required property string name
                required property string logo
                required property string year
                required property string rating
                required property bool favorite
                required property real progress
                readonly property bool current: GridView.isCurrentItem

                width: grid.cellWidth
                height: grid.cellHeight

                Rectangle {
                    id: poster
                    x: 8
                    y: 8
                    width: parent.width - 16
                    height: Math.round(width * 1.5)
                    color: win.raised
                    radius: win.small
                    border.width: cell.current && grid.activeFocus ? 3 : 0
                    border.color: win.accent
                    clip: true

                    Image {
                        id: art
                        anchors.fill: parent
                        anchors.margins: poster.border.width
                        source: cell.logo
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 320
                    }
                    Label {
                        anchors.fill: parent
                        anchors.margins: 12
                        visible: art.status !== Image.Ready
                        text: cell.name
                        color: win.muted
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        visible: cell.favorite
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 8
                        width: 26
                        height: 26
                        radius: 13
                        color: "#cc000000"
                        Label {
                            anchors.centerIn: parent
                            text: "★"
                            color: win.accent
                        }
                    }
                    Rectangle {
                        visible: cell.progress > 0
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.margins: poster.border.width
                        width: (parent.width - 2 * poster.border.width) * cell.progress
                        height: 4
                        color: win.accent
                    }
                }

                Label {
                    anchors.top: poster.bottom
                    anchors.topMargin: 6
                    x: 8
                    width: parent.width - 16
                    text: cell.name
                    color: cell.current ? win.ink : "#b9b9c2"
                    font.bold: cell.current
                    elide: Text.ElideRight
                }
                Label {
                    anchors.top: poster.bottom
                    anchors.topMargin: 26
                    x: 8
                    width: parent.width - 16
                    text: [cell.year, cell.rating ? "★ " + cell.rating : ""].filter(s => s).join(" · ")
                    color: win.muted
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        grid.currentIndex = cell.index
                        grid.forceActiveFocus()
                        if (win.touch)
                            win.activate(cell.key)
                    }
                    onDoubleClicked: if (!win.touch) win.activate(cell.key)
                    onPressAndHold: if (win.touch) win.toggleFavorite(cell.key)
                }
            }

            Label {
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 420)
                visible: grid.count === 0
                text: backend.sources.length === 0
                      ? (win.touch ? qsTr("No sources yet. Open Sources from the menu to add an Xtream Codes account or an M3U playlist.")
                                 : qsTr("No sources yet. Press 7 to add an Xtream Codes account or an M3U playlist."))
                      : backend.busy ? qsTr("Loading…") : qsTr("Nothing in this category.")
                color: win.muted
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
