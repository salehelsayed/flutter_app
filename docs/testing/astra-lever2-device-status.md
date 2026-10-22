# Astra lever 2: device status (2026-10-22)

Owner decision 2026-10-22: option (a). All 32 MEDIA routes of the lever 2 media content oracle runbook (`docs/testing/astra-lever2-media-native-runbook.md`) are recorded as **NOT RUN: SOURCE_CAPTURE_NOT_WIRED**.

## Reason

The oracle's sender-side capture (`MediaOracleGoBridgeClient` wrapping `GoBridgeClient.send` at blob encrypt) cannot be wired into the shipping app with test-only code:

- `lib/app/bootstrap/production_application_bootstrap.dart:5338` builds the bridge directly (`bridge = GoBridgeClient();`) with no factory or override.
- The same file builds it directly at `:191` (canonical inbox projection composition) and `:837` (headless call admission).
- `lib/debug/debug_e2e_composition_root.dart` only receives the bridge and has no hook to wrap it. The voice E2E named by the runbook lives in `lib/core/debug` (app code).

Wiring these routes would need a debug-only bridge seam in `lib/` (not approved). The group multi-device harness (`integration_test/group_multi_device_real_harness.dart`) builds its bridge in test code and could take the oracle for GX-003, GC-006, GC-010, MEDIA-036 and MEDIA-037, but the runbook's video, PDF and voice witnesses are missing there too. No harness work was done.

## Routes

DC-008, DC-018, DC-021, MEDIA-001 to 008, MEDIA-010, MEDIA-011, MEDIA-014 to 018, MEDIA-020, MEDIA-021, MEDIA-023, MEDIA-024, MEDIA-027 to 030, MEDIA-033 (real app UI), and GX-003, GC-006, GC-010, MEDIA-036, MEDIA-037 (group harness): NOT RUN, SOURCE_CAPTURE_NOT_WIRED.
