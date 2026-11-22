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
  --exclude 'test/addons/' \
  "$HERE"/ "$PI:$PI_DIR"/

# The widgets live on the Pi, not here: add-ons from the catalogue, and
# any uploaded as Dart in the editor. Their folder is left alone above.
# Whatever the Pi's dashboard uses and does not yet have is fetched — a
# panel set up when the widgets were built in keeps them — and the file
# that registers them written again, so the next build has them in it.
ssh "$PI" "python3 '$PI_DIR/scripts/addons.py' ensure; bash '$PI_DIR/scripts/widget-build.sh' generate"

echo "Synced $HERE -> $PI:$PI_DIR"
