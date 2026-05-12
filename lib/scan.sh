#!/usr/bin/env bash

FINDINGS=0

print_finding_file() {
  local title="$1"
  local file="$2"
  local count=""

  if [ ! -s "$file" ]; then
    return 0
  fi

  count="$(wc -l < "$file" | tr -d ' ')"
  FINDINGS=$((FINDINGS + count))

  printf '\n[%s] %s finding(s)\n' "$title" "$count"
  sed 's/^/  /' "$file"
}

scan_php_in_runtime_dirs() {
  local tmp=""
  local dir=""

  tmp="$(mktemp)"
  collect_php_block_dirs

  for dir in "${PHP_BLOCK_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    find "$dir" -type f \
      \( -iname '*.php' -o -iname '*.phtml' -o -iname '*.php5' -o -iname '*.phar' \) \
      -print >> "$tmp" 2>/dev/null || true
  done

  print_finding_file "PHP files in writable/runtime directories" "$tmp"
  rm -f "$tmp"
}

scan_obfuscated_php() {
  local tmp=""
  tmp="$(mktemp)"

  if command -v rg >/dev/null 2>&1; then
    rg -n --pcre2 '(base64_decode|gzinflate|eval|str_rot13|shell_exec)\s*\(' \
      "$WEBROOT" --glob '*.php' > "$tmp" 2>/dev/null || true
  else
    find "$WEBROOT" -type f -name '*.php' -print0 2>/dev/null |
      xargs -0 grep -nE '(base64_decode|gzinflate|eval|str_rot13|shell_exec)[[:space:]]*\(' \
      > "$tmp" 2>/dev/null || true
  fi

  print_finding_file "Obfuscated or dangerous PHP patterns" "$tmp"
  rm -f "$tmp"
}

scan_recent_files() {
  local tmp=""
  tmp="$(mktemp)"

  find "$WEBROOT" -type f -mtime -2 -print > "$tmp" 2>/dev/null || true
  print_finding_file "Files modified in last 2 days" "$tmp"
  rm -f "$tmp"
}

scan_hidden_php() {
  local tmp=""
  tmp="$(mktemp)"

  find "$WEBROOT" -type f -name '.*.php' -print > "$tmp" 2>/dev/null || true
  print_finding_file "Hidden PHP files" "$tmp"
  rm -f "$tmp"
}

scan_symlinks() {
  local tmp=""
  tmp="$(mktemp)"

  find "$WEBROOT" -type l -print > "$tmp" 2>/dev/null || true
  print_finding_file "Symlinks" "$tmp"
  rm -f "$tmp"
}

scan_site() {
  info "Scan suspicious WordPress files"

  scan_php_in_runtime_dirs
  scan_obfuscated_php
  scan_hidden_php
  scan_symlinks
  scan_recent_files

  if [ "$FINDINGS" -eq 0 ]; then
    printf '\nScan complete: no findings.\n'
  else
    printf '\nScan complete: %s finding(s). Review before quarantining anything.\n' "$FINDINGS"
  fi
}
