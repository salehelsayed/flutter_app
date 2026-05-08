# Reliability Simulation Coverage for Race and Failure Convergence

## 1. Title and Type

- **Title:** Reliability simulation coverage for race and failure convergence
- **Issue type:** `feature-improvement`
- **Output doc path:** `Test-Flight-Improv/92-reliability-simulation-race-failure-convergence.md`

## 2. Problem Statement

Users expect 1:1 chats, group chats, announcements, notifications, media, and
message state changes to converge to one correct timeline even when delivery is
messy: both peers send at once, the same message arrives through more than one
path, a connection silently stops carrying bytes, an ACK arrives late, a push
handler dies mid-flight, or inbox replay races live delivery.

The current test surface covers many important reliability paths, but the
remaining simulation gaps are concentrated around race convergence, partial
failure, retry/idempotency, resource cleanup, backlog scale, and malformed
libp2p traffic.

From the user's perspective, these gaps matter because the visible failures are
not transport details. They appear as duplicate messages, stale deleted content,
wrong chat routing, stuck sending states, media that looks done when it is not,
an Online badge that cannot actually send, unread counts that drift, or group
state that differs between members and devices.

## 3. Impact Analysis

- **Affected users:** people using 1:1 chat, group discussion, announcements,
  media messages, notification opens, same-account multi-device group use, and
  offline recovery.
- **When it appears:** during reconnect, resume, cold start, background push,
  notification tap, direct/relay/WiFi path changes, group membership changes,
  media upload/download, inbox drain, retry, and long-running sessions.
- **Severity:** critical for message trust where the same message, ACK, stream,
  notification, media job, or group event can arrive more than once or in a
  conflicting order; high for resource cleanup and device-context parity.
- **Frequency:** not measurable from repo evidence alone. Repo evidence shows
  broad delivery and recovery coverage, but does not prove the specific
  convergence matrix described here.
- **Visible cost:** duplicate rows, missing rows, stale bodies after delete/edit,
  incorrect unread counts, wrong route targets, frozen upload/download state,
  misleading sendability, and timeline divergence after restart or recovery.

## 4. Current State

- `Test-Flight-Improv/_current-test-map.md` defines named gates for baseline,
  1:1 reliability, groups, notifications/deep links, and startup/transport. It
  also lists heavier device-bound or soak-style suites such as
  `integration_test/wifi_transport_test.dart`,
  `integration_test/group_recovery_e2e_test.dart`,
  `integration_test/multi_relay_failover_test.dart`,
  `integration_test/relay_chaos_soak_test.dart`, and
  `integration_test/soak_e2e_test.dart` as nightly or release-pool style
  confidence.
- `scripts/check_reliability_simulation_discovery.sh` classifies current
  reliability candidates across 1:1, group, and intro surfaces. It includes
  routing smoke, WiFi/relay fallback, soak, media journey, notification-open,
  notification sound, foreground group push drain, group recovery,
  multi-device group proof, iOS notification tap, push decrypt, and intro
  scenarios. It intentionally classifies benchmark-only and general UI
  performance files outside reliability simulation discovery.
- `scripts/run_reliability_simulations.sh` consumes that discovery output and
  plans simulator/E2E commands for `all`, `1to1`, `group`, and `intro` scopes.
  This establishes that the repo already treats reliability simulation as a
  first-class acceptance layer.
- `lib/core/services/p2p_service_impl.dart` merges bridge-delivered messages
  and local WiFi messages into one message stream, tracks relay state and
  connection state, drains staged 1:1 inbox entries, ACKs after local staging,
  and exposes send results with ACK, transport, stream-open, write, and
  ACK-wait timing metadata.
- The 1:1 inbox path now stages `retrieve_pending` results locally before ACK
  and replays staged entries. It skips malformed entries individually and emits
  flow events for skipped malformed rows, staging, ACK, replay, and safe
  no-progress error cases.
