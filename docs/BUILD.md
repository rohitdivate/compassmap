# Building Tradewind

## What you need

- A Mac with **Xcode 16 or later** (the project targets iOS 17 and the tests use Swift Testing).
- An **iPhone**, for anything involving the compass or the camera. The simulator has no
  magnetometer, so the arrow will not move and the camera screen shows its unavailable state.
- An **Apple Developer account** — a free one is enough to run on your own device. iCloud sync
  needs a paid one.

## First run

```bash
git clone https://github.com/rohitdivate/compassmap.git
cd compassmap
open Tradewind.xcodeproj
```

Then, once, before it will build for a device:

1. Select the **Tradewind** target → *Signing & Capabilities* → set your **Team**.
2. Do the same for the **TradewindWidgets** target.
3. Change the bundle identifiers. `com.tradewind.app` is a placeholder and almost certainly is not
   yours:

   | Where | Change from | To |
   | --- | --- | --- |
   | Tradewind target | `com.tradewind.app` | `com.yourname.tradewind` |
   | TradewindWidgets target | `com.tradewind.app.widgets` | `com.yourname.tradewind.widgets` |
   | App Group (both targets) | `group.com.tradewind.app` | `group.com.yourname.tradewind` |
   | iCloud container (Tradewind) | `iCloud.com.tradewind.app` | `iCloud.com.yourname.tradewind` |

4. Update the same identifiers in **[`Shared/Snapshot/AppGroup.swift`](../Shared/Snapshot/AppGroup.swift)**.
   That file is the single place the code refers to them, so it is one edit, not a search.
5. Build and run.

If you skip the iCloud container, the app still runs: the store falls back to the App Group without
CloudKit and Settings reports "On this iPhone only". If you skip the App Group too, it falls back to
a private container and says "widgets unavailable" — which is accurate, because widgets read the
shared container.

## Selecting a simulator vs. a device

Everything except the compass, the camera and Live Activities works in the simulator, and you can
fake a location with *Features → Location → Custom Location* to see distances change. For the arrow,
run on hardware.

## Running the tests

`⌘U`, or:

```bash
xcodebuild test \
  -project Tradewind.xcodeproj \
  -scheme Tradewind \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

The test bundle compiles the Foundation-only layers (`Shared/Math`, `Shared/Snapshot`,
`Shared/Metadata`) directly, so there is no host app and no signing involved.

## Checking it actually works, on a device

The parts that only hardware can prove:

1. **Capture** — take a photo of something 100–200 m away from where you are standing. The badge
   above the shutter should say "Good fix" with an accuracy in metres before you press it.
2. **The arrow** — open the spot. Turn on the spot; the ring should glow and the phone should tap
   you once. Turn away; the arrow should swing the *short* way round, not spin through north.
3. **Distance** — walk 50 m toward it. The number should fall smoothly, and the haptic pulses should
   speed up.
4. **Arrival** — get within 25 m. Confetti, a stamp on the photo, two ascending notes if sound is on.
5. **Widgets** — add each size from the home screen gallery. Long-press the small one and pick a
   specific spot. Check the medium one lists your three nearest. Add the Lock Screen accessories.
6. **Interactive widgets** — tap *Next* on the large widget. The pinned spot should move on without
   the app opening, and the app should agree next time you open it.
7. **Live Activity** — tap *Track on Lock Screen* on the arrow screen. Lock the phone; the distance
   should appear and update as you move. Check the Dynamic Island while another app is foreground.
8. **Siri** — "How far to \<spot name\> in Tradewind". It answers without opening the app.
9. **Spotlight** — swipe down, type a spot name; it should appear and open onto its arrow.
10. **Sharing** — share a spot to yourself in Messages. The postcard image and the link should both
    arrive; tapping the link should open the arrow. Try it on a device where the spot is *not*
    saved — the arrow should still work from the coordinates in the link, offering to save it.

## Regenerating the project

`Tradewind.xcodeproj` is generated and committed so the repo opens with no extra steps. After adding
or deleting a source file:

```bash
python3 Tools/gen_xcodeproj.py
```

CI fails if the committed project is out of date with the source tree.

If the generated project ever misbehaves, [`project.yml`](../project.yml) describes the same layout
for XcodeGen:

```bash
brew install xcodegen && xcodegen generate
```

## Other generated files

```bash
python3 Tools/make_appicon.py          # the app icon
python3 Tools/make_preview_images.py   # painted placeholders for the design preview
python3 Tools/build_preview.py         # docs/preview/index.html
```

## Continuous integration

[`.github/workflows/ios.yml`](../.github/workflows/ios.yml) builds the app and the widget extension
for the simulator and runs the tests on a macOS runner.

⚠️ **macOS runner minutes bill at 10× on private repositories.** If that is not wanted, disable the
workflow in the repository's Actions settings — nothing else in the project depends on it.
