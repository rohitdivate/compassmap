# The design of Tradewind

There is a rendered version of everything below — every screen in both moods, set in the typefaces the
app ships — at [`docs/preview/index.html`](preview/index.html). Open it in a browser; it needs nothing.

## The idea

One number matters: how far away the place in the photograph is. Everything else on screen exists to
support reading that number at a glance, while walking, in sunlight, probably one-handed.

So the app is built around a single hero moment — a big arrow, a bigger number, and the photo of
where you are going sitting blurred behind both — and everything else is a way of getting to it.

## Two moods

Not two colour schemes. The moods disagree about how a surface is separated from the page, what a
corner radius should be, how large a heading is, and whether a gradient is allowed at all. One
component definition satisfies both because the answers live in `Theme` as tokens rather than in the
views as constants.

| | **Tropical Spritz** | **Nomad Money** |
| --- | --- | --- |
| Reads as | Sun-soaked, editorial, tactile | Tabular, hairline, one accent |
| Scheme | Light, and it forces light | Dark, and it forces dark |
| Canvas | Piña Cream `#FFF6E9` | Void `#0A0B0D` |
| Cards | White, lifted on a soft shadow | `#131519`, separated by a 1px hairline |
| Accent | Paloma Pink `#FF6B8B` | Electric Lime `#C6F24E` — the only one |
| Second colour | Lagoon Blue `#1FA3B8`, Margarita Lime `#B8E62E` | None. Grey carries every non-accent state |
| Display face | Instrument Serif 400 · 40pt | Space Grotesk 700 · 28pt |
| Body face | DM Sans | Space Grotesk |
| Numerals | DM Mono | JetBrains Mono, tabular |
| Radii | 999 pills · 20 cards · 16 rows · 14 avatars | 10 controls · 16 cards · 14 rows · 9 avatars |
| Gradients | One per screen, behind a photo or as the hero. Never on a button | None |
| Grain | 3.5% over the canvas — it is paper | None — it is a screen |

Each mood fixes its own scheme, which is why `colorScheme` is a token and the app applies
`.preferredColorScheme(theme.colorScheme)`. A cream editorial mood rendered in dark mode is not that
mood any more, and a ledger mood in light mode is a spreadsheet.

### The rules each mood is written to

**Tropical Spritz.** Serif for feeling, mono for fact — never set a number in the serif. Cream, not
white, is the canvas; white is reserved for cards so they lift off it. Lime is a highlight, not a
surface: badges, progress, toggles-on. Primary buttons sit on a hard `0 3 0` offset in
`accentShadow` and press down into it. Copy is warm and short.

**Nomad Money.** One accent, and it means "this is the live value". Separation is a hairline, never a
shadow — `Elevation.hairline` collapses every card shadow and every button offset to zero. Numerals are
tabular so columns of distances line up. No decoration; density is the aesthetic.

Both are values in [`ThemeCatalog`](../Shared/DesignSystem/Theme.swift). The theme picker is what
onboarding ends on and what Settings opens with, and changing it restyles the widgets and the Live
Activity too, because a mood that stops at the app boundary is not the app's identity.

### Tokens

`Theme` carries structure as well as colour. The structural ones are the reason a single set of views
can be both moods:

- `colorScheme` — the mood's own scheme, forced
- `elevation` — `.shadow` or `.hairline`; `usesHairlines` and `cardShadow` derive from it
- `radii` — control, card, row, avatar, screen
- `scale` — ten sizes, from `display` down to `eyebrow`, plus `readout` and `cardNumber`
- `numerals` — `.mono` or `.tabularMono`; only the latter applies `monospacedDigit()`
- `displayFont` / `bodyFont` / `bodyMediumFont` / `bodyBoldFont` / `monoFont` / `monoMediumFont`,
  addressed by PostScript name
- `heroGradient` — the one permitted gradient, or `nil`, which `heroFill` resolves to a flat surface

and the colour ones: `canvas`, `surface`, `surfaceRaised`, `hairline`, `accent`, `onAccent`,
`accentShadow`, `secondary`, `highlight`, `onHighlight`, `depth`, `text`, `textMuted`, `textFaint`,
`positive`, `negative`, `glow`, `arrow`, `celebration`, `grainOpacity`.

## Type

