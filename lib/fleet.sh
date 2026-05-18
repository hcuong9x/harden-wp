#!/usr/bin/env bash

MODE="harden"
STACK=""
DISCOVER=0
STOP_ON_ERROR=0
DOMAIN_INPUT=0
WEBROOT_INPUT=0

FLEET_DOMAINS=()
FLEET_DOMAIN_FILES=()
FLEET_WEBROOTS=()
FLEET_WEBROOT_FILES=()
FLEET_FORWARD_ARGS=()
FLEET_OK=()
FLEET_FAILED=()

fleet_usage() {
  cat <<EOF
Usage:
  sudo bash $SCRIPT_NAME --mode harden --stack webinoly [options]
  sudo bash $SCRIPT_NAME --mode scan --stack tino [options]
  bash $SCRIPT_NAME --mode scan --stack custom --webroots webroots.txt --yes --no-chown

Inputs:
  --domain DOMAIN       Add one domain. Can be repeated.
  --domains FILE       Read domains from FILE, one per line. # comments allowed.
  --webroot PATH       Add one custom WordPress webroot. Can be repeated.
  --webroots FILE      Read custom webroots from FILE, one per line.
  --all, --discover     Discover all sites from known stack paths.

Fleet options:
  --mode VALUE         harden | unlock-update | scan | snapshot |
                       immutable | unimmutable | baseline
  --stack VALUE        webinoly | tino | ols | custom
  --continue-on-error  Keep processing after a failed site. Default.
  --stop-on-error      Stop at the first failed site.
  -h, --help           Show this help

Forwarded harden-wp options:
  --owner USER:GROUP   Use the same owner for every site.
  --strict             Forward strict wp-config mode.
  --yes, -y            Continue when WordPress markers are missing.
  --dry-run            Print commands without changing files.
  --no-chown           Skip chown.
  --no-snapshot        Do not auto-create snapshot during harden.
  --no-nginx-reload    Do not reload nginx after Webinoly rule changes.

Discovery paths:
  webinoly             /var/www/*/htdocs
  tino                 /home/*/public_html
  ols                  /home/www/*/public_html

For webinoly, tino, and ols, discovery is automatic when no --domain/--domains
input is provided. For custom, pass --webroot or --webroots explicitly.
EOF
}

fleet_trim() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

fleet_array_len() {
  local name="$1"
  local restore_nounset=0
  local count=0

  case "$name" in
    FLEET_DOMAINS|FLEET_DOMAIN_FILES|FLEET_WEBROOTS|FLEET_WEBROOT_FILES|FLEET_FORWARD_ARGS|FLEET_OK|FLEET_FAILED)
      ;;
    *)
      die "Internal error: unsupported fleet array: $name"
      ;;
  esac

  case "$-" in
    *u*)
      restore_nounset=1
      set +u
      ;;
  esac

  eval "count=\"\${#$name[@]}\""

  if [ "$restore_nounset" -eq 1 ]; then
    set -u
  fi

  printf '%s' "$count"
}

fleet_normalize_stack() {
  STACK="$(printf '%s' "$STACK" | tr '[:upper:]' '[:lower:]')"

  case "$STACK" in
    webinoly|web)
      STACK="webinoly"
      ;;
    tino)
      STACK="tino"
      ;;
    ols|openlitespeed)
      STACK="ols"
      ;;
    custom|manual)
      STACK="custom"
      ;;
    "")
      ;;
    *)
      die "--stack must be: webinoly, tino, ols, or custom"
      ;;
  esac
}

fleet_validate_mode() {
  case "$MODE" in
    harden|unlock-update|scan|snapshot|immutable|unimmutable|baseline)
      ;;
    restore-permission|verify-integrity)
      die "Fleet mode does not support $MODE because it requires a per-site file. Run bin/harden-wp for that site."
      ;;
    *)
      die "--mode must be harden, unlock-update, scan, snapshot, immutable, unimmutable, or baseline"
      ;;
  esac
}

fleet_validate_domain_name() {
  local domain="$1"

  [ -n "$domain" ] || die "Domain cannot be empty"

  case "$domain" in
    .*|*..*|*/*|*\\*)
      die "Invalid domain/path segment: $domain"
      ;;
    *[!A-Za-z0-9._-]*)
      die "Domain can only contain letters, numbers, dot, dash, underscore: $domain"
      ;;
  esac
}

