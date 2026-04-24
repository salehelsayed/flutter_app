# Notification Sound Smoke Test (Two-Simulator)

## Context

**Problem.** Users receive notifications with a visible badge when a 1:1 or group message arrives, but it is unclear whether an **audible sound** is also produced. The user reports sound "was working earlier" but may have regressed. This plan delivers a repeatable smoke test, run across two simulators, that either **proves sound works** or **proves it doesn't** so root-cause investigation can proceed with facts.

**Why this matters now.** Two recent commits plausibly touched sound delivery:
- `0a38bdb` "notification fixed" (Apr 4 2026) — reworked `FlutterNotificationService` initialization and tap dismissal.
- `2e4488e` "ios notification fixed" (Mar 23 2026) — reworked `AppDelegate.swift` and `Info.plist` background modes.

Either change could have silently broken sound while badges continue to display.

**Scope.** Three notification entry points must be covered:
1. **1:1 direct chat** — P2P message from Alice → Bob.
2. **Group discussion** — `GroupType.chat` message from Alice → Bob in a group.
3. **Group announcement** — `GroupType.announcement` message from Alice (admin) → Bob (member).

**What the test will tell us.**
1. Whether the code paths that *should* produce sound are reached (programmatic FLOW-event assertions).
2. Whether the OS then plays audible sound at the speaker (human observation per a printed checklist, per scenario).

## Findings from exploration

### Sound is enabled at the code level — nothing is suppressing it by configuration
- `lib/core/notifications/local_notification_support.dart:19-27` — `mknoonMessagesNotificationDetails` sets Android `playSound: true` + `importance: Importance.high` + `priority: Priority.high`, and iOS `presentSound: true, presentAlert: true, presentBadge: true`. **This same constant is used by both 1:1 and group notifications** — so sound is configured identically across all three scenarios.
- `lib/core/notifications/flutter_notification_service.dart:28-32` — `DarwinInitializationSettings` requests sound/badge/alert permissions (defaults to true).
- `lib/features/push/application/request_push_permission_use_case.dart:17-20` — requests Firebase `alert/badge/sound` permissions at startup.

### Runtime paths that can still silence a notification
- `lib/features/push/application/show_notification_use_case.dart:72-84` — SUPPRESS if `AppLifecycleState.resumed` AND the user is on the sender's conversation screen. Same gate is used for 1:1 *and* group (via the respective `ActiveConversationTracker`).
- `show_notification_use_case.dart:86-110` — SUPPRESS if backgrounded AND a recent Firebase remote-push announcement already fired for the same payload.
- `lib/features/groups/application/group_message_listener.dart:249-276` — SUPPRESS if `group.isMuted`. (Test must use a non-muted group.)
- `lib/core/notifications/flutter_notification_service.dart:9,17` — if a caller constructs `FlutterNotificationService(requestApplePermissions: false)` and the user never granted permission, the OS drops sound silently.

### Group notification path is structurally identical to 1:1
- `group_message_listener.dart:255-275` calls the same `maybeShowNotification` function used by `chat_message_listener.dart`, with the same `mknoonMessagesNotificationDetails`. The only differences:
  - `contactPeerId: 'group:$groupId'` (prefix namespace).
  - `senderUsername` is the **group name**, `messageText` is `"$senderUsername: $body"`.
  - Early-exits when `group.isMuted`.
- Implication: **the same sound config applies** to both group discussions and announcements. The smoke test's job is to prove each entry point actually reaches this code, not to test three different sound configurations.

### Group types
- `lib/features/groups/domain/models/group_model.dart:2-23` — `enum GroupType { chat, announcement, qa }`. "Discussion" in the user's language = `GroupType.chat`. `GroupType.announcement` exists as a separate type; the notification path is identical but the group's posting rules differ (admin-only write). A QA type also exists but is out of scope for this test.

### Test infrastructure already in place (reuse, don't rebuild)
- `integration_test/routing_smoke_alice_harness.dart` + `routing_smoke_bob_harness.dart` — two-user 1:1 harness: identity gen, contact exchange, send, receive, FLOW log capture via `debugPrint`, file-based signal coordination under `/tmp/smoke_<runId>_*.json`.
- `integration_test/group_smoke_alice_harness.dart` + `group_smoke_bob_harness.dart` — two-user group harness: uses `setupGroupMultiDeviceStack`, `createGroupWithMembers(type: GroupType.chat, ...)`, `sendGroupMessage`; currently hard-codes `GroupType.chat` but the `type` parameter is the only change needed for announcement.
- `integration_test/scripts/run_routing_smoke_e2e.dart` — orchestrator pattern: launch both harnesses via `flutter drive` in parallel with `--dart-define` flags, wait for signal files, tear down.

