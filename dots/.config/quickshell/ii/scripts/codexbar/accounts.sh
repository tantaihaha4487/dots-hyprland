#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

data_root="${XDG_DATA_HOME:-$HOME/.local/share}/CodexBar"
registry="$data_root/managed-codex-accounts.json"
managed_homes="$data_root/managed-codex-homes"
archives="$data_root/managed-codex-archives"
lock_file="$data_root/account-manager.lock"
uuid_pattern='^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'

json_error() {
    jq -cn --arg message "$1" '{ok:false,message:$message}'
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || json_error "Required command is unavailable: $1"
}

new_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        tr '[:upper:]' '[:lower:]' < /proc/sys/kernel/random/uuid
    fi
}

valid_uuid() {
    [[ "$1" =~ $uuid_pattern ]]
}

expected_home() {
    printf '%s/%s\n' "$managed_homes" "$1"
}

secure_layout() {
    mkdir -p "$data_root" "$managed_homes" "$archives"
    chmod 700 "$data_root" "$managed_homes" "$archives"
    touch "$lock_file"
    chmod 600 "$lock_file"
}

lock_registry() {
    exec 9>"$lock_file"
    flock -x 9
    if [[ ! -f "$registry" ]]; then
        local initial
        initial="$(mktemp "$data_root/.registry.initial.XXXXXX")"
        printf '%s\n' '{"version":3,"accounts":[]}' > "$initial"
        chmod 600 "$initial"
        mv -f "$initial" "$registry"
    fi
    chmod 600 "$registry"
    jq -e '.version == 3 and (.accounts | type == "array")' "$registry" >/dev/null \
        || json_error "The managed account registry is invalid."
}

backup_registry() {
    local stamp backup
    stamp="$(date -u +%Y%m%dT%H%M%S).$$"
    backup="$data_root/managed-codex-accounts.json.bak.$stamp"
    cp -p "$registry" "$backup"
    chmod 600 "$backup"
}

replace_registry() {
    local source="$1" staged
    jq -e '.version == 3 and (.accounts | type == "array")' "$source" >/dev/null \
        || json_error "Refusing to write an invalid managed account registry."
    backup_registry
    staged="$(mktemp "$data_root/.registry.write.XXXXXX")"
    install -m 600 "$source" "$staged"
    mv -f "$staged" "$registry"
}

account_record() {
    local id="$1"
    jq -c --arg id "$id" '.accounts[]? | select(.id == $id)' "$registry" | head -n 1
}

validate_record_path() {
    local record="$1" id path
    id="$(jq -r '.id // empty' <<<"$record")"
    path="$(jq -r '.managedHomePath // empty' <<<"$record")"
    valid_uuid "$id" && [[ "$path" == "$(expected_home "$id")" ]]
}

identify_home() {
    local home="$1" usage email provider_id
    CODEX_HOME="$home" codex login status >/dev/null 2>&1 \
        || json_error "Authentication did not complete; the existing account was preserved."
    usage="$(CODEX_HOME="$home" codexbar usage --provider codex --format json 2>/dev/null)" \
        || json_error "Could not verify the authenticated account; the existing account was preserved."
    email="$(jq -r '.[0].usage.accountEmail // .[0].usage.identity.accountEmail // empty' <<<"$usage")"
    [[ -n "$email" ]] || json_error "Could not determine the authenticated account email."
    provider_id="$(jq -r '.tokens.account_id // empty' "$home/auth.json" 2>/dev/null || true)"
    jq -cn --arg email "$email" --arg providerId "$provider_id" \
        '{email:$email,providerId:(if $providerId == "" then null else $providerId end)}'
}

