#!/usr/bin/env bash
# Installs piper, the voice that runs on the Pi, and a British voice for it:
# notes and news read aloud, timers and bins announced, Home Assistant's
# answers spoken. Nothing needs root, and nothing is sent anywhere.
#
#   bash scripts/setup-piper.sh            the default voice (Jenny, British)
#   PIPER_VOICE=en_GB/alan/medium bash scripts/setup-piper.sh
#
# Safe to run again: what is there is kept. (Not Debian's `piper` package,
# which configures gaming mice.)
set -euo pipefail

P="$HOME/.local/share/piper"
VOICE="${PIPER_VOICE:-en_GB/jenny_dioco/medium}"
case "$(uname -m)" in
  aarch64 | arm64) ARCH=aarch64 ;;
  x86_64 | amd64) ARCH=x86_64 ;;
  *) echo "piper isn't built for $(uname -m)" >&2; exit 1 ;;
esac

mkdir -p "$P" "$HOME/.local/bin"
if [ -x "$P/piper/piper" ]; then
  echo "piper is already installed"
else
  echo "Downloading piper"
  curl -fsSL "https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_linux_$ARCH.tar.gz" |
    tar xz -C "$P"
fi
ln -sf "$P/piper/piper" "$HOME/.local/bin/piper"

if [ -f "$P/voice.onnx" ] && [ -f "$P/voice.onnx.json" ]; then
  echo "A voice is already installed"
else
  echo "Downloading the voice ($VOICE)"
  base="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/$VOICE"
  file="${VOICE%%/*}-$(echo "$VOICE" | cut -d/ -f2)-$(echo "$VOICE" | cut -d/ -f3)"
  curl -fsSL -o "$P/voice.onnx.part" "$base/$file.onnx"
  curl -fsSL -o "$P/voice.onnx.json" "$base/$file.onnx.json"
  mv "$P/voice.onnx.part" "$P/voice.onnx"
fi

echo "Hello from HomeCanvas." | "$P/piper/piper" --model "$P/voice.onnx" --output_file /dev/null >/dev/null 2>&1 &&
  echo "piper speaks" || { echo "piper is installed but wouldn't speak" >&2; exit 1; }
