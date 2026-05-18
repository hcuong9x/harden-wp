#!/usr/bin/env bash
# Run harden-wp across many WordPress sites on the same server.

set -Eeuo pipefail

SCRIPT_NAME="${0##*/}"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WARNINGS=0

# shellcheck source=../lib/common.sh
. "$APP_DIR/lib/common.sh"
# shellcheck source=../lib/fleet.sh
. "$APP_DIR/lib/fleet.sh"

fleet_main "$@"
