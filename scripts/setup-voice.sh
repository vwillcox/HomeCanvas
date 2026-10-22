#!/usr/bin/env bash
# Sets up voice control's speech engine: a Python of its own with sherpa-onnx
# in it, and the two Moonshine recognisers. Everything goes in
# ~/.local/share/homecanvas/voice; nothing needs root but the two system
# packages it may ask for (python3-venv and pw-record).
#
#   bash scripts/setup-voice.sh          set up, or finish setting up
#   bash scripts/setup-voice.sh --check  say what is there; change nothing
#
# Safe to run again: what is already there is kept.
set -euo pipefail

V="$HOME/.local/share/homecanvas/voice"
MODELS="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models"
NAMES="sherpa-onnx-moonshine-base-en-int8 sherpa-onnx-moonshine-tiny-en-int8"

have_engine() { [ -x "$V/venv/bin/python" ] && "$V/venv/bin/python" -c 'import sherpa_onnx, numpy' 2>/dev/null; }
have_model() { [ -f "$V/models/$1/tokens.txt" ]; }

if [ "${1:-}" = --check ]; then
  missing=0
  command -v pw-record >/dev/null && echo "ok pw-record" || { echo "missing pw-record"; missing=1; }
  have_engine && echo "ok engine" || { echo "missing engine"; missing=1; }
  for m in $NAMES; do
    have_model "$m" && echo "ok $m" || { echo "missing $m"; missing=1; }
  done
  exit "$missing"
fi

pkg_install() {
  if command -v apt-get >/dev/null; then sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
  elif command -v dnf >/dev/null; then sudo dnf install -y "$@"
  elif command -v pacman >/dev/null; then sudo pacman -S --needed --noconfirm "$@"
  elif command -v zypper >/dev/null; then sudo zypper --non-interactive install "$@"
  else return 1
  fi
}

mkdir -p "$V/models"

if ! command -v pw-record >/dev/null; then
  echo "Installing pw-record (reads the microphone)"
  if command -v apt-get >/dev/null; then pkg_install pipewire-bin; else pkg_install pipewire; fi
fi

if have_engine; then
  echo "The speech engine is already set up"
else
  echo "Making a Python for the speech engine"
  if ! python3 -m venv "$V/venv" 2>/dev/null; then
    # Debian and Raspberry Pi OS keep venv's pip in a package of its own.
    rm -rf "$V/venv"
    command -v apt-get >/dev/null && pkg_install python3-venv
    python3 -m venv "$V/venv"
  fi
  echo "Installing sherpa-onnx (a few minutes on a Pi)"
  "$V/venv/bin/pip" install --quiet --upgrade pip
  "$V/venv/bin/pip" install --quiet sherpa-onnx numpy
  have_engine || { echo "sherpa-onnx did not install" >&2; exit 1; }
fi

for m in $NAMES; do
  if have_model "$m"; then
    echo "Already downloaded: $m"
  else
    echo "Downloading $m"
    curl -fsSL "$MODELS/$m.tar.bz2" | tar xj -C "$V/models"
    have_model "$m" || { echo "$m did not unpack" >&2; exit 1; }
  fi
done

echo "Voice control is ready"
