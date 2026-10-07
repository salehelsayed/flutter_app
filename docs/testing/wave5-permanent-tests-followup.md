# Wave 5 follow-up: permanent tests and the retirement proposal

## Terms

- **Permanent tests**: originals with no production replacement by design
  (groups 1 to 3 below). They stay in the suite and run alongside the
  production tests; they are not legacy and are never retired.
- **Pending replacement**: originals that could gain a production
  replacement with more work (group 4 below).
- **Retirable originals**: originals whose production replacement already
  passed on devices. Only these go into the step 5 retirement proposal.

Written 2026-10-07 at the end of Wave 5 step 4, for a later session.
Plan: [production-bootstrap-migration-plan.md](production-bootstrap-migration-plan.md).
Results: the crosswalk sections "2026-10-06 Wave 5 steps 1 to 3" and
"2026-10-07 Wave 5 step 4" in
[production-bootstrap-migration-crosswalk.md](production-bootstrap-migration-crosswalk.md).

## Where things stand

- Steps 1 to 3 (accounting, guard, build reuse) are done.
- Step 4 is done for the replacements: all 66 production capabilities pass
  on devices (one PASS receipt each, listed in the crosswalk).
- Host gate: Flutter fully green. 4 Go relay smoke tests fail on this Mac's
  corporate network only.
- Permanent tests and retirable originals were mostly **not run** in step 4
  (user choice).
- Step 5 (retirement proposal) has not started. Executing any retirement
  needs separate user approval.
- Pushed: `main` and `wave3-baseline-20260930` at `f92957e3c`.

## Recommendation

Do not rerun every original. Run the permanent tests, settle one
comparison, then write step 5.

1. **Run the permanent tests** (table below). They are the only coverage
   for their rules on the current candidate, and they belong in every
   regular run from now on.
2. **Investigate `ge004`, `ge005` and `ge007` on the original harness.**
   They failed there on 2026-10-06 while their production replacements pass.
   Either the old harness has decayed or it catches something the
   replacement misses. Settle this before proposing to retire that harness.
   - `ge007`: Alice timed out waiting for the shared signal
     `gmp_<run>_charlie_ge007_readded` (Charlie was never re-added).
   - `ge004`, `ge005`: role logs end with "end of failure 1"; not yet read.
   - The role logs were in the Mac's `$TMPDIR/group_multi_party_<case>_*`
     folders; rerun to get fresh ones.
   - 2026-10-07, Linux, three Android emulators: the old harness had decayed.
     Its out-of-band re-add hit the Plan 263 self-removal rule. With the
     harness fixed, GE-004 and GE-007 pass. GE-005 also passes (twice) after it
     stores the removal replay for Bob, as the app does for remaining members.
     Before that, Bob had no inbox recovery when a live removal missed him.
     Details: `TESTING.md`, "The original multi-party harness re-adds a member
     out of band".
3. **Skip repeat runs of the retirable originals** (the 51
   replaced catalog cases, the 15 replaced harnesses, the replaced lifecycle
   scenarios). Their replacements already passed on devices.
4. **Then write the step 5 retirement proposal**: each original route, its
   replacement, preserved assertions/platforms, comparison evidence, and the
   builds and runs it would save.

Expected device time for items 1 and 2: about 4 to 6 hours, mostly the
catalog cases.

## Permanent and pending-replacement tests

| Group | Count | What they cover | Devices |
|---|---|---|---|
| Non-portable catalog cases (original multi-party harness, SIMS capability `groups.multi_party_release`) | 58: 49 three-person, 9 four-person | Forged or injected traffic, never-member publish rejection, network chaos, key conflicts, multi-device re-add. Lists and reasons: crosswalk tables "catalog cases kept on the original harness" (2026-10-01 and 2026-10-04 sections) | 4 iOS simulators (A to D) for the 4-person cases, 3 for the rest |
| Native suites | 6 | `full.native.371`, `.373` (iOS native), `.374` (Android JVM), `.app-visibility`, `.pb266-release`, `.vc204` | 371/373: 1 iOS simulator; 374: none (Mac); others: Pixel 6 |
| macOS performance targets (`performance_harness.dart`) | 6 | `full.performance.feed_init`, `shell_switch`, `feed_orbit_offscreen`, `conversation`, `conversation_sub`, `orbit` | The Mac (desktop app) |
| Component benchmarks (`run_benchmark_suite.dart`) | 9 | Ack, bridge crossing, connection reuse, encryption, event queue, inbox, media, voice, timeout accuracy | 1 iOS simulator + the Go test peer on the Mac. **This route hangs** (idle parentless `flutter_tools test` processes, empty log); fix it first |
| Pending replacement: inventory scenarios | 4 | Lifecycle `ADMIN_METADATA`; invite `invite_send_latency`, `direct_linked_device_addressing`, `direct_linked_device_event_blob_fanout` | Invite: Pixel + 1 emulator; lifecycle: 1 device |
| Diagnostics harnesses | 2 | Reconnect isolation, relay recovery diagnostics | None: host lanes (passed in step 4) |
| No runner of their own | 2 | Inbox replay-before-ack custody, push payload persistence | Covered only through the harnesses that import them |
| Manual | 9 | APNs provider capture, 7 signed-release checks, Android notification recovery proof | People and signed builds; Pixel for the recovery proof (needs zero Mknoon notification cards first) |

Peak need at once: 4 iOS simulators, the Pixel 6 and 1 emulator.

The 9 four-person non-portable cases: `private_readd_active_members`,
`private_readd_alternating_churn`, `private_admin_demotion_enforcement`,
`regression_group_admin_permissions_and_message_reliability_four_users`,
`private_concurrent_admin_membership_edits`,
`scenario7_group_invite_stale_metadata_recovery`,
`private_never_member_publish_rejected`, `private_network_chaos_invariants`,
`private_same_user_multi_device_readd`.

