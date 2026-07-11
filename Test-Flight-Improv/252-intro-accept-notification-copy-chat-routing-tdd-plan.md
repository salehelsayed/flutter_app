# 252 - Introduction Acceptance Notification Copy And Chat Routing

Status: implemented — host/relay complete; D1/D2 device acceptance pending
Type: Feature Improvement
Spec: free-text intent (2026-07-10)
Classification: implemented / device-acceptance-pending
Closure tier: device
Review verdict: ready (2026-07-10); core bet confirmed; disposition execute

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-10 11:10 CEST | Evidence Collector / Planner | `introduction_listener.dart`, `introduction_copy.dart`, `introduction_payload.dart`, `send_introduction_use_case.dart`, `background_push_notification_fallback.dart`, `notification_route_target.dart`, `main.dart`, `go-relay-server/inbox.go`, direct tests and gate scripts | Current source confirms generic acceptance copy and unconditional Orbit/Intros routing; the current recognized relay path does not emit the reported `New Message`, but the Dart missing-copy fallback does. No implementation blocker. | Execute RED-first contract, then run host/relay and live OS proof. |
| 2026-07-10 11:18 CEST | Planner / Sufficiency Audit | Live Flutter/ADB/simctl matrix, full-graph relay fallback, tier matrix, plan template, sufficiency checklist | User constraint applied: closure is self-controlled on the physical Pixel and Android emulator, with a controllable simulator as C and no user tap. All checklist gates are structurally satisfied; invalid classification command corrected to canonical completeness/discovery gates. | Offer independent `$tdd-review`, then execute only after acceptance. |
| 2026-07-10 review | Independent counterexample audit / plan revision | `252-review-fixlist.md`, current notification dispatcher, payload codec, fallback, relay producer/consumer, listener sink, gate arrays, and wiring-test precedent | Core direction confirmed. Closed the production-wiring no-op, untested fallback-copy branch, cross-language fixture drift, local-payload precision, local-tap host proof, and device-harness ambiguity. Rejected score-driven ceremony and an unnecessary milestone split. | Execute the revised causal contract. |

## Problem And Evidence

- Behavior to improve: when User A introduces User B to User C, an acceptance
  notification must explain that it is an introduction update. When A taps it,
  the app must open A's existing conversation with B, where introduction status
  messages are already written, rather than opening the potentially empty
  Orbit/Intros surface.
- Impact: the generic notification can be mistaken for a chat message, and the
  current tap destination removes the context needed to understand the update.
- Confirmed current gaps:
  - `buildBackgroundPushFallbackNotification` resolves absent title/body through
    the global `New Message` defaults at
    `lib/features/push/application/background_push_notification_fallback.dart:132-143,242-255`;
    the current test explicitly pins that output for data-only `type=intros` at
    `test/features/push/application/background_push_notification_fallback_test.dart:514-523`.
  - `extractChatPushMetadata` classifies every introduction envelope only as
    `RouteType: "intros"`, ignoring `send` versus `accept`, at
    `go-relay-server/inbox.go:629-642`; `buildPushMessage` consequently uses the
    same `New Introduction / Open Mknoon to review` copy at
    `go-relay-server/inbox.go:314-350`.
  - `NotificationRouteTarget.fromRemoteMessageData` discards the introduction
    `message_id` and maps every `type=intros` push to the unqualified Intros
    target at `lib/core/notifications/notification_route_target.dart:129-160`.
    `main.dart:3836-3847` then always calls `_openIntroOrbitRoute`.
  - The stable envelope ID already carries the missing decision input as
    `<introductionId>::<action>::<senderPeerId>` at
    `lib/features/introduction/domain/models/introduction_payload.dart:208-219`,
    and the relay already forwards it as `message_id` at
    `go-relay-server/inbox.go:347-360`.
  - User B is the introduction `recipientId` by construction at
    `lib/features/introduction/application/send_introduction_use_case.dart:133-183`.
    Introducer-side progress and mutual-acceptance messages are already inserted
    into B's thread at
    `lib/features/introduction/application/introduction_listener.dart:400-419`.
- Existing coverage:
  - `introduction_listener_test.dart:509-610` proves the first and mutual
    acceptance status messages use B's thread and that mutual acceptance has
    role-correct local copy, but it currently expects payload `intros`.
  - `intro_notification_orbit_route_test.dart:80-188` proves the current generic
    Intros target opens Orbit with the Intros filter and persistent navigation.
  - `notification_tap_smoke_test.dart:107-137,680-693` proves generic `intros`
    and group invites prepare by draining the 1:1 inbox and then route to Intros.
  - `go-relay-server/inbox_test.go:722-764` proves the current recognized
    introduction relay notification is generic and omits `sender_id`.
- Missing coverage: no test distinguishes an acceptance notification from an
  incoming introduction, preserves its envelope identity through remote/local
  routing, resolves the introducer's origin thread, or proves the real OS banner
  tap lands on B's chat.
