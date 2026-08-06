# Add another Codex account on Linux

The Codex CLI normally keeps one active login in `~/.codex`. CodexBar can show
additional accounts when each account has its own `CODEX_HOME` and is registered
in its managed-account file.

The helper in this repository performs that setup without replacing the login in
`~/.codex`.

## Requirements

- `codex`
- `codexbar`
- `jq`

On Arch Linux, `./setup install-deps` installs the `codexbar-cli` package used by
the bar widget.

## Add an account

From the repository root, run:

```bash
./sdata/codexbar/add-account.sh
```

Complete the browser login using the additional ChatGPT account. The script then:

1. Creates an isolated Codex home under
   `~/.local/share/CodexBar/managed-codex-homes/`.
2. Runs `codex login` only inside that home.
3. Registers the account in
   `~/.local/share/CodexBar/managed-codex-accounts.json`.
4. Creates a timestamped backup before changing an existing account file.
5. Prints every account detected by CodexBar.

If `XDG_DATA_HOME` is set, CodexBar uses that directory instead of
`~/.local/share`.

## Verify

```bash
codexbar usage --provider codex --all-accounts --format json |
  jq -r '.[] | (.usage.accountEmail // .account // "unknown")'
```

Each account email should appear on its own line.

In **Settings → Bar → CodexBar**, select **Popup accounts → All accounts**. Move
the pointer away from CodexBar and hover it again, or press **Refresh usage** in
the popup.

## Troubleshooting

### The browser used the existing account

Sign out of ChatGPT in the browser or use a private browser window, then run the
helper again and choose the other account.

### Login succeeded but registration failed

The script prints the isolated Codex home it created. Re-run the login for that
home with:

```bash
CODEX_HOME="/path/printed/by/the/script" codex login
```

Then run the helper again if the account is not listed.

### Only one account appears

Check the managed account file and query CodexBar directly:

```bash
jq '.accounts[] | {email, managedHomePath}' \
  "${XDG_DATA_HOME:-$HOME/.local/share}/CodexBar/managed-codex-accounts.json"

codexbar usage --provider codex --all-accounts --format json | jq
```

Do not copy or publish `auth.json`, access tokens, or the managed Codex homes.
They contain private authentication credentials.
