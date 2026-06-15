# 120 — Harden the 118 Notification Regression Net: Wiring Locks, Test Isolation, 2-Party Simulation & Cross-Boundary Contract (TDD Plan)

Status: execution-ready
Date: 2026-06-13
Branch: 121-improvements
Source findings: post-implementation coverage audit of doc 118 (`118-direct-message-notifications-calm-ux-tdd-plan.md`, IMPLEMENTED 2026-06-13). The 118 behavioral logic is well-guarded by red-first unit tests, but five places can silently re-break the live-direct-notification + calm-policy behavior **without any test going red**. Re-verified in source this session by a 5-agent graph-first recon (one agent per gap), all anchors current on `121-improvements`.
Related plans (do NOT duplicate): `118-direct-message-notifications-calm-ux-tdd-plan.md` (the behavior these tests protect — its closure log lists the production changes), `106-…notification-suppression-routing-plan.md` (group FCM/membership suppression — a different surface).

---

## Problem statement

Doc 118 fixed "live direct (1:1) messages never notify" and added a calm policy (silent channel + 30s per-conversation tone debounce + live-wins FCM dedup). Its red-first unit tests strongly guard the **behavioral logic** (the `maybeShowNotification` gate, the `P2PServiceImpl` routing, the tone-tracker math, the silent variant + notification-id parity). But a coverage audit found **five guard gaps** where a future code change re-breaks 118 with the suite still green — and the 118 bug itself was exactly this class of failure (a wiring constant set to `suppressNotification: true`).

- **G1 — `main.dart` wiring is not regression-tested.** The three replay closures in `main()` (`main.dart:1665-1685`) each just hardcode a `suppressNotification` boolean and forward to `replayInboxChatMessage` (`main.dart:1616-1654`). The 118 bug *was* the recovery-vs-live boolean. All 118 tests inject their **own** spy/test closures into `P2PServiceImpl`; `replayLiveDirectChatMessage` appears only in `p2p_service_impl_test.dart` and `live_direct_notification_integration_test.dart`, **never the real `main.dart` closure**. Flip the production constant to `true` → every test still passes. (118 §"dropped Phase 0" deliberately rejected extracting these as "testing-the-mock" — this plan resolves that tension; see G1.)
- **G2 — the notification/group suites are flaky under parallel `flutter test`.** Tests that don't inject a unique-temp gate race on the shared module-global `recentRemoteNotificationGate` (and `recentBackgroundNotificationGate`), whose default file paths are **fixed** (`recent_remote_notification_gate.dart:33-35`, `recent_background_notification_gate.dart:32-34`). `debugReset*` re-news with the **same** fixed path and never deletes the on-disk file, so it is not isolation. ~100 of 103 `GroupMessageListener` constructions in the group suite omit the gate and hit the global. The suites only pass deterministically at `-j 1`. A flaky guard is a weak guard: a real regression gets dismissed as "known flaky."
- **G3 — no automated multi-party / transport-aware simulation.** Nothing proves that a live 1:1 message over **relay** takes the live-direct (notify) path vs LAN vs the FCM-handoff, across `resumed`/`backgrounded`/`viewing` lifecycle. That path selection is the actual bug surface and is currently proven **only by a manual device run**. There is no 1:1 analogue of `GroupTestUser`; `FakeP2PService` is a `P2PService` stub, not the real `P2PServiceImpl`, so it never exercises the staging/confirm/route logic.
- **G4 — listener call-site wiring is not directly asserted.** That `chat_message_listener.dart:571` passes `toneTracker:` and `:582-588` passes the `markRecentRemoteNotificationAnnouncement:` closure into `maybeShowNotification` (and that `group_message_listener.dart:941` passes `toneTracker:` while staying mark-free) is exercised only by the integration test's **own** closures. Neither unit test injects a `NotificationToneTracker`; no test references `.silent`. Delete `toneTracker:` from a call site → the debounce silently stops, zero tests fail.
- **G5 — the Go→Dart `confirmNonce` contract is unguarded.** 118 only exists because Go attaches `"confirmNonce"` to an incoming direct `chat_message` when `EnableDeferredDirectAck` is true (default `true`, `feature_flags.go:42`; attach at `node.go:1616-1620`). The wire-key string, the `message:received` event name, the `type=="chat_message"` gate, and the default-true flag are string/format coupling with **no shared schema and no `DisallowUnknownFields`**. Every Dart test **fabricates** `confirmNonce`; none consumes a real Go payload. If Go drops/renames the key or flips the default, Dart silently gets `confirmNonce == null`, the deferred-ack→notify path is bypassed, and all tests stay green.