- `integration_test/wifi_transport_test.dart` covers direct WiFi send/receive,
  ACK timeout, connection pool reuse, idle disconnect and reconnect,
  bidirectional messages, malformed WebSocket messages, concurrent sends on one
  pooled connection, max connection rejection and recovery, remote close, and
  WiFi media transfer with hash verification.
- `integration_test/scripts/run_routing_smoke_e2e.dart` covers local WiFi,
  relay probe, both-sides restart, background/foreground resume, relay failover,
  group publish, warm group send, group bidirectional send, group offline inbox,
  group lifecycle, group peer discovery timing, group key rotation, and
  multi-member publish.
- `integration_test/group_recovery_e2e_test.dart` covers missed group messages
  after resume drain, missed announcement recovery, dissolved group cleanup,
  live-plus-inbox dedupe for one group message, watchdog restart, and bounded
  multi-group drain.
- `integration_test/foreground_group_push_drain_test.dart` covers targeted
  group inbox drain from foreground push, group media drain exactly once,
  tampered media failure before done display, oversized media rejection,
  live-first then foreground-push dedupe, background announcement notification
  dedupe, and 1:1-vs-group drain isolation.
- `integration_test/notification_open_ui_smoke_test.dart` covers warm and cold
  chat notification opens, backlog rendering before route completion,
  delete-before-open, background edit/delete state on first render, and
  relaunch reconstruction of quote, edit, delete, and reaction state.
- `scripts/smoke_test_push_decrypt_simulator.sh` includes iOS and Android rows
  for 1:1 text, 1:1 media descriptor, group text, group media descriptor,
  missing key fallback, corrupt ciphertext fallback, tampered signature
  fallback, unknown envelope kind, thread identifiers, active conversation
  suppression, same-user multi-device delivery, group fan-out delivery, and
  Android force-stop background-isolate cold-start payload.
- `scripts/run_ios_notification_tap_ui_smoke.sh` covers iOS simulator-bound
  notification tap flows for warm/cold 1:1 and warm group rows. The evidence
  gathered for this spec did not show a matching Android OS notification tap
  parity runner in the current reliability discovery output.
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  uses cursor-based group inbox pagination, idempotent message handling,
  receipt/cursor transaction boundaries, stale cursor stop, max page stop,
  history-gap persistence, group reaction replay handling, media descriptors,
  transport sender validation, and authorized source checks for gap repair.