- Refuted findings:
  - Current HEAD's recognized relay introduction path does **not** emit `New
    Message`; it emits `New Introduction / Open Mknoon to review`
    (`go-relay-server/inbox.go:44-45`, locked by
    `go-relay-server/inbox_test.go:722-764`). The observed title is consistent
    with a legacy/missing-copy data push reaching the confirmed Dart fallback,
    or with an older deployed relay, so the plan closes both compatibility
    surfaces without requiring runtime provenance.
  - The current tap destination is not an arbitrary empty app tab: source and
    widget coverage show it is the Orbit route pre-filtered to Intros. It can
    still be empty after the response is processed, so the UX concern remains.
- Unresolved findings: N/A — exact responder-name preview while the app is
  terminated is deliberately deferred below; it is not needed for meaningful,
  truthful acceptance copy or correct routing.
- Affected production, test, and gate files:
  `go-relay-server/inbox.go`,
  `lib/features/push/application/background_push_notification_fallback.dart`,
  `lib/core/notifications/notification_route_target.dart`,
  `lib/features/introduction/domain/models/introduction_payload.dart`,
  new `resolve_introduction_notification_target_use_case.dart` and
  `intro_accept_notification_open_flow.dart` resolver/coordinator files,
  `lib/features/introduction/application/introduction_listener.dart`,
  `lib/main.dart`, their focused tests, `scripts/run_test_gates.sh`, and
  `Test-Flight-Improv/test-gate-definitions.md`, plus a bounded Android-led
  three-party device-proof harness and its discovery registration.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `b95ca8fa8fb8e8d3`;
  `freshness=stale:lib/main.dart`. The reported staleness overlaps unrelated
  received-media work in the dirty tree, so all load-bearing lines above were
  verified in current source rather than refreshing a read-only planning graph.
- Initial query / profile:
  `python3 graphify-arch/tdd_context.py query "introduction acceptance notification for introducer currently displays New Message and notification tap opens intro tab instead of the introducer's originating 1:1 chat; locate notification producer payload fields tap routing symbols tests and gate registrations" --profile tdd --budget 700`
  returned `confidence=broad`.
- Required one-time refinement:
  `python3 graphify-arch/tdd_context.py query "intro_notification_orbit_route_test.dart AppShellController introduction_wired.dart NotificationService acceptance notification payload routes introducer originating conversation by peer public key" --profile tdd --budget 700`
  returned `confidence=anchored`.
- Anchors: `_unreadMessage` ->
  `test/features/push/application/intro_notification_orbit_route_test.dart`;
  `NotificationService` -> `ios/NotificationService/NotificationService.swift`;
  `appShellController` ->
  `test/features/identity/presentation/screens/startup_router_recovery_test.dart`.
- Surfaced proof/gate files:
  `test/features/push/application/intro_notification_orbit_route_test.dart`,
  `lib/main.dart`, `lib/features/feed/application/app_shell_controller.dart`,
  and AUTO `feature-host-all` registration.
- Graph gaps requiring fallback: the compact architecture graph did not surface
  the Flutter fallback-copy seam, introduction listener, stable envelope-ID
  contract, or Go relay push builder. The required full-graph exact-anchor
  fallback, `graphify query "buildPushMessage extractChatPushMetadata go-relay-server/inbox.go" --budget 400`,
  resolved `buildPushMessage()` at `go-relay-server/inbox.go:286`,
  `extractMessageId()` at `:739`, `inbox_test.go`, and the relay community.
  Targeted current-source search then verified the exact action/copy logic and
  the Flutter seams; neither graph was treated as proof.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.
- Independent review query:
  `python3 graphify-arch/tdd_context.py query "Plan 252 counterexamples: _handleNotificationRouteTarget intros branch _openIntroOrbitRoute intro acceptance message_id NotificationRouteTarget.fromPayload coordinator wiring INTRO_TESTS relay extractMessageId background fallback" --profile review --budget 800`
  returned `confidence=anchored`; current source then verified the production
  dispatcher, source-wiring precedent, fallback suppression, mixed-ID relay
  precedence, listener sink, and gate registrations.

## Scope Contract And Guard

Done invariant: an acceptance notification shows the locked action-aware copy,
and an introducer tap deterministically lands in the recipient (User B)
conversation (`finalPeer=peer-B`) whether B or C sent the acceptance.

In scope:

- Give acceptance pushes truthful, role-neutral copy:
  title `Introduction accepted`, body
  `Someone accepted an introduction involving you.`
- Give legacy/data-only `intros` pushes without usable provider copy a safe
  fallback: `Introduction update` / `Open Mknoon to see the latest update.`
- Preserve the stable introduction envelope `message_id` through remote and
  local notification targets.
- After the existing notification-open inbox drain, resolve canonical
  `accept` IDs against the local introduction record. If the local user is the
  introducer, route to `recipientId` (User B); otherwise retain the Intros route.
- Anchor the introducer's local mutual-accept notification to the same canonical
  response ID so warm/local and terminated/remote taps share one decision seam.
- Distinguish the notification sources honestly: the relay emits a remote push
  for each acceptance, while `IntroductionListener` emits its local notification
  only at mutual acceptance (the second accept) when A is alive. Both feed the
  same canonical-accept resolver after notification-open preparation.

Must preserve:

- Incoming `send` introductions and group invites still open Orbit/Intros ->
  `notification_tap_smoke_test.dart` generic-intros/group-invite rows and
  `intro_notification_orbit_route_test.dart` are GREEN sentinels.
- Participant-side acceptance notifications still open Intros; only the local
  introducer is redirected to B's chat -> new resolver role sentinel.
- The first acceptance remains a progress update, not a false `New Connection`
  local notification -> existing
  `introduction_listener_test.dart::introducer-side first accept writes a recipient-thread progress message without a false connection notification`.
- Existing exact local mutual copy (`New Connection` plus role-correct names),
  duplicate suppression, accept/pass delivery, contact creation, and B-thread
  system-message insertion remain unchanged -> `introduction_listener_test.dart`
  and `./scripts/run_test_gates.sh intro`.
- Ordinary 1:1/group notification preview and routing behavior remains unchanged
  -> `notification_route_contract_matrix_test.dart` and
  `notification_tap_smoke_test.dart` sentinels.
- Explicit provider copy remains byte-preserved for both new-introduction and
  introducer mutual-accept Intros fallbacks ->
  `background_push_notification_fallback_test.dart::preserves provided copy for a new-introduction intros fallback`
  and `::preserves provided role-correct copy for an introducer mutual-accept intros fallback`.
- No cleartext responder username or decrypted introduction payload is added to
  FCM/APNs data; only the already-existing stable message ID is interpreted.

Hard `Do not`:

- Do not change accept/pass fan-out, introduction status derivation, retry,
  outbox, relay custody, encryption, contact creation, or system-message text.
- Do not route A to the responder or to User C. The origin thread is always the
  introduction `recipientId` (User B).
- Do not route B or C to A's B-thread rule, and do not turn every `intros` or
  group-invite push into a conversation route.
- Do not expose responder usernames, introduction parties, or plaintext copy in
  the relay envelope, and do not extend server-side decryption.
- Do not redesign native notification delegates/NSE, the Orbit screen, or the
  app shell.
- Do not change foreground Intros behavior in
  `handle_foreground_remote_message_use_case.dart`: the already-open app drains
  and does not perform tap-to-open navigation. Do not change
  `notification_open_dedupe_gate.dart`; it already keys remote opens by the data
  `message_id`, independently of the Intros route identity.

Deferred / accepted difference:

- Showing the exact responder name and full acceptance sentence on a terminated
  app's OS banner is deferred to a dedicated encrypted introduction-preview
  plan. It would require Android background and iOS NSE decryption support plus
  privacy review. Plan 252 instead supplies truthful action-aware copy and then
  opens the exact contextual chat.
- Pass-response notification copy and pass-tap destination remain the existing
  generic Intros behavior; owner is a future pass-notification product request.
- **N/A by product choice:** iOS-as-introducer notification render and tap are not
  required closure. The iOS simulator is only party C; APNs acceptance copy is
  asserted at relay-build time, not rendered or tapped on iOS. Cross-platform
  device closure therefore covers Android introducers only.
- On the second acceptance tap, app-root clears the provider card before the
  awaited Intros drain; replay can then emit the existing local `New Connection`
  mutual-accept notification. Preserve that behavior and classify the distinct
  post-tap local card by title/source, not as a duplicate provider acceptance.

Dependencies:

- `IntroductionPayload.buildEnvelopeMessageId` remains
  `<introductionId>::<action>::<senderPeerId>` and is parsed from the right so
  malformed or legacy IDs fail closed to Intros.
- `prepareNotificationOpen` continues to await the 1:1 inbox drain for Intros
  before route resolution (`prepare_notification_open_use_case.dart:81-84`).
- Remote rollout is backward-compatible: a new client safely falls back to
  Intros when an old relay omits/corrupts `message_id`, and an old client ignores
  the new remote `message_id` while retaining its generic Intros route. Local
  payload compatibility is one-way: a new client still parses bare `intros`, but
  an old client parsing new `intros|message:<canonicalMessageId>` hits the
  catch-all conversation parser and may open a dead conversation. That soft,
  back-navigable downgrade edge is accepted; do not label the anchored local
  encoding strictly backward-compatible.
- No database migration or new persisted field is required.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-01 | A data-only/legacy `type=intros` push with no title/body never displays `New Message`. | `test/features/push/application/background_push_notification_fallback_test.dart::intros fallback without provider copy uses meaningful introduction update copy` | Host application unit / `RemoteMessage` fixture | HEAD returns `New Message / You have a new message` -> `Introduction update / Open Mknoon to see the latest update.` | Remove the route-kind fallback -> TC-01 re-reds on title/body. | `flutter test test/features/push/application/background_push_notification_fallback_test.dart --plain-name 'intros fallback without provider copy uses meaningful introduction update copy'`; append file to `INTRO_TESTS`, AUTO `feature-host-all`. |
| TC-02 | Relay v1 and v2 acceptance envelopes emit role-neutral acceptance copy, select and preserve the exact canonical `message_id`, and expose no responder username. | `go-relay-server/inbox_test.go::TestBuildIntroductionAcceptPushMessage_UsesActionAwareCopyAndStableRouteData` | Go unit / v1 plaintext matching `payload.action:"accept"`; two opaque-v2 canonical accepts; and opaque mixed-ID `{id:"legacy-envelope-id", messageId:"intro-golden::accept::peer-responder"}` | HEAD emits `New Introduction / Open Mknoon to review` -> `Introduction accepted / Someone accepted an introduction involving you.` in data, Android, FCM notification, and APNs alert. The mixed-ID row derives action from and forwards the validated canonical `messageId`, never the legacy `id`. | Hard-code one golden, parse action from one field but forward another, use the legacy `id`, or add `sender_username` -> TC-02 re-reds. | `(cd go-relay-server && go test -count=1 -run 'TestBuildIntroductionAcceptPushMessage' ./... && go test -count=1 -run 'TestParseIntroductionEnvelopeIdentity' ./...)`; package-native registration. |
| TC-02a | Relay introduction action parsing accepts canonical identities from the right and rejects wrong implementations before push construction. | `go-relay-server/inbox_test.go::TestParseIntroductionEnvelopeIdentity_ValidatesCanonicalAction` | Go unit / table with two valid accepts (including an intro ID containing `::`), opaque-v2 canonical `send` and `pass`, and missing/extra-right-segment/unsupported-action IDs | New parser is absent (compile RED) -> valid rows return exact intro/action/sender and every malformed row returns no action. | Use `strings.Contains("::accept::")`, split from the left, accept an extra segment, or implement `action != "send"` -> TC-02a re-reds. | `(cd go-relay-server && go test -count=1 -run 'TestParseIntroductionEnvelopeIdentity' ./...)`; package-native registration. |
| TC-03 | Opaque-v2 canonical `send`/`pass`, malformed canonical IDs, and v1 payload/ID action mismatches keep `New Introduction / Open Mknoon to review`, the `intros` route, and no `sender_id`. | Extend `go-relay-server/inbox_test.go::TestBuildIntroductionPushMessage_UsesIntrosRouteAndGenericCopy` with opaque-v2 `send`/`pass`, malformed-v2-ID, and mismatched-v1 rows | GREEN/preservation sentinel / Go unit table | The current generic path is GREEN for every row -> all remain generic after the action split. | Implement acceptance copy as `action != "send"`, substring-match `::accept::`, or trust mismatched v1 cleartext action -> a negative row re-reds. | `(cd go-relay-server && go test -count=1 ./...)`; package-native registration. |
| TC-04 | Remote `type=intros` with canonical accept `message_id` and its local payload round-trip retain the full message ID. | `test/core/notifications/notification_route_target_test.dart::acceptance intros route preserves envelope identity across remote and local payloads` | Host unit / map and payload strings | HEAD returns `messageId == null` and serializes `intros` -> anchored Intros target round-trips the exact ID. | Drop `messageId` in `fromRemoteMessageData` or `toPayload` -> TC-04 re-reds. | `flutter test test/core/notifications/notification_route_target_test.dart`; append file to `INTRO_TESTS`, AUTO `core-host-all`. |
| TC-05 | Legacy/malformed Intros IDs and group invites remain unanchored Intros, never guessed conversations. | `test/core/notifications/notification_route_target_test.dart::malformed acceptance identity and group invite fail closed to generic intros` | Host unit / malformed table | Generic Intros/group invite behavior is GREEN on HEAD -> remains unqualified Intros. | Treat any `message_id` or group invite as an acceptance anchor -> TC-05 re-reds. | Same direct command as TC-04; `INTRO_TESTS` + AUTO `core-host-all`. |
| TC-06 | Canonical introduction message IDs build and parse action/intro/sender from the right; missing segments and unsupported actions are rejected. | `test/features/introduction/application/introduction_payload_test.dart::builds the relay golden and parses canonical envelope identity while rejecting malformed ids` | Host domain unit / paired golden plus malformed table | HEAD builder returns the literal `intro-golden::accept::peer-responder` while the parser is absent (compile RED) -> the same literal consumed by TC-02 parses exactly; `send/accept/pass` are accepted and malformed inputs return null. | Drift the builder delimiter, accept two-segment IDs, or split from the left without validation -> TC-06 re-reds. | `flutter test test/features/introduction/application/introduction_payload_test.dart`; append file to `INTRO_TESTS`, AUTO `feature-host-all`. |
| TC-07 | After drain, introducer A resolves either B-accept or C-accept for the same introduction to conversation B (`recipientId`). | `test/features/introduction/application/resolve_introduction_notification_target_use_case_test.dart::introducer accept routes to recipient thread for either responder` | Host application unit / fake intro, identity, and contact repositories | New use case is absent (compile RED) -> both responder variants return `conversation(peer-B)`. | Return `senderPeerId` or `introducedId` instead of `recipientId` -> TC-07 re-reds. | `flutter test test/features/introduction/application/resolve_introduction_notification_target_use_case_test.dart`; new file appended to `INTRO_TESTS`, AUTO `feature-host-all`. |
| TC-08 | Participants, `send`/`pass`, missing intro rows, missing B contact, and malformed IDs fall back to the original Intros target instead of a wrong/dead chat. | `resolve_introduction_notification_target_use_case_test.dart::non-introducer and unresolved response targets fail closed to intros` | Host application unit / fake table | New use case is absent (compile RED); current dispatcher is generic Intros -> guarded resolver returns Intros for every non-qualified case. | Remove own-role/contact/action checks -> TC-08 re-reds. | Same direct/new-file registration as TC-07. |
| TC-09 | Remote and local anchored notification dispatch drain first, then the shared coordinator opens B, preserves the tap timestamp, and does not call the Orbit/Intros callback for introducer acceptance. | `test/features/push/application/intro_accept_notification_open_flow_test.dart::remote and local introducer accepts drain then open the recipient conversation` | Host integration / real remote-data and TC-04 local-payload dispatch plus fake repos/callback recorder | New anchored flow is absent (compile/assertion RED); HEAD generic path routes Intros -> both remote data and the TC-04 anchored local payload produce ordered `prepare, drain, resolve, conversation:peer-B`, with no `intros`, and the conversation callback receives the original non-null `notificationTappedAt`. The intro is seeded only by the drain callback. | Resolve before drain, clear the tap timestamp before redirect, skip the local codec path, or bypass the resolver -> TC-09 re-reds. | `flutter test test/features/push/application/intro_accept_notification_open_flow_test.dart`; new file appended to `INTRO_TESTS`, AUTO `feature-host-all`. |
| TC-09b | The production `_handleNotificationRouteTarget` Intros case invokes the shared coordinator and no longer unconditionally invokes `_openIntroOrbitRoute`. | `test/core/notifications/intro_accept_open_coordinator_wiring_test.dart::main intros branch wires the accept open coordinator` | Host source-wiring lock / scope `lib/main.dart` text to the Intros case body | HEAD Intros branch contains unconditional `await _openIntroOrbitRoute(...)` -> the branch contains the coordinator call and no unconditional Orbit call. | Revert only `main.dart` to `_openIntroOrbitRoute` while leaving coordinator/resolver tests GREEN -> TC-09b re-reds. | `flutter test test/core/notifications/intro_accept_open_coordinator_wiring_test.dart`; append file to `INTRO_TESTS`, AUTO `core-host-all`. |
| TC-10 | Only the introducer's local mutual-accept notification keeps exact current copy while carrying the canonical accept anchor for the shared A->B route. | Update `test/features/introduction/application/introduction_listener_test.dart::introducer-side mutual acceptance writes a recipient-thread connection message and a role-correct notification` and its participant sibling | Host application unit / existing fake listener repos | HEAD payload is literal `intros` -> when `isIntroducer && responderId != null`, payload becomes the TC-04 anchored Intros form while title/body/system message stay byte-equal; non-introducer and missing-responder notifications remain bare `intros`. | Restore payload `intros`, anchor the shared sink unconditionally, or alter exact copy -> TC-10 re-reds. | `flutter test test/features/introduction/application/introduction_listener_test.dart`; already in `INTRO_TESTS`. |
| TC-11 | Generic incoming introduction/group-invite opens still use Orbit/Intros; first accept emits no false local `New Connection`; explicit Intros provider copy remains unchanged. | Existing `intro_notification_orbit_route_test.dart`, `notification_tap_smoke_test.dart::group_invite -> intros`, listener first-accept test, and the two named provider-copy fallback tests | GREEN sentinels / host widget + integration/application fakes | GREEN on HEAD -> remain GREEN. | Route all Intros to chat, notify first accept as a connection, or overwrite provided copy -> a named sentinel re-reds. | `flutter test test/features/push/application/intro_notification_orbit_route_test.dart test/integration/notification_tap_smoke_test.dart test/features/introduction/application/introduction_listener_test.dart test/features/push/application/background_push_notification_fallback_test.dart`; existing AUTO/`INTRO_TESTS` plus TC-01 registration. |
| TC-12 | Physical Pixel as A: emulator B's and simulator C's relay-backed acceptances each show acceptance copy; an automated Android notification tap opens A-B and emits the corresponding machine-readable status context. | `integration_test/intro_accept_notification_android_proof_test.dart` via `run_intro_accept_notification_android.dart::physical_introducer` | Three-party physical Android + Android emulator + iOS simulator / real relay and OS notification | Device-only proof; current source/test contracts predict generic copy + Orbit/Intros -> both automated taps open B's chat and emit `finalPeer=peer-B`, first `statusContext=b_accept_recorded`, then `statusContext=bc_connected`, with no `New Message`. | Route by responder or restore generic copy -> D1 fails its notification-card and final-marker assertions. | `_proof_test.dart` is recognized by `run_test_gates.sh::classify_path`; register runner/test in `check_reliability_simulation_discovery.sh` under intro and require `--list-scenarios` to show `physical_introducer`. |
| TC-13 | Android emulator as A proves the same two acceptance notifications, bounded automated taps, and route/status markers, while the physical Pixel acts as B and a simulator acts as C. | `integration_test/intro_accept_notification_android_proof_test.dart` via `run_intro_accept_notification_android.dart::emulator_introducer` | Three-party Android emulator + physical Android + iOS simulator / real relay and OS notification | Device-only proof; current source/test contracts predict generic copy + Orbit/Intros -> both automated taps open B's chat with the same `finalPeer` and `statusContext` markers as TC-12. | Drop anchored `message_id`, bypass the Dart resolver, or make the proof depend on manual taps/visual text judgment -> D2 fails. | Same concrete proof/discovery registration; `--list-scenarios` must show `emulator_introducer`. |

### Test Notes

- TC-02 must cover both v1 plaintext and v2 opaque envelopes with the exact
  top-level golden `intro-golden::accept::peer-responder`; the v1 fixture also
  carries `payload.action:"accept"`. TC-06 independently locks
  `buildEnvelopeMessageId(introductionId:'intro-golden', action:'accept', senderPeerId:'peer-responder')`
  to that same literal. The relay may read `payload.action` for v1 and the
  canonical top-level message ID for v2, but it must not inspect or expose
  encrypted responder data.
- TC-03 makes malformed and mixed inputs fail closed. For v1, acceptance copy
  requires the cleartext `payload.action` to agree with the validated canonical
  top-level ID; for v2, only that canonical ID supplies the action. Legacy or
  conflicting inputs retain generic copy and generic Intros routing.
- TC-02's mixed top-level `id`/`messageId` row locks an intro-specific rule:
  prefer a validated canonical `messageId` and use that same value for both the
  action decision and forwarded push `message_id`. If it is absent/invalid,
  preserve the existing generic `extractMessageId` result for route identity but
  keep generic copy. Do not change global `extractMessageId` precedence.
- TC-07 must use the same introduction twice with message IDs ending in
  `::accept::peer-B` and `::accept::peer-C`; the expected route is `peer-B` in
  both cases. This discriminator prevents the tempting but wrong "open the
  responder" implementation.
- TC-09 seeds the introduction only during the drain callback. Resolving before
  that callback therefore fails causally and cannot pass on pre-seeded state.
  It must run both the remote-data and local `fromPayload` entry paths; TC-10's
  string assertion alone is not proof that a warm/local tap reaches B.
- TC-09b is intentionally a narrow source-wiring lock because `main.dart`'s
  private dispatcher cannot be invoked by the exported Orbit widget test. Scope
  the read to the Intros case body so `_openIntroOrbitRoute` in the group fallback
  cannot create a false match.
- TC-12/13 execute B-accept first and C-accept second, terminating A before each
  acceptance to force relay custody/push instead of a direct foreground event.
  On Android, the runner backgrounds A, executes `adb -s <A> shell am kill
  com.mknoon.app`, and requires `adb -s <A> shell pidof com.mknoon.app` to be
  empty before the acceptance and again after the card arrives/before the tap.
  It must never use `am force-stop`: that cancels notifications and puts the
  package in the stopped state, making the push/tap boundary unfaithful.
  Before either scenario, the runner must prove that `adb shell dumpsys
  notification` exposes the exact title/body for a relay-built card. If it does
  not, switch the copy assertion to a bounded UIAutomator XML content-text read.
  For the tap, expand the shade, locate a node for this app whose text contains
  the exact title `Introduction accepted`, derive its bounds, and tap the node
  center; fixed screen coordinates are forbidden. Test-only markers expose
  `finalPeer=peer-B` plus `statusContext=b_accept_recorded` or
  `statusContext=bc_connected`; no rendered-text judgment or human tap is
  acceptance evidence.

## Implementation Steps

1. Snapshot `git status --short` and preserve all unrelated received-media,
   Graphify, localization, and settings changes. Add TC-01, TC-02/02a/03, TC-04,
   TC-06, TC-07, TC-09, TC-09b, and TC-10 assertions before production edits.
   Record their actual causal REDs; do not reinterpret compile RED as behavioral
   RED.
2. Add a small validated envelope-message identity parser beside
   `IntroductionPayload.buildEnvelopeMessageId`. Parse from the right, accept
   only `send`, `accept`, and `pass`, and return null for legacy/malformed IDs.
   Stop-if: current delivery tests disprove the canonical top-level ID on either
   v1 or v2; repair the existing envelope-normalization contract before routing.
3. Extend `NotificationRouteTarget.intros` to optionally retain `messageId`.
   `toPayload` must encode an anchored target exactly as
   `intros|message:<canonicalMessageId>`, mirroring the existing group marker,
   and `fromPayload` must prefix-parse that form back to anchored Intros while
   still exact-matching bare `intros`. Make `type=intros` remote data retain
   `message_id`. Leave group-invite and bare `intros` targets unanchored, and
   preserve the documented soft old-build local-payload downgrade edge.
4. Extend relay `chatPushMetadata` with validated introduction action metadata.
   Emit action-aware, role-neutral copy for `accept` only; preserve incoming
   `send`, pass, FCM/APNs visibility, `message_id`, and privacy fields. For v1,
   require `payload.action` to agree with the validated canonical top-level ID;
   for v2, derive action only from that ID. Malformed, unsupported, or
   conflicting action evidence fails closed to generic introduction copy.
   Introduction metadata must prefer a validated canonical top-level
   `messageId` over a coexisting legacy `id`, and the one selected value must
   drive both action copy and forwarded `data["message_id"]`. If no canonical
   `messageId` validates, preserve existing generic `extractMessageId` routing
   identity with generic copy; do not change global ID precedence.
   Stop-if: a real recorded v2 opaque introduction envelope does not expose a
   validated intro-specific `<introId>::accept::<senderPeerId>` identity; repair
   the envelope contract instead of guessing an action from ciphertext or
   changing global `extractMessageId` semantics.
5. Make the Dart background fallback choose route-aware introduction defaults
   before global message defaults. Every data-only Intros fallback without
   provider copy uses the locked generic `Introduction update` / `Open Mknoon to
   see the latest update.` copy. Do not add an accept-ID-specific fallback-copy
   branch: the relay already supplies a visible notification block for Intros,
   and Step 4 makes that relay path the sole owner of acceptance copy, so the
   Dart branch would be unexercised production surface. Preserve explicit
   provider title/body byte-for-byte.
6. Add `resolveIntroductionNotificationTarget` in
   `lib/features/introduction/application/resolve_introduction_notification_target_use_case.dart`.
   It may return B's conversation only when the target is a
   canonical `accept`, the intro exists after drain, the local identity is the
   introducer, and B still resolves as a contact; otherwise return Intros.
7. Add one shared open coordinator in
   `lib/features/push/application/intro_accept_notification_open_flow.dart` and
   invoke it at the single
   `_handleNotificationRouteTarget` Intros case in `main.dart`. It calls the
   resolver after existing preparation, reuses the existing conversation
   open/active-route guard, and calls `_openIntroOrbitRoute` for every fallback.
   Do not execute the branch's current eager `_notificationTappedAt = null`
   before resolution: snapshot the timestamp, pass it through the conversation
   redirect, and clear it exactly once after the chosen conversation or Orbit
   outcome, matching the existing conversation/group branches.
   Do not wrap individual warm call sites: initial remote open from
   `startup_router.dart`, warm/background remote taps, initial local launch, and
   warm local taps all converge on this dispatcher branch. Lock that production
   call with TC-09b.
   Stop-if: wiring requires a second inbox drain or bypasses
   `_handleNotificationRouteTarget`'s existing conversation guard; rework the
   coordinator instead of duplicating navigation.
8. The mutual-accept branch has one shared `showNotification` sink for introducer
   and participant copy. Change its payload to canonical anchored Intros only
   when `isIntroducer && responderId != null`; otherwise keep bare `intros`.
   Keep exact title/body and all participant/incoming behavior unchanged.
9. Append the newly causal Dart files named in TC-01/04/06/07/09/09b to
   `INTRO_TESTS` and mirror the canonical list in
   `Test-Flight-Improv/test-gate-definitions.md`. While mirroring, also reconcile
   the current documentation omission of existing
   `introduction_b_to_a_c_precondition_test.dart`, which is already in the live
   `INTRO_TESTS` array. Add a bounded app-side proof target
   `integration_test/intro_accept_notification_android_proof_test.dart`
   plus `run_intro_accept_notification_android.dart` orchestrator that
   reuses the existing intro E2E setup/config channel, controls the Android
   lifecycle/notification shade through `adb`, controls the third iOS simulator
   through `simctl`, emits redacted artifacts, and supports
   `--list-scenarios`. Keep the `_proof_test.dart` suffix so
   `scripts/run_test_gates.sh::classify_path` accounts for the device target,
   and register the test, runner, and both scenarios in
   `scripts/check_reliability_simulation_discovery.sh`. Go relay tests remain
   package native. For each acceptance the runner must background A, use `am
   kill` on the explicitly pinned Android ID, and verify `pidof` is empty before
   send and before tap; `am force-stop` is forbidden. The runner must perform
   the dumpsys-content feasibility probe,
   fall back to bounded UIAutomator XML text extraction when necessary, use an
   exact-title notification-node selector for taps, and emit the TC-12/13
   route/status markers. Stop-if: the runner needs user interaction, fixed
   screen-coordinate taps, rendered-text judgment, or a production-only debug
   bypass; keep the causal host/relay plan executable and redesign the harness.
10. Run focused GREEN, mutation re-red, full relay package tests, the named
    intro gate, notification-route sentinels, analyzer/diff hygiene, then D1 and
    D2 on explicitly rediscovered targets.

## Risks And Blind Spots

- Race between notification open and inbox materialization -> TC-09 seeds the
  intro only inside the awaited drain and requires drain-before-resolve order.
- Forgot-to-wire production no-op -> TC-09b fails if the private `main.dart`
  Intros branch keeps calling Orbit even when the coordinator is correct in
  isolation.
- Tap-context loss on redirect -> TC-09 requires the original non-null
  `notificationTappedAt` to reach the conversation open callback instead of
  being cleared by the old Intros branch before resolution.
- Wrong chat when C is the second responder -> TC-07 requires both B-accept and
  C-accept to resolve to recipient B.
- Missing/stale local data can produce a dead tap -> TC-08 requires a visible
  Intros fallback rather than a silent missing-contact conversation route.
- Compatibility with old relays/local notifications -> TC-01, TC-04, and TC-05
  prove new-client fallback. The accepted old-build/new-local-payload downgrade
  can open a dead conversation but is ephemeral and back-navigable; remote old
  clients retain generic Intros routing.
- Privacy regression from pursuing exact copy -> TC-02 asserts no cleartext
  responder identity; exact-name preview is explicitly deferred.
- Device automation fragility -> TC-12/13 require bounded notification-node
  discovery, explicit target IDs, route markers, and zero user interaction; a
  coordinate-only tap without UIAutomator verification is not acceptance proof.
- Lifecycle / derived-state durability: no new state is persisted. Existing
  intro/outbox/contact durability is untouched; TC-09 proves the resolved route
  consumes post-drain repository truth.
- Sibling-surface consistency: TC-11 preserves incoming intro and group-invite
  Orbit behavior; TC-08 and TC-10 preserve participant behavior; foreground
  drain and notification-open dedupe remain explicitly out of scope.
- Destructive-action side effects: N/A — no destructive action or schema write
  is added.
- Invariant re-verification under new transitions: TC-07, TC-09, and D1/D2
  jointly prove `accept -> drain -> resolve A role -> recipient B -> existing
  conversation guard` for warm/local and cold/remote boundaries.

## Acceptance Gates

```bash
# Snapshot before execution; record and preserve unrelated changes.
git status --short