fleet_add_domain() {
  local domain=""
  local existing=""

  domain="$(fleet_trim "$1")"
  [ -n "$domain" ] || return 0

  fleet_validate_domain_name "$domain"

  for existing in "${FLEET_DOMAINS[@]+"${FLEET_DOMAINS[@]}"}"; do
    [ "$existing" != "$domain" ] || return 0
  done

  FLEET_DOMAINS+=("$domain")
}

fleet_add_webroot() {
  local webroot=""
  local existing=""

  webroot="$(fleet_trim "$1")"
  [ -n "$webroot" ] || return 0

  case "$webroot" in
    ""|"/"|"/home"|"/var"|"/var/www"|"/usr"|"/etc")
      die "WEBROOT is too broad or dangerous: '$webroot'"
      ;;
  esac

  webroot="${webroot%/}"

  for existing in "${FLEET_WEBROOTS[@]+"${FLEET_WEBROOTS[@]}"}"; do
    [ "$existing" != "$webroot" ] || return 0
  done

  FLEET_WEBROOTS+=("$webroot")
}

fleet_read_domain_file() {
  local file="$1"
  local line=""

  [ -f "$file" ] || die "Domain list not found: $file"

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    fleet_add_domain "$line"
  done < "$file"
}

fleet_read_webroot_file() {
  local file="$1"
  local line=""

  [ -f "$file" ] || die "Webroot list not found: $file"

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    fleet_add_webroot "$line"
  done < "$file"
}

