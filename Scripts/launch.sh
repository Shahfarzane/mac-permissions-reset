#!/usr/bin/env bash
# Launch the packaged app.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_NAME=${APP_NAME:-AppReset}
open "$ROOT/${APP_NAME}.app"
