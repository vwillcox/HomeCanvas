# What changed on `youtube-playback`

Everything on this branch that is not on `main`: the commits from `7698404`
onwards. New features first, then the security fixes, the
bugs fixed, the work on power and speed, and what to do after updating.

On the dashboard with its pages held, the kiosk now uses about 2% of one CPU
core, down from 66%, and the whole Pi is 3–4% busy, down from 22%.

---

## New

### Videos on the panel: YouTube, Floatplane and Nebula

- **Sent from anywhere.** A link shared from the phone app, tapped in the
  News widget, or sent to the local control API
  (`POST 127.0.0.1:8766/youtube?url=…`) plays on the panel. Links from all
  three sites work.
- **Full screen or picture-in-picture.** The picture-in-picture window floats
  over any other screen. Drag it with one finger, pinch it, or pull its
  corner handle to resize it. It remembers where it was left.
- **Played by the kiosk itself**, with the same mpv the photo videos use.
  yt-dlp (and deno, which YouTube now needs) is downloaded from
  **Settings → Music → Videos** and kept up to date daily. Debian's packaged
  yt-dlp no longer works against YouTube.
- **Video tiles.** A **YouTube** dashboard tile shows the latest from your
  subscriptions, or plays one chosen video in the tile. **Floatplane** and
  **Nebula** tiles show the latest from the creators you follow. Touch any
  video to watch it on the panel.
- **Signing in is optional** and done per site, in either of two ways:
  - on the panel itself, in a kept browser profile;
  - from a computer at the editor's address followed by `/youtube`,
    `/floatplane` or `/nebula`, by uploading a `cookies.txt`.

  Signing in unlocks Premium, members-only and age-restricted YouTube videos,
  and is required for Floatplane and Nebula.
- **Smooth playback on the Pi 5:**
  - YouTube is played as H.264, which is the cheapest to decode in software.
  - Nebula's HEVC uses the Pi's hardware decoder, up to 30 frames a second.
  - Fragmented HLS streams are played through mpv's own fragment list, so
    seeking works instead of freezing the picture.
  - Larger buffers mean a seek takes about 2 seconds rather than 10.
- **Idle and interruptions.** A video left paused for 30 minutes closes by
  itself. Music already playing is paused while a video plays. Whatever is
  covered by a full-screen video stops drawing, and the hidden taskbar and
  TV remote app are paused for its length.

### Booting straight into the kiosk

`scripts/kiosk-session.sh` sets the Pi to log in to a session with only the
kiosk and what it needs, instead of the full Raspberry Pi desktop. The
desktop's taskbar alone uses about 370 MB. To go back to the desktop, run
`bash scripts/kiosk-session.sh remove`. See INSTALL.md, "Booting straight
into the kiosk".

### News tiles

- **Scroll and pull to refresh.** A News tile lists every headline its feeds
  carry and scrolls through them. Pulling down from the top fetches the feeds
  again straight away.
- **Where each headline is from.** A small icon — the site's own, found on
  its home page, or the feed name's first letter — sits beside each headline.
- **Tabs.** **Layout → A tab for each feed** puts one feed per tab along the
  bottom, showing the site's icon, the feed's name, or both.
- **Shorter lists in the editor.** Rows of a list (feeds, entities, chores)
  fold to one line each; **Edit** opens one.

### Smaller additions

- A **Locked Folder** left untouched for 10 minutes locks itself and closes.
- **Shared photos and videos are deleted once seen**, or when their card is
  dismissed. Anything left over is cleared on start.
- `POST 127.0.0.1:8766/screen?lit=true|false` tells the kiosk when the screen
  goes dark or lights up. `screen_control.py` sends it.

---

## Security fixes

- **Sender tokens could be read by any web page.** Any web page open on any
  device on the home network could read every share token from the editor,
  or create a new one. Now only the editor's own senders page is answered.
- **Editor settings could be rewritten by any web page.** The dashboard layout
  could be overwritten from any web page. Saving now works only from the
  editor.
- **DNS rebinding.** A site that points its own domain name at the panel no
  longer gets past the "same site" checks. The editor answers only to IP
  addresses, bare machine names and home-network names (`.local`, `.lan`,
  `.home.arpa` and similar).
- **Links opened in the browser.** Only `http` and `https` addresses are
  opened. A `file://` link from a news feed or a share could have shown the
  config, passwords included, on screen. A "link" starting with `--` was
  passed to the browser as an option.
- **Local control port.** It now refuses commands sent from a web page. A page
  in the kiosk's browser could previously turn the camera on.
- **Secrets on disk.** `config.json`, the share encryption keys, site cookies
  and the TV's login tokens are now readable by the kiosk's user only, from
  before anything is written, and are saved whole. A power cut mid-save used
  to leave a half-written `config.json`, which the next start replaced with
  an empty one. An unreadable config is now kept as `config.json.unreadable`
  instead of being overwritten.
- **Share tokens** are compared in constant time.
- **Size limits** on editor requests (4 MB), news feeds and calendars (10 MB)
  and article pages (5 MB), so nothing can fill the Pi's memory.