fleet_discover_domains() {
  local old_nullglob=""
  local root=""
  local domain=""

  [ "$STACK" != "custom" ] || die "--discover is only available for webinoly, tino, or ols"

  old_nullglob="$(shopt -p nullglob || true)"
  shopt -s nullglob

  case "$STACK" in
    webinoly)
      for root in /var/www/*/htdocs; do
        [ -d "$root/wp-content" ] || [ -f "$root/wp-load.php" ] || continue
        domain="$(basename "$(dirname "$root")")"
        fleet_add_domain "$domain"
      done
      ;;
    tino)
      for root in /home/*/public_html; do
        [ -d "$root/wp-content" ] || [ -f "$root/wp-load.php" ] || continue
        domain="$(basename "$(dirname "$root")")"
        fleet_add_domain "$domain"
      done
      ;;
    ols)
      for root in /home/www/*/public_html; do
        [ -d "$root/wp-content" ] || [ -f "$root/wp-load.php" ] || continue
        domain="$(basename "$(dirname "$root")")"
        fleet_add_domain "$domain"
      done
      ;;
  esac

  eval "$old_nullglob"
}

fleet_parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mode)
        need_value "$1" "${2:-}"
        MODE="$2"
        shift 2
        ;;
      --stack|--type)
        need_value "$1" "${2:-}"
        STACK="$2"
        shift 2
        ;;
      --domain)
        need_value "$1" "${2:-}"
        DOMAIN_INPUT=1
        fleet_add_domain "$2"
        shift 2
        ;;
      --domains|--domains-file|--domain-file|--file)
        need_value "$1" "${2:-}"
        DOMAIN_INPUT=1
        FLEET_DOMAIN_FILES+=("$2")
        shift 2
        ;;
      --webroot)
        need_value "$1" "${2:-}"
        WEBROOT_INPUT=1
        fleet_add_webroot "$2"
        shift 2
        ;;
      --webroots|--webroots-file|--webroot-file)
        need_value "$1" "${2:-}"
        WEBROOT_INPUT=1
        FLEET_WEBROOT_FILES+=("$2")
        shift 2
        ;;
      --all|--discover)
        DISCOVER=1
        shift
        ;;
      --continue-on-error)
        STOP_ON_ERROR=0
        shift
        ;;
      --stop-on-error)
        STOP_ON_ERROR=1
        shift
        ;;
      --owner)
        need_value "$1" "${2:-}"
        FLEET_FORWARD_ARGS+=("$1" "$2")
        shift 2
        ;;
      --strict|--yes|-y|--dry-run|--no-chown|--no-snapshot|--no-nginx-reload)
        FLEET_FORWARD_ARGS+=("$1")
        shift
        ;;
      --snapshot|--baseline|--config|--wp-config)
        die "$1 is per-site and is not accepted by fleet.sh. Use bin/harden-wp for one site, or rely on per-site defaults for snapshot/baseline modes."
        ;;
      --)
        shift
        FLEET_FORWARD_ARGS+=("$@")
        break
        ;;
      -h|--help)
        fleet_usage
        exit 0
        ;;
      *)
        die "Invalid fleet option: $1"
        ;;
    esac
  done
}

fleet_prepare_sites() {
  local file=""

  for file in "${FLEET_DOMAIN_FILES[@]+"${FLEET_DOMAIN_FILES[@]}"}"; do
    fleet_read_domain_file "$file"
  done

  for file in "${FLEET_WEBROOT_FILES[@]+"${FLEET_WEBROOT_FILES[@]}"}"; do
    fleet_read_webroot_file "$file"
  done

  if [ -z "$STACK" ] && [ "$WEBROOT_INPUT" -eq 1 ]; then
    STACK="custom"
  fi

  [ -n "$STACK" ] || die "--stack is required unless you pass --webroot/--webroots for custom sites"
  fleet_normalize_stack
  fleet_validate_mode

  if [ "$STACK" != "custom" ] && { [ "$DISCOVER" -eq 1 ] || [ "$DOMAIN_INPUT" -eq 0 ]; }; then
    fleet_discover_domains
  fi

  if [ "$STACK" = "custom" ]; then
    [ "$(fleet_array_len FLEET_DOMAINS)" -eq 0 ] || die "--domain/--domains cannot be used with --stack custom; use --webroot/--webroots"
    [ "$(fleet_array_len FLEET_WEBROOTS)" -gt 0 ] || die "--stack custom needs --webroot or --webroots"
  else
    [ "$(fleet_array_len FLEET_WEBROOTS)" -eq 0 ] || die "--webroot/--webroots can only be used with --stack custom"
    [ "$(fleet_array_len FLEET_DOMAINS)" -gt 0 ] || die "No domains discovered. Check the stack path or pass --domain/--domains explicitly."
  fi
}

fleet_site_count() {
  if [ "$STACK" = "custom" ]; then
    fleet_array_len FLEET_WEBROOTS
  else
    fleet_array_len FLEET_DOMAINS
  fi
}

fleet_run_one() {
  local index="$1"
  local total="$2"
  local label="$3"
  local domain="$4"
  local webroot="$5"
  local status=0
  local cmd=(bash "$APP_DIR/bin/harden-wp" --mode "$MODE")

  if [ "$STACK" = "custom" ]; then
    cmd+=(--stack custom --webroot "$webroot")
  else
    cmd+=(--stack "$STACK" --domain "$domain")
  fi

  if [ "$(fleet_array_len FLEET_FORWARD_ARGS)" -gt 0 ]; then
    cmd+=("${FLEET_FORWARD_ARGS[@]+"${FLEET_FORWARD_ARGS[@]}"}")
  fi

  printf '\n===== [%s/%s] %s =====\n' "$index" "$total" "$label"

  if "${cmd[@]}"; then
    FLEET_OK+=("$label")
    printf 'OK: %s\n' "$label"
    return 0
  fi

  status=$?
  FLEET_FAILED+=("$label (exit $status)")
  printf 'FAILED: %s (exit %s)\n' "$label" "$status" >&2

  if [ "$STOP_ON_ERROR" -eq 1 ]; then
    return "$status"
  fi

  return 0
}

fleet_print_summary() {
  local item=""

  printf '\nFleet summary: %s OK, %s failed\n' "$(fleet_array_len FLEET_OK)" "$(fleet_array_len FLEET_FAILED)"

  if [ "$(fleet_array_len FLEET_FAILED)" -gt 0 ]; then
    printf 'Failed sites:\n'
    for item in "${FLEET_FAILED[@]+"${FLEET_FAILED[@]}"}"; do
      printf '  %s\n' "$item"
    done
  fi
}

fleet_run_all() {
  local total=""
  local index=1
  local site_status=0
  local domain=""
  local webroot=""
  local label=""

  total="$(fleet_site_count)"
  info "Fleet run: $total site(s), mode=$MODE, stack=$STACK"

  if [ "$STACK" = "custom" ]; then
    for webroot in "${FLEET_WEBROOTS[@]+"${FLEET_WEBROOTS[@]}"}"; do
      label="$webroot"
      site_status=0
      fleet_run_one "$index" "$total" "$label" "" "$webroot" || site_status=$?
      [ "$site_status" -eq 0 ] || break
      index=$((index + 1))
    done
  else
    for domain in "${FLEET_DOMAINS[@]+"${FLEET_DOMAINS[@]}"}"; do
      label="$domain"
      site_status=0
      fleet_run_one "$index" "$total" "$label" "$domain" "" || site_status=$?
      [ "$site_status" -eq 0 ] || break
      index=$((index + 1))
    done
  fi

  fleet_print_summary

  [ "$(fleet_array_len FLEET_FAILED)" -eq 0 ] || return 1
}

fleet_main() {
  fleet_parse_args "$@"
  fleet_prepare_sites
  fleet_run_all
}
