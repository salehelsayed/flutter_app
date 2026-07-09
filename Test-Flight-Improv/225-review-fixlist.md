# 225 Review — Fix-List (apply against `225-notif-tap-last-message-lag-tdd-plan.md`)

Source: 8-agent audit (2 source-verifiers → 5 dimension assessors → 1 evergreen critic) + orchestrator self-verification against real source, 2026-07-09. Workflow `wf_ea1fd793-f62`.

**Verdict: READY-WITH-TIGHTENING.** Both core bets are ground-truth SOUND (Slice A replay-before-ack is *strictly safer* than today; Slice B payload is *sufficient* to render with zero relay RTT). Apply §A–§B (material) before execution; §C–§D during execution; §E are line-fixes. None is a re-plan.

Dimension scores: D1 Goal 70 · D2 Compartmentalization **76 (strong)** · D3 Anti-drift 57 · D4 Define-good 68 · D5 Tests-verify-goal 62.

## Decisions locked with the user
- **Ingest wiring = BOUNDED AWAIT (~400ms).** Keep the plan's awaited-ingest + TC-B7 "first settled frame" intent for the common ~ms case, but cap the route-gating wait at ~300–500ms and fall through to the live `incomingMessageStream` on the rare slow/cold case. (Rejected: fire-and-forget, keep-as-planned-10s.)
- **Rollback risk = N/A (B-1 CLEAR).** File-based additive staging, no schema/wire change, forward-compatible; old builds ignore staged files. No forward-compat-release / kill-switch needed.
- **Next action = findings + this fix-list** (plan file left untouched for the executor to apply).

