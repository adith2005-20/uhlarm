# Design spec

Source canvas: "Proof-of-Wake Alarm" (Claude design canvas; Proof of Wake was the working name for uhlarm). Screens are numbered as on the canvas.

## Look

- **Night sky** (dark appearance): the setup screens, NFC, fallback, and the dark ringing screen.
- **Dawn sky** (light appearance): success, Wake Up Check, and the light ringing screen.
- Clouds drift slowly behind Liquid Glass on every sky screen; stars twinkle at night.
- One warm accent (sunlight). Minimal: few elements per screen, generous whitespace.

## Tokens

| Token | Night (Dark) | Dawn (Any) |
|---|---|---|
| skyTop | #081326 | #7FB2EA |
| skyMid | #12264A / #14294F | #B5D3F1 |
| skyHorizon | #2B4A78 (ringing: #34507E) | #F1DCCB → #FFD1A6 |
| text | #F5F8FF | #10233A |
| textSecondary | text @ 70 % | text @ 72 % |
| accent | #FFC46B | #FFB547 (fills only; ink label on top) |
| sunBloom | #FFD27A → #FF9F5A | #FFECBE → #FFC27A → #FFB547 |
| clouds | #9DB3D6 / #B4C7E4 @ 18–30 %; warm-lit #FFB988 / #FFC9A0 near sunrise | #FFFFFF / #FFE6D2 @ 60–85 % |
| calmSky (after NFC success) | #24497A → #4F7FB6 → #8DB5DF | — |
| success | #30D158 | #248A3D |
| error / wrong | #FF7A66 | #D9442F |

Type: **Sora** throughout. Sora Light for big clock times (136 pt ringing, 58–60 pt list); Sora Regular body 17, secondary 15; Medium for labels; SemiBold for buttons and titles; Bold for large titles (34). Sizes follow the system text styles and scale with Dynamic Type.
Radii: cards 28, sheet 38, grouped sections 24, buttons are capsules.

## SkyView (shared background)

- `LinearGradient` top → horizon.
- Stars: `Canvas` of ~12 small circles; opacity 0.35 ↔ 0.9 over 5 s.
- Clouds: `Canvas` of 4 overlapping ellipses, `.blur(radius: 9)`; x offset drifts ±40 pt over 60–90 s, each cloud at its own speed and direction. Stop under Reduce Motion.
- Ringing variant: sunrise `RadialGradient` anchored at the bottom, breathing (scale 0.94 ↔ 1.04, 4.5 s ease-in-out). Intensity rises from ~0.55 to 1.0 over ~5 min of ringing.

## Screens

**01 Alarm list (night).** Large title "Alarms" + "Next alarm in …". Each alarm is a glass card (radius 28) with time, AM/PM, a meta line (label · days · method icon + name) and a toggle tinted accent. All cards sit in one `GlassEffectContainer`. Toolbar: Edit (glass capsule), + (glass circle). Floating glass tab bar: Alarms, Codes.

**02 Create / Edit (night).** Clear-background sheet so the sky shows through. Cancel (xmark) and Save (accent-filled check) in the toolbar. Wheel time picker; 7 day circles (44 pt, selected = accent fill with ink letter); Label; "Gentle wake": Gradual volume (rises over 60 s) and Vibration toggles; "Turn off by" row → 02b. Sections are plain tinted fills, not glass.

**02b Stop method (night).** Intro line; three rows: QR code, Any barcode, NFC tag (check on the selected one). "Your tag": name + status. Full-width accent "Test tag" button.
⚠️ With NFC done through Shortcuts, this screen needs an extra step that guides the user to create the automation (deep link into Shortcuts). The canvas doesn't show that yet.

**03 Ringing (night + dawn).** Date, huge time, label, ONE glass "Stop" capsule (76 pt) at the bottom. The night version is a sunrise breaking through warm clouds. The label always sits on its own tint (navy 35 % at night, white 50 % at dawn) so it stays legible at every transparency setting.

**04 Scan (camera, minimal).** Full-bleed camera, four thin white corner brackets (240 pt, breathing 1 ↔ 1.025), small glass close button top-left. Bottom: one glass row with the instruction pill ("Scan the kitchen QR") and a 56 pt glass flashlight button. Auto-detect, no shutter.
- Matched: brackets turn green and close in to 0.62 scale, a small green check pops in, pill = "Matched", success haptic, go to 06 after 0.6 s.
- Wrong: brackets turn coral and shake (−10, 8, −4, 0 over 0.45 s), pill = "Not that one", error haptic. The "Code missing?" link appears above the bar after a wrong scan or 60 s.

**05 NFC (night).** Glass disc (168 pt) centred in the upper half, breathing warm glow; three accent rings ripple outward (scale 1 → 2.4, 6 s loop, staggered). Hint: "Hold your phone to the tag" + tag name. Small antenna glow at the top edge.
- Success (~1.2 s, see frame table): plays when `VerifyTagIntent` fires.
- Failure: disc tinted coral, shakes (−12, 10, −6, 0 / 0.45 s), exclamation icon, "That's not the mirror tag", glass "Try again" button.

| Time | Phase | What happens | API |
|---|---|---|---|
| 0 ms | Waiting | disc breathes, rings drift | phaseAnimator, TimelineView |
| 0–80 ms | Contact | antenna edge flashes, disc presses to 0.93, success haptic | .sensoryFeedback(.success) |
| 80–300 ms | Snap | 3 white rings burst from the top edge, 80 ms apart, scale 0.1 → 7 | scaleEffect(anchor: .top) |
| 300–600 ms | Ripple | rings sweep past, disc wobbles to 1.06, wave icon dissolves | .spring(duration: 0.35, bounce: 0.15) |
| 600–900 ms | Morph | checkmark replaces the wave; sunrise fades, calm sky fades in | .contentTransition(.symbolEffect(.replace)) |
| 1200 ms | Settled | calm sky, white check, "Alarm off / You're up" | glassEffectID("disc", in: ns) → 06 |

**06 Dismissed (dawn by day, night after 7 PM).** Glass disc (140 pt) with check, "You're up", "Alarm off at 6:34 AM", glass pill "Wake Up Check in 5 minutes" (only when the alarm has Wake Up Check on), accent "Done" button.

**07 Wake Up Check (dawn by day, night after 7 PM).** "Wake Up Check / Still up?", glass disc (240 pt) with a countdown ring (accent, 8 pt) and "0:48", the line "Tap before the timer ends, or the alarm rings again.", accent "I'm up" (76 pt). No answer → re-ring with the same stop method.

**08 Lost-code fallback (night).** Glass step bar: Wait 90 s ✓ · Type · Hold 3 s. Glass card: "Type this sentence" + the sentence + a text field (paste disabled). Note: "Paste is off. The alarm keeps ringing, quieter, until you finish." Disabled glass "Hold to turn off" (lock icon) until the sentence matches.

## Accessibility (the bar for every screen)

- Legible at both ends of the iOS 27 transparency slider, with Reduce Transparency and with Increase Contrast (add a 2 pt primary-colored border to capsules).
- Text contrast ≥ 4.5:1 on its own tint; big type ≥ 3:1.
- Reduce Motion: clouds and stars stop, ripple rings removed, NFC success becomes a crossfade.
