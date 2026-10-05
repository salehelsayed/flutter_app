# Handover: Wave 4 production measurements (2026-10-05)

Branch `wave3-baseline-20260930` (also `main`, see "Git state"). Results and
classification: crosswalk sections "2026-10-05 Wave 4 batch 1" and
"2026-10-05 Wave 4 device results" in
`docs/testing/production-bootstrap-migration-crosswalk.md`.

## Status: Wave 4 device work complete

All 26 Wave 4 harnesses have a disposition:
- 3 already covered by `production.startup_resume_performance` (B, M, BR);
- 6 new or extended production measurements, each device-proven (run PASS,
  negative probe FAIL at the intended step):
  `production.startup_resume_performance` + C-Sim-2,
  `production.transport_census`, `production.message_latency` (A, R, GP),
  `production.notification_tap_latency` (N);
- 15 retained as component evidence (6 reclassified from the baseline, with
  source reasons), 2 dispatchers retained;
- the shared-XCTest adapter has a real caller, `production.shared_xctest`,
  PASS on the iPhone 11.

## Decisions taken (user, 2026-10-05)

1. **Notification regression fixed.** The notification-lock work of
   `329ff3140` was reverted on main as one unit (`f59db25a8`); afterwards
   `production.notification_open` and `production.notification_tap_latency`
   PASS on `6e2d74816`.
2. **Original A and R benchmarks fixed** (`6e2d74816`): every send carries
   the recipient ML-KEM key. Analysis-verified; the simulator benchmark
   route hangs before its `flutter test` starts (see the crosswalk), so the
   fixed originals were not executed.

## Still open

- The `run_benchmark_suite.dart` simulator route hangs in this environment
  (idle parentless `flutter_tools test` processes; nothing installed). The
  Go test peer also needs the WSS relay address when the Mac blocks UDP.
- The iPhone 11's Appium WebDriverAgent (another session's) was stopped for
  the XCTest batch; that session must restart it.
- Not done: a forced-relay census condition; R-Sim-6 and R-Sim-8 recorded
  as not reproduced.
- **Host-all on `6e2d74816` (2026-10-05):** Flutter 18,997 passed, 7 failed.
  Fixed: the TC-342-07 `sendChatMessage` caller census (the two new Wave 4
  controls are now classified `generatedIdFresh`) and the wake-token binary
  check (the worktree lacked the git-ignored macOS Go xcframework). Left for
  the user / the other session: 5 failures caused by `caff0f087` ("fix(inbox):
  retry stuck messages in the background instead of a banner"), which changed
  frozen files without re-pinning: 3 DTR-18 digest pins
  (`production_application_bootstrap.dart`, `application_root.dart`), the
  TC-294-09 Wired API freeze, and the received-media transport call-site
  count (24 to 23, it removed a `p2pService` reference from
  `conversation_wired.dart`). Re-pinning DTR-18 needs the user's approval.

## How to run

- Device runs use the worktree `.claude/worktrees/wave3-next`; code is
  edited and committed in the main checkout (host git only: container git
  hangs on the shared disk), then `wt_next.sh rebase`.
- Queue: `docker-ws/beta/wave3/queue.sh` with `QPREFIX=production-`,
  `QPROOF=production.`, `QCONFIG=<worktree>/.codex-test-logs/production-bootstrap-migration-20260930/wave4-device-config.json`
  (Pixel 6 + emulator-5554) or `wave4-device-config-ios.json` (iPhone 11),
  `QAVDS=7` (or `none`). Quiet wait is 1 minute.
- Always run `docker-ws/beta/wave3/watchdog.sh <queue log> 0` beside a queue
  (`STALL_S=1800` for a first iOS device build).
- New capabilities: `docker-ws/beta/wave4/register_capability.py <spec>`
  (specs in `docker-ws/beta/wave4/specs/`).
- The iOS device build needs the signing attestation
  (`docker-ws/beta/wave4/mint_signing_attestation.sh <udid> <out>`; output in
  the git-ignored `docker-ws/beta/wave4/private/`), exported by
  `docker-ws/beta/wt_campaign.sh`.
- `docker-ws/beta/main_check.sh <files...>` formats, analyzes and tests only
  the named files (other sessions edit the main checkout).

## Landmines met

- Measurements run alone on the Mac: no builds or test runs beside them.
- A relay can drop and recover within one host poll: watch the production
  state stream, not snapshots, for short outages.
- SIMS rejects evidence whose validator IDs differ from the manifest's single
  `artifactValidator`.
- A test-only xcodebuild inside SIMS must set `SIMS_CHILD_BUILDS_FORBIDDEN=1`.
- Stopping a queue mid-probe leaves the probe edit: restore it with
  `probe_apply.py restore` and compare with the `.orig` file.
- A same-peer notification tap emits no tap-to-message timing (the screen is
  already open).