The fix is **all test/test-infra work** except G2 (adds one test bootstrap file) — **zero production-behavior change**. Each guard must be proven to have teeth.

---

## Methodology: mutation-verified RED for regression guards

These are **regression guards**, not new-behavior tests, so "RED-first" means something specific: a guard is only real if it **fails when the thing it protects is broken**. For every guard below, the RED step is a **mutation check**:

1. Write the guard.
2. **Temporarily mutate the protected code** (flip the constant / delete the wiring arg / rename the key / remove the isolation) and run the guard — confirm it goes **RED for the intended reason**.
3. **Revert the mutation**, run the guard — confirm **GREEN**.

A guard that stays green under its mutation is worthless; the mutation step is mandatory, not optional. G2 and G3 additionally have a genuine first-run RED (a reproduced flake / a non-existent harness) before their GREEN change.

---

## TDD implementation plan (ordered phases)

### Phase G2 (FOUNDATION — land first): isolate the notification gates per test

Landing first because it de-flakes the base every other phase runs on, and turns the existing 118 suite into a trustworthy parallel-green gate.

Root cause (verified): `recentRemoteNotificationGate` (`recent_remote_notification_gate.dart:9-10`) and `recentBackgroundNotificationGate` (`recent_background_notification_gate.dart:8-9`) are module globals defaulting to **fixed** file paths (`…:33-35` / `…:32-34`). `debugResetRecentRemoteNotificationGate()` (`:18-19`) re-constructs with the same default path and never `clear()`s the file. Production read sites with **no injection seam**: `background_message_handler.dart:135/168/191` (reads both globals directly).

RED (reproduce the flake at unit speed):
- New `test/core/notifications/notification_gate_isolation_test.dart` — two sequential tests in one file, both using the **default** global (no injection): test A calls `recentRemoteNotificationGate.markAnnouncement(payload:'p', messageId:'m')`; test B asserts `recentRemoteNotificationGate.consumeIfRecentAnnouncement(payload:'p', messageId:'m')` returns **false** (clean state). **Fails before Phase-G2 GREEN** — A's on-disk write leaks into B → B sees `true`. This encodes the exact `-j 1`-passes / parallel-fails hazard deterministically.

GREEN production/infra change:
- Create `test/flutter_test_config.dart` (does NOT exist today) with a `testExecutable(FutureOr<void> Function() testMain)` that, in a `setUp`, swaps **both** globals to unique-temp-file gates (stamp via a monotonically-varying value — NOT `Math.random`; use the test description or an incrementing counter, since `DateTime.now()` is the established pattern in `background_message_handler_test.dart:25-37`) and registers `addTearDown(gate.clear)` + `addTearDown(debugReset…)`:
  ```dart
  // test/flutter_test_config.dart
  Future<void> testExecutable(FutureOr<void> Function() testMain) async {
    setUp(() {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final remote = RecentRemoteNotificationGate(
          filePath: '${Directory.systemTemp.path}/mknoon_remote_gate_$stamp.json');
      final bg = RecentBackgroundNotificationGate(
          filePath: '${Directory.systemTemp.path}/mknoon_bg_gate_$stamp.json');
      debugSetRecentRemoteNotificationGate(remote);
      debugSetRecentBackgroundNotificationGate(bg);
      addTearDown(remote.clear);
      addTearDown(bg.clear);
      addTearDown(debugResetRecentRemoteNotificationGate);
      addTearDown(debugResetRecentBackgroundNotificationGate);
    });
    await testMain();
  }
  ```
