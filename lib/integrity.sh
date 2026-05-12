#!/usr/bin/env bash

default_baseline_file() {
  local parent=""
  local base=""

  parent="$(dirname "$WEBROOT")/.harden-wp/baselines"
  base="$(basename "$WEBROOT")"
  printf '%s/baseline-%s-%s.sha256' "$parent" "$base" "$(date +%Y%m%d-%H%M%S)"
}

generate_integrity_baseline() {
  local file="$BASELINE_FILE"
  local dir=""
  [ -n "$file" ] || file="$(default_baseline_file)"

  command -v sha256sum >/dev/null 2>&1 || die "sha256sum not found."

  dir="$(dirname "$file")"
  ensure_dir "$dir"

  info "Generate integrity baseline: $file"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'DRY-RUN: sha256sum baseline for %q > %q\n' "$WEBROOT" "$file"
    return 0
  fi

  find "$WEBROOT" -type f \
    ! -path "$WEBROOT/wp-content/cache/*" \
    ! -path "$WEBROOT/wp-content/litespeed/*" \
    -print0 |
    sort -z |
    xargs -0 sha256sum > "$file"

  printf 'Baseline: %s\n' "$file"
}

verify_integrity_baseline() {
  [ -n "$BASELINE_FILE" ] || die "--baseline FILE is required for verify-integrity"
  [ -f "$BASELINE_FILE" ] || die "Baseline not found: $BASELINE_FILE"
  command -v sha256sum >/dev/null 2>&1 || die "sha256sum not found."

  info "Verify integrity baseline"
  run_cmd sha256sum -c "$BASELINE_FILE"
}
