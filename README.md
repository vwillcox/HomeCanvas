# HomeCanvas

**Turn a Raspberry Pi and a touchscreen into a wall display for your home:**
a photo frame for your own [Immich](https://immich.app) library, a dashboard
you arrange from your phone, and a speaker for Spotify.

| Photo frame | Dashboard |
|---|---|
| ![The slideshow, with the weather and what's playing in the corners](docs/screenshots/slideshow.jpg) | ![The dashboard: clock, weather, TV remote, now playing and the news](docs/screenshots/dashboard.jpg) |

Install on the Pi with one command. It walks you through the rest:

```bash
curl -fsSL https://raw.githubusercontent.com/vwillcox/HomeCanvas/main/install.sh | bash
```

Private by design: your photos stay on your own server, with no account and
no cloud of ours. ([What it does talk to](#privacy).) An open-source,
self-hosted alternative to DAKboard, Skylight and other smart photo frames.

---

It boots straight into a fullscreen kiosk — no desktop, no mouse, no keyboard.
Browse your albums, pinch to zoom photos, play videos, run a slideshow, and see
the local weather. It doubles as a speaker (Bluetooth or Spotify Connect), takes
photos and notes shared from a phone, and switches to a dashboard of nearly
forty widgets — clock, weather, calendar, news, trains, bins, chores, your
network and your servers — that you arrange from a browser.

Built with Flutter as a native Linux app, so it stays smooth on a Pi.

| | |
|---|---|
| **[Wiki](https://github.com/vwillcox/HomeCanvas/wiki)** | Start here: installing, what hardware you need, using it, every widget, the FAQ and troubleshooting. Questions go in [Discussions](https://github.com/vwillcox/HomeCanvas/discussions). |
| **[INSTALL.md](INSTALL.md)** | Setting it up: the hardware, the install, and every optional feature — Spotify, Bluetooth, the camera, the share inbox, the dashboard's widgets, turning the screen off with Alexa. Troubleshooting too. |
| **[VOICE.md](VOICE.md)** | Voice control: "hey canvas", heard and understood on the Pi — installing it, every command, and asking Home Assistant. |
| **[THEMES.md](THEMES.md)** | The seventeen themes, each shown on the real panel, and how to make your own. |
| **[TECHNICAL.md](TECHNICAL.md)** | How it works: the dashboard's widget registry and editor, the encryption, the visualiser, the APIs it talks to, the project layout, debug hooks and the libraries it is built on. |

---

## Screenshots

### Photos

| The home screen | An album |
|---|---|
| ![The home screen: a greeting, a mini player and the albums](docs/screenshots/home.jpg) | ![An album's photo wall](docs/screenshots/album.jpg) |
| A greeting and the library in numbers, a mini player while music plays, and the albums. | A photo wall with headings that follow the photos rather than the calendar. |

| Photo viewer | Slideshow |
|---|---|
| ![The photo viewer](docs/screenshots/photo-viewer.jpg) | ![The slideshow with the weather and now playing](docs/screenshots/slideshow.jpg) |
| Pinch, double-tap or the +/− buttons to zoom; swipe for the next. | Photo-frame mode: the weather and what's playing in the corners, drifting slowly so nothing burns in. |

![The weather panel expanded over the slideshow](docs/screenshots/weather.jpg)

Tap the weather in the corner for a fortnight's forecast.

![Slideshow animation](docs/screenshots/05-slideshow-animation.gif)

Ken Burns pan with a cross-fade between slides *(also as
[MP4](docs/screenshots/05-slideshow-animation.mp4))*.

### Now playing

![The full-screen player](docs/screenshots/now-playing.jpg)

When music is playing the player takes over the screen, with the album art
blurred behind, a visualiser of what is actually coming out of the speaker, and
controls sized for a thumb — like, shuffle, repeat and add-to-playlist included.
Shrink it and it tucks into the mini player on the home screen, or into the Now
playing tile on the dashboard.

### The dashboard

![The dashboard: clock, weather, TV remote, now playing and the news](docs/screenshots/dashboard.jpg)

A 12×8 grid of widgets in pages that turn themselves — or hold, with the pause
beside the page dots. Play and pause are in the top bar on every page whenever
something is playing. Pages can have hours of their own: a morning page from
six till nine, a night page after ten.

| Home lab | Network |
|---|---|
| ![Servers, services, notes, sun and moon, certificates, updates and a memory](docs/screenshots/dashboard-homelab.jpg) | ![UniFi network health, clients, devices, throughput and speed tests](docs/screenshots/dashboard-network.jpg) |
| This Pi and the NAS with disk health from SMART, services, certificates, updates, notes and a memory from this day. | UniFi health, who's on the network, the router and switches, and two speed tests: to the internet, and across your own wiring. |

| Around the house | Calendar and photos |
|---|---|
| ![Grid carbon, on this day in history, train departures and chores](docs/screenshots/dashboard-around-the-house.jpg) | ![A month calendar beside a photo](docs/screenshots/dashboard-calendar.jpg) |
| How clean the electricity is, the next trains, a chores chart with stars, and something from history. | Your calendars and a photo from Immich. |

| The full forecast | Switching TV inputs |
|---|---|
| ![The full forecast](docs/screenshots/forecast.jpg) | ![The TV inputs](docs/screenshots/tv-inputs.jpg) |
| Tap the weather: now, the next 24 hours as a curve, and the week on one scale. | The TV remote's Input button: every input, and what is plugged into each. |

![The Omarchy hotkeys cheat sheet](docs/screenshots/dashboard-omarchy.jpg)

A page of its own for the Omarchy keyboard shortcuts.

### Themes

[![The themes](docs/screenshots/themes/all.jpg)](THEMES.md)

Seventeen themes, dark and light, glassy, glossy and flat, and one a starship's console, and each one dresses
the whole kiosk: the photo browser, the music player and Settings as well as
the dashboard. **[THEMES.md](THEMES.md)** shows each one full size.

| LCARS | The Home Assistant bridge |
|---|---|
| ![The dashboard in the LCARS theme](docs/screenshots/themes/lcars.jpg) | ![The Home Assistant bridge in LCARS](docs/screenshots/themes/lcars/bridge.jpg) |
| A starship's console: bars swept round every panel, block buttons, and frames that step into place. | The house as a console: rooms down the side, a switch for each light. |

### Arranged from a browser

![The dashboard editor in a browser](docs/screenshots/editor.jpg)

The editor runs on the panel and opens in any browser on your network. The
previews are the panel's own drawing of each widget, so what you lay out is
what you get. Widgets come in folding groups; drag to place and resize,
reorder pages by dragging their tabs.

### Installed from the terminal

The installer runs full screen in the terminal, over SSH or on the Pi itself.
It asks everything first, shows you the list, and only then changes
anything. Run it again later to update, to change widgets and theme, or to
pick a new wake word.

| Welcome back | Choosing widgets |
|---|---|
| ![The installer offering to update, change widgets, or set up voice control](docs/screenshots/installer/welcome.png) | ![A checklist of every widget, grouped as in the editor](docs/screenshots/installer/widgets.png) |
| On an installed panel: update, change the widgets and theme, or set up voice control. | Start from a preset, then tick any of the 71 widgets. Each says what it needs. |

| A theme, previewed | Your own wake word |
|---|---|
| ![The theme list with a preview of LCARS](docs/screenshots/installer/theme.png) | ![A wake word being typed, with a check under it](docs/screenshots/installer/wake-word.png) |
| A preview of each theme's colours as you move through the list. | Checked as you type: commands, common words and very short names are caught. |

| Teaching it how you say it | How it went |
|---|---|
| ![The wizard listening, with a microphone meter and what it heard each time](docs/screenshots/installer/teaching.png) | ![The verdict: heard 4 of 5, learned two mishearings, now 5 of 5](docs/screenshots/installer/verdict.png) |
| Say it five times; both recognisers write down what they heard. | It keeps how they misheard you, then checks everyday speech doesn't set it off. |

![The list of what will happen, before anything is installed](docs/screenshots/installer/review.png)

Nothing is changed until you've seen this list and chosen **Install**.

### Settings and more

| Settings | About |
|---|---|
| ![Settings, in tabs](docs/screenshots/settings.jpg) | ![The About screen](docs/screenshots/about.jpg) |
| In seven tabs: Photos, Music, Home, Display, Volumes, Sharing and System. | Every library the app is built on, with its licence. |

![A shared link open in Firefox](docs/screenshots/10-firefox-article.jpg)

A link shared from a phone opens in Firefox with the browser's furniture hidden
and a close button the kiosk draws itself.

> Personal details in these screenshots — the server's address, device names,
> the household's notes and the album covers on the home screen — are blurred or
> pixelated. Album artwork shown is © its respective rights holder, fetched live
> to demonstrate the UI; this project claims no ownership of it.

---

## Features

**Photos & video** — every Immich album, sortable and with empty ones hidden;
a full-screen viewer with pinch-zoom, double-tap zoom and swipe; video via
libmpv with speed, scrub, zoom and volume; portrait and landscape uncropped.

**YouTube** — links shared from the phone play on the panel, full screen or
as a picture-in-picture window you can drag and resize over anything else; a
dashboard widget lists your subscriptions to pick from, and signing in brings
Premium and members-only videos. Up to 1080p60. **Floatplane** and
**Nebula** too: widgets of your creators' latest videos, played the same way
(Nebula's HEVC decoded by the Pi's hardware).

**Slideshow** — fade, slide, Ken Burns or page-turn transitions, shuffle, a
blurred backdrop behind letterboxed shots, and several albums played as one.

**Music** — pair a phone over Bluetooth and the Pi becomes its speaker, or play
Spotify on it directly as a Connect device named "Kiosk". With Premium the panel
controls the account: seek, like, add to a playlist, pick the device, see the
queue.

**The dashboard** — nearly forty widgets in groups, arranged from a browser:

| Group | Widgets |
|---|---|
| Time & day | Clock, Calendar, Timers, Sun & moon, Countdowns (with bank holidays) |
| Weather & air | Weather with a full forecast, Air & pollen, Rain soon |
| Photos, music & TV | Now playing, TV remote, Photo, On this day, Immich library, Birthdays |
| Around the house | Bin day, Notes, Shopping list, Grid carbon, Lights (Govee), Home Assistant, Meal plan, Chores & rewards |
| Getting out | Train departures |
| News & reference | News feeds (with adverts filtered out), On this day in history, Omarchy hotkeys |
| Network | UniFi health, Who's home, UniFi devices, Network clients, WAN throughput, ISP speed test, Speed test, LAN speed test |
| Home lab | Servers (with SMART disk health), Services, Certificates, Updates |

Seventeen [themes](THEMES.md) — dark and light, glassy, glossy and flat, and LCARS, dressing the whole kiosk — plus a JSON template for your own, twenty-one fonts, per-widget sizing,
pages and widgets that show only at certain hours, and an optional background
of your own photos behind the tiles.

**Share Inbox** — a companion Android app (in this repo) shares photos, GIFs,
videos, links and notes to the kiosk from any app's share sheet, from anywhere,
**end-to-end encrypted** with a fresh key per message. Notes can be read aloud
by a voice that runs on the Pi.

**A phone as a camera** — an old Android phone running IP Webcam becomes a
camera in a corner window; pinch to drive the phone's own zoom.

**Private content** — opens Immich's Locked Folder with your PIN, and re-locks
when you leave.

**Voice control** — say "hey canvas, show the stocks", "next page" or "pause the
music"; anything else goes to Home Assistant. Heard and understood on the Pi;
see [VOICE.md](VOICE.md).

**Built for a wall** — panels drift slowly against burn-in; the screen turns
itself off when idle and wakes on touch (or by voice, through Alexa); starts on
boot and restarts if it crashes; caches aggressively on disk.

---

## How it compares

There are other good ways to put Immich on a screen, and they suit different
set-ups:

- **[ImmichFrame](https://github.com/immichFrame/ImmichFrame)** and
  **[Immich Kiosk](https://github.com/damongolding/immich-kiosk)** are
  slideshows that run in a browser or on a TV, so they work on almost any
  device. Choose them if you want a photo frame and nothing else.
- **[Picture Frame](https://github.com/MateEke/picture-frame)** is a light
  Raspberry Pi photo frame that runs even on a Pi Zero.
- **DAKboard** and **Skylight** are polished commercial wall displays, with a
  subscription and your data in their cloud.

HomeCanvas is for a touchscreen you walk up to and use. It's a native app,
so you browse albums, zoom photos and play video by hand. It adds a
dashboard of nearly forty widgets you arrange from your phone, and plays
music. It needs a Pi 4 or 5 (or another 64-bit Linux machine), and it's
all self-hosted.

---

## Getting started

You need a **Raspberry Pi 5** (or 4) with a touch display, running **Raspberry
Pi OS** (trixie), and an **Immich server**. On the Pi, open a terminal and run:

```bash
curl -fsSL https://raw.githubusercontent.com/vwillcox/HomeCanvas/main/install.sh | bash
```

The [installer](#installed-from-the-terminal) opens full screen in the
terminal and asks everything first: your Immich, the widgets you want, a
theme, voice control and its wake word, and the extras they need. Then it
shows you the list and does it all: it installs what's needed, builds
HomeCanvas, names it on your network, starts it on boot, and teaches it your
wake word. Run the same command again later to update or change things. It also works on Debian, Ubuntu, Fedora, Arch and openSUSE, on 64-bit
ARM or Intel/AMD.

**[INSTALL.md](INSTALL.md)** has the steps done by hand, and the optional
extras: Spotify, the weather, Home Assistant, sharing from your phone.

---

## Privacy

HomeCanvas talks to your own Immich server, and to a public service only when
you add a widget that needs one — Open-Meteo for the weather, National Grid ESO
for grid carbon, Realtime Trains for departures — sending no more than that
widget needs: a place, a postcode district, a station. No analytics, no
accounts of ours. Your credentials live in `~/.config/homecanvas/config.json` on
the device and are never committed. Shares from the companion app are
end-to-end encrypted, so even a reverse proxy in the path cannot read them.

---

## Licence

[MIT](LICENSE) — do what you like with it, no warranty.

Third-party libraries, their licences and credits for adapted code are in
[TECHNICAL.md](TECHNICAL.md#third-party-libraries) and on the device under
**Settings → System → About**, so attribution travels with the app.
