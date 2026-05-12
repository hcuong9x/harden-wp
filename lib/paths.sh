#!/usr/bin/env bash

normalize_stack() {
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

validate_domain_name() {
  [ -n "$DOMAIN" ] || die "Domain cannot be empty"

  case "$DOMAIN" in
    .*|*..*|*/*|*\\*)
      die "Invalid domain/path segment: $DOMAIN"
      ;;
    *[!A-Za-z0-9._-]*)
      die "Domain can only contain letters, numbers, dot, dash, underscore: $DOMAIN"
      ;;
  esac
}

resolve_paths() {
  if [ -z "$STACK" ] && [ -n "$WEBROOT" ]; then
    STACK="custom"
  fi

  STACK="$(prompt_if_empty stack 'Stack? (webinoly/tino/ols/custom): ' "$STACK")"
  normalize_stack

  if [ "$STACK" != "custom" ]; then
    DOMAIN="$(prompt_if_empty domain 'Domain, example domain.com: ' "$DOMAIN")"
    validate_domain_name
  fi

  case "$STACK" in
    webinoly)
      WEBROOT="${WEBROOT:-/var/www/$DOMAIN/htdocs}"
      WP_CONFIG="${WP_CONFIG:-/var/www/$DOMAIN/wp-config.php}"
      ;;
    tino)
      WEBROOT="${WEBROOT:-/home/$DOMAIN/public_html}"
      WP_CONFIG="${WP_CONFIG:-$WEBROOT/wp-config.php}"
      ;;
    ols)
      WEBROOT="${WEBROOT:-/home/www/$DOMAIN/public_html}"
      WP_CONFIG="${WP_CONFIG:-$WEBROOT/wp-config.php}"
      ;;
    custom)
      WEBROOT="$(prompt_if_empty webroot 'WordPress webroot: ' "$WEBROOT")"
      WP_CONFIG="${WP_CONFIG:-$WEBROOT/wp-config.php}"
      ;;
  esac

  WEBROOT="${WEBROOT%/}"
}

validate_paths() {
  case "$WEBROOT" in
    ""|"/"|"/home"|"/var"|"/var/www"|"/usr"|"/etc")
      die "WEBROOT is too broad or dangerous: '$WEBROOT'"
      ;;
  esac

  [ -d "$WEBROOT" ] || die "WEBROOT not found: $WEBROOT"

  if [ ! -d "$WEBROOT/wp-content" ] || [ ! -f "$WEBROOT/wp-load.php" ]; then
    if [ "$YES" -eq 1 ]; then
      warn "WordPress markers not fully found in $WEBROOT, continuing because --yes is set."
    elif [ -t 0 ]; then
      local confirm=""
      printf 'WARN: wp-content or wp-load.php not found in %s\n' "$WEBROOT" >&2
      read -rp "Type 'yes' to continue, or Enter to cancel: " confirm
      [ "$confirm" = "yes" ] || die "Cancelled."
    else
      die "WordPress markers not found in $WEBROOT. Re-run with --yes if this is intended."
    fi
  fi

  if [ ! -f "$WP_CONFIG" ]; then
    if [ "$YES" -eq 1 ]; then
      warn "wp-config.php not found at $WP_CONFIG, continuing because --yes is set."
    elif [ -t 0 ]; then
      local confirm=""
      printf 'WARN: wp-config.php not found at %s\n' "$WP_CONFIG" >&2
      read -rp "Type 'yes' to continue, or Enter to cancel: " confirm
      [ "$confirm" = "yes" ] || die "Cancelled."
    else
      die "wp-config.php not found at $WP_CONFIG. Re-run with --yes if this is intended."
    fi
  fi
}

validate_owner_spec() {
  local owner_user="${OWNER_SPEC%%:*}"
  local owner_group="${OWNER_SPEC#*:}"

  [ -n "$owner_user" ] || die "Owner user is empty."
  [ "$owner_group" != "$OWNER_SPEC" ] || die "Owner must be USER:GROUP, got '$OWNER_SPEC'."
  [ -n "$owner_group" ] || die "Owner group is empty."

  if ! is_number "$owner_user"; then
    getent passwd "$owner_user" >/dev/null || die "User '$owner_user' does not exist."
  fi

  if ! is_number "$owner_group"; then
    getent group "$owner_group" >/dev/null || die "Group '$owner_group' does not exist."
  fi
}

detect_owner_from_path() {
  local path="$1"

  if [ -e "$path" ]; then
    OWNER_SPEC="$(stat -c '%u:%g' "$path")"
    OWNER_SOURCE="$path"
    return 0
  fi

  return 1
}

detect_owner() {
  if [ -n "$OWNER_SPEC" ]; then
    validate_owner_spec
    return
  fi

  detect_owner_from_path "$WEBROOT/wp-load.php" && return
  detect_owner_from_path "$WEBROOT/index.php" && return
  detect_owner_from_path "$WEBROOT/wp-content" && return
  detect_owner_from_path "$WEBROOT" && return
  detect_owner_from_path "$WP_CONFIG" && return
  detect_owner_from_path "$(dirname "$WEBROOT")" && return

  if [ "$SKIP_CHOWN" -eq 1 ]; then
    OWNER_SPEC="$(id -u):$(id -g)"
    OWNER_SOURCE="current user because --no-chown is set"
    return
  fi

  die "Cannot detect real owner. Pass --owner USER:GROUP if you want to override."
}
