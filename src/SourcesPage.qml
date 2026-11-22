import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

FocusScope {
    id: page

    property bool editing: false
    property string editingId: ""

    function edit(source) {
        editingId = source.id || ""
        xtream.checked = (source.type || "xtream") === "xtream"
        m3u.checked = !xtream.checked
        nameField.text = source.name || ""
        serverField.text = source.server || ""
        userField.text = source.username || ""
        passwordField.text = source.password || ""
        playlistField.text = source.playlist || ""
        epgField.text = source.epg || ""
        errorLabel.text = ""
        editing = true
        Qt.callLater(() => nameField.forceActiveFocus())
    }
    // Back on a phone closes the form, back to the list.
    function back() {
        if (!win.touch || !editing)
            return false
        editing = false
        list.forceActiveFocus()
        return true
    }
    function save() {
        const error = backend.saveSource({
            id: editingId,
            type: xtream.checked ? "xtream" : "m3u",
            name: nameField.text,
            server: serverField.text,
            username: userField.text,
            password: passwordField.text,
            playlist: playlistField.text,
            epg: epgField.text
        })
        errorLabel.text = error
        if (!error) {
            editing = false
            list.forceActiveFocus()
        }
    }

    Component.onCompleted: {
        if (backend.sources.length === 0)
            edit({})
        else
            list.forceActiveFocus()
    }

    // A phone shows the list or the form, not both.
    RowLayout {
        anchors.fill: parent
        anchors.margins: win.compact ? 10 : 16
        spacing: 24

        ColumnLayout {
            visible: !win.compact || !page.editing
            // Children that fill the width would otherwise make this column fill it too.
            Layout.fillWidth: win.compact
            Layout.preferredWidth: win.compact ? -1 : 300
            Layout.maximumWidth: win.compact ? -1 : 300
            Layout.fillHeight: true
            spacing: 10

            Label {
                visible: !win.compact
                text: qsTr("Sources")
                font.pixelSize: 22
                font.bold: true
                color: win.ink
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                focus: !page.editing
                clip: true
                model: backend.sources
                highlightMoveDuration: 0
                keyNavigationEnabled: true
                highlight: Rectangle { color: win.tint(list.activeFocus ? 0.22 : 0.09); radius: win.small }
                Keys.onReturnPressed: if (currentIndex >= 0) page.edit(backend.sources[currentIndex])
                Keys.onEnterPressed: if (currentIndex >= 0) page.edit(backend.sources[currentIndex])
                delegate: ItemDelegate {
                    id: sourceRow
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    background: null
                    onClicked: {
                        list.currentIndex = index
                        page.edit(modelData)
                    }
                    contentItem: ColumnLayout {
                        spacing: 2
                        Label {
                            text: sourceRow.modelData.name
                            color: win.ink
                            font.bold: sourceRow.modelData.id === page.editingId && page.editing
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Label {
                            text: sourceRow.modelData.type === "xtream" ? "Xtream Codes" : qsTr("M3U playlist")
                            color: win.muted
                            font.pixelSize: 12
                        }
                    }
                }
                Label {
                    anchors.centerIn: parent
                    width: parent.width - 24
                    visible: list.count === 0
                    text: qsTr("No sources yet.")
                    color: win.muted
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
            }

            Button {

                Material.roundedScale: theme.radius
                text: qsTr("Add a source")
                highlighted: true
                Material.foreground: theme.accentForeground
                Layout.fillWidth: true
                onClicked: page.edit({})
            }
            Button {
                Material.roundedScale: theme.radius
                text: qsTr("Refresh everything")
                flat: true
                enabled: backend.sources.length > 0 && !backend.busy
                Layout.fillWidth: true
                onClicked: backend.refresh()
            }
        }

        Rectangle {
            visible: !win.compact || page.editing
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: win.panel
            radius: theme.radius

            Label {
                anchors.centerIn: parent
                visible: !page.editing
                width: parent.width - 48
                text: qsTr("Pick a source to change it, or add a new one.\nZap reads Xtream Codes accounts and M3U playlists, with their XMLTV programme guide.")
                color: win.muted
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }

            Flickable {
                anchors.fill: parent
                anchors.margins: win.compact ? 14 : 24
                visible: page.editing
                contentHeight: form.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: form
                    width: Math.min(parent.width, 620)
                    spacing: 12

                    Label {
                        text: page.editingId ? qsTr("Edit the source") : qsTr("New source")
                        font.pixelSize: 20
                        font.bold: true
                        color: win.ink
                    }

                    RowLayout {
                        spacing: 12
                        RadioButton {
                            id: xtream
                            text: "Xtream Codes"
                            checked: true
                        }
                        RadioButton {
                            id: m3u
                            text: qsTr("M3U playlist")
                        }
                    }

                    TextField {

                        Material.roundedScale: theme.radius
                        id: nameField
                        placeholderText: qsTr("Name")
                        Layout.fillWidth: true
                    }
                    TextField {
                        Material.roundedScale: theme.radius
                        id: serverField
                        visible: xtream.checked
                        placeholderText: qsTr("Server (http://example.com:8080)")
                        inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                        Layout.fillWidth: true
                    }
                    GridLayout {
                        visible: xtream.checked
                        Layout.fillWidth: true
                        columns: win.compact ? 1 : 2
                        columnSpacing: 12
                        rowSpacing: 12
                        TextField {
                            Material.roundedScale: theme.radius
                            id: userField
                            placeholderText: qsTr("Username")
                            inputMethodHints: Qt.ImhNoAutoUppercase
                            Layout.fillWidth: true
                        }
                        TextField {
                            Material.roundedScale: theme.radius
                            id: passwordField
                            placeholderText: qsTr("Password")
                            echoMode: TextInput.Password
                            Layout.fillWidth: true
                        }
                    }
                    TextField {
                        Material.roundedScale: theme.radius
                        id: playlistField
                        visible: m3u.checked
                        placeholderText: qsTr("Playlist address or file path")
                        inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                        Layout.fillWidth: true
                    }
                    TextField {
                        Material.roundedScale: theme.radius
                        id: epgField
                        placeholderText: xtream.checked ? qsTr("TV guide (XMLTV) address, optional: the server's own is used otherwise")
                                                        : qsTr("TV guide (XMLTV) address, optional: the playlist's own is used otherwise")
                        inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                        Layout.fillWidth: true
                    }

                    Label {
                        id: errorLabel
                        visible: text !== ""
                        color: "#ff7b7b"
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        spacing: 10
                        Button {
                            Material.roundedScale: theme.radius
                            text: qsTr("Save")
                            highlighted: true
                            Material.foreground: theme.accentForeground
                            onClicked: page.save()
                        }
                        Button {
                            Material.roundedScale: theme.radius
                            text: qsTr("Cancel")
                            flat: true
                            onClicked: {
                                page.editing = false
                                list.forceActiveFocus()
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Button {
                            Material.roundedScale: theme.radius
                            visible: page.editingId !== ""
                            text: qsTr("Delete")
                            flat: true
                            Material.foreground: "#ff7b7b"
                            onClicked: confirm.open()
                        }
                    }

                    Label {
                        text: win.android ? qsTr("Passwords stay on this device, in storage only Zap can read.")
                                          : qsTr("Passwords are kept in ~/.config/zap/sources.json, readable only by you.")
                        color: win.muted
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                    }
                }
            }

            Keys.onReturnPressed: page.save()
            Keys.onEnterPressed: page.save()
        }
    }

    Dialog {
        id: confirm
        anchors.centerIn: parent
        modal: true
        title: qsTr("Delete “%1”?").arg(nameField.text)
        Label {
            text: qsTr("Its favourites and resume points go with it.")
            color: win.muted
        }
        footer: DialogButtonBox {
            Button {
                Material.roundedScale: theme.radius
                text: qsTr("Delete")
                flat: true
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
            }
            Button {
                Material.roundedScale: theme.radius
                text: qsTr("Cancel")
                flat: true
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
            }
        }
        onAccepted: {
            backend.removeSource(page.editingId)
            page.editing = false
            list.forceActiveFocus()
        }
    }
}
