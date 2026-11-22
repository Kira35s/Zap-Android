import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Rectangle {
    id: pane
    color: win.panel

    property alias videoHost: host
    readonly property var info: win.selectedKey ? (backend.revision, backend.entry(win.selectedKey)) : ({})
    readonly property bool isLive: info.kind === "live"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        Rectangle {
            id: host
            Layout.fillWidth: true
            Layout.preferredHeight: Math.round(width * 9 / 16)
            color: "#0b0b0d"
            radius: theme.radius
            clip: true

            Image {
                id: art
                anchors.fill: parent
                anchors.margins: pane.isLive ? 40 : 0
                source: pane.info.logo || ""
                asynchronous: true
                fillMode: pane.isLive ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                sourceSize.width: 640
                opacity: pane.isLive ? 1 : 0.55
            }
            Label {
                anchors.centerIn: parent
                visible: art.status !== Image.Ready
                text: pane.info.name ? (win.touch ? qsTr("Tap to play") : qsTr("Enter to play")) : qsTr("Nothing selected")
                color: win.muted
            }
        }

        Label {
            text: (pane.isLive && pane.info.number > 0 ? pane.info.number + "  " : "") + (pane.info.name || "")
            color: win.ink
            font.pixelSize: 20
            font.bold: true
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        Label {
            text: [pane.info.seriesName, pane.info.groupName, pane.info.year,
                   pane.info.rating ? "★ " + pane.info.rating : "",
                   pane.info.favorite ? qsTr("In favourites") : ""].filter(s => s).join(" · ")
            color: win.muted
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            visible: text !== ""
        }

        // Live: now and next.
        ColumnLayout {
            visible: pane.isLive
            Layout.fillWidth: true
            spacing: 4
            Label {
                text: qsTr("Now")
                color: win.accent
                font.pixelSize: 12
                font.bold: true
                font.capitalization: Font.AllUppercase
                Layout.topMargin: 6
            }
            Label {
                text: pane.info.nowTitle || qsTr("No programme information")
                color: win.ink
                font.bold: true
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            Label {
                visible: !!pane.info.nowStart
                text: pane.info.nowStart ? win.clock(pane.info.nowStart) + " – " + win.clock(pane.info.nowStop) : ""
                color: win.muted
            }
            ProgressBar {
                visible: !!pane.info.nowStart
                from: 0
                to: 1
                value: pane.info.nowStop > pane.info.nowStart
                       ? (backend.now - pane.info.nowStart) / (pane.info.nowStop - pane.info.nowStart) : 0
                Layout.fillWidth: true
            }
            Label {
                text: pane.info.nowDesc || ""
                visible: text !== ""
                color: "#c4c4cc"
                wrapMode: Text.Wrap
                maximumLineCount: 6
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Label {
                visible: !!pane.info.nextTitle
                text: qsTr("Next")
                color: win.accent
                font.pixelSize: 12
                font.bold: true
                font.capitalization: Font.AllUppercase
                Layout.topMargin: 8
            }
            Label {
                visible: !!pane.info.nextTitle
                text: pane.info.nextTitle ? win.clock(pane.info.nextStart) + "  " + pane.info.nextTitle : ""
                color: win.ink
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }

        Label {
            visible: !pane.isLive && !!pane.info.plot
            text: pane.info.plot || ""
            color: "#c4c4cc"
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        Label {
            visible: pane.info.position > 0
            text: qsTr("Resumes at %1").arg(win.duration(pane.info.position || 0))
            color: win.accent
        }

        Item { Layout.fillHeight: true }

        Label {
            visible: !!pane.info.kind
            text: pane.info.kind === "live" ? qsTr("Enter: watch · Enter again: full screen · F: favourite")
                : pane.info.kind === "series" ? qsTr("Enter: episodes · F: favourite")
                : backend.section === "continue" ? qsTr("Enter: resume · Del: remove from the list")
                : pane.info.kind === "movie" ? qsTr("Enter: movie details · F: favourite · O: open in mpv")
                : qsTr("Enter: play · F: favourite · O: open in mpv")
            color: win.muted
            font.pixelSize: 12
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
    }
}