- **Phase-G2a (validate the assumption first — flagged risk).** Flutter resolves `flutter_test_config.dart` by walking **up** from each test file to the nearest one, so a single `test/flutter_test_config.dart` *should* cover all nested dirs (`test/features/...`, `test/integration/...`, `test/core/...`). This is the one assumption to validate before relying on it: add a probe test in a deeply-nested dir asserting `recentRemoteNotificationGate.filePath.contains('mknoon_remote_gate_')` (the per-test stamp), NOT the fixed `mknoon_recent_remote_notifications.json`. If recursion does not hold on this Flutter version, the fallback is one `flutter_test_config.dart` per offending directory (`test/features/groups/application/`, `test/features/conversation/application/`, `test/integration/`).

VERIFICATION (Phase-G2b — the true acceptance gate):
- A repeatable shard script (e.g. `tool/notif_parallel_smoke.sh`) running `flutter test test/features/groups/ test/integration/ test/features/push/ -j 4` **N=20 times**, asserting zero flake. This is the real G2 close; the unit RED is the fast proxy.
- Phase-G2 must also re-run the previously-`-j 1`-only-green suites at **default parallelism** and show green.

Refactor notes: keep the `remoteNotificationGate:` constructor param on both listeners (`group_message_listener.dart:152`, `chat_message_listener.dart:80/112`) — it is the production injection seam and is still used by the 3 group / 1 drain / chat tests. Do not delete the existing per-test gate blocks in `background_message_handler_test.dart` / the two dedupe integration tests / `show_notification_use_case_test.dart`; they are belt-and-suspenders and exercise the `remoteNotificationGate:` param. Optionally slim them in a later cleanup.

### Phase G1: lock the `main.dart` replay-closure wiring constants

Goal: make a flipped `suppressNotification` boolean (the literal 118 bug) fail a test.

Context / 118 tension (must be acknowledged): doc 118 §"dropped Phase 0" explicitly rejected extracting `buildInboxChatReplayDispositions` because "testing a wrapper that forwards a constant is testing-the-mock." The replay closures (`main.dart:1665-1685`) each capture only `replayInboxChatMessage` and hardcode one boolean; `replayInboxChatMessage` itself (`:1616-1654`) is a `main()`-local closure capturing three `main()` locals (`chatMessageListener` — a `late final` at `:1610` — `introductionRepository`, `contactRepository`), so a *pure* top-level extraction is awkward. The codebase already has the right pattern for exactly this situation:

- **Primary (RECOMMENDED) — source-text wiring lock**, mirroring the established `test/core/lifecycle/main_resume_group_upload_wiring_test.dart` (which reads `lib/main.dart` as a string and `expect(block, contains('mediaFileManager: mediaFileManager'))`). This is the house pattern for locking a constant that lives inline in `main()` and is otherwise unreachable, with zero production churn and zero conflict with the 118 decision.

RED (mutation-verified):
- New `test/core/lifecycle/main_replay_disposition_wiring_test.dart` — read `lib/main.dart`, slice the `P2PServiceImpl(` argument region, and assert:
  - the `replayLiveDirectChatMessage:` block contains `suppressNotification: false`,
  - the `replayLiveLanChatMessage:` block contains `suppressNotification: false`,
  - the `replayRecoveredInboxChatMessage:` block contains `suppressNotification: true`,
  - and a structural guard that all three closures are present (count == 3) so a deletion fails too.
- **Mutation check**: temporarily flip `replayLiveDirectChatMessage:`'s constant to `true` in `main.dart` → the test must go RED → revert → GREEN. (Slice by `indexOf('replayLiveDirectChatMessage:')` … next `replay…:`/`)` boundary to avoid matching the wrong block — the recovery and live blocks both contain `suppressNotification:`.)

GREEN production change: **none** (test-only). The test is the GREEN artifact.