Five families, all Open Font License, bundled in `Tradewind/Resources/Fonts` and registered by the app
and the widget extension both. Google Fonts' static cuts register each weight as its own family, so
faces are addressed by PostScript name through [`Fonts`](../Shared/DesignSystem/Fonts.swift) rather
than by family and weight — `Fonts.Sans.medium` is `"DMSans-Medium"`, not DM Sans at `.medium`.

- **Instrument Serif** — Spritz display. A masthead face; it reads like a travel magazine.
- **DM Sans** — Spritz body, three weights.
- **DM Mono** — every Spritz number.
- **Space Grotesk** — Nomad display *and* body, three weights. One family doing both is part of why
  that mood feels like a single instrument.
- **JetBrains Mono** — every Nomad number, tabular.

`Fonts.verifyRegistration()` logs any face the bundle failed to register, because a missing font
silently substitutes rather than failing, and a substituted display face is a different design.

Eyebrow labels are tiny, uppercase and tracked out; they carry state that would otherwise need a
sentence ("Turn right", "Golden hour", "Nearest first").

## Motion

Motion should carry information, and where it cannot, it should be quiet.

- The **arrow** is smoothed with an exponential filter on the circle — one step per frame along the
  shortest arc. Raw magnetometer values jitter; naïve averaging spins the arrow the long way round
  through north. See `BearingMath.smoothed` and `BearingMath.unwrapped`.
- The **glow** grows with proximity, so getting closer is visible without reading anything.
- The **haptic pulse** accelerates as you approach — a warmer/colder game you can play with the phone
  in your pocket, which is the only way to navigate that does not involve staring at a screen.
- The **backdrop does not move at all.** It used to drift. Neither mood permits it.
- The **arrival** burst is the one unearned flourish, and it is allowed because arriving is the point.

## Craft details worth knowing

- **The arrow is drawn, not a symbol.** `ArrowShape` is four quadratic curves — long tip, swept wings,
  deep tail notch — so the silhouette is the app's own and reads as direction even at 10×16 points in
  a widget. The app icon is generated from the same curve.
- **The compass rose rotates with its letters**, as a real rose does, rather than counter-rotating
  them to stay upright.
- **The arrow screen belongs to neither mood.** A photograph is the background, so the compass plate
  goes dark and translucent and the type goes white in both moods. A cream card over a photo reads as
  a hole punched in the picture, and a cream scrim washes the photo out.
- **Placeholders are themed.** A photo that has not decoded yet shows a themed surface carrying
  whichever glyph you gave the spot, not a grey box, so a half-loaded grid still looks intentional.

### Three things the moods cost us

Re-skinning removed features rather than restyling them, because the moods' own rules forbid them:

- **The mesh-gradient backdrop is gone.** Spritz allows one gradient per screen and spends it on the
  hero; Nomad allows none. `ThemedBackground` is now a flat canvas plus optional grain.
- **The bottom scrim is gone.** It existed because the old backdrops ran bright under the floating
  bar. A flat canvas does not, so the scrim had nothing to fix.
- **The time-of-day tint is gone.** A colour wash drifting over the canvas is decoration in a mood
  that permits none. `TimeOfDay` survives only for the greeting copy.

## Honest limits

- **Widgets show a bearing, not a live compass.** WidgetKit cannot stream sensor updates, so the
  widget arrow points at the spot's compass bearing with north up. Where the distance came from a
  cached fix rather than a fresh one, the widget says "last known position".
- **The Live Activity does not follow your heading** — ActivityKit cannot stream the magnetometer.
  It does stay live while the phone is locked: tracking a spot holds background location open for
  the walk (the blue indicator makes the cost visible), so the distance counts down and the pointer
  swings as you *move*, just not as you turn on the spot. Arrival or stopping the walk releases the
  GPS with it.
- **Golden hour is computed, not fetched.** Accurate to a minute or two, which is far better than the
  decision it informs. There is no weather.
- **Each mood forces its own scheme**, so the app does not follow the system appearance. Picking the
  look is picking light or dark; that is the trade the moods ask for.

## Where things live

```
Shared/DesignSystem/
  Theme.swift              structural and colour tokens, and the two moods
  Fonts.swift              PostScript names for the twelve bundled faces, and a registration check
  Typography.swift         the scale, as a Theme extension
  ThemedBackground.swift   flat canvas, grain, HeroPanel, TimeOfDay
  CompassRose.swift        ArrowShape, DirectionArrow, CompassRose, MiniArrow, RadarRings
  CelebrationView.swift    arrival confetti and stamp
  Components.swift         Surface, pills, chips, buttons, stat tiles, empty states
```
