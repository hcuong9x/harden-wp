#!/usr/bin/env bash

runtime_php_block() {
  cat <<'EOF'
# Block PHP execution in writable WordPress runtime paths.
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule \.(php|phtml|phar|php[0-9]?)$ - [F,L,NC]
</IfModule>
<FilesMatch "\.(php|phtml|phar|php[0-9]?)$">
    Require all denied
</FilesMatch>
Options -Indexes
EOF
}

root_htaccess_block() {
  cat <<'EOF'
# Harden common sensitive files.
Options -Indexes
<FilesMatch "^(\.env|\.gitignore|composer\.(json|lock)|debug\.log|error_log|readme\.html|license\.txt)$">
    Require all denied
</FilesMatch>
RedirectMatch 403 (^|/)\.git(/|$)
RedirectMatch 403 (^|/)\.env$
RedirectMatch 403 (^|/)xmlrpc\.php$
EOF
}

write_runtime_htaccess_rules() {
  collect_php_block_dirs

  local dir=""
  local file=""
  local block=""
  block="$(runtime_php_block)"

  for dir in "${PHP_BLOCK_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
      continue
    fi

    file="$dir/.htaccess"
    info "Write PHP execution block: ${file#$WEBROOT/}"
    replace_marker_block "$file" "# BEGIN HARDEN-WP-RUNTIME" "# END HARDEN-WP-RUNTIME" "$block"
    if [ "$SKIP_CHOWN" -eq 0 ]; then
      try_run chown "$OWNER_SPEC" "$file"
    fi
    try_run chmod 644 "$file"
  done
}

write_root_htaccess_rules() {
  local file="$WEBROOT/.htaccess"
  local block=""
  block="$(root_htaccess_block)"

  info "Write root .htaccess hardening block"
  replace_marker_block "$file" "# BEGIN HARDEN-WP" "# END HARDEN-WP" "$block"
  if [ "$SKIP_CHOWN" -eq 0 ]; then
    try_run chown "$OWNER_SPEC" "$file"
  fi
  try_run chmod 644 "$file"
}

write_webinoly_nginx_rule() {
  [ "$STACK" = "webinoly" ] || return 0
  [ -n "$DOMAIN" ] || return 0

  local nginx_dir="/var/www/$DOMAIN/nginx"
  local rule_file="$nginx_dir/harden-wp.conf"

  if [ ! -d "$nginx_dir" ]; then
    warn "$nginx_dir not found; skipped Webinoly nginx rules."
    return 0
  fi

  info "Write Webinoly nginx hardening rules"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'DRY-RUN: write %q\n' "$rule_file"
  else
    cat > "$rule_file" <<'EOF'
# Managed by harden-wp.
autoindex off;

location ~* ^/wp-content/(uploads|cache|upgrade|litespeed|ai1wm-backups|backup[^/]*)/.*\.(php|phtml|phar|php[0-9]?)$ {
    deny all;
}

location ~* (^|/)\.git(/|$) {
    deny all;
}

location ~* (^|/)\.env$ {
    deny all;
}

location ~* /(composer\.(json|lock)|debug\.log|error_log|readme\.html|license\.txt)$ {
    deny all;
}

location = /xmlrpc.php {
    deny all;
}
EOF
  fi

  try_run chown root:root "$rule_file"
  try_run chmod 644 "$rule_file"

  if [ "$RELOAD_NGINX" -eq 1 ] && command -v nginx >/dev/null 2>&1; then
    if nginx -t; then
      if command -v systemctl >/dev/null 2>&1; then
        try_run systemctl reload nginx
      elif command -v service >/dev/null 2>&1; then
        try_run service nginx reload
      else
        warn "nginx -t passed, but systemctl/service was not found for reload."
      fi
    else
      warn "nginx -t failed. Check $rule_file before reloading nginx."
    fi
  fi
}

apply_webserver_rules() {
  write_root_htaccess_rules
  write_runtime_htaccess_rules
  write_webinoly_nginx_rule
}
