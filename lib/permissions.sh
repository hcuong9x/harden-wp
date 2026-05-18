#!/usr/bin/env bash

WRITABLE_DIRS=()
PHP_BLOCK_DIRS=()

collect_writable_dirs() {
  local wp_content="$WEBROOT/wp-content"
  local ai1wm_plugin="$wp_content/plugins/all-in-one-wp-migration"
  local ai1wm_storage="$ai1wm_plugin/storage"

  WRITABLE_DIRS=()
  WRITABLE_DIRS+=("$wp_content/uploads")

  local name=""
  for name in cache litespeed upgrade ai1wm-backups; do
    if [ -d "$wp_content/$name" ]; then
      WRITABLE_DIRS+=("$wp_content/$name")
    fi
  done

  if [ -d "$ai1wm_plugin" ] || [ -d "$ai1wm_storage" ]; then
    WRITABLE_DIRS+=("$ai1wm_storage")
  fi
}

collect_php_block_dirs() {
  collect_writable_dirs
  PHP_BLOCK_DIRS=("${WRITABLE_DIRS[@]}")

  local old_nullglob=""
  old_nullglob="$(shopt -p nullglob || true)"
  shopt -s nullglob

  local dir=""
  for dir in "$WEBROOT"/wp-content/backup*; do
    if [ -d "$dir" ]; then
      PHP_BLOCK_DIRS+=("$dir")
    fi
  done

  eval "$old_nullglob"
}

ensure_writable_dirs() {
  local dir=""

  info "Ensure writable WordPress runtime directories"
  collect_writable_dirs

  for dir in "${WRITABLE_DIRS[@]}"; do
    ensure_dir "$dir"
  done
}

apply_owner() {
  if [ "$SKIP_CHOWN" -eq 1 ]; then
    info "Skip chown because --no-chown is set"
    return 0
  fi

  info "Apply detected owner to WordPress source"
  try_run chown -R "$OWNER_SPEC" "$WEBROOT"

  if [ -f "$WP_CONFIG" ]; then
    try_run chown "$OWNER_SPEC" "$WP_CONFIG"
  fi
}

apply_base_permissions() {
  info "Base permissions: dirs 755, files 644"
  try_run find "$WEBROOT" -type d -exec chmod 755 {} +
  try_run find "$WEBROOT" -type f -exec chmod 644 {} +

  if [ -f "$WP_CONFIG" ]; then
    try_run chmod 644 "$WP_CONFIG"
  fi
}

chmod_readonly_tree() {
  local dir="$1"
  local label="$2"

  if [ -d "$dir" ]; then
    info "Lock $label: dirs 555, files 444"
    try_run find "$dir" -type d -exec chmod 555 {} +
    try_run find "$dir" -type f -exec chmod 444 {} +
  fi
}

chmod_writable_tree() {
  local dir="$1"
  local label="$2"

  if [ -d "$dir" ]; then
    info "Keep writable $label: dirs 755, files 644"
    if [ "$SKIP_CHOWN" -eq 0 ]; then
      try_run chown -R "$OWNER_SPEC" "$dir"
    fi
    try_run find "$dir" -type d -exec chmod 755 {} +
    try_run find "$dir" -type f -exec chmod 644 {} +
  fi
}

apply_readonly_permissions() {
  chmod_readonly_tree "$WEBROOT/wp-admin" "wp-admin"
  chmod_readonly_tree "$WEBROOT/wp-includes" "wp-includes"
  chmod_readonly_tree "$WEBROOT/wp-content/themes" "wp-content/themes"
  chmod_readonly_tree "$WEBROOT/wp-content/plugins" "wp-content/plugins"

  info "Lock WordPress root code files"
  try_run find "$WEBROOT" -maxdepth 1 -type f \
    \( -name '*.php' -o -name '*.js' -o -name '*.css' -o -name '*.txt' -o -name '*.html' -o -name '.htaccess' \) \
    -exec chmod 444 {} +

  info "Lock top-level code directories"
  try_run chmod 555 "$WEBROOT"
  if [ -d "$WEBROOT/wp-content" ]; then
    try_run chmod 555 "$WEBROOT/wp-content"
  fi

  collect_writable_dirs
  local dir=""
  for dir in "${WRITABLE_DIRS[@]}"; do
    chmod_writable_tree "$dir" "${dir#$WEBROOT/}"
  done
}

harden_wp_config() {
  if [ ! -f "$WP_CONFIG" ]; then
    return 0
  fi

  info "Lock wp-config.php"
  if ! run_cmd chmod 400 "$WP_CONFIG"; then
    try_run chmod 440 "$WP_CONFIG"
  fi
}
