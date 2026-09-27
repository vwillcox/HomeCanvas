#!/bin/sh
# Boots the panel straight into HomeCanvas, without the Raspberry Pi desktop.
#
#   bash scripts/kiosk-session.sh            set it up (asks for sudo)
#   bash scripts/kiosk-session.sh remove     back to the desktop
#
# Run on the Pi. Takes effect at the next boot, or at once with
#   sudo systemctl restart lightdm
#
# The kiosk still needs a Wayland compositor — for itself, for the browser
# windows it opens and for the TV remote app — so labwc stays. What goes is
# the desktop around it: the taskbar (wf-panel-pi, some 370 MB and a
# redraw every so often, all day, behind the kiosk), the desktop icons
# (pcmanfm), the polkit agent and the desktop's autostart programs. Kept:
# kanshi, which turns the screen the right way up; squeekboard, the
# on-screen keyboard for typing a password into a sign-in page; the power
# button's handling; and everything ~/.config/labwc/autostart starts.
#
# labwc is given a config folder of its own, ~/.config/labwc-kiosk, and run
# without merging the system's (-m), which is where the desktop's autostart
# lives. Its rc.xml is a link to ~/.config/labwc/rc.xml, so the window rules
# and touchscreen mapping stay in one place.
#
# If the screen stays black: ssh in and run this with `remove`.

set -eu

KIOSK_DIR="$HOME/.config/labwc-kiosk"
SESSION=/usr/share/wayland-sessions/homecanvas.desktop
LIGHTDM=/etc/lightdm/lightdm.conf
DESKTOP=rpd-labwc

install() {
  if [ ! -f "$HOME/.config/labwc/autostart" ] || [ ! -f "$HOME/.config/labwc/rc.xml" ]; then
    echo "No ~/.config/labwc/autostart or rc.xml: run scripts/pi-setup.sh first." >&2
    exit 1
  fi

  mkdir -p "$KIOSK_DIR"
  ln -sf "$HOME/.config/labwc/rc.xml" "$KIOSK_DIR/rc.xml"

  # The Pi's own settings for labwc — keyboard layout, cursor, the renderer
  # options — under this session's name rather than the desktop's.
  grep -v '^DESKTOP_SESSION=' /etc/xdg/labwc/environment > "$KIOSK_DIR/environment"
  echo 'DESKTOP_SESSION=homecanvas' >> "$KIOSK_DIR/environment"

  cat > "$KIOSK_DIR/autostart" <<'EOF'
#!/bin/sh
# The HomeCanvas kiosk session. Written by scripts/kiosk-session.sh.

# The screen's rotation and mode, from ~/.config/kanshi/config.
/usr/bin/kanshi &

# Programs started by D-Bus — the keyboard, the portals — need to know
# which display to use.
/usr/bin/dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY

# For any X program opened through Xwayland.
/usr/bin/create_xauth

# The on-screen keyboard, when there is a touchscreen.
/usr/bin/sbtest &

# The power button, handled as the desktop handles it rather than as an
# instant shutdown.
systemd-inhibit --what=handle-power-key rpi-gui-nop &

# The kiosk and its services, exactly as in the desktop session.
. "$HOME/.config/labwc/autostart"
EOF

  sudo tee "$SESSION" > /dev/null <<EOF
[Desktop Entry]
Name=HomeCanvas kiosk
Comment=HomeCanvas on labwc, without the desktop
Exec=/usr/bin/labwc -C $KIOSK_DIR
Type=Application
EOF

  if [ ! -f "$LIGHTDM.before-kiosk" ]; then
    sudo cp "$LIGHTDM" "$LIGHTDM.before-kiosk"
  fi
  set_session homecanvas
  echo "Done. Reboot, or: sudo systemctl restart lightdm"
  echo "To go back: bash scripts/kiosk-session.sh remove"
}

remove() {
  set_session "$DESKTOP"
  echo "The desktop is back from the next boot, or: sudo systemctl restart lightdm"
}

# Sets the session LightDM logs in to, and offers by default.
set_session() {
  sudo sed -i \
    -e "s/^autologin-session=.*/autologin-session=$1/" \
    -e "s/^user-session=.*/user-session=$1/" \
    "$LIGHTDM"
  if ! grep -q "^autologin-session=$1\$" "$LIGHTDM"; then
    echo "Could not set the session in $LIGHTDM: is autologin set up there?" >&2
    exit 1
  fi
}

case "${1:-install}" in
  install) install ;;
  remove) remove ;;
  *) echo "Usage: $0 [install|remove]" >&2; exit 2 ;;
esac
