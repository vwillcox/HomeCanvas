# Testing HomeCanvas 2.0.0 alpha 3

This alpha moves every widget out of the app, and makes the dashboard the
kiosk's first screen: the photo albums are a widget now too. All fifty-two now live in
[HomeCanvas-Widgets](https://github.com/vwillcox/HomeCanvas-Widgets) as
**add-ons**, and the editor has an **Add-ons** page to download them from.
None is built in any more: the app is what widgets are made from.

It is an alpha: it has passed its tests and been built, but it has not yet
run on a panel on a wall. Try it on a panel you can afford to have out of
action for an evening, and keep the backup below.

## Before you start

On the panel (over SSH):

```bash
cp -a ~/.config/homecanvas ~/homecanvas-config-backup
```

The panel needs to reach `raw.githubusercontent.com` to fetch add-ons.

## Installing it

**On a panel that already runs HomeCanvas** (the case most worth testing):

```bash
cd ~/homecanvas
git remote set-branches --add origin widget-addons
git fetch --depth 1 origin widget-addons
git checkout widget-addons
bash install.sh
```

Choose **Update** when the installer asks. Before it builds, it fetches
every add-on your dashboard uses — look for the line
`Add-ons installed: …` in `~/homecanvas-install.log` if you want to see
which.

**On a fresh Raspberry Pi:**

```bash
curl -fsSL https://raw.githubusercontent.com/vwillcox/HomeCanvas/widget-addons/install.sh | HOMECANVAS_BRANCH=widget-addons bash
```

## What to try

Tick these off, and say which failed.

**1. Your dashboard survived the update**

- [ ] Every tile you had is still there and working — none says
      "Unknown widget".
- [ ] Settings → About says version 2.0.0-alpha.3.

**2. The Add-ons page**

Open the editor (`http://<panel>:8090`) and choose **Add-ons**.

- [ ] The list loads, each add-on with a picture, a description, its author
      and its group.
- [ ] What your dashboard uses is marked **Installed**.
- [ ] Search, and the group buttons, narrow the list.

**3. Downloading one written in Dart**

Pick one you do not have — **Tides**, say — and press **Download**.

- [ ] The page says it is fetching, then building, then restarting.
      Expect several minutes on a Pi — please say how long it took.
- [ ] The panel comes back by itself, and the page says it is built in.
- [ ] The widget is in the editor under **Add a widget**, and works on the
      panel.

**4. Several at once**

- [ ] Tick **Pick with others** on two or three, then **Download these**:
      one build, one restart, all of them there afterwards.

**5. One described in JSON**

- [ ] Download **Sea state**. It should be installed within a second or
      two, with no rebuild and no restart.

**6. Removing**

- [ ] **Remove** an add-on that is on your dashboard. After the rebuild
      its tile says "Unknown widget" and the Add-ons page offers, at the
      top, to download what your dashboard is waiting for.
- [ ] Press that button: the tile comes back with its settings as they
      were.

**7. When the network is away** (if you can)

- [ ] With the panel's internet unplugged, the Add-ons page says the
      catalogue could not be reached and still lists what is installed.
      The dashboard itself is unaffected.

**8. Calendar and Parcels are add-ons too** (new in alpha 2)

- [ ] If your dashboard had a Calendar or Parcels tile, it is still there
      after the update, and both show as **Installed** on the Add-ons page.
- [ ] With Parcels removed, a tracking link shared from the phone still
      arrives, and Your day still lists what is due.

**9. A third-party library** (new in alpha 2)

At the foot of the Add-ons page, open **Third-party libraries**.

- [ ] The warning is plain: untested, and at your own risk.
- [ ] **Add library** stays greyed out until the box is ticked.
- [ ] A name that is not a library (`someone/nothing`) is refused, in words.
- [ ] If you have a library to hand (the catalogue's
      `docs/your-own-library.md` says how to make one): its add-ons are
      listed, each marked **Untested — from …**; one written in Dart will
      not download until "Widgets written in Dart" is switched on in
      Settings → Dashboard on the panel; **Stop reading** takes the library
      away again.

**10. The dashboard is home, and the albums are a tile** (new in alpha 3)

- [ ] The panel starts on the dashboard, not the albums. Its top bar has
      the greeting, the Dashboard button lit, Photos, the lock (if the
      Locked Folder is set up), Settings.
- [ ] If the panel was connected to Immich, the update added a last page
      named **Photos** with the **Photo albums** tile filling it.
- [ ] **Photos** in the top bar turns to that page. On a smaller albums
      tile it also brings the tile close.
- [ ] In the tile: tap an album — its photos, Slideshow, a photo, a video
      all work, and back comes back to the dashboard.
- [ ] The search button opens Find photos.
- [ ] The tick button, then two albums, then **Slideshow**: one slideshow
      of both.
- [ ] The ⤢ button opens all the albums full screen: sorting, Find photos,
      holding albums to pick them for a slideshow, Refresh, back.
- [ ] Take the Photos tile off in the editor and update or restart: it is
      not put back.
- [ ] "Hey canvas, show the photos" goes to the tile.
- [ ] Settings → Display has no "Widget dashboard" switch any more.

**11. Themes are add-ons** (new in alpha 3)

- [ ] After the update the panel is still in its theme (it was fetched).
- [ ] Add-ons → **Themes** lists sixteen, with a picture of each; the one
      in use says **Installed, and in use**.
- [ ] Download another: it is in the theme pickers at once, no restart.
- [ ] Remove the one in use: the panel goes back to Glass straight away.
- [ ] Download it again and choose it: back as it was.
- [ ] **Third-party libraries** is what the box at the foot of Add-ons is
      called now.

**12. Everything else still works** — nothing here should have changed it,
which is the point of checking: the slideshow, music, voice, the share
inbox, the day's brief, uploading a widget of your own under
**Custom widgets**.

## If something goes wrong

A build that fails puts the panel back on the build it had, and the
Add-ons page shows what the compiler said — please copy that into your
report. The fuller log is `~/.local/share/homecanvas/widget-build/build.log`.

To go back to 1.0.3.2:

```bash
cd ~/homecanvas
git checkout main
bash install.sh
cp -a ~/homecanvas-config-backup/. ~/.config/homecanvas/   # only if your settings were disturbed
```

## Reporting

Open an issue at <https://github.com/vwillcox/HomeCanvas/issues> with
**2.0 alpha** in the title: which step, what you saw, what Pi and screen,
and the build log if a build was involved. Do not paste `config.json`; it
has your keys in it.

## Known in this alpha

- The music's mini player that sat above the albums is gone with the old
  photo screen: the dashboard's top bar and the Now playing tile do its job.

- Every add-on written in Dart is a rebuild of the app on the Pi. Picking
  several at once is the way to keep that to one.
- Translations for the Add-ons page itself are English only so far; the
  widgets keep their translations.
- The installer's widget checklist still lists every widget; what you tick
  is fetched as add-ons before the first build.
- Anyone on your network who can open the editor can download an add-on
  from the catalogue, which rebuilds the panel. Uploading Dart of your own
  still needs the switch in Settings → Dashboard, and so does
  installing Dart from another library.
- Add-ons from another library are not tested by anyone but their owner.
