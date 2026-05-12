#!/usr/bin/env bash

default_snapshot_file() {
  local parent=""
  local base=""

  parent="$(dirname "$WEBROOT")/.harden-wp/snapshots"
  base="$(basename "$WEBROOT")"
  printf '%s/permissions-%s-%s.acl' "$parent" "$base" "$(date +%Y%m%d-%H%M%S)"
}

snapshot_permissions_to_file() {
  local file="$1"
  local dir=""

  dir="$(dirname "$file")"
  ensure_dir "$dir"

  if command -v getfacl >/dev/null 2>&1; then
    info "Save permission snapshot: $file"
    if [ "$DRY_RUN" -eq 1 ]; then
      printf 'DRY-RUN: getfacl -pR %q > %q\n' "$WEBROOT" "$file"
    else
      getfacl -pR "$WEBROOT" > "$file"
    fi
  else
    warn "getfacl not found; writing stat-only snapshot that cannot be restored automatically."
    if [ "$DRY_RUN" -eq 1 ]; then
      printf 'DRY-RUN: stat snapshot %q\n' "$file"
    else
      find "$WEBROOT" -printf '%m\t%u\t%g\t%p\n' > "$file"
    fi
  fi
}

snapshot_permissions_optional() {
  local file="$SNAPSHOT_FILE"
  [ -n "$file" ] || file="$(default_snapshot_file)"

  if ! snapshot_permissions_to_file "$file"; then
    warn "Permission snapshot failed: $file"
  fi
}

snapshot_permissions_required() {
  local file="$SNAPSHOT_FILE"
  [ -n "$file" ] || file="$(default_snapshot_file)"

  snapshot_permissions_to_file "$file"
  printf 'Snapshot: %s\n' "$file"
}

restore_permissions() {
  [ -n "$SNAPSHOT_FILE" ] || die "--snapshot FILE is required for restore-permission"
  [ -f "$SNAPSHOT_FILE" ] || die "Snapshot not found: $SNAPSHOT_FILE"

  if ! command -v setfacl >/dev/null 2>&1; then
    die "setfacl not found; cannot restore ACL snapshot automatically."
  fi

  if ! grep -q '^# file: ' "$SNAPSHOT_FILE"; then
    die "Snapshot does not look like getfacl output: $SNAPSHOT_FILE"
  fi

  info "Restore permissions from snapshot"
  run_cmd setfacl --restore="$SNAPSHOT_FILE"
}
