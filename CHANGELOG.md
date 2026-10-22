# Changelog

## 1.0.3

Voice control: say "hey canvas", or a wake word of your own, and the panel
does what you ask. Anything it doesn't know goes to Home Assistant. It's all
heard and understood on the Pi. There's a new installer too, full screen in
the terminal. It asks everything first, including which widgets, theme and
extras you want, then teaches the panel your wake word. Two new widgets
bring it to 71.

### Updating

- **Update** by running the installer again. On an installed panel it now
  opens full screen and offers **Update to the latest version**:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/vwillcox/HomeCanvas/main/install.sh | bash
  ```

- **For voice control**, run `bash ~/homecanvas/install.sh --voice`
  afterwards. It sets up the speech engine (about 300 MB), lets you choose a
  wake word and teaches it how you say it. You need a microphone. See
  [VOICE.md](VOICE.md).
- **The old question-by-question installer** is still there:
  `bash install.sh --classic`.

### New

**Voice control**
- Say "hey canvas", then "show the stocks", "next page", "page three",
  "open the remote", "forecast", "photos" or "back". A widget is found by
  its name, part of its name or another word for it, and a page you ask for
  stays put until you say "resume".
- The music too: "play", "pause", "skip", "previous song", "volume up",
  "mute". This works with Spotify, or a phone's music over Bluetooth.
- "Open the remote" brings up the dashboard's TV remote at twice its size,
  with the inputs.
- Anything the panel doesn't know, and every question or switching
  ("turn off the lamp", "what's the temperature indoors"), goes to Home
  Assistant's Assist. Its answer is shown and spoken, unless Do Not Disturb
  is on.
- Heard and understood on the Pi, by sherpa-onnx with two Moonshine
  recognisers. Nothing is sent anywhere, and with it switched off the
  microphone is closed. Switch it on in **Settings → Screen → Voice
  control**.
- A strip at the top of the screen shows what it heard and what it did.
- `POST /voice?say=…` on the local control port tries a phrase without
  speaking.

**A wake word of your own**
- Choose "computer", "hey jarvis", "okay house", "hey panel", or type your
  own. It's checked as you type: commands, common words and very short names
  are caught.
- The installer then listens to you say it five times and learns how the
  recognisers hear you. An unusual name that came out as "hazor blacks" or
  "hey sore blacks" went from 0 of 6 to 6 of 6. Two everyday sentences
  check that it doesn't wake by itself, and then you try it for real.
- It's kept in the config as `screen.wakeWord`, and the panel starts
  listening for it as soon as it changes.

**The installer, full screen**
- Plain `curses` in the terminal, on the Pi or over SSH, styled like the
  LCARS theme. It asks for your Immich address and key (checked), a name,
  the dashboard, a theme, voice control and its wake word, and the extras
  your widgets need. Then it shows the list, and only then changes anything.
- **The dashboard:** start from a preset (*A good start*, *The family's
  board*, *Smart home*, *Music, TV and video*, *Home lab*) and tick or untick
  any widget. They're laid out a page per group, with a page added to an
  existing dashboard or replacing it, as you choose.
- **A theme**, with a preview of its colours as you move through the list,
  and whether the panel starts on the dashboard or the albums.
- **Extras:** your location for the weather, piper so the panel can speak,
  yt-dlp for the video player, librespot for Spotify on the panel's own
  speakers, and Home Assistant or Homey, with their keys checked as they're
  typed. Each is a script of its own in `scripts/`.
- On an installed panel it offers to update, to change widgets, theme and
  extras, or to go straight to voice control.
- It asks for your password only when something has to be installed
  system-wide.

**Two new widgets**
- **Home Assistant bridge:** the house as a starship's console, on a page of
  its own. Home Assistant's rooms are down an LCARS rail; for the chosen
  room, its lights and switches are blocks to tap and its temperatures are
  readouts.
- **Electricity:** today's use and cost from the smart meter, through Home
  Assistant, against yesterday's, hour by hour. With a Bright login it also
  shows a week, a month and a year, each against the one before.

**Smaller additions**
- The panel has its own on-screen keyboard for every text field. The Pi's
  own keyboard is drawn under the full-screen kiosk, where nobody could see
  it.
- [VOICE.md](VOICE.md): everything you can say, and how to set it up.
- [THEMES.md](THEMES.md) shows LCARS on the real panel at last, with a
  gallery; the README has the installer screen by screen.

### Bug fixes

- **TV remote:** the access token is renewed before it runs out, and a
  dropped connection reconnects. It used to sit at "connecting" for days
  once the token had expired, with every key lost.
- **Railcam:** when railcam.uk is down, the tile says so instead of showing
  a grid of blanks, and the cameras come back by themselves.
- **Screen control:** pulling out a mouse's receiver no longer leaves the
  touch watcher using a whole core.
- **Voice:** "what's the weather?" asks Home Assistant instead of turning to
  the weather widget's page.

## 1.0.2

A seventeenth theme, LCARS, which draws the panel as a starship's console,
and seventeen new widgets: 69 in all, up from 52. You can now add widgets of
your own from the editor too.

### Updating

- **Update** by running the installer again, as before:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/vwillcox/HomeCanvas/main/install.sh | bash
  ```

