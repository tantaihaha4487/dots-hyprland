import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentSubsection {
    id: root

    title: Translation.tr("Accounts")
    tooltip: Translation.tr("Additional logins are isolated from the primary ~/.codex account. Credentials stay in private machine-local storage.")

    property var primaryAccount: ({ id: "current", email: "Current account", status: "loading", managed: false })
    property var managedAccounts: []
    property var archivedAccounts: []
    property var pendingRemoval: null
    property string statusMessage: Translation.tr("Loading accounts…")
    property bool statusIsError: false
    property string actionOperation: ""
    property string actionTarget: ""
    readonly property string backend: Quickshell.shellPath("scripts/codexbar/accounts.sh")
    readonly property bool busy: listProcess.running || actionProcess.running
    readonly property var accountOptions: {
        const options = [{
            displayName: Translation.tr("Current account"),
            icon: "person",
            value: "current"
        }]
        root.managedAccounts.forEach(account => options.push({
            displayName: account.email,
            icon: account.status === "ready" ? "verified_user" : "warning",
            value: account.id
        }))
        return options
    }

    function refreshAccounts() {
        if (listProcess.running)
            return
        root.statusMessage = Translation.tr("Refreshing account list…")
        root.statusIsError = false
        listProcess.running = true
    }

    function parseList(text) {
        try {
            const result = JSON.parse(text)
            if (!result.ok)
                throw new Error(result.message || "Account list failed")
            root.primaryAccount = result.primary
            root.managedAccounts = result.accounts || []
            root.archivedAccounts = result.archives || []
            root.statusMessage = Translation.tr("Account list is up to date.")
            root.statusIsError = false
        } catch (error) {
            root.statusMessage = Translation.tr("Could not load managed accounts.")
            root.statusIsError = true
        }
    }

    function runAction(operation, target) {
        if (root.busy)
            return
        root.actionOperation = operation
        root.actionTarget = target || ""
        root.pendingRemoval = null
        root.statusIsError = false
        switch (operation) {
        case "add":
            root.statusMessage = Translation.tr("Waiting for browser authentication…")
            break
        case "reauth":
            root.statusMessage = Translation.tr("Waiting for browser re-authentication…")
            break
        case "remove":
            root.statusMessage = Translation.tr("Moving account to the restoration archive…")
            break
        case "restore":
            root.statusMessage = Translation.tr("Restoring account…")
            break
        }
        actionProcess.command = target ? [root.backend, operation, target] : [root.backend, operation]
        actionProcess.running = true
    }

    function finishAction(text) {
        try {
            const result = JSON.parse(text)
            root.statusMessage = result.message || (result.ok ? Translation.tr("Account action completed.") : Translation.tr("Account action failed."))
            root.statusIsError = !result.ok
            if (result.ok && root.actionOperation === "remove" &&
                    Config.options.bar.codexUsage.barAccountMode === root.actionTarget) {
                Config.options.bar.codexUsage.barAccountMode = "current"
            }
        } catch (error) {
            root.statusMessage = Translation.tr("Account action failed safely; existing credentials were preserved.")
            root.statusIsError = true
        }
        Qt.callLater(root.refreshAccounts)
    }

    Process {
        id: listProcess
        command: [root.backend, "list"]
        stdout: StdioCollector {
            onStreamFinished: root.parseList(text)
        }
    }

    Process {
        id: actionProcess
        stdout: StdioCollector {
            onStreamFinished: root.finishAction(text)
        }
    }

    Component.onCompleted: refreshAccounts()

    ContentSubsection {
        title: Translation.tr("Compact bar account")

        ConfigSelectionArray {
            enabled: !root.busy
            currentValue: Config.options.bar.codexUsage.barAccountMode
            onSelected: newValue => {
                Config.options.bar.codexUsage.barAccountMode = newValue
            }
            options: root.accountOptions
        }
    }

    ContentSubsection {
        title: Translation.tr("Managed accounts")

        ConfigRow {
            id: primaryRow
            Layout.fillWidth: true
            Layout.topMargin: 2
            implicitHeight: Math.max(primaryAccountInfo.implicitHeight, 36)

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: "person"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer2
            }
            ColumnLayout {
                id: primaryAccountInfo
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                StyledText {
                    text: Translation.tr("Current account")
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    text: root.primaryAccount.status === "ready" ? Translation.tr("Primary login · read only") : Translation.tr("Primary login unavailable · read only")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }

        Repeater {
            model: root.managedAccounts

            delegate: ConfigRow {
                id: accountDelegate
                required property var modelData
                Layout.fillWidth: true
                Layout.topMargin: 2
                implicitHeight: Math.max(accountInfo.implicitHeight, reauthButton.implicitHeight, removeButton.implicitHeight)

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: accountDelegate.modelData.status === "ready" ? "verified_user" : "warning"
                    iconSize: Appearance.font.pixelSize.larger
                    color: accountDelegate.modelData.status === "ready" ? Appearance.colors.colPrimary : Appearance.colors.colError
                }
                ColumnLayout {
                    id: accountInfo
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: accountDelegate.modelData.email
                        elide: Text.ElideMiddle
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        text: accountDelegate.modelData.status === "ready" ? Translation.tr("Ready") : Translation.tr("Credentials unavailable")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
                RippleButtonWithIcon {
                    id: reauthButton
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignVCenter
                    enabled: !root.busy
                    materialIcon: "sync"
                    mainText: Translation.tr("Re-authenticate")
                    onClicked: root.runAction("reauth", accountDelegate.modelData.id)
                }
                RippleButtonWithIcon {
                    id: removeButton
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignVCenter
                    enabled: !root.busy
                    materialIcon: "delete"
                    mainText: Translation.tr("Remove")
                    onClicked: root.pendingRemoval = accountDelegate.modelData
                }
            }
        }
    }

    NoticeBox {
        visible: root.managedAccounts.length === 0
        Layout.fillWidth: true
        materialIcon: "info"
        text: Translation.tr("No additional Codex accounts are managed yet.")
    }

    NoticeBox {
        visible: root.pendingRemoval !== null
        materialIcon: "warning"
        text: root.pendingRemoval ? Translation.tr("Remove %1? Its private login will be archived and can be restored later.").arg(root.pendingRemoval.email) : ""

        DialogButton {
            enabled: !root.busy
            buttonText: Translation.tr("Cancel")
            onClicked: root.pendingRemoval = null
        }
        DialogButton {
            enabled: !root.busy
            buttonText: Translation.tr("Remove")
            onClicked: root.runAction("remove", root.pendingRemoval.id)
        }
    }

    ContentSubsection {
        visible: root.archivedAccounts.length > 0
        title: Translation.tr("Restoration archive")

        Repeater {
            model: root.archivedAccounts
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: modelData.email
                    elide: Text.ElideMiddle
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    text: modelData.status === "archived" ? Translation.tr("Archived") : Translation.tr("Archive incomplete")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                DialogButton {
                    enabled: !root.busy && modelData.status === "archived"
                    buttonText: Translation.tr("Restore")
                    onClicked: root.runAction("restore", modelData.archiveId)
                }
            }
        }
    }

    ConfigRow {
        Layout.fillWidth: true
        Layout.topMargin: 4

        RippleButtonWithIcon {
            Layout.fillWidth: false
            enabled: !root.busy
            materialIcon: "person_add"
            mainText: Translation.tr("Add account")
            onClicked: root.runAction("add", "")
        }
        RippleButtonWithIcon {
            Layout.fillWidth: false
            enabled: !root.busy
            materialIcon: "refresh"
            mainText: Translation.tr("Refresh")
            onClicked: root.refreshAccounts()
        }
        Item { Layout.fillWidth: true }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.topMargin: 2
        text: root.statusMessage
        color: root.statusIsError ? Appearance.colors.colError : Appearance.colors.colSubtext
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.smaller
    }
}
