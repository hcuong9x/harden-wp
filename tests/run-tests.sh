#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
WEBROOT="$TMP_DIR/public_html"

cleanup() {
  chmod -R u+w "$TMP_DIR" 2>/dev/null || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_mode() {
  local expected="$1"
  local path="$2"
  local actual=""

  actual="$(stat -c '%a' "$path")"
  [ "$actual" = "$expected" ] || fail "Expected mode $expected for $path, got $actual"
}

assert_contains() {
  local needle="$1"
  local path="$2"

  grep -q "$needle" "$path" || fail "Expected $path to contain: $needle"
}

mkdir -p \
  "$WEBROOT/wp-admin" \
  "$WEBROOT/wp-includes" \
  "$WEBROOT/wp-content/plugins/hello" \
  "$WEBROOT/wp-content/themes/twenty" \
  "$WEBROOT/wp-content/uploads/2026" \
  "$WEBROOT/wp-content/cache" \
  "$WEBROOT/wp-content/upgrade"

printf '%s\n' '<?php // wp-load' > "$WEBROOT/wp-load.php"
printf '%s\n' '<?php // index' > "$WEBROOT/index.php"
printf '%s\n' '<?php // settings' > "$WEBROOT/wp-settings.php"
printf '%s\n' '<?php // admin' > "$WEBROOT/wp-admin/admin.php"
printf '%s\n' '<?php // include' > "$WEBROOT/wp-includes/load.php"
printf '%s\n' '<?php // plugin' > "$WEBROOT/wp-content/plugins/hello/hello.php"
printf '%s\n' '<?php // theme' > "$WEBROOT/wp-content/themes/twenty/functions.php"
printf '%s\n' '<?php eval($_POST["x"]);' > "$WEBROOT/wp-content/uploads/2026/shell.php"
printf '%s\n' '<?php' 'define("DB_NAME", "example");' > "$WEBROOT/wp-config.php"

bash "$ROOT_DIR/bin/harden-wp" \
  --mode harden \
  --stack custom \
  --webroot "$WEBROOT" \
  --config "$WEBROOT/wp-config.php" \
  --owner "$(id -u):$(id -g)" \
  --yes \
  --no-chown \
  --no-snapshot

assert_mode 555 "$WEBROOT"
assert_mode 555 "$WEBROOT/wp-admin"
assert_mode 444 "$WEBROOT/wp-admin/admin.php"
assert_mode 555 "$WEBROOT/wp-content/plugins"
assert_mode 444 "$WEBROOT/wp-content/plugins/hello/hello.php"
assert_mode 755 "$WEBROOT/wp-content/uploads"
assert_mode 644 "$WEBROOT/wp-content/uploads/.htaccess"
assert_mode 400 "$WEBROOT/wp-config.php"
assert_contains "BEGIN HARDEN-WP" "$WEBROOT/.htaccess"
assert_contains "DISALLOW_FILE_EDIT" "$WEBROOT/wp-config.php"

SCAN_OUT="$TMP_DIR/scan.txt"
bash "$ROOT_DIR/bin/harden-wp" \
  --mode scan \
  --stack custom \
  --webroot "$WEBROOT" \
  --config "$WEBROOT/wp-config.php" \
  --owner "$(id -u):$(id -g)" \
  --yes \
  --no-chown > "$SCAN_OUT"

assert_contains "shell.php" "$SCAN_OUT"
assert_contains "eval" "$SCAN_OUT"

printf 'All tests passed.\n'
