# Proof-of-Wake (working name)

An iOS 27 alarm app. The alarm only counts as stopped once the user proves they're awake by scanning a registered QR code or barcode, or by tapping an NFC tag (e.g. on the bathroom mirror). Inspired by Alarmy, but calmer: minimal screens, a sky that moves, Liquid Glass throughout.

The full visual spec is in `design/SPEC.md`. Screen images are in `design/screens/` (exported from the design canvas). `design/source/*.dc.html` are the raw design files: open them as text when you need an exact hex, size or radius. They won't render outside the canvas.

## Hard constraints (read before writing code)

1. **Free Apple ID + SideStore. No paid developer account.**
   - The app is sideloaded with SideStore on a free Apple ID. Do not use any capability that needs the $99 program: no Core NFC, no App Groups, no Associated Domains / universal links, no push notifications, no CloudKit.
   - Keep everything in a single app target unless a feature truly needs an extension. Intents run in the app's process, so plain `UserDefaults` / SwiftData shared inside the app is enough.
2. **AlarmKit is the alarm engine.** Tested on this setup: it schedules and rings through Silent mode.
3. **The system Stop button silences the alarm completely.** Tested. Scan enforcement therefore needs the re-ring workaround described below.
4. **iOS 27 / Xcode 27 force Liquid Glass.** Use the system glass (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)` / `.glassProminent`). Don't fake it with materials or custom blurs, and don't stack glass on glass. Standard controls render larger in 27, so check every layout at the largest Dynamic Type size.
5. **SwiftUI only, no third-party UI or animation libraries** (no Lottie). Typeface is **Sora** (bundled in `Resources/Fonts`, OFL; use `Font.sora(_:_:)` from `Theme.swift`, never `.system` text styles). SF Symbols for icons.

## Alarm flow and the re-ring workaround (documented, NOT yet tested: spike this first)

```
AlarmKit alert (system UI)
 ├─ secondary button "Prove you're awake" → secondaryIntent (opens the app) → RingingView → Stop → Scanner / NFC
 └─ system Stop button → stopIntent → if no verified scan for this alarm: schedule a re-ring at now + 60 s
```

- Build with `AlarmManager.AlarmConfiguration.alarm(schedule:attributes:stopIntent:secondaryIntent:sound:)`.
- `stopIntent`: a `LiveActivityIntent`. It checks `WakeStore.isVerified(alarmID)`. If not verified, it schedules a one-shot alarm 60 s out, with the same attributes, label and stop method.
- `secondaryIntent`: opens the app (`openAppWhenRun` / an `OpenIntent`) and routes to `RingingView` for that alarm.
- Verifying (QR match or NFC intent) marks the alarm verified, cancels any pending re-ring, shows the success screen and schedules the Wake Up Check (+5 min).
- If the alert's Stop button label can be customised, call it something honest like "Silence 1 min".
- **Spike 0 is to prove this works on device:** tap Stop, wait 60 s, confirm it rings again. If intents can't schedule from the stop action, report back before building further.

## Stop methods

| Method | How | Status |
|---|---|---|
| QR code | VisionKit `DataScannerViewController`, `recognizedDataTypes: [.barcode(symbologies: [.qr])]` | Should work on a free account |
| Any barcode | Same scanner, all symbologies | Should work on a free account |
| NFC tag | **No Core NFC.** The app exposes an App Intent `VerifyTagIntent(tagName:)` through `AppShortcutsProvider`. The user creates a Shortcuts Personal Automation: *When NFC tag "Bathroom mirror" is scanned → Run VerifyTagIntent*. The intent marks the alarm verified and brings the app forward to play the NFC success animation. | Untested |
| NFC fallback idea | Write a custom-URL-scheme record (`proofofwake://verify?tag=mirror`) to the tag and handle it with `onOpenURL` | Untested; may not open custom schemes |

Store a SHA-256 of the scanned payload + symbology, never the raw payload.

## Build and run

- Building needs **Xcode 27 on a Mac**. Without a Mac: write code here, then build an unsigned `.ipa` on a macOS CI runner (e.g. GitHub Actions `macos-latest`, `xcodebuild archive` with `CODE_SIGNING_ALLOWED=NO`, then zip `Payload/`), and install it with SideStore, which signs it with the free Apple ID.
- Deployment target: iOS 27. Info.plist needs `NSAlarmKitUsageDescription` and `NSCameraUsageDescription`.

## Build order

0. Spike: AlarmKit schedule + stopIntent re-ring (above). Tiny UI, prove the mechanism.
1. Sky background (`SkyView`) + Alarm list + Create/Edit sheet + persistence (SwiftData).
2. Ringing screen (night + dawn) wired to the AlarmKit secondary intent.
3. QR / barcode scanner with match / wrong-code states, flashlight.
4. Success + Wake Up Check.
5. NFC via Shortcuts automation + the NFC success animation.
6. Lost-code fallback (90 s wait → type sentence → hold 3 s).
7. Accessibility pass: transparency slider extremes, Reduce Transparency, Increase Contrast, Reduce Motion, VoiceOver, largest Dynamic Type.

## Conventions

- One `Theme` file holds every color from `design/SPEC.md` as named asset-catalog colors with Any (dawn) / Dark (night) appearances. No hex literals in views.
- Animations: springs with low bounce (≤ 0.2). Nothing flashes. Respect `accessibilityReduceMotion` everywhere.
- Haptics with `.sensoryFeedback` only.
- Touch targets ≥ 44 pt. Primary action buttons are 56–76 pt tall.
- Ask before changing anything that alters the look defined in `design/SPEC.md`.
