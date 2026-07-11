# 248 — Signal True Light Theme: Pixel 6 Visual Acceptance (TC-248-26 / TC-248-27)

Status: exploratory partial captures only — `0/23` formal states accepted.

The three images below confirm a few theme-critical renders on the physical
Pixel 6 and Android emulator, but they do not satisfy TC-248-26/27. The formal
checklist remains open until every required state is captured and reviewed at
both font scales with reproducible production-selection and cold-restore
provenance. Host contrast coverage supplements this review; it does not replace
the missing device states.

## Captured results (this run)

Physical Pixel 6 `21071FDF600CSC` (`com.mknoon.egressproof` exploratory build):
- `P10-signal-orbit-1.0.png` — exploratory Signal Orbit capture only. It also
  contains an unredacted QR identifier, so it is not admissible formal evidence.
- `P11-signal-orbit-1.3.png` — despite the filename, this is a scanner
  permission-denied screen, not an Orbit scale-1.3 capture.
- `P12-signal-scanner.png` — this is the Android camera-permission prompt, not
  the required live-scanner state.

Android emulator `emulator-5554` (see `emulator/`):
- Exploratory Signal Orbit @ scale 1.0 and 1.3 (warm, coherent, no dark island), scanner
  black under Signal, dark Default preset preserved.

Method note: Settings→Signal isn't reachable by blind adb taps on the empty-circle
first-run Orbit (that entry lives on the *populated* Orbit), so the light theme
was forced via a temporary `BackgroundPreference.fromStorageString` fallback →
Signal, then **reverted** (verified pristine) and a clean build reinstalled.
font_scale restored to 1.0 on both devices.

---


## Device / build

- Device: Pixel 6 `21071FDF600CSC`, Android 16 / API 36, 1080x2400.
- App/build provenance: the captured Pixel state came from the
  `com.mknoon.egressproof` exploratory variant described above; a clean
  production `com.mknoon.app` selection/restore run is not yet recorded.
- Base commit at implementation: `38c10f62d` (+ uncommitted 248 changes).
- Selection/restore: not formally proven by these captures. The temporary
  fallback method was reverted; repeat through production Settings and record a
  force-stop/launcher cold restore before acceptance.

## How this is graded

Host causal gates (TC-248-01..25, 28, 29) own the deterministic contrast /
lifecycle / literal coverage and all pass. This artifact is the **required UX
acceptance layer on top of them**: a reviewer confirms each state reads warm and
dimensional with no light/dark island, at font scale 1.0 and 1.3. It is never a
substitute for a failed automated gate.

Only the OS-owned camera-permission prompt may be `N/A`, and only with a recorded
`android.permission.CAMERA: granted=true` dumpsys line. Any other omission blocks
acceptance. The recovery phrase is never revealed; contact / QR identifiers are
redacted.

## Required PASS states (both scales)

| # | State | scale 1.0 | scale 1.3 | Result | Notes |
|---|---|---|---|---|---|
| 01 | Signal Settings | `01-settings-scale-1.0.png` | `01-settings-scale-1.3.png` | ⬜ | |
| 02 | Orbit | | | ⬜ | |
| 03 | All Chats (loaded rows) | | | ⬜ | |
| 04 | Intros | | | ⬜ | |
| 05 | Archived | | | ⬜ | |
| 06 | Conversation (loaded bubbles) | | | ⬜ | |
| 07 | Empty conversation | | | ⬜ | |
| 08 | Conversation overflow popup | | | ⬜ | |
| 09 | Attachment sheet | | | ⬜ | Cancel keeps draft |
| 10 | Contact Profile (pushed) | | | ⬜ | redact peer/QR |
| 11 | Create menu | | | ⬜ | |
| 12 | New-group picker | | | ⬜ | |
| 13 | Chat search | | | ⬜ | |
| 14 | Orbit find | | | ⬜ | placeholder AA |
| 15 | Loaded Feed | | | ⬜ | |
| 16 | Focused Feed composer | | | ⬜ | |
| 17 | Redacted My QR | | | ⬜ | redact QR |
| 18 | Live scanner | | | ⬜ | stays black/white |
| 19 | Photo-quality sheet | | | ⬜ | |
| 20 | Move Account | | | ⬜ | |
| 21 | Introduction picker | | | ⬜ | |
| 22 | Selected background chooser | | | ⬜ | |
| 23 | Lower Settings diagnostics | | | ⬜ | debug cards readable |

Camera prompt row: `N/A` only with recorded `granted=true`; otherwise Scanner
must show + capture the prompt as PASS.

## Font-scale restore

`adb -s 21071FDF600CSC shell settings put system font_scale 1.0` must be the final
state (verified via `settings get system font_scale`), protected by a shell
`trap ... EXIT`.

## Reviewer sign-off

- scale 1.0: ⬜ all states PASS, no pure-white canvas, clear surface hierarchy,
  coherent routes/sheets, readable controls, scanner dark.
- scale 1.3: ⬜ every safe state unclipped / no overlap / no hidden action / no
  contrast regression.
- Compared against `artifacts/signal-theme-ui-audit-2026-07-09`.
