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
sealed it. The one other thing it acts on is a sealed *switch off* from the
panel ("hey canvas, turn the PC off"). It shows a notice for 30 seconds
with **Keep it on**, then runs `systemctl poweroff`. A *switch off* more
than two minutes old when it arrives, because it waited while the computer
was off, is dropped.

## Switching it on from the panel

"Turn the PC on" sends a Wake-on-LAN packet to the hardware address the
receiver reports (`X-Device-Wake`, from the network card the default route
leaves by). For that:

1. Turn Wake-on-LAN on in the firmware. It's often called *Power On by
   PCI-E* or *Wake on LAN*, and *ErP* must be off, or the card loses power
   when the computer is off.
2. Turn it on for the card, so it stays on across reboots:

   ```sh
   nmcli connection modify "Wired connection 1" 802-3-ethernet.wake-on-lan magic
   ```

   It takes effect the next time the connection comes up, for example at the
   next boot.
3. Mind the router. A broadcast doesn't cross from one network to another,
   so if the panel and the computer are on different subnets, the packet
   arrives only as a direct (unicast) one, which works while the router still
   has the computer's address cached. If that fails, connect the panel to the
   computer's network as well (a second cable or its Wi-Fi). Then the
   packet's broadcast to that network reaches the computer whatever the
   router does.

Only addresses on a home network are kept (10/8, 172.16/12, 192.168/16): a
request reaching the panel from outside isn't anyone's computer to wake.

To see whether the packet arrives, run this on the computer while saying
"turn the PC on" from elsewhere (it only shows anything if the computer is
up, so it tests the route, not the waking):

```sh
sudo tcpdump -ni any 'udp and (port 9 or port 7)'
``` The key, settings and where it got up to are in
`~/.config/homecanvas-links/`, readable by you alone.
