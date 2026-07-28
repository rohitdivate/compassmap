# Tradewind 2026 — the design brief

The synthesis of three research passes (July 2026): the Liquid Glass platform study, the
best-of-2026 app study (Apple Design Awards 2025/2026, Flighty, Polarsteps, Not Boring,
Moonlitt, Tide Guide), and the photo-ingestion/durability prior-art study. This is the
document the redesign wave builds against; each numbered move cites why it earned its place.

## Thesis

Tradewind is exactly the species of app that wins design awards in 2026: a small,
single-purpose, data-rich utility. The winners' shared formula — obsessive touch feel,
hidden complexity, deep Liquid Glass adoption in the chrome, saturated content underneath,
and a palette tied to the real world — is the formula for this redesign. The two moods
(Tropical Spritz, Nomad Money) stay; they move from static palettes to living ones.

## Platform decision

**Minimum OS: iOS 26.** Every glass API is iOS 26-only with no backport; adoption is
~80–85% and rising; the devices dropped are 2018 models. Dual-path chrome for the last 15%
costs more than it returns for a personal app. The accessory show/hide API needs 26.2 —
guard that one call with `#available(iOS 26.2, *)`.

## The ten moves

1. **System glass tab bar replaces the custom capsule.** The system bar *is* now a floating
   glass capsule, with `.tabBarMinimizeBehavior(.onScrollDown)` and a bottom accessory we
   cannot replicate. Custom floating tab bars are a 2024 pattern; deleting ours buys the
   iOS 27 refresh for free.
2. **The live readout moves into `tabViewBottomAccessory`.** The mini-player idiom: when a
   spot is being tracked, a persistent glass strip shows mini-arrow + distance + ETA above
   the bar, compact when the bar minimizes (`tabViewBottomAccessoryPlacement`). This is the
   signature iOS 26 pattern and precisely our data.
3. **The arrow screen becomes Precision Finding.** The user's mental model comes from
   AirTag: giant display-type distance, plain-language direction ("240 m — bear left"),
   haptics that quicken as you close in, and an arrival bloom (color flood + success haptic
   + sound). The escalation curve is the product.
4. **Time-of-day living palettes.** Tide Guide won Visuals for a sky-matching palette. Each
   mood gets dawn/day/dusk/night variants keyed to local solar time (SolarTimes already
   exists in the codebase). Every screenshot becomes different; the app breathes.
5. **Glass the chrome, saturate the content.** Map and photos run edge-to-edge under glass
   controls clustered in one `GlassEffectContainer`; `.soft` scroll edges under bars;
   `backgroundExtensionEffect()` on photo headers; cards stay opaque in the content layer
   with our bundled fonts. Never glass-on-glass; never glass a card.
6. **Morphs, not cuts.** `glassEffectID` morphs the save button into its action row;
   `.navigationTransition(.zoom)` grows a card into the detail; the arrow ⇄ map ⇄ photo
   views of one place feel like turning one object over (Moonlitt's trio).
7. **Empty states are the onboarding.** First-run shows a ghost pin ("This could be your
   hotel"); every empty collection teaches with one CTA. Onboarding itself stays ≤4 screens;
   the only system prompt in it is location, primed by showing the arrow's value.
8. **Delete is soft, undo is standard.** Long-press context menu + Select mode on the grid
   (grids don't swipe), no confirm dialogs on delete — spots move to a 30-day Recently
   Deleted with restore; only permanent purge confirms. `deletedAt: Date?` keeps it
   CloudKit-safe.
9. **Memory resurfacing.** "One year ago, this taverna in Naxos" — Day One's On This Day +
   Polarsteps' trip playback are the loved features of the memory category. Cheap on our
   data model; emotionally the whole point of a photo-compass.
10. **Toy-like materiality on the compass.** Not Boring's lesson: the dial is a physical
    object. Grain, light that shifts subtly with device tilt (CoreMotion), a soft tick as
    the bezel crosses cardinal points. Paired with widget/Live Activity passes: handle the
    iOS 26 accented widget mode (photos otherwise get recolored), keep the Live Activity on
    system glass.

## The two commissioned features

**Automatic photo ingestion (no tab, no per-place save).** PhotoKit cannot filter by
location, so: metadata-only sweep of all image assets (no pixel decode — seconds for 50k
photos), read `asset.location` in memory, cluster time-gapped sessions into ~150 m places,
rank by visits × photos — and then save them, by itself. `PhotoIngestService` runs on scene
activation, throttled to a pass per day and a dozen places per pass; each cluster becomes a
spot through the existing `SpotStore.createSpot` path, reading "Somewhere you've been" until
the serialized GeocodeService backfills the area name. The home cluster (the biggest one)
is saved as a Home-kind spot. Idempotency is double-walled: geometry de-dupe against every
existing spot including the trash, plus a persisted set of seen cluster keys so a place
deleted on purpose never returns. Permission is the one system prompt, primed by an
onboarding page; Limited mode degrades honestly; the off-switch lives in Settings.

**Durability (free-tier honest) + deletion.** Nothing survives uninstall on a Personal
Team — so durability is export: a `.zip` archive (manifest + spots.json + trips.json +
photos/) via `fileExporter`, which the user can save to iCloud Drive through Files with no
entitlement; import merges by spot UUID, idempotently. GPX sidecar export/import for the
outdoor-app ecosystem. A rolling automatic snapshot in Documents is the safety net, with
"Last backed up" surfaced in Settings — and honest copy that only an exported file survives
reinstall. CloudKit promotion stays scaffolded for the paid tier; sync is not backup.

## Test doctrine (unchanged)

Decisions extracted to pure `Shared/Snapshot|Metadata|Math` types with unit tests
(clustering rule, palette schedule, backup manifest, suggestion ranking); XCUITest for
presentation; glass QA matrix: light/dark × Clear/Tinted (26.1 toggle) × Reduce
Transparency/Motion; GPU/thermal sanity on iPhone 11-class hardware.
