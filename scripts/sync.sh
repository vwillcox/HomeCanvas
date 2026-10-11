#!/usr/bin/env bash
# Sync source from the Mac (source of truth) to the Pi for building.
# Usage: scripts/sync.sh
set -euo pipefail

# Load local overrides (git-ignored) so usernames/hosts stay out of the repo.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[ -f "$SCRIPT_DIR/local.env" ] && . "$SCRIPT_DIR/local.env"

PI="${PI_HOST:-pi@raspberrypi.local}"
PI_DIR="${PI_DIR:-/home/pi/homecanvas}"
HERE="$(cd "$SCRIPT_DIR/.." && pwd)"

ssh "$PI" "mkdir -p '$PI_DIR'"

rsync -az --delete \
  --exclude '.git/' \
  --exclude 'build/' \
  --exclude '.dart_tool/' \
  --exclude 'linux/flutter/ephemeral/' \
  --exclude '**/.DS_Store' \
  --exclude 'companion_app/' \
  --exclude 'assets/certs/*.key' \
  --exclude 'lib/dashboard/widgets/custom/' \
  "$HERE"/ "$PI:$PI_DIR"/

# Widgets uploaded as Dart in the editor live on the Pi, not here: their
# folder is left alone above, and the file that registers them written
# again from what is installed, so the next build has them in it.
ssh "$PI" "bash '$PI_DIR/scripts/widget-build.sh' generate"

echo "Synced $HERE -> $PI:$PI_DIR"