# First causal RED before production edits; expect non-zero because HEAD says
# "New Message" for a data-only intros push with missing provider copy.
flutter test test/features/push/application/background_push_notification_fallback_test.dart --plain-name 'intros fallback without provider copy uses meaningful introduction update copy'

# Focused Dart GREEN; expect exit 0 and zero failed tests.
flutter test \
  test/features/push/application/background_push_notification_fallback_test.dart \
  test/core/notifications/notification_route_target_test.dart \
  test/core/notifications/intro_accept_open_coordinator_wiring_test.dart \
  test/features/introduction/application/introduction_payload_test.dart \
  test/features/introduction/application/resolve_introduction_notification_target_use_case_test.dart \
  test/features/push/application/intro_accept_notification_open_flow_test.dart \
  test/features/introduction/application/introduction_listener_test.dart

# Relay contract GREEN; expect exit 0 and zero package failures.
(cd go-relay-server && go test -count=1 ./...)

# Preservation: generic Intros/group-invite routing and existing Orbit surface.
flutter test \
  test/features/push/application/intro_notification_orbit_route_test.dart \
  test/integration/notification_tap_smoke_test.dart \
  test/core/notifications/notification_route_contract_matrix_test.dart

# Registration check: completeness must classify every newly pinned/proof path,
# discovery must list both Android proof scenarios, and the named gate exits 0.
./scripts/run_test_gates.sh completeness-check
./scripts/check_reliability_simulation_discovery.sh
./scripts/run_test_gates.sh intro

