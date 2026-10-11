#!/usr/bin/env bash
# Builds widgets uploaded as Dart from the editor into the app, on the panel.
#
#   widget-build.sh generate         write the registry from what is installed
#   widget-build.sh install <name>   take <name>.dart from incoming/, rebuild
#   widget-build.sh remove <name>    take it out, rebuild
#   widget-build.sh rebuild          rebuild with what is installed
#
# The kiosk starts this in a unit of its own (systemd-run), so that the
# restart at the end does not take the builder down with the kiosk.
#
# A build either lands whole or not at all. Before anything is touched the
# installed widgets and the built app are copied aside; the new source is
# then checked, built, started and asked whether it is up. If any of those
# fails, both are put back as they were — and the kiosk restarted on the old
# build if it had been restarted on the new — and what went wrong is left in
# status.json for the editor to show whoever uploaded it.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${HOMECANVAS_WIDGETS:-$HOME/.config/homecanvas/widgets-src}"
STATE="${HOMECANVAS_WIDGET_STATE:-$HOME/.local/share/homecanvas/widget-build}"
CONFIG="$HOME/.config/homecanvas/config.json"
DEST="$ROOT/lib/dashboard/widgets/custom"
STATUS="$STATE/status.json"
LOG="$STATE/build.log"
ACTION="${1:-}"
NAME="${2:-}"
STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "$SRC" "$STATE" "$DEST"

# Copies what is installed into the source tree and writes the file that
# registers it. Each widget is asked for inside a try, so one whose
# description throws costs that widget, not the panel.
generate() {
  find "$DEST" -maxdepth 1 -name '*.dart' -delete
  local i=0 imports="" entries=""
  for f in "$SRC"/*.dart; do
    [ -f "$f" ] || continue
    local base
    base="$(basename "$f")"
    [[ "$base" =~ ^[a-z][a-z0-9_]*\.dart$ ]] || continue
    [ "$base" = custom_registry.dart ] && continue
    cp "$f" "$DEST/$base"
    imports+="import '$base' as w$i;"$'\n'
    entries+="    '$base': () => w$i.widgetType,"$'\n'
    i=$((i + 1))
  done
  cat >"$DEST/custom_registry.dart" <<DART
// Written by scripts/widget-build.sh from the widgets uploaded in the
// editor. Do not edit by hand: it is written again at every build.
import 'package:flutter/foundation.dart';

import '../../widget_registry.dart';
$imports
/// The widgets uploaded as Dart from the editor and built into this copy
/// of the app, by the file each came from.
final Map<String, DashboardWidgetType Function()> customCodeWidgets = {
$entries};

/// Registers them. One that throws, or that names itself after a widget
/// there already is, is left out and said so in the log.
void registerCustomCodeWidgets() {
  for (final e in customCodeWidgets.entries) {
    try {
      final type = e.value();
      if (WidgetRegistry.find(type.type) != null) {
        debugPrint('Custom widget \${e.key}: "\${type.type}" is taken');
        continue;
      }
      WidgetRegistry.register(type);
    } catch (error) {
      debugPrint('Custom widget \${e.key}: \$error');
    }
  }
}
DART
}

if [ "$ACTION" = generate ]; then
  generate
  exit 0
fi

# What the editor shows: where the build has got to, or how it ended.
status() { # state step [error]
  STATE_="$1" STEP="$2" ERROR="${3:-}" ACTION="$ACTION" NAME="$NAME" \
    STARTED="$STARTED" OUT="$STATUS" python3 - <<'PY'
import json, os, datetime
e = os.environ
done = e["STATE_"] != "building"
tmp = e["OUT"] + ".part"
with open(tmp, "w") as f:
    json.dump({
        "state": e["STATE_"],
        "step": e["STEP"],
        "action": e["ACTION"],
        "name": e["NAME"],
        "error": e["ERROR"],
        "started": e["STARTED"],
        "finished": datetime.datetime.now(datetime.timezone.utc)
            .strftime("%Y-%m-%dT%H:%M:%SZ") if done else None,
    }, f)
os.replace(tmp, e["OUT"])
PY
}

# One build at a time.
exec 9>"$STATE/lock"
if ! flock -n 9; then
  echo "A build is already running." >&2
  exit 3
fi

FL="$(command -v flutter || true)"
[ -n "$FL" ] || FL="$HOME/flutter/bin/flutter"
BUNDLE="$(ls -d "$ROOT"/build/linux/*/release/bundle 2>/dev/null | head -1)"
: >"$LOG"
status building checking