- **Updating by hand?** After `git pull`, run
  `bash scripts/widget-build.sh generate` before the build. It writes the
  file that registers the widgets you have installed, and the installer now
  does it for you.
- **For Homey:** create an API key at my.homey.app, then enter it with the
  Homey's address under **Settings → Home → Homey**, or run
  `bash scripts/set-homey-key.sh` on the Pi.

### New

**LCARS theme**
- Black, with bars of flat orange, lilac and blue swept round the corner of
  every panel, and tall condensed capitals in Antonio, the twenty-first
  bundled font.
- It changes the drawing as well as the colours: each widget sits inside a
  bar and a lettered rail, buttons are solid blocks joined into strips,
  screens are headed by a text bar, and Settings lists its tabs as a rail of
  blocks.
- Sliders, progress bars and the music visualiser are drawn in segments.
- It moves in steps, as a console does: bars come up a length at a time, one
  blinks now and then, and a readout flashes as its figure changes. All of it
  stops while the screen is dark or where animations are switched off.
- A theme of your own can ask for it with `"style": "lcars"` and a
  `"palette"`. See [THEMES.md](THEMES.md).

**Homey**
- Sixteen widgets for a Homey on your network: devices, a room, lights,
  light colour, fans, flows, moods, alerts, climate, energy, history, who's
  home, variables, the timeline, the whole house, and Homey itself.
- The API key is only sent to a Homey on the home network.

**Railcam**
- Lineside cameras from railcam.uk: pick any of its 300 and touch one to
  watch it live, or have them playing in the tile, small and silent. Needs
  your own railcam.uk account.

**Widgets of your own**
- Install a widget from the editor's new widgets page, in one of two forms:
  - **described in JSON:** its name, its settings, the address its data comes
    from and how to show it. It is on the panel at once and can show figures,
    cards and lists;
  - **written in Dart:** as full as any built-in widget. The panel checks it,
    builds it in and restarts, which takes a few minutes, and puts everything
    back if any of that fails. Switch it on first under
    **Settings → Dashboard → Widgets written in Dart**.
- The editor hands out an example of each to change and upload.
- Only install widgets you trust: one in Dart runs on the panel as a program.

**Smaller additions**
- **Weather:** an 8-day forecast, and a forecast that takes two rows where
  that leaves each day larger.
- **Stocks**, **Crypto**, **Weather** and **News** say when they were last
  fetched, as "Updated 09:14".
- **UniFi:** network clients show their addresses, and both client lists
  size their text to fill the tile.
- [INSTALL.md](INSTALL.md) lists the parts this panel is built on, and what
  they cost.

### Bug fixes

- The music visualiser's waveform drew a flat line for quiet music, such as
  a phone over Bluetooth with its own volume low.

## 1.0.1

