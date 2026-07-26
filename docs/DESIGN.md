# The design of Tradewind

There is a rendered version of everything below — every screen in every theme — at
[`docs/preview/index.html`](preview/index.html). Open it in a browser; it needs nothing.

## The idea

One number matters: how far away the place in the photograph is. Everything else on screen exists to
support reading that number at a glance, while walking, in sunlight, probably one-handed.

So the app is built around a single hero moment — a big arrow, a bigger number, and the photo of
where you are going sitting blurred behind both — and everything else is a way of getting to it.

## Themes

Six, and they are the app's personality rather than a preference buried in Settings. The theme picker
is the first thing onboarding ends on and the first thing Settings opens with. Changing it restyles
the widgets and the Live Activity too, because a theme that stops at the app boundary is not really
the app's identity.

| Theme | Palette | Reads as |
| --- | --- | --- |
| **Margarita** | lime zest, agave, salt, tequila gold | Bright, herbal, midday |
| **Paloma** | grapefruit pink, soda blue, pink salt | Soft, fizzy, late afternoon |
| **Hawaii Sunset** | mango, hibiscus, deep ocean violet | The default. Golden hour |
| **King Coconut** | tea fields, cinnamon, amber husk | Earthy, hill country |
| **Mango Temple** | lagoon turquoise, temple gold | Hot, tiled, humid |
| **Midnight Tide** | ink navy, phosphorescent teal | Night dive |

All six are night palettes, and the app opts out of light mode rather than shipping six
half-considered light variants. That is a deliberate limit, not an omission: the whole look depends on
a light source glowing out of a dark ground, and there is no honest way to invert that.

Every theme is a value in [`ThemeCatalog`](../Shared/DesignSystem/Theme.swift). Adding one is adding
an entry to `ThemeCatalog.all`; nothing else needs to change, including the widgets.

### Tokens

`Theme` carries exactly what a screen needs and nothing that is only used once:

- `backdrop` — three gradient stops, deepest first
- `mesh` — nine colours for the iOS 18 `MeshGradient`; enrichment, never a requirement
- `accent` / `accentSoft` — the interactive colour, and its contrast partner
- `arrow` — three stops along the dart, tip last
- `glow` — the halo behind the arrow, and button shadows
- `text` / `textMuted`
- `cardTint` — laid under frosted glass
- `celebration` — the arrival confetti
- `grainOpacity`

## Type

Two families, used for different jobs.

- **Serif** (`ui-serif` → New York) for names and headings. It reads like a beach-bar menu, which is
  the right register for a thing about places worth walking to.
- **Rounded** (`ui-rounded` → SF Rounded) for every number. Rounded digits are easier to read at a
  glance, and the whole app is really one big number.

Numbers that change are `monospacedDigit()` so the readout does not jitter as digits swap. Eyebrow
labels are tiny, uppercase and tracked out; they carry the state that would otherwise need a sentence
("Turn right", "Golden hour", "Nearest first").

## Motion

The rule is that motion should carry information, and where it cannot, it should be quiet.

- The **arrow** is smoothed with an exponential filter on the circle — one step per frame along the
  shortest arc. Raw magnetometer values jitter; naïve averaging spins the arrow the long way round
  through north. See `BearingMath.smoothed` and `BearingMath.unwrapped`.
- The **glow** grows with proximity, so getting closer is visible without reading anything.
- The **haptic pulse** accelerates as you approach — a warmer/colder game you can play with the phone
  in your pocket, which is the only way to navigate that does not involve staring at a screen.
- The **backdrop** drifts very slowly on the hero screens only. Everywhere else it is static, because
  an animated gradient behind a scrolling list is just battery.
- The **arrival** burst is the one unearned flourish, and it is allowed because arriving is the point.

## Craft details worth knowing

- **The arrow is drawn, not a symbol.** `ArrowShape` is four quadratic curves — long tip, swept wings,
  deep tail notch — so the silhouette is the app's own and reads as direction even at 10×16 points in
  a widget. The app icon is generated from the same curve.
- **Grain over every gradient.** Flat gradients band on OLED. `FilmGrain` lays a fixed dot field over
  the backdrop from a seeded PRNG, so it never shimmers between redraws.
- **A bottom scrim.** The backdrops run bright at their foot, which is where the floating bar sits.
  Without the scrim the tab labels land light-on-light. This was found by looking at the rendered
  preview, not by reading the code.
- **The compass rose rotates with its letters**, as a real rose does, rather than counter-rotating
  them to stay upright.
- **Placeholders are themed.** A photo that has not decoded yet shows a theme gradient and the spot's
  emoji, not a grey box, so a half-loaded grid still looks intentional.

## Honest limits

- **Widgets show a bearing, not a live compass.** WidgetKit cannot stream sensor updates, so the
  widget arrow points at the spot's compass bearing with north up. Where the distance came from a
  cached fix rather than a fresh one, the widget says "last known position".
- **The Live Activity does not follow your heading** either, for the same reason plus ActivityKit's
  update throttling. It counts the distance down, which is the useful part.
- **Golden hour is computed, not fetched.** Accurate to a minute or two, which is far better than the
  decision it informs. There is no weather.
- **Light mode is not supported**, as above.

## Where things live

```
Shared/DesignSystem/
  Theme.swift              tokens and the six palettes
  ThemedBackground.swift   mesh gradient, iOS 17 fallback, grain, time-of-day tint, bottom scrim
  CompassRose.swift        ArrowShape, DirectionArrow, CompassRose, MiniArrow, RadarRings
  CelebrationView.swift    arrival confetti and stamp
  Components.swift         glass card, pills, chips, buttons, empty states
  Typography.swift         the type scale
```
