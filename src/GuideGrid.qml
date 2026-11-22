import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// The classic TV guide: channels down the side, time across the top. Left and
// Right walk the selected channel's programmes; past the current one, Left
// goes back to the categories.
FocusScope {
    id: guide

    property alias videoHost: preview
    readonly property int channelWidth: win.compact ? 112 : 240
    readonly property real pxPerMinute: win.compact ? 4 : 7
    readonly property int rowHeight: 58
    readonly property int halfHour: 1800

    property real viewStart: 0
    property real cursor: 0
    readonly property real span: Math.max(halfHour, Math.floor(timeline.width / pxPerMinute * 60))
    readonly property string currentKey: rows.currentIndex >= 0 ? backend.entries.keyAt(rows.currentIndex) : ""
    readonly property var currentEntry: currentKey ? (backend.revision, backend.entry(currentKey)) : ({})
    readonly property var selected: currentKey ? (backend.revision, backend.programmeAt(currentKey, cursor)) : ({})

    function floorHalfHour(t) { return t - t % halfHour }
    function resetTime() {
        cursor = backend.now
        viewStart = floorHalfHour(backend.now)
    }
    function ensureVisible() {
        if (cursor < viewStart)
            viewStart = floorHalfHour(cursor)
        else if (cursor > viewStart + span - halfHour)
            viewStart = Math.max(floorHalfHour(backend.now), floorHalfHour(cursor) - halfHour)
    }
    function step(direction) {
        const current = backend.programmeAt(currentKey, cursor)
        if (direction < 0) {
            const target = (current.start || cursor - halfHour) - 1
            if (target < backend.now) {
                if (cursor > backend.now) {
                    cursor = backend.now
                    ensureVisible()
                } else {
                    win.focusCategories()
                }
                return
            }
            const previous = backend.programmeAt(currentKey, target)
            cursor = previous.start ? Math.max(previous.start, backend.now) : floorHalfHour(target)
        } else {
            const next = current.stop || floorHalfHour(cursor) + halfHour
            if (next > backend.now + 4 * 86400)
                return
            cursor = next
        }
        ensureVisible()
    }

    function reselect() {
        const index = backend.entries.indexOf(win.playingKey)
        rows.currentIndex = index >= 0 ? index : (backend.entries.count > 0 ? 0 : -1)
        rows.positionViewAtIndex(Math.max(0, rows.currentIndex), ListView.Center)
    }
    Connections {
        target: backend.entries
        function onModelReset() { guide.reselect() }
    }
    Component.onCompleted: {
        resetTime()
        reselect()
    }
    onCurrentKeyChanged: win.selectedKey = currentKey

    // Touch has no arrow keys to walk the timeline, so these buttons do.
    function shift(hours) {
        viewStart = Math.max(floorHalfHour(backend.now), viewStart + hours * 3600)
        cursor = Math.max(cursor, viewStart)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: win.compact ? 8 : 16
        spacing: win.compact ? 6 : 12

        // Explicit geometry: the preview's width follows its height, which
        // inside nested layouts would feed back into the page's implicit size.
        Item {
            id: top
            Layout.fillWidth: true
            Layout.preferredHeight: Math.round(guide.height * (win.compact ? 0.2 : 0.34))

            // A phone plays full screen, so there's no preview to keep room for.
            Rectangle {
                id: preview
                visible: !win.compact
                width: win.compact ? 0 : Math.min(Math.round(top.height * 16 / 9), Math.round(top.width * 0.55))
                height: Math.round(width * 9 / 16)
                color: "black"
                radius: theme.radius
                clip: true
                Label {
                    anchors.centerIn: parent
                    width: parent.width - 32
                    visible: win.playingKey === ""
                    text: qsTr("Enter plays the selected channel")
                    color: win.muted
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Column {
                anchors.left: preview.right
                anchors.leftMargin: win.compact ? 0 : 18
                anchors.right: parent.right
                height: top.height
                spacing: 6
                clip: true
                Label {
                    width: parent.width
                    text: guide.currentEntry.name || ""
                    color: win.accent
                    font.bold: true
                    elide: Text.ElideRight
                }
                Label {
                    width: parent.width
                    text: guide.selected.title || qsTr("No programme information")
                    color: win.ink
                    font.pixelSize: win.compact ? 18 : 24
                    font.bold: true
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                Label {
                    width: parent.width
                    visible: !!guide.selected.start
                    text: guide.selected.start
                          ? win.day(guide.selected.start) + " · " + win.clock(guide.selected.start) + " – " + win.clock(guide.selected.stop)
                          : ""
                    color: win.muted
                    elide: Text.ElideRight
                }
                Label {
                    width: parent.width
                    text: guide.selected.desc || ""
                    color: "#c4c4cc"
                    wrapMode: Text.Wrap
                    maximumLineCount: 5
                    elide: Text.ElideRight
                }
            }
        }

        RowLayout {
            visible: win.touch
            Layout.fillWidth: true
            spacing: 4
            ToolButton {
                icon.source: "qrc:/icons/rewind.svg"
                icon.color: win.ink
                enabled: guide.viewStart > guide.floorHalfHour(backend.now)
                onClicked: guide.shift(-1)
            }
            Button {
                text: qsTr("Now")
                flat: true
                Material.roundedScale: theme.radius
                onClicked: guide.resetTime()
            }
            ToolButton {
                icon.source: "qrc:/icons/forward.svg"
                icon.color: win.ink
                onClicked: guide.shift(1)
            }
            Item { Layout.fillWidth: true }
        }

        Item {
            id: gridArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
                id: header
                width: parent.width
                height: 30

                Label {
                    width: guide.channelWidth - 12
                    text: { const d = win.day(guide.viewStart); return d.charAt(0).toUpperCase() + d.slice(1) }
                    color: win.muted
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item {
                    id: timeline
                    x: guide.channelWidth
                    width: parent.width - guide.channelWidth
                    height: parent.height
                    clip: true
                    Repeater {
                        model: Math.ceil(guide.span / guide.halfHour) + 1
                        delegate: Label {
                            required property int index
                            x: index * 30 * guide.pxPerMinute + 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.clock(guide.viewStart + index * guide.halfHour)
                            color: win.muted
                            font.pixelSize: 13
                        }
                    }
                }
            }

            ListView {
                id: rows
                anchors.top: header.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                focus: true
                clip: true
                model: backend.entries
                highlightMoveDuration: 0
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: true
                ScrollBar.vertical: ScrollBar {}

                Keys.onLeftPressed: guide.step(-1)
                Keys.onRightPressed: guide.step(1)
                Keys.onReturnPressed: win.activate(guide.currentKey)
                Keys.onEnterPressed: win.activate(guide.currentKey)

                WheelHandler {
                    acceptedModifiers: Qt.ShiftModifier
                    onWheel: event => {
                        guide.viewStart = Math.max(guide.floorHalfHour(backend.now),
                                                   guide.viewStart + (event.angleDelta.y < 0 ? 1 : -1) * guide.halfHour)
                    }
                }

                delegate: Item {
                    id: row
                    required property int index
                    required property string key
                    required property string name
                    required property string logo
                    required property int number
                    readonly property bool current: ListView.isCurrentItem
                    width: ListView.view.width
                    height: guide.rowHeight

                    Rectangle {
                        width: guide.channelWidth - 6
                        height: parent.height - 4
                        radius: win.small
                        color: row.current ? win.tint(rows.activeFocus ? 0.24 : 0.12) : win.raised
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8
                            Label {
                                visible: !win.compact
                                text: row.number > 0 ? row.number : ""
                                color: win.muted
                                font.pixelSize: 12
                                Layout.preferredWidth: 28
                                horizontalAlignment: Text.AlignRight
                            }
                            Image {
                                source: row.logo
                                asynchronous: true
                                fillMode: Image.PreserveAspectFit
                                sourceSize.height: 64
                                Layout.preferredWidth: win.compact ? 36 : 48
                                Layout.preferredHeight: 32
                            }
                            Label {
                                text: (row.key === win.playingKey ? "▶ " : "") + row.name
                                font.pixelSize: win.compact ? 12 : 14
                                wrapMode: win.compact ? Text.Wrap : Text.NoWrap
                                maximumLineCount: 2
                                color: win.ink
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                rows.currentIndex = row.index
                                rows.forceActiveFocus()
                                if (win.touch)
                                    win.activate(row.key)
                            }
                            onDoubleClicked: if (!win.touch) win.activate(row.key)
                        }
                    }

                    Item {
                        id: lane
                        x: guide.channelWidth
                        width: parent.width - guide.channelWidth
                        height: parent.height - 4
                        clip: true
                        readonly property var programmes: (backend.revision,
                            backend.programmes(row.key, guide.viewStart, guide.viewStart + guide.span))

                        Repeater {
                            model: lane.programmes
                            delegate: Rectangle {
                                id: block
                                required property var modelData
                                readonly property bool chosen: row.current && modelData.start <= guide.cursor && guide.cursor < modelData.stop
                                readonly property bool past: modelData.stop <= backend.now
                                readonly property bool airing: modelData.start <= backend.now && !past
                                x: Math.max(0, (modelData.start - guide.viewStart) / 60 * guide.pxPerMinute)
                                width: Math.max(2, (Math.min(modelData.stop, guide.viewStart + guide.span)
                                                    - Math.max(modelData.start, guide.viewStart)) / 60 * guide.pxPerMinute - 3)
                                height: lane.height
                                radius: win.small
                                color: chosen ? (rows.activeFocus ? win.accent : win.tint(0.45))
                                     : airing ? "#25252c" : past ? "#141417" : win.raised
                                Label {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 6
                                    text: block.modelData.title
                                    color: block.chosen && rows.activeFocus ? theme.accentForeground
                                         : block.past ? win.muted : win.ink
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                    maximumLineCount: 1
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    // On touch, the first tap shows the programme, a second on it plays.
                                    onClicked: {
                                        if (win.touch && block.chosen && block.airing) {
                                            win.activate(row.key)
                                            return
                                        }
                                        rows.currentIndex = row.index
                                        guide.cursor = Math.max(block.modelData.start, backend.now)
                                        rows.forceActiveFocus()
                                    }
                                    onDoubleClicked: if (!win.touch) win.activate(row.key)
                                }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: lane.programmes.length === 0
                            color: row.current ? win.tint(0.08) : "#16161a"
                            radius: win.small
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                x: 10
                                text: qsTr("No programme information")
                                color: win.muted
                            }
                        }
                    }
                }

                Label {
                    anchors.centerIn: parent
                    visible: rows.count === 0
                    text: backend.busy ? qsTr("Loading…") : qsTr("Nothing in this category.")
                    color: win.muted
                }
            }

            // Where "now" is on the timeline.
            Rectangle {
                readonly property real offset: (backend.now - guide.viewStart) / 60 * guide.pxPerMinute
                visible: offset >= 0 && offset <= timeline.width
                x: guide.channelWidth + offset - 1
                y: header.height - 6
                width: 2
                height: parent.height - y
                color: win.accent
                opacity: 0.85
            }
        }
    }
}