sanitized_list() {
    local accounts_json='[]' archives_json='[]' row record id email path status archive_dir archive_id home

    while IFS= read -r row; do
        record="$(base64 -d <<<"$row")"
        id="$(jq -r '.id // empty' <<<"$record")"
        email="$(jq -r '.email // "Unknown account"' <<<"$record")"
        path="$(jq -r '.managedHomePath // empty' <<<"$record")"
        status="invalid"
        if valid_uuid "$id" && [[ "$path" == "$(expected_home "$id")" ]]; then
            status="missing"
            [[ -f "$path/auth.json" ]] && status="ready"
        fi
        accounts_json="$(jq -c --arg id "$id" --arg email "$email" --arg status "$status" \
            '. + [{id:$id,email:$email,status:$status,managed:true}]' <<<"$accounts_json")"
    done < <(jq -r '.accounts[]? | @base64' "$registry")

    while IFS= read -r archive_dir; do
        [[ -f "$archive_dir/metadata.json" ]] || continue
        archive_id="${archive_dir##*/}"
        record="$(jq -c '.' "$archive_dir/metadata.json" 2>/dev/null)" || continue
        id="$(jq -r '.id // empty' <<<"$record")"
        email="$(jq -r '.email // "Unknown account"' <<<"$record")"
        home="$archive_dir/home"
        valid_uuid "$id" || continue
        status="missing"
        [[ -f "$home/auth.json" ]] && status="archived"
        archives_json="$(jq -c --arg archiveId "$archive_id" --arg id "$id" --arg email "$email" --arg status "$status" \
            '. + [{archiveId:$archiveId,id:$id,email:$email,status:$status}]' <<<"$archives_json")"
    done < <(find "$archives" -mindepth 1 -maxdepth 1 -type d -print | sort -r)

    jq -cn \
        --arg primaryStatus "$([[ -f "$HOME/.codex/auth.json" ]] && printf ready || printf missing)" \
        --argjson accounts "$accounts_json" \
        --argjson archived "$archives_json" \
        '{ok:true,primary:{id:"current",email:"Current account",status:$primaryStatus,managed:false},accounts:$accounts,archives:$archived}'
}

do_list() {
    lock_registry
    sanitized_list
}

do_resolve() {
    local requested="${1:-current}" record path
    if [[ "$requested" == "current" ]]; then
        jq -cn '{ok:true,requested:"current",resolved:"current",fallback:false}'
        return
    fi
    valid_uuid "$requested" || {
        jq -cn --arg requested "$requested" '{ok:true,requested:$requested,resolved:"current",fallback:true,message:"Selected account is invalid; using the current account."}'
        return
    }
    lock_registry
    record="$(account_record "$requested")"
    if [[ -z "$record" ]] || ! validate_record_path "$record"; then
        jq -cn --arg requested "$requested" '{ok:true,requested:$requested,resolved:"current",fallback:true,message:"Selected account is unavailable; using the current account."}'
        return
    fi
    path="$(jq -r '.managedHomePath' <<<"$record")"
    if [[ ! -f "$path/auth.json" ]]; then
        jq -cn --arg requested "$requested" '{ok:true,requested:$requested,resolved:"current",fallback:true,message:"Selected account credentials are unavailable; using the current account."}'
        return
    fi
    jq -cn --arg requested "$requested" '{ok:true,requested:$requested,resolved:$requested,fallback:false}'
}

do_usage() {
    local requested="${1:-current}" record path
    require_command codexbar
    if [[ "$requested" == "current" ]]; then
        exec codexbar usage --provider codex --format json
    fi
    valid_uuid "$requested" || json_error "Invalid managed account ID."
    lock_registry
    record="$(account_record "$requested")"
    [[ -n "$record" ]] && validate_record_path "$record" || json_error "Managed account not found or has an unsafe path."
    path="$(jq -r '.managedHomePath' <<<"$record")"
    [[ -f "$path/auth.json" ]] || json_error "Managed account credentials are unavailable."
    flock -u 9
    exec env CODEX_HOME="$path" codexbar usage --provider codex --format json
}