## Verified facts this list relies on (checked against source by the orchestrator)
- Slice A ordering: `_retrievePendingInboxPage` = stage `:1970` → migration-gate `:1976-1993` → **awaited** `callP2PInboxAck` `:1994-2022` (exception-swallowed `:2014-2020`) → replay `:2024-2028`. Ack has no ordering dependency on replay. ✅
- Relay is non-destructive on retrieve, deletes only on ack: `backend_memory.go:156-186`/`:219-265`, `backend_redis.go:378-423`/`:425`. Reorder is strictly safer than today's ack→replay. ✅
- Push carries `sender_id` + `message_id` + `kem/ciphertext/nonce`: `go-relay-server/inbox.go:289-296`; oversized/media drop ciphertext `:297-310`. iOS `MutableContent:true` `:429`; `apnsCustomDataFromPushData` `:530-536`. ✅
- Three-way sender check (needs `senderPeerId`): `handle_incoming_chat_message_use_case.dart:263-265`. Row dedupe: `:303` (`getMessage(payload.id)`). ✅
- Route awaits prepare BEFORE navigate: `notification_route_dispatch.dart:21-22`. Bridge calls carry 10s timeouts: `bridge.dart:268/338`. ✅
- **Two** prepare wrappers: `main.dart:4475` (passes `warmPeer` `:4499`) and `startup_router.dart:1031` (cold `getInitialMessage` tap via `:811-833`, does NOT pass `warmPeer`). ✅
- No P2PService interface change needed: `ReplayRecoveredInboxChatMessage` typedef + `main.dart:2083` closure are standalone-injectable. ✅
- iOS precedents real: `AppGroupPushDedupeStore` (`NotificationPreviewResolver.swift:446`), `RecentRemoteShownMarkerStore` (`:501`, file-based), Dart seam `lib/core/notifications/app_group_path_channel.dart`. ✅
- `test/core/**` is NOT auto-globbed into `ONE_TO_ONE_TESTS` (the plan's "add explicitly" registration instruction is necessary and correct). ✅

Glossary: *Move* = the account-migration feature; *NSE* = the iOS Notification Service Extension (a separate process that runs on push receipt); *145* = the prior fix that made notif-tap routing non-blocking; *drain* = the relay offline-inbox catch-up.

---

## §A — OS-boundary correctness (device-only-catchable; MUST land before/at execution)

- **A1. Pin the iOS NSE *written* schema, not just its trigger. [MATERIAL — blocker #1]**
  Plan §"Real Scope" iOS bullet (lines 149-155) and step 9 (line 346) enumerate only `kem`/`ciphertext`/`nonce` as the write *trigger* and never pin the *written* field set. If the Swift executor omits `senderPeerId`, the three-way sender check (`handle_incoming_chat_message_use_case.dart:263-265`) is unsatisfiable → **every iOS ingest is rejected as senderMismatch** → silent fall-back to drain (host-green, TestFlight-broken on iOS; the NSE has zero host/sim coverage).
  *Edit:* replace "writes the envelope JSON when the userInfo carries `kem`/`ciphertext`/`nonce`" with the explicit mapping, identical to Android:
  `{kind:'chat', kem, ciphertext, nonce, senderPeerId: userInfo['sender_id'] ?? userInfo['from'], messageId: userInfo['message_id'], receivedAtMs}`.

- **A2. Split TC-B12 into two REQUIRED per-platform receiver legs. [MATERIAL — blocker #4]**
  TC-B12 (lines 290-295, matrix 318, Done-criteria 414) is a single `--scenario`/single device-A, but the iOS-NSE-Swift and Android-Dart-isolate writes are disjoint and the iOS one is non-substitutable (no host/sim covers the NSE). As written, closure can pass running only one platform.
  *Edit:* two required scenarios `payload_fast_path_ios_receiver` (receiver = iPhone; mutation = disable NSE staging) and `payload_fast_path_android_receiver` (receiver = Pixel; mutation = disable handler staging); register both `--scenario` ids in the `classify_path` device-proof case; Done-criteria requires **both** green.

- **A3. Mandate full airplane mode; strike "relay unreachable". [part of blocker #4]**
  TC-B12 "airplane mode / relay unreachable" (line 292) — "relay unreachable" is a **false-green vector**: same-WiFi devices take a libp2p **LAN-direct** leg (per project memory `project_lan_ws_server_over_libp2p_rationale`) that can deliver the message live while the staged path is broken.
  *Edit:* strike "/ relay unreachable"; require **full airplane mode** (all radios off) on the receiver *after* the push has arrived, with an explicit precondition that no A↔B LAN/WS transport exists (separate networks or fully offline).

- **A4. Add a real cold-kill leg. [part of blocker #4]**
  "backgrounded ≥1min" (line 292) ≠ killed; the dominant notif-tap reality (OS kills the app; the NSE exists *because* the app may be dead) is never RUN — only host-proxied by TC-B1/B8/B10.
  *Edit:* add a step (or a third scenario `payload_fast_path_cold_kill`): after the push arrives and before the tap, force-stop the receiver (`adb shell am force-stop <pkg>` / iOS terminate), then cold-launch via the tap; assert the announced message still renders, proving the killed→cold-launch→startup-ingest handoff.

## §B — The 145 route-await (LOCKED: bounded await ~400ms)

- **B1. Bound the route-gating ingest await. [MATERIAL — blocker #2]**
  Plan lines 146-147 & 345 assert the awaited ingest is "wrapped so a throw can never fail/block the route." **Inaccurate:** `notification_route_dispatch.dart:21-22` awaits prepare before navigation; try/catch stops a *throw* but not a *stall*, and `callDecryptMessage` carries a 10s timeout (`bridge.dart:268/338`) — a pathological native decrypt hang gates the screen up to 10s, re-introducing the 145 latency class.
  *Edit:* in the conversation branch of `prepareNotificationOpen`, wrap the ingest as `await ingest().timeout(const Duration(milliseconds: 400), onTimeout: () {/* fall through; live stream renders it */})`; keep the swallow-and-log. Replace the "can never block the route" wording with "bounded to ~400ms; a stall or throw falls through to the `incomingMessageStream` render." Note the common case is ~ms (pure crypto, concurrent dispatch on both platforms, instant `missingKey` no-op on cold taps `:624`).

- **B2. Restate TC-B7 to keep the bound honest.**
  TC-B7 (lines 266-271) must tolerate the fall-through: primary assertion = "announced text visible on the first settled frame in the common case; on the bounded-timeout path, visible within N frames via the stream render." (See also E4 — the event-absence clause is separately vacuous.)

## §C — Sibling site that does NOT inherit (B-2 undercount)

- **C1. Wire (or test) the cold remote-FCM tap. [MATERIAL — blocker #3]**
  `prepareNotificationRouteTarget` has two wrappers; the plan wires only `main.dart:4475`. The cold `getInitialMessage` tap uses `startup_router.dart:1031/:833`, which (like `warmPeer`) would receive a default-null ingest param → the **dominant "app was killed → cold launch via tap" case** gets no prepare-time first-frame fast-path.
  *Edit:* either pass the ingest param into `startup_router.dart:1031` too, OR add an explicit test proving wiring-(b) startup/resume ingests the staged envelope *before* the cold-tapped conversation's first render. Add `startup_router.dart` to "Files To Inspect Next" and the step-8 wiring section.

## §D — Under-specified seams (pin before an executor improvises)

- **D1. Key the staging store on `nonce`, not `messageId`. [MODERATE]**
  `messageId` can be null (`remoteNotificationMessageIdFromData` → null when absent; `buildPushMessage` adds `message_id` only "if present"). Keying `clear(id)`/dedupe on it breaks for message-id-less pushes.
  *Edit:* in the `push_envelope_staging.dart` bullet (lines 128-130) declare the entry id = `nonce` (always present, unique per message); `messageId` is metadata only. In TC-B5 clarify that "already-persisted dedupe" rides the pipeline's decrypted `payload.id` (`getMessage`), not a push-messageId pre-check.

- **D2. Source `message.to` from local identity; scope step-7's Stop-if to sender fields. [MODERATE]**
  The reconstructed ChatMessage needs `message.to` = local own-peer-id (as the drain passes `toPeerId` into `_stagingEntryFromRawInboxMessage`), not the push. Step 7 (line 344) says "extend the staged schema from the go-relay-server push builder side" — for `to` that would drive a **Scope-Guard violation** (Do-not-touch-relay).
  *Edit:* in the ingest bullet (lines 134-143) and step 7, add "`message.to` = local own-peer-id (identity/keystore seam), NOT staged and NOT from the push; step-7's Stop-if applies to SENDER-side identity only."

- **D3. Mandate atomic file writes; don't clear torn-young files. [MODERATE — B-5]**
  The mirrored precedent (`RecentRemoteShownMarkerStore`) writes a *contentless* presence file — no content-atomicity pattern for the ~4KB envelope JSON. A torn read is "malformed" → TC-B5 *clears* it → fast-path silently lost.
  *Edit:* `push_envelope_staging.dart` (+ iOS store) MUST write atomically (`Data.write(options:.atomic)` on iOS / temp-file+rename on Dart). Do NOT clear a malformed file younger than a short write-window (leave it for retry). Add a TC-B1 case for a torn/partial file being retried, not deleted.

- **D4. Single per-platform staging-dir resolver for BOTH writer and reader. [MODERATE]**
  The reader is pinned (iOS app-group / Android path-provider) but the Dart *writer* isn't; a writer/reader dir mismatch on iOS orphans files (never read, never pruned).
  *Edit:* pin one `resolveStagingDir()` used by both writer and reader; state that on iOS the NSE owns staging (the Dart background handler either does not stage on iOS or stages to the same app-group dir).

- **D5. Enforce cap-on-WRITE (not only prune-on-read). [MODERATE]**
  Prune runs on Dart read; the NSE only writes. Existing NSE markers "accumulate until next cold-start prune" (`NotificationService.swift:52-54`), so ~4KB envelopes accumulate if the app is never opened.
  *Edit:* the iOS `AppGroupPushEnvelopeStore` enforces the ~64 cap on write (evict oldest), not only on the Dart-side prune.

- **D6. Add a preserve-with-staging gate for NSE 04-P0 + a receipt-timing parity note. [MODERATE — B-9]**
  Adding a ~4KB sync write to NSE `didReceive` consumes the ~30s NSE budget, yet no test asserts preview/mute/dedupe still pass *with staging enabled* (only the disable mutation). Ingest also fires receipts via `processIncomingMessage` *earlier* than the drain's 146 deferral.
  *Edit:* add a device/sim assertion that NSE preview+mute+dedupe pass with envelope staging ON; add a note/test that ingest-path receipt timing matches the 146 drain-path contract.

- **D7. Guard concurrent double-ingest. [MODERATE — critic-only find]**
  Wiring (a) prepare-tap and (b) startup/resume can both fire for the same entry on a tap-during-resume; `getMessage(payload.id)` saves the row, but two concurrent `readAll→decrypt→clear` passes are untested.
  *Edit:* add a single-flight guard around ingest (or a concurrent-ingest idempotency test asserting one clear, one row, no double emit).

- **D8. Capture a warm-path latency baseline; demote `≤2s`. [MODERATE — B-4]**
  The complaint is warm-path latency, but no baseline is captured and `≤2s` overlaps the asserted `0.5–2s` baseline (a network-up `≤2s` gate would pass on the *unfixed* build). The categorical zero-relay-RTT discriminator is the right *correctness* proof but is not a *latency* proof.
  *Edit:* add a step-0 baseline capture via the existing `benchmark_notification_tap_harness.dart` (N≥20, p50/p95) on HEAD; state "primary pass/fail = renders with zero relay RTT (categorical); `≤2s` is a UX comfort wrapper, NOT the improvement bar"; optionally add an automated `pumpUntil(..., timeout)`/Stopwatch bound in the TC-B12 body and a network-available variant.

## §E — Line-level corrections (nits, but real)

- **E1.** Arbiter line 17: "closure gate = **TC-B10** device proof" → **TC-B12** (TC-B10 is a host unit test). This is the hand-off-to-execution line.
- **E2.** Root cause (line 92) + step 3 (line 340): replay block `:2024-2027` → `:2024-2028` (line 2028 `replaySw.stop()` is part of the block and must move with it, or the stopwatch is orphaned).
- **E3.** Blocked-before-decrypt precedent cited `chat_message_listener.dart:374` (lines 140, 177) → actual reject is `:383` (`:374` is the migration gate). Non-breaking (inherited via `processIncomingMessage`) but the cited line backing INV-225-7/TC-B5 is wrong.
- **E4.** TC-B7 event-absence discriminator (line 270) is **vacuous at the fake tier** (a `FakeP2PService` never emits the drain event) and the plan's constant `P2P_SERVICE_STAGED_DRAIN_SUCCESS` drops the `INBOX_` segment vs the real `P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS` (`p2p_service_impl.dart:2176`) — a literal grep-gate would miss. Move the event-absence clause to the real-impl sim tier (TC-B11) and restore `INBOX_`.
- **E5.** "Missing coverage gaps" para (lines 194-199): first-frame credited to TC-B6 / device-threshold to TC-B10 → matrix says **TC-B7** / **TC-B12** (TC-B6 = prepare hook, TC-B10 = startup/resume ingest).

---

## Priority order to apply
1. **§A1 + §A2/A3/A4** — the iOS write-set (silent host-green/TestFlight-broken) and the device gate that actually RUNS both OS boundaries. Without these the deliverable can ship broken on iOS undetected.
2. **§B1/B2** — bound the route await (locked ~400ms) so the fix does not re-introduce its own 145 latency, and keep TC-B7 honest about the fall-through.
3. **§C1** — wire/test the cold remote-FCM tap so the dominant notif-tap case gets the first-frame fast-path.
4. **§D1–D8** — pin the improvise-prone seams (store key, `message.to`, write atomicity, dir resolver, cap-on-write, preserve/receipt gates, concurrency, baseline).
5. **§E1–E5** — line-fixes (constant/grep-gate correctness and the mislabeled ship gate matter most).
