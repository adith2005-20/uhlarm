<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="128" alt="uhlarm icon">
</p>

<h1 align="center">uhlarm</h1>

<p align="center">
  An alarm clock you can't snooze from under the covers.<br>
  It only stops when you get up and scan a code or tap a tag.
</p>

<p align="center">
  <img alt="iOS 26+" src="https://img.shields.io/badge/iOS-26%2B-black">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-orange">
  <img alt="SwiftUI" src="https://img.shields.io/badge/UI-SwiftUI-blue">
</p>

---

## Features

- **Prove you're up.** Turn alarms off by scanning a QR code, any product barcode, or tapping an NFC tag
  that lives somewhere away from your bed.
- **No easy way out.** Silencing the alarm only buys 15 seconds before it rings again.
- **Wake Up Check.** Five minutes after you turn it off, uhlarm makes sure you didn't go back to sleep.
- **Emergency unlock.** Lost the code? Wait 90 seconds, type a sentence and hold to turn off.
- **Rings through Silent mode**, powered by AlarmKit.
- **Your sounds.** Five built-in alarm sounds, the system alarm, or import any audio file.
- **Calm design.** A living sky with drifting clouds and a rising sun, Liquid Glass controls and the
  Sora typeface.
- **Accessible.** Supports Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency and Increase Contrast.

## How it works

1. **Register a code** in the Codes tab: a QR code on the kitchen wall, the barcode on your coffee bag,
   or an NFC sticker on the bathroom mirror.
2. **Create an alarm** and choose which code turns it off.
3. **When it rings**, tap **Prove you're awake**, then scan the code or tap the tag.
   Tapping **Silence 15 sec** instead quiets it briefly, then it rings again.
4. **Good morning.** Five minutes later, a Wake Up Check notification asks if you're still up. Tap it and press **I'm up** within a minute, or the alarm returns.

## Stop methods

| Method | How it works |
|---|---|
| QR code | Scanned with the camera. |
| Barcode | Any common product barcode (EAN, UPC, Code 128 and more). |
| NFC tag | Read by iOS through a Shortcuts automation that runs uhlarm's **Verify Wake Tag** action. |

Scanned codes are never stored. uhlarm keeps only a SHA-256 fingerprint of each code and compares
against that.

### Setting up an NFC tag

1. In uhlarm, go to **Codes → + → NFC tag** and give the tag a name, e.g. *Bathroom mirror*.
2. Open **Shortcuts → Automation → New Automation → NFC**, scan the tag and choose **Run Immediately**.
3. Add the **Verify Wake Tag** action from uhlarm and set **Tag Name** to the same name.
4. Back in uhlarm, tap **Test tag** and hold your phone to it.

Alternatively, write the URL `uhlarm://verify?tag=<name>` to the tag with any NFC writer app.

## Building

**Requirements:** Xcode 26 or later, iOS 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open AlarmKitTest.xcodeproj
```

The Xcode project is generated from `project.yml`; the scheme is named `AlarmKitTest`.

Every push builds an unsigned `.ipa` with GitHub Actions (`.github/workflows/build.yml`). Download it from
the run's **AlarmKitTest-ipa** artifact and install it with a sideloading tool such as SideStore or AltStore.

## Project structure

```
Sources/
├── App/            App entry point and root view
├── Model/          SwiftData models, ring-session store, formatting
├── Engine/         AlarmKit wrapper, App Intents, re-ring rules, sounds, notifications
├── Theme/          Colors, Sora type helpers
└── Views/
    ├── Sky/        Animated sky: gradient, stars, sun, layered clouds
    ├── Alarms/     Alarm list, editor, stop method, sound picker
    ├── Codes/      Registered codes, registration, tester
    ├── Ring/       Ringing, scanner, NFC, success, Wake Up Check, emergency unlock
    └── Onboarding/
Resources/
├── Assets.xcassets Colors and app icon
└── Fonts/          Sora
design/             Visual spec, design source files, icon layers
```

## Credits

- [Sora](https://github.com/sora-xor/sora-font) typeface, licensed under the
  [SIL Open Font License 1.1](Resources/Fonts/OFL.txt).
