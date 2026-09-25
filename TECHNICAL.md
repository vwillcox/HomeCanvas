# ImmichKioskPi — technical notes

How it works, and why it is the way it is rather than the obvious way. For
setting it up, see [INSTALL.md](INSTALL.md).

- [Overview](#overview)
- [The dashboard](#the-dashboard)
- [Music](#music)
- [Photos](#photos)
- [The news, the forecast and the TV](#the-news-the-forecast-and-the-tv)
- [Sharing and encryption](#sharing-and-encryption)
- [The camera](#the-camera)
- [The screen](#the-screen)
- [One look throughout](#one-look-throughout)
- [Talking to other things](#talking-to-other-things)
- [Development](#development)
- [Third-party libraries](#third-party-libraries)
- [Credits and sources](#credits-and-sources)

---

## Overview

A Flutter app built as a native **arm64 Linux** binary, running fullscreen and
borderless under the **labwc** Wayland compositor on Raspberry Pi OS. State is
held in `ChangeNotifier` services handed down with `provider`; each screen and
widget watches the ones it needs. Configuration is one JSON file,
`~/.config/immich_kiosk_pi/config.json`, read and written by `ConfigService`;
things the household adds — notes, the shopping list, chores done — are kept in
small files beside it (`notes.json`, `shopping.json`, `chores.json`), written
atomically through a temporary file.

Around the app, a few small pieces on the Pi:

| Piece | What it is |
|---|---|
| `immich_kiosk_pi.service` | the app, a systemd **user** unit started from labwc's autostart |
| `screen_control.py` | screen power and touch-to-wake, on `127.0.0.1:8765` |
| The kiosk's control endpoint | lets the TV remote app open places in the kiosk, on `127.0.0.1:8766` |
| The editor | the dashboard editor and household pages, on port 8090 |
| The share listener | shares from the companion app, on port 8081 |
| `librespot.service` | the Spotify Connect device |

---

## The dashboard

### Widgets are described, not wired in

A widget is a Flutter widget plus a `DashboardWidgetType`: its name, glyph,
group, default and smallest size, and its **options** — text, number, switch,
choice, colour, multi-line, a list of rows, or a secret. Nothing else in the
app needs changing to add one: the editor builds its palette and its settings
forms from those descriptions, served at `/api/schema`, and the saved
dashboard keeps each widget's options as an opaque bag. A `secret` option is
shown as a password box in the editor, so a token is not on screen for anyone
passing.

[`lib/dashboard/widgets/README.md`](lib/dashboard/widgets/README.md) walks
through adding one.

Widgets are grouped (`WidgetCategory`: Time & day, Weather & air, Photos, music
& TV, Around the house, Getting out, News & reference, Network, Home lab) for
the editor's palette, where each group folds like the other panels and
remembers whether it was open.

### Fitting any size of tile

Any widget can be made any size from its minimum up to the whole 12×8 grid, on
panels of other shapes too, so nothing is laid out in fixed pixels. Two tools
do most of the work:

- **`FitCanvas`** lays a widget out on a design canvas of a fixed height and
  scales the result to the tile, up to a limit — so a clock designed at one
  size stays in proportion at every other.
- **`bestGrid`** picks the columns and rows for *n* items in a tile of a given
  shape, so six chores or eight lights fill the space they are given.

Inside those, crowded rows give way rather than overflow: `Flexible` and
`Expanded` for what can shrink, `FittedBox(scaleDown)` for what must stay whole.
A widget that can't manage that opts out with `fitsItself: false` and is
shrunk as a whole by the tile instead.

The tests sweep every widget through every shape from 1×1 to 12×8 that its
minimum allows and fail on any overflow. The test font draws every glyph as a
square, which makes text wider than it really is — a widget that fits there has
room to spare on the panel.

### Previews are the panel's own drawing

The editor's tiles show exactly what the panel would draw, because the panel
draws them. `POST /api/render` takes a widget's settings and a size, and
`TileRenderHost` — an off-screen part of the running app — builds the real
`DashboardTile` for it, paints it to an image and returns a PNG. The editor lays
that over its tile and refreshes it every half minute and after every change.

Widgets that fetch something keep their last result in a static cache for a
few seconds, so a preview rendered in a fresh widget shows data rather than a
spinner.

### The editor's HTTP API

Served by `DashboardService` on port 8090, meant for the home network — don't
forward this port. The senders page, which hands out share tokens, refuses
anything from outside the private address ranges even so. Adding to the notes
and the shopping list must come from the page itself: a request whose `Origin`
does not match its `Host` is refused, so another site open in a phone's
browser cannot post to them.

| Request | Does |
|---|---|
| `GET /` | the editor (`assets/dashboard/editor.html`) |
| `GET /api/schema` | the widget types, groups, themes, fonts, sizes and dynamic lists (Home Assistant entities, albums) |
| `GET /api/dashboard`, `PUT /api/dashboard` | the saved dashboard |
| `GET /api/preview` | the panel's live content, for the editor's chrome |
| `POST /api/render` | a PNG of one widget, drawn by the app |
| `GET /api/background.jpg` | the photo behind the dashboard now |
| `GET /notes`, `/api/notes` | the phone page for posting a note, and its API |
| `GET /list`, `/api/list` | the shopping list page, and its API |
| `GET /senders`, `/api/senders` | share-inbox senders and their tokens |
| `GET /fonts/…` | the dashboard's fonts, for the editor |

Nothing is saved until **Save to panel** sends the whole dashboard back with
`PUT`. The editor keeps focus while typing by redrawing only the canvas, not the
form, on every keystroke.

### Pages, hours and turning

The saved dashboard has a list of widgets, each with a `page`, and an optional
list of **pages** carrying a name and a `Schedule` — from, to and days.
`Schedule.activeAt` handles windows that run past midnight (22:00–06:30), which
count as belonging to the day they start. `visiblePages` gives the pages whose
hours are on; if none are, it gives them all, since an empty panel is never
the right answer. The screen looks again every thirty seconds and goes straight
to a page whose hours have just begun. Widgets have the same `schedule`,
stored only when it is not "always".

The automatic turn is an `AnimationController` running from 0 to 1 over the
page's time. That same value fills the current page's dot, so a turn is never a
surprise; pausing is stopping the animation, and a paused dot breathes so a
held page reads as held rather than stuck. Any touch on a page restarts its
time, and the page stays put while the full music player is open.

### The photo background

`PhotoBackdrop` sits behind the grid: a pool of Immich photos (the whole
library at random, or one album) cross-fading every few minutes, under a
gradient that is darker at the top where the greeting sits. A random pool is
topped up before it runs out rather than repeated. Its current photo is what
`/api/background.jpg` serves, so the editor shows the same one.

### Music on the dashboard

The home screen's full-screen player, `NowPlayingOverlay`, is reused: a
`NowPlayingOverlayController` handed to the tiles through an `InheritedWidget`
(`NowPlayingOpener`) lets a Now playing tile or the top bar's controls open it
from wherever they are — it grows out of whatever was tapped and shrinks back
into it.

### Emoji

Flutter on the Pi does not fall back to the system's emoji font by itself, so
`fontFallback` in `lib/theme.dart` names Noto Color Emoji. Naming any fallback
also replaces Flutter's own list of Linux default fonts, and text with no font
of its own then draws no letters at all — so those defaults are named too, in
Flutter's order, with the emoji font straight after the one in use. The
dashboard's tiles set a fresh text style rather than a merged one, so they name
it again. Anything the app must always show — stars, ticks — is drawn with
Material icons instead, so it works on a Pi without the font.

### The speed tests

Both speeds share **one dial**, because the pair is the interesting thing — a
line is "200 down, 20 up", and reading that off two gauges makes you do the
comparison yourself.

The scale is **logarithmic**, one power of ten per equal sweep. A linear dial
calibrated for a gigabit line squashes everything under about 50 Mbps into the
first few degrees, so 20 Mbps and 2 Mbps look identical — which is exactly when
you are looking at it.

The internet test runs Ookla's CLI (see [INSTALL.md](INSTALL.md#speed-test)).
It reads Ookla's `--format=jsonl` stream — one JSON object per line as the test
runs, which is what makes a live display possible. Ookla's `--format=json`
prints nothing at all until the test has finished, and Debian's `speedtest-cli`
is a different program with different output.

Bandwidth arrives as **bytes per second** and is converted to megabits here.
Getting that wrong is the classic way to report a line as an eighth of its real
speed.

The **LAN speed test** measures against a self-hosted OpenSpeedTest server.
It is **measured directly rather than by opening OpenSpeedTest's own page.** The page
would work, but on a Pi with no hardware acceleration it would measure
*Chromium's* throughput and report the browser's limits as the network's. The
widget reads the same `/downloading` and `/upload` endpoints itself.

Two details that matter for the numbers being true. It uses **four parallel
connections**, because a single TCP stream is limited by window size and
round-trip time long before a 2.5 Gb link is busy. And each phase runs for
**six seconds**: a single 30 MiB fetch completes in about a third of a second
on a fast LAN, which measures TCP slow start rather than the rate.

### Omarchy hotkeys

All 224 shortcuts from [omarchy.org/manual/hotkeys](https://omarchy.org/manual/hotkeys/),
as a cheat sheet sized for a page of its own — drop it in at 12×8 and give it
a dashboard page to itself.

They will not all fit on a screen at a size anybody can read from across a
room, so it does not try. It shows one of twenty sections at a time, and there
are three ways to move:

- **Tap a section tab.** The strip scrolls, and it follows the selection, so
  the highlight is never off the side where you cannot see which one you are
  on.
- **Tap the sheet** to turn the page; past the last page of a section it moves
  to the next one. The whole sheet is the target, not the rows — most of a
  short section is empty space.
- **A timer**, off by default. Under three seconds is treated as three, for the
  same reason the dashboard's own page timer has a floor.

Combinations are drawn as keycaps, split on the manual's own notation: ` + `
between the keys of one combination, ` or ` between alternatives, so
`Super + W or Super + Q` reads as two ways of doing the same thing rather than
a four-key chord. Anything else — `1/2/3/4`, `Print Screen`, `CapsLock M S` —
is left exactly as written and goes on one cap, because that is the manual's
own shorthand and rewriting it would invent notation you have never seen on
the page you are trying to memorise.

Columns, rows and page count are all worked out from the tile, so **larger
text means more pages rather than smaller rows**. Three sizes; the largest is
meant to be read from a sofa. On a tile too small for the page dots to mean
anything they become a `3 / 12` counter instead.

The list is **baked into the build**, not fetched. This is a cheat sheet on a
wall: it has to be right when the network is not, and scraping a documentation
page would put the panel one redesign away from showing nothing. The cost is
that it goes stale quietly, so `omarchyHotkeysFetched` in
`lib/dashboard/widgets/omarchy_hotkeys.dart` records when it was taken. Re-read
the manual and update that file when Omarchy changes.

> The **Quick emojis** section is transcribed verbatim, and one of its entries
> is crude. Pin the widget to a different section, or edit
> `omarchy_hotkeys.dart`, if the panel is somewhere that matters.

---

## Music

### Bluetooth (AVRCP)

The now-playing panel reads Bluetooth **AVRCP**, so it works with whatever app
your phone is using — no accounts or API keys.

With **Play the audio on this device** off, the Pi stops acting as an audio
sink but the panel keeps showing the track and the controls keep working. That
works because AVRCP's control channel is independent of the A2DP audio
stream, so `org.bluez.MediaPlayer1` survives with the audio profile switched
off. The setting is re-applied whenever the phone reconnects, since PipeWire
turns the audio profile back on by itself.

With the setting on, PipeWire routes the incoming stream to whatever output is
active. Check the link with:

```bash
pw-link -l | grep bluez
```

(`pactl` may not be installed on Raspberry Pi OS; `pw-link` and `wpctl` are the
PipeWire tools that are.)

Two things that look like faults but aren't: those links only exist while audio
is **actively streaming**, so a paused track shows none; and `wpctl inspect` can
report a stale `bluez5.profile`. Neither is a reliable way to tell whether audio
routing is enabled — the setting itself is the source of truth.

The volume slider sets **AVRCP absolute volume**, i.e. the level the phone is
sending — the same control as the phone's own volume buttons. It is not a local
mixer level for the Pi's output.

Album artwork isn't part of AVRCP, so it's looked up from the free
[iTunes Search API](https://performance-partners.apple.com/search-api) using the
artist and track name. Searching by track is markedly more reliable than by
album, because AVRCP album strings often carry suffixes like
`(Deluxe Version) [Explicit]`.

### The visualiser

The expanded player draws a spectrum (or a waveform) between the scrubber and
the transport controls. **Settings → Music → Visualiser** switches between
bars, waveform and off.

**Touch it to change style** — bars, waveform, off, and round again. The choice
is written to the config as you tap, so whatever it was left showing is what
comes back after a restart. Off leaves a slim strip with a faint equaliser mark
rather than vanishing, because a control that disappears when you switch it off
is a control you cannot switch on again.

Colour maps pitch: the sweep runs violet through blue, cyan and green to amber
and pink across the bars, bass on the left, and each bar brightens towards its
own tip so a peak reads as a peak rather than a longer block of flat colour.
The waveform uses the same stops laid across the width, so changing style
changes the shape rather than the whole look of the player.

The waveform is an envelope — the peak of each slice, not the mean, since
averaging a waveform mostly averages it away — and it is scaled to fill the
band on the same terms as the bars. Drawing raw sample values would give a
sliver: measured off this panel during ordinary playback, the median frame
peaks at 0.05 of full scale, which in a 112px band is about six pixels. Scaled,
the same music sits around 0.90.

It shows what is genuinely coming out of this device's speaker. `pw-record`
captures the default sink's **monitor**, the mix on its way out, so it hears the
phone over Bluetooth, librespot, and the spoken notifications, at the level they
are actually playing at:

```bash
PIPEWIRE_PROPS='{ stream.capture.sink=true }' pw-record --channels=1 \
  --rate=16000 --format=s16 --latency=20ms -
```

`stream.capture.sink` is the whole trick. Without it `pw-record` opens the
default *source*, which on this Pi is the USB speaker's microphone, and the bars
would dance to the room instead of the music. With no `--target` it follows
whatever the default sink is at the time, so changing output does not need the
capture restarting.

**It is silent when the audio is not on this device.** With "play the audio on
this device" off, or with Spotify handed to another speaker, the music never
passes through this sink and there is nothing here to draw. That is the
mechanism, not a fault.

Nothing runs unless something is looking at it. The capture process, the FFT and
the repainting only exist while the player is expanded *and* the track is
playing: collapsing it, pausing, paging away or setting the visualiser to off
all stop the subprocess outright. A silence stops the repainting too — the bars
settle to their floor and then nothing is pushed at the screen until sound
returns.

The bar heights follow the music rather than a fixed scale, so turning the
speaker down makes the bars smaller without emptying them. The window rises
quickly to meet a loud entry and falls back slowly, and it does not move at all
during a silence — letting it drift down through the gap between tracks is how a
visualiser ends up screaming at the first note of the next one. Its range was
measured off this panel rather than guessed: five seconds of ordinary music put
the median band about 17 dB below the peaks, which is why `rangeDb` is 34.

### Spotify

The Web API control uses OAuth Authorization Code with PKCE, so no client secret
is stored. Rate limiting honours Spotify's `Retry-After` per endpoint rather
than retrying through 429s.

> Spotify replaced several library/playlist endpoints in February 2026 (the old
> per-type `/me/tracks` and `/playlists/{id}/tracks` now 403 silently); this
> integration uses the current `/me/library` and `/playlists/{id}/items`.

**On transferring playback away from the kiosk:** stock librespot restarts the
track from the beginning when you move playback from "Kiosk" to another device,
if you're playing from a large context like Liked Songs — an
[upstream bug](https://github.com/librespot-org/librespot/issues/1459) open
since January 2025. [`patches/`](patches/) carries a fix, with the cause and how
to build it.

**On audio quality:** the unit passes `--bitrate 320`, the highest Ogg Vorbis
quality Connect carries (the default is 160 without it). True lossless isn't
reachable on any Connect device — Spotify's Lossless tier only streams inside
its own apps, over a different pipeline entirely.

#### The DJ, and podcasts

While Spotify's DJ, X, is talking between tracks, the Web API says it is
playing but names no track — `item` is null and the context is the DJ's
playlist. The kiosk used to read that as "nothing playing", so the full-screen
player folded itself away every time the DJ spoke. It now shows **DJ X ·
Talking between tracks** instead, keeps the last track's artwork behind it,
and hides the scrubber, since there is no track to scrub.

Anything else that is playing but unnamed shows as **Playing on Spotify** and
keeps the player up the same way. That is the fallback if Spotify ever changes
the DJ playlist's id: the label goes generic, but the player stays.

Podcasts had the same problem for a different reason: the API leaves episodes
out unless asked. The poll now asks, so an episode shows its title and show.
It cannot be liked from the panel, since liking works on tracks.

And the player no longer hides on the first empty reply. Spotify answers with
nothing for a poll or two at some handovers; the panel now waits twelve seconds
of genuinely nothing before folding away.

---

## Photos

### The photo browser

The home screen leads with a greeting, the date and the library in numbers,
with the controls gathered into one frosted pill at the top right rather than a
title bar. Albums are cards with the cover edge to edge and the name over a
shadow at the foot, sortable by **Recent**, **A–Z** or **Most items**. **Empty
albums are hidden** — a grey tile that opens onto "This album is empty" is not
worth a place on a wall of photographs — and the counts in the header only
count what is shown.

When something is playing and the now-playing player is switched on, a **mini
player** sits above the albums, with its own previous, play/pause and next.
Tap anywhere else on it and the full player grows out of it; close the full
player and it shrinks back into it, wherever the page has scrolled to.

Inside an album there is a large header with the counts and the years it
covers, a Slideshow button, and a photo wall with thin gaps. Headings follow
the photos rather than the calendar: a month with a row's worth keeps its own
heading, and runs of thin months share one — "May – July 2026", "2016 – 2025".
Grouping strictly by month made the Family album a heading over every lone
picture: 36 months, 19 of them holding fewer than four photos. A full month is
never folded into a range, and undated photos are never given a date by one.

Dates come from Immich's `localDateTime`, which is the camera's wall-clock time
written with a "Z" it does not mean — so it is read as-is, never converted to
the Pi's time zone, or a photo from late on the last of a month would move to
the next one.

### Caching

Images and API responses are cached under `~/.cache/immich_kiosk_pi` —
deliberately **not** in `/tmp`, which on Raspberry Pi OS is a RAM-backed tmpfs.
The cache holds up to 20,000 files for a year, so restarts are near-instant.
Clear it any time from **Settings → Photos → Storage**.

---

## The news, the forecast and the TV

### Reading the news

Tapping a headline shows the feed's own summary first; **Read the page** opens
the article in Firefox's **reader view** — the text and pictures only, with no
adverts, no cookie banner and no autoplaying video. On a panel with nobody in
front of it most of the time, that last part matters: a consent dialog nobody
answers leaves the page unusable.

It is asked for by address, `about:reader?url=…`, on Firefox's command line.
That was checked on the panel's own Firefox 153 rather than assumed, because
Firefox refuses most `about:` pages from outside and this one could as easily
have been on that list.

**The text is sized to fill the screen.** Firefox measures the reader's column
in *ems* — its width slider runs from 20em to 60em — so the same setting is a
narrow strip at small text and wider than the window at large text. The kiosk
works it out from the window instead: at whatever size you pick, it chooses
the widest column that fits beside the reader's toolbar. On this panel's
1872px article window:

| Reader text size | Font | Column |
|---|---|---|
| Medium | 32px | 50em — 1600px |
| Large (default) | 40px | 40em — 1600px |
| Very large | 56px | 30em — 1680px |

The mapping from Firefox's settings to pixels was read out of Firefox 153's own
`AboutReader.sys.mjs`, not guessed: steps 1–9 are `10 + 2n` px, and 10–15 jump
through 32, 40, 56, 72, 96 and 128. If a future Firefox changes that, the
column will be the wrong width until `KioskBrowser.readerFontPx` is updated to
match.

The size, width and colours are rewritten into the viewer's profile on every
launch, so changing them on the panel with the reader's own **Aa** lasts until
the article is closed. The widget's settings are the ones that stick: **Open
articles in reader view**, **Reader text size** and **Reader colours**.

**Video and live pages open normally.** Reader view has nothing to extract from
them, and what it shows instead is "Failed to load article from page" — with no
link back to the original. So links whose path says `/videos/`, `/live/`,
`/av/`, `/watch` and the like, and anything on YouTube, skip it. The check is
the address alone, deliberately: fetching every page first to ask would add a
second or so to every tap. It will occasionally be wrong in the other
direction — an article with nothing Firefox can extract — and then the reader's
own **×**, top left, goes to the original page.

Chromium, the fallback browser, has no reader view that can be opened by
address, so with Chromium articles always open as the site serves them.

### Keeping adverts out of the news

Some feeds are more shopping than news. On the day this was added, 25 of
WIRED's 50 items were coupon posts — "Peacock Promo Codes: 40% Off", "Motley
Fool Promo Code: $200 Off" — and four of the seven headlines on the tile were
selling something. The news widget now drops them, on any one of three signals:

- **the headline** — promo codes, coupons, vouchers, discount codes, "40% off",
  "$20 off", sponsored, paid post, partner content, a leading `[Ad]`, and named
  sales ("Black Friday deals");
- **the address** — `/story/peacock-promo-code/`, `/sponsored/`, `/deals/`;
- **the publisher's own category** — WIRED files its coupon posts under
  "Gear / Deals"; "Sponsored" and "Coupons" are caught the same way.

Filtered before the feeds are blended and counted, so a tile of seven stays a
tile of seven real headlines rather than three and some gaps.

What it deliberately leaves alone:

- **"deal" on its own** — a trade deal, a pay deal and a transfer deal are news;
- **a price on its own** — "Apple's $250 Million Siri Settlement" is a story,
  "$250 off" is not;
- **reviews and buying guides** — "The Best Linux Laptops (2026)" is editorial
  even when it earns commission. If those are not wanted either, they are a
  category away (`Buying Guides`), but that is a different decision.

Checked against the live feeds before it shipped: all 25 WIRED coupon posts
hidden, and nothing from the BBC or The Verge. **Hide promo codes, coupons and
sponsored posts** in the widget's settings turns it off.

### The full forecast

Tap the weather widget for the whole picture, over the dashboard:

- **Now** — the reading, with feels-like, humidity, wind, chance of rain, the
  UV index in the Met Office's words, and sunrise and sunset.
- **The next 24 hours** — the sky and a temperature curve an hour at a time,
  with the chance of rain wherever it is worth an umbrella (20% or more).
  "Now" shows the same reading as the headline rather than Open-Meteo's
  forecast for the top of the hour, which by twenty past can be a couple of
  degrees out and reads as a mistake beside the big number.
- **The week** — each day's low-to-high as a bar on one shared scale, so a
  warm day sits visibly to the right of a cold one, with a dot on today's for
  the current temperature.

Close it with the **×**, a tap outside it, or a swipe down; it closes itself
after two minutes so the dashboard is not left behind it. **Tap for the full
forecast** in the widget's settings turns it off.

The hourly data is one extra field on the request the widget already makes —
`forecast_hours=25`, so "the next day" still reaches the same hour tomorrow.

### Switching TV inputs

The remote has an **Input** button beside what the television is showing. It
opens every input the set reports, each with what is plugged into it:

- a **green** dot — something connected and on, named where the television
  knows it (over HDMI-CEC);
- **amber** — a device the television remembers but cannot see, usually
  something switched off at the wall;
- **grey** — nothing connected.

The one showing now is highlighted. Pick one and the television switches and
the pop-up closes; left alone, it closes itself after 45 seconds.

It uses the list the television sent when the remote connected, and does
**not** ask again just because the pop-up opened. Asking makes the set run its
pairing check, which flashes a code over whatever is being watched. If there
is no list yet, the pop-up offers to ask once, and says up front that a code
may flash.

The **Show a row of inputs** setting still exists for a tile with room to
spare; the button works on any size of tile.

### The VIDAA client certificate

It needs a client certificate and matching private key at
`assets/certs/vidaa_client.pem` and `assets/certs/vidaa_client.key`. The
television will only accept **the manufacturer's own** client certificate, so
this is not a credential you can generate or rotate — it is the same key on
every VIDAA set, extracted from Hisense's own app.

**The key is not in this repository.** `assets/certs/*.key` is git-ignored:
even a key that isn't secret in any real sense shouldn't be published from
here, and keeping it out means the repo doesn't have to be rewritten again if
that judgement changes. Put your own copy at that path before building.
Without it the widget reports "TV client certificate not set up" rather than
failing later with a TLS handshake error that names the wrong thing.

> Because it can't be rotated, treat it as what it is: a shared manufacturer
> key that grants control of a television on your own network, and nothing
> more. It is not a secret of yours, and losing it costs you nothing that
> keeping it would have protected.

---

## Sharing and encryption

There's no relay: the kiosk runs its own small HTTP listener. Getting that
listener reachable from wherever the app is — same Wi-Fi, or the whole internet
— is your own networking concern: a port forward, a reverse proxy, whatever you
already run. The kiosk only needs to know which local port to bind.

### End-to-end encryption

Shares reaching the kiosk from outside pass through whatever proxy you put in
front of it, which terminates TLS and can therefore read every message. TLS
protects the wire and nothing else, so the payload is sealed as well.

The panel holds a long-lived X25519 identity key and publishes the public half
at `GET /pubkey`. To send, the phone generates a **fresh key pair for that one
message**, does X25519 against the panel's key, and derives a one-message key
with HKDF-SHA256. The body is ChaCha20-Poly1305 in 64 KiB chunks, each binding
its index and a final-flag into the AAD, so chunks can't be reordered, dropped,
repeated, or the message truncated.

A new key per message is a stronger reading of "rotate often" than any schedule:
there's no long-lived message key to capture, and taking the panel's identity key
later decrypts nothing sent before it. The identity key rotates weekly on top of
that, keeping the previous one for a further period so a phone that cached the
old key mid-rotation isn't rejected.

**What it deliberately does not do.** It doesn't prove *who* sent a message —
anyone with the public key can seal one, and authorship still rests on the bearer
token. Nor does it protect content from anyone with a shell on the Pi, since the
identity key is a file there. The threat addressed is the path in between, not
the endpoints.

Set `requireEncryption` in `config.json` to reject anything unsealed with a 412,
once every phone is on a version that encrypts.

### Reading notes aloud

Text only. A photo has nothing to read, and a link spoken aloud is a stream of
letters nobody can follow — the chime already says something arrived and the
screen says what it was. A URL inside a note becomes "a link", and anything
past 600 characters is cut short with "and there is more on screen" rather
than trapping you in a recital.

Speech has its own volume, defaulting to **45%** — deliberately below the
chime and the music. A voice at the same level as music is startling in a
quiet room: it arrives unannounced rather than being something you chose to
play. Do Not Disturb silences it along with the chime.

It uses [piper](https://github.com/rhasspy/piper), a neural text-to-speech
engine that runs locally — measured on this Pi 5 at a real-time factor of
about 0.16, so a sentence is synthesised in roughly a sixth of the time it
takes to say. Local rather than a cloud voice for the same reason as
everything else here: a note somebody shares to this panel is private, and
reading it out should not mean sending it anywhere.

Text is handed to piper on its standard input, never as a command-line
argument, so nothing in a note can become part of a command.

---

## The camera

The picture comes over **RTSP (H.264)**, not MJPEG, which costs an absurd
180 Mbit/s by comparison. RTSP also carries the sensor's rotation, so the image
arrives the right way up whichever way the phone is lying — this is why the
earlier android-ip-camera approach could not be made to work.

Worth knowing if you change this code:

- The Pi 5 has **no hardware H.264 decoder**, so this is software decode.
  `hwdec=no` is set explicitly, because
  `VideoControllerConfiguration(enableHardwareAcceleration: false)` does not
  reach libmpv.
- **libmpv tolerates exactly one `Player`.** A second never opens, and
  dispose-then-recreate hangs. Full screen borrows the overlay's player rather
  than making its own.
- `VideoController.platform.future` must be awaited before `player.open()`.
- Retry only on a real player error or completion event. Judging liveness by
  `player.stream.width` looks reasonable and is wrong — the width never arrives
  for a stream that is working fine, so the retry loop tears down a good stream.

---

## The screen

### Touch wakes it

**Touch wakes it, which is why "off" dims rather than powers down.** Cutting the
DSI output also cuts power to the touch controller, so the panel stops reporting
touches and nothing in software can wake it. Measured on this display: 13 touch
events with the output on, none at all with it off.

So `/screen/off` sets the backlight to zero and leaves the output powered, and
`screen_control.py` watches the touchscreen to turn it back up.
`/screen/off?deep=1` still powers the output right down, for when the saving
matters more than waking it by hand.

Devices to watch come from `/proc/bus/input/devices` — anything with a `mouse`
handler. Keyboard-style devices are deliberately excluded: the paired phone's
AVRCP media keys appear as one, and a track change shouldn't wake the screen.
Reading the touchscreen needs membership of the `input` group.

Power changes and wakes are recorded in
`~/.cache/immich_kiosk_pi/screen_control.log`, which is the quickest way to tell
whether a touch was seen at all.

### Touching it awake

"Off" is the backlight at zero, not the panel powered down — cut the DSI output
and the touch controller loses power with it, and nothing but Alexa can bring
the screen back. So the panel keeps reporting touches while it is dark, which
used to mean the touch that woke it also landed on whatever was underneath: the
TV remote's power button, a headline, a link.

Now `screen_control.py` takes the touchscreen for itself while the screen is
off (Linux's `EVIOCGRAB`), so touches reach it and nothing else. The first one
wakes the screen, and the device is held until that finger lifts, so the whole
touch is swallowed. The next touch is an ordinary one. It is done below the
compositor, so it covers every window — the kiosk, the TV remote app and any
browser open on top.

Two things it is careful about:

- **It never grabs mid-touch.** A grab taken while a finger is down would hide
  the lift from the compositor, leaving the app holding a touch that never
  ends. It waits for the panel to be still first.
- **It does not hold on for ever** if a lift is never reported: three seconds
  with no input at all and the device is given back.

The logic is tested on its own, without a panel:

```bash
python3 -m unittest deploy/test_screen_control.py
```

### Indoor sensor, and Bluetooth

**The kiosk doesn't scan for it.** Home Assistant already watches the same sensor
full-time via `govee_ble`, so the kiosk reads the value from its REST API
instead. Two things scanning the same air gained nothing, and BLE scanning on the
Pi's built-in radio makes Bluetooth audio stutter, because that radio shares one
antenna with A2DP.

The 24-hour chart comes from Home Assistant's history API, thinned to roughly one
point per ten minutes so the chart doesn't try to draw thousands of segments.

**If you want Bluetooth audio and BLE sensing at once, use two radios.** A USB
BLE dongle removes the contention entirely: leave the built-in `hci0` for audio
and give Home Assistant the dongle. Disable the Bluetooth config entry for the
built-in adapter, or it will scan on both. BlueZ only powers extra controllers at
boot when `AutoEnable=true` is set in `/etc/bluetooth/main.conf`.

### Burn-in

The weather and now-playing panels are the only things that stay put on an
always-on display, so they drift continuously within a 24px radius, tracing a
slow Lissajous path (17- and 23-minute periods on the two axes, recomputed every
20 seconds — about two pixels a step, below the threshold of notice).

The panels' margin is deliberately larger than the drift amplitude: a panel
clamped against a screen edge would sit still there, which is the problem this is
meant to solve. See `lib/widgets/burn_in_drift.dart`.

---

## One look throughout

Every screen shares one set of parts, in `lib/widgets/glass.dart`, so they
cannot drift apart:

- **`ScreenHeader`** — the top bar: a round glass back button, a large title
  and the line under it, and the screen's controls gathered into one frosted
  pill on the right (or a single white pill button, such as Slideshow).
- **`ModernScaffold`** — the near-black background with a soft glow of the
  accent from the top left, and the safe area.
- **`GlassSection`** — a titled group of rows on a glass card, as in Settings.

The home screen, albums, Settings, the Locked Folder, PIN entry, About and
first-run setup all use them.

**The dashboard** matches through its **Glass** theme — the same background,
glow and accent (the accent is taken from the app's own colour scheme, and a
test fails if the two ever differ) — and the same top bar, drawn in whichever
theme is chosen so it still reads under a light one such as Paper. The top bar
has a switch in the editor; off, the widgets get the whole panel and a floating
glass back button returns. A theme can carry a `glow` colour of its own in its
JSON to get the same effect.

### The control bar, from the TV remote too

The pill at the top right of the photos and the dashboard — Photos, Dashboard,
TV remote, then Locked Folder, camera, the notifications switch, Refresh and
Settings — is one widget, `ModuleBar`, with the screen you are on lit.

The TV remote app carries the same bar. It is a separate program, so its
buttons cannot reach into the kiosk directly; the kiosk listens for them on a
small control endpoint instead, **on the loopback address only**:

| Request | Does |
|---|---|
| `GET /state` | which buttons would work: dashboard on, Locked Folder available, camera set up, notifications muted |
| `POST /open/photos`, `/open/dashboard`, `/open/settings`, `/open/locked-folder` | opens that place, as the kiosk's own button would |
| `POST /camera` | shows or hides the camera |
| `POST /dnd?muted=true` | sets the notifications switch |

on `127.0.0.1:8766`, one up from `screen_control.py`'s 8765. Nothing on the
network can reach it — a request to the Pi's own LAN address is refused — and
it only opens what the kiosk's buttons open; the Locked Folder still asks for
its PIN. The remote asks for `/state` every few seconds and shows only what
the kiosk says would work; while the kiosk is not running it shows only its
own buttons. After a command it brings the kiosk's window forward.

---

## Talking to other things

### Immich

Immich v3 REST API, authenticated with the `x-api-key` header:

| Purpose | Endpoint |
|---|---|
| Album list | `GET /api/albums` |
| Album contents | `POST /api/search/metadata` with `albumIds` |
| Thumbnail / preview | `GET /api/assets/{id}/thumbnail?size=thumbnail\|preview` |
| Full image | `GET /api/assets/{id}/original` |
| Video stream | `GET /api/assets/{id}/video/playback` |
| Random photos | `POST /api/search/random` |
| On this day | `GET /api/memories?for=YYYY-MM-DD` — a date only; a full timestamp is refused |
| Library in numbers | `GET /api/server/statistics` |
| Server version | `GET /api/server/version` |
| People and birthdays | `GET /api/people`, `GET /api/people/{id}/thumbnail` |

The Locked Folder additionally uses `POST /api/auth/login`,
`POST /api/auth/session/unlock`, then `POST /api/search/metadata` with
`visibility: locked`, and `POST /api/auth/session/lock` on exit — these need a
session token rather than an API key.

### Everything else

| Service | Used by | Notes |
|---|---|---|
| [Open-Meteo](https://open-meteo.com) | Weather, Air & pollen, Rain soon | No key. Rain soon uses the 15-minute forecast. |
| [Carbon Intensity API](https://carbonintensity.org.uk) | Grid carbon | National Grid ESO. The region comes from the postcode's outward code — only that half is sent. |
| [Realtime Trains](https://api-portal.rtt.io) | Train departures | The current API at `data.rtt.io`. A token may be a long-life access token or a refresh token, swapped for an access token as needed. |
| [Govee](https://developer.govee.com) | Lights | On the LAN: discovery by multicast to 239.255.255.250:4001, replies on 4002, commands to 4003. Otherwise the cloud API with a key. |
| [Wikimedia](https://api.wikimedia.org) | In history | Wikipedia's "on this day" feed. |
| [gov.uk](https://www.gov.uk/bank-holidays.json) | Countdowns | Bank holidays for each UK nation. |
| [GitHub](https://docs.github.com/rest/releases) | Updates | Immich's latest release, compared with your server's version. |
| [Glances](https://github.com/nicolargo/glances) | Servers | The v4 web API (`/api/4/…`), with v3 as a fallback; the `smart` plugin for disk health. |
| UniFi Network | the Network widgets | The console's integration API with an `X-API-KEY`. |
| Home Assistant | Home Assistant, Updates, the indoor sensor | REST API with a long-lived token. |
| iTunes Search API | Bluetooth artwork | By artist and track, which matches far more reliably than album. |

**Disk health** is derived from Glances' SMART attributes: *failing* if any
normalised value is at or below its threshold or the drive reports a failure;
*warning* for reallocated, pending or uncorrectable sectors. Glances sends the
values as padded strings (`"074"`), so they are parsed rather than trusted as
numbers.

**Certificates** are read with a TLS handshake and nothing more; an untrusted
certificate is read and reported as untrusted, never used.

---

## Development

Built on the Pi (it's an arm64 Linux target), but the source can live elsewhere
and sync over:

```bash
scripts/sync.sh        # copy source to the Pi
scripts/run.sh         # sync, build release, restart the kiosk
scripts/run.sh debug   # sync, then flutter run with hot reload
scripts/shot.sh        # screenshot the Pi's display to a PNG
```

Everything is configured through `scripts/local.env`, or by overriding `PI_HOST`
/ `PI_DIR` as environment variables.

The window is fullscreen and borderless by default. Set
`IMMICH_KIOSK_WINDOWED=1` to run it in a normal window while debugging.

**Tests.** `flutter test` runs the lot, including the size sweeps; the screen
service's own tests are `python3 -m unittest deploy/test_screen_control.py`.

### Debug launch hooks

Environment variables that boot straight into one screen — handy for capturing
screenshots or testing a screen in isolation. Inert unless set.

| Variable | Opens |
|---|---|
| `IMMICH_KIOSK_TEST_ALBUMGRID=<albumId>` | an album's asset grid (`IMMICH_KIOSK_TEST_ALBUMNAME` sets its title) |
| `IMMICH_KIOSK_TEST_GALLERY=<albumId>` | the photo viewer (`IMMICH_KIOSK_TEST_GALLERY_INDEX` picks the photo) |
| `IMMICH_KIOSK_TEST_SLIDESHOW=<albumId>` | the slideshow |
| `IMMICH_KIOSK_TEST_VIDEO=<assetId>` | the video player |
| `IMMICH_KIOSK_TEST_LOCKED=<pin>` | the Locked Folder, unlocked |
| `IMMICH_KIOSK_TEST_LOCKED_VIDEO=<pin>` | the first locked video |
| `IMMICH_KIOSK_TEST_ABOUT=1` | the About screen |
| `IMMICH_KIOSK_TEST_SETTINGS=1` | the Settings screen |
| `IMMICH_KIOSK_TEST_NOWPLAYING=1` | the now-playing panel on a blank background |
| `IMMICH_KIOSK_TEST_DASHBOARD=<page>` | the dashboard, opened at that page |
| `IMMICH_KIOSK_TEST_POPUP=forecast` or `inputs` | with the above, opens the full forecast or the TV inputs over the dashboard |
| `IMMICH_KIOSK_TEST_PLAYER=small` or `full` | the home screen with the player shrunk to the mini player, or the full player opened as soon as music is playing |
| `IMMICH_KIOSK_TEST_WEATHER=expanded` | with the slideshow, the weather panel opened |

They are read at start-up, so with the service running they are set with
`systemctl --user set-environment`, followed by a restart — and cleared
afterwards with `unset-environment`.

### Project layout

```
lib/
  main.dart                    # app entry, providers, root routing
  theme.dart                   # dark, touch-first theme; the emoji fallback
  config/app_config.dart       # settings model
  models/immich_models.dart    # Album, Asset
  dashboard/
    widget_registry.dart       # DashboardWidgetType, options, groups
    dashboard_model.dart       # the saved dashboard: widgets, pages, look
    schedule.dart              # hours for pages and widgets
    tile_renderer.dart         # draws a widget off-screen for the editor
    photo_backdrop.dart        # photos behind the dashboard
    widgets/                   # one file per widget, plus fit helpers
  services/
    config_service.dart        # reads/writes config.json
    immich_service.dart        # Immich REST client + response caching
    dashboard_service.dart     # the editor's web server
    now_playing_service.dart   # BlueZ AVRCP over D-Bus + artwork lookup
    spotify_service.dart       # Web API control, OAuth PKCE
    share_inbox_service.dart   # the HTTP listener for shares
    sealed_share.dart          # X25519 + ChaCha20-Poly1305, key rotation
    tv_service.dart            # Hisense VIDAA over MQTT
    …                          # and one service per outside source:
                               # weather, trains, carbon, Govee, UniFi,
                               # Glances, Home Assistant, notes, chores…
  screens/                     # home, album, gallery, video, slideshow,
                               # dashboard, settings, about, viewers
  widgets/                     # the glass parts, overlays, module bar
assets/dashboard/              # editor.html, notes.html, list.html
deploy/                        # systemd units, labwc config, screen control
companion_app/                 # the Android share app
test/                          # widget, logic and size-sweep tests
```

---

## Third-party libraries

The same list is on the device under **Settings → System → About**, so attribution travels
with the app rather than living only here.

Built with [Flutter](https://flutter.dev) (BSD-3-Clause,
[source](https://github.com/flutter/flutter)).

### Dart packages

| Package | Used for | Licence |
|---|---|---|
| [provider](https://pub.dev/packages/provider) · [src](https://github.com/rrousselGit/provider) | State management / dependency injection | MIT |
| [dio](https://pub.dev/packages/dio) · [src](https://github.com/cfug/dio) | HTTP client for the Immich and weather APIs | MIT |
| [cached_network_image](https://pub.dev/packages/cached_network_image) · [src](https://github.com/Baseflow/flutter_cached_network_image) | Images with auth headers and caching | MIT |
| [flutter_cache_manager](https://pub.dev/packages/flutter_cache_manager) · [src](https://github.com/Baseflow/flutter_cache_manager) | On-disk cache, relocated to the NVMe | MIT |
| [file](https://pub.dev/packages/file) · [src](https://github.com/google/file.dart) | Filesystem abstraction for the custom cache | MIT |
| [media_kit](https://pub.dev/packages/media_kit) · [src](https://github.com/media-kit/media-kit) | Video playback and speed control | MIT |
| [media_kit_video](https://pub.dev/packages/media_kit_video) | Video render surface | MIT |
| [media_kit_libs_video](https://pub.dev/packages/media_kit_libs_video) | Native video dependencies | MIT |
| [dbus](https://pub.dev/packages/dbus) · [src](https://github.com/canonical/dbus.dart) | Talks to BlueZ for phone media metadata | MPL-2.0 |
| [cryptography](https://pub.dev/packages/cryptography) | X25519, HKDF and ChaCha20-Poly1305 for encrypted shares | Apache-2.0 |
| [crypto](https://pub.dev/packages/crypto) · [src](https://github.com/dart-lang/tools) | SHA-256 for the Spotify OAuth PKCE code challenge and key ids | BSD-3-Clause |
| [path](https://pub.dev/packages/path) · [src](https://github.com/dart-lang/path) | Path joining for cache locations | BSD-3-Clause |
| [flutter_lints](https://pub.dev/packages/flutter_lints) (dev) | Lint rules | BSD-3-Clause |

### System libraries

| Library | Used for | Licence |
|---|---|---|
| [mpv / libmpv](https://mpv.io) · [source](https://github.com/mpv-player/mpv) | Video decoding behind media_kit | LGPL-2.1+ ([details](https://github.com/mpv-player/mpv/blob/master/Copyright)) |
| [BlueZ](http://www.bluez.org) · [source](https://github.com/bluez/bluez) | Bluetooth stack — AVRCP metadata and control | GPL-2.0+ / LGPL-2.1+ |
| [librespot](https://github.com/librespot-org/librespot) | Spotify Connect device ("Kiosk") | MIT |
| [Firefox](https://www.mozilla.org/firefox/) | Shared links and articles, and the Spotify login | MPL-2.0 |
| [labwc](https://labwc.github.io) | The Wayland compositor the kiosk runs under | GPL-2.0 |
| [wlrctl](https://git.sr.ht/~brocellous/wlrctl) | Focusing windows for the TV Remote button | MIT |
| [GTK 3](https://www.gtk.org) | Flutter's Linux embedder window | LGPL-2.1+ |

### Fonts

The dashboard's twenty fonts are all under the
[SIL Open Font Licence 1.1](https://scripts.sil.org/OFL), listed with their
designers on the About screen.

### Services

| Service | Used for | Terms |
|---|---|---|
| [Immich](https://immich.app) · [src](https://github.com/immich-app/immich) | Your own photo server (the whole point) | AGPL-3.0 |
| [Open-Meteo](https://open-meteo.com) | Weather forecast — no API key required | Free for non-commercial use, [CC BY 4.0](https://open-meteo.com/en/license) |
| [iTunes Search API](https://performance-partners.apple.com/search-api) | Album artwork lookup | Free, no key · Apple terms |
| [Spotify Web API](https://developer.spotify.com/documentation/web-api) | Playback control, liked songs and playlists | Requires your own free Developer app + Premium |
| [postcodes.io](https://postcodes.io) · [src](https://github.com/ideal-postcodes/postcodes.io) | UK postcode → coordinates | MIT, data under [OGL](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/) |
| [IP Webcam](https://play.google.com/store/apps/details?id=com.pas.webcam) | The phone-as-camera stream and its control API | Free / paid app, third-party |
| [Carbon Intensity API](https://carbonintensity.org.uk) | Grid carbon | Free, CC BY 4.0 |
| [Realtime Trains](https://www.realtimetrains.co.uk) | Train departures | Free token; RTT's terms |
| [Wikimedia](https://api.wikimedia.org) | On this day in history | CC BY-SA |
| [Glances](https://github.com/nicolargo/glances) | Servers | LGPL-3.0, runs on your own machines |
| [piper](https://github.com/rhasspy/piper) | Reading aloud | MIT, runs on the Pi |

---

## Credits and sources

Almost all of the code here was written for this project, but these parts come
from, or are adapted from, elsewhere:

- **Flutter project scaffolding** — `linux/runner/*`, `.metadata`,
  `analysis_options.yaml` and the initial `main.dart` were generated by
  `flutter create` and then modified (notably `my_application.cc`, changed to
  start fullscreen and borderless). Flutter SDK, BSD-3-Clause.
- **`_NvmeFileSystem`** in `lib/services/media_cache.dart` is modelled on
  [`IOFileSystem`](https://github.com/Baseflow/flutter_cache_manager/blob/develop/lib/src/storage/file_system/file_system_io.dart)
  from flutter_cache_manager (MIT), changed to store files under a fixed
  directory instead of the system temp directory.
- **Weather code descriptions and icon mapping** in
  `lib/services/weather_service.dart` and `lib/widgets/weather_overlay.dart`
  follow the WMO weather-code table as published in the
  [Open-Meteo API docs](https://open-meteo.com/en/docs).
- **Immich API usage** was derived from the
  [Immich API documentation](https://immich.app/docs/api) together with probing a
  live v3 server — in particular that album contents come from
  `POST /api/search/metadata`, and that the Locked Folder needs a session token
  rather than an API key.
- **Bluetooth now-playing** uses BlueZ's AVRCP support over D-Bus
  ([`org.bluez.MediaPlayer1`](https://github.com/bluez/bluez/blob/master/doc/org.bluez.MediaPlayer.rst))
  for metadata and transport control. Album art is not part of AVRCP, so it is
  resolved separately from the iTunes Search API by artist + track title.
- **The sealed-share format** follows the standard sealed-box construction
  (ephemeral X25519 → HKDF → AEAD) as described in the
  [libsodium documentation](https://doc.libsodium.org/public-key_cryptography/sealed_boxes),
  implemented here over the `cryptography` package rather than copied.
- **Material Design icons** ship with Flutter (Apache-2.0).

No code was copied from Stack Overflow, blog posts or other projects.

---

## Licence

[MIT](LICENSE) — do what you like with it, no warranty.
