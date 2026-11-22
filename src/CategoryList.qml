import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Rectangle {
    id: pane
    color: win.panel

    function focusList() { list.forceActiveFocus() }

    function syncIndex() {
        for (let i = 0; i < backend.categories.length; ++i)
            if (backend.categories[i].id === backend.category) {
                list.currentIndex = i
                return
            }
        list.currentIndex = 0
    }

    Connections {
        target: backend
        function onCategoriesChanged() { pane.syncIndex() }
        function onCategoryChanged() { pane.syncIndex() }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 16
        spacing: 8

        Label {
            text: qsTr("Categories")
            color: win.muted
            font.pixelSize: 12
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1
            Layout.leftMargin: 16
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: backend.categories
            highlightMoveDuration: 0
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: true
            ScrollBar.vertical: ScrollBar {}
            Component.onCompleted: pane.syncIndex()

            // Moving through categories with the keyboard shows each one straight away.
            onCurrentIndexChanged: {
                if (activeFocus && currentIndex >= 0 && currentIndex < backend.categories.length)
                    backend.category = backend.categories[currentIndex].id
            }

            highlight: Rectangle {
                color: win.tint(list.activeFocus ? 0.24 : 0.1)
                radius: win.small
            }

            delegate: ItemDelegate {
                id: row
                required property var modelData
                required property int index
                width: ListView.view.width
                implicitHeight: win.touch ? 48 : 40
                background: null
                onClicked: {
                    list.currentIndex = index
                    backend.category = modelData.id
                    win.closeDrawers()
                    win.restoreFocus()
                }
                contentItem: RowLayout {
                    spacing: 8
                    Label {
                        text: row.modelData.name
                        color: row.modelData.id === backend.category ? win.ink : "#b9b9c2"
                        font.bold: row.modelData.id === backend.category
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Label {
                        text: row.modelData.count.toLocaleString(Qt.locale(), 'f', 0)
                        color: win.muted
                        font.pixelSize: 12
                    }
                }
            }

            Keys.onRightPressed: win.restoreFocus()
            Keys.onReturnPressed: win.restoreFocus()
            Keys.onEnterPressed: win.restoreFocus()
        }
    }
}
