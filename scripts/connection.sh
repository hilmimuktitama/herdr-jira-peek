# Connection identity and publication epoch. Sourced by runtime and clear-cache.
# shellcheck disable=SC2034 # Values are consumed by callers and viewer children.
connection_hash() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'
  else return 1
  fi
}
connection_config_hash() {
  [ ! -L "$CONFIG_DIR" ] && [ ! -L "$CONFIG_DIR/config.sh" ] && [ -f "$CONFIG_DIR/config.sh" ] || return 1
  connection_hash < "$CONFIG_DIR/config.sh"
}
connection_fingerprint() {
  connection_cfg=$(connection_config_hash) || return 1
  [ "$connection_cfg" = "$CONNECTION_CONFIG_DIGEST" ] || return 1
  if [ "$JIRA_BACKEND" = rest ]; then
    rest_validate_netrc || return 1
    connection_auth=$(connection_hash < "$JIRA_NETRC_FILE") || return 1
  else
    connection_identity=$(mktemp "$STATE/.identity.$$.XXXXXX") || return 1
    if ! "$TWG" --mode user --site "$JIRA_SITE" --output json whoami > "$connection_identity" 2>/dev/null; then
      rm -f "$connection_identity"; return 1
    fi
    connection_account=$(jq -ser 'if length == 1 then (.[0].data.user // .[0].data // .[0]) | .accountId | select(type == "string" and length > 0) else empty end' "$connection_identity" 2>/dev/null) || {
      rm -f "$connection_identity"; return 1
    }
    rm -f "$connection_identity"
    connection_auth=$(printf '%s' "$connection_account" | connection_hash) || return 1
    unset connection_account
  fi
  [ "$(connection_config_hash)" = "$CONNECTION_CONFIG_DIGEST" ] || return 1
  CONNECTION_CURRENT_AUTH=$connection_auth
  # Layout/TTL edits do not change the authenticated data boundary.
  if [ "$JIRA_BACKEND" = rest ]; then connection_target=$JIRA_CLOUD_ID; else connection_target=$JIRA_SITE; fi
  CONNECTION_CURRENT_ID=$(printf '%s\n' "$JIRA_BACKEND" "$JIRA_BASE" "$connection_target" "$JIRA_PROJECTS" "$connection_auth" | connection_hash)
}
connection_lock() {
  connection_lock_dir=$STATE/.connection-lock
  [ ! -L "$connection_lock_dir" ] || return 1
  connection_owner_file=$(mktemp "$STATE/.connection-owner.$$.XXXXXX") || return 1
  connection_wait=0
  while ! mkdir "$connection_lock_dir" 2>/dev/null; do
    for connection_token in "$connection_lock_dir"/.connection-owner.*.*; do
      [ -f "$connection_token" ] && [ ! -L "$connection_token" ] || continue
      connection_owner=${connection_token%.*}; connection_owner=${connection_owner##*.}
      case "$connection_owner" in
        ''|*[!0-9]*) ;;
        *) if ! kill -0 "$connection_owner" 2>/dev/null; then
             if rm "$connection_token" 2>/dev/null; then rmdir "$connection_lock_dir" 2>/dev/null || true; fi
           fi ;;
      esac
    done
    # Recover the tiny mkdir-to-owner crash window, only for an old empty dir.
    if [ -n "$(find "$connection_lock_dir" -prune -type d -mmin +1 -print 2>/dev/null)" ]; then
      rmdir "$connection_lock_dir" 2>/dev/null || true
    fi
    connection_wait=$((connection_wait + 1))
    [ "$connection_wait" -lt 200 ] || { rm -f "$connection_owner_file"; return 1; }
    sleep 0.05
  done
  mv "$connection_owner_file" "$connection_lock_dir/" || { rm -f "$connection_owner_file"; rmdir "$connection_lock_dir"; return 1; }
  connection_owner_file=$connection_lock_dir/${connection_owner_file##*/}
  CONNECTION_LOCK_HELD=1
}
connection_unlock() {
  [ "${CONNECTION_LOCK_HELD:-0}" = 1 ] || return 0
  rm -f "$connection_owner_file" && rmdir "$STATE/.connection-lock" || return 1
  CONNECTION_LOCK_HELD=0
}
connection_read_marker() {
  [ ! -L "$STATE/connection-context" ] || return 1
  connection_saved_id=$(sed -n '1p' "$STATE/connection-context" 2>/dev/null || true)
  connection_saved_epoch=$(sed -n '2p' "$STATE/connection-context" 2>/dev/null || true)
}
connection_new_epoch() {
  connection_marker=$(mktemp "$STATE/.connection.$$.XXXXXX") || return 1
  CONNECTION_EPOCH=${connection_marker##*/}
  printf '%s\n%s\n' "$CONNECTION_ID" "$CONNECTION_EPOCH" > "$connection_marker" \
    && mv "$connection_marker" "$STATE/connection-context"
}
connection_remove_cache() {
  [ ! -L "$CACHE" ] || return 1
  [ -d "$CACHE" ] || return 0
  find "$CACHE/." ! -name . -prune -type f -exec rm -f {} +
}
connection_initialize() {
  connection_lock || return 1
  connection_ok=0
  if connection_read_marker && connection_fingerprint; then
    CONNECTION_ID=$CONNECTION_CURRENT_ID
    CONNECTION_AUTH_DIGEST=$CONNECTION_CURRENT_AUTH
    if [ "$connection_saved_id" = "$CONNECTION_ID" ] && [ -n "$connection_saved_epoch" ]; then
      CONNECTION_EPOCH=$connection_saved_epoch
      connection_ok=1
    elif connection_remove_cache && connection_new_epoch; then
      # First-run migration clears legacy cache; later changes also clear keys.
      if [ -n "$connection_saved_id" ]; then
        for connection_key in "$STATE/key" "$STATE/candidates" "$STATE"/sources/source-*/key "$STATE"/sources/source-*/candidates "$STATE"/session-*/key "$STATE"/session-*/candidates "$STATE"/session-*/sources/source-*/key "$STATE"/session-*/sources/source-*/candidates; do
          [ ! -L "$connection_key" ] && [ -f "$connection_key" ] && rm -f "$connection_key"
        done
      fi
      connection_ok=1
    fi
  fi
  connection_unlock || return 1
  [ "$connection_ok" = 1 ] || return 1
  if [ -n "${VIEWER_CONNECTION_ID:-}" ]; then
    [ "$VIEWER_CONNECTION_ID" = "$CONNECTION_ID" ] && [ "${VIEWER_CONNECTION_EPOCH:-}" = "$CONNECTION_EPOCH" ] || return 1
  fi
}
connection_marker_current() {
  connection_read_marker && [ "$connection_saved_id" = "$CONNECTION_ID" ] && [ "$connection_saved_epoch" = "$CONNECTION_EPOCH" ]
}
connection_assert_current() {
  connection_local_current || return 1
  if [ "${1:-}" = --identity ]; then
    connection_fingerprint && [ "$CONNECTION_CURRENT_ID" = "$CONNECTION_ID" ] || return 1
  fi
}
# Local-only checks for the viewer timer. TWG account changes are checked on
# the next request; no Jira or authentication polling runs in the UI timer.
connection_local_current() {
  connection_marker_current && [ "$(connection_config_hash)" = "$CONNECTION_CONFIG_DIGEST" ] || return 1
  if [ "$JIRA_BACKEND" = rest ]; then
    rest_validate_netrc && [ "$(connection_hash < "$JIRA_NETRC_FILE")" = "$CONNECTION_AUTH_DIGEST" ] || return 1
  fi
}

# A server-observed auth rejection invalidates the session's cached data.
connection_revoke() {
  connection_lock || return 1
  if connection_marker_current; then
    if ! connection_remove_cache || ! connection_new_epoch; then connection_unlock; return 1; fi
  fi
  connection_unlock
}

# A cancelled fzf preview can exit before common.sh installs its caller's traps.
# Reap only recognized temporary files whose creating process has exited.
connection_cleanup_abandoned() {
  cleanup_abandoned_temps "$STATE"/.identity.*.* "$STATE"/.connection-owner.*.* "$STATE"/.connection.*.*
  for connection_stale in "$STATE"/.connection-lock/.connection-owner.*.*; do
    [ -f "$connection_stale" ] && [ ! -L "$connection_stale" ] || continue
    connection_pid=${connection_stale%.*}; connection_pid=${connection_pid##*.}
    case "$connection_pid" in ''|0|*[!0-9]*) continue ;; esac
    if ! kill -0 "$connection_pid" 2>/dev/null; then
      if rm "$connection_stale" 2>/dev/null; then rmdir "$STATE/.connection-lock" 2>/dev/null || true; fi
    fi
  done
}