Videos on the panel, the panel in thirteen languages, and fourteen new
widgets: 52 in all, up from 38.

On a still dashboard the kiosk now uses about 2% of one CPU core, down from
66%, and the whole Pi is 3–4% busy, down from 22%.

### Breaking changes

These may need something doing after you update:

- **The editor only answers on the home network.** Opening it by a public
  domain name, or through a reverse proxy, is now refused. Use the Pi's IP
  address, its name (`homecanvas.local`), or another home-network name
  (`.lan`, `.home.arpa`). This closes a DNS-rebinding hole.
- **Scripts that call the editor's API must send an `Origin` header.**
  Saving the layout, and the sender-token pages, now answer only the editor's
  own pages. From `curl`, add the editor's own address, for example
  `-H "Origin: http://127.0.0.1:8090"`.
- **The local control port (8766) refuses requests from web pages.** `curl`
  and scripts on the Pi are unaffected.
- **`config.json` and the other secrets are readable only by the kiosk's
  user.** That includes the share keys, site cookies and TV tokens. A tool
  running as another user can no longer read them.
- **News tiles lost the "Headlines to show" setting.** They scroll through
  every headline instead.
- **The panel's language defaults to British English.** For American
  spelling and MM/DD/YYYY dates, choose **English (US)** under
  **Settings → System → Language**, or from the language picker in the
  editor.
- **YouTube needs a current yt-dlp, not the distribution's package.** The
  packaged yt-dlp no longer works with YouTube. Install it from
  **Settings → Music → Videos** (see below).

### Updating, and changes to the install instructions