- **Alternative (owner-decision, only if the owner wants a behavioral assertion over a text assertion)**: extract a top-level `List<…>/record buildInboxChatReplayDispositions({required ReplayInboxChatMessage replay})` (mirroring `intro_notification_orbit_route_test.dart`'s extracted-top-level-function pattern) returning the three closures, wire `main()` to it, and unit-test that invoking each returned closure calls `replay` with the documented `suppressNotification` value. This is *more* than testing-the-mock (it asserts the closure→boolean mapping = the contract) but reverses the 118 decision and touches `main.dart` structure. Flag for the owner in OQ-1; default = primary source-text lock.

Refactor notes: keep the source-slice resilient to formatting — match on the closure label + the `suppressNotification:` token within its block, not on exact whitespace/line numbers (line numbers drift; the existing wiring test matches on tokens).

### Phase G4: lock the listener call-site wiring of `toneTracker:` + the mark closure

Goal: deleting `toneTracker:` from a listener call site (debounce silently stops) or the mark closure (live-wins dedup silently stops), or "symmetrizing" the group path by adding a mark closure, must fail a unit test. `FakeNotification` already carries `silent` (`fake_notification_service.dart:72`) — no fake change needed.

Shared helper (write first): `test/shared/fakes/spy_recent_remote_notification_gate.dart` — `class SpyRecentRemoteNotificationGate extends RecentRemoteNotificationGate` overriding `markAnnouncement`/`consumeIfRecentAnnouncement` to record calls (payload + messageId) while delegating to a temp-file super. Both listeners accept it via `remoteNotificationGate:`.

RED (mutation-verified), in `test/features/conversation/application/chat_message_listener_test.dart` (extend the `ChatMessageListener notification integration` group at `:1587`; add `NotificationToneTracker? toneTracker` + a `RecentRemoteNotificationGate? gate` to the `createListenerWithNotifications` builder at `:1612-1633` and thread them as `notificationToneTracker:` / `remoteNotificationGate:`):
1. `'toneTracker is wired: two direct messages, same conversation, in-window → first audible, second silent'` — inject `NotificationToneTracker(clock: () => fixedNow, window: Duration(seconds: 30))` (single fixed clock so both are in-window), paused lifecycle, feed two messages with the same `from`; assert `shown[0].silent == false`, `shown[1].silent == true`. **Mutation**: remove `toneTracker: notificationToneTracker` at `chat_message_listener.dart:571` → both `false` → RED.
2. `'markRecentRemoteNotificationAnnouncement is wired: a live direct notification marks the gate'` — inject `SpyRecentRemoteNotificationGate`, feed one message with a known id; assert exactly one `markAnnouncement` with `payload == contactPeerId` and `messageId == <id>`. **Mutation**: remove `chat_message_listener.dart:582-588` → zero marks → RED.

RED (mutation-verified), in `test/features/groups/application/group_message_listener_test.dart` (extend the `group notifications` group at `:10907`; thread `notificationToneTracker:` + spy gate into the `GroupMessageListener(...)` builder):
3. `'toneTracker is wired: two group messages, same group, in-window → first audible, second silent'` — fixed-clock 30s tracker, unmuted group, `getSelfPeerId` ≠ sender, feed two events same `groupId`/different `messageId`; assert `shown[0].silent == false`, `shown[1].silent == true`. **Mutation**: remove `toneTracker: _notificationToneTracker` at `group_message_listener.dart:941` → RED.
4. `'group path is intentionally mark-free: gate.markAnnouncement is never called'` — inject `SpyRecentRemoteNotificationGate`, feed one group message; assert a notification was shown AND **zero** `markAnnouncement` calls. This pins the intentional 118 asymmetry (group is mark-free per 118 plan Risk). **Mutation**: add a mark closure to the group call site → RED.

GREEN production change: **none** (test-only).

Refactor notes: chat keys on the bare `contactPeerId`; group keys on `group:$groupId` with an anchored `routePayload` — both normalize via `ActiveConversationTracker.normalizeActiveKey`, so two group messages bucket together for the silent-debounce assertion (proven by the existing 118 tone-key guard; this phase locks the *call-site wiring*, not the key math).

### Phase G3: a 2-party live-direct notification simulation

Goal: convert the manual-only device proof into a deterministic, automated 2-party, transport-and-lifecycle-aware simulation that catches a regression in **which path** a live message takes. Reuses the entire receiver pipeline already proven by the single-node `live_direct_notification_integration_test.dart` — **zero production change**, ~80 lines of test scaffolding modelled on `GroupTestUser`.

Scaffolding (write first):
- Lift the `_FakeBridge` from `live_direct_notification_integration_test.dart:339-393` into `test/shared/fakes/recording_fake_bridge.dart` (records commands, configurable responses, exposes `onMessageReceived` + `payloadsFor`).
- New `test/shared/fakes/one_to_one_test_user.dart` — a 1:1 sibling of `GroupTestUser`. Per user it owns: a `RecordingFakeBridge`, a real `ChatMessageListener`, a real `P2PServiceImpl` wired with the three **main.dart-mirroring** replay closures (recovery=suppress, lan/direct=notify), a `FakeNotificationService`, a `FakeContactRepository`/`FakeMessageRepository`, a shared (per-sim) `RecentRemoteNotificationGate`, a real clock-injected `NotificationToneTracker`, and `getAppLifecycleState: () => _lifecycle` (mutable) + a `conversationTracker` the test can set viewing/not.
- New `DirectMessageRouter.deliver(from, to, text, {required String transport})` — mints a `confirmNonce`, builds a v1 `chat_message` envelope, and for `transport in {'direct','relay'}` calls `to.bridge.onMessageReceived(ChatMessage(... transport, confirmNonce))`; for `transport == 'wifi'` pushes a `LocalChatMessage` onto the receiver's LAN stream (the `_localMessageSub` path, `p2p_service_impl.dart:277-302`, which stages `lan:` and routes through `replayLiveLanChatMessage`).

RED (the harness does not exist → the test cannot run; then mutation-verified once GREEN), new `test/integration/live_direct_notification_simulation_test.dart`:
1. `'relay direct message, recipient resumed-not-viewing → one audible notification + sender confirmed'` — `router.deliver(bob, alice, …, transport:'relay')`; assert `alice.notificationService.shown` length 1, `silent == false`, and `bob.bridge.payloadsFor('message:confirm')` has `{'nonce':…, 'ok':true}` (notify + ack coexist). Assert `transport == 'relay'` on the message handed to the live-direct callback (as `p2p_service_impl_test.dart:1107`).
2. `'direct transport behaves identically to relay (both confirmNonce-gated, not transport-gated)'` — same with `transport:'direct'`; assert notify + the `MSG_RECEIVED_TRANSPORT` event shows `direct`.
3. `'resumed + viewing the sender's conversation → suppressed'` — `alice.conversationTracker.setActive(bobPeerId)`; deliver; assert `shown` empty (`viewing_conversation`).
4. `'burst within the window → one tone then silent'` — two relay deliveries same sender in-window; assert `shown` `[false, true]`.
5. `'LAN (wifi) takes the live-lan path, not the direct staging path'` — `transport:'wifi'`; assert notify and that the staged id was `lan:…` (different branch).
6. `'FCM-handoff dedup: after a live notify writes its marker, a late push for the same messageId is suppressed'` — after test 1's notify, call the shared gate's `consumeIfRecentAnnouncement(payload: bobPeerId, messageId: <id>)` and assert it returns **true** (the late FCM suppresses → no double-alert). This is the simulation form of the 118 Phase-5 dedup-race verification across the live-wins marker.
- **Mutation checks** (prove the sim has teeth): (a) flip the production `replayLiveDirectChatMessage` constant to suppress → tests 1/2 RED; (b) make the recovery sweep prefix-blind again → a swept-`direct:` sub-case RED. Revert after.

GREEN: no production change; the harness + tests are the artifact.

Refactor notes: the sim must depend on Phase G2 landing first (it uses the gate; without per-test isolation the sim would itself be flaky). Keep the router's transport set minimal (`direct`/`relay`/`wifi`); chaos/reorder is out of scope (that is `ChaosP2PNetwork`'s domain and not a 118 concern).

