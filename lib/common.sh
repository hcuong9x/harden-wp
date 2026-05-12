#!/usr/bin/env bash

info() {
  printf '==> %s\n' "$*"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  printf 'WARN: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

need_value() {
  local opt="${1:-}"
  local val="${2:-}"

  [ -n "$val" ] || die "Missing value for $opt"
}

prompt_if_empty() {
  local name="$1"
  local prompt="$2"
  local value="$3"

  if [ -n "$value" ]; then
    printf '%s' "$value"
    return
  fi

  if [ ! -t 0 ]; then
    die "Missing $name. Pass it as an argument."
  fi

  local input=""
  read -rp "$prompt" input
  printf '%s' "$input"
}

is_number() {
  case "$1" in
    ""|*[!0-9]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    die "Run with root/sudo."
  fi
}

run_cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi

  "$@"
}

try_run() {
  if ! run_cmd "$@"; then
    warn "Command failed: $*"
  fi
}

ensure_dir() {
  local dir="$1"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'DRY-RUN: mkdir -p %q\n' "$dir"
    return 0
  fi

  mkdir -p "$dir"
}

replace_marker_block() {
  local file="$1"
  local begin="$2"
  local end="$3"
  local content="$4"
  local tmp=""

  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'DRY-RUN: update marker block in %q\n' "$file"
    return 0
  fi

  tmp="$(mktemp)"

  if [ -f "$file" ]; then
    awk -v begin="$begin" -v end="$end" '
      $0 == begin { skip = 1; next }
      $0 == end { skip = 0; next }
      skip != 1 { print }
    ' "$file" > "$tmp"
  else
    : > "$tmp"
  fi

  {
    printf '\n%s\n' "$begin"
    printf '%s\n' "$content"
    printf '%s\n' "$end"
  } >> "$tmp"

  mv "$tmp" "$file"
}
