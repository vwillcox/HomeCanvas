#!/usr/bin/env bash
# Builds widgets uploaded as Dart from the editor into the app, on the panel.
#
#   widget-build.sh generate             write the registry from what is installed
#   widget-build.sh install <name>       take <name>.dart from incoming/, rebuild
#   widget-build.sh remove <name>        take it out, rebuild
#   widget-build.sh addons <id,id,…>     fetch these add-ons from the catalogue, rebuild
#   widget-build.sh addon-remove <id>    take an add-on out, rebuild
#   widget-build.sh rebuild              rebuild with what is installed
#
# Add-ons are the widgets in the catalogue (scripts/addons.py says which
# repository that is): a folder each under ~/.config/homecanvas/addons, with
# an addon.json saying what it is. HOMECANVAS_ADDONS points that somewhere
# else — at a checkout of the catalogue's widgets/ folder, to work on them.
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
ADDONS="${HOMECANVAS_ADDONS:-$HOME/.config/homecanvas/addons}"
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
# registers it: add-ons from the catalogue, a folder each, and widgets
# uploaded as single files. Each is asked for inside a try, so one whose
# description throws costs that widget, not the panel.
generate() {
  find "$DEST" -maxdepth 1 -name '*.dart' -delete
  rm -rf "$DEST/addons" "$ROOT/test/addons"
  local i=0 imports="" entries="" addons=""
  # Add-ons written in Dart: "id<TAB>entry" for each, as its addon.json
  # says. One described in JSON is not built in; the app reads it as it is.
  while IFS=$'\t' read -r id entry; do
    [ -n "$id" ] || continue
    mkdir -p "$DEST/addons/$id"
    cp "$ADDONS/$id"/*.dart "$ADDONS/$id/addon.json" "$DEST/addons/$id/"
    imports+="import 'addons/$id/$entry' as a$i;"$'\n'
    addons+="    '$id': () => a$i.widgetTypes,"$'\n'
    i=$((i + 1))
    # Their tests, for whoever is working on them: see the README.
    if [ "${HOMECANVAS_ADDON_TESTS:-}" = 1 ] && [ -d "$ADDONS/$id/test" ]; then
      mkdir -p "$ROOT/test/addons/$id"
      cp -r "$ADDONS/$id/test/." "$ROOT/test/addons/$id/"
    fi
  done < <(ADDONS="$ADDONS" python3 - <<'PY'
import json, os, re
root = os.environ["ADDONS"]
name = re.compile(r"^[a-z][a-z0-9_]{1,39}$")
part = re.compile(r"^[a-z][a-z0-9_]*\.dart$")
for id in sorted(os.listdir(root)) if os.path.isdir(root) else []:
    try:
        with open(os.path.join(root, id, "addon.json")) as f:
            m = json.load(f)
    except (OSError, ValueError):
        continue
    entry = m.get("entry", "")
    if (m.get("kind") == "dart" and name.match(id) and part.match(entry)
            and os.path.isfile(os.path.join(root, id, entry))):
        print(f"{id}\t{entry}")
PY
  )
  if [ "${HOMECANVAS_ADDON_TESTS:-}" = 1 ] && [ -d "$ADDONS/../tests" ]; then
    mkdir -p "$ROOT/test/addons"
    cp -r "$ADDONS/../tests/." "$ROOT/test/addons/"
  fi
  # Themes are not built in — a panel reads them from its themes folder —
  # but their tests read them: test/addons/themes/<theme id>.json.
  if [ "${HOMECANVAS_ADDON_TESTS:-}" = 1 ]; then
    ADDONS="$ADDONS" OUT="$ROOT/test/addons/themes" python3 - <<'PY'
import json, os, re, shutil
root, out = os.environ["ADDONS"], os.environ["OUT"]
name = re.compile(r"^[a-z][a-z0-9-]{1,39}$")
for id in sorted(os.listdir(root)) if os.path.isdir(root) else []:
    try:
        with open(os.path.join(root, id, "addon.json")) as f:
            m = json.load(f)
    except (OSError, ValueError):
        continue
    themes = m.get("themes") or []
    src = os.path.join(root, id, "theme.json")
    if m.get("kind") == "theme" and len(themes) == 1 and name.match(str(themes[0])) \
            and os.path.isfile(src):
        os.makedirs(out, exist_ok=True)
        shutil.copyfile(src, os.path.join(out, f"{themes[0]}.json"))
PY
  fi
  i=0
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
// Written by scripts/widget-build.sh from the add-ons installed and the
// widgets uploaded in the editor. Do not edit by hand: it is written again
// at every build.
import 'package:flutter/foundation.dart';

import '../../widget_registry.dart';
$imports
/// The add-ons installed from the catalogue and built into this copy of
/// the app, by name: each the widgets it brings.
final Map<String, List<DashboardWidgetType> Function()> addonWidgets = {
$addons};

/// The widgets uploaded as Dart from the editor and built into this copy
/// of the app, by the file each came from.
final Map<String, DashboardWidgetType Function()> customCodeWidgets = {
$entries};

/// Registers them: add-ons first, then uploads. One that throws, or that
/// names itself after a widget there already is, is left out and said so
/// in the log.
void registerCustomCodeWidgets() {
  void add(String from, DashboardWidgetType type) {
    if (WidgetRegistry.find(type.type) != null) {
      debugPrint('Widget \$from: "\${type.type}" is taken');
      return;
    }
    WidgetRegistry.register(type);
  }

  for (final e in addonWidgets.entries) {
    try {
      for (final type in e.value()) {
        add(e.key, type);
      }
    } catch (error) {
      debugPrint('Add-on \${e.key}: \$error');
    }
  }
  for (final e in customCodeWidgets.entries) {
    try {
      add(e.key, e.value());
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
# How long the last build that worked took here, for the editor's
# progress bar: a Pi 5 and a Pi 4 are minutes apart.
took = os.path.join(os.path.dirname(e["OUT"]), "took")
now = datetime.datetime.now(datetime.timezone.utc)
if e["STATE_"] == "ok":
    try:
        began = datetime.datetime.strptime(e["STARTED"], "%Y-%m-%dT%H:%M:%SZ")
        seconds = int((now.replace(tzinfo=None) - began).total_seconds())
        if 5 <= seconds <= 3600:
            with open(took, "w") as f:
                f.write(str(seconds))
    except (ValueError, OSError):
        pass
try:
    with open(took) as f:
        expected = int(f.read().strip())
except (OSError, ValueError):
    expected = None
with open(tmp, "w") as f:
    json.dump({
        "state": e["STATE_"],
        "step": e["STEP"],
        "action": e["ACTION"],
        "name": e["NAME"],
        "error": e["ERROR"],
        "started": e["STARTED"],
        "expected": expected,
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
  rm -rf "$SRC" "$ADDONS"
  cp -a "$STATE/src.prev" "$SRC"
  cp -a "$STATE/addons.prev" "$ADDONS"
  generate
}
restore_bundle() {
  [ -n "$BUNDLE" ] && [ -d "$STATE/bundle.prev" ] || return 0
  rm -rf "$BUNDLE"
  cp -a "$STATE/bundle.prev" "$BUNDLE"
}

[ -x "$FL" ] || fail checking "Flutter is not installed on this panel, so it cannot build widgets."
[ -n "$BUNDLE" ] || fail checking "This panel has no build of its own to rebuild."

mkdir -p "$ADDONS"
rm -rf "$STATE/src.prev" "$STATE/addons.prev"
cp -a "$SRC" "$STATE/src.prev"
cp -a "$ADDONS" "$STATE/addons.prev"

case "$ACTION" in
  install)
    [ -f "$STATE/incoming/$NAME.dart" ] || fail checking "Nothing was uploaded."
    mv "$STATE/incoming/$NAME.dart" "$SRC/$NAME.dart"
    ;;
  remove)
    rm -f "$SRC/$NAME.dart"
    ;;
  addons)
    # Fetched beside and checked against the catalogue's own sums before
    # any of it is put where the build will find it.
    rm -rf "$STATE/incoming-addons"
    # shellcheck disable=SC2086
    if ! fetched="$(python3 "$ROOT/scripts/addons.py" fetch \
      --dest "$STATE/incoming-addons" ${NAME//,/ } 2>&1)"; then
      fail checking "$fetched"
    fi
    for d in "$STATE/incoming-addons"/*/; do
      id="$(basename "$d")"
      rm -rf "${ADDONS:?}/$id"
      mv "$d" "$ADDONS/$id"
    done
    # Downloaded again: an update may fetch it once more.
    # shellcheck disable=SC2086
    python3 "$ROOT/scripts/addons.py" removed drop ${NAME//,/ } || true
    ;;
  addon-remove)
    [[ "$NAME" =~ ^[a-z][a-z0-9_]*$ ]] || fail checking "Unknown add-on."
    rm -rf "${ADDONS:?}/$NAME"
    # Taken off by hand: an update leaves it off, even with a tile of its
    # type still on the dashboard.
    python3 "$ROOT/scripts/addons.py" removed add "$NAME" || true
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
