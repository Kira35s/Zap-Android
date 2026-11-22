import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// On a phone the sections and categories live in drawers; this bar opens them,
// says where we are, and steps back out of a movie or a series.
ToolBar {
    id: bar
    Material.background: win.panel
    Material.foreground: win.ink
    Material.elevation: 0

    readonly property bool detail: backend.seriesOpen || backend.movieOpen
    readonly property string categoryName: {
        for (let i = 0; i < backend.categories.length; ++i)
            if (backend.categories[i].id === backend.category)
                return backend.categories[i].name
        return ""
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        ToolButton {
            icon.source: bar.detail ? "qrc:/icons/back.svg" : "qrc:/icons/menu.svg"
            icon.color: win.ink
            onClicked: bar.detail ? win.back() : navDrawer.open()
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Label {
                text: backend.movieOpen ? (backend.movie.name || "")
                    : backend.seriesOpen ? (backend.series.name || "")
                    : win.sectionTitle(backend.section)
                color: win.ink
                font.pixelSize: 18
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Label {
                visible: !bar.detail && text !== "" && backend.categories.length > 0
                text: bar.categoryName
                color: win.muted
                font.pixelSize: 12
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        BusyIndicator {
            running: backend.busy
            visible: running
            implicitWidth: 32
            implicitHeight: 32
        }
        ToolButton {
            visible: !bar.detail && backend.categories.length > 0
            icon.source: "qrc:/icons/categories.svg"
            icon.color: win.ink
            onClicked: categoryDrawer.open()
        }
        ToolButton {
            visible: !bar.detail && backend.section !== "search"
            icon.source: "qrc:/icons/search.svg"
            icon.color: win.ink
            onClicked: win.startSearch()
        }
    }
}
