# Building Tradewind

## Getting it onto your phone

You need a **Mac with Xcode 16 or later** and an **iPhone**. There is no way around the Mac: Apple
does not allow an iOS app to be signed or installed from anywhere else, and this container has no
Xcode, so no build of this app exists yet — only source that CI has proved compiles.

```bash
git clone https://github.com/rohitdivate/compassmap.git
cd compassmap

# Rewrites every bundle identifier to yours and sets the signing team, then regenerates the project.
python3 Tools/setup_signing.py --prefix com.yourname --team ABCDE12345

open Tradewind.xcodeproj
```

Then plug the iPhone in, pick it in the toolbar's device menu, and press **⌘R**. The first run asks
you to trust the developer certificate on the phone: *Settings → General → VPN & Device Management →
your Apple ID → Trust*.

**Your team ID** is the ten characters at https://developer.apple.com/account under *Membership
details*. If you have never signed in to Xcode with your Apple ID, do that first (*Xcode → Settings →
Accounts → +*) and it creates a free "Personal Team" for you.

### Free Apple ID vs. paid membership

This is the one thing worth knowing before you start, because it decides whether the widgets work.

| | Free Apple ID (Personal Team) | Apple Developer Program ($99/yr) |
| --- | --- | --- |
| App on your phone | Yes, **expires after 7 days** — re-run from Xcode to renew | Yes, for a year |
| Camera, compass, arrow, map, trips, sharing, Siri | All work | All work |
| **Widgets and Live Activity** | **Install but stay empty** | Work |
| iCloud sync between devices | No | Yes |

The widget limitation is Apple's, not a shortcut here: an App Group is the only channel through which
a widget extension can read the app's data, and a free Personal Team cannot provision one. So on a
free account, run:

```bash
python3 Tools/setup_signing.py --prefix com.yourname --team ABCDE12345 --free
```

which removes the App Group, iCloud and push entitlements — without that, Xcode refuses to build at
all, with *"Personal development teams do not support the App Groups capability"*. The app then falls
back to a private store and Settings honestly reports **"On this iPhone (widgets unavailable)"**.

If you later pay for a membership, `--paid` puts the entitlements back:

```bash
python3 Tools/setup_signing.py --prefix com.yourname --team YOURREALID --paid
```

`--reset` restores the `com.tradewind` placeholders, which is what the repository is committed with.

### What that script touches

So you can check it rather than trust it: the three bundle IDs in
[`Tools/gen_xcodeproj.py`](../Tools/gen_xcodeproj.py), the App Group and CloudKit container in
[`Shared/Snapshot/AppGroup.swift`](../Shared/Snapshot/AppGroup.swift), the URL name in
`Tradewind/Info.plist`, both `.entitlements` files, `project.yml`, and then it re-runs the project
generator. Nothing else in the code refers to an identifier.

### If it will not build

- **"Signing for 'Tradewind' requires a development team"** — you did not pass `--team`, or the ID is
  wrong. Check it against *Membership details*.
- **"Personal development teams do not support the App Groups capability"** — you are on a free Apple
  ID. Re-run with `--free`.
- **"Failed to register bundle identifier"** — someone already owns that identifier. Pick a different
  `--prefix`; it does not need to be a domain you actually own, just one nobody else has claimed.
- **"Unable to install"** on the phone — you have hit the free account's ten-app limit, or the
  certificate needs trusting; see the Trust step above.

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

The parts that only hardware can prove. Items 5 to 7 need the App Group, so they only apply on a paid
membership — see the table above.

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
python3 Tools/setup_signing.py --help  # bundle identifiers and signing team
python3 Tools/make_appicon.py          # the app icon
python3 Tools/make_preview_images.py   # painted placeholders for the design preview
python3 Tools/build_preview.py         # docs/preview/index.html
```

## Continuous integration

[`.github/workflows/ios.yml`](../.github/workflows/ios.yml) builds the app and the widget extension
for the simulator and runs the tests on a macOS runner.

⚠️ **macOS runner minutes bill at 10× on private repositories.** If that is not wanted, disable the
workflow in the repository's Actions settings — nothing else in the project depends on it.