- `lib/core/notifications/active_conversation_tracker.dart`,
  `lib/core/notifications/notification_route_dispatch.dart`,
  `lib/features/conversation/application/chat_message_listener.dart`,
  `lib/features/conversation/presentation/screens/conversation_wired.dart`,
  and `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  show current listener, tracker, notification route, media download, reaction,
  and dispose paths. The code has cleanup hooks, but the current simulator
  evidence does not explicitly assert leak counts or duplicate active
  subscriptions after repeated route changes and notification taps.
- `integration_test/soak_e2e_test.dart` reports message counts, incoming and
  outgoing counts, drain counts, health-check counts, circuit count, recovery
  method, last outgoing transport, and last outgoing status during a 60-minute
  signal-driven loop. `integration_test/relay_chaos_soak_test.dart` wraps the
  same soak when multiple relay addresses are configured. `test/core/resilience/soak_test.dart`
  covers fake-infrastructure stress for 1000 bidirectional messages, 200-message
  inbox drain, 3-user concurrent send batches, and 5000-message bounded count.
  The evidence gathered for this spec did not show soak acceptance that asserts
  runtime ceilings for open streams, active readers, timers, file descriptors,
  DB handles, media jobs, or pending drain jobs.
- Existing Test-Flight-Improv docs already cover adjacent areas:
  `Test-Flight-Improv/47-message-reliability-roadmap.md` defines the durable
  1:1 no-loss bar; `Test-Flight-Improv/65-same-user-multi-device-group-convergence.md`
  defines same-user multi-device group convergence as an existing
  feature-improvement area; `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan.md`
  covers foreground group push drain; `Test-Flight-Improv/73-on-device-push-decrypt-plan.md`
  covers push decrypt behavior; `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`
  covers all-recipient group media parity.

## 5. Scope Clarification

In scope:

- User-visible convergence when the same message, ACK, stream, notification,
  media descriptor, media blob, group event, or reaction reaches the app through
  multiple paths or in a conflicting order.
- 1:1 text, group text, announcement, image, voice, GIF, edit, delete,
  reaction, quote, invite, and dissolve behavior under race and partial-failure
  conditions.
- Foreground, background, cold start, force-stopped, process-killed, resumed,
  stale-stream, and half-open transport states where those states affect what a
  user sees.
- Direct WiFi, relay, simultaneous WiFi-plus-relay, stale stream, relay
  failover, expired relay reservation, inbox-only, and no-route delivery
  contexts as acceptance dimensions.
- Persistence boundaries around local insert, durable queue state, stream
  write, remote receive, ACK receive, notification display, media descriptor
  persistence, media blob persistence, group publish, and restart.
- Resource cleanup that is visible through duplicate messages, duplicate
  notifications, stuck jobs, unbounded backlogs, or degraded sendability.

Explicit non-goals:

- No protocol redesign, cryptographic redesign, relay architecture decision, or
  product policy change.
- No prescribed test file names, framework seams, helper APIs, ownership split,
  or rollout sessions.
- No replacement for existing gates, smoke suites, Test-Flight-Improv docs, or
  benchmark inventories.
- No claim that every possible OS/OEM push behavior is covered. Simulator
  evidence remains the top device-context acceptance layer for this spec unless
  a later release process explicitly asks for a separate manual or device-lab
  layer.
- No expansion of supported media formats, file size limits, notification copy,
  group roles, or same-account sync policy beyond the observable convergence
  expectations listed here.

Accepted ambiguities for the later implementation pass:

- The exact canonical ordering rule for clock-skewed edits, deletes, reactions,
  and live/inbox merge should follow the current product contract or be decided
  in the implementation pass if the product contract is incomplete.
- The exact resource ceilings for long soak runs should be chosen from current
  runtime baselines and platform limits.
- Same-account conflict policy, such as delete-over-edit priority, should use
  the existing product rule where one exists and remain explicit where it does
  not.
- Backlog scale thresholds may use representative production-scale values, but
  the acceptance should include both normal paging and restart-after-partial
  failure behavior.

## 6. Test Cases

### Happy Path

- **SIM-001: simultaneous send race converges to one logical conversation.**
  When two connected users both resume from a partition and send to each other
  at the same time, each user sees the other's message exactly once, the thread
  remains sendable only when a real usable path exists, and no duplicate visible
  reads, ACK effects, or unread increments appear.
- **SIM-002: simultaneous stream opening does not duplicate user-visible state.**
  When both sides can open a chat stream at the same time, the final
  conversation behaves as one logical session: one visible copy per message,
  one terminal send state per local message, and no later close event from an
  abandoned stream removes a message that already succeeded.
- **SIM-003: duplicate path delivery renders once.** When the same envelope is
  delivered through direct WiFi and relay, or through a stale path and a resumed
  path, the receiver sees one message row, one notification effect, and one ACK
  effect for the logical message.
- **SIM-004: half-open transport does not show misleading sendability.** When a
  connection silently stops carrying bytes without a close/reset event, sends do
  not remain pending indefinitely, the app does not keep a plain Online or
  sendable indication that cannot actually send, and the message remains either
  delivered once or queued/failed with a truthful retry state.
- **SIM-005: late and duplicate ACKs are idempotent.** When a message is retried
  on a fallback path and a late ACK later arrives from the abandoned path, the
  sender still sees one terminal delivered state, one delivery event, and no
  resurrection of deleted or superseded local rows.
- **SIM-006: crash recovery is exactly-once across send lifecycle points.**
  After app death or process restart at user-visible send boundaries, the sender
  and receiver converge to one local row and one remote row for the logical
  message, with a truthful delivered, queued, failed, or retryable state.
- **SIM-007: live delivery and inbox drain merge into canonical order.** When a
  receiver reconnects and live messages arrive while old inbox pages are still
  draining, the visible thread ends in stable canonical order without duplicate
  rows, stale bodies, or incorrect unread counts.
- **SIM-008: group membership races converge.** When group sends race member
  removal, invite acceptance, dissolve, re-add, or key rotation, eligible active
  members see the final allowed messages and removed or unauthorized members do
  not see or decrypt post-removal content.
- **SIM-009: large inbox drain resumes without gaps.** When a user drains a
  large paginated backlog and the app fails partway through a later page, restart
  and resume preserve all visible messages exactly once with no skipped IDs and
  no duplicated IDs.
- **SIM-010: OS notification taps route to the same final state on Android and
  iOS.** Warm and cold 1:1 taps, warm and cold group taps, delete-before-open,
  active conversation suppression, and tap-while-another-chat-is-open all route
  to the correct target and render only the latest stored state.

### Edge Cases

- **SIM-011: malformed libp2p stream frames are rejected safely.** Truncated,
  oversized, wrong-sender, wrong-conversation, replayed, unauthorized, bad media
  descriptor, path-traversal media filename, mismatched checksum, and unknown
  protocol-version frames never become visible messages and do not prevent a
  valid peer from sending afterward.
- **SIM-012: inbound stream flood stays bounded.** A malicious or broken peer
  opening many streams or sending frames faster than the app can process does
  not starve normal chats, duplicate readers, exhaust descriptors, or leave the
  app unable to receive from an honest peer.
- **SIM-013: route changes and notification taps clean up old listeners.** After
  repeatedly opening different 1:1 and group conversations through notification
  taps, only the currently visible conversation receives active UI updates and
  messages for previously opened conversations do not render twice.
- **SIM-014: media cancellation and partial transfer remain truthful.** Partial
  upload, partial download, sender crash during upload, receiver crash during
  download, delete-before-upload-completes, checksum mismatch, and cancellation
  after delete never produce a completed media bubble unless the blob and
  descriptor are both valid and durable.
- **SIM-015: process death during push handling is idempotent.** If a background
  push is decrypted or displayed but the app dies before all local state is
  committed, restart from notification tap shows one message, one unread effect,
  and at most one notification effect for the logical message.
- **SIM-016: local persistence failures do not create false delivery.** Disk
  full, DB locked, failed attachment write, failed queue persistence, or local
  DB corruption does not mark a message as locally durable or delivered unless
  the user-visible row and retry state can survive restart.
- **SIM-017: clock skew does not break thread state.** Devices with skewed
  clocks and relay timestamps that differ from both devices still converge on
  the correct message order, delete/edit precedence, reaction state, TTL state,
  and notification preview state after restart.
- **SIM-018: same-account devices resolve conflicts predictably.** Two devices
  for the same logical user sending with the same local nonce, editing and
  deleting the same message, accepting and passing on an invite, or catching up
  after key rotation converge according to one explicit product rule.
- **SIM-019: paginated history remains stable while live updates arrive.** A
  user viewing older thread history does not lose scroll position, duplicate
  rows, or stale quote/reaction/delete state when new live messages and updates
  arrive.
- **SIM-020: announcement and discussion drains stay isolated.** Concurrent
  group discussion and announcement pushes or replays do not cross-route bodies,
  unread counts, notification sounds, or drain state.
- **SIM-021: stale peer identity and address changes remain safe.** A known user
  rotating network address, relay reservation, or peer identity does not cause
  messages to be accepted from an unauthorized peer claiming that user, and does
  not permanently strand sends on stale address-book data.
- **SIM-022: relay service edge cases remain user-safe.** Reservation expiry,
  refused reservation, quota exhaustion, relay restart, relay identity change,
  and relay accepting connections but dropping streams do not lose messages or
  leave permanently misleading online/sendable state.
- **SIM-023: soak runs assert resource ceilings.** Long-running send, resume,
  relay churn, inbox drain, media, and notification activity stays under
  bounded open stream, reader, timer, DB connection, media job, pending drain,
  descriptor, and memory budgets.
- **SIM-024: user actions during recovery remain ordered and deduped.** Sending,
  deleting, accepting invites, opening media, reacting, or navigating while
  inbox recovery is still running produces the same final visible state as if
  the recovery and user action had happened in a stable serial order.
- **SIM-025: notification collapse and update semantics stay current.** Multiple
  messages in one chat, delete/edit after display, group dissolve, and summary
  count updates never route to stale visible content or duplicate unread state.

### Regressions To Preserve

- **Existing 1:1 reliability stays intact.** The current 1:1 reliability gate
  behavior for text, media, voice, retry, resume, offline inbox, and quote/reply
  remains green while race/failure convergence evidence expands.
- **Existing WiFi transport behavior stays intact.** Direct WiFi send/receive,
  ACK timeout, connection pool reuse, idle reconnect, bidirectional sends,
  malformed WebSocket ignore, concurrent sends on one pooled connection, max
  connection recovery, remote close recovery, and WiFi media hash verification
  remain protected.
- **Existing routing and group smoke behavior stays intact.** Local WiFi, relay
  probe, both-sides restart, background/foreground resume, relay failover, group
  publish, group warm send, group bidirectional send, group offline inbox, group
  lifecycle, group discovery timing, key rotation, and multi-member publish
  continue to converge.
- **Existing foreground group push behavior stays intact.** Foreground group
  push still drains the targeted group inbox, media drains once, tampered media
  does not become done, oversized media is rejected, live-first push dedupes,
  background announcement dedupes, and 1:1 foreground push drains only the 1:1
  inbox.
- **Existing notification-open behavior stays intact.** Warm/cold chat opens,
  backlog-before-route behavior, delete-before-open, background edit/delete,
  and relaunch reconstruction of quote/edit/delete/reaction state keep working.
- **Existing durable 1:1 inbox staging stays intact.** Relay rows are not ACKed
  before local staging, malformed rows do not destroy valid rows, and staged
  replay continues to recover after restart.
- **Existing group inbox cursor behavior stays intact.** Cursor persistence,
  stale cursor stop, max page stop, reaction replay, media descriptors,
  transport sender validation, and authorized history-gap repair remain
  correct.
- **Existing media parity stays intact.** Group media still reaches every
  eligible recipient, missing media can recover, stable attachment IDs stay
  stable, and failed/tampered media remains visibly failed rather than silently
  complete.
- **Existing same-user multi-device group behavior stays intact.** Current
  same-user group convergence guarantees remain preserved while additional
  conflict cases become observable.
- **Existing push decrypt fallback behavior stays intact.** Missing keys,
  corrupt ciphertext, tampered signatures, unknown envelope kinds, active
  conversation suppression, same-user multi-device delivery, group fan-out, and
  Android force-stop cold-start payload behavior do not regress.

### Acceptance Evidence Layers

- **Unit evidence is required** for deterministic idempotency, canonical
  ordering, conflict resolution, malformed envelope rejection, persistence
  durability classification, and resource-budget accounting.
- **Integration evidence is required** because the user-visible outcomes span
  transport, repositories, inbox staging, group membership, media descriptors,
  notifications, route dispatch, and conversation rendering.
- **Smoke evidence is required** for broad 1:1, group, notification, media, and
  recovery journeys so the added race/failure evidence does not only pass in
  isolated helper conditions.
- **Simulator evidence is required** for lifecycle, foreground/background,
  notification tap, force-stop, process death, route changes, media rendering,
  and transport state behavior that depends on a mobile runtime context.
