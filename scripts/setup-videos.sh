#!/usr/bin/env bash
# Fetches yt-dlp and deno, which the video player needs for YouTube,
# Floatplane and Nebula, into ~/.local/share/homecanvas/bin — the same as
# Settings → Music → Videos → Install does on the panel. The panel keeps
# yt-dlp up to date from then on. No root needed.
set -euo pipefail

BIN="$HOME/.local/share/homecanvas/bin"
case "$(uname -m)" in
  aarch64 | arm64) YT=yt-dlp_linux_aarch64 DENO=deno-aarch64-unknown-linux-gnu.zip ;;
  x86_64 | amd64) YT=yt-dlp_linux DENO=deno-x86_64-unknown-linux-gnu.zip ;;
  *) echo "yt-dlp isn't built for $(uname -m)" >&2; exit 1 ;;
esac
mkdir -p "$BIN"

echo "Downloading yt-dlp"
curl -fsSL -o "$BIN/yt-dlp.part" "https://github.com/yt-dlp/yt-dlp/releases/latest/download/$YT"
chmod +x "$BIN/yt-dlp.part"
mv "$BIN/yt-dlp.part" "$BIN/yt-dlp"

echo "Downloading deno"
curl -fsSL -o "$BIN/deno.zip" "https://github.com/denoland/deno/releases/latest/download/$DENO"
unzip -oq "$BIN/deno.zip" -d "$BIN"
rm -f "$BIN/deno.zip"

echo "yt-dlp $("$BIN/yt-dlp" --version) is ready"
