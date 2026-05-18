#!/usr/bin/env bash
# Compatibility wrapper for the fleet runner.

set -Eeuo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec bash "$APP_DIR/bin/fleet.sh" "$@"
