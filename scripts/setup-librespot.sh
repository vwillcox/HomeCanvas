#!/usr/bin/env bash
# Puts the panel in Spotify's device list as "Kiosk", playing through its own
# speakers: librespot, from the raspotify package, run as a user service so it
# plays through PipeWire. Needs Spotify Premium. Debian and Raspberry Pi OS.
#
# Asks for your password (sudo) to install the package.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v apt-get >/dev/null || { echo "This needs Debian or Raspberry Pi OS; see INSTALL.md, Spotify" >&2; exit 1; }

if command -v librespot >/dev/null; then
  echo "librespot is already installed"
else
  echo "Installing librespot (from raspotify)"
  curl -fsSL https://dtcooper.github.io/raspotify/install.sh | sudo sh
fi
# Only its binary is wanted: its own system service would play through ALSA,
# fighting PipeWire for the speakers.
sudo systemctl disable --now raspotify 2>/dev/null || true

mkdir -p "$HOME/.config/systemd/user" "$HOME/.cache/librespot"
cp "$ROOT/deploy/librespot.service" "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable --now librespot.service
echo "The panel is “Kiosk” in Spotify's device list"
