#!/usr/bin/env bash
# Store a Homey's address and API key in the HomeCanvas config, for the
# Homey widgets on the dashboard — instead of typing a long key on the
# panel's own keyboard in Settings -> Home -> Homey.
#
# Create the key at my.homey.app: Settings -> API Keys, allowed to see and
# control devices, and to see zones and flows.
#
# Run on the Pi:  bash ~/homecanvas/scripts/set-homey-key.sh
set -e
CONFIG="$HOME/.config/homecanvas/config.json"
[ -f "$CONFIG" ] || { echo "Config not found at $CONFIG"; exit 1; }

read -rp "Homey's address on your network (e.g. 192.168.1.50): " ADDRESS
[ -n "$ADDRESS" ] || { echo "Address is required"; exit 1; }

# Read silently: the key is a credential and shouldn't land in scrollback.
read -rsp "Homey API key: " KEY; echo
[ -n "$KEY" ] || { echo "Key is required"; exit 1; }

# Through the environment, not the command line, where `ps` would show it.
ADDRESS="$ADDRESS" KEY="$KEY" python3 - "$CONFIG" <<'PY'
import json, os, sys, urllib.request, urllib.error

path = sys.argv[1]
address, key = os.environ["ADDRESS"].strip().rstrip("/"), os.environ["KEY"].strip()
base = address if "://" in address else "http://" + address

# Check the key works before saving it, so a typo is caught here rather than
# showing up later as an empty tile. A self-hosted Homey listens on 4859.
has_port = ":" in base.split("://", 1)[1]
for root in [base] + ([] if has_port else [base + ":4859"]):
    req = urllib.request.Request(
        root + "/api/manager/devices/device",
        headers={"Authorization": "Bearer " + key},
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            print(f"Homey at {root} answered: {len(json.load(r))} devices")
            break
    except urllib.error.HTTPError as e:
        sys.exit(f"Homey at {root} refused the key (HTTP {e.code}). Nothing saved.")
    except Exception as e:
        print(f"Nothing at {root}: {e}")
else:
    sys.exit("Could not reach Homey. Nothing saved.")

d = json.load(open(path))
d["homey"] = {"address": address, "apiKey": key}
tmp = path + ".part"
fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    json.dump(d, f, indent=2)
os.replace(tmp, path)
print("Saved. Restart the kiosk to pick it up: systemctl --user restart homecanvas")
PY