# Auto-glob companions; expect exit 0 and no omitted focused tests.
./scripts/run_host_test_gates.sh feature-host-all
./scripts/run_host_test_gates.sh core-host-all

# Touched Dart hygiene; expect exit 0 and no issues. Repository-wide analyzer
# debt remains a rollout/release concern rather than a per-plan false blocker.
for path in \
  lib/main.dart \
  lib/core/notifications/notification_route_target.dart \
  lib/features/introduction/application/introduction_listener.dart \
  lib/features/introduction/application/resolve_introduction_notification_target_use_case.dart \
  lib/features/introduction/domain/models/introduction_payload.dart \
  lib/features/push/application/background_push_notification_fallback.dart \
  lib/features/push/application/intro_accept_notification_open_flow.dart \
  test/core/notifications/intro_accept_open_coordinator_wiring_test.dart \
  test/core/notifications/notification_route_target_test.dart \
  test/features/introduction/application/introduction_listener_test.dart \
  test/features/introduction/application/introduction_payload_test.dart \
  test/features/introduction/application/resolve_introduction_notification_target_use_case_test.dart \
  test/features/push/application/background_push_notification_fallback_test.dart \
  test/features/push/application/intro_accept_notification_open_flow_test.dart \
  integration_test/intro_accept_notification_android_proof_test.dart \
  integration_test/scripts/run_intro_accept_notification_android.dart; do
  dart analyze "$path" || exit 1
