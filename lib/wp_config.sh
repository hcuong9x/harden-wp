#!/usr/bin/env bash

wp_config_harden_block() {
  if [ "$STRICT" -eq 1 ]; then
    cat <<'EOF'
// Managed by harden-wp.
if (!defined('DISALLOW_FILE_EDIT')) {
    define('DISALLOW_FILE_EDIT', true);
}
if (!defined('DISALLOW_FILE_MODS')) {
    define('DISALLOW_FILE_MODS', true);
}
EOF
  else
    cat <<'EOF'
// Managed by harden-wp.
if (!defined('DISALLOW_FILE_EDIT')) {
    define('DISALLOW_FILE_EDIT', true);
}
EOF
  fi
}

apply_wp_config_hardening() {
  if [ ! -f "$WP_CONFIG" ]; then
    warn "Skipped wp-config.php hardening because file was not found: $WP_CONFIG"
    return 0
  fi

  local begin="// BEGIN HARDEN-WP-CONFIG"
  local end="// END HARDEN-WP-CONFIG"
  local block=""
  local clean=""
  local tmp=""

  block="$(wp_config_harden_block)"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'DRY-RUN: update wp-config.php hardening block in %q\n' "$WP_CONFIG"
    return 0
  fi

  info "Update wp-config.php internal hardening"

  clean="$(mktemp)"
  tmp="$(mktemp)"

  awk -v begin="$begin" -v end="$end" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    skip != 1 { print }
  ' "$WP_CONFIG" > "$clean"

  awk -v begin="$begin" -v end="$end" -v block="$block" '
    /^[[:space:]]*\?>[[:space:]]*$/ && inserted != 1 {
      print ""
      print begin
      print block
      print end
      inserted = 1
    }
    { print }
    END {
      if (inserted != 1) {
        print ""
        print begin
        print block
        print end
      }
    }
  ' "$clean" > "$tmp"

  mv "$tmp" "$WP_CONFIG"
  rm -f "$clean"
}
