# Adding a dashboard widget

A widget is a Flutter widget plus a `DashboardWidgetType` describing it.
Nothing else in the app needs changing: the browser editor builds its palette
and its settings form from that descriptor, and the saved configuration keeps
the options as an opaque bag.

## Where the widgets are

Not here. Every widget is an **add-on**, in a repository of its own —
[vwillcox/HomeCanvas-Widgets](https://github.com/vwillcox/HomeCanvas-Widgets)
— downloaded to a panel from the editor's **Add-ons** page and built in
there. The app has none of its own. What is in this folder is what widgets
are made from: `tile_bits.dart`, `fit_canvas.dart`, the feed, social and
video tiles, the sheets, and the two views the rest of the app shows for
itself — `calendar_view.dart` (the day's brief reads calendars the same way)
and `parcels_view.dart` (a shared tracking link opens a parcel's story
whether or not the Parcels tile is installed). An add-on imports them as `package:home_canvas/dashboard/widgets/…`.

How an add-on reaches a panel:

1. The catalogue's own checks (a GitHub Action there) read every add-on,
   build it into this app and run its tests. When they pass on its `main`,
   they write `index.json` to its `catalogue` branch: each add-on, the commit
   it was read at, and the SHA-256 of each of its files.
2. `lib/services/addons.dart` reads that index for the Add-ons page
   (`assets/dashboard/addons.html`, `/api/addons`).
3. Download starts `scripts/widget-build.sh addons <names>`, which has
   `scripts/addons.py` fetch the files — refusing any that does not match
   its sum — into `~/.config/homecanvas/addons/<name>/`, copies them to
   `custom/addons/<name>/` here, writes `custom/custom_registry.dart`,
   and rebuilds as for an uploaded widget (below): whole, or not at all.
   An add-on described in JSON needs no build and is installed at once.

`install.sh` and `scripts/sync.sh` run `scripts/addons.py ensure` before
they build: whatever the panel's dashboard uses and does not have is
fetched, so a panel laid out when the widgets were built in keeps them. A
panel with no dashboard yet gets the catalogue's starter set.

Which repository is read is `addonsRepo` under `dashboard` in config.json
(or `HOMECANVAS_ADDONS_REPO` for the scripts): `owner/name` on GitHub. It
is the panel's own setting — what comes from it is run — and the editor
cannot change it.

Beside the catalogue a panel can read **third-party libraries**:
repositories laid out the same way, named on the Add-ons page and kept as
`addonLibraries` under `dashboard`. Their files are held to their own
index's sums and nothing more — nobody has reviewed them — so the page
marks each add-on from one as untested, and one written in Dart is built
in only while the panel's own "Widgets written in Dart" switch is on. The
catalogue is read first: a library's add-on with a name or a widget type
the catalogue has is left out. The builder is asked for one as
`name@owner/repository`.

### Working on add-ons

With the catalogue checked out beside this repository:

```bash
HOMECANVAS_ADDONS=../HomeCanvas-Widgets/widgets HOMECANVAS_ADDON_TESTS=1 \
  scripts/widget-build.sh generate
```

copies every add-on into `custom/addons/` and its tests into `test/addons/`
(both git-ignored), after which `flutter run`, `flutter analyze` and
`flutter test` see the whole app as it was. Edit the widgets in the
catalogue's checkout and run it again. A handful of the app's own tests use
the catalogue's widgets as their examples and say they were skipped when
none are built in; `l10n/en-GB.arb` and the installer's catalogue are
written from the code with them built in, so write those with them linked.

`tool/addon_shots_test.dart` draws the picture each add-on is listed with.

What follows is how a widget is written — for the catalogue, or to upload
to one panel.

## 1. Write the widget

```dart
class TideWidget extends StatelessWidget {
  const TideWidget({super.key, required this.w});
  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    // w.theme  — colours, corner radius, fonts for the chosen theme
    // w.option — a setting, with the type's default as the fallback
    final port = w.option('port', 'Harwich');
    return Text(port, style: TextStyle(color: w.theme.textPrimary));
  }
}
```

Read settings through `w.option(key, fallback)` rather than `w.config.options`
directly, so a dashboard saved before an option existed still behaves.

Draw with `w.theme`. A widget that hard-codes colours looks wrong in four of
the five shipped themes and in every one written later.

## 2. Describe it

```dart
final tideWidgetType = DashboardWidgetType(
  type: 'tide',                    // stored in the config — never rename in place
  name: 'Tide times',
  description: 'High and low water for a port.',
  glyph: '🌊',                      // shown in the editor's palette
  defaultWidth: 3, defaultHeight: 2,
  minWidth: 2, minHeight: 2,
  options: const [
    WidgetOption(
      key: 'port',
      label: 'Port',
      defaultValue: 'Harwich',
      help: 'Say what the setting is for, not what it is.',
    ),
  ],
  build: (context, w) => TideWidget(w: w),
);
```

`OptionKind` covers `text`, `multiline`, `number`, `boolean` and `choice`
(with `choices: {'value': 'Label'}`).

## 3. Register it

In the catalogue, the widget's file ends by saying what it brings, and its
folder's `addon.json` names that file as its `entry`:

```dart
final widgetTypes = <DashboardWidgetType>[tideWidgetType];
```

That is the whole integration.

## Fetching things

Widgets are rebuilt often — whenever the clock ticks, a track changes, or
anything else on the dashboard updates. Never fetch in `build`. For feeds,
use `FeedService`, which caches by URL, serves stale content while
refreshing, and shares one fetch between widgets pointed at the same address.

## Uploading a widget, instead of building it yourself

A widget written exactly as above can be uploaded in the editor, under
**Custom widgets**, as a single `.dart` file. The panel builds it into
itself and restarts. The editor hands out a working example
(`assets/dashboard/example_widget.dart`) to start from.

The file is steps 1 and 2, and in place of step 3 one line the panel looks
for by name:

```dart
final widgetType = DashboardWidgetType(type: 'tide', … build: (context, w) => TideWidget(w: w));
```

What happens to it, in `scripts/widget-build.sh`:

1. The widgets already installed and the built app are copied aside.
2. The file is checked with the analyser. Errors stop it here, with the
   panel untouched and never restarted.
3. The app is built, and the kiosk restarted on the new build.
4. The editor is asked whether it is up, twice running.

If any step fails, the sources and the app are put back as they were — the
kiosk restarted on the old build if it had got as far as the new — and what
the compiler said is shown in the editor, to fix and upload again.

Uploaded Dart is run as the panel's own user, and the editor asks nobody who
they are. So it is off until switched on at the panel itself: Settings →
Dashboard → **Widgets written in Dart**. The editor cannot switch it on.

The files live in `~/.config/homecanvas/widgets-src/` on the panel, and are
copied into `lib/dashboard/widgets/custom/` at every build — `sync.sh` and
`install.sh` leave that folder alone and write its registry again, so a
build from a developer's machine keeps them.

## Custom widgets, without rebuilding

A widget can also be a JSON file, uploaded in the editor under **Custom
widgets** and on the panel at once — no rebuild, no restart. It has the same
descriptor as a built-in one, and where a built-in has Dart to fetch and
draw, it has a `source` and a `show`. The editor hands out a working example
(`assets/dashboard/example-widget.json`) to start from.

```json
{
  "type": "sea_state",
  "name": "Sea state",
  "description": "Shown in the editor's palette.",
  "glyph": "🌊",
  "defaultWidth": 3, "defaultHeight": 2, "minWidth": 1, "minHeight": 1,
  "options": [
    { "key": "place", "label": "Place", "default": "Harwich", "help": "…" },
    { "key": "latitude", "label": "Latitude", "kind": "number", "default": 51.95 }
  ],
  "source": { "url": "https://example.org/sea?lat={{option.latitude}}", "every": 900 },
  "show": { "kind": "value", "title": "{{option.place}}", "value": "{{current.level | number:2}} m" }
}
```

- **`type`** — lower-case letters, digits and underscores. A dashboard saves
  it as `custom_<type>`, so it can never take the place of a built-in one.
- **`options`** — `kind` is `text` (the default), `number`, `boolean`,
  `choice` (with `choices: {"value": "Label"}`), `multiline`, `secret` or
  `date`.
- **`source`** — a `url` that answers with JSON, fetched every `every`
  seconds (never oftener than 30), and optional `headers`. Leave `source`
  out for a widget that only shows its settings.
- **`show`** — one of three layouts:
  - `value`: a `title`, the `value`, a `detail` line.
  - `cards`: up to twelve `cards`, each a `glyph`, a `label` and a `value`.
  - `list`: `items` is the path to a list in the answer; `title` and
    `trailing` are drawn for each, up to `limit`.

Text in double braces is filled in: `{{current.wave_height}}` from the
answer (`a.b[0].c` reaches into it), `{{option.place}}` from the settings,
`{{item.name}}` from the row of a list. After a bar, what to do with it:
`number:1`, `round`, `percent`, `times:3.6`, `plus:1`, `time`, `date`,
`upper`, `lower`, `or:nothing`. What is missing is drawn as a dash.

It is a description the panel reads, never a program it runs — but it does
say which address the panel fetches, so it is taken only from the editor's
own page on the local network.

## Removing one

Deleting a type leaves any saved widget of that type in the configuration.
The dashboard draws it as "Unknown widget" and keeps its settings, so
reinstating the widget later brings it back intact rather than losing the
setup.