- **Update** by running the installer again, as before:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/vwillcox/HomeCanvas/main/install.sh | bash
  ```

  It now also restarts the screen controller (`screen-control.service`),
  if you set it up, so the panel can rest while the screen is dark.
- **Updating by hand?** After `git pull` and the build, also run
  `systemctl --user restart screen-control`.
- **For videos:** **Settings → Music → Videos → Install yt-dlp**. This
  fetches yt-dlp and deno into `~/.local/share/homecanvas/bin`, needs no
  sudo, and yt-dlp then updates itself daily.
- **New, optional: boot straight into the kiosk.** Run
  `bash scripts/kiosk-session.sh`, then reboot, for a session with only the
  kiosk instead of the full desktop. The desktop's taskbar alone uses about
  370 MB. `bash scripts/kiosk-session.sh remove` goes back.
- **New, optional keys.** Every new widget works without a key. Two can use
  one:
  - a free CoinGecko Demo key for **Crypto**, which is recommended because
    CoinGecko's keyless allowance is small and shared by everyone at your
    address;
  - an ElevenLabs key, to have **News** articles read in an ElevenLabs voice
    rather than piper.
- New sections in [INSTALL.md](INSTALL.md): YouTube, Floatplane, Nebula,
  booting straight into the kiosk, and ElevenLabs for the news reader.

### New

**Videos on the panel: YouTube, Floatplane and Nebula**
- Play links shared from the phone app, tapped in the News widget, or sent to
  the control port (`POST 127.0.0.1:8766/youtube?url=…`).
- Watch full screen, or picture-in-picture over any screen. Drag it, pinch
  it, or pull its corner to resize it.
- **YouTube**, **Floatplane** and **Nebula** widgets show the latest from
  your subscriptions.
- Signing in is optional for YouTube and required for the other two. Sign in
  on the panel, or from a computer at the editor's address plus `/youtube`,
  `/floatplane` or `/nebula`.
- Up to 1080p60 on a Pi 5. Nebula's HEVC uses the Pi's hardware decoder.

**Thirteen languages**
- Every on-screen string can be translated: the panel, Settings and the
  editor's web pages.
- British English is the base, with an American English pack.
- AI-created packs, marked as such in the picker:
  - complete: Spanish, Italian, Dutch, Polish, Swedish and Norwegian
    (Bokmål);
  - partial: French, German, Portuguese and Irish, which fall back to English
    where a string isn't translated yet.
- Dates follow the language: 28/09/2026 in British English, 09/28/2026 in
  American English, 28.9.2026 in German.

**New widgets**
- **Stocks** and **Crypto:**
  - a list, cards, or one card filling the tile, with daily to yearly charts;
  - what you paid shown as a line on the chart, with holdings, gain or loss,
    and time held;
  - Crypto falls back to Coinbase's public prices when CoinGecko refuses.
- **GitHub:** stars, issues, pull requests, releases and a weekly commit
  chart for your repositories, with a tab each, and with a token, who has
  been visiting.
- **Reminders:** send "Remind me to put the bins out at 7pm" from the phone
  app. When a reminder is due, the panel says it aloud and shows its page.
- **Getting out:**
  - **London lines** and **London arrivals**, from TfL;
  - **Fuel prices**: the cheapest petrol or diesel near home, from the UK's
    open fuel-price scheme;
  - **Departures**: trains, trams, subways and buses across Europe and
    North America, live where the operator shares it, from Transitous;
  - **Planes overhead**: flights around home, with where each is from and
    going to, and which way to look;
  - **Traffic cameras**: TfL's 900 JamCams, or any camera image address;
  - **Tides**: high and low times, and the sea's height through the day.
- **YouTube**, **Floatplane** and **Nebula**, above.

**News**
- Tiles scroll, and pulling down from the top refreshes them.
- Each headline shows its site's icon.
- An optional layout with a tab for each feed.
- The article reader can use ElevenLabs. Piper stays the default, and reads
  whenever ElevenLabs can't.

**The editor**
- Rows in any list setting (stocks, coins, feeds, cameras…) can be dragged
  into a new order, or moved with the arrow keys.
- Folded panels and rows stay as you left them, in every browser.
- Links to the panel's other pages (notes, list, senders…), and a way back
  from each.
- UniFi widgets have a group of their own.
- Dates are entered in the panel's language's order.

**Smaller additions**
- A Locked Folder left alone for 10 minutes locks itself.
- Shared photos and videos are deleted once they've been seen.
- `POST 127.0.0.1:8766/screen?lit=true|false` tells the kiosk when the
  screen goes dark or lights up.

### Security fixes

- Any web page on the home network could read or create share tokens. Now
  only the editor's senders page can.
- Any web page could overwrite the dashboard layout. Now only the editor can.
- Sites that point their own domain name at the panel (DNS rebinding) are
  refused.
- Links are opened only if they're `http` or `https`. A `file://` link in a
  feed could have shown the config on screen.
- The control port refuses commands from web pages.
- Secrets on disk are readable by the kiosk's user only, and are saved in
  one piece. A power cut mid-save could leave an empty config.
- Share tokens are compared in constant time.
- Size limits on editor requests, feeds, calendars and article pages.

### Bug fixes

- The correct Locked Folder PIN was refused after Immich's session expired.
- The TV showed its pairing code on every restart.
- Days the clocks change: fixes to bins, meals, scheduled tiles and chores.
- Every shared photo and video was kept on disk forever.
- A few video-site errors: a crash on a video with no formats, and uploaded
  cookies being discarded when the site couldn't be reached.

### Power and speed

- While the screen is dark, animations stop and tiles that poll skip their
  checks. They catch up the moment it lights again.
- A still dashboard no longer redraws itself 60 times a second.
- Less background work: Spotify progress, the servers tile and the TV-remote
  button are all checked less often.
- Feeds, calendars and articles are parsed off the UI thread, so video
  doesn't stutter.

### Known issues

- The screen stays at full brightness whenever the dashboard is up. Night
  hours are planned.
- The UniFi console's certificate isn't checked yet.
- The French, German, Portuguese and Irish translations are partial, and
  Danish and Welsh aren't started.
- New York subway times from Transitous are timetabled, not live.
- Tide heights are modelled, not measured: fine for the beach, not for
  navigation.

## 1.0.0

The first release. See the
[release notes](https://github.com/vwillcox/HomeCanvas/releases/tag/v1.0.0).