## Why the permanent tests have no production replacement

Decisions: crosswalk "2026-10-01 Wave 3 catalog cases kept on the original
harness" and "2026-10-05 Wave 4 batch 1: classification".

1. **The test needs input the real app cannot produce** (58 catalog cases).
   A production journey only causes what the app itself causes. These need
   forged or repeated protocol messages (`gm009` republishes a removal,
   `gm010` a duplicate members-added, `never_member_publish_rejected` a
   non-member publish, `readd_current` forged keys and a duplicate removal),
   app behaviour that does not exist (rotate-on-add is an off-by-default
   flag; non-contact invitations are dropped; a second device of the same
   account), test-chosen delivery orders or fixed-seed network chaos, or
   oracle details the app does differently (PNG group photo expected, JPEG
   uploaded). Faking them would be no stronger than the original.
2. **The isolation is what is measured** (component benchmarks, macOS
   performance, diagnostics). Encryption, bridge, timer, frame-cost and
   reconnect-isolation numbers would be blurred by the rest of the app;
   Wave 4 classified them "retain: the isolation is the claim".
3. **They test native code, not app journeys** (native 371, 373, 374,
   app-visibility, pb266, vc204). The migration replaced harnesses that
   rebuilt the Flutter app graph; native suites were never in scope.
4. **Not built yet, or not automatable.** Lifecycle `ADMIN_METADATA` and
   the three invite scenarios (send latency, linked-device addressing,
   blob fan-out) are candidates for new replacements; the linked-device
   ones need a second device of the same account. Manual items need
   people, signed builds or the Apple push service.

Groups 1 to 3 are the permanent tests. Group 4 is pending replacement.

## How to run

All device work runs in the worktree `.claude/worktrees/wave3-next` (clean,
at `f92957e3c`). Use host git only; container git hangs on this disk.

- **Catalog cases.** The SIMS adapter `run_group_multi_party_sims.dart`
  accepts only `--scenario smoke` or `all` (all = 109 cases, 8 to 12 hours).
  For selected cases, call
  `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario <id> -d <simA>,<simB>,<simC>[,<simD>]`.
  A direct run uses Flutter's normal simulator build output, so build the
  harness for the simulator first. Set `MKNOON_RELAY_ADDRESSES` to exactly
  the string `expectedMultiPartyRelayAddresses` in
  `integration_test/scripts/group_multi_party_device_criteria.dart`
  (`/dns/...`, not `/dns4/...`).
- **Full-plan device checks** (native, performance, media):
  `docker-ws/beta/wave5/devices_run.sh "<check,check>" <config> <label>`
  (detached; output under the worktree's
  `.codex-test-logs/production-bootstrap-migration-20260930/wave5-<label>-*`).
  It runs one check at a time by default.
- **Per-capability campaigns**: `docker-ws/beta/wave5/run_queue.sh` with
  `docker-ws/beta/wave5/queue_args.txt`, watched by
  `docker-ws/beta/wave3/watchdog.sh <queue log> 0`.
- **Device configs** (git-ignored, in the worktree's
  `.codex-test-logs/production-bootstrap-migration-20260930/`):
  - `wave5-full-device-config.json`: full-run roles (`ios_simulator` = A,
    `_b`, `_c`; Pixel; emulator-5554/5556; iPhone 11; macos).
  - `wave3-device-config-ios.json`: per-capability iOS checks
    (`ios_simulator_a` to `_c`).
  - `wave5-legacy-device-config.json` (file name only): original routes run
    through the tool's "legacy target contracts" (no third emulator).
- **Devices**: `docker-ws/beta/wave5/boot_sims.sh` boots simulators A to D;
  `start_avds.sh` / `restart_emus.sh` start emulators. All were closed at the
  end of step 4.

## Landmines met in step 4 (check these first)

- The full runner starts device checks only after every host check passes,
  and one failed device check stops every later device check in that run.
  Split runs with `--only`.
- Config roles: never list both `ios_simulator` and `ios_simulator_a`;
  per-capability iOS checks need `ios_simulator_a`; the tool's legacy target
  contracts (`scripts/legacy_target_contracts.py`) reject
  `android_emulator_third`; every listed device must be up, or the run is
  BLOCKED as "target unavailable".
- Orphaned `flutter build ios` helpers stall SIMS after iOS builds; clear
  them every minute with `docker-ws/beta/r78_kill_build_orphans.sh`.
- A stopped run leaves `dev.mobile.maestro` on the Pixel; the next preflight
  reports "device_automation_busy". Force-stop it
  (`docker-ws/beta/wave5/stop_maestro_driver.sh <serial>`).
- Emulators can lose DNS (`ping mknoun.xyz` fails); cold restart fixes it.
  macOS throttles an emulator whose screen is off; keep screens on
  (`docker-ws/beta/wave5/emu_awake.sh`).
- Do not run `flutter` on the same SDK during a device run: its startup lock
  stalls the run.
- Xcode rewrites the tracked root `info.plist`; restore it before a run that
  requires a clean tree.
- Tool caches (Flutter artifacts, Xcode DeviceSupport, Go module cache) are
  symlinked into folders on the external drive. Scan for links before
  deleting anything there; Flutter artifacts now live in
  `/Volumes/CrucialX9/mac-development/flutter-3.47.2-engine-artifacts`.
- iOS XCTest on the iPhone 11 needs the phone unlocked once per boot
  ("enabling automation mode").
- This Mac's network blocks QUIC and raw TCP to the relay; WSS works.