---

## Bugs fixed

- **Locked Folder:** once Immich's session had expired, the correct PIN was
  rejected as "Incorrect PIN" until the kiosk restarted.
- **TV:** it no longer shows its pairing code on every restart. The input
  list is kept on disk; **Refresh** and **Pair again** are in Settings.
- **Days the clocks change:**
  - bins showed "today" after noon on the day the clocks go back;
  - meals showed tonight's dinner instead of tomorrow's that evening;
  - scheduled tiles checked the wrong weekday just after midnight on the
    Monday after the clocks go forward;
  - chores dropped their old history an hour out.
- **Video sites:**
  - a video with an empty list of formats crashed on loading;
  - cookies uploaded while the site couldn't be reached were thrown away and
    reported as rejected;
  - a video tile removed mid-start left its player running.
- **Screens:** a few used a closed screen after waiting (the video player's
  seek bar and volume, the Spotify setup dialog).
- **Shared files:** every photo and video ever shared stayed on disk. The Pi
  had 35 MB of them.

---

## Power and speed

### When the screen is off

"Off" is the backlight at zero, and the app never used to find out. Now it
is told straight away, and checks the backlight every 15 seconds besides.
While the screen is dark:

- every animation stops;
- tiles that poll (servers, Home Assistant, trains, lights, services, certs,
  updates, the Immich library, birthdays, carbon, history, Omarchy) skip
  their checks, and catch up the moment the screen lights again;
- the Spotify and Bluetooth progress stop updating. Spotify is still checked
  every 10 seconds, so music starting can still wake the screen.

`screen_control.py` used to wake 20 times a second the whole time the screen
was off. It now wakes about twice a second.

### A still dashboard stays still

- **Page-turn progress dot:** it ran a 60-frames-a-second animation for the
  whole time the dashboard was up, and redrew the blurred glass behind it
  every frame. It now moves in 44 steps per page and looks the same.
- **Held pages dot:** it breathed at 60 frames a second, and held pages are
  saved, so it had been running permanently. It is now a steady, dimmed fill
  beside the play button.
- **Long Spotify titles:** they scroll three times, then rest at the start
  until the track changes. They used to scroll forever, even with the music
  paused.
- **Blurred album art** is no longer re-blurred each time the progress bar
  moves.

### Less work in the background

- **Spotify progress** updates once a second instead of four times.
- **The servers tile** reads this Pi's disks and Docker containers once a
  minute instead of every 10 seconds. Each reading started two programs,
  `df` and `docker`.
- **The TV-remote button** is checked every 10 seconds instead of 4, and only
  while it can be seen. Each check started a process.
- **Parsing off the UI thread.** News feeds, calendars, article pages and
  yt-dlp's replies are processed on another isolate, so video playback
  doesn't stutter while they load.
- **Reused connections.** Immich, weather and article fetches keep their HTTP
  connections instead of opening a new one per request.
- **Thumbnails** in video tiles are decoded at the size they are drawn.
- **Video feeds** retry within seconds after a failed first fetch, rather
  than showing an error for 15 minutes.
- **piper** runs at the lowest CPU priority, so speech and the screen come
  first.

---

## Tidying

- One place for time formats (`lib/time_format.dart`), replacing nine copies
  of the clock format and three of the video position format.
- Mixins for work that should stop while hidden:
  - `ShownTimers`, for timers that skip their ticks;
  - `RebuildEveryMinute`, for tiles whose words are about "now";
  - `SteppedTimeline`, for slow progress shown small.
- Helpers:
  - `findOnPath`, instead of starting `which`;
  - `KioskBrowser.focusKiosk`, to bring the kiosk window back;
  - the editor server's replies, which replaced 36 hand-written copies.
- Analyzer notices cleared, bar four about constructor style.

---

## After updating

1. **Restart the screen controller:** `systemctl --user restart
   screen-control`. The kiosk can only rest while dark once
   `screen_control.py` is the new one.
2. **For videos:** Settings → Music → Videos → **Install yt-dlp**.
3. **Optional:** `bash scripts/kiosk-session.sh`, then reboot, for the lighter
   session.

### Things that look different

- The held-pages dot no longer breathes.
- Long Spotify titles stop scrolling after three laps.
- The Spotify progress bar moves once a second.
- The TV-remote button can take up to 10 seconds to appear after the remote
  starts.
- The video player shows `1:02:09`, not `01:02:09`.
- News tiles no longer have a **Headlines to show** setting; they scroll
  instead.
- The editor refuses to load from an address outside the home network (a
  public domain name, or a reverse proxy in front of it).

### Not yet done

- **Night hours for the screen.** The backlight stays at full brightness
  whenever the dashboard is up, which is likely the biggest power draw left.
- **UniFi certificate check.** Its certificate is accepted without checking,
  so someone on the network could read its API key. The safe fix is to check
  it against the console's `ui.direct` name.
- **Home Assistant fetch.** It downloads every entity's state, not just the
  ones the tiles show.
- **Share uploads** have no size limit, and there's no cap on how many can
  wait unopened.
