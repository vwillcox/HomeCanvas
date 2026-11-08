# Links from the panel, on a computer

Touch **Send to…** on a post, a news story or an open page on the panel, pick
this computer, and the page opens in your browser here, with a notification
saying where it came from.

`homecanvas-links` asks the panel for links over the Share Inbox's port, a
request at a time held open until there is one. Each link is sealed on the
panel to this computer's own key, so nothing in between can read it. It needs
Python 3 and `python-cryptography` (`pacman -S python-cryptography`,
`apt install python3-cryptography`), and `xdg-open` and `notify-send`.

## Setting it up

In the panel's **Settings → Share Inbox**, add a sender for the computer (or
use your own) and copy its token. Then:

```bash
install -Dm755 companion_pc/homecanvas-links ~/.local/bin/homecanvas-links
homecanvas-links setup http://192.168.1.57:8081 TOKEN
```

The address is the Share Inbox's: the panel's own on the home network, or
whatever reaches it from outside, the same one the phone app uses. A third
argument names the computer in the panel's list; otherwise it is the host
name. It prints the computer's key id, and the panel lists the same one under
"Receiving links" once it has asked.

To run it whenever you are logged in:

```bash
install -Dm644 companion_pc/homecanvas-links.service \
    ~/.config/systemd/user/homecanvas-links.service
systemctl --user enable --now homecanvas-links
journalctl --user -u homecanvas-links -f     # what it is doing
```

`homecanvas-links --once` collects what is waiting and stops, for trying it.

Only web pages are opened: a link that is anything else is refused, whoever
sealed it. The key, settings and where it got up to are in
`~/.config/homecanvas-links/`, readable by you alone.