done
git diff --check
```

Device D1/D2 use the explicit self-controlled commands and checkpoints in the next
section after the test relay is running the Plan 252 relay build.

## Device/Relay Proof Profile

- Profile: `os-notification-device-lab`, three parties, real relay, physical and
  emulated Android introducer legs; no user interaction.
- Boundary being proven: a real relay-built Android FCM notification shows the
  intended copy, survives a terminated-app tap, drains/materializes the
  acceptance, and lands the introducer in B's real 1:1 conversation. Host tests
  cannot prove provider rendering, native callback delivery, or OS tap launch.
- Explicit boundary limitation: iOS-as-introducer render/tap is **N/A by
  choice**. The iOS simulator participates only as C. TC-02 asserts APNs payload
  construction, but no real iOS card or `didReceiveResponse` tap is exercised;
  device closure is Android-introducer closure, not cross-platform tap parity.
- Live availability check (2026-07-10 11:10 CEST):
  `flutter devices --machine`, `adb devices`, and
  `xcrun simctl list devices available -j` found physical Pixel 6
  `21071FDF600CSC`, physical iPhones
  `00008150-001C3C6A3684401C`, `00008110-00184D622289801E`, and
  `00008030-001A6D2801BB802E`, Android emulator `emulator-5554`, plus multiple
  available iOS 26.5 simulators. Re-run discovery at execution and substitute
  only explicitly listed live IDs; an unavailable target is N/A, not a blocker,
  under project policy.
- Required setup: install the client build on the physical Pixel, Android
  emulator, and one booted iOS simulator; point all at a staging/test relay
  running the Plan 252 relay binary; register real Android push tokens; create
  A/B/C identities; make A-B and A-C contacts; and initiate A's B-to-C
  introduction from A-B chat through the existing test-only intro E2E config
  channel. The orchestrator, not the user, performs all setup/actions/taps.
- D1 assignment: A=`21071FDF600CSC` (physical Pixel 6), B=`emulator-5554`,
  C=`674DFFF6-5F38-4235-93F6-AF7FBF86AE65` (available iPhone 17 Pro simulator;
  boot explicitly before use).
- D2 assignment: A=`emulator-5554`, B=`21071FDF600CSC`,
  C=`674DFFF6-5F38-4235-93F6-AF7FBF86AE65`.
- The physical iPhones are not part of required closure. They remain optional
  follow-up only; Plan 252 must not wait for the user to operate them.
- Closure role: required closure evidence when those targets remain available;
  an absent platform leg is recorded `N/A (target unavailable by project
  policy)` and does not block the host/relay verdict.
- `FLUTTER_DEVICE_ID`: host selector only; it is insufficient for the
  three-party proof because all three IDs and the Android `adb` control channel
  are required.
- Registration: `integration_test/intro_accept_notification_android_proof_test.dart`
  (device proof recognized by `run_test_gates.sh::classify_path`) plus
  `integration_test/scripts/run_intro_accept_notification_android.dart` with
  `physical_introducer` and `emulator_introducer`; add both to the canonical
  reliability discovery inventory under `intro` as device-proof scenarios.
- Discovery command:
  `dart run integration_test/scripts/run_intro_accept_notification_android.dart --list-scenarios && flutter devices --machine && adb devices && xcrun simctl list devices available`
  -> both scenarios and every used target ID must be listed immediately before
  execution.
- Closure procedure enforced by the orchestrator for each assignment:
  1. Boot/install/configure all three targets and start timestamped
     Flutter/native/relay logs. Clear stale app notification cards and require
     that no `Introduction accepted` card remains before the first acceptance.
  2. Background A, run `adb -s <A> shell am kill com.mknoon.app`, require
     `pidof com.mknoon.app` to be empty, then have B accept. After the card
     arrives, require `pidof` empty again. Probe whether `dumpsys notification`
     exposes the card's literal title/body; if not, select the bounded
     UIAutomator XML content-text reader for both acceptance legs. Assert title
     `Introduction accepted`, body
     `Someone accepted an introduction involving you.`, and no `New Message`.
  3. Expand the Android shade; select this app's notification node whose text
     contains exact title `Introduction accepted`, derive its bounds, and tap
     its center. Assert A cold-launches into A-B, not Orbit/Intros, with
     `finalPeer=peer-B` and `statusContext=b_accept_recorded`.
  4. Repeat the background + `am kill` + pre-send/pre-tap empty-`pidof` sequence
     before C accepts. Repeat the copy assertion and bounded node tap. Assert
     A-B opens again with `finalPeer=peer-B` and
     `statusContext=bc_connected`. A subsequent local `New Connection` card from
     drain replay is preserved behavior and must be source/title-classified, not
     counted as a duplicate `Introduction accepted` provider card. Never
     substitute `am force-stop`.
  5. Capture redacted screenshots plus logs proving two distinct canonical
     `message_id` values, relay push send, notification-open callback, inbox
     preparation, and final conversation peer B, with zero navigation errors.
- Closure commands (after rediscovery and booting C):
  `dart run integration_test/scripts/run_intro_accept_notification_android.dart --scenario physical_introducer --introducer 21071FDF600CSC --recipient emulator-5554 --introduced 674DFFF6-5F38-4235-93F6-AF7FBF86AE65`
  and
  `dart run integration_test/scripts/run_intro_accept_notification_android.dart --scenario emulator_introducer --introducer emulator-5554 --recipient 21071FDF600CSC --introduced 674DFFF6-5F38-4235-93F6-AF7FBF86AE65`.
  Each must exit 0 with a copy-extractor feasibility PASS, two acceptance-copy
  PASS markers, two bounded-node-tap PASS markers, two `finalPeer=peer-B`
  markers, the two expected `statusContext` markers, zero navigation errors,
  and a redacted artifact directory. No prompt for user action is allowed.
- Deferred device work: exact-name encrypted preview is owned by the future
  preview plan; unavailable OS/hardware versions are N/A by project policy.

## Execution Interpretation And Done Criteria

- Expected RED: TC-01 fails on `New Message`; TC-02 fails on generic relay copy;
  TC-04 fails because Intros drops `message_id`; TC-06/07/09 initially compile
  red until their new contracts are scaffolded; TC-09b fails because the
  production branch is still wired directly to Orbit; TC-10 fails on payload
  `intros`.
- Green sentinel: TC-03 and TC-11 preserve send/pass copy, incoming-intro,
  group-invite, first acceptance, explicit fallback copy, and current exact
  mutual-accept copy behavior.
- Pre-existing dirty tree / known failure: planning observed extensive unrelated
  received-media Plan 229 implementation, plan/index edits, Graphify artifacts,
  localization/settings/media files, and unrelated `lib/main.dart` edits. Do not
  revert or absorb them; record any actual baseline failure before Plan 252.
- Environment blocker: none at planning time. The live matrix supports both D1
  and D2. Later unavailable targets are N/A under project policy, not evidence
  gaps.
- Scope drift: any need for new DB state, cleartext responder identity, NSE
  decryption, accept fan-out changes, a second inbox drain, or routing A to the
  responder instead of B blocks execution and requires replanning.

- [x] Every behavior has a named test or justified proof.
- [x] Causal RED, focused GREEN, and representative mutation re-red are
      recorded.
- [x] Relay, preservation, named intro, and auto-glob gates pass with zero
      failures or an exact pre-existing baseline classification
      (background_choice_control_test.dart 2 failures pre-existing at HEAD
      from the 221/248 background workstream; sqlite3 native-asset fetch
      failure environmental, file green in isolation).
- [x] `INTRO_TESTS` and gate documentation registration are implemented and
      synchronized, including the pre-existing documented-list omission, and
      completeness-check classifies every newly pinned/proof path (1106/1106).
- [ ] D1 and D2 pass on available targets, or an unavailable leg is recorded
      N/A exactly as project policy requires. — PENDING: all three targets are
      live and the self-controlled harness + discovery registration are
      complete, but the campaign requires a staging relay running the Plan 252
      relay binary; relay redeploy is a user-owned deployment decision and the
      device pool is shared with other live sessions.
- [x] Touched-file `flutter analyze` has no issues; `git diff --check` is clean.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command:
  `flutter test test/features/push/application/background_push_notification_fallback_test.dart --plain-name 'intros fallback without provider copy uses meaningful introduction update copy'`.
- Preservation command:
  `flutter test test/features/push/application/intro_notification_orbit_route_test.dart test/integration/notification_tap_smoke_test.dart test/core/notifications/notification_route_contract_matrix_test.dart`.
- Manual registration: none. Harness registration: append the six Dart paths
  named in Steps 9/TC-01, 04, 06, 07, 09, and 09b to `INTRO_TESTS`; mirror the
  full live array in `Test-Flight-Improv/test-gate-definitions.md`; keep the new device target
  `_proof_test.dart`-classified; and register the D1/D2 runner/test/scenarios in
  reliability discovery. No manual-user checkpoint remains.
- Migration: none; no DB version or persisted schema change.
- Boundary closure: Go relay package GREEN plus availability-bounded,
  self-controlled D1 physical-Android-introducer and D2
  emulator-Android-introducer notification/tap proof. iOS-as-introducer
  render/tap remains explicit N/A by choice, not implied parity.
- Unresolved product evidence: none. Runtime provenance of the originally
  observed `New Message` is unnecessary because TC-01 covers the confirmed
  missing-copy fallback and TC-02 covers recognized acceptance pushes. Final
  device closure remains blocked on a staging relay running the Plan-252 build
  and an uncontended available Android pair, as recorded below.
- Independent `$tdd-review` is complete; the source-grounded deltas are included
  above and no unresolved user-owned decision remains.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plan | contract extraction |
| 2026-07-10 13:05 CEST | RED contract | all TC-01..10 test files + inbox_test.go | TC-01 focused run -> FAIL `Expected: 'Introduction update' / Actual: 'New Message'`; `go vet` -> `undefined: parseIntroductionEnvelopeIdentity` | TC-04 behavioral RED (messageId null), TC-05 behavioral RED (catch-all coerced malformed local anchor to conversation), TC-09b RED (branch still Orbit), TC-06/07/08/09 compile RED, TC-10 RED on payload `intros` | none | production edits |
| 2026-07-10 13:15 CEST | GREEN + mutation | payload parser, route target, fallback, resolver, coordinator, listener, main.dart, inbox.go | focused Dart 7-file run -> `+100 All tests passed`; `(cd go-relay-server && go test -count=1 ./...)` -> ok | Mutation A (drop remote intros anchor) re-red TC-04; Mutation C (route responder not recipient) re-red TC-07; Go mutation (accept any non-empty action) re-red TC-02a; all reverted, suites re-green | none | harness + registration |
| 2026-07-10 13:25 CEST | registration + gates | run_test_gates.sh INTRO_TESTS(+6), test-gate-definitions.md (mirror + pre-existing b_to_a_c omission reconciled), check_reliability_simulation_discovery.sh, runner + proof test + artifact helper | `completeness-check` -> 1106/1106 PASS; discovery -> PASS listing both 252 scenarios; `run_test_gates.sh intro` -> +285 All tests passed; preservation trio -> +110 passed; touched-file `dart analyze` -> no issues; `git diff --check` -> clean | `--list-scenarios` emits `physical_introducer`/`emulator_introducer` | none | host-all globs + D1/D2 |
| 2026-07-10 13:40 CEST | device tier | integration_test/intro_accept_notification_android_proof_test.dart, integration_test/scripts/run_intro_accept_notification_android.dart | live matrix rediscovered: `21071FDF600CSC`, `emulator-5554`, booted `674DFFF6-5F38-4235-93F6-AF7FBF86AE65` | full self-controlled orchestrator implemented (am-kill+pidof boundary, dumpsys/UIAutomator feasibility probe, bounded exact-title node tap, logcat `finalPeer`/`statusContext` markers, redacted artifacts) | D1/D2 PENDING: requires a staging relay running the Plan 252 relay binary (relay redeploy is a user-owned deployment decision) and an uncontended device pool (other live sessions share this host) | run D1 then D2 via the closure commands once the 252 relay build is on the test relay |
| 2026-07-10 16:40 CEST | auto-glob gates | feature-host-all, core-host-all | fail-fast sweep: files #1-#644 PASS; abort at #645 `show_notification_use_case_test.dart` was an environmental sqlite3 native-asset fetch (`Failed host lookup: github.com`) and the file PASSES in isolation (+36); alphabetical tail (`push`..`theme`, 646 tests) re-run separately | tail shows 2 failures, both `test/features/settings/presentation/widgets/background_choice_control_test.dart` (missing Signal background description copy) — pre-existing at HEAD from the parallel 221/248 background workstream, zero overlap with 252 surfaces; exact baseline classification recorded | a concurrent session's mid-sweep `pub get`/clean killed one full-sweep attempt (shared-tree contention); segmented coverage is complete and equivalent | core-host-all completion |
| 2026-07-10 17:15 CEST | gates complete | - | `core-host-all` -> 296/296 PASS, `PASS: host tests completed for scope: core-host-all` | all host/relay/gate tiers GREEN or exact-baseline-classified; done criteria updated | none | surgical commit (252-scope files only on the shared dirty tree); D1/D2 remain pending the 252 relay build on the test relay |
