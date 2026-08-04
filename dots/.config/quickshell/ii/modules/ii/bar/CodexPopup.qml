import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

StyledPopup {
    id: root

    property var usageEntry: null
    property string errorText: ""
    property bool showPace: true
    property bool showResetCredits: true
    signal refreshRequested()

    readonly property var usage: usageEntry?.usage ?? null
    readonly property var pace: usageEntry?.pace?.secondary ?? null
    readonly property color accentColor: Appearance.colors.colPrimary
    readonly property color trackColor: Appearance.colors.colLayer3

    function clampPercent(value) {
        if (typeof value !== "number" || !isFinite(value))
            return 0
        return Math.max(0, Math.min(100, value))
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

                Behavior on width {
                    NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            StyledText {
                text: `${Math.round(root.clampPercent(parent.parent.windowData?.usedPercent ?? 0))}% used`
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
            text: parent.note
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        implicitWidth: 330
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

            ColumnLayout {
                spacing: 0

                StyledText {
                    text: "Codex"
                    color: Appearance.colors.colOnLayer2
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Bold
                }

                StyledText {
                    text: root.usage?.accountEmail ?? "OpenAI Codex"
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }

            Item { Layout.fillWidth: true }

            StyledText {
                text: {
                    const method = root.usage?.loginMethod ?? root.usageEntry?.source ?? ""
                    if (!method)
                        return ""
                    return method.charAt(0).toUpperCase() + method.slice(1)
                }
                color: Appearance.colors.colSubtext
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Appearance.colors.colLayer0Border
        }

        StyledText {
            visible: root.errorText.length > 0
            Layout.fillWidth: true
            text: root.errorText
            color: Appearance.colors.colError
            wrapMode: Text.Wrap
        }

        UsageSection {
            visible: root.usage?.primary != null
            title: "Session"
            windowData: root.usage?.primary ?? null
        }

        UsageSection {
            visible: root.usage?.secondary != null
            title: "Weekly"
            windowData: root.usage?.secondary ?? null
            note: root.showPace ? (root.pace?.summary ?? "") : ""
        }

        UsageSection {
            visible: root.usage?.tertiary != null
            title: "Additional limit"
            windowData: root.usage?.tertiary ?? null
        }

        ColumnLayout {
            visible: root.showResetCredits && (root.usage?.codexResetCredits?.availableCount ?? 0) > 0
            Layout.fillWidth: true
            spacing: 4

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colLayer0Border
            }

            RowLayout {
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
                    text: `${root.usage?.codexResetCredits?.availableCount ?? 0} available`
                    color: Appearance.colors.colSubtext
                }
            }
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

                StyledText {
                    text: "Refresh usage"
                    color: Appearance.colors.colOnLayer2
                }

                Item { Layout.fillWidth: true }

                StyledText {
                    text: root.usage?.updatedAt ? "CodexBar data" : "Waiting for CodexBar"
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }
    }
}
