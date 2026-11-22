import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

FocusScope {
    id: page

    // Each language is named in itself, so it can be found whatever is showing.
    function languageName(code) {
        const name = Qt.locale(code).nativeLanguageName
        return name.charAt(0).toUpperCase() + name.slice(1)
    }

    readonly property var languages: [
        { code: "", label: (win.android ? qsTr("Follow the system (%1)") : qsTr("Follow Omarchy (%1)"))
                               .arg(languageName(translator.systemLanguage)) },
        { code: "fr", label: "Français" },
        { code: "en", label: "English" }
    ]

    function choose(index) {
        if (index >= 0 && index < languages.length)
            backend.language = languages[index].code
    }

    Component.onCompleted: {
        for (let i = 0; i < languages.length; ++i)
            if (languages[i].code === backend.language)
                list.currentIndex = i
        list.forceActiveFocus()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        Label {
            visible: !win.compact
            text: qsTr("Settings")
            font.pixelSize: 22
            font.bold: true
            color: win.ink
        }

        Label {
            text: qsTr("Language")
            color: win.muted
            font.pixelSize: 12
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1
            Layout.topMargin: 12
        }

        ListView {
            id: list
            Layout.preferredWidth: Math.min(460, page.width - 32)
            Layout.preferredHeight: contentHeight
            focus: true
            interactive: false
            model: page.languages
            highlightMoveDuration: 0
            keyNavigationEnabled: true
            highlight: Rectangle {
                color: win.tint(list.activeFocus ? 0.22 : 0.09)
                radius: win.small
            }
            Keys.onReturnPressed: page.choose(currentIndex)
            Keys.onEnterPressed: page.choose(currentIndex)
            Keys.onSpacePressed: page.choose(currentIndex)

            delegate: RadioDelegate {
                required property var modelData
                required property int index
                width: ListView.view.width
                text: modelData.label
                checked: backend.language === modelData.code
                background: null
                onClicked: {
                    list.currentIndex = index
                    page.choose(index)
                }
            }
        }

        Label {
            text: (win.android ? "" : qsTr("Only Zap changes language: the rest of the desktop keeps the one set in Omarchy.") + "\n")
                  + qsTr("Languages without a translation show in English.")
            color: win.muted
            font.pixelSize: 13
            wrapMode: Text.Wrap
            Layout.preferredWidth: Math.min(460, page.width - 32)
        }

        Item { Layout.fillHeight: true }
    }
}
