# Tradewind

**Photograph a place. Walk away. Come back to it.**

An iPhone app that remembers exactly where you were standing when you took a photo, and points an
arrow back at it — with the distance counting down as you walk.

> **See it before you build it:** [`docs/preview/index.html`](docs/preview/index.html) — every screen,
> in both moods, set in the typefaces the app ships. A single self-contained file; open it straight
> from a clone.

---

## What it does

**Save a place.** The in-app camera stamps the coordinate, altitude and heading at the instant the
shutter fires. Or import a photo you already took — Tradewind reads the location out of its metadata,
and says so plainly when it has to fall back to where you are standing now.

**Point me there.** A compass rose, a tapered arrow that swings to the bearing, and a distance in
numbers big enough to read while moving. Walking time, height difference, and "turn left" / "turn
right" underneath. The arrow's glow warms as you close in and the phone taps you faster, so you can
navigate with it in your pocket. Arrive, and it says so properly.

**Everything at once.** A map with photo-thumbnail pins, range rings, and a great-circle line to
whatever you tap. Or the gallery, re-sorting itself by distance as you move.

**Without opening the app.** Widgets in every size — one following a spot you pin, one listing
everything nearest-first — plus all three Lock Screen accessories, two Control Centre buttons, and a
Live Activity that counts the distance down on the Lock Screen and in the Dynamic Island. Ask Siri
"how far to the waterfall", or find a spot from Spotlight.

**Trips.** Group spots into trips, each with a cover and, if you like, its own look.

**Two moods.** *Tropical Spritz* — piña cream, paloma pink, a serif for feeling and a mono for every
number. *Nomad Money* — near-black, one lime accent, hairlines instead of shadows, tabular figures
throughout. They differ in structure, not just colour: corner radii, elevation, type scale and whether
a gradient is allowed at all change with the mood. Change it and the widgets change too.

## Building it

Requires a Mac with Xcode 16 — Apple does not allow an iOS app to be signed anywhere else — and an
iPhone for anything involving the compass or camera.

```bash
git clone https://github.com/rohitdivate/compassmap.git
cd compassmap
python3 Tools/setup_signing.py --prefix com.rohitdivate --free   # your own name in the prefix
open Tradewind.xcodeproj
```

That rewrites the placeholder bundle identifiers to yours and regenerates the project, so the only
step left in Xcode is pressing Run. Drop `--free` if you have a paid Apple Developer membership; keep
it if you do not, because a free Apple ID gets a Personal Team, which cannot provision the App Group
the widgets read through — the app runs fully, for seven days at a time, with the widgets empty.
**[`docs/BUILD.md`](docs/BUILD.md)** has the full table and a device checklist.

## How it is put together

```
Shared/
  Math/         great-circle bearing and distance, angle smoothing, distance formatting, sun times
  Metadata/     EXIF GPS parsing
  Snapshot/     the small JSON file the widgets read
  Models/       SwiftData: Spot, Trip, and the container that degrades instead of crashing
  Services/     location and heading, the compass engine, camera, geocoding, haptics, Live Activity
  DesignSystem/ the two moods, the bundled faces, the arrow, the rose, the confetti
  Intents/      Siri, Shortcuts, and widget configuration
Tradewind/      the app: gallery, arrow, map, trips, detail, capture, settings, onboarding
TradewindWidgets/ widgets, Lock Screen accessories, Live Activity views, Control Centre controls
TradewindTests/ unit tests over everything in Math, Metadata and Snapshot
```

Four decisions shaped most of the rest:

**Widgets read a snapshot, not the database.** The app writes a small JSON file plus thumbnails into
the App Group on every change. A widget timeline provider never opens a CloudKit-backed SwiftData
store, so it cannot be blocked by sync, a schema mismatch, or a cold launch.

**The geometry is pure and tested.** Bearing, distance, angle unwrapping, smoothing, unit formatting,
EXIF hemispheres and sun times are Foundation-only functions with no UIKit or CoreLocation types. The
test bundle compiles them directly, so there is no host app and no signing in the test path.

**Angles are handled on the circle, not the number line.** Feeding raw magnetometer values into a
rotation makes the arrow jitter; averaging them makes it spin the long way past north. The filter
steps along the shortest arc and hands SwiftUI an unwrapped angle that keeps increasing.

**Persistence degrades in steps.** A CloudKit container refuses to open without its entitlement —
which is the normal state of a fresh clone — so the store falls back App Group → local → in-memory,
and Settings reports which one it actually got rather than which one you asked for.

There is more on the visual side, including what the widgets deliberately do *not* pretend to do, in
**[`docs/DESIGN.md`](docs/DESIGN.md)**.

## Tools

The repository generates a few of its own files:

```bash
python3 Tools/setup_signing.py --help  # your bundle identifiers and signing team
python3 Tools/gen_xcodeproj.py         # Tradewind.xcodeproj (committed; CI checks it is current)
python3 Tools/make_appicon.py          # the app icon, from the same curve as the in-app arrow
python3 Tools/make_preview_images.py   # painted placeholders for the preview
python3 Tools/build_preview.py         # docs/preview/index.html
```

## A note on how this was written

Tradewind was written in an environment without Xcode, so it was never compiled locally.
[`.github/workflows/ios.yml`](.github/workflows/ios.yml) is the compiler of record: it builds the app
and the widget extension and runs the tests on a macOS runner. The design was verified the other way
round — by rendering [the preview](docs/preview/index.html) and looking at all eighteen
screen-and-mood combinations. That is how the arrow screen was caught still offering to track a spot
you were already standing on.

⚠️ macOS runner minutes bill at 10× on private repositories. If that is not wanted, disable the
workflow in the repository's Actions settings; nothing else depends on it.
