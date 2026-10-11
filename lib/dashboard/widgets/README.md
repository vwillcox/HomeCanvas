# Adding a dashboard widget

A widget is a Flutter widget plus a `DashboardWidgetType` describing it.
Nothing else in the app needs changing: the browser editor builds its palette
and its settings form from that descriptor, and the saved configuration keeps
the options as an opaque bag.

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

Add it to the list in `widgets.dart`. That is the whole integration.

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
