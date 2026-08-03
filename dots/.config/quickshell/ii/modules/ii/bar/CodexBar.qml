import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property string statusText: "Codex"
    property string detailText: "Waiting for CodexBar"
    property color textColor: Appearance.colors.colOnLayer1

    implicitWidth: contentLayout.implicitWidth
    implicitHeight: Appearance.sizes.barHeight

    function numberFrom(value) {
        if (typeof value === "number" && isFinite(value))
            return value
        return null
    }

    function collectPercentages(value, output) {
        if (value === null || value === undefined)
            return

        if (Array.isArray(value)) {
            value.forEach(item => collectPercentages(item, output))
            return
        }

        if (typeof value !== "object")
            return

        Object.keys(value).forEach(key => {
            const lowerKey = key.toLowerCase()
            const candidate = numberFrom(value[key])
            if (candidate !== null &&
                (lowerKey.includes("utilization") ||
                 lowerKey.includes("usedpercent") ||
                 lowerKey.includes("usagepercent") ||
                 lowerKey === "percentage" ||
                 lowerKey === "percent" ||
                 lowerKey === "used_percentage")) {
                output.push(Math.max(0, Math.min(100, candidate)))
            } else if (typeof value[key] === "object") {
                collectPercentages(value[key], output)
            }
        })
    }

    function formatPercentages(data) {
        const weeklyUsed = data?.[0]?.usage?.secondary?.usedPercent
        if (typeof weeklyUsed === "number")
            return `Week ${Math.round(Math.max(0, Math.min(100, 100 - weeklyUsed)))}% left`

        const percentages = []
        collectPercentages(data, percentages)

        const unique = []
        percentages.forEach(value => {
            if (!unique.some(existing => Math.abs(existing - value) < 0.01))
                unique.push(value)
        })

        if (unique.length === 0)
            return "Codex"

        // CodexBar reports the short session window before the weekly window.
        const weekly = unique.length > 1 ? unique[1] : unique[0]
        return `Week ${Math.round(weekly)}% left`
    }

    function updateFrom(text) {
        try {
            const data = JSON.parse(text)
            const error = data?.[0]?.error
            if (error) {
                root.statusText = "Codex !"
                root.detailText = error.message || "CodexBar could not fetch usage"
                return
            }

            root.statusText = formatPercentages(data)
            root.detailText = "CodexBar usage"
        } catch (error) {
            root.statusText = "Codex !"
            root.detailText = "Invalid CodexBar JSON output"
        }
    }

    Process {
        id: usageProcess
        command: ["codexbar", "usage", "--provider", "codex", "--format", "json"]

        stdout: StdioCollector {
            onStreamFinished: root.updateFrom(text)
        }
    }

    Timer {
        interval: 300000
        running: true
        repeat: true
        onTriggered: {
            if (!usageProcess.running)
                usageProcess.running = true
        }
    }

    Component.onCompleted: usageProcess.running = true

    RowLayout {
        id: contentLayout
        anchors.centerIn: parent
        spacing: 4

        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 16
            implicitHeight: 16

            StyledImage {
                id: codexLogo
                anchors.fill: parent
                source: Quickshell.shellPath("assets/icons/codex.svg")
            }

            ColorOverlay {
                anchors.fill: codexLogo
                source: codexLogo
                color: root.textColor
            }
        }

        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: 20
            implicitWidth: textLabel.implicitWidth

            StyledText {
                id: textLabel
                anchors.fill: parent
                text: root.statusText
                color: root.textColor
                font.pixelSize: Appearance.font.pixelSize.small
                verticalAlignment: Text.AlignVCenter
                animateChange: true
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton

        PopupToolTip {
            extraVisibleCondition: mouseArea.containsMouse
            alternativeVisibleCondition: extraVisibleCondition
            text: root.detailText
            anchorEdges: (!Config.options.bar.bottom && !Config.options.bar.vertical) ? Edges.Bottom : Edges.Top
        }
    }
}
