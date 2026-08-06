#!/usr/bin/env bash
set -euo pipefail

for required_command in codex codexbar jq; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Error: $required_command is not installed or not on PATH." >&2
    exit 1
  fi
done

data_root="${XDG_DATA_HOME:-$HOME/.local/share}/CodexBar"
managed_file="$data_root/managed-codex-accounts.json"
managed_homes="$data_root/managed-codex-homes"

if command -v uuidgen >/dev/null 2>&1; then
  account_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
else
  account_id="$(cat /proc/sys/kernel/random/uuid)"
fi

new_home="$managed_homes/$account_id"
mkdir -p "$new_home"
chmod 700 "$data_root" "$managed_homes" "$new_home"

echo "A browser login will open for the additional Codex account."
echo "The existing account under $HOME/.codex will not be changed."
echo

CODEX_HOME="$new_home" codex login
CODEX_HOME="$new_home" codex login status

account_json="$(CODEX_HOME="$new_home" codexbar usage --provider codex --format json)"
email="$(printf '%s' "$account_json" | jq -r \
  '.[0].usage.accountEmail // .[0].usage.identity.accountEmail // empty')"
provider_id="$(jq -r '.tokens.account_id // empty' "$new_home/auth.json" 2>/dev/null || true)"

if [[ -z "$email" ]]; then
  echo "Error: could not determine the new account email." >&2
  echo "The authenticated Codex home was kept at: $new_home" >&2
  exit 1
fi

if [[ -f "$managed_file" ]]; then
  if jq -e --arg email "$email" \
    '.accounts[]? | select(.email == $email)' "$managed_file" >/dev/null; then
    echo "This account is already registered: $email"
    echo "New authenticated home kept at: $new_home"
    exit 0
  fi
  now="$(date +%s)"
  backup="$managed_file.bak.$now"
  cp -a "$managed_file" "$backup"
  source_file="$managed_file"
else
  now="$(date +%s)"
  source_file="$(mktemp)"
  printf '%s\n' '{"version":3,"accounts":[]}' > "$source_file"
  backup=""
fi

tmp_file="$(mktemp)"
if [[ "$source_file" != "$managed_file" ]]; then
  trap 'rm -f "$tmp_file" "$source_file"' EXIT
else
  trap 'rm -f "$tmp_file"' EXIT
fi

jq \
  --arg id "$account_id" \
  --arg email "$email" \
  --arg provider_id "$provider_id" \
  --arg home "$new_home" \
  --argjson now "$now" \
  '.version = 3
   | .accounts = (.accounts // [])
   | .accounts += [{
       id: $id,
       email: $email,
       providerAccountID: (if $provider_id == "" then null else $provider_id end),
       workspaceLabel: null,
       workspaceAccountID: null,
       authFingerprint: null,
       managedHomePath: $home,
       createdAt: $now,
       updatedAt: $now,
       lastAuthenticatedAt: $now
     }]' \
  "$source_file" > "$tmp_file"

install -m 600 "$tmp_file" "$managed_file"

echo
echo "Added Codex account: $email"
echo "Managed home: $new_home"
if [[ -n "$backup" ]]; then
  echo "Backup: $backup"
fi
echo
echo "Detected accounts:"
codexbar usage --provider codex --all-accounts --format json |
  jq -r '.[] | (.usage.accountEmail // .account // "unknown")'
