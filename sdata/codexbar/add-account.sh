#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
backend="$repo_root/dots/.config/quickshell/ii/scripts/codexbar/accounts.sh"

echo "A browser login will open for the additional Codex account."
echo "The primary login under $HOME/.codex will not be changed."

if ! result="$($backend add)"; then
    jq -r '.message // "Account login failed."' <<<"$result" >&2
    exit 1
fi

jq -r '.message + " " + .account.email' <<<"$result"
echo
echo "Managed accounts:"
"$backend" list | jq -r '.accounts[] | "- " + .email + " (" + .status + ")"'