### Phase G5: pin the Go→Dart `confirmNonce` contract (Go-side)

Goal: a Go rename/drop of the `confirmNonce` key, a change to the `type=="chat_message"` gate, or a flip of the `EnableDeferredDirectAck` default must fail a Go test. Dart cannot guard this (it never sees a real Go payload in unit tests); a Dart parser test is necessary-but-insufficient.

Home: `go-mknoon/node/transport_label_test.go` (package `node`) — it already has the purpose-built harness: `newDeferredAckTestNode(t, cb, timeout)` (`:152-168`, gate-satisfied: `isStarted`, real `eventDispatcher`, `directConfirmTimeoutOverride`), `newStubTransportStream(...)` + `chatEnvelopeForTest(t, id)` (`:170-188`), and `directConfirmCallback.OnEvent` already reads `payload.Data["confirmNonce"]` (`:124-150`). Do NOT use `protocol_contract_test.go` (relay module), `crypto/interop_test.go` (golden crypto vectors; nonce is a random UUID so golden vectors don't fit), or `bridge_test.go` (command direction, not the event).

RED (mutation-verified), add `TestHandleIncomingMessage_DirectAckContract_AttachesConfirmNonce`:
1. Build node via `newDeferredAckTestNode(t, collector, 50*time.Millisecond)` with a `testEventCollector`; feed `chatEnvelopeForTest(t, "msg-contract")` through `newStubTransportStream` into `n.handleIncomingMessage(stream)`.
2. Assert on the captured `message:received` event: the key is **exactly `"confirmNonce"`** (string literal — a rename fails), and its value is a **non-empty string** (do NOT assert the UUID value — keeps it deterministic/non-flaky).
3. **Negative control**: with `EnableDeferredDirectAck=false` on the node's flags, a `chat_message` `message:received` event carries **no** `confirmNonce` key — pins the gate, not just presence.
4. Default-flag guard: assert `DefaultFeatureFlags().EnableDeferredDirectAck == true` (mirrors `feature_flags_runtime_test.go:29-30`) so a default flip is caught.
- **Mutation check**: temporarily rename `msgData["confirmNonce"]` → `msgData["confirmNonceX"]` at `node.go:1618` → test RED; revert → GREEN. Temporarily set the default flag false → guard #4 RED; revert.

GREEN production change: **none** (test-only).

Optional Dart sibling (cheap): in `test/features/p2p/domain/models/chat_message_test.dart` the parser pin already exists at `:194-203` (`fromJson` reads `confirmNonce`). Add a code comment in BOTH `chat_message.dart` (near `:9/:42`) and `node.go` (near `:1618`) naming the shared wire key `confirmNonce` and the `message:received` event, so a future renamer sees both halves of the contract. (No new Dart test required — the existing parser test plus the Go producer test bracket the boundary.)

Gate: `cd go-mknoon && go test ./node` (the standard review gate per `phase-review.md:83-84`; `make test` runs `go test ./...`).

---

## Mandatory landing order & dependencies

```
Phase G2  (gate isolation)            ← FOUNDATION, land first; de-flakes the base
   └─> Phase G3 (2-party simulation)  ← HARD-depends on G2 (uses the gate; flaky without isolation)
Phase G1  (main.dart wiring lock)     ← independent; cheap; highest single-bug value
Phase G4  (listener call-site lock)   ← independent (needs the SpyGate helper)
Phase G5  (Go confirmNonce contract)  ← fully independent (different module/language); land any time
```

- **G2 first.** It is the highest-leverage change: it makes every other guard (and the existing 118 suite) trustworthy under parallel `flutter test`. G3 must not land before G2 (it would import the same flakiness).
- **G1, G4, G5 are independent** and may interleave; G5 can be done in parallel by anyone (Go-only).
- Minimum set to "the 118-class bug cannot silently recur": **G1 + G4 + G5** (the three wiring/contract locks). G2 makes them reliable; G3 is the strongest end-to-end proof. Recommended full order: **G2 → G1 → G4 → G3**, with **G5** anytime.

---

## Risks & regressions to guard

- **Source-text wiring lock brittleness (G1).** A whitespace/formatting refactor of `main.dart` can false-RED the slice match. **Mitigation**: match on the closure label + `suppressNotification:` token within the sliced block (not exact lines/whitespace), exactly as `main_resume_group_upload_wiring_test.dart` does; document that an intentional rename requires updating the lock.
- **`flutter_test_config.dart` recursion assumption (G2).** If the nearest-config-walking-up behavior does not cover nested dirs on this Flutter version, a single root config silently isolates nothing. **Mitigation**: Phase-G2a probe test asserting the active gate `filePath` carries the per-test stamp from a deeply-nested test; fallback to per-directory configs.
- **Over-isolation hiding a real cross-message dedup (G2).** Per-test gate reset must not mask a genuine within-test dedup the 118 tests rely on. **Mitigation**: isolation is per-test (setUp), not per-call; within a test the gate persists. The existing 118 dedup tests must stay green after G2.
- **Simulation drift from `main.dart` (G3).** The sim mirrors the main.dart closures rather than booting `main()`, so it cannot catch a `main.dart` wiring regression — that is G1's job. **Mitigation**: G1 + G3 are complementary; the plan keeps both. Note this explicitly in the sim file header.
- **Go contract test flakiness (G5).** Asserting the UUID value or relying on real timers would be flaky. **Mitigation**: assert key-presence + non-empty only; reuse the existing 50ms `directConfirmTimeoutOverride` harness; no live libp2p.
- **Scope creep.** Chaos/reorder transport modelling, multi-device group simulation, persisted background tone-debounce (118 OQ-4), and the G1 extraction alternative are all attractive but NOT required to close these five gaps. **Mitigation**: explicitly deferred (OQ-1/OQ-2).
- **Touching the 118 production code.** This plan is test/test-infra only (G2 adds a test bootstrap file, not production). If any phase tempts a production edit, stop — that is a behavior change, not a coverage fix.

---

## Open questions for the owner

1. **OQ-1 (G1 strategy).** Primary = source-text wiring lock (zero production churn, matches house pattern, respects 118's no-extraction decision). Alternative = extract `buildInboxChatReplayDispositions` to a top-level function + behavioral unit test (reverses 118's call, touches `main.dart`). Default chosen: source-text lock. Confirm, or opt into the extraction.
2. **OQ-2 (G3 depth).** Is the single happy-path-plus-suppression-plus-handoff sim sufficient, or should it also model chaos (drop/reorder via `ChaosP2PNetwork`) and a second receiver? Default: minimal (no chaos, 2 users).
3. **OQ-3 (G2 cleanup).** After global isolation lands, slim the now-redundant per-file gate setUp blocks, or leave them as belt-and-suspenders? Default: leave them (harmless; they also exercise the `remoteNotificationGate:` injection seam).
4. **OQ-4 (G5 Dart sibling).** Is the existing parser test + the new Go producer test sufficient to bracket the boundary, or do you want an additional Dart bridge-contract test that round-trips a recorded real Go `message:received` payload fixture? Default: Go producer test + cross-reference comments only.

---

## Closure bar

Closed only when ALL hold:

- **G1**: a wiring-lock test fails when `replayLiveDirectChatMessage`'s `suppressNotification` is flipped to `true` in `main.dart` (mutation-verified), and passes on the real wiring.
- **G2**: `test/flutter_test_config.dart` exists and is auto-applied (probe test confirms the per-test stamped gate path); the gate-leak repro test passes; the previously-`-j 1`-only-green suites pass at **default parallelism**, and the parallel-shard smoke (`-j 4`, N≥20) shows **zero** flake.
- **G3**: a 2-party simulation test asserts the relay/direct live path notifies (+ sender ack), viewing suppresses, a burst coalesces to one tone, LAN takes the `lan:` path, and the live-then-late-FCM sequence does not double-alert — and the sim goes RED when the live-direct routing constant is mutated (mutation-verified).
- **G4**: removing `toneTracker:` (chat or group) or the chat mark closure fails a unit test; adding a mark closure to the group path fails the mark-free guard (all mutation-verified); `FakeNotification.silent` assertions are the seam.
- **G5**: a Go `node`-package contract test fails when `node.go`'s `confirmNonce` key is renamed or when `EnableDeferredDirectAck`'s default is flipped (mutation-verified); `cd go-mknoon && go test ./node` is green; the shared wire key is comment-cross-referenced in `chat_message.dart` and `node.go`.
- Every guard above is **mutation-verified** (proven to go RED under the break it protects, then GREEN on revert), per the methodology section.
- Full host suite green at default parallelism; `cd go-mknoon && go test ./node` green; `flutter analyze` 0 new issues; `graphify update .` run.

---

## Implementation closure log (2026-06-13)

IMPLEMENTED on `121-improvements` (uncommitted), executed via a staged workflow (G2 foundation → G1∥G4∥G5 → G3) on the main tree with disjoint-file fencing + mutation-verify. All five guards are mutation-verified (proven to go RED under the break they protect, then GREEN on revert). Zero production-behavior change; all temporary mutation edits reverted (verified: main.dart live-direct `suppress:false`, p2p_service_impl `_replayLiveDirectChatMessage`, chat listener toneTracker+mark present, group listener toneTracker present + mark-free, node.go `confirmNonce` key, `EnableDeferredDirectAck: true`).

Files added:
- `test/flutter_test_config.dart` (G2), `test/core/notifications/notification_gate_isolation_test.dart` (G2), `tool/notif_parallel_smoke.sh` (G2)
- `test/core/lifecycle/main_replay_disposition_wiring_test.dart` (G1, 4 source-text wiring-lock tests)
- `test/shared/fakes/spy_recent_remote_notification_gate.dart` + tests in `chat_message_listener_test.dart` & `group_message_listener_test.dart` (G4, 4 cases)
- `test/shared/fakes/recording_fake_bridge.dart`, `test/shared/fakes/one_to_one_test_user.dart`, `test/integration/live_direct_notification_simulation_test.dart` (G3, 6 cases)
- `go-mknoon/node/transport_label_test.go` `TestHandleIncomingMessage_DirectAckContract_AttachesConfirmNonce` (G5) + cross-ref comments in `node.go` and `chat_message.dart`

**G2 config fix (post-workflow correction).** The first `flutter_test_config.dart` registered `addTearDown(gate.clear)` — an awaited async `File.delete` in every test's teardown — which intermittently destabilized timing-sensitive upload **widget** tests (`group_conversation_wired_test.dart` flaked WITH the config, passed 125/125 without it; toggled-off run proved causation). Per the project rule "testWidgets: sync I/O only", cleanup was switched to **synchronous** `deleteSync` (unique paths already give the isolation; delete is hygiene-only). After the fix the widget test is stable AND the gate isolation still holds.

**Gate (default parallelism, the real win — these suites were previously `-j 1`-only-green):** notifications-core + lifecycle + push + G3 sim = 493 ✓; **groups 2022/2022 ✓** (was flaky under parallel before G2); conversation 1189 (G4 chat tests pass); `go test ./node -run DirectAckContract` ok ✓; `flutter analyze` 0 new issues (1 pre-existing `_bytes123ContentHash` unused_element). Phase-G2a recursion verdict: a single root `test/flutter_test_config.dart` IS auto-applied to nested dirs on this Flutter version (no per-dir fallback needed). Only non-120 failure anywhere: pre-existing `retry_unacked_messages_null_guard` (115 `'inboxed'`), concurrent in-flight work untouched by 120.

**Open follow-ups**: OQ-1 (source-text lock vs extraction — shipped source-text), OQ-3 (slim redundant per-file gate setUp — left as belt-and-suspenders). `tool/notif_parallel_smoke.sh` red-flags on iteration 1 only because its shard set contains the 4 pre-existing 114/115/116 failures (it can't distinguish them from a real flake); the notification/group flake itself is gone (5 consecutive `-j 4` runs were bit-for-bit identical).
