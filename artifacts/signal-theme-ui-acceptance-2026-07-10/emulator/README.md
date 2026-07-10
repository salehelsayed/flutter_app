# 248 Signal light theme — Android emulator visual evidence (2026-07-10)

The USB Pixel 6 was in use, so the on-device visual pass was run on the running
Android emulator `emulator-5554` (Pixel-class AVD, 1080x2400). The emulator has
no real contacts/chats, so loaded-row/loaded-bubble states could not be shown;
this is supplementary evidence on top of the deterministic host gates (all 27
automated TC rows green), not the formal Pixel-6 24-state acceptance.

## Method

`flutter build apk --debug` (built clean — the concurrent session's native edits
did not break it) → `adb install -r`. Identity created via onboarding. To exercise
the **light** theme without the (hard-to-reach-by-blind-tap) Settings→Signal
navigation, the `BackgroundPreference.fromStorageString` null/unknown fallback was
**temporarily** pointed at `daylightLagoon` so a fresh launch renders Signal;
this one-line change was **reverted** immediately after capture (verified pristine
vs git) and a clean APK reinstalled.

## Captured states

| File | State | Result |
|---|---|---|
| `04-onboarding.png` | First-run onboarding (pre-identity, always dark) | dark, correct |
| `06-orbit-dark.png` | Orbit / identity, **Default** background | dark, correct (dark preset preserved) |
| `11-signal-orbit-1.0.png` | Orbit / identity under **Signal**, scale 1.0 | **PASS** — warm mineral ground (not white, not dark), warm-charcoal text, raised "Scan" card with soft violet `surfaceBorder`, green `#236143` "Online" pill, dark status-bar icons. No dark island. |
| `12-signal-scanner.png` | Scanner opened under Signal light root | **PASS (TC-248-24)** — scanner stays **black with white camera chrome**; only the OS camera-permission prompt overlays (the allowed single exception) |
| `13-signal-orbit-1.3.png` | Orbit under Signal, **font scale 1.3** | **PASS (TC-248-27 spot)** — warm ground preserved, text scales cleanly (subtitle wraps to 2 lines), card + border stay readable, no contrast regression |

font_scale restored to 1.0 after capture.

## Verdict

On-device the Signal true-light theme renders as intended — one coherent, warm,
dimensional light appearance with no dark Material islands — and the deliberate
dark scanner exception is preserved under the light root. The full formal
acceptance (loaded chats/bubbles, all 24 states, Settings-driven selection) still
wants the Pixel 6 with real data per `../README.md`.
