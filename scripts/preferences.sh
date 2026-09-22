#!/bin/sh
# shellcheck disable=SC2086 # IFS-scoped CSV splitting is intentional.
# Shared, side-effect-free helpers for Peek's display preferences.
#
# This file deliberately does not source common.sh or read config.sh. Runtime
# and doctor can use the same field vocabulary without executing user data or
# creating plugin state.

preferences_defaults() {
  PICKER_FIELDS=${PICKER_FIELDS-'status,summary'}
  PREVIEW_FIELDS=${PREVIEW_FIELDS-'status,assignee,updated,description,comments'}
  READER_FIELDS=${READER_FIELDS-'status,assignee,updated,link,description,comments'}
  FIELD_LABELS=${FIELD_LABELS-}
  TEXT_STYLE=${TEXT_STYLE-'bold'}
}

preferences_is_field_id() {
  case "${1:-}" in
    summary|status|assignee|reporter|priority|issuetype|project|created|updated|duedate|resolution|labels|components|fixVersions|versions|parent) return 0 ;;
    customfield_[0-9]*) printf '%s' "${1#customfield_}" | grep -Eq '^[0-9]+$' && return 0 ;;
    *) return 1 ;;
  esac
}

preferences_is_detail_field() {
  case "${1:-}" in
    summary) return 1 ;;
    description|comments|link) return 0 ;;
    *) preferences_is_field_id "$1" ;;
  esac
}

preferences_validate_field_list() {
  preferences_scope=${1:-}
  preferences_value=${2-}
  case "$preferences_scope" in
    picker|preview|reader) ;;
    *) return 1 ;;
  esac
  # Empty lists are intentional: they produce a key-only picker or a title-
  # only detail view. Whitespace and shell metacharacters are never accepted.
  [ -z "$preferences_value" ] && return 0
  case "$preferences_value" in ,*|*,|*,,*) return 1 ;; esac
  case "$preferences_value" in *[!A-Za-z0-9_,-]*) return 1 ;; esac
  preferences_seen=,
  preferences_old_ifs=$IFS
  IFS=,
  set -- $preferences_value
  IFS=$preferences_old_ifs
  for preferences_field do
    [ -n "$preferences_field" ] || return 1
    case "$preferences_scope" in
      picker) preferences_is_field_id "$preferences_field" || return 1 ;;
      *) preferences_is_detail_field "$preferences_field" || return 1 ;;
    esac
    case "$preferences_seen" in *,"$preferences_field",*) return 1 ;; esac
    preferences_seen=$preferences_seen$preferences_field,
  done
  return 0
}

preferences_validate_labels() {
  preferences_labels=${1-}
  [ -z "$preferences_labels" ] && return 0
  case "$preferences_labels" in ,*|*,|*,,*) return 1 ;; esac
  printf '%s\n' "$preferences_labels" | grep -Eq '^[A-Za-z0-9_. ,:-]+$' || return 1
  preferences_old_ifs=$IFS
  IFS=,
  set -- $preferences_labels
  IFS=$preferences_old_ifs
  preferences_seen=,
  for preferences_pair do
    preferences_field=${preferences_pair%%:*}
    preferences_label=${preferences_pair#*:}
    [ "$preferences_pair" != "$preferences_field" ] || return 1
    preferences_is_field_id "$preferences_field" || {
      case "$preferences_field" in description|comments|link) : ;; *) return 1 ;; esac
    }
    [ -n "$preferences_label" ] || return 1
    printf '%s' "$preferences_label" | grep -q '[^ ]' || return 1
    printf '%s\n' "$preferences_label" | grep -Eq '^[A-Za-z0-9_. -]+$' || return 1
    case "$preferences_seen" in *,"$preferences_field",*) return 1 ;; esac
    preferences_seen=$preferences_seen$preferences_field,
  done
  return 0
}

preferences_validate_text_style() {
  case "${1:-}" in plain|bold) return 0 ;; *) return 1 ;; esac
}

# shellcheck disable=SC2034 # Runtime displays PREFERENCES_ERROR to the user.
preferences_validate_all() {
  PREFERENCES_ERROR='PICKER_FIELDS must contain unique supported field IDs separated by commas'
  preferences_validate_field_list picker "${PICKER_FIELDS-}" || return 1
  PREFERENCES_ERROR='PREVIEW_FIELDS must contain unique supported detail fields separated by commas'
  preferences_validate_field_list preview "${PREVIEW_FIELDS-}" || return 1
  PREFERENCES_ERROR='READER_FIELDS must contain unique supported detail fields separated by commas'
  preferences_validate_field_list reader "${READER_FIELDS-}" || return 1
  PREFERENCES_ERROR='FIELD_LABELS must contain unique field:Label pairs separated by commas'
  preferences_validate_labels "${FIELD_LABELS-}" || return 1
  PREFERENCES_ERROR='TEXT_STYLE must be plain or bold'
  preferences_validate_text_style "${TEXT_STYLE-}" || return 1
  PREFERENCES_ERROR=
}

preferences_label_for() {
  preferences_target=${1:-}
  preferences_fallback=${2:-$preferences_target}
  preferences_labels=${FIELD_LABELS-}
  [ -n "$preferences_labels" ] || { printf '%s' "$preferences_fallback"; return 0; }
  preferences_old_ifs=$IFS
  IFS=,
  set -- $preferences_labels
  IFS=$preferences_old_ifs
  for preferences_pair do
    [ "${preferences_pair%%:*}" = "$preferences_target" ] || continue
    printf '%s' "${preferences_pair#*:}"
    return 0
  done
  printf '%s' "$preferences_fallback"
}