### FLOW events the test will assert (already instrumented)
- `NOTIFICATION_SERVICE_INITIALIZED` (`flutter_notification_service.dart:48`)
- `NOTIFICATION_SHOWN` (`flutter_notification_service.dart:137, 167`)
- `NOTIFICATION_SUPPRESSED` (negative assertion — `show_notification_use_case.dart:57, 75, 100`)
- `GROUP_MESSAGE_LISTENER_ERROR` (negative — `group_message_listener.dart:291`)

## Plan

### Scope confirmed with user
- **Receiver state**: backgrounded (with a foreground fallback — see iOS caveat below).
- **Verification**: programmatic FLOW-event assertions + printed manual-audio checklist per scenario.
- **Platforms**: iOS simulator (primary); Android emulator if available.
- **Scenarios**: four total — 1:1 direct, group discussion, group announcement, plus a suppression control.

### iOS background caveat and test strategy

On iOS, a fully backgrounded Flutter app stops running Dart. The P2P libp2p listener does not process an incoming message until the app resumes — so a pure "lock Bob's app in the background and send" cannot deterministically verify the local-notification path through libp2p alone. To keep the test deterministic *and* honor the user's "backgrounded" preference, the plan runs two sub-states per scenario:

- **State F — Foreground, off-conversation (automated, primary gate).** Bob is on a neutral staging screen (not on the sender's conversation). Alice sends. `maybeShowNotification` hits the `presentSound: true` foreground path. iOS simulator plays the banner sound. This is the deterministic, repeatable signal.
- **State B — Backgrounded (semi-manual, confirmation).** Orchestrator pushes Bob's simulator app to background via `xcrun simctl launch booted com.apple.mobilesafari` *just before* Alice sends; after a delay the orchestrator brings Bob forward via `xcrun simctl launch booted <bob-bundle-id>`. Dart resumes, the listener fires, notification presents briefly. Operator confirms audible + visible banner. If this proves flaky across runs, the test still has State F as the authoritative gate — State B is advisory.

### Scenarios

Each scenario runs in both State F and State B. Operator confirms audio per state; programmatic FLOW assertions run in both.

| ID | Scenario | Entry point | Group type | Expected |
|----|----------|-------------|------------|----------|
| S1 | 1:1 direct | `chat_message_listener.dart` | n/a | `NOTIFICATION_SHOWN`, sound + banner |
| S2 | Group discussion | `group_message_listener.dart` | `chat` | `NOTIFICATION_SHOWN`, sound + banner |
| S3 | Group announcement | `group_message_listener.dart` | `announcement` | `NOTIFICATION_SHOWN`, sound + banner |
| S4 | Suppression control | 1:1 while Bob is on Alice's conversation | n/a | `NOTIFICATION_SUPPRESSED` (silent — proves gate works) |

S4 is included so a failing test cannot be dismissed as "permissions are off for everything" — if S1–S3 all report silence but S4 reports `NOTIFICATION_SUPPRESSED`, the suppression gate is working and the other failures are real.

### Files to create

1. **`integration_test/notification_sound_smoke_bob_harness.dart`** (receiver, new)
   - Model after `routing_smoke_bob_harness.dart` and `group_smoke_bob_harness.dart`. Key points:
     - Wire the **real** `FlutterNotificationService` into the DI chain (same pattern as `lib/main.dart`). Verify `NOTIFICATION_SERVICE_INITIALIZED` fires before signaling `bob_ready`.
     - After identity + contact-exchange + group-join phases, stay on a neutral **staging screen** (simple `Scaffold` with text "Staging — awaiting messages"). **Do NOT** open the 1:1 or group conversation screens — otherwise `isViewingConversation` suppresses notifications in scenarios S1–S3.
     - Capture `debugPrint` FLOW events into an in-memory list (pattern: `routing_smoke_bob_harness.dart:217-240`).
     - On each incoming message, append a record to `/tmp/smoke_<runId>_bob_notification_<seq>.json` containing: scenario id (S1/S2/S3/S4), all FLOW events since the previous signal, current `AppLifecycleState`, and a pass/fail verdict (`NOTIFICATION_SHOWN` present; `NOTIFICATION_SUPPRESSED` absent for S1–S3 / present for S4).
   - Reuses: `emitFlowEvent`, identity generation via `bridge.send({cmd: 'identity.generate'})`, `sendChatMessage` for the S4 send, `setupGroupMultiDeviceStack` for S2/S3.

2. **`integration_test/notification_sound_smoke_alice_harness.dart`** (sender, new)
   - Thin orchestrator that composes the 1:1 sender logic (from `routing_smoke_alice_harness.dart`) and the group sender logic (from `group_smoke_alice_harness.dart`).
   - Sequence (waits on signal files between steps):
     - S1: send 1:1 message `"S1: direct"`.
     - S2: create group with `type: GroupType.chat` named `"Smoke Discussion"`; wait for Bob to join; send `"S2: discussion"`.
     - S3: create group with `type: GroupType.announcement` named `"Smoke Announcement"`; wait for Bob to join; send `"S3: announcement"` (Alice is admin by virtue of creation).
     - S4: instruct Bob (via signal file `open_alice_conversation`) to navigate to Alice's 1:1 conversation; then send `"S4: suppressed"` once Bob acknowledges.

3. **`integration_test/scripts/run_notification_sound_smoke.dart`** (orchestrator, new)
   - Model after `integration_test/scripts/run_routing_smoke_e2e.dart`.
   - Flow:
     1. Discover two iOS simulators via `flutter devices --machine`. Fail fast if fewer than two are booted.
     2. Launch Alice + Bob in parallel via `flutter drive`, each with `--dart-define=SMOKE_RUN_ID=<uuid>` + `--dart-define=E2E_DB_NAME=...`.
     3. Wait for Bob's `bob_ready` signal; verify `NOTIFICATION_SERVICE_INITIALIZED` appears in Bob's FLOW log capture.
     4. Print the **manual audio checklist** (below). Wait for operator to press Enter (confirms operator is actively listening to Bob's simulator speaker).
     5. For each scenario S1–S4:
        - **State F pass**: signal Alice to send; poll Bob's signal file; assert programmatic verdict; ask operator "did you hear sound?" (y/n).
        - **State B pass**: invoke `xcrun simctl launch booted com.apple.mobilesafari` on Bob's device to push the app to background; signal Alice to send; wait ~5 s; invoke `xcrun simctl launch booted <bob-bundle-id>` to bring Bob forward; poll signal; assert; ask operator.
     6. Write a final `notification_sound_smoke_summary_<runId>.json` under `/tmp/` with per-scenario (programmatic, audible) verdicts and a consolidated pass/fail.

### Files to modify

None. Do **not** alter `flutter_notification_service.dart`, `local_notification_support.dart`, `show_notification_use_case.dart`, or `group_message_listener.dart` as part of this test work. If the test reveals a regression, that fix is a separate task.

### Manual audio checklist (printed by the orchestrator before runs)

```
=== Notification Sound Smoke — Manual Audio Checklist ===
Before proceeding, confirm on Bob's simulator:
  [ ] Simulator menu > I/O > Audio Output > your Mac's speakers
  [ ] macOS host volume > 50% and NOT muted
  [ ] Simulator Settings > Focus / Do Not Disturb = OFF
  [ ] Settings > <app> > Notifications > Sounds = ON
  [ ] Settings > <app> > Notifications > Allow Notifications = ON

Press Enter to run scenario S1 (1:1 direct chat, State F — foreground)...
```

After each scenario+state pair:

```
=== S2 / State F result ===
Programmatic: PASS (NOTIFICATION_SHOWN emitted for 'group:<groupId>'; no NOTIFICATION_SUPPRESSED)
Audio: Did you hear a notification sound on Bob's simulator? (y/n):
```

The operator's y/n answer is recorded to the summary log, so the final verdict combines programmatic + audible facts per scenario per state.

## Verification

How to prove the smoke test itself works end-to-end:

1. **Boot two simulators.** `xcrun simctl list devices | grep Booted` should list at least two iPhone simulators. If not: `xcrun simctl boot "iPhone 15"` + `xcrun simctl boot "iPhone 15 Pro"`.
2. **Ensure Go bindings are fresh** (per project memory): `cd go-mknoon && PATH="$PATH:$(go env GOPATH)/bin" make all && cd ../ios && pod install`.
3. **Run the smoke.** `dart run integration_test/scripts/run_notification_sound_smoke.dart`.
4. **Expected outcomes.**
   - **Healthy**: S1–S3 report programmatic PASS + operator hears sound in both State F and State B; S4 reports programmatic `NOTIFICATION_SUPPRESSED` (silent as designed).
   - **Code regression**: S1–S3 report programmatic FAIL (either no `NOTIFICATION_SHOWN`, or an unexpected `NOTIFICATION_SUPPRESSED`) → root cause is in the Dart notification path. Inspect Bob's `/tmp/smoke_<runId>_bob_notification_<seq>.json` FLOW events to identify which gate fired or why `showMessageNotification` was not reached.
   - **OS/permission regression**: S1–S3 programmatic PASS but operator reports no audio → root cause is at the OS/permission/simulator-audio layer, not the app code. Remediation in `AppDelegate.swift`, `Info.plist`, or iOS permission prompt.
   - **Group-specific regression**: S1 PASS but S2/S3 FAIL → regression is in `group_message_listener.dart` or `ActiveConversationTracker` for groups.
5. **Regression-gate candidate.** Once stable, add the script to `scripts/run_test_gates.sh` behind an opt-in flag (requires two simulators + operator).

## Out of scope

- Fixing the notification feature if the test reveals a bug (separate follow-up task, triaged from the smoke's summary JSON).
- Android emulator automation of background/foreground toggling (manual for now).
- Firebase remote-push path (`background_message_handler.dart`) — covered by a different plan (see `Test-Flight-Improv/53-notification-background-delivery-reliability-plan.md`).
- `GroupType.qa` — not in user's stated scope.
