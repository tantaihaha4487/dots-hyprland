# Manage additional Codex accounts on Linux

The primary Codex CLI login remains in `~/.codex` and is read-only in this
workflow. Additional accounts use isolated Codex homes under
`${XDG_DATA_HOME:-$HOME/.local/share}/CodexBar/managed-codex-homes/`.

Account emails and private credential paths are never written to the tracked
Quickshell defaults. Settings persists only `"current"` or the selected managed
account UUID in `bar.codexUsage.barAccountMode`.

## Requirements

- `codex`
- `codexbar` 0.42.1 or newer
- `jq`
- `flock` from `util-linux`

On Arch Linux, `./setup install-deps` installs the `codexbar-cli` package used by
the bar widget.

## Settings workflow

Open **Settings → Bar → CodexBar → Accounts**.

- **Add account** opens Codex browser authentication in a new isolated home.
- **Re-authenticate** stages a fresh login and replaces the working credentials
  only after the account identity has been verified.
- **Remove** asks for confirmation, unregisters the account, and moves its
  private home into the restoration archive.
- **Restore** moves an archived account back into managed accounts.
- **Refresh** reloads account status without showing tokens, authorization URLs,
  credential paths, or raw authentication data.
- **Compact bar account** selects the account shown by the weekly quota. Popup
  account display remains controlled independently by **Popup accounts**.

The primary account cannot be re-authenticated or removed here. If a selected
managed account disappears or its credentials become unavailable, the compact
bar shows current-account usage and labels the fallback.

## Command-line workflow

The command-line helper uses the exact same backend as Settings:

```bash
./sdata/codexbar/add-account.sh
```

The backend can also be called directly:

```bash
backend=./dots/.config/quickshell/ii/scripts/codexbar/accounts.sh

"$backend" list
"$backend" add
"$backend" reauth MANAGED_ACCOUNT_UUID
"$backend" remove MANAGED_ACCOUNT_UUID
"$backend" restore ARCHIVE_ID
"$backend" resolve current
"$backend" usage MANAGED_ACCOUNT_UUID
```

All backend responses are sanitized JSON intended for Settings and automation.
`list` reports account IDs, emails, and status, but never returns credential
paths or credential contents. `usage` resolves the UUID internally and invokes
CodexBar with the isolated `CODEX_HOME`, because CodexBar 0.42.1 does not select
Codex managed homes through its token-account `--account` flag.

## Storage and recovery

The backend serializes registry updates with a lock, writes the registry
atomically with mode `0600`, and creates a timestamped backup before every
change. Managed homes and archive directories use mode `0700`.

Removed accounts remain under:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/CodexBar/managed-codex-archives/
```

Permanent archive deletion is deliberately outside this workflow.

## Verify

```bash
./dots/.config/quickshell/ii/scripts/codexbar/accounts.sh list | jq

codexbar usage --provider codex --all-accounts --format json |
  jq -r '.[] | (.usage.accountEmail // .account // "unknown")'
```

To test lifecycle and concurrency behavior without touching real credentials:

```bash
./tests/codexbar/account-manager-test.sh
```

Never copy or publish `auth.json`, access tokens, managed Codex homes, registry
backups, or restoration archives. They contain private machine-local account
data.