do_add() {
    require_command codex
    require_command codexbar
    local id staging final identity email provider_id now source cleanup_path
    id="$(new_uuid)"
    valid_uuid "$id" || json_error "Could not allocate a valid account ID."
    staging="$managed_homes/.staging-$id"
    final="$(expected_home "$id")"
    cleanup_path="$staging"
    trap '[[ -n "${cleanup_path:-}" && -d "$cleanup_path" ]] && rm -rf -- "$cleanup_path"' EXIT
    mkdir -m 700 "$staging"

    CODEX_HOME="$staging" codex login >/dev/null 2>&1 \
        || json_error "Login was canceled or failed; no account was added."
    if ! identity="$(identify_home "$staging")"; then
        printf '%s\n' "$identity"
        exit 1
    fi
    email="$(jq -r '.email' <<<"$identity")"
    provider_id="$(jq -r '.providerId // empty' <<<"$identity")"

    lock_registry
    if jq -e --arg email "$email" --arg provider "$provider_id" \
        '.accounts[]? | select(.email == $email or ($provider != "" and .providerAccountID == $provider))' "$registry" >/dev/null; then
        json_error "That Codex account is already managed."
    fi
    [[ ! -e "$final" ]] || json_error "The allocated managed account home already exists."
    mv "$staging" "$final"
    cleanup_path="$final"
    now="$(date +%s)"
    source="$(mktemp "$data_root/.registry.source.XXXXXX")"
    jq --arg id "$id" --arg email "$email" --arg provider "$provider_id" --arg home "$final" --argjson now "$now" \
        '.accounts += [{id:$id,email:$email,providerAccountID:(if $provider == "" then null else $provider end),workspaceLabel:null,workspaceAccountID:null,authFingerprint:null,managedHomePath:$home,createdAt:$now,updatedAt:$now,lastAuthenticatedAt:$now}]' \
        "$registry" > "$source"
    replace_registry "$source"
    rm -f "$source"
    cleanup_path=""
    jq -cn --arg id "$id" --arg email "$email" '{ok:true,message:"Account added.",account:{id:$id,email:$email,status:"ready",managed:true}}'
}

do_reauth() {
    local id="${1:-}" record old_email old_provider final staging identity email provider_id now source old_backup cleanup_path
    valid_uuid "$id" || json_error "Invalid managed account ID."
    require_command codex
    require_command codexbar
    lock_registry
    record="$(account_record "$id")"
    [[ -n "$record" ]] && validate_record_path "$record" || json_error "Managed account not found or has an unsafe path."
    old_email="$(jq -r '.email' <<<"$record")"
    old_provider="$(jq -r '.providerAccountID // empty' <<<"$record")"
    final="$(expected_home "$id")"
    flock -u 9

    staging="$managed_homes/.staging-reauth-$id-$$"
    cleanup_path="$staging"
    trap '[[ -n "${cleanup_path:-}" && -d "$cleanup_path" ]] && rm -rf -- "$cleanup_path"' EXIT
    mkdir -m 700 "$staging"
    CODEX_HOME="$staging" codex login >/dev/null 2>&1 \
        || json_error "Login was canceled or failed; the existing account was preserved."
    if ! identity="$(identify_home "$staging")"; then
        printf '%s\n' "$identity"
        exit 1
    fi
    email="$(jq -r '.email' <<<"$identity")"
    provider_id="$(jq -r '.providerId // empty' <<<"$identity")"
    if [[ -n "$old_provider" && -n "$provider_id" ]]; then
        [[ "$old_provider" == "$provider_id" ]] || json_error "The login belongs to a different account; the existing account was preserved."
    else
        [[ "$old_email" == "$email" ]] || json_error "The login belongs to a different account; the existing account was preserved."
    fi

    lock_registry
    record="$(account_record "$id")"
    [[ -n "$record" ]] && validate_record_path "$record" || json_error "The managed account changed while login was running."
    old_backup="$data_root/.reauth-backup-$id-$(date +%s)-$$"
    [[ -d "$final" ]] || json_error "The existing managed account credentials are missing."
    mv "$final" "$old_backup"
    mv "$staging" "$final"
    cleanup_path="$final"
    now="$(date +%s)"
    source="$(mktemp "$data_root/.registry.source.XXXXXX")"
    jq --arg id "$id" --arg email "$email" --arg provider "$provider_id" --argjson now "$now" \
        '(.accounts[] | select(.id == $id)) |= (.email=$email | .providerAccountID=(if $provider == "" then null else $provider end) | .updatedAt=$now | .lastAuthenticatedAt=$now)' \
        "$registry" > "$source"
    if ! replace_registry "$source"; then
        rm -rf -- "$final"
        mv "$old_backup" "$final"
        json_error "Could not save re-authentication; the existing account was restored."
    fi
    rm -f "$source"
    rm -rf -- "$old_backup"
    cleanup_path=""
    jq -cn --arg id "$id" --arg email "$email" '{ok:true,message:"Account re-authenticated.",account:{id:$id,email:$email,status:"ready",managed:true}}'
}

