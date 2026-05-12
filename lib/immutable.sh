#!/usr/bin/env bash

immutable_targets() {
  printf '%s\n' \
    "$WP_CONFIG" \
    "$WEBROOT/index.php" \
    "$WEBROOT/wp-settings.php"
}

set_immutable() {
  local flag="$1"
  local file=""

  command -v chattr >/dev/null 2>&1 || die "chattr not found."

  info "Apply chattr $flag to critical files"
  while IFS= read -r file; do
    [ -f "$file" ] || continue
    try_run chattr "$flag" "$file"
  done < <(immutable_targets)
}
