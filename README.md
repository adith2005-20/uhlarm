# Proof of Wake

An iOS alarm that only stops once you prove you're up: scan a registered QR code or barcode, or tap an
NFC tag (e.g. on the bathroom mirror). Calm screens, a moving sky, Liquid Glass throughout.

The design handoff lives in [`CLAUDE.md`](CLAUDE.md) and [`design/SPEC.md`](design/SPEC.md).

## How it works

- **AlarmKit** rings the alarm, through Silent mode. The alert has two buttons:
  - **Prove you're awake** opens the app on the ringing screen → Stop → scanner or NFC screen.
  - **Silence 1 min** (the system stop button) silences completely, so unless you've already
    proved you're awake, the app books a re-ring 60 s later.
- While the ringing screen is open, a re-ring is kept ~75 s ahead, so leaving the app still ends in
  another alarm. Verifying cancels it.
- After verifying: **Good morning**, then a **Wake Up Check** five minutes later (local notification
  plus an in-app 60 s countdown). If you don't answer it, the alarm rings again with the same stop method.
- **Lost your code?** The emergency unlock: wait 90 s, type a sentence (paste is blocked), hold 3 s.

## Stop methods

| Method | How |
|---|---|
| QR code | VisionKit live scanner, QR only |
| Any barcode | Same scanner, all common symbologies |
| NFC tag | No Core NFC (needs a paid account). A Shortcuts personal automation runs **Verify Wake Tag** with the tag's name when the tag is scanned. The Codes tab walks you through it. `proofofwake://verify?tag=<name>` also works if you write it to the tag. |

Only a SHA-256 of the scanned code (with its symbology) is stored, never the payload.

## Sounds

Five built-in sounds (Sunrise, Meadow, Bells, Glass Harp, Pulse) are synthesized on first launch into
`Library/Sounds`, where AlarmKit plays them. Import your own from Files: it's converted to CAF and
trimmed to 30 s. The system alarm sound is also available.

## Look

- Typeface: **Sora** (SIL OFL, `Resources/Fonts`), applied through `Font.sora(_:_:)` and to UIKit
  navigation and tab bar chrome.
- App icon: "Rising edge", with Any, Dark and Tinted appearances in `Assets.xcassets/AppIcon`. The
  layered SVGs for an Icon Composer (Liquid Glass) icon are in `design/icon/layers`; exporting that
  `.icon` file needs Xcode on a Mac.

## Build and install (no Mac needed)

Every push runs `.github/workflows/build.yml` on a macOS runner. It generates the project with
XcodeGen, builds an unsigned Release `.app` and uploads `AlarmKitTest-ipa` as an artifact. Install
the `.ipa` with SideStore, which signs it with your free Apple ID.

The Xcode target is still called `AlarmKitTest` because the workflow builds that scheme. The app's
display name is **Proof of Wake** and its bundle ID is `com.adith.proofofwake`.

Locally on a Mac: `brew install xcodegen && xcodegen generate`, then open `AlarmKitTest.xcodeproj`.

## Code map

```
Sources/
  App/            entry point, root view (tabs, onboarding, ringing cover, URL handling)
  Model/          SwiftData models, ring-session store, formatting helpers
  Engine/         AlarmKit wrapper, App Intents, re-ring rules, sounds, notifications
  Theme/          every color (asset catalog, dawn/night) and type helpers
  Views/Sky/      animated sky: gradient, stars, sun bloom, layered clouds
  Views/Alarms/   list, create/edit, stop method, sound picker
  Views/Codes/    registered codes, registration, tester
  Views/Ring/     ringing, scanner, NFC, success, Wake Up Check, emergency unlock
  Views/Onboarding/
Resources/Assets.xcassets   colors and app icon
```
