# Themes

Sixteen themes ship with ImmichKioskPi: dark and light, glassy, glossy and
flat. A theme dresses the **whole kiosk**: the dashboard, the photo browser,
the music player, the weather panel, Settings and the rest. Photos and videos
themselves are always shown on black.

Pick one in the dashboard editor's **Look** panel (at `http://<pi>:8090`), or in
**Settings → Display → Dashboard → Theme** on the panel itself. Each picture
below is the same dashboard page on the real panel, in that theme.

- [Dark](#dark): [Glass](#glass) · [Aurora](#aurora) · [Abyss](#abyss) ·
  [Obsidian](#obsidian) · [Synthwave](#synthwave) · [Midnight](#midnight) ·
  [Ember](#ember) · [Forest](#forest) · [Espresso](#espresso) ·
  [Terminal](#terminal) · [Terminal Night](#terminal-night) ·
  [Nightstand](#nightstand)
- [Light](#light): [Frost](#frost) · [Paper](#paper) · [Sorbet](#sorbet) ·
  [Swiss](#swiss)
- [Making your own](#making-your-own)

![All sixteen themes](docs/screenshots/themes/all.jpg)

---

## Dark

### Glass

*Glassy · the default.* The kiosk's own look: near-black with a soft blue glow
from the top left, frosted tiles with tight gaps, and a pale blue accent.

![Glass](docs/screenshots/themes/glass.jpg)

### Aurora

*Glassy.* Glass after dark: an inkier black lit violet from the top left and
teal from the bottom right, light catching the top of each tile, and a mint
accent between the two.

![Aurora](docs/screenshots/themes/aurora.jpg)

### Abyss

*Glassy.* Deep water: blue light from above, cyan from below, and very clear
glass with big rounded corners.

![Abyss](docs/screenshots/themes/abyss.jpg)

### Obsidian

*Glossy.* Black lacquer: solid tiles rather than glass, a strong gloss along
the top of each, and a champagne-gold accent.

![Obsidian](docs/screenshots/themes/obsidian.jpg)

### Synthwave

*Glossy · Chakra Petch.* Eighties neon: magenta and cyan light on deep purple,
tiles edged in pink and glossed, in a techno face that stays readable.

![Synthwave](docs/screenshots/themes/synthwave.jpg)

### Midnight

*Glassy.* A navy gradient with see-through tiles and a sky-blue accent.

![Midnight](docs/screenshots/themes/midnight.jpg)

### Ember

*Glassy.* Warm dark browns and reds with an orange accent, like a fire gone
to coals.

![Ember](docs/screenshots/themes/ember.jpg)

### Forest

*Glassy.* Deep greens with pale-mint tiles and a green accent.

![Forest](docs/screenshots/themes/forest.jpg)

### Espresso

*Flat · Lora.* Warm and bookish: flat coffee-brown tiles with no edges or
shadows, a serif face and a caramel accent.

![Espresso](docs/screenshots/themes/espresso.jpg)

### Terminal

*Flat · Share Tech Mono.* A green-screen terminal: phosphor on black, hairline
boxes, a monospaced face and the faintest glow, as off an old tube.

![Terminal](docs/screenshots/themes/terminal.jpg)

### Terminal Night

*Flat · Share Tech Mono.* Terminal with the lights off: true black, no glow,
boxes you only just see, and a softer green that is easy on the eyes in a dark
room.

![Terminal Night](docs/screenshots/themes/terminal-night.jpg)

### Nightstand

*Flat.* Deliberately plain and very high contrast: white and amber on black,
no tiles at all. It's readable across a room, and the gentlest choice for an
always-on panel because so little of the screen is lit.

![Nightstand](docs/screenshots/themes/nightstand.jpg)

---

## Light

### Frost

*Glassy.* Glass in daylight: frosted white panes on ice blue, a white bloom
from the top left, and light along each pane's top edge.

![Frost](docs/screenshots/themes/frost.jpg)

### Paper

*Flat.* Warm off-white paper with white cards and a burnt-orange accent.

![Paper](docs/screenshots/themes/paper.jpg)

### Sorbet

*Glossy · Nunito.* Sweets in a shop window: glossy near-white panes over a
peach-to-pink wash, a coral accent and a rounded face.

![Sorbet](docs/screenshots/themes/sorbet.jpg)

### Swiss

*Flat · Inter.* International Typographic Style: flat white blocks on grey,
square corners, wide gutters, black type and one signal red. No gloss, no
glass, no shadow.

![Swiss](docs/screenshots/themes/swiss.jpg)

---

## Making your own

A theme is a JSON file. Copy
[`deploy/theme-template.json`](deploy/theme-template.json) into
`~/.config/immich_kiosk_pi/themes/` on the Pi, change it, and restart the kiosk.
It appears in both pickers. A file with the same `id` as a built-in theme
replaces that theme.

| Setting | What it does |
|---|---|
| `background` | One colour for a flat background, two for a gradient |
| `surface`, `border` | Each tile's fill and edge. See-through for glass, solid for flat or glossy |
| `textPrimary`, `textSecondary`, `accent` | Text, quieter text, and what the eye should land on first |
| `glow`, `glowEnd` | Soft light from the top left and the bottom right |
| `sheen` | Light along the top of each tile: 0 for none, about 0.05–0.1 for glass, more for gloss |
| `cornerRadius`, `gap`, `shadow` | The shape of the tiles and the space between them |
| `fontFamily` | Any of the twenty bundled fonts, for the whole kiosk |

Colours are `#rrggbb`, or `#aarrggbb` for see-through. The built-in themes are
held to WCAG contrast levels by a test (`test/theme_contrast_test.dart`): body
text at 7:1 against its tiles, secondary text at 3.5:1 and the accent at 3:1.
That's worth matching in your own.