do_remove() {
    local id="${1:-}" record final archive_id archive_dir metadata source now
    valid_uuid "$id" || json_error "Invalid managed account ID."
    lock_registry
    record="$(account_record "$id")"
    [[ -n "$record" ]] && validate_record_path "$record" || json_error "Managed account not found or has an unsafe path."
    final="$(expected_home "$id")"
    [[ -d "$final" ]] || json_error "Managed account credentials are missing; nothing was removed."
    now="$(date +%s)"
    archive_id="${now}-${id}"
    archive_dir="$archives/$archive_id"
    [[ ! -e "$archive_dir" ]] || json_error "Could not allocate a unique account archive."
    mkdir -m 700 "$archive_dir"
    metadata="$archive_dir/metadata.json"
    jq --arg archiveId "$archive_id" --argjson now "$now" '. + {archiveId:$archiveId,archivedAt:$now}' <<<"$record" > "$metadata"
    chmod 600 "$metadata"
    mv "$final" "$archive_dir/home"
    source="$(mktemp "$data_root/.registry.source.XXXXXX")"
    jq --arg id "$id" '.accounts |= map(select(.id != $id))' "$registry" > "$source"
    if ! replace_registry "$source"; then
        mv "$archive_dir/home" "$final"
        rm -f "$metadata"
        rmdir "$archive_dir"
        json_error "Could not update the registry; the account was restored."
    fi
    rm -f "$source"
    jq -cn --arg archiveId "$archive_id" --arg id "$id" --arg email "$(jq -r '.email' <<<"$record")" \
        '{ok:true,message:"Account moved to the restoration archive.",archive:{archiveId:$archiveId,id:$id,email:$email,status:"archived"}}'
}

do_restore() {
    local archive_id="${1:-}" archive_dir metadata record id email target source
    [[ "$archive_id" =~ ^[0-9]{10,}-[0-9a-f-]{36}$ ]] || json_error "Invalid archive ID."
    archive_dir="$archives/$archive_id"
    metadata="$archive_dir/metadata.json"
    [[ -f "$metadata" && -d "$archive_dir/home" ]] || json_error "Account archive not found."
    record="$(jq -c '.' "$metadata" 2>/dev/null)" || json_error "Account archive metadata is invalid."
    id="$(jq -r '.id // empty' <<<"$record")"
    email="$(jq -r '.email // empty' <<<"$record")"
    valid_uuid "$id" || json_error "Account archive contains an invalid account ID."
    [[ "$(jq -r '.archiveId // empty' <<<"$record")" == "$archive_id" ]] || json_error "Account archive metadata does not match its directory."
    target="$(expected_home "$id")"

    lock_registry
    jq -e --arg id "$id" --arg email "$email" '.accounts[]? | select(.id == $id or .email == $email)' "$registry" >/dev/null \
        && json_error "That account is already managed."
    [[ ! -e "$target" ]] || json_error "The managed account destination already exists."
    mv "$archive_dir/home" "$target"
    source="$(mktemp "$data_root/.registry.source.XXXXXX")"
    jq --argjson account "$(jq 'del(.archiveId,.archivedAt)' <<<"$record")" '.accounts += [$account]' "$registry" > "$source"
    if ! replace_registry "$source"; then
        mv "$target" "$archive_dir/home"
        json_error "Could not update the registry; the archive was preserved."
    fi
    rm -f "$source" "$metadata"
    rmdir "$archive_dir" 2>/dev/null || true
    jq -cn --arg id "$id" --arg email "$email" '{ok:true,message:"Account restored.",account:{id:$id,email:$email,status:"ready",managed:true}}'
}

require_command jq
require_command flock
secure_layout

case "${1:-list}" in
    list|refresh) do_list ;;
    resolve) do_resolve "${2:-current}" ;;
    usage) do_usage "${2:-current}" ;;
    add) do_add ;;
    reauth) do_reauth "${2:-}" ;;
    remove) do_remove "${2:-}" ;;
    restore) do_restore "${2:-}" ;;
    *) json_error "Usage: accounts.sh {list|refresh|resolve ID|usage ID|add|reauth ID|remove ID|restore ARCHIVE_ID}" ;;
esac