fail() { # step message
  status failed "$1" "$2"
  echo "FAILED at $1" >>"$LOG"
  exit 1
}

# As they were before this build began.
restore_sources() {
  rm -rf "$SRC"
  cp -a "$STATE/src.prev" "$SRC"
  generate
}
restore_bundle() {
  [ -n "$BUNDLE" ] && [ -d "$STATE/bundle.prev" ] || return 0
  rm -rf "$BUNDLE"
  cp -a "$STATE/bundle.prev" "$BUNDLE"
}

[ -x "$FL" ] || fail checking "Flutter is not installed on this panel, so it cannot build widgets."
[ -n "$BUNDLE" ] || fail checking "This panel has no build of its own to rebuild."

rm -rf "$STATE/src.prev"
cp -a "$SRC" "$STATE/src.prev"

case "$ACTION" in
  install)
    [ -f "$STATE/incoming/$NAME.dart" ] || fail checking "Nothing was uploaded."
    mv "$STATE/incoming/$NAME.dart" "$SRC/$NAME.dart"
    ;;
  remove)
    rm -f "$SRC/$NAME.dart"
    ;;
  rebuild) ;;
  *)
    fail checking "Unknown action."
    ;;
esac
generate

# Checked before it is built: quicker, the build untouched if it is wrong,
# and the analyser's errors name the line.
cd "$ROOT" || fail checking "The source is not where it was."
if ! "$FL" analyze --no-pub --no-fatal-infos --no-fatal-warnings \
  lib/dashboard/widgets/custom >>"$LOG" 2>&1 ||
  [ "${HOMECANVAS_TEST_FAIL:-}" = check ]; then
  errors="$(grep -E '^[[:space:]]*error •' "$LOG" |
    sed -e 's/^[[:space:]]*//' -e 's#lib/dashboard/widgets/custom/##g' | head -40)"
  [ -n "$errors" ] || errors="$(tail -30 "$LOG")"
  restore_sources
  fail checking "$errors"
fi

status building building
rm -rf "$STATE/bundle.prev"
cp -a "$BUNDLE" "$STATE/bundle.prev"
if ! "$FL" build linux --release >>"$LOG" 2>&1 ||
  [ "${HOMECANVAS_TEST_FAIL:-}" = build ]; then
  errors="$(grep -iE 'error' "$LOG" |
    sed -e 's#lib/dashboard/widgets/custom/##g' | head -40)"
  [ -n "$errors" ] || errors="$(tail -30 "$LOG")"
  restore_bundle
  restore_sources
  fail building "$errors"
fi

# Up when the editor answers, twice running: a build that starts and falls
# over is not up.
up() {
  local port
  port="$(python3 -c "
import json, sys
try: print(json.load(open(sys.argv[1])).get('dashboard', {}).get('editorPort', 8090))
except Exception: print(8090)" "$CONFIG")"
  local good=0
  for _ in $(seq 1 30); do
    sleep 2
    if curl -sf -m 3 -o /dev/null "http://127.0.0.1:$port/api/widgets/build"; then
      good=$((good + 1))
      [ "$good" -ge 2 ] && return 0
    else
      good=0
    fi
  done
  return 1
}

status building restarting
systemctl --user restart homecanvas.service >>"$LOG" 2>&1
if [ "${HOMECANVAS_TEST_FAIL:-}" = start ] || ! up; then
  restore_bundle
  restore_sources
  systemctl --user restart homecanvas.service >>"$LOG" 2>&1
  fail restarting "It built, but the panel did not start with it. The panel is back on the build it had."
fi

status ok done
exit 0
