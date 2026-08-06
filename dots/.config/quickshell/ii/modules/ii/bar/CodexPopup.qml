import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

StyledPopup {
    id: root

    popupWidth: 380

    property var usageEntry: null
    property var accountEntries: []
    property string accountDisplayMode: "all"
    property string errorText: ""
    property bool showPace: true
    property bool showResetCredits: true
    signal refreshRequested()

    readonly property color accentColor: Appearance.colors.colPrimary
    readonly property color trackColor: Appearance.colors.colLayer3
    readonly property var displayEntries: accountDisplayMode === "all" && accountEntries.length > 0
                                          ? accountEntries
                                          : usageEntry ? [usageEntry] : []

    function clampPercent(value) {
        if (typeof value !== "number" || !isFinite(value))
            return 0
        return Math.max(0, Math.min(100, value))
    }

    function percentText(value) {
        const used = Math.round(root.clampPercent(value))
        switch (Config.options.bar.codexUsage.displayMode) {
        case "used":
            return `${used}% used`
        case "iconOnly":
            return `${100 - used}% left`
        default:
            return `${100 - used}% left`
        }
    }

    function resetText(value) {
        if (!value)
            return "Reset unavailable"
        const seconds = Math.max(0, Math.floor((new Date(value).getTime() - Date.now()) / 1000))
        const days = Math.floor(seconds / 86400)
        const hours = Math.floor((seconds % 86400) / 3600)
        const minutes = Math.floor((seconds % 3600) / 60)
        if (days > 0)
            return `Resets in ${days}d ${hours}h`
        if (hours > 0)
            return `Resets in ${hours}h ${minutes}m`
        return `Resets in ${minutes}m`
    }

    component UsageSection: ColumnLayout {
        required property string title
        required property var windowData
        property string note: ""
        Layout.fillWidth: true
        spacing: 6

        StyledText {
            text: parent.title
            color: Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.large
            font.weight: Font.DemiBold
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 8
            radius: height / 2
            color: root.trackColor
            Rectangle {
                width: parent.width * root.clampPercent(parent.parent.windowData?.usedPercent ?? 0) / 100
                height: parent.height
                radius: height / 2
                color: root.accentColor
            }
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                text: root.percentText(parent.parent.windowData?.usedPercent ?? 0)
                color: Appearance.colors.colOnLayer2
            }
            Item { Layout.fillWidth: true }
            StyledText {
                text: root.resetText(parent.parent.windowData?.resetsAt)
                color: Appearance.colors.colSubtext
            }
        }
        StyledText {
            visible: parent.note.length > 0
            Layout.fillWidth: true
            text: parent.note
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
    }

    component AccountCard: Rectangle {
        required property var entry
        property bool compact: false
        Layout.fillWidth: true
        color: compact ? "transparent" : Appearance.colors.colLayer1
        radius: Appearance.rounding.small
        implicitHeight: cardLayout.implicitHeight + (compact ? 0 : 24)

        ColumnLayout {
            id: cardLayout
            anchors.fill: parent
            anchors.margins: compact ? 0 : 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    text: entry?.usage?.accountEmail ?? entry?.account ?? "OpenAI Codex"
                    color: Appearance.colors.colOnLayer2
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                StyledText {
                    text: {
                        const method = entry?.usage?.loginMethod ?? entry?.source ?? ""
                        return method ? method.charAt(0).toUpperCase() + method.slice(1) : ""
                    }
                    color: Appearance.colors.colSubtext
                }
            }

            StyledText {
                visible: !!entry?.error
                Layout.fillWidth: true
                text: entry?.error?.message ?? "Account usage unavailable"
                color: Appearance.colors.colError
                wrapMode: Text.Wrap
            }

            UsageSection {
                visible: entry?.usage?.primary != null
                title: "Session"
                windowData: entry?.usage?.primary ?? null
            }
            UsageSection {
                visible: entry?.usage?.secondary != null
                title: "Weekly"
                windowData: entry?.usage?.secondary ?? null
                note: root.showPace ? (entry?.pace?.secondary?.summary ?? "") : ""
            }
            UsageSection {
                visible: entry?.usage?.tertiary != null
                title: "Additional limit"
                windowData: entry?.usage?.tertiary ?? null
            }

            RowLayout {
                visible: root.showResetCredits && (entry?.usage?.codexResetCredits?.availableCount ?? 0) > 0
                Layout.fillWidth: true
                MaterialSymbol {
                    text: "restart_alt"
                    iconSize: Appearance.font.pixelSize.large
                    color: root.accentColor
                }
                StyledText {
                    text: "Full reset credit"
                    color: Appearance.colors.colOnLayer2
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    text: `${entry?.usage?.codexResetCredits?.availableCount ?? 0} available`
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: 360
        implicitWidth: 360
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Item {
                implicitWidth: 26
                implicitHeight: 26
                StyledImage {
                    id: popupLogo
                    anchors.fill: parent
                    source: Quickshell.shellPath("assets/icons/codex.svg")
                }
                ColorOverlay {
                    anchors.fill: popupLogo
                    source: popupLogo
                    color: Appearance.colors.colOnLayer2
                }
            }
            StyledText {
                text: "Codex"
                color: Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.Bold
            }
            Item { Layout.fillWidth: true }
            StyledText {
                visible: root.displayEntries.length <= 1
                text: root.displayEntries[0]?.usage?.accountEmail ?? "OpenAI Codex"
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                elide: Text.ElideRight
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Appearance.colors.colLayer0Border
        }

        StyledText {
            visible: root.errorText.length > 0 && root.displayEntries.length === 0
            Layout.fillWidth: true
            text: root.errorText
            color: Appearance.colors.colError
            wrapMode: Text.Wrap
        }

        Repeater {
            model: root.displayEntries
            delegate: AccountCard {
                required property var modelData
                entry: modelData
                compact: root.displayEntries.length === 1
            }
        }

        StyledText {
            visible: root.displayEntries.length === 0 && root.errorText.length === 0
            text: "Waiting for CodexBar"
            color: Appearance.colors.colSubtext
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Appearance.colors.colLayer0Border
        }
        MouseArea {
            Layout.fillWidth: true
            implicitHeight: 32
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.refreshRequested()
            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.verysmall
                color: parent.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                MaterialSymbol {
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
                StyledText { text: "Refresh usage"; color: Appearance.colors.colOnLayer2 }
                Item { Layout.fillWidth: true }
                StyledText {
                    text: root.displayEntries.length > 0 ? "CodexBar data" : "Waiting for CodexBar"
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }
    }
}
