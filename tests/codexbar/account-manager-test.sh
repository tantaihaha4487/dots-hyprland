#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
backend="$repo_root/dots/.config/quickshell/ii/scripts/codexbar/accounts.sh"
mock_bin="$repo_root/tests/codexbar/mock-bin"
test_root="$(mktemp -d)"
export HOME="$test_root/home"
export XDG_DATA_HOME="$test_root/data"
export PATH="$mock_bin:/usr/bin:/bin"
mkdir -p "$HOME"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_jq() {
    local json="$1" expression="$2" message="$3"
    jq -e "$expression" <<<"$json" >/dev/null || fail "$message"
}

empty="$($backend list)"
assert_jq "$empty" '.ok and (.accounts | length == 0) and (.archives | length == 0)' "empty registry"

first="$(MOCK_EMAIL=first@example.com MOCK_PROVIDER_ID=provider-first "$backend" add)"
first_id="$(jq -r '.account.id' <<<"$first")"
assert_jq "$first" '.ok and .account.status == "ready"' "add"

if MOCK_EMAIL=first@example.com MOCK_PROVIDER_ID=provider-first "$backend" add >/dev/null; then
    fail "duplicate account was accepted"
fi

reauth="$(MOCK_EMAIL=first@example.com MOCK_PROVIDER_ID=provider-first "$backend" reauth "$first_id")"
assert_jq "$reauth" '.ok' "re-authentication"

if MOCK_EMAIL=other@example.com MOCK_PROVIDER_ID=provider-other "$backend" reauth "$first_id" >/dev/null; then
    fail "different account replaced existing credentials"
fi

removed="$($backend remove "$first_id")"
archive_id="$(jq -r '.archive.archiveId' <<<"$removed")"
after_remove="$($backend list)"
assert_jq "$after_remove" '(.accounts | length == 0) and (.archives | length == 1)' "archive"

restored="$($backend restore "$archive_id")"
assert_jq "$restored" '.ok and .account.status == "ready"' "restore"

resolved="$($backend resolve "$first_id")"
assert_jq "$resolved" ".resolved == \"$first_id\" and (.fallback | not)" "resolve"

usage="$(MOCK_EMAIL=first@example.com "$backend" usage "$first_id")"
assert_jq "$usage" '.[0].usage.accountEmail == "first@example.com"' "managed usage"

fallback="$($backend resolve 00000000-0000-4000-8000-000000000000)"
assert_jq "$fallback" '.resolved == "current" and .fallback' "stale selection fallback"

if MOCK_LOGIN_FAIL=1 "$backend" add >/dev/null; then
    fail "interrupted login was accepted"
fi

if MOCK_USAGE_FAIL=1 "$backend" add >/dev/null; then
    fail "unverified login was registered"
fi

if "$backend" remove invalid-id >/dev/null; then
    fail "invalid ID was accepted"
fi

MOCK_EMAIL=concurrent@example.com MOCK_PROVIDER_ID=provider-concurrent "$backend" add > "$test_root/concurrent-one.json" &
pid_one=$!
MOCK_EMAIL=concurrent@example.com MOCK_PROVIDER_ID=provider-concurrent "$backend" add > "$test_root/concurrent-two.json" &
pid_two=$!
set +e
wait "$pid_one"; status_one=$?
wait "$pid_two"; status_two=$?
set -e
[[ $((status_one + status_two)) -eq 1 ]] || fail "concurrent duplicate serialization"

final="$($backend list)"
assert_jq "$final" '(.accounts | length == 2) and ([.accounts[].email] | index("concurrent@example.com") != null)' "final account list"

backup_count="$(find "$XDG_DATA_HOME/CodexBar" -maxdepth 1 -type f -name 'managed-codex-accounts.json.bak.*' | wc -l)"
[[ "$backup_count" -ge 5 ]] || fail "timestamped registry backups"

find "$XDG_DATA_HOME/CodexBar" -type f -perm /077 -print -quit | grep -q . \
    && fail "private files have permissive modes"

printf 'PASS: CodexBar account manager (%s)\n' "$test_root"
