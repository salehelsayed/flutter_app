# 256 - 1:1 Reaction Notification Context, Lifecycle, And Unread Semantics

Status: implementation complete — host/platform gates green; TC-13/14/16
device closure awaits the staging capture manifest; `feature-host-all` is
delegated to the user's separate session
Type: Bug
Spec: free-text intent — a recipient of a 1:1 emoji reaction must see the
reactor and meaningful reaction copy instead of only `New Message`; ordinary
message unread state must keep its existing avatar-orbit lifecycle, while a
reaction must not masquerade as an unread message
Classification: implementation-gated
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-11 21:35 CEST | Evidence Collector | `handle_incoming_reaction_use_case.dart`, its tests, `flutter_notification_service.dart`, Plan 127 | The remembered fix is present and its focused local/plugin probes are green; the local path supplies the sender and reaction body. | Trace relay, background, NSE, routing, staging, and dedupe paths. |
| 2026-07-11 21:55 CEST | Evidence Collector | `inbox.go`, Dart push files, `NotificationPreviewResolver.swift`, route/staging tests and gates | The previous fix never established a typed remote reaction notification: the relay excludes `message_reaction`, and Android/iOS preview code recognizes only ordinary chat/group pushes. | Define a privacy-safe typed push and lifecycle proof contract. |
| 2026-07-11 22:16 CEST | Planner | official Android/Apple guidance, live device matrix, gate/discovery scripts | Current HEAD cannot itself explain a generic *reaction* card: it would emit no relay reaction push. Exact deployed-card provenance must be captured on a clean build before implementation is accepted. | Add RED-first producer attribution, host/platform contracts, and availability-bounded device closure. |
| 2026-07-11 22:47 CEST | Planner | `UnreadOrbitIndicator`, `OrbitWired`, `ConversationWired`, message read repository, notification-open routing, exact Orbit tests | Product decision: the green avatar orbit is unread-**message** state, not a generic unseen-activity badge. Preserve normal-message appear/clear behavior, and prove reactions never increment its count, satellites, or accessibility label. | Add message-lifecycle preservation, reaction-negative, and foreground phone-tap proof contracts without adding a reaction badge. |
| 2026-07-11 22:51 CEST | Planner validation | TC-194-10/11/16/27, app-root local notification route, repository read-event tests | All six literal test filters selected one test and passed. A combined regex-like `--plain-name` probe selected zero and was discarded, confirming the acceptance section must retain separate literal commands. | Keep these as verified planning GREEN observations; execution reruns them as preservation gates. |
| 2026-07-11 23:24 CEST | Independent TDD review | direct reaction handler/listener, P2P stage fallback, relay auth/wake gates, Android headless engine, iOS NSE, dedupe/tone/id helpers, gates | Pre-revision verdict `not-ready`: author-only eligibility, background crypto registration, trusted iOS contact state, atomic claims, fallback callers, mixed-version rollout, and literal gates were under-specified. | Apply the source-backed deltas below and rerun all five review lenses before execution. |
| 2026-07-12 08:49 CEST | TC-00 resume | clean HEAD APKs, Android emulator + physical Pixel, explicitly authorized read-only deployed relay journal/provider window | TC-00 passed. The exact reaction was stored as `message_reaction`; a post-store 10-second journal refetch found no provider send and Android showed no app card. The reported generic card is not produced by this clean-HEAD/deployed-relay path. | Run TC-07 before production edits, then implement the typed reaction notification path already specified below. |
| 2026-07-12 11:15 CEST | Executor + independent counterexample audit | typed Dart/Go/Swift/Android paths, SQLCipher concurrency, host/platform tests, real-FCM TC-07, runner/discovery/docs | TC-01..20 implementation contracts are present. TC-07 passed again with acknowledged synthetic cleanup and exact candidate/local-APK restoration. Independent audits closed the atomic DB, mounted unread, frozen-reader, and cross-isolate/cross-process tone gaps. | Keep TC-13/14/16 fail-closed until a staging capture manifest is supplied; accept `feature-host-all` evidence from the user's delegated session. |

## TDD Review Result

- Pre-revision verdict: `not-ready`; core typed-remote-reaction gap confirmed,
  but the cross-platform delivery contract could pass with unsafe or unreachable
  implementations.
- Post-revision verdict: `ready` for the plan's declared **evidence-gated**
  execution. TC-00 and the Android background-plugin preflight run before any
  wire or relay behavior is enabled.
- Core bet: `confirmed`. Current source still has no typed relay reaction push;
  the remembered local notification copy remains present.
- Disposition: `execute` the evidence/preflight rows first, then continue only
  if their stop conditions pass.
- Five-lens rerun after revision: evidence/classification `clear`; causal tests
  `clear`; bypass/scope `clear`; gate integrity `clear`; boundary/reversibility
  `clear` with the explicitly bounded iOS passive-card and stale-hint accepted
  differences.
- Blind-spot hits corrected: B-1 mixed-version rollback, B-2 raw-listener and
  headless-engine bypasses, B-3 author/tone/wake-gate claims, B-4 missing exact
  gate, B-5 concurrent dedupe, B-6 contact/tone marker lifecycle, B-7 native
  crypto fallback, B-8 real FCM/NSE proof, B-9 iOS/stale accepted differences,
  and B-10 Android/iOS plus old/new parity.

## Problem And Evidence

- Behavior to improve: when user A adds an emoji reaction to user B's 1:1
  message, B must receive one conversation-scoped notification whose title is
  A's display name and whose body identifies the reaction. A recognized
  reaction must not masquerade as a generic chat message.
- Impact: `New Message` hides both the actor and event, makes the notification
  impossible to triage, and weakens trust that a tap will open the relevant
  conversation. Missing remote reaction support also makes behavior depend on
  whether the recipient process happens to be alive.
- Product/UX decision: a reaction is unseen conversation activity, but it is
  not a new message. The existing green `UnreadOrbitIndicator` is explicitly
  one satellite per unread message (capped at three), and its accessibility
  copy says "unread message(s)". Plan 256 therefore keeps reaction attention in
  the OS notification and conversation UI; it does not inflate or relabel the
  message-unread orbit.
- Confirmed root cause/current gap: the June Plan 127 fix is local-only.
  `handleIncomingReaction` calls `maybeShowNotification` with the contact name
  and `Reacted <emoji> to your message` at
  `lib/features/conversation/application/handle_incoming_reaction_use_case.dart:263-290`,
  but `extractChatPushMetadata` has no `message_reaction` case at
  `go-relay-server/inbox.go:692-790`, and `InboxStore.Store` sends a push only
  when `ShouldNotify` is true at `go-relay-server/inbox.go:982-1000`.
  Downstream, Dart accepts only `new_message` / `group_message` at
  `lib/features/push/application/push_decrypt_preview.dart:26-49`, while the iOS
  NSE accepts the same two types at
  `ios/NotificationService/NotificationPreviewResolver.swift:140-183`.
  Thus no end-to-end remote reaction-notification contract exists.
- Confirmed adjacent gap: `ReactionPayload` v2 carries neither a clear outer
  reaction event id nor an add/remove discriminator
  (`reaction_payload.dart:13-19,87-104,162-173`). The relay therefore cannot
  safely wake for ADD while keeping REMOVE silent. The notification title must
  come from recipient-owned contact state, not a sender-asserted display field;
  the encrypted payload remains authority for the emoji only after parity
  checks.
- Confirmed author-eligibility gap: `handleIncomingReaction` verifies only that
  the target exists and is not deleted, then notifies after every accepted ADD
  (`handle_incoming_reaction_use_case.dart:181-195,263-290`). Reactions to one's
  own outgoing messages are legal, so the target can be incoming on the remote
  peer. Persistence must still converge, but only a target with
  `isIncoming == false` on the receiving device is notification-eligible.
- Confirmed Android engine gap: the production handler is wired without a
  decrypt callback (`background_message_handler.dart:38-42`), and the custom Go
  channel is registered only by `MainActivity.configureFlutterEngine`
  (`android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt:23-35`). Firebase
  creates a separate headless engine for killed-process callbacks, so an
  injected Dart fake cannot prove production ML-KEM access.
- Confirmed receive bypass: when durable live-direct staging throws,
  `P2PServiceImpl` emits the raw reaction (`p2p_service_impl.dart:1261-1280`),
  and `ReactionListener` calls the handler without the notification/dedupe
  dependencies (`reaction_listener.dart:88-115`). That fallback must join the
  same notify-capable replay seam or have identical dependencies.
- Confirmed sender-binding gap at the push boundary: the relay stream handler
  accepts caller-provided `req.From` instead of always deriving inbox
  `entry.From` from the authenticated libp2p remote peer
  (`go-relay-server/inbox.go:1678-1697`). A typed reaction push must not turn
  that existing ambiguity into spoofable notification attribution.
- Confirmed authorization caveat: the repository ships the global wake-token
  gate fail-open and sender token emission disabled
  (`wake_token_store.go:23-34`; `wake_token_wiring.dart:6-33`). Typed reaction
  push must therefore use its own default-off capability plus enforced
  recipient-issued authorization; a unit test that merely turns on the global
  gate is not evidence of the production policy.
- Confirmed concurrency/identity gaps: reaction receive is a read-then-save-
  then-notify sequence, Android background display is check-show-mark, and the
  live/background notification ids use `String.hashCode`. Sequential tests in
  one isolate cannot prove first-wins dedupe, restart-stable card replacement,
  or the claimed cross-process 30-second tone policy. The existing
  `NotificationToneTracker` explicitly documents foreground/in-memory scope.
- Existing coverage: planning probes passed
  `handle_incoming_reaction_use_case_test.dart::incoming ADD reaction notifies the recipient`,
  `flutter_notification_service_test.dart::showMessageNotification forwards conversation payload and details`,
  and `push_decrypt_preview_test.dart::decrypts 1:1 ciphertext preview with sender title`.
  `go-relay-server::TestInboxStore_UnsupportedEnvelopeDoesNotSendPush` also
  passed and confirms the active unsupported-type filter. These are planning
  observations, not execution RED/GREEN evidence for this plan. Independent
  review found that the ADD fixture makes the target incoming on the receiver;
  it proves copy wiring but not target-author eligibility. Execution must revise
  that fixture to a locally authored target and retain the incoming-target case
  as a persist-but-silent negative under TC-18.
- Confirmed adjacent behavior: `OrbitWired` refreshes a peer when
  `incomingMessageStream` emits (`orbit_wired.dart:1908-1916`) and refreshes it
  again when `conversationReadStream` emits, explicitly including a
  notification-tap route (`orbit_wired.dart:1934-1958`). `ConversationWired`
  calls its normal mark-read path after initial load
  (`conversation_wired.dart:637-650,1653-1658`), and
  `MessageRepositoryImpl.markConversationAsRead` emits the peer only when at
  least one incoming row changes (`message_repository_impl.dart:292-318`).
  Existing TC-194-10 and TC-194-16 cover the two UI projections separately.
  Planning validation also selected and passed TC-194-10/11/16/27, the warm
  local notification-tap route, and the repository read-event test. These are
  baseline observations, not substitutes for TC-16's composed phone proof.
- Missing coverage: no test or fixture maps `message_reaction` through relay
  push construction, Android background display, iOS NSE decryption, remote
  routing, push-envelope staging, cross-process dedupe, OS card rendering, or a
  terminated-app notification tap. The original Plan 256 also did not name the
  adjacent message-unread contract: a foreground ordinary message lights the
  avatar orbit, dismissing its OS card does not mark it read, a successful
  notification tap opens the conversation and clears it through the normal
  read commit, and a reaction never creates or increments that state.
- Standards rubric used by this plan:
  - keep one stable notification per conversation and update it rather than
    flooding the user, consistent with Android's guidance to update an existing
    notification or use a message-style conversation notification
    ([Android notification grouping](https://developer.android.com/develop/ui/views/notifications/group));
  - preserve a conversation identity/thread on both platforms; Android defines
    conversation notifications around message-style presentation and stable
    conversation shortcuts
    ([Android people and conversations](https://developer.android.com/develop/ui/views/notifications/conversations)),
    while Apple defines `threadIdentifier` as the key that groups related
    notifications
    ([Apple `threadIdentifier`](https://developer.apple.com/documentation/usernotifications/unnotificationcontent/threadidentifier));
  - decrypt private preview material on the recipient device and retain a safe
    fallback if that fails, which is a documented use of an iOS notification
    service extension
    ([Apple modifying notification content](https://developer.apple.com/documentation/usernotifications/modifying-content-in-newly-delivered-notifications)).
- Refuted findings:
  - **"The old reaction copy fix disappeared" is refuted.** The production call
    and focused application test still supply `Sender` plus the emoji body.
  - **"FlutterLocalNotifications rewrites the reaction to `New Message`" is
    refuted.** `FlutterNotificationService.showMessageNotification` forwards
    title/body directly at `flutter_notification_service.dart:117-139`, and its
    method-channel test passed.
  - **"The checked-in relay currently emits a generic reaction push" is
    refuted.** It emits no reaction push because the type is unsupported. A
    generic card therefore implies a deployed-build difference, stale install,
    type coercion, or a different notification event.
- Unresolved findings: the observed phone/platform, app/relay build revisions,
  remote `type`, and actual producer (`NOTIFICATION_SHOWN`, Android background
  handler, iOS NSE, or provider alert) are not available. TC-00 must capture
  them on a clean HEAD build. If the generic card belongs to a normal message
  rather than the reaction, execution must split that incident and must not
  widen this plan silently.
- Affected production, test, and gate files: `reaction_payload.dart`,
  `send_reaction_use_case.dart`, `remove_reaction_use_case.dart`,
  `handle_incoming_reaction_use_case.dart`, reaction repository interface/
  implementation, `reaction_listener.dart`, `p2p_service_impl.dart`, `inbox.go`,
  push-token capability/authorization files,
  `background_push_notification_fallback.dart`, `background_message_handler.dart`,
  `push_decrypt_preview.dart`, `push_envelope_staging.dart`,
  `ingest_staged_push_envelopes_use_case.dart`, `notification_route_target.dart`,
  `flutter_notification_service.dart`, `local_notification_support.dart`,
  deterministic notification identity, atomic remote-claim, and durable tone-
  lease helpers,
  `contact_repository_impl.dart`, `block_contact_use_case.dart`,
  `unblock_contact_use_case.dart`, contact delete/add/update wiring, `main.dart`,
  `pubspec.yaml`, a local `packages/background_push_crypto/` Flutter plugin and
  Kotlin/Dart registration tests,
  `NotificationPreviewResolver.swift`, `NotificationService.swift`, physical
  `NotificationTapUITests.swift` coverage, their focused tests, shared
  push/dedupe fixtures, the preservation-only Orbit/read/open-route tests, and
  the named gate/discovery scripts. `OrbitWired`, `UnreadOrbitIndicator`, and
  message-read production code are test-protected boundaries, not planned
  production edits unless a named sentinel exposes a real regression.

## Graph Grounding Snapshot

- Graph fingerprints / freshness: initial notification query
  `4b707ee9eed1e46d` with
  `stale:lib/features/conversation/presentation/screens/conversation_wired.dart`;
  unread-semantics refinement `bf874be415eaf2e3` with
  `stale:lib/features/conversation/application/build_direct_media_library_batch_forward.dart`.
- Independent review query: `bf874be415eaf2e3`, `confidence=anchored`; graph
  freshness remained stale at an unrelated conversation file, so source was
  authoritative. Command:
  `python3 graphify-arch/tdd_context.py query "Counterexample audit Plan 256 ReactionPayload message_reaction extractChatPushMetadata InboxStore Store authenticated remote req.From background_message_handler NotificationPreviewResolver push_envelope_staging replayInboxReaction RecentRemoteNotificationGate conversationReadStream exact tests gate registration bypasses" --profile review --budget 800`.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "emoji reaction notification for a received 1:1 message shows generic New message instead of sender and reaction/message context; trace notification payload construction, local display, routing, tests, and gate registration" --profile tdd --budget 700`,
  refined once after `confidence=broad` with
  `python3 graphify-arch/tdd_context.py query "HandleIncomingReactionUseCase notification title body sender reaction emoji New message NotificationService handle_incoming_reaction_use_case_test.dart gate registration" --profile tdd --budget 700`,
  then supplemented for this product decision with
  `python3 graphify-arch/tdd_context.py query "Update Plan 256: UnreadOrbitIndicator remains message-only; foreground incoming message lights avatar orbit; notification tap ConversationWired markConversationAsRead clears it; message_reaction must not increment unreadCount or satellites; exact tests and gate registration" --profile tdd --budget 700`.
- Anchors: `_senderPeerId` ->
  `test/features/conversation/application/handle_incoming_reaction_use_case_test.dart:21`;
  `NotificationService` -> `ios/NotificationService/NotificationService.swift:3`;
  `ReactionPayload.emoji` -> `reaction_payload.dart:16`;
  `UnreadOrbitIndicator` ->
  `lib/features/orbit/presentation/widgets/unread_orbit_indicator.dart:19`;
  `ConversationWired` ->
  `lib/features/conversation/presentation/screens/conversation_wired.dart:220`;
  `unreadCount` ->
  `test/features/orbit/presentation/widgets/orbital_visualization_test.dart:45`.
- Surfaced proof/gate files:
  `handle_incoming_reaction_use_case.dart`,
  `handle_incoming_reaction_use_case_test.dart`, `reaction_payload.dart`,
  `NotificationService.swift`, `notification_tone_tracker.dart`, and the
  `ONE_TO_ONE_TESTS` / `feature-host-all` registrations. The supplemental query
  surfaced `orbit_unread_indicator_wired_test.dart`,
  `unread_orbit_indicator_test.dart`, `OrbitWired`, and `ConversationWired`.
- Graph gaps requiring source search: relay push eligibility, Android fallback
  resolution, remote route parsing, staged-envelope replay, Swift preview and
  dedupe-marker logic were not surfaced and were verified in current source.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Attribute the reported generic card on a clean current build before accepting
  a production fix.
- Define a typed, ciphertext-only `message_reaction` push for fresh 1:1 ADD
  events aimed at the target author. Push-visible data may contain routing/
  event identifiers, target-message id, an ADD discriminator, and capability
  version, but never emoji, sender display name, original message text, or
  private preview copy. A fixed non-private APNs fallback may say `New reaction`
  / `Someone reacted to your message` so an NSE timeout never says
  `New Message`.
- Bind relay notification attribution to the authenticated inbox-stream peer;
  reject or ignore a conflicting caller-supplied `from` value. The cleartext
  ADD discriminator is only a wake hint, never authority to persist a reaction.
- Keep reaction persistence for valid reactions to either incoming or outgoing
  messages, but acquire/display a notification only when the local target row
  proves it was authored by the receiver. The live, staged, raw-listener,
  Android background, and iOS NSE routes share this policy.
- Add outer event-id/action/target fields and accept only exact `add` or
  `remove`; cross-check them against decrypted data. Actor display name comes
  from recipient-owned contact state rather than a sender-asserted payload
  field. Old v2 reaction envelopes remain readable; missing notification
  fields store/replay without a remote wake.
- Add `direct_reaction_v1` recipient capability and reaction-specific,
  recipient-issued wake authorization behind a default-off relay switch. The
  global fail-open wake-token setting is unchanged. Relay rollout stores
  reactions silently first; capable clients register second; typed wake is
  enabled last. Rollback disables only typed reaction push and never custody.
- Render normal-key previews as title `<reactor name>` and body
  `Reacted <emoji> to your message`. A decrypt/local-state failure uses
  reaction-specific safe copy (`Reaction` / `Someone reacted to your message`),
  never `New Message` for a recognized reaction.
- On Android background/terminated delivery, resolve contact and target-author
  eligibility from the real SQLCipher DB. A local Flutter plugin registered on
  every engine, including the Firebase headless engine, exposes only the pure
  ML-KEM decrypt needed for preview and must not replace the main Go event
  callback. Kotlin/plugin and real-FCM preflight tests prove registration.
  Decrypt success yields actor + emoji after parity; failure yields trusted
  local actor + semantic no-emoji copy.
- Mirror recipient-owned direct-contact display/blocked state and a bounded set
  of locally authored target-message ids into the shared iOS Keychain/App Group,
  using the established group-mute projection pattern. Cover add/update/block/
  unblock/delete/re-add, outgoing-message create/delete, failed projection
  writes, and launch backfill. The NSE requires known-unblocked contact plus an
  authored-target marker, takes the title from that projection, and uses the
  decrypted emoji only after parity.
- Preserve conversation routing, stable per-conversation replacement, Android
  message category, iOS thread identifier, remote/local dedupe, and
  stage-before-open handling for the reaction envelope. Replace per-isolate
  check-show-mark and `String.hashCode` with a documented deterministic 31-bit
  Android id, a <=64-byte cross-language request/collapse identity, an atomic
  event claim, and a durable 30-second per-conversation tone lease with TTL/cap
  pruning. The first logical reaction alerts; concurrent same-event races have
  one winner; a distinct reaction in the window updates silently.
- Route the live-direct staging-error fallback through the same notify-capable
  reaction replay policy. A staging exception may change durability/ack outcome
  but must not silently bypass author eligibility, dedupe, or notification.
- Preserve the existing ordinary-message unread lifecycle: while the recipient
  is already in the app but outside that conversation, a persisted incoming
  message lights the sender's avatar orbit; dismissing the phone notification
  leaves it lit; tapping the notification routes to the conversation, whose
  successful normal read commit clears the orbit. A failed/no-op route must not
  clear unread state early.
- Keep reaction activity out of `MessageRepository` unread accounting. Showing,
  dismissing, receiving, replaying, or tapping a reaction notification must not
  create a synthetic `ConversationMessage`, increment `unreadCount`, add a
  satellite, or change message-unread semantics. If genuine unread messages
  already exist, a reaction leaves their count unchanged until the conversation
  is actually opened; that open may then clear those real messages normally.
- Add host, Go, Swift, device-artifact, gate-registration, and maintained
  notification-matrix coverage.

Must preserve:

- REMOVE, stale ADD, exact duplicate ADD, unknown sender, unavailable target,
  blocked sender, active-conversation, and explicit recovery suppression stay
  silent after recipient-side validation -> focused cases in
  `handle_incoming_reaction_use_case_test.dart`. Valid reactions to an incoming
  target persist but remain notification-silent because the local user is not
  the author.
- A genuinely new replacement reaction from the same contact still updates the
  notification card, with the tone debounce making a burst's follow-up silent
  rather than dropping it -> existing rapid-reaction sentinel plus TC-02.
- Ordinary 1:1 and group message sender/body previews, privacy fallback, mute,
  route, notification ids, and avatar-orbit unread lifecycle remain unchanged
  -> TC-12 and TC-15/16.
- The relay stores every valid reaction envelope even when it does not send a
  push; wake-token authorization remains layered over push eligibility.

Hard `Do not`:

- Do not put sender username, emoji, original message text, media metadata, or
  generated/private preview copy in relay/FCM/APNs data fields. The only allowed
  provider alert copy is the fixed, non-private typed reaction fallback.
- Do not apply or persist reaction content from outer metadata. REMOVE,
  stale/exact duplicate replay, self/group echo, sender mismatch, and blocked or
  unknown senders remain silent. A pre-decrypt OS fallback may use only the
  typed reaction label and locally trusted actor state; it may never present
  outer metadata as decrypted emoji/content.
- Do not modify group-reaction transport/notification behavior; it is only a
  preservation sentinel here.
- Do not add a DB migration, new persisted reaction table, notification
  permission prompt, reply action, or notification-channel id.
- Do not overload `unreadCount`, `UnreadOrbitIndicator`, its green satellites,
  or its "unread message(s)" accessibility text with reaction activity. Do not
  insert a synthetic message row merely to make a reaction visible.
- Do not clear real message unread state when a notification is delivered,
  displayed, or dismissed. Clear it only after the canonical conversation-open
  read path succeeds.
- Do not use `am force-stop` for terminated-app proof; it disables/cancels the
  delivery boundary being tested. Use `am kill` plus an empty-`pidof` check.
- Do not enable typed reaction push for recipients lacking
  `direct_reaction_v1` or a valid recipient-issued reaction wake authorization.
- Do not use `String.hashCode`, a non-atomic JSON read/modify/write, or a test-
  injected decrypt callback as the production cross-process identity/claim/
  crypto seam.

Deferred / accepted difference:

- Full Android `MessagingStyle` + long-lived conversation shortcuts and iOS
  Communication Notifications are an app-wide notification-UX project, not a
  reaction-copy bug fix. Owner: a follow-up notification presentation plan;
  Plan 256 still sets the message category/thread and preserves stable ids.
- The new Android background plugin is scoped to typed direct-reaction preview;
  it does not claim Report 73 closure for ordinary chat/group previews. If the
  real-FCM preflight cannot register the plugin without disturbing the main Go
  callback, execution stops before wire enablement and retains the trusted
  local actor/no-emoji fallback as the only Android deliverable.
- iOS NSE suppression is defense-in-depth: Apple still requires the extension
  to return content. For an eligibility mismatch, blocked contact, late stale
  hint, or duplicate that already reached APNs, Plan 256 guarantees no sound or
  banner and a passive Notification Center entry may remain. Reaction-specific
  relay authorization is the primary no-send boundary.
- iOS does not guarantee replacement between an app-origin local request and an
  APNs-origin request. Closure requires one audible alert and one thread; if the
  physical first/second-order proof shows a passive duplicate, that platform
  behavior is accepted and recorded rather than falsely called one visible
  card. Android still requires one replaced conversation card.
- Original target-message text is intentionally absent from reaction
  notifications. The event description plus correct conversation route is the
  accepted privacy-preserving context.
- A separate reaction-attention signal (for example `unseenReactionCount`, an
  activity inbox, or a visually distinct marker) is deferred. It needs its own
  product semantics, persistence/read lifecycle, accessibility copy, and plan;
  it must not reuse the green message-unread orbit by stealth.

Dependencies:

- Device closure needs a staging/test relay running the Plan 256 relay build,
  valid Android FCM and iOS APNs registrations, and the available targets named
  below. No production deployment is authorized by this plan.
- Mixed-version rollout requires relay support for default-off reaction
  classification/capability first. Old clients keep reading the unchanged v2
  reaction envelope; legacy senders store/replay without typed wake. Rollback
  flips off typed push while leaving inbox custody and client readers intact.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-00 | Attribute the observed card to a reaction event and record app/relay revision, remote type, producer, title/body, lifecycle, and tap route. | `integration_test/one_to_one_reaction_notification_proof_test.dart::head_provenance` via `run_1to1_reaction_notification_device.dart` | Paired-device / real relay, physical Android + Android emulator | HEAD is expected to produce no remote reaction card or the reported generic card; either result must be source-attributed -> GREEN produces exactly one typed reaction card and a redacted provenance artifact. | Force the runner to accept a card without matching reaction event id/type -> TC-00 red. | `_proof_test.dart` -> existing `classify_path` device-proof rule; manually register runner/test/scenario in `check_reliability_simulation_discovery.sh` under `1to1`. |
| TC-01 | The already-fixed live/local ADD path for a locally authored target passes trusted local actor, emoji body, conversation payload, and stable id through the real plugin boundary. | `test/features/conversation/integration/reaction_notification_pipeline_test.dart::live ADD to locally authored target preserves actor body route and stable conversation id through plugin` | Host integration + real `FlutterNotificationService` over method-channel plugin fake | GREEN sentinel on HEAD's copy/plugin seams -> one integrated notification with title `Sender`, body `Reacted 👍 to your message`, payload peer id, and per-conversation id. The fixture must make the target outgoing on the receiver. | Replace the reaction body/title with generic constants, make the target incoming, or key the plugin id by reaction id -> TC-01 red. | Exact command; new consolidated integration file pinned in `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS`; AUTO feature host also discovers it. |
| TC-02 | Concurrent copies of the same ADD event have one atomic persistence/announcement winner, while a distinct event may still update silently inside the tone window. | `test/features/conversation/application/handle_incoming_reaction_use_case_test.dart::concurrent exact ADD has one change and one notification`; `test/features/conversation/domain/repositories/reaction_repository_impl_test.dart::atomic reaction event claim distinguishes insert from exact replay` | Host application/repository / barrier-controlled concurrent calls, real SQLCipher repository where available, fake notification service | HEAD read-save-notify lets both calls observe absence -> GREEN returns one inserted/change result and one notification; exact retry is idempotent and distinct id persists. | Reintroduce read-before-write without serialization/insert discriminator, compare only timestamps, or emit two changes -> TC-02 red. | Exact commands; handler file already in `ONE_TO_ONE_TESTS`; repository test AUTO feature-host and added to the focused command. |
| TC-03 | New ADD/REMOVE envelopes expose only outer event id/action/target/routing crypto, keep emoji encrypted, accept only exact `add`/`remove`, and preserve legacy v2 reads. | `test/features/conversation/domain/models/reaction_payload_test.dart::v2 notification metadata is minimal and legacy readable`; `::unknown action is rejected even when outer and inner match`; send/remove use-case notification-metadata cases | Host domain/application / fake crypto bridge plus frozen old-reader fixture | HEAD lacks outer fields and treats any non-`remove` action as ADD -> GREEN proves parity, old-reader/new-envelope tolerance, new-reader/legacy behavior, mismatch rejection, and unknown-action rejection. | Move actor/emoji to outer data, accept `dance`, omit event/target/action, or make old v2 unreadable -> TC-03 red. | Exact files AUTO feature-host; send/remove already in `ONE_TO_ONE_TESTS`; frozen reader fixture direct. |
| TC-04 | A stored direct ADD emits one ciphertext-only typed push only when the authenticated sender, recipient-issued reaction authorization, recipient capability, and default-off rollout flag all pass. Android stays data-only; APNs carries mutable-content/thread/collapse identity plus fixed silent typed fallback. | `go-relay-server/inbox_test.go::TestInboxStore_ReactionAddRequiresCapabilityAndAuthorization`; `::TestInboxHandler_ReactionPushBindsAuthenticatedRemotePeer`; `::TestBuildReactionPush_TimeoutFallbackNeverSaysNewMessage` | Go relay host / recording push sender, enforced reaction token store, capability-bearing device token, real framed stream handler | HEAD emits no reaction push and trusts direct `req.From` -> GREEN sends exactly once only for authorized/capable recipient, derives sender from remote peer, leaks no private fields, and uses bounded typed APNs fallback. | Trust `req.From`, omit capability/token/flag, coerce to `new_message`, add private copy, make fallback audible, or exceed 64-byte collapse id -> TC-04 red. | Exact `GOTOOLCHAIN=go1.25.0 go test` commands below; direct shared tests outside Flutter globs. |
| TC-05 | REMOVE, unknown/missing/malformed action/id/target, duplicate store, legacy envelope, unauthorized token, incapable recipient, or disabled flag stores according to custody rules but never sends a reaction push. | `go-relay-server/inbox_test.go::TestInboxStore_ReactionNonAddOrIneligibleNeverSendsPush` | Go relay host / recording store/sender with explicit enforced reaction gate | HEAD's no-push default is GREEN; after ADD support every negative remains zero sends with unchanged storage result. The test explicitly proves the global fail-open default is not being mistaken for reaction authorization. | Treat every reaction as push-worthy, accept unknown action, or bypass the reaction-specific gate -> TC-05 red. | Exact named Go command below; no Flutter registration. |
| TC-06 | Remote `message_reaction` data routes to the reactor's conversation, gets a fixed reaction-specific fallback, and derives the same bounded event/collapse identity in Dart, Go, and Swift. | route/fallback/identity tests plus reaction row in `test_fixtures/si5_dedupe_keys.json` | Host core/push/Go/Swift shared fixture | HEAD route is null and fallback is generic -> peer route, target anchor, semantic fallback, deterministic event key, <=64-byte collapse/request id. | Use target id as event id, return chat defaults, or diverge between languages -> TC-06 red. | Exact tests; core/push AUTO, Go/Swift direct fixture consumers. |
| TC-07 | Android headless FCM resolution reads real SQLCipher contact/target-author eligibility and reaches a production background-safe ML-KEM plugin registered on every engine; validated decrypt uses emoji, failure uses trusted local actor/no-emoji copy. | Dart resolver/handler cases; `android/.../BackgroundPushCryptoPluginTest.kt::registers on headless engine without replacing main callback`; real-FCM plugin preflight scenario | Host push + Kotlin/native + device preflight / fake and real plugin registrants | HEAD has no headless channel -> host policy plus native registration and real callback prove title/body, parity, missing/blocked/non-author suppression, and safe fallback. | Register only in Activity, replace Go message callback, trust mismatched content, or require debug injection -> TC-07 red. | Dart AUTO feature-host; Gradle Kotlin exact gate; TC-13 real SQLCipher/crypto boundary. |
| TC-08 | iOS NSE requires a projected known-unblocked contact and locally authored target, takes actor title from recipient-owned state, validates emoji parity before atomically claiming the event, and uses passive/silent typed fallback on rejection/error. | Swift resolver cases; contact/authored-target projection lifecycle tests; block/unblock/delete/re-add/wake-reconcile integration | Swift XCTest + host integration / shared ciphertext fixture, fake Keychain, real claim filesystem | HEAD has no direct projection/reaction branch -> valid card uses local actor + decrypted emoji; invalid-first does not poison a later valid copy; absent/blocked/non-author is passive/no-sound; projection/backfill/token lifecycle self-heals. | Use sender-asserted name, claim before validation, leave stale delete marker, or omit production callsite/reconcile wiring -> TC-08 red. | Direct Swift plus exact Dart repository/use-case/integration tests; fixture parity documented in gate docs. |
| TC-09 | Android and iOS stage a reaction envelope as `kind=reaction`; app startup/open replays it through `replayInboxReaction`, clears only committed/exact-duplicate entries, and never parses it as chat. | `test/features/push/application/ingest_staged_push_envelopes_use_case_test.dart::staged reaction dispatches to reaction replay`; `ios/RunnerTests/NotificationPreviewResolverTests.swift::testReactionEnvelopeStagesWithReactionKind`; `test/features/push/application/background_message_handler_staging_test.dart::Android stages reaction kind` | Host application + Swift XCTest / file staging fakes | HEAD refuses the type or stages only `kind=chat` -> typed dispatch and retention/clear dispositions are correct. | Hard-code `chat`, clear on retryable/target-unavailable, or send reaction bytes to `replayChatMessage` -> TC-09 red. | Dart files AUTO feature host; Swift direct XCTest; exact shared commands required. |
| TC-10 | Concurrent remote/live/staged/inbox copies share one atomic event claim and durable tone lease; crash residue expires/prunes, a distinct event updates silently inside 30 seconds, and it alerts after expiry. | barrier-controlled pipeline test; Dart durable-lease tests; Swift simultaneous-claim/expiry/pruning tests; shared identity fixture | Host integration + Swift XCTest / atomic filesystem primitives, fake clock, crash residue | HEAD uses sequential/in-memory decisions -> GREEN proves one first winner under concurrency, no rejected-event poisoning, bounded marker count, restart survival, expiry, and both arrival orders. | Revert to JSON check-show-mark, claim before validation, never prune, or key by target -> TC-10 red. | Pipeline pinned in both 1:1 arrays; helper tests AUTO/direct Swift. |
| TC-11 | Live/background cards use a deterministic 31-bit conversation id on Android, message category, iOS peer thread, <=64-byte request/collapse identity, exact copy, and canonical tap payload across process restart. | deterministic notification-id vector test; Flutter service/background handler serialization tests; shared Dart/Go/Swift identity fixture | Host core/push/Go/Swift plus device restart assertion | HEAD uses process-scoped `String.hashCode` and static background details -> same vector survives restart and both producers replace the same Android conversation card. | Restore `hashCode`, use reaction id as card id, exceed APNs limit, or drop category/thread/route -> TC-11 red. | Exact core/push tests AUTO; shared fixture direct Go/Swift; TC-13 restart proof. |
| TC-12 | Ordinary 1:1/group messages, group reactions, mute/active suppression, privacy fallback, notification ids, and tap routes do not change. | `test/features/push/application/push_decrypt_preview_test.dart::decrypts 1:1 ciphertext preview with sender title`; `test/features/push/application/push_decrypt_preview_test.dart::decrypts group ciphertext preview with sender-prefixed body`; `test/core/notifications/flutter_notification_service_test.dart::notification id is per-conversation and stable across a burst for both direct and group (silent updates reuse the same id)`; `test/core/notifications/notification_route_contract_matrix_test.dart::conversation remote data resolves to the canonical target`; five exact `test/features/groups/application/group_message_listener_test.dart` cases listed below | Host GREEN sentinels / existing fakes and fixtures | GREEN on HEAD -> remain GREEN after typed direct-reaction support. | Route `group_message`/group reaction through the direct-reaction branch, change shared channel/id semantics, or bypass mute/viewing/self suppression -> sentinel red. | Copy-pasteable exact preservation commands plus `./scripts/run_test_gates.sh 1to1`; all five group cases use the exact `127-Bug-D` filter, not a full `groups` gate because group production is untouched. |
| TC-13 | With Android B killed but not force-stopped, A reacts through UI to B's authored message; B's real headless FCM engine shows one trusted-actor + emoji card, replaces it after a restart-separated second event, and an automated tap opens A's conversation with zero reaction-created unread state. | `integration_test/one_to_one_reaction_notification_proof_test.dart::android_physical_recipient` via runner plus artifact validator | Paired-device / emulator sender + physical Android recipient, real relay/FCM/SQLCipher/background plugin/Go ML-KEM | HEAD has no typed push/headless channel -> exact copy, decrypt-success marker, deterministic card id across restart, correct tap/application, no duplicate/unread. A paired negative reacts to A's own message: B persists it but receives no push/card. | Register plugin only in Activity, ignore author policy, restore generic fallback/hashCode, create unread row, force-stop, or accept manual tap -> TC-13 red. | Device proof AUTO plus manual discovery; runner must invoke the proof/validator and collect app/SQLCipher/provider artifacts. |
| TC-14 | A physical iOS NSE rewrites the fixed silent provider fallback using projected local actor + decrypted emoji, preserves thread/tap/collapse identity, and creates no message unread state; both live-first and remote-first orders yield one audible alert. | `integration_test/one_to_one_reaction_notification_proof_test.dart::ios_physical_recipient` plus exact `NotificationTapUITests` selector/artifact validation | iOS-specific / Android sender + physical iPhone recipient, real relay/APNs/NSE/Go ML-KEM | HEAD has no reaction APNs/NSE branch -> valid card has exact copy and zero forbidden fields/unread; NSE timeout remains `New reaction`, never `New Message`; an OS-retained duplicate must be passive in the same thread. | Make fallback generic/audible, use sender name, claim before validation, omit collapse/thread, or count a passive duplicate as a second alert -> TC-14 red. | Proof runner registered under 1:1 and explicit physical `xcodebuild` UI-test command below. |
| TC-15 | The avatar orbit remains a message-only projection: zero unread messages renders no indicator, an ordinary foreground incoming message lights it, a second message adds a second satellite without remounting, and accessibility announces only the real unread-message count. | Existing `test/features/orbit/presentation/screens/orbit_unread_indicator_wired_test.dart::TC-194-10: incoming message lights the node live`; `::TC-194-11: second message increments satellites without node re-entrance`; `test/features/orbit/presentation/widgets/orbital_visualization_test.dart::TC-194-27: lit node semantics announces unread; unlit label unchanged` | Host wired/widget GREEN sentinels / `InMemoryMessageRepository`, fake incoming listener, real Orbit widgets and semantics tree | GREEN on HEAD -> remain GREEN with 0/1/2 message counts and labels; no reaction language enters this visual. | Disconnect `incomingMessageStream`, derive satellites from generic notification/activity count, or relabel reaction activity as an unread message -> TC-15 red. | Copy-pasteable exact commands; wired file is already pinned in the curated groups inventory and AUTO feature-host, visualization file AUTO feature-host. Run exact cases plus the justified feature family, not the full groups gate. |
| TC-16 | On a real phone while B is already on Orbit, A's first ordinary message lights one satellite and posts the normal OS card; dismissing that card leaves the message unread; A's second message produces two satellites/a replacement card; tapping that card opens A's conversation, commits both reads, and returning to Orbit shows no indicator. | `integration_test/one_to_one_reaction_notification_proof_test.dart::android_message_unread_lifecycle` via `run_1to1_reaction_notification_device.dart --scenario android_message_unread_lifecycle` | Paired-device GREEN preservation proof / `emulator-5554` sender + `21071FDF600CSC` active physical Android recipient, real relay/FCM/local notification/SQLCipher/UIAutomator | Expected GREEN on HEAD: persisted unread count `0 -> 1 -> 1 after dismiss -> 2 -> 0 after successful notification route/read`, matching `0 -> 1 -> 1 -> 2 -> 0` Orbit satellites; execution must first classify any failure before changing production. | Clear on notification delivery/dismiss, drop Orbit incoming refresh, route without real `ConversationWired`, skip `_markAsRead`, suppress the repository read event, or merely hide the widget in the harness -> TC-16 red. | Same `_proof_test.dart` AUTO device classification; manually register the new scenario under `1to1`. This Android pair closes the app/UI lifecycle because it is not iOS-specific; unavailable named targets are N/A under project policy. |
| TC-17 | Reaction activity does not create or increment message unread state. With zero genuine unreads it leaves zero/no orbit; with two genuine unread messages plus an outgoing target, a fresh reaction stores/notifies but leaves two satellites and the "2 unread messages" semantics unchanged. A reaction-notification tap may clear those two only by routing to a real conversation and completing the normal read commit. | `test/features/conversation/integration/reaction_notification_pipeline_test.dart::reaction activity never increments unread-message orbit state` | Host integration GREEN sentinel / real `handleIncomingReaction`, app-root local-tap router, mounted `OrbitWired` and `ConversationWired`, in-memory message/reaction repositories, method-channel notification fake | GREEN on HEAD's live path -> zero stays zero; two stays two through reaction receipt/display/dismissal; successful tap/render/read then becomes zero. Remote/staged paths added by this plan must satisfy the same assertion. | Insert a synthetic message for a reaction, increment a generic activity count, change satellite/semantics count, clear on display/dismiss, or replace the real routed conversation with a test callback that directly marks read -> TC-17 red. | Exact command; consolidated pipeline file is pinned in `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS` and AUTO feature-host. TC-13/14 repeat the zero-unread invariant at the OS boundary. |
| TC-18 | Reaction persistence is independent from notification eligibility: an ADD to a locally authored target notifies; an ADD to an incoming target persists/emits UI change but stays silent; missing local identity fails closed. | `test/features/conversation/application/handle_incoming_reaction_use_case_test.dart::only target author is notified while both target directions persist` | Host application / outgoing and incoming target fixtures, notification fake | HEAD notifies both target directions -> GREEN has equal reaction convergence but only outgoing/local-authored target notification. | Gate persistence instead of notification, infer authorship from reactor, or fail open when identity/target direction is missing -> TC-18 red. | Existing curated 1:1 file + AUTO feature-host; exact command below. |
| TC-19 | A forced live-direct staging failure cannot bypass the notification policy: the raw fallback reaches the shared notify-capable replay seam once, with author/dedupe/active-view gates intact. | `test/core/services/p2p_service_impl_test.dart::reaction stage failure uses shared notify-capable fallback exactly once`; main wiring contract test | Host core/lifecycle / throwing staging repository and real listener/replay wiring | HEAD emits to `ReactionListener` without deps -> valid authored-target ADD becomes silent. GREEN persists/notifies once or returns explicit retry without duplicate emission. | Restore raw emit, inject deps only in a unit fixture, or call both listener and replay -> TC-19 red. | Exact core tests; `core-host-all` and existing main wiring inventory. |
| TC-20 | Mixed versions are safe: old reader accepts a new optional-metadata v2 reaction, new reader accepts legacy v2, legacy/incapable recipients receive no typed push, and disabling the relay flag immediately restores silent-store behavior. | frozen old/new reader fixtures; `TestInboxStore_ReactionCapabilityRolloutAndRollback` | Host Dart + Go / frozen envelopes, capability token store, default-off flag | HEAD has no typed feature -> GREEN proves additive read compatibility, staged rollout, and no custody loss during rollback. | Require new fields to parse, push to legacy device, or make rollback reject/drop reaction storage -> TC-20 red. | Exact Dart fixture and pinned-toolchain Go command; wave-level rollout evidence. |

### Test Notes

- TC-02 uses a barrier, not two sequential awaits. It distinguishes an exact
  replay by reaction event id plus decrypted identity/action and requires the
  repository/claim primitive to report the single first insert. Equal
  timestamps with a different event id are not silently discarded.
- TC-03's cleartext allowlist is limited to `type`, envelope version, sender
  peer id, reaction event id, ADD/REMOVE discriminator, and crypto fields.
  The relay replaces any caller-supplied sender attribution with the
  target-message id, capability version, and crypto fields. The relay replaces
  any caller-supplied sender attribution with the authenticated stream peer.
  The discriminator is a wake hint only; decrypted/local parity remains
  authoritative for committing or displaying private emoji content.
- TC-07's real-FCM preflight is load-bearing. The Kotlin test alone cannot show
  that FlutterFire's headless engine registers the local plugin. The scenario
  must record a production plugin-call/decrypt marker without launching the
  Activity and prove the main Go event callback still works after foregrounding.
  It may omit the emoji only on a genuine key/decrypt-failure path. It must
  still resolve the known, unblocked local actor and semantic reaction body. A
  missing, blocked, non-author, or sender-mismatched state fails closed; it may
  not revert to `New Message`.
- TC-08 reuses the shared-Keychain/App-Group projection pattern rather than a
  database migration. Projection and reaction-wake authorization share the
  real add/update/block/unblock/delete/re-add callsites and launch backfill. The
  NSE marker is defense in depth for a push already in flight and can make it
  passive/silent; it cannot remove an APNs item already delivered.
- TC-10 asserts simultaneous and sequential races. It acquires the event claim
  only after eligibility/decrypt validation, uses atomic creation/locking, and
  prunes expired/capped claims and tone leases. Android must leave one replaced
  card. iOS must leave one audible alert in one thread; a same-thread passive
  duplicate is an accepted OS result if the physical ordering proof records it.
- TC-12's five exact group-reaction sentinel names are:
  `127-Bug-D: incoming ADD group reaction notifies (route + emoji)`,
  `127-Bug-D: incoming REMOVE group reaction does NOT notify`,
  `127-Bug-D: ADD reaction in a MUTED group does NOT notify`,
  `127-Bug-D: own reaction (mesh echo) does NOT self-notify`, and
  `127-Bug-D: reaction is suppressed while viewing the group conversation`.
- TC-13/14 use unique usernames, target text, reaction id, and emoji per run so
  stale cards cannot satisfy the proof. The artifact validator requires one
  matching Android card or one iOS audible alert/thread, one route-open marker,
  one stored reaction,
  zero reaction-created message rows, and unchanged message-unread count. After
  returning to Orbit, no `UnreadOrbitIndicator` may exist when the precondition
  was zero genuine unread messages.
- TC-15/16 make "notification" and "unread message" separate state machines.
  Delivery or dismissal changes the OS card, not the persisted read flag. The
  flag changes only when the canonical conversation view completes its read
  operation; `conversationReadStream` then refreshes Orbit.
- TC-17 must exercise production routing and mark-read code. A harness callback
  that directly mutates unread state would prove only the test and is rejected
  as vacuous. If a reaction opens a conversation that already contains genuine
  unread messages, those messages become read because the conversation was
  viewed, not because the reaction notification itself consumed them.

## Implementation Steps

1. **Completed 2026-07-12:** snapshot `git status --short`, preserve the dirty
   tree, build the runner/artifact validator, install clean HEAD builds, and run
   TC-00. The bounded event produced no provider send and no card, so there is
   no unrelated ordinary-message incident to split out; Plan 256 remains scoped
   to typed reaction lifecycle support.
2. Before wire edits, add and run the Android headless-plugin preflight from
   TC-07. Stop-if the plugin is not registered by the real FCM engine or
   disturbs the main Go callback; keep the semantic no-emoji fallback and amend
   device expectations before continuing. Run TC-15 and notification-open/read
   sentinels. Add the shared
   `test_fixtures/one_to_one_reaction_add.json` push fixture, forbidden-field
   assertions, TC-02..12 and TC-17..20. Run the first causal Dart/Go/Swift/
   Kotlin REDs while recording preservation GREENs.
3. Extend `ReactionPayload` and ADD/REMOVE send use cases with optional outer
   event-id/action/target metadata; accept only exact actions, preserve frozen
   old-v2 reads, and reject outer/decrypted mismatches. Keep display names out
   of sender-authored payload authority.
4. Make receiver application atomic and author-aware. Preserve every valid
   reaction, but expose a first-insert/claim result and notify only for a locally
   authored target. Route the P2P staging-error fallback through the identical
   replay/notify seam and add concurrent barrier tests.
5. Add relay `message_reaction` metadata and a typed ciphertext-only builder.
   Bind the stored/push sender to the authenticated stream peer, wake only for
   a well-formed authorized/capable ADD while the default-off flag is enabled,
   retain storage rules, and use silent typed APNs fallback plus bounded
   collapse identity. Prove flag-off rollback and both old/new reader directions.
6. Add remote route/fallback/preview handling. Android reads contact/target state
   and calls the every-engine plugin. iOS reads the recipient-owned contact and
   authored-target projections, decrypts emoji, and rewrites title/body/thread.
   Wire projection and reaction-token reconciliation through actual add/update/
   block/unblock/delete/re-add callsites and backfill.
7. Extend Android/iOS push staging and Dart ingestion with `kind=reaction` and a
   `replayInboxReaction` callback. Carry the reaction event id through remote
   marker creation/consumption; validate before claiming. Add atomic durable
   event/tone stores with expiry/cap pruning and deterministic notification/
   collapse identity shared by Dart, Go, and Swift.
8. Add dynamic conversation metadata in `FlutterNotificationService`, preserve
   channel ids/group behavior, and remove `String.hashCode` from cross-process
   card identity.
9. Pin the consolidated pipeline test in `ONE_TO_ONE_TESTS` and
   `ONE_TO_ONE_HOST_TESTS`; mirror the inventory in
   `test-gate-definitions.md`; register provenance, normal-message unread
   lifecycle, Android reaction, and iOS reaction scenarios in
   `check_reliability_simulation_discovery.sh`; update
   `52-notification-journey-test-matrix.md` and `_current-test-map.md` with the
   final evidence state.
10. Run focused GREEN, representative mutation re-red, privacy/preservation
   sentinels, the curated 1:1 lane, justified feature/core sweeps, Swift/Go
   direct gates, then TC-13/14/16 on a staging relay running the candidate
   build. Do not edit Orbit/read production code unless TC-15/16 proves a
   current regression rather than a harness or environment failure.

## Risks And Blind Spots

- Outer ADD is not content authority -> TC-04 binds its sender to the
  authenticated relay stream, while TC-03 cross-checks decrypted
  action/id/sender before persistence or private preview; the hint may trigger a
  typed wake but cannot commit a forged reaction.
- Remote/local/live/inbox copies race -> TC-02 and TC-10 use atomic event-aware
  dedupe,
  not route-wide suppression that could drop a later legitimate reaction. The
  separate conversation tone lease silences a later event without dropping its
  card update.
- Staged reaction arrives before ordinary inbox drain -> TC-09 dispatches it to
  the reaction replay seam and retains retryable outcomes; it never clears or
  parses the bytes as chat.
- Live staging can fail before replay -> TC-19 closes the raw-listener bypass
  and rejects a unit-only dependency injection that leaves `main.dart` unwired.
- Android background isolate may not have ML-KEM -> TC-07 intentionally proves
  a production typed decrypt plus local-state semantic fallback, while Report
  73 owns broader ordinary-message decrypt wiring.
- iOS simulator can make a fixture card without invoking the genuine NSE ->
  TC-08 is deterministic logic proof and TC-14 is the physical provider/NSE
  boundary.
- Lifecycle / derived-state durability: no schema changes; TC-08 rebuilds and
  garbage-collects contact/authored-target projections, TC-10 prunes claims/
  leases, and staging disposition plus relay custody are covered by
  TC-05/09/13/14/19.
- Mixed-version and rollback risk -> TC-20 keeps base v2 readable in both
  directions and makes flag-off a silent-store rollback, never a custody drop.
- Notification activity and unread-message state can be conflated -> TC-15/17
  lock the repository/UI/accessibility meaning, while TC-13/14 prove the OS
  reaction path creates no message row or unread orbit.
- A phone-card dismissal or route attempt could clear too early -> TC-16 holds
  unread state across dismissal and requires a real conversation render/read
  commit before the repository event clears Orbit.
- Sibling-surface consistency: ordinary 1:1/group and group-reaction paths are
  preserved by TC-12; Plan 256 does not generalize group reaction pushes.
- Destructive-action side effects: N/A — reactions and notifications do not
  delete user data; notification-tap dismissal remains existing behavior.
- Invariant re-verification under new transitions: TC-03/05/09 re-check outer
  action mismatch, REMOVE silence, legacy v2 tolerance, and staged replay;
  TC-15/17 re-check message-only count, satellites, and accessibility after the
  new reaction transitions.

## Gate Cadence

- Per-plan closure: focused Dart/Go/Swift/Kotlin tests, exact privacy and group
  sentinels, `./scripts/run_test_gates.sh 1to1`,
  `./scripts/run_host_test_gates.sh feature-host-all`, and
  `./scripts/run_host_test_gates.sh core-host-all`. Both family sweeps are
  justified because this plan changes production under `lib/features/**` and
  `lib/core/notifications/**`.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the reaction-notification
  dependency wave (Plan 256 plus any Report 73 Android-decrypt reopen), and once
  at final rollout/release closure.
- Shared tests outside feature/core globs: run relay Go tests, Swift XCTest,
  Android background-plugin unit/real-FCM preflight,
  device discovery/artifact validation, and the directly named group-reaction
  and Orbit/message-read preservation tests with the exact commands below.

## Acceptance Gates

```bash
# Snapshot before execution; record and preserve unrelated changes.
git status --short

# First causal RED after adding the named test; expect non-zero because HEAD
# returns the generic/unsupported reaction fallback instead of actor/body copy.
flutter test test/features/push/application/push_decrypt_preview_test.dart \
  --plain-name 'reaction preview uses validated actor and semantic body'

# Author-policy and concurrent duplicate REDs; HEAD notifies an incoming target
# and two barrier-released copies can both announce.
flutter test \
  test/features/conversation/application/handle_incoming_reaction_use_case_test.dart \
  --plain-name 'only target author is notified while both target directions persist'
flutter test \
  test/features/conversation/application/handle_incoming_reaction_use_case_test.dart \
  --plain-name 'concurrent exact ADD has one change and one notification'

# Android engine RED/preflight. The unit leg must pass before the real-FCM
# preflight; the preflight must run before typed wire enablement.
flutter test packages/background_push_crypto/test/background_push_crypto_test.dart
(cd android && ./gradlew :background_push_crypto:testDebugUnitTest \
  --tests 'com.mknoon.background_push_crypto.BackgroundPushCryptoPluginTest')
dart run integration_test/scripts/run_1to1_reaction_notification_device.dart \
  --scenario android_background_crypto_preflight \
  --recipient 21071FDF600CSC \
  --artifact-dir build/reaction_notification_proof/android_background_crypto_preflight

# Relay REDs; HEAD emits no typed/capability-gated reaction push.
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test -count=1 \
  -run '^TestInboxStore_ReactionAddRequiresCapabilityAndAuthorization$' ./...)
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test -count=1 \
  -run '^TestInboxStore_ReactionNonAddOrIneligibleNeverSendsPush$' ./...)

# Focused Dart GREEN; exit 0 with zero failed tests.
flutter test \
  test/features/conversation/domain/models/reaction_payload_test.dart \
  test/features/conversation/application/send_reaction_use_case_test.dart \
  test/features/conversation/application/remove_reaction_use_case_test.dart \
  test/features/conversation/application/handle_incoming_reaction_use_case_test.dart \
  test/features/conversation/domain/repositories/reaction_repository_impl_test.dart \
  test/features/conversation/integration/reaction_notification_pipeline_test.dart \
  test/core/services/p2p_service_impl_test.dart \
  test/core/lifecycle/main_replay_disposition_wiring_test.dart \
  test/features/contacts/application/block_contact_use_case_test.dart \
  test/features/contacts/application/unblock_contact_use_case_test.dart \
  test/features/contacts/domain/repositories/contact_repository_impl_test.dart \
  test/features/contacts/integration/direct_notification_projection_lifecycle_test.dart \
  test/features/contacts/integration/contact_push_eligibility_reconcile_test.dart \
  test/features/push/application/push_decrypt_preview_test.dart \
  test/features/push/application/background_push_notification_fallback_test.dart \
  test/features/push/application/background_message_handler_test.dart \
  test/features/push/application/background_message_handler_staging_test.dart \
  test/features/push/application/ingest_staged_push_envelopes_use_case_test.dart \
  test/features/orbit/presentation/screens/orbit_unread_indicator_wired_test.dart \
  test/features/orbit/presentation/widgets/orbital_visualization_test.dart \
  test/core/notifications/notification_route_target_test.dart \
  test/core/notifications/app_root_notification_open_test.dart \
  test/core/notifications/deterministic_notification_id_test.dart \
  test/core/notifications/durable_notification_tone_lease_test.dart \
  test/core/notifications/remote_notification_identity_test.dart \
  test/core/notifications/flutter_notification_service_test.dart \
  test/core/notifications/recent_remote_notification_gate_test.dart

# Relay and privacy GREEN; pinned toolchain, every load-bearing negative selected,
# default-off rollout/rollback proven, and no forbidden plaintext fields.
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test -count=1 \
  -run 'Reaction(Add|NonAdd|Capability|Rollout)|BuildReactionPush|AuthenticatedRemotePeer|Forbidden' ./...)
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test -count=1 \
  -run '^TestInboxStore_ReactionNonAddOrIneligibleNeverSendsPush$' ./...)
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test -count=1 \
  -run '^TestInboxStore_ReactionCapabilityRolloutAndRollback$' ./...)
flutter test test/security/forbidden_field_classifier_test.dart

# iOS resolver/staging GREEN on the currently available simulator; exit 0.
xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,id=DBE8C32E-9F19-4593-860A-B41113791D79' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:RunnerTests/NotificationPreviewResolverTests

# Exact production wiring/bypass sentinels.
flutter test test/core/services/p2p_service_impl_test.dart \
  --plain-name 'reaction stage failure uses shared notify-capable fallback exactly once'
flutter test test/features/conversation/domain/models/reaction_payload_test.dart \
  --plain-name 'unknown action is rejected even when outer and inner match'

# Exact preservation sentinels; every command exits 0 and selects at least one
# named test (no cross-file --plain-name filter that silently runs zero cases).
flutter test test/features/push/application/push_decrypt_preview_test.dart \
  --plain-name 'decrypts 1:1 ciphertext preview with sender title'
flutter test test/features/push/application/push_decrypt_preview_test.dart \
  --plain-name 'decrypts group ciphertext preview with sender-prefixed body'
flutter test test/core/notifications/flutter_notification_service_test.dart \
  --plain-name 'notification id is per-conversation and stable across a burst'
flutter test test/core/notifications/notification_route_contract_matrix_test.dart \
  --plain-name 'conversation remote data resolves to the canonical target'
flutter test test/features/groups/application/group_message_listener_test.dart \
  --plain-name '127-Bug-D'

# Message-only unread lifecycle and reaction-negative sentinels. All are GREEN
# on HEAD; they protect the boundary while the reaction pipeline changes.
flutter test \
  test/features/orbit/presentation/screens/orbit_unread_indicator_wired_test.dart \
  --plain-name 'TC-194-10: incoming message lights the node live'
flutter test \
  test/features/orbit/presentation/screens/orbit_unread_indicator_wired_test.dart \
  --plain-name 'TC-194-11: second message increments satellites without node re-entrance'
flutter test \
  test/features/orbit/presentation/screens/orbit_unread_indicator_wired_test.dart \
  --plain-name 'TC-194-16: externally-pushed conversation read clears the lit node (read event) [PROD-CRITICAL]'
flutter test \
  test/features/orbit/presentation/widgets/orbital_visualization_test.dart \
  --plain-name 'TC-194-27: lit node semantics announces unread; unlit label unchanged'
flutter test test/core/notifications/app_root_notification_open_test.dart \
  --plain-name 'warm local notification tap prepares conversation target before route'
flutter test \
  test/features/conversation/domain/repositories/message_repository_impl_test.dart \
  --plain-name 'markConversationAsRead emits peerId on conversationReadStream when rows>0, and nothing when 0'
flutter test \
  test/features/conversation/integration/reaction_notification_pipeline_test.dart \
  --plain-name 'reaction activity never increments unread-message orbit state'

# Registration/discovery; target pipeline test and all five runner scenarios
# (including the headless-plugin preflight) listed.
./scripts/run_test_gates.sh completeness-check
./scripts/run_host_test_gates.sh 1to1 --list
dart run integration_test/scripts/run_1to1_reaction_notification_device.dart \
  --list-scenarios
./scripts/check_reliability_simulation_discovery.sh

# Runner/proof binding. Each campaign command invokes the named proof test and
# this validator consumes app/SQLCipher/provider artifacts, not runner booleans.
dart run integration_test/scripts/run_1to1_reaction_notification_device.dart \
  --validate-artifacts build/reaction_notification_proof

# Physical iOS notification boundary; the runner prepares the peers/provider,
# then this XCUITest drives SpringBoard and validates tap/navigation artifacts.
xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS,id=00008150-001C3C6A3684401C' \
  -only-testing:RunnerUITests/NotificationTapUITests/testReactionNotificationTap

# Per-plan named/family gates; exit 0 and zero failed tests.
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh feature-host-all
./scripts/run_host_test_gates.sh core-host-all

# Hygiene; analyzer stays within the recorded repository baseline and no
# whitespace errors are introduced.
./scripts/check_flutter_analyze_baseline.sh
git diff --check
```

## Device/Relay Proof Profile

- Profile: os-notification-device-lab.
- Boundary being proven: real relay eligibility, FCM/APNs provider delivery,
  reaction capability/authorization, headless-engine plugin registration,
  background/terminated process behavior, real SQLCipher contact/target lookup,
  real Go ML-KEM/AES-GCM preview decryption, iOS NSE execution, OS-rendered
  title/body/thread, bounded notification tap, staged/inbox materialization,
  Android one-card replacement/iOS one-audible-thread dedupe, and the foreground ordinary-message OS-card -> real
  conversation-read -> Orbit-clear lifecycle. Host fakes cannot prove all of
  these composed boundaries.
- Live availability check (2026-07-11 22:10 CEST):
  `flutter devices --machine`, `adb devices -l`, `flutter emulators`, and
  `xcrun simctl list devices available` found USB Pixel 6
  `21071FDF600CSC`, Android AVD `mknoon_play_35` (runtime serial
  `emulator-5554` when booted), physical iPhones
  `00008150-001C3C6A3684401C`, `00008110-00184D622289801E`, and
  `00008030-001A6D2801BB802E`, plus booted iPhone 16e simulator
  `DBE8C32E-9F19-4593-860A-B41113791D79`. Re-run discovery immediately before
  proof; unavailable targets are `N/A (target unavailable by project policy)`.
- Required setup: clean candidate builds, notification permission granted by
  the harness, unique A/B identities and mutual contact state, staging relay
  running the Plan 256 binary with typed wake default-off until preflight,
  valid capability-bearing platform push tokens and recipient reaction
  authorization, clear notification
  trays, production native crypto frameworks/plugins loaded, timestamped
  redacted app/relay/provider logs, an Orbit-readable UI automation/accessibility
  tree, and no concurrent use of either selected target.
- Two-peer default: TC-13 and TC-16 pin sender A=`emulator-5554` and recipient
  B=`21071FDF600CSC`. TC-16 keeps B active on Orbit and drives two ordinary
  messages, notification dismissal, replacement-card tap, conversation render,
  read commit, and return-to-Orbit assertions. TC-13 then drives message
  creation, app backgrounding, `am kill`, UI long-press, emoji selection, shade
  inspection, process restart, two distinct reactions, a reaction-to-A's-own-
  message negative, bounded node tap, and reaction assertions. Both are fully
  automated with no user taps.
- iOS-specific topology: TC-14 pins Android sender A=`21071FDF600CSC` and
  physical iPhone recipient B=`00008150-001C3C6A3684401C`. A physical iPhone is
  required specifically for real APNs/NSE proof; the XCUITest harness performs
  permission handling, termination, card inspection, and tap automatically.
- Closure role: TC-13, TC-14, and TC-16 are required closure evidence while
  their targets are available. If a named target is unavailable at execution,
  that leg is recorded N/A by project policy; host/relay/platform tests still
  run.
- `FLUTTER_DEVICE_ID`: host selector only; it is insufficient because each
  scenario needs both explicit peer ids plus relay/provider configuration.
- Registration: `integration_test/one_to_one_reaction_notification_proof_test.dart`
  is AUTO-classified by the existing `_proof_test.dart` rule. The runner must
  invoke that proof and its artifact validator; manually register both the
  runner in `classify_path`/`expand_record_to_checks` and scenarios
  `head_provenance`, `android_background_crypto_preflight`,
  `android_message_unread_lifecycle`,
  `android_physical_recipient`, and `ios_physical_recipient` in the canonical
  reliability discovery inventory under `1to1`.
- Discovery command:
  `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --list-scenarios && flutter devices --machine && adb devices -l && flutter emulators && xcrun simctl list devices available`
  -> all five scenarios and every selected id must be present.
- Clean-HEAD provenance command (must run before production edits):
  `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --scenario head_provenance --sender emulator-5554 --recipient 21071FDF600CSC --artifact-dir build/reaction_notification_proof/head_provenance`
  -> exit 0 only after recording app/relay revisions, the reaction event id,
  remote type, actual producer, lifecycle, title/body, and tap route; no-card is
  an allowed HEAD observation but a card unrelated to the exact reaction id is
  rejected.
- Android headless-plugin preflight command (before typed wire enablement):
  `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --scenario android_background_crypto_preflight --recipient 21071FDF600CSC --artifact-dir build/reaction_notification_proof/android_background_crypto_preflight`
  -> recipient Activity is absent, a real FCM callback records plugin
  registration/decrypt success, and foregrounding later proves the main Go
  event callback was not replaced. Failure triggers the TC-07 stop condition.
- Android ordinary-message unread lifecycle closure command:
  `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --scenario android_message_unread_lifecycle --sender emulator-5554 --recipient 21071FDF600CSC --artifact-dir build/reaction_notification_proof/android_message_unread_lifecycle`
  -> exit 0 with B already on Orbit; SQLCipher/UI unread counts and visible
  satellites `0 -> 1 -> 1 after card dismissal -> 2 -> 0 after tap/read`;
  ordinary sender/body card copy; a real conversation route/render/read marker;
  both target messages visible; and no indicator after automated return to
  Orbit. The validator rejects a hidden-widget-only result or any clear before
  the read commit.
- Android closure command:
  `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --scenario android_physical_recipient --sender emulator-5554 --recipient 21071FDF600CSC --artifact-dir build/reaction_notification_proof/android_physical_recipient`
  -> exit 0 with one matching reaction id, `Alice` /
  `Reacted 👍 to your message`, Android message category, a real
  decrypt-success marker, no `New Message`, empty recipient `pidof` before
  delivery/tap, a second restart-separated event replacing the same card id,
  correct conversation-open marker, stored emoji, zero
  reaction-created message/unread rows, no Orbit indicator after return, and no
  duplicate/navigation errors. The paired own-target reaction must persist on B
  without any B push/card.
- iOS closure command:
  `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --scenario ios_physical_recipient --sender 21071FDF600CSC --recipient 00008150-001C3C6A3684401C --artifact-dir build/reaction_notification_proof/ios_physical_recipient`
  -> exit 0 with NSE decrypt success, `Alice` / `Reacted 👍 to your message`,
  peer thread, no forbidden push fields, typed silent timeout fallback, correct
  cold tap, stored emoji, and no reaction-created message/unread rows. Both
  arrival orders produce one audible alert; any retained second item is passive
  and in the same thread.
- Deferred device work: unavailable OS/API bands are N/A. An optional second
  physical iPhone/Android role reversal may add confidence but is not a closure
  condition.

## Execution Interpretation And Done Criteria

- Expected RED: TC-07 lacks a headless production channel; TC-04 emits no
  reaction push and accepts caller-supplied sender attribution; TC-02 can notify
  twice concurrently; TC-18 notifies a non-author; TC-19 bypasses notify deps;
  TC-06/08/09 do not recognize, eligibility-gate, or stage the reaction type.
- Green sentinel: TC-01 preserves the remembered local fix; TC-05 and TC-12
  preserve REMOVE silence, custody/wake gates, ordinary messages, group
  reactions, mute, active-conversation suppression, and stable ids. TC-15/16
  preserve the normal message `arrive -> unread orbit -> successful
  notification-open/read -> clear` lifecycle; TC-17 preserves the inverse rule
  that reaction activity never becomes message unread state.
- Pre-existing dirty tree / known failure: planning observed extensive unrelated
  media/private-media, Android/iOS, plan/index, Graphify, l10n, test, and gate
  changes. Do not revert or absorb them. One parallel Flutter probe lost a
  native-asset install-name race; the same reaction test passed immediately
  when rerun serially, so that collision is not a product baseline failure.
- Environment blocker: none for TC-00. The user explicitly authorized EC2
  access, and TC-00 kept all EC2 administrative access to read-only
  version/hash/journal inspection. The two test identities still made expected
  protocol writes for their message, reaction, and recipient token registration;
  no relay binary/config/service operation was performed. Later rollout/device
  closure may not infer authority to restart the single live relay.
- Scope drift: cleartext preview fields, group-reaction transport changes, a DB
  migration, app-wide MessagingStyle/communication-notification work, or a need
  to fix an unrelated normal-message generic card blocks completion and requires
  a scoped follow-up. A new reaction badge/activity inbox also requires a
  separate product decision; it may not be smuggled into `unreadCount` here.

- [x] Every behavior has its named test or justified proof implemented.
- [x] TC-00 records clean-build producer provenance and resolves the current
      evidence gate.
- [x] TC-07's real-FCM headless-plugin preflight passes before typed wire/push
      enablement, or its stop condition is applied and the plan is re-reviewed.
- [x] Causal RED, focused GREEN, and representative mutation re-red are
      recorded.
- [ ] Relay privacy, preservation, curated 1:1, and core family gates pass;
      `feature-host-all` remains explicitly delegated to the user's other
      session and is not claimed here.
- [x] Harness/gate/discovery/matrix registrations are synchronized and listed.
- [x] TC-15/17 prove message-only unread semantics at host level: ordinary
      messages control count/satellites/accessibility, reactions do not.
- [ ] TC-13/14/16 pass on available targets or are recorded N/A exactly under the
      project device policy.
- [ ] TC-16 proves dismissal leaves ordinary messages unread and only the real
      notification-open conversation read clears the Orbit indicator.
- [ ] TC-13/14 artifacts prove reaction delivery/tap creates no message row,
      unread count, satellite, or unread-message accessibility state.
- [x] TC-18/19 prove author-only display and the staging-error fallback; TC-20
      proves old/new compatibility and flag-off silent-store rollback.
- [ ] The broad analyzer baseline still reports unrelated dirty-tree lint
      drift with zero analyzer errors; Plan-256 scoped analysis passes and
      `git diff --check` is clean.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command:
  `flutter test test/features/push/application/push_decrypt_preview_test.dart --plain-name 'reaction preview uses validated actor and semantic body'`.
- Preservation command:
  `flutter test test/features/conversation/application/handle_incoming_reaction_use_case_test.dart --plain-name 'only target author is notified while both target directions persist' && flutter test test/features/orbit/presentation/screens/orbit_unread_indicator_wired_test.dart --plain-name 'TC-194-10: incoming message lights the node live' && flutter test test/features/orbit/presentation/screens/orbit_unread_indicator_wired_test.dart --plain-name 'TC-194-16: externally-pushed conversation read clears the lit node (read event) [PROD-CRITICAL]'`.
- Registration completed: the consolidated pipeline test is pinned in
  `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS`; the gate docs are mirrored;
  runner/proof/artifact scenarios `head_provenance`,
  `android_background_crypto_preflight`,
  `android_message_unread_lifecycle`, `android_physical_recipient`, and
  `ios_physical_recipient` are registered in reliability discovery. All other
  Dart component
  tests use existing AUTO globs/direct classification.
- Migration: none; no DB version or SQLCipher schema work.
- Boundary closure: Go relay host contract + Swift NSE tests + availability-
  bounded, fully automated Android physical/emulator and physical-iPhone NSE
  proof with real SQLCipher and ML-KEM/AES-GCM paths, plus the Android foreground
  message-notification/unread-orbit lifecycle.
- Resolved evidence: TC-00 bound the clean-HEAD reaction to the deployed relay
  store and confirmed provider no-send plus no Android app card. The user's
  remembered generic card therefore came from an older/different producer or an
  ordinary-message event, not the current reaction path. This does not close the
  bug: current remote behavior is silence, and the typed reaction path remains
  required.
- Review state: independent `$tdd-review` completed on 2026-07-11; its
  source-backed author, native-engine, contact projection, concurrency,
  mixed-version, runner, and gate deltas are incorporated above. Implementation
  and TC-07 are done; resume only the manifest-backed TC-13/14/16 device proof
  and the user-delegated `feature-host-all` gate.

## Prior Execution Preflight Contract (2026-07-12 00:14 CEST)

- **Validated at:** 2026-07-12 00:14 CEST for a fresh full-orchestrator retry.
- **Invocation topology:** controller -> fresh isolated Executor -> fresh
  independent QA Reviewer, with no role overlap. Any blocking QA finding uses a
  fresh bounded Executor fix pass, up to three fix passes total.
- **Source of truth and exact scope:** this plan, especially `Scope Contract And
  Guard`, `Test Contract`, `Implementation Steps`, `Acceptance Gates`, and
  `Device/Relay Proof Profile`, subject to `AGENTS.md` and the governing gate
  scripts. Current source still confirms the typed remote-reaction gap; the
  absent runner/plugin/pipeline artifacts are expected work, not stale-plan
  evidence.
- **Closure bar:** all TC-00..TC-20 behaviors have their named regression or
  justified boundary proof; TC-00 attribution and the TC-07 real-FCM preflight
  run before typed wire enablement; required direct, relay, Swift, Kotlin,
  curated `1to1`, `feature-host-all`, and `core-host-all` evidence resolves;
  availability-bounded TC-13/14/16 proof resolves as pass or policy-defined
  N/A; analyzer baseline and `git diff --check` resolve; no blocking independent
  QA finding remains. Full `host-all` is explicitly not a per-plan gate.
- **Code-entry ownership:** the direct reaction model/send/remove/receive,
  reaction repository, listener, P2P fallback, relay inbox/auth/capability,
  push preview/fallback/staging/ingestion/routing, deterministic identity/atomic
  claim/durable tone, local notification, contact/authored-target projection,
  app wiring, Android every-engine crypto plugin, and iOS NSE/projection seams
  enumerated in `Problem And Evidence` and `Implementation Steps`. The Executor
  also owns only the named tests, fixtures, proof runner, gate registrations,
  and matrix/current-map updates needed by this plan.
- **Regressions to add first:** TC-00 runner/proof/artifact attribution and the
  TC-07 Android plugin unit plus real-FCM preflight precede production wire
  edits. Then add the three named causal REDs for reaction preview,
  target-author notification eligibility, and concurrent exact ADD, followed by
  the remaining TC-02..TC-12 and TC-17..TC-20 contracts. There is no valid
  `none` regression exemption for this plan.
- **Exact direct tests and named gates:** the literal commands in `Acceptance
  Gates` are mandatory and may not be replaced by smaller ad hoc commands. The
  five separately named unread/message-route sentinels must each select a test;
  Go uses `GOTOOLCHAIN=go1.25.0`; Swift and Kotlin remain direct platform gates;
  device commands use freshly discovered explicit IDs. Governing script
  precedence is `scripts/run_test_gates.sh`,
  `scripts/run_host_test_gates.sh`, and
  `scripts/check_reliability_simulation_discovery.sh`, with
  `Test-Flight-Improv/test-gate-definitions.md` as mirrored documentation.
- **Known-failure interpretation:** the previously observed parallel Flutter
  native-asset install-name collision is acceptable only if the exact focused
  slice passes on an immediate serial rerun and current changes did not widen
  it. No other known failure is pre-authorized. Required provider/relay proof
  that cannot run is `environment_blocked`, except an unavailable device target
  is recorded `N/A (target unavailable by project policy)` rather than a
  blocker.
- **Done criteria:** the checklist under `Execution Interpretation And Done
  Criteria` is binding, including causal RED/GREEN and representative mutation
  re-red evidence, synchronized registrations, author-only persistence/display,
  staging-error fallback, mixed-version rollback, message-only unread semantics,
  and exact OS-boundary artifacts.
- **Non-goals/scope guard:** no group-reaction transport change, DB migration,
  reaction table/badge/activity inbox, unread-orbit semantic change,
  notification channel/prompt/action, app-wide MessagingStyle/Communication
  Notification redesign, private cleartext preview, or production deployment.
  A normal-message generic-card cause or an inability to preserve a coherent
  caller/callee/test seam stops execution rather than widening scope.
- **Scoped pre-existing worktree overlap:** extensive user-owned changes are
  present and must not be reverted or absorbed. Plan-overlap baseline hashes at
  preflight are: gate definitions `d32e9882`, Android build `ab1c39ec`,
  `MainActivity.kt` `10bbc285`, root `info.plist` `63bb7ec9`, Xcode project
  `475fe2e4`, `AppDelegate.swift` `82e317d8`, `push_decrypt_preview.dart`
  `e968803e`, `main.dart` `93d6e8ec`, host gate `1377e908`, reliability gate
  `cb20a49f`, and `push_decrypt_preview_test.dart` `c46d0ea7`. Their existing
  diffs are respectively `73/0`, `4/0`, `40/0`, `1/1`, `9/0`, `8/0`, `21/2`,
  `244/1`, `34/0`, `45/0`, and `166/0` added/deleted lines. The plan itself was
  untracked with pre-retry SHA-256
  `e859d7ef5d119b96a6d638f36062c057137f34f019e6e200db25856f41037ffc`;
  the retained TC-00 proof file was also untracked with SHA-256
  `1785807c49106d9718a48abf82bf525a1fcf2d8fecba5724795ede888be6dd7d`.
  Executor/QA must attribute new hunks explicitly against this snapshot.
- **Graph grounding:** reused plan anchors plus one exact execution query;
  fingerprint `bf874be415eaf2e3`, `confidence=anchored`, freshness
  `stale:lib/main.dart`. It confirmed `NotificationPreviewResolver`,
  `ONE_TO_ONE_TESTS`, and `ONE_TO_ONE_HOST_TESTS`; relay/native gaps still
  require current-source verification. After a scoped diff, use one
  `affected ... --budget 600` query, then exactly one final incremental refresh
  only after acceptance.
- **Live availability snapshot:** physical Android `21071FDF600CSC`, physical
  iPhone `00008150-001C3C6A3684401C`, and simulator
  `DBE8C32E-9F19-4593-860A-B41113791D79` are currently discovered; AVD
  `mknoon_play_35` is available but not booted. Re-resolve before device proof.
- **Fresh-retry role milestones:** the initial Executor's first bounded
  milestone is to materialize
  `integration_test/scripts/run_1to1_reaction_notification_device.dart`, add
  only its required 1:1 discovery expansion, and make `--list-scenarios` emit
  all five exact Plan-256 scenarios. Its next observable is the exact TC-00
  `head_provenance` command producing a fail-closed redacted artifact or an
  explicit provider/relay environment stop; clean-build/install and device
  automation are the known long-running commands. The independent QA role's
  first bounded milestone is a source/diff/evidence audit of TC-00 and any
  subsequently landed scope, persisted as stable `B*`/`N*` findings in this
  plan; no platform rebuild is expected unless the recorded smallest proof is
  missing or inconsistent.
- **Fresh-retry counters:** `fix_passes=0`, `materialization_retries=0`,
  `progress_extensions=0`, and controller-owned `no_progress_intervals=0`.
  The first-milestone scoped dirty-diff fingerprint is
  `7ea982d1944b727fb0aae795b97c653edb6ad3030782d349ddc43e0196962a21`;
  the runner is absent and the retained proof file is 3,273 bytes.
- **Preflight decision:** valid for execution. No plan field is missing or
  contradicted by higher-precedence evidence. TC-00 provenance and TC-07
  preflight remain mandatory stop/go evidence, not reasons to skip the initial
  Executor pass.

## Execution Preflight Contract

- **Validated at:** 2026-07-12 00:38 CEST for this fresh full-orchestrator
  invocation.
- **Invocation topology:** root controller -> fresh isolated Executor -> fresh
  independent QA Reviewer, with no overlap. A blocking QA finding returns only
  to a fresh bounded Executor fix pass, with at most three fix passes.
- **Source of truth and exact scope:** this plan's `Scope Contract And Guard`,
  `Test Contract`, `Implementation Steps`, `Acceptance Gates`, and
  `Device/Relay Proof Profile`, under `AGENTS.md` and the current gate scripts.
  Current source still has no typed remote reaction path:
  `go-relay-server/inbox.go` has no `message_reaction` metadata case,
  `lib/features/push/application/push_decrypt_preview.dart:36-49` accepts only
  chat/group message previews, and
  `ios/NotificationService/NotificationPreviewResolver.swift:149-183` accepts
  only those same types.
- **Closure bar:** implement and prove TC-00..TC-20; resolve TC-00 attribution
  and the TC-07 real-FCM headless-plugin preflight before typed wire enablement;
  pass every literal direct/platform command and the curated `1to1`,
  `feature-host-all`, and `core-host-all` gates; resolve TC-13/14/16 on the live
  availability-bounded matrix; preserve the analyzer baseline and whitespace
  hygiene; and finish with no blocking independent-QA finding. Full `host-all`
  is not a per-plan gate.
- **Code-entry ownership:** only the direct reaction model/send/remove/receive,
  repository/listener/P2P fallback, relay inbox/auth/capability, push preview/
  fallback/staging/ingestion/routing, deterministic identity/atomic claim/tone
  lease, local-notification, direct-contact/authored-target projection, app
  wiring, Android every-engine crypto plugin, iOS NSE/projection seams, and the
  exact tests/fixtures/runner/gate/matrix docs enumerated by this plan.
- **Regressions to add first:** the retained fail-closed TC-00 proof plus its
  missing runner/discovery expansion, then TC-00 clean-build provenance and the
  TC-07 plugin unit/real-FCM preflight. Only after those stop/go boundaries may
  the Executor add the named reaction-preview, target-author, concurrent-ADD,
  and remaining TC-02..TC-12/TC-17..TC-20 REDs. Regression exemption: `none`.
- **Exact direct tests and named gates:** every literal command in `Acceptance
  Gates` is mandatory. Go remains pinned to `GOTOOLCHAIN=go1.25.0`; Swift and
  Kotlin remain direct platform gates; device commands must use freshly
  discovered explicit IDs. Governing executable definitions are
  `scripts/run_test_gates.sh`, `scripts/run_host_test_gates.sh`, and
  `scripts/check_reliability_simulation_discovery.sh`; mirrored documentation
  is `Test-Flight-Improv/test-gate-definitions.md`.
- **Known-failure interpretation:** only the previously documented parallel
  Flutter native-asset install-name collision may be accepted after the exact
  focused slice passes immediately in serial and this diff did not widen it.
  No other failure has a waiver. Missing provider/relay authority is
  `environment_blocked`; an unavailable device leg is only
  `N/A (target unavailable by project policy)`.
- **Done criteria:** the complete checklist under `Execution Interpretation And
  Done Criteria` is binding, including causal RED/GREEN plus representative
  mutation re-red, synchronized registrations, author-only display with
  persistence convergence, staging-fallback parity, mixed-version rollback,
  message-only unread semantics, and exact OS-boundary artifacts.
- **Non-goals and scope guard:** no group-reaction transport change, DB
  migration/reaction table, reaction badge/activity inbox, unread-orbit
  semantic change, notification channel/prompt/action, app-wide notification
  redesign, private cleartext preview, or production deployment. A normal-
  message incident or an incoherent typed seam stops this run rather than
  widening it.
- **Scoped pre-existing worktree changes:** the extensive dirty tree remains
  user-owned. For the first milestone,
  `scripts/check_reliability_simulation_discovery.sh` is already modified only
  by two Plan-234 private-media classifications (8 added lines; SHA-256
  `1716df7212f8a41b7007cc5fc3fb956fca552cb020c5f24db5231b827d27efc7`)
  and must be preserved; the retained untracked proof is 3,273 bytes/SHA-256
  `1785807c49106d9718a48abf82bf525a1fcf2d8fecba5724795ede888be6dd7d`;
  the Plan-256 runner is absent. Other gate baselines are
  `run_test_gates.sh` `cb20a49f...fc6`, `run_host_test_gates.sh`
  `1377e908...788`, and `test-gate-definitions.md` `d32e9882...f38`.
  Existing overlapping production hashes recorded in the prior preflight
  remain user-owned; new hunks must be attributed explicitly.
- **Graph Grounding Snapshot:** the required compact execution query returned
  fingerprint `bf874be415eaf2e3`, `confidence=anchored`, freshness
  `stale:lib/main.dart`, and surfaced `NotificationPreviewResolver`,
  `ONE_TO_ONE_TESTS`, and `expand_record_to_checks`. Relay/native gaps were
  verified in current source. After a scoped diff, run one
  `affected <changed-file>... --budget 600` query; refresh incrementally exactly
  once only after accepted coherent app-owned changes.
- **Cheap baseline evidence:** runner `--list-scenarios` exits 255 because the
  planned runner is absent (expected missing artifact); completeness passes
  `1178/1178`; host `1to1 --list` passes with 88 commands; reliability discovery
  exits 1 solely for the retained, in-scope unclassified Plan-256 proof (the two
  prior unrelated private-media rows now classify); scoped `git diff --check`
  passes. The required physical Android/iPhones and booted iOS simulator are
  live; Android AVD `mknoon_play_35` is available but not booted.
- **First bounded milestones:** Executor milestone 1 is to create
  `integration_test/scripts/run_1to1_reaction_notification_device.dart`, add
  only the attributable Plan-256 classification/expansion while preserving the
  Plan-234 hunks, and make `--list-scenarios` emit all five exact scenario IDs.
  Its next checkpoint is the exact TC-00 `head_provenance` command producing a
  fail-closed redacted artifact or a precise relay/provider environment stop;
  clean build/install and device automation are the known long-running work.
  QA milestone 1 is a source/diff/evidence audit persisted with stable `B*`/
  `N*` findings; it need not rerun an expensive passing platform gate unless
  evidence is missing or inconsistent.
- **Counters and initial fingerprint:** `fix_passes=0`,
  `materialization_retries=0`, `progress_extensions=0`, and controller-owned
  `no_progress_intervals=0`. First-milestone scoped fingerprint is
  `769606f941ce9808dcfc92909d8a9b28300d131ce6cdc38169cfc98793aa6b48`.
- **Preflight decision:** valid. No higher-precedence conflict or missing
  contract field exists. The sole discovery RED and missing runner are
  attributable artifacts the plan explicitly requires the Executor to create;
  no unrelated required gate is currently red.

## Execution Progress

### Heartbeat 3 — Executor runner/discovery materialized (2026-07-12 00:47 CEST)

- **Sequence/phase:** heartbeat 3; initial Executor pass, first bounded
  milestone materialized and scenario-list proof complete.
- **Current bounded milestone:** structurally verify the new runner/discovery
  seam, then re-resolve the live device matrix and start the exact TC-00
  `head_provenance` command.
- **New source evidence:**
  `integration_test/scripts/run_1to1_reaction_notification_device.dart:16-57`
  owns exactly the five Plan-256 scenario IDs; its execution path requires an
  explicit sender/recipient/artifact directory and refuses to synthesize a
  device artifact. `scripts/check_reliability_simulation_discovery.sh:219-226`
  classifies the runner under `1to1`, and its `expand_record_to_checks` case
  delegates to the existing scenario-list expander. Decision: the discovery
  inventory can enumerate every required scenario without weakening TC-00.
- **Assigned artifacts:** new runner is 6,103 bytes/SHA-256
  `14aed945db1d425fa9b223235204131d3cac114adea722b0396cda7b97d4f521`;
  discovery is 33,023 bytes/SHA-256
  `033b2697dcd1deb32eedbe2ec6b0d1e363e36831a7f75a151e973eab1aff9eda`;
  retained proof remains 3,273 bytes/SHA-256
  `1785807c49106d9718a48abf82bf525a1fcf2d8fecba5724795ede888be6dd7d`.
  Discovery's total diff is 16 added/0 deleted lines: the original 8-line
  Plan-234 private-media hunk is intact and the other 8 lines are attributable
  Plan-256 runner classification/expansion.
- **Scoped work-diff fingerprint:**
  `fbfa8886e7c2f44d9da472eab2f3754b7649385b3c51172e5ebd2daf43bce134`,
  computed from the discovery binary diff plus runner/proof SHA-256 records and
  excluding progress-only plan edits.
- **Last completed command/result:** exact
  `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart
  --list-scenarios` exited 0 and printed, in order, `head_provenance`,
  `android_background_crypto_preflight`, `android_message_unread_lifecycle`,
  `android_physical_recipient`, and `ios_physical_recipient`; the subsequent
  size/hash/diff attribution snapshot exited 0.
- **Current command status:** none; no PID/session/log is active. Last observed
  command output was 2026-07-12 00:47 CEST.
- **Decision/blocker state:** first milestone passed; controller counters are
  `progress_extensions=2` and `no_progress_intervals=0`. No TC-00 blocker is
  classified until the exact provenance command runs.
- **Next observable checkpoint:** focused discovery verification lists the
  runner plus all five scenario IDs; live IDs are re-resolved; then the exact
  TC-00 command runs with a persisted log and either validates a redacted
  clean-build artifact or exits with a precise relay/provider environment stop.

### Heartbeat 4 — discovery verification pending triage (2026-07-12 00:49 CEST)

- **Sequence/phase:** heartbeat 4; structural validation failure recorded
  before focused triage.
- **Current bounded milestone:** classify the discovery failure without
  changing the runner/discovery patch, then proceed to TC-00 only if the
  canonical inventory is clean.
- **New source evidence:** `--list-scenarios` already proves the runner itself
  enumerates all five IDs; the canonical discovery script nevertheless exited
  before the focused output contained either the runner or retained proof.
  Decision: this is `pending_triage`, not yet attributable to Plan 256 or
  eligible for a fix.
- **Assigned artifacts:** runner remains 6,103 bytes/SHA-256
  `14aed945db1d425fa9b223235204131d3cac114adea722b0396cda7b97d4f521`;
  discovery remains 33,023 bytes/SHA-256
  `033b2697dcd1deb32eedbe2ec6b0d1e363e36831a7f75a151e973eab1aff9eda`;
  retained proof remains unchanged at SHA-256 `1785807c...e6dd7d`.
- **Scoped work-diff fingerprint:** unchanged at
  `fbfa8886e7c2f44d9da472eab2f3754b7649385b3c51172e5ebd2daf43bce134`,
  excluding progress-only plan edits.
- **Last completed command/result:**
  `./scripts/check_reliability_simulation_discovery.sh --checks-tsv` exited 1;
  the focused capture contained no Plan-256 rows. Failure file:
  `scripts/check_reliability_simulation_discovery.sh`; no persisted log was
  created for this short command.
- **Current command status:** none; no PID/session/log is active. Focused triage
  command queued:
  `./scripts/check_reliability_simulation_discovery.sh --checks-tsv` with
  unfiltered stdout/stderr capture.
- **Decision/blocker state:** `pending_triage`; no fix attempted and no waiver
  inferred. Controller counters remain `progress_extensions=2`,
  `no_progress_intervals=0`.
- **Next observable checkpoint:** the unfiltered discovery error identifies the
  exact candidate/expansion failure, which is classified as session-caused,
  pre-existing, unrelated-but-required, or tooling-related before any edit.

### Heartbeat 5 — discovery green; TC-00 handoff (2026-07-12 00:53 CEST)

- **Sequence/phase:** heartbeat 5; structural validation complete, entering the
  mandatory clean-build/device provenance boundary.
- **Current bounded milestone:** re-resolve explicit live device IDs and run the
  exact TC-00 `head_provenance` command, producing either its redacted artifact
  or the contract's precise relay/provider environment stop.
- **New source evidence:** unfiltered discovery identified only
  `integration_test/one_to_one_reaction_notification_proof_test.dart` as
  unclassified. Current source has no generic `_proof_test.dart` rule, so the
  failure was classified `session-caused/in-scope expected registration` and
  fixed with one explicit Plan-256 `1to1` test rule. The rerun now expands that
  proof's `head_provenance` declaration and all five runner scenarios.
- **Assigned artifacts:** runner remains 6,103 bytes/SHA-256
  `14aed945db1d425fa9b223235204131d3cac114adea722b0396cda7b97d4f521`;
  discovery is 33,230 bytes/SHA-256
  `09f718d971bf3c3e77242fa16a1f95fe7cc576a9036f218eb51335fe4bb848f3`;
  retained proof remains 3,273 bytes/SHA-256 `1785807c...e6dd7d`.
  Discovery's 20-added/0-deleted total diff consists of the preserved 8-line
  Plan-234 hunk plus 12 attributable Plan-256 runner/proof/expander lines.
- **Scoped work-diff fingerprint:**
  `2c9a3f656328201c04c028cfb4a0270a4c8fae0ec8cd7defdd62eee65d035b83`,
  computed from the discovery binary diff plus runner/proof hashes and
  excluding progress-only plan edits.
- **Last completed command/result:**
  `./scripts/check_reliability_simulation_discovery.sh --checks-tsv` exited 0
  and listed the proof plus `head_provenance`,
  `android_background_crypto_preflight`,
  `android_message_unread_lifecycle`, `android_physical_recipient`, and
  `ios_physical_recipient`; the single required Graphify `affected` command
  exited 0 with no reverse dependencies, so direct runner/discovery checks
  remain authoritative.
- **Current command status:** none at heartbeat write; no PID/session/log is
  active. The next command is live device discovery immediately followed by
  the exact TC-00 command and persisted command evidence.
- **Decision/blocker state:** discovery triage resolved and structural seam is
  green. Ordinary wait extensions are exhausted; no TC-00 result has yet been
  claimed.
- **Next observable checkpoint:** explicit sender `emulator-5554` and recipient
  `21071FDF600CSC` availability are recorded, and the exact TC-00 command has a
  PID/session/log while active or a persisted artifact/environment-blocker
  result after exit.

### Heartbeat 6 — controller Executor takeover (2026-07-12 00:54 CEST)

- **Sequence/phase:** heartbeat 6; initial Executor stopped after structural
  milestone completion, followed by controller-local takeover under
  `executor_local_takeover`.
- **Current bounded milestone:** resolve the runner's focused formatting
  structural failure, then run the exact TC-00 clean-build provenance command
  or persist its precise relay/provider environment stop before any production
  reaction-wire edit.
- **New source evidence:** Heartbeats 4-5 and current files show the Executor
  completed the focused discovery triage and Graphify reverse-impact check.
  Two later controller observations plus the settle poll found the same
  runner/discovery hashes, no TC-00 artifact, no further heartbeat, and no
  assigned device/build process. Decision: the coherent runner/discovery patch
  is attributable and safe for local takeover; independent QA remains
  mandatory.
- **Assigned artifacts:** runner 6,103 bytes/SHA-256
  `14aed945...f521` before formatting and 6,061 bytes/SHA-256
  `e7e4e2b9...eb36` after the mechanical fix; discovery 33,230 bytes/SHA-256
  `09f718d9...48f3`; retained proof 3,273 bytes/SHA-256
  `1785807c...e6dd7d`. No TC-00 artifact exists.
- **Scoped work-diff fingerprint:**
  `918ef28b209aee969684af44759b51c79dfa2a7dcb26e7933e7fe7696328fa9a`,
  excluding progress-only plan edits.
- **Last completed command/result:** focused emulator triage found both explicit
  Android targets live in `adb devices -l`: physical Pixel
  `21071FDF600CSC` and AVD runtime `emulator-5554`; the QEMU process is alive.
  The launcher exit is classified `tooling-related/misleading` because the AVD
  successfully booted despite Flutter reporting exit 1.
- **Current command status:** none. The exact TC-00 command completed with exit
  78; console evidence reports the absent redacted artifact and unconfigured
  staging relay/provider capture driver. No PID/session/log remains active.
- **Decision/blocker state:** TC-00 is `environment_blocked`; the explicit
  Android pair is live, but no Plan-256 clean-build relay/provider capture rig
  or `head_provenance.json` is configured. The plan's stop condition forbids
  TC-07 and typed production edits. Takeover metadata remains child subtype
  `worker_no_progress_timeout`; `fix_passes=0`, `materialization_retries=0`,
  `progress_extensions=2`, final child `no_progress_intervals=2`.
- **Next observable checkpoint:** a fresh independent QA Reviewer audits the
  runner/proof/discovery diff, structural evidence, and TC-00 environment stop,
  then persists stable findings and a blocking/clear verdict.

### Heartbeat 7 — independent QA source/diff/evidence audit (2026-07-12 00:55 CEST)

- **Sequence/phase:** heartbeat 7; fresh independent QA, first bounded source/
  diff/evidence milestone complete.
- **Current bounded milestone:** audit fail-closed behavior, discovery
  attribution, and the TC-00 blocker boundary, then persist stable `B*`/`N*`
  findings and a QA verdict without editing code.
- **New source evidence:**
  `integration_test/scripts/run_1to1_reaction_notification_device.dart:64-121,158-193`
  requires one explicit scenario, sender/recipient/artifact inputs, exits 78
  when the expected artifact is absent, rejects the four unimplemented
  validators, and invokes the retained proof only for `head_provenance`.
  `integration_test/one_to_one_reaction_notification_proof_test.dart:15-72`
  rejects missing configuration and requires clean-build, relay, exact event,
  provider, producer/lifecycle/tap, and matched-card/no-send attribution.
  Removing only the 12 Plan-256 additions from current discovery reconstructs
  SHA-256 `1716df7212f8a41b7007cc5fc3fb956fca552cb020c5f24db5231b827d27efc7`,
  exactly the active preflight's Plan-234 baseline. Decision: the scaffold is
  fail-closed and the Plan-234 hunk is untouched; neither fact satisfies TC-00.
- **Assigned artifacts:** runner 6,061 bytes/SHA-256
  `e7e4e2b95c7c2fcd1a043c2cef0cdf7a17eead06675dab9c81d7d3d54cd8eb36`;
  retained proof 3,273 bytes/SHA-256
  `1785807c49106d9718a48abf82bf525a1fcf2d8fecba5724795ede888be6dd7d`;
  discovery 33,230 bytes/SHA-256
  `09f718d971bf3c3e77242fa16a1f95fe7cc576a9036f218eb51335fe4bb848f3`.
- **Scoped work-diff fingerprint:**
  `918ef28b209aee969684af44759b51c79dfa2a7dcb26e7933e7fe7696328fa9a`,
  excluding progress/review-only plan edits.
- **Last completed command/result:** direct full source reads, hash/size/mtime
  snapshot, scoped discovery diff/`git diff --check`, and the Plan-256-removal
  reconstruction all exited 0; the reconstructed discovery hash exactly
  matched the recorded pre-Plan-256 baseline.
- **Current command status:** none; no PID/session/log is active. After this
  heartbeat, the reviewer received one grounding extension, then two unchanged
  controller observations plus the settle poll found no review section or
  active command; the reviewer was interrupted.
- **Decision/blocker state:** first independent QA attempt ended
  `qa_no_result_timeout`. The scoped fingerprint remained exactly
  `918ef28b...fa9a`, so the orchestrator's one automatic replacement QA is
  eligible. Counters: `materialization_retries=1`, total
  `progress_extensions=3`, first-QA `no_progress_intervals=2`, `fix_passes=0`.
- **Next observable checkpoint:** one fresh replacement QA materializes
  `## Independent QA Review — Fresh Invocation (2026-07-12)` with stable
  findings, required dispositions, verification commands, and an explicit
  `blocking` or `clear` verdict against the unchanged scoped patch.

### Heartbeat 8 — controller terminal verdict (2026-07-12 01:02 CEST)

- **Sequence/phase:** heartbeat 8; replacement-QA materialization failure and
  terminal controller result.
- **Current bounded milestone:** persist the final blocked evidence ledger and
  stop without an unauthorized local sequential QA substitute.
- **New source evidence:** the first independent QA produced exact fail-closed
  source/hash grounding but no review/verdict. The one permitted fresh
  replacement produced no heartbeat, review section, command, or other
  artifact across two unchanged observations and the settle poll. Throughout
  both attempts, the runner/proof/discovery fingerprint stayed
  `918ef28b...fa9a`. Decision: independent QA cannot be claimed; the separate
  TC-00 environment stop also remains unresolved.
- **Assigned artifacts:** runner 6,061 bytes/SHA-256
  `e7e4e2b9...eb36`; discovery 33,230 bytes/SHA-256
  `09f718d9...48f3`; retained proof 3,273 bytes/SHA-256
  `1785807c...e6dd7d`; no TC-00 artifact and no QA review section.
- **Scoped work-diff fingerprint:**
  `918ef28b209aee969684af44759b51c79dfa2a7dcb26e7933e7fe7696328fa9a`,
  excluding progress/result-only plan edits.
- **Last completed command/result:** final completeness passed `1178/1178`,
  canonical reliability discovery passed with the proof plus five runner
  scenarios, and final scoped `git diff --check` passed. Replacement QA was
  interrupted with previous status `running` after the required settle poll.
- **Current command status:** none; both QA roles and the Executor are stopped,
  with no child PID/session/log active.
- **Decision/blocker state:** final `blocked`, class
  `spawn_or_tool_failure`, subtype `qa_no_result_timeout`;
  `fix_passes=0`, `materialization_retries=1`, total
  `progress_extensions=3`, final controller-owned
  `no_progress_intervals=6` (Executor 2, first QA 2, replacement QA 2).
- **Next observable checkpoint:** none in this run. Retry after provisioning
  the Plan-256 staging relay/provider capture rig; rerun TC-00, then complete
  TC-07/implementation and obtain a fresh independent QA verdict.

## Executor Handoff — Fresh Invocation (2026-07-12 00:58 CEST)

- **Executor outcome:** stopped at the mandatory TC-00 environment boundary.
  The fresh child completed the runner/discovery milestone; after the child
  reached `worker_no_progress_timeout`, the controller used
  `executor_local_takeover`, fixed only runner formatting, verified the seam,
  booted/resolved the Android AVD, and ran the exact TC-00 command. No typed
  production, relay, native, model, repository, notification, unread, or app-
  wiring code was edited.
- **Attributable files:** new
  `integration_test/scripts/run_1to1_reaction_notification_device.dart`
  (6,061 bytes/SHA-256 `e7e4e2b9...eb36`); retained prior-attempt
  `integration_test/one_to_one_reaction_notification_proof_test.dart`
  (unchanged, 3,273 bytes/SHA-256 `1785807c...e6dd7d`); and 12 Plan-256 lines in
  `scripts/check_reliability_simulation_discovery.sh` for runner/proof
  classification and runner expansion. Its pre-existing 8-line Plan-234 hunk
  remains intact. Current scoped fingerprint is
  `918ef28b209aee969684af44759b51c79dfa2a7dcb26e7933e7fe7696328fa9a`.
- **Tests added or updated:** no new proof assertion in this invocation; the
  retained `head_provenance` validator remains fail-closed. The runner lists
  all five plan scenarios, invokes the proof for TC-00 when a redacted artifact
  exists, rejects missing artifacts, and marks the four not-yet-implemented
  proof validators fail-closed.
- **Evidence ledger:** all commands ran from repository root; console-only
  commands have no separate log artifact.

  | Exact command | Exit/result | Classification | Artifact/log |
  |---|---|---|---|
  | `dart format --output=none --set-exit-if-changed integration_test/scripts/run_1to1_reaction_notification_device.dart integration_test/one_to_one_reaction_notification_proof_test.dart` | initial exit 1, runner only; mechanical `dart format` applied; exact rerun exit 0 | `passed` after in-scope triage/fix | console |
  | `dart analyze integration_test/scripts/run_1to1_reaction_notification_device.dart integration_test/one_to_one_reaction_notification_proof_test.dart` | exit 0, no issues | `passed` | console |
  | `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --list-scenarios` | exit 0; all five exact IDs | `passed` | console |
  | `./scripts/check_reliability_simulation_discovery.sh --checks-tsv` | exit 0 after explicit proof classification; Plan-256 proof plus five runner rows listed | `passed` | console |
  | `python3 graphify-arch/tdd_context.py affected integration_test/scripts/run_1to1_reaction_notification_device.dart integration_test/one_to_one_reaction_notification_proof_test.dart scripts/check_reliability_simulation_discovery.sh --budget 600` | exit 0; no reverse dependencies surfaced, so direct checks remain authoritative | `passed` | console |
  | `git diff --check -- integration_test/scripts/run_1to1_reaction_notification_device.dart integration_test/one_to_one_reaction_notification_proof_test.dart scripts/check_reliability_simulation_discovery.sh Test-Flight-Improv/256-1to1-reaction-notification-context-tdd-plan.md` | exit 0 | `passed` | console |
  | `flutter emulators --launch mknoon_play_35` | launcher exit 1, but focused triage found live QEMU and `emulator-5554` in `adb devices -l` beside physical `21071FDF600CSC` | `passed` for target availability after focused triage; wrapper exit was misleading | console |
  | `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --scenario head_provenance --sender emulator-5554 --recipient 21071FDF600CSC --artifact-dir build/reaction_notification_proof/head_provenance` | exit 78; required `head_provenance.json` and configured Plan-256 staging relay/provider capture driver absent | `environment_blocked` | no artifact |
  | Every command after TC-00 in `Acceptance Gates`, including TC-07, causal RED/GREEN, direct Go/Swift/Kotlin tests, family gates, and TC-13/14/16 | not eligible under the plan's mandatory TC-00 stop condition | `environment_blocked` | none |

- **Failure triage:** discovery's initial failure was session-caused and fixed by
  the required explicit proof rule; runner formatting was session-caused and
  fixed mechanically; the misleading emulator launcher exit was tooling-only
  because the process/device came online. TC-00 remains environment-related:
  device availability is proven, but matched clean-build app/relay/provider
  evidence cannot be captured from the configured environment.
- **Remaining uncertainty:** independent QA must decide whether the runner and
  retained proof are safe partial scaffolding and whether exit 78 accurately
  represents the external boundary. It must not treat the scaffold as TC-00
  success or waive any later regression/gate/done criterion.
- **Executor recommendation (historical; superseded by the current Execution
  Result below):** final verdict could not be accepted. Provision the
  Plan-256 staging relay/provider capture rig, generate the redacted
  `build/reaction_notification_proof/head_provenance/head_provenance.json`, and
  rerun the exact TC-00 command. Only a passing attribution permits TC-07 and
  production implementation.

## Execution Result

- **Verdict:** `implementation_complete_acceptance_pending`. TC-01..TC-20 code,
  host, native, relay, and proof-harness contracts are implemented. Required
  live TC-13/14/16 artifacts remain `environment_blocked` because the redacted
  staging capture manifest is absent while their targets are available.
- **Captured:** 2026-07-12 11:15 CEST in the shared dirty worktree. Unrelated
  user changes were preserved. No relay deploy, restart, config, binary, or
  administrative write was performed.
- **Implemented behavior:** typed additive reaction metadata; authenticated,
  capability-gated and default-off relay wake/push; recipient-owned actor and
  author eligibility; Android headless SQLCipher + generated crypto plugin;
  iOS shared-Keychain projection/NSE decrypt; reaction-kind staging/replay;
  notification route/tap identity; atomic SQLCipher ADD/REMOVE convergence;
  durable event claims and one audible tone per conversation window; and
  reaction-negative ordinary-message unread/Orbit semantics.
- **Concurrency/compatibility closure:** Dart foreground/background isolates
  and the Swift NSE use `flock` on the same persistent App Group coordination
  file. The causal holder/contender isolate test proves the contender cannot
  complete before release. Swift concurrent-winner tests pass. A frozen exact
  copy of the pre-256 reader accepts the new additive envelope, and the current
  reader accepts a committed legacy v2 fixture.
- **TC-00:** passed at
  `build/reaction_notification_proof/head_provenance/head_provenance.json`;
  clean HEAD/deployed relay stored the reaction but emitted no provider push or
  generic card, confirming the missing typed remote path rather than an
  ordinary-message detour.
- **TC-07:** passed on physical Pixel `21071FDF600CSC` at
  `build/reaction_notification_proof/android_background_crypto_preflight/android_background_crypto_preflight.json`.
  It proves killed-process FCM receipt, generated plugin registration, native
  `decryptMessage` only, trusted `TC256 Alice` / `Reacted 👍 to your message`
  copy, one card, and post-background Go callback. Cleanup is acknowledged
  before restoration; the synthetic rows/card/claims are removed. The local
  and reinstalled candidate APKs both restored to SHA-256
  `a36160c4e1ca5a99837c06297a8588a5eb8726fcf95a44456b2aae39fba10dff`.
- **Passing gates/evidence:** focused combined Dart suite (489 tests); curated
  `./scripts/run_test_gates.sh 1to1` (1,978 tests); `core-host-all` items
  1..306 with the final item-215 rerun green; full relay Go suite; go-mknoon
  bridge/node suites; Android crypto-package Dart/Kotlin tests; 29-test Swift
  `NotificationPreviewResolverTests`; scoped analyzer; completeness
  `1185/1185`; reliability discovery; all five runner scenarios; exact TC-07
  artifact validation; and `git diff --check`.
- **Graph:** the final architecture affected query completed and
  `./graphify-arch/refresh_arch_graph.sh --incremental` refreshed 100 changed
  code files plus the deterministic TDD overlay.
- **Delegated gate:** per the user's explicit instruction,
  `./scripts/run_host_test_gates.sh feature-host-all` was stopped and is neither
  passed nor failed here. The user will run it in a separate session. Full
  `host-all` is not a per-plan gate under the repository cadence.
- **Analyzer baseline:** the broad baseline command exits 1 with zero analyzer
  errors because this shared dirty tree contains unrelated lint-fingerprint
  drift in existing integration harnesses and account-migration files.
  Plan-256 scoped analysis reports no issues; the one touched DB-opener brace
  lint was removed. No unrelated lint sweep was absorbed into this plan.
- **Independent QA:** final counterexample audit returned `READY` for the
  repaired tone-lock, exact frozen-reader, and TC-07
  cleanup/restoration/redaction seams; no P0/P1 blocker remains in implemented
  scope.
- **Unresolved live proof:** TC-13 `android_physical_recipient`, TC-14
  `ios_physical_recipient`, and TC-16 `android_message_unread_lifecycle` each
  fail closed with exit 78 until the staging/provider capture manifest is
  supplied. This is not N/A because the Android and iOS targets are available.
- **Resume instruction:** supply the redacted staging capture manifest and run
  TC-13/14/16; merge the separately-run `feature-host-all` result. Reopen code
  only for a real regression or a failed artifact counterexample.

## Post-implementation live Android verification and scoped relay rollout (2026-07-12)

- **Requested Android verdict:** `passed`. One uninterrupted automated campaign
  used Android emulator `emulator-5554` as reaction sender and USB Pixel 6
  `21071FDF600CSC` as notification recipient. User A received a real message,
  long-pressed it, selected `👍`, and user B received exactly one relay/FCM card
  with title `TC256-A` and body `Reacted 👍 to your message`. The generic
  `New Message` fallback was rejected before an automated notification tap
  opened A's conversation.
- **Unread lifecycle:** `passed` with visible Orbit semantics
  `[0, 1, 1, 2, 0]`. The reaction created no unread-message dot; the first
  ordinary message created one unread; dismissing its notification preserved
  one; the second ordinary message raised the count to two and reused the same
  deterministic notification id (`717140209`); tapping it displayed both
  messages and cleared Orbit to zero. The post-tap Orbit observation used an
  Android launcher-root reopen with `NEW_TASK|CLEAR_TASK`, never `am force-stop`,
  because a cold-start notification conversation is the task root and has no
  in-app route to pop.
- **Primary evidence:**
  `build/reaction_notification_proof/live_typed_reaction_smoke/live_typed_reaction_smoke.json`
  (`status=passed`, captured `2026-07-12T14:37:44.680501Z`). Sanitized relay,
  reaction, notification, notification-tap, ordinary-card, and unread-tap logs
  are adjacent. The stale failure artifact was removed by the successful run.
- **Candidate provenance:** the tested APKs were built successfully from
  `84e8ead5d98928d60b1581bdb517b0f307503c35+working-tree` immediately before an
  unrelated concurrent group-media edit temporarily broke compilation. The
  fail-closed reuse path revalidated build profile, HEAD revision, and both
  persisted hashes before install: E2E
  `dc103677e05d79e12f5f0d32a43a8f689fad25c72a0eba155bdfd699cc23db8b` and normal
  `5ff5fc6f0b05484d73c077ce03ca95e064831a713933dc5eac802c775245ea3d`.
  Post-campaign inspection confirmed that both Android targets were restored to
  that exact normal-APK hash.
  After the owning session completed that unrelated interface, a fresh current-
  worktree Android arm64 debug build with the same wake-token test define exited
  0. The accepted device artifact remains bound to the exact APK hashes above.
- **Regression closure added/verified:** proof helpers now reject generic copy,
  validate ordinary sender/body copy, parse notification ids and Orbit 0/1/2
  semantics, scroll a busy notification shade only until both validated title
  and body are visible, normalize initial shade state, reopen Orbit without
  force-stop, and reject cached APK revision/profile/hash mismatches. The final
  focused command passed 58 tests across proof support, the causal reaction
  pipeline, wake-emission default-off policy, and contact-request wake-token
  behavior; focused analysis and scoped `git diff --check` passed. Canonical
  reliability discovery passed and lists the Plan-256 runner, proof, five
  scenarios, and support files. Per the user's instruction,
  `./scripts/run_test_gates.sh` was not rerun in this verification session.
- **Relay rollout:** a Plan-256-only Linux amd64 binary was built from an
  isolated clean worktree, excluding the concurrent Plan-257 group/announcement
  reaction code, and deployed to the single EC2 relay. Live service state is
  `active/running`, version is `relay-server v1.5.1`, and deployed SHA-256 is
  `d91c68f3d2f5e819735ac223a969cc0ee96aa503ed75dc6a07a802c6a3f08356`.
  `DIRECT_REACTION_PUSH_ENABLED=true`; no group-reaction flag is enabled. The
  retained rollback files are
  `/usr/local/bin/relay-server.pre-plan256-20260712T132930Z` and
  `/etc/mknoon/relay-server.env.pre-plan256-20260712T132930Z`. The live campaign
  matched both the relay store and provider send against this exact binary.
- **Release activation caveat:** the client candidates used the explicitly
  test-local `--dart-define=MKNOON_EMIT_WAKE_TOKEN=true`. Plan 217 intentionally
  keeps release-default wake-token emission off until receiver saturation and
  its rollout decision. Therefore the relay capability is deployed and proven,
  but existing/default production clients will not authorize this typed wake
  path until that separate client-side gate is deliberately enabled. This
  verification did not change that safe default.
- **Scope boundary:** this Android core smoke closes the user-requested
  emulator/USB behavior and unread-dot question. It does not claim the stricter
  full TC-13/TC-16 SQLCipher artifact schema, and it does not close TC-14 iOS;
  those remain separate release-closure proofs if the full original plan matrix
  is required. Group and announcement reactions remain Plan 257 and were not
  mixed into this relay deployment.

## Prior Blocked Execution Result (2026-07-12 01:02 CEST)

- **Final verdict:** `blocked`.
- **Invocation topology:** root controller -> fresh isolated Executor ->
  controller `executor_local_takeover` after a bounded Executor stall -> fresh
  independent QA Reviewer -> one fresh replacement QA Reviewer. Roles never
  overlapped. `fix_passes=0`.
- **Independent QA used:** two independent reviewers were attempted. The first
  independently verified fail-closed source/hash attribution in Heartbeat 7
  but did not materialize findings or a verdict; the permitted replacement
  produced no heartbeat or verdict. No completed independent QA verdict is
  claimed.
- **Local sequential fallback used:** no. The caller did not explicitly permit
  degraded non-independent QA, so the controller did not substitute itself.
- **Progress extensions used:** 3 total (Executor grounding, Executor artifact,
  first-QA grounding). Final controller-owned `no_progress_intervals=6`
  (Executor 2, first QA 2, replacement QA 2);
  `materialization_retries=1`.
- **Files changed:** new
  `integration_test/scripts/run_1to1_reaction_notification_device.dart`; 12
  attributable Plan-256 lines in
  `scripts/check_reliability_simulation_discovery.sh`; and this plan's active
  preflight/progress/handoff/result. The pre-existing 8-line Plan-234 discovery
  hunk is preserved exactly. The retained untracked
  `integration_test/one_to_one_reaction_notification_proof_test.dart` was read
  and verified but not changed in this invocation. No production, relay,
  native, model, repository, notification, unread, or app-wiring file changed.
- **Tests added or updated:** none in this invocation. The retained
  `head_provenance` proof from the prior attempt remains fail-closed; the new
  runner lists five scenarios, validates only TC-00 when its external artifact
  exists, and rejects all missing/unimplemented proof paths.
- **Evidence ledger:** working directory for every command is repository root;
  console-only commands have no separate log artifact.

  | Exact command/source | Exit or result | Classification | Log/artifact |
  |---|---|---|---|
  | `git status --short --untracked-files=all` | exit 0; extensive user-owned dirty tree and scoped overlap captured | `passed` | active preflight |
  | `python3 graphify-arch/tdd_context.py query "Plan 256 fresh execution TC-00 ..." --profile general --budget 600` | exit 0; `confidence=anchored`, fingerprint `bf874be415eaf2e3`, stale at unrelated `lib/main.dart` | `passed` | console |
  | initial `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --list-scenarios` | exit 255 because planned runner was absent | `blocking_failure` expected artifact owned by the Executor | console |
  | final same `--list-scenarios` command | exit 0; five exact scenario IDs | `passed` | console |
  | `./scripts/run_test_gates.sh completeness-check` | preflight and final exit 0; `1178/1178` | `passed` | console |
  | `./scripts/run_host_test_gates.sh 1to1 --list` | exit 0; 88-command dry-run inventory | `passed` | console |
  | initial `./scripts/check_reliability_simulation_discovery.sh` | exit 1 solely for the in-scope retained Plan-256 proof | `blocking_failure` expected registration owned by the Executor | console |
  | final `./scripts/check_reliability_simulation_discovery.sh` | exit 0; proof and five runner scenarios classified/expanded | `passed` | console |
  | `dart format --output=none --set-exit-if-changed ...runner... ...proof...` | initial exit 1 for runner; failure persisted/triaged; mechanical format; exact rerun exit 0 | `passed` | console |
  | `dart analyze ...runner... ...proof...` | exit 0; no issues | `passed` | console |
  | `python3 graphify-arch/tdd_context.py affected ...runner... ...proof... ...discovery... --budget 600` | exit 0; no reverse dependencies surfaced | `passed` | console |
  | final scoped `git diff --check -- ...` | exit 0 | `passed` | console |
  | `flutter devices --machine`; `adb devices -l`; `xcrun simctl list devices available`; `flutter emulators` | exit 0; physical Android/iPhones and iOS simulator resolved; AVD available | `passed` | console |
  | `flutter emulators --launch mknoon_play_35` plus focused QEMU/ADB triage | wrapper exit 1, but QEMU remained alive and `emulator-5554` became a live ADB target beside `21071FDF600CSC` | `passed` for required target availability | console |
  | exact TC-00 `dart run ... --scenario head_provenance --sender emulator-5554 --recipient 21071FDF600CSC --artifact-dir build/reaction_notification_proof/head_provenance` | exit 78; no configured Plan-256 staging relay/provider capture driver or `head_provenance.json` | `environment_blocked` | no artifact |
  | TC-07 and every later direct/Go/Swift/Kotlin/family/device command in `Acceptance Gates` and `Device/Relay Proof Profile` | not eligible after the mandatory TC-00 stop condition | `environment_blocked` | none |
  | first QA role; replacement QA role | first produced grounding only; replacement produced no artifact; both stopped after bounded no-progress/settle protocol | `blocking_failure` | no QA review section |

- **QA findings and dispositions:** no completed independent QA findings exist.
  The following are controller-recorded blockers and are not represented as an
  independent verdict:
  - **B1 (blocking):** TC-00 clean-build producer provenance is absent. The
    exact command exits 78 with no matched app/relay/provider artifact.
    Required disposition: provision the Plan-256 staging relay/provider
    capture rig, generate the redacted artifact, and rerun the exact command.
  - **B2 (blocking):** TC-07, TC-01..TC-20 implementation/regressions, every
    later direct and named gate, and device closure remain unresolved by the
    TC-00 stop condition. Required disposition: continue only after B1 passes,
    obeying TC-07 before typed wire enablement.
  - **B3 (blocking):** the runner's four later scenario validators intentionally
    exit 78 and cannot close TC-07/13/14/16. Required disposition: implement
    their named artifact assertions during the permitted post-TC-00 execution
    sequence; never count scenario listing as behavioral proof.
  - **B4 (blocking):** neither fresh QA role produced the required independent
    findings/verdict. Required disposition: the next run must finish with a
    fresh independent review of the stable diff and complete evidence ledger.
- **Blocking issues remaining:** B1-B4.
- **Non-blocking follow-ups deferred:** none. The plan's documented platform/UX
  differences remain scope notes, not waivers for missing closure evidence.
- **Blocker class:** `spawn_or_tool_failure`.
- **Child failure subtype:** `qa_no_result_timeout`.
- **Last two measurable-progress snapshots:** replacement QA snapshot 1 found
  scoped fingerprint `918ef28b...fa9a`, runner SHA-256 `e7e4e2b9...eb36`,
  discovery SHA-256 `09f718d9...48f3`, no Heartbeat 8/review section, and no
  active QA command. Snapshot 2 after the explicit progress request and settle
  poll found the identical fingerprints, plan size/mtime unchanged at that
  boundary, and still no heartbeat, review, command, or verdict.
- **Exact blocker:** the one permitted replacement independent QA remained live
  but produced no verdict and met the bounded stalled threshold after the
  first QA had already timed out. The required independent-review role is
  therefore unavailable in this run, and local sequential QA is not
  authorized. Separately, the mandatory TC-00 provider/relay boundary is
  environment-blocked.
- **Recommended next retry focus:** first provision the clean Plan-256 staging
  relay/provider capture rig and TC-00 artifact path. Rerun the exact TC-00
  command against `emulator-5554` and `21071FDF600CSC`; only on pass continue
  with TC-07 and the plan's production/test sequence, then obtain a fresh
  independent QA verdict.
- **Completion safety:** the retained partial scaffold is fail-closed and
  changes no runtime behavior, so it is safe to keep. It is unsafe to consider
  Plan 256 implemented or accepted: provenance, typed reaction delivery,
  regressions, named gates, device closure, and independent QA are missing.
- **Graph refresh:** skipped. No accepted coherent app-owned code change was
  produced; the one-time incremental refresh is not applicable.

## Prior Execution Progress (2026-07-12 00:14-00:24 CEST)

### Heartbeat 1 — controller preflight (2026-07-12 00:14 CEST)

- **Current bounded milestone:** validate the fresh retry and hand TC-00 runner,
  discovery, and provenance ownership to a fresh Executor.
- **New source evidence:** current source still recognizes no
  `message_reaction` relay push in `go-relay-server/inbox.go:692`, no reaction
  preview in `lib/features/push/application/push_decrypt_preview.dart:36`, and
  no reaction NSE branch in
  `ios/NotificationService/NotificationPreviewResolver.swift:149`; all recorded
  overlapping-file hashes remain unchanged, so the plan remains current.
- **Assigned artifacts:** retained
  `integration_test/one_to_one_reaction_notification_proof_test.dart`
  (3,273 bytes; SHA-256 `1785807c...e6dd7d`); required runner absent;
  Plan-256 discovery entries absent.
- **Scoped work-diff fingerprint:**
  `7ea982d1944b727fb0aae795b97c653edb6ad3030782d349ddc43e0196962a21`,
  excluding this progress-only plan edit.
- **Last completed command:** live device discovery (`flutter devices
  --machine`, `adb devices -l`, `xcrun simctl list devices available`, and
  `flutter emulators`) passed; required Android/iPhone/simulator ids are present
  and `mknoon_play_35` is available but not booted.
- **Current command:** none; no PID/session/log is active.
- **Decision/blocker state:** preflight valid; no blocker yet;
  `fix_passes=0`, `progress_extensions=0`, `no_progress_intervals=0`.
- **Next observable checkpoint:** runner file plus discovery diff materialize and
  `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart
  --list-scenarios` exits 0 with all five exact scenario ids.

### Heartbeat 2 — Executor runner materialization (2026-07-12 00:17 CEST)

- **Sequence/phase:** heartbeat 2; initial Executor pass, bounded TC-00 runner
  materialization milestone.
- **Current bounded milestone:** create the fail-closed Plan-256 runner and add
  only its canonical 1:1 discovery classification/expansion entries before any
  production or broader test work.
- **New source evidence:** the required compact query for the exact filenames
  surfaced `scripts/check_reliability_simulation_discovery.sh:1` and
  `integration_test/scripts/run_notification_tap_device_real.dart`, but no
  existing Plan-256 runner node; current filesystem verification confirms
  `run_1to1_reaction_notification_device.dart` is absent. Decision: this is a
  new bounded runner implementation, followed by targeted verification against
  the closest checked-in device runners and the discovery script; the graph is
  only a broad shortlist and cannot establish registration.
- **Assigned artifacts:** retained
  `integration_test/one_to_one_reaction_notification_proof_test.dart` (3,273
  bytes; SHA-256
  `1785807c49106d9718a48abf82bf525a1fcf2d8fecba5724795ede888be6dd7d`);
  runner absent; discovery script unchanged at 32,223 bytes and SHA-256
  `1abc8cb983c22c0fcecc58c9108fc74acfa9a235cac43d9bdc758d58de91b8c0`.
- **Scoped work-diff fingerprint:** unchanged from preflight at
  `7ea982d1944b727fb0aae795b97c653edb6ad3030782d349ddc43e0196962a21`,
  excluding progress-only plan edits.
- **Last completed command/result:** exact compact Graphify query for
  `one_to_one_reaction_notification_proof_test`,
  `run_notification_tap_device_real`, and discovery registration exited 0 with
  `confidence=broad`; targeted filesystem status/stat/hash commands exited 0
  and confirmed the runner is absent.
- **Current command status:** none; no PID/session/log is active. Last observed
  artifact time is 2026-07-12 00:17 CEST.
- **Decision/blocker state:** no execution blocker established; controller
  observation records `no_progress_intervals=1`. The next checkpoint must
  materialize the named artifact rather than extend on grounding alone.
- **Next observable checkpoint:** runner exists with a direct hash/size,
  discovery has attributable Plan-256 hunks, and
  `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart
  --list-scenarios` exits 0 with exactly the five required ids.

### Heartbeat 3 — controller child-failure classification (2026-07-12 00:19 CEST)

- **Sequence/phase:** heartbeat 3; initial Executor pass terminated before
  materialization, controller structural-validation handoff.
- **Current bounded milestone:** verify the retained TC-00 proof remains
  structurally safe, then obtain an independent QA blocker verdict without
  using a degraded local Executor fallback.
- **New source evidence:** two controller snapshots plus the required settle
  poll found the same absent runner, unchanged retained-proof/discovery hashes,
  unchanged non-progress diff fingerprint, and no demonstrably active command.
  Decision: the Executor met the measurable `stalled` threshold and was
  interrupted; failure subtype is `worker_no_progress_timeout`.
- **Assigned artifacts:** no fresh Executor artifact materialized. The retained
  proof remains 3,273 bytes/SHA-256 `1785807c...e6dd7d`; discovery remains
  32,223 bytes/SHA-256 `1abc8cb9...e91b8c`; the required runner remains absent.
- **Scoped work-diff fingerprint:** unchanged at
  `7ea982d1944b727fb0aae795b97c653edb6ad3030782d349ddc43e0196962a21`,
  excluding progress-only plan edits.
- **Last completed command/result:** short artifact/process settle poll exited 0
  and produced no runner, discovery hunk, or matching PID/session/log.
- **Current command status:** none; the Executor was interrupted and no child
  command remains active.
- **Decision/blocker state:** provisional `spawn_or_tool_failure` /
  `worker_no_progress_timeout`; `fix_passes=0`, `materialization_retries=0`,
  `progress_extensions=1`, `no_progress_intervals=2`. Under the role-relaunch
  rule, another Executor may not be launched without new repository evidence.
- **Next observable checkpoint:** targeted format/analyze/diff checks for the
  retained proof complete, followed by a fresh QA review with stable blocking
  finding IDs and an evidence-based partial-patch safety verdict.

### Heartbeat 4 — controller structural validation (2026-07-12 00:21 CEST)

- **Sequence/phase:** heartbeat 4; post-Executor structural validation and QA
  handoff.
- **Current bounded milestone:** hand the independently verified child failure,
  scoped artifacts, and required-gate failures to a fresh read-only QA role.
- **New source evidence:** the retained TC-00 proof is formatted/analyzable, but
  the exact runner-list command exits 255 because the runner is absent. The
  completeness gate passes `1178/1178`; reliability discovery exits 1 with
  three unclassified files: the in-scope retained Plan-256 proof plus two
  pre-existing private-media proofs. Decision: the Plan-256 registration gap is
  unresolved session scope; the private-media rows are pre-existing,
  unrelated-but-required gate failures and are not an authorized known failure.
- **Assigned artifacts:** no code/test/gate artifact changed in this fresh
  Executor pass; only current preflight/progress text changed in this untracked
  plan.
- **Scoped work-diff fingerprint:** production/test/gate fingerprint remains
  `7ea982d1944b727fb0aae795b97c653edb6ad3030782d349ddc43e0196962a21`;
  retained proof SHA-256 remains `1785807c...e6dd7d`.
- **Last completed commands/results:** `dart format --output=none
  --set-exit-if-changed` proof exit 0; targeted `dart analyze` exit 0;
  scoped `git diff --check` exit 0; exact missing-runner list exit 255;
  completeness exit 0; reliability discovery exit 1. Failure triage used the
  discovery report's exact unclassified list and current scoped status; no fix
  was attempted.
- **Current command status:** none; no PID/session/log is active.
- **Decision/blocker state:** provisional `spawn_or_tool_failure` remains;
  required runner/TC-00/discovery evidence is blocking, and downstream gates
  are not eligible after the mandatory TC-00 boundary. Counters remain
  `fix_passes=0`, `progress_extensions=1`, `no_progress_intervals=2`.
- **Next observable checkpoint:** fresh QA persists stable `B*`/`N*` findings,
  verifies attributable partial-patch safety from files/diffs rather than child
  summary, and returns `blocking` or `clear` without editing production/tests.

### Heartbeat 5 — independent QA audit start (2026-07-12 00:22 CEST)

- **Sequence/phase:** heartbeat 5; fresh independent QA review, initial bounded
  source/diff/evidence audit milestone.
- **Current bounded milestone:** independently verify retained TC-00 proof
  safety, required runner/discovery materialization, mandatory-gate resolution,
  scope attribution, and done-criteria status, then persist stable `B*`/`N*`
  findings immediately before the interrupted-Executor handoff.
- **New source evidence:** the current filesystem independently fingerprints
  `integration_test/one_to_one_reaction_notification_proof_test.dart`
  (`head_provenance`; 3,273 bytes; SHA-256
  `1785807c49106d9718a48abf82bf525a1fcf2d8fecba5724795ede888be6dd7d`),
  confirms `integration_test/scripts/run_1to1_reaction_notification_device.dart`
  is absent, and fingerprints
  `scripts/check_reliability_simulation_discovery.sh` at 32,223 bytes / SHA-256
  `1abc8cb983c22c0fcecc58c9108fc74acfa9a235cac43d9bdc758d58de91b8c0`.
  The scoped status contains only the untracked plan and retained proof; no
  runner or discovery hunk exists. Decision: the QA review must treat runner,
  registration, and TC-00 evidence as unresolved until current source and gate
  evidence prove otherwise.
- **Assigned artifacts:** QA may modify only this progress section and the new
  durable fresh-retry QA review section. Production, test, runner, and gate code
  remain read-only for this role.
- **Scoped work-diff fingerprint:** production/test/gate fingerprint remains
  `7ea982d1944b727fb0aae795b97c653edb6ad3030782d349ddc43e0196962a21`,
  excluding progress-only edits to this plan; retained proof and discovery
  hashes match the controller handoff.
- **Last completed command/result:** timestamp/stat/SHA-256/existence/scoped
  status snapshot exited 0 at 2026-07-12 00:22:25 CEST; runner absence and the
  two untracked scoped artifacts were observed directly.
- **Current command status:** none; no PID/session/log is active. No platform,
  build, or device command is expected during this bounded QA pass.
- **Decision/blocker state:** audit in progress; provisional blocking evidence
  exists for the absent runner and unresolved TC-00 boundary, but stable
  findings await direct source/diff/gate inspection. Controller counters remain
  `fix_passes=0`, `progress_extensions=1`, `no_progress_intervals=2`.
- **Next observable checkpoint:** persist
  `## Independent QA Review — Fresh Retry (2026-07-12)` with stable blocking
  findings, exact evidence references/dispositions/verification commands, and
  a `blocking` or `clear` QA verdict; report its SHA-256/mtime to the controller.

### Heartbeat 6 — controller terminal verdict (2026-07-12 00:24 CEST)

- **Sequence/phase:** heartbeat 6; independent-QA materialization failure and
  terminal controller verdict.
- **Current bounded milestone:** persist the final blocked evidence ledger and
  stop without a prohibited local-role replacement or another role relaunch.
- **New source evidence:** the fresh QA role independently fingerprinted the
  retained proof, absent runner, and unchanged discovery seam, but after its
  single grounding extension and required settle poll it produced no durable
  QA review section and had no active command. Decision: independent QA did not
  complete; the initial Executor failure remains unrecoverable inside this run.
- **Assigned artifacts:** no production, test, runner, gate, native, relay, or
  Graphify artifact changed in the fresh retry. Only this untracked plan's
  preflight/progress/result text changed; the retained proof remains unchanged.
- **Scoped work-diff fingerprint:** production/test/gate fingerprint remains
  `7ea982d1944b727fb0aae795b97c653edb6ad3030782d349ddc43e0196962a21`;
  retained proof SHA-256 remains `1785807c...e6dd7d`.
- **Last completed command/result:** QA settle snapshot found no review section,
  no matching PID/session/log, and unchanged scoped artifacts; the reviewer was
  interrupted.
- **Current command status:** none; all spawned roles are stopped.
- **Decision/blocker state:** final `blocked`, class
  `spawn_or_tool_failure`, child subtype `worker_no_progress_timeout`;
  `fix_passes=0`, `materialization_retries=0`, `progress_extensions=2`,
  final controller-owned `no_progress_intervals=4`.
- **Next observable checkpoint:** none in this run. A new outer retry needs new
  repository evidence at the runner/discovery milestone or explicit caller
  authorization for the skill's degraded local sequential fallback.

## Prior Execution Result (2026-07-12 00:24 CEST)

- **Final verdict:** `blocked`.
- **Invocation topology:** root controller -> fresh isolated Executor -> fresh
  independent QA Reviewer. The roles never overlapped. No fix pass or role
  relaunch occurred.
- **Independent QA used:** a fresh reviewer was spawned, directly verified the
  proof/discovery hashes and absent runner, and persisted a QA-start heartbeat,
  but it did not materialize the required review/verdict before the bounded
  wait, grounding extension, and settle poll ended. No independent QA verdict
  is claimed.
- **Local sequential fallback used:** no. The caller did not explicitly permit
  degraded local replacement of either role.
- **Progress extensions used:** 2 total (one grounding-only extension for the
  Executor and one for QA); final controller-owned
  `no_progress_intervals=4`. `materialization_retries=0`; `fix_passes=0`.
- **Files changed by this fresh retry:** this untracked plan only, for current
  preflight, progress, and result persistence. The retained untracked
  `integration_test/one_to_one_reaction_notification_proof_test.dart` was
  verified but not changed. No production, test, runner, gate, native, relay,
  matrix, or Graphify file changed.
- **Tests added or updated:** none in this fresh retry. The retained
  `head_provenance` proof from the prior attempt remains unchanged and is not
  counted as newly added evidence.
- **Evidence ledger:** working directory for every command is
  `/Users/I560101/Project-Sat/mknoon-2/flutter_app`; console-only commands have
  no separate log artifact.

  | Exact command / source | Exit or result | Classification | Log or artifact |
  |---|---|---|---|
  | `python3 graphify-arch/tdd_context.py query "Plan 256 execution retry TC-00 head_provenance one_to_one_reaction_notification_proof_test run_1to1_reaction_notification_device classify_path expand_record_to_checks ReactionPayload handleIncomingReaction extractChatPushMetadata background_message_handler NotificationPreviewResolver ONE_TO_ONE_TESTS ONE_TO_ONE_HOST_TESTS" --profile general --budget 600` | exit 0; `confidence=anchored`, stale only at `lib/main.dart` | `passed` | console; fingerprint `bf874be415eaf2e3` |
  | `flutter devices --machine`; `adb devices -l`; `xcrun simctl list devices available`; `flutter emulators` | exit 0; required physical Android/iPhones and iOS simulator present; Android AVD available but not booted | `passed` | console |
  | `dart format --output=none --set-exit-if-changed integration_test/one_to_one_reaction_notification_proof_test.dart` | exit 0; 0 files changed | `passed` | console |
  | `dart analyze integration_test/one_to_one_reaction_notification_proof_test.dart` | exit 0; no issues | `passed` | console |
  | `git diff --check -- integration_test/one_to_one_reaction_notification_proof_test.dart Test-Flight-Improv/256-1to1-reaction-notification-context-tdd-plan.md scripts/check_reliability_simulation_discovery.sh` | exit 0 | `passed` | console |
  | `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --list-scenarios` | exit 255; runner file absent | `blocking_failure` | console |
  | `./scripts/run_test_gates.sh completeness-check` | exit 0; `1178/1178` files classified | `passed` | console |
  | `./scripts/check_reliability_simulation_discovery.sh` | exit 1; in-scope Plan-256 proof plus two pre-existing private-media proofs are unclassified | `blocking_failure` | console; full discovery report |
  | `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --scenario head_provenance --sender emulator-5554 --recipient 21071FDF600CSC --artifact-dir build/reaction_notification_proof/head_provenance` | not run because the required runner did not materialize | `blocking_failure` | no TC-00 artifact |
  | `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --scenario android_background_crypto_preflight --recipient 21071FDF600CSC --artifact-dir build/reaction_notification_proof/android_background_crypto_preflight` | not eligible after unresolved TC-00 | `blocking_failure` | none |
  | Every remaining literal command in `Acceptance Gates`, from the first causal reaction-preview RED through the focused Dart/Go/Swift/Kotlin proofs, preservation sentinels, runner/artifact validation, `1to1`, `feature-host-all`, `core-host-all`, analyzer baseline, and final `git diff --check` | not eligible after the mandatory TC-00 stop/go boundary failed; none is claimed as run | `blocking_failure` | exact commands remain verbatim in the governing block |
  | TC-13/14/16 device commands in `Device/Relay Proof Profile` | not eligible; live targets were available, so these are not policy-defined N/A | `blocking_failure` | none |

- **Failure triage:** the missing runner and absent Plan-256 discovery entries are
  unresolved session-scope failures. The two private-media discovery rows are
  pre-existing and unrelated-but-required; the plan authorizes no known-failure
  waiver, so the required discovery gate remains blocking. No failed-gate fix
  was attempted after triage.
- **QA findings and dispositions:** no completed independent QA findings exist,
  so these are controller-recorded blockers and are not represented as a QA
  verdict:
  - **B1 (blocking):** the required runner, five-scenario listing, TC-00 clean-
    build provenance command, and artifact are absent. Evidence: exact runner
    list exits 255 and the path does not exist. Required disposition: materialize
    the fail-closed runner/discovery seam, then verify with the exact list and
    `head_provenance` commands before any production wire edit.
  - **B2 (blocking):** required discovery exits 1; the Plan-256 proof lacks its
    1:1 rule/expansion, while two unrelated pre-existing private-media proofs
    also remain unclassified. Required disposition: add only attributable
    registration changes in their owning scopes and rerun the exact discovery
    gate to exit 0.
  - **B3 (blocking):** TC-07 and all downstream regressions, direct tests, named
    gates, done criteria, and device artifacts are unresolved because TC-00 did
    not complete. Required disposition: resume only after B1, obey the TC-07
    preflight stop condition, then execute the existing plan in order.
  - **B4 (blocking):** the fresh QA role produced no durable review/verdict.
    Required disposition: the next complete run must end with a fresh
    independent QA inspection of the preflight snapshot, scoped diff, evidence
    ledger, and landed tests.
- **Blocking issues remaining:** B1-B4.
- **Non-blocking follow-ups deferred:** none. The plan's accepted platform/UX
  differences do not substitute for missing required evidence.
- **Blocker class:** `spawn_or_tool_failure`.
- **Child failure subtype:** `worker_no_progress_timeout`.
- **Last two measurable-progress snapshots:** (1) 00:17 CEST: runner absent;
  retained proof 3,273 bytes/SHA-256 `1785807c...e6dd7d`; discovery 32,223
  bytes/SHA-256 `1abc8cb9...e91b8c`; scoped fingerprint
  `7ea982d1...a21`; no active command; exact grounding named the runner as the
  next artifact. (2) 00:19 CEST after the grounding extension and settle poll:
  the same artifact and diff fingerprints, no runner/discovery hunk, no active
  command, and no new source decision; the Executor was interrupted as stalled.
- **Exact blocker:** the fresh Executor remained live but failed to materialize
  the first bounded runner milestone, reached the measurable stalled threshold,
  and left no new repository evidence that would permit a same-role relaunch.
  The subsequent fresh QA role also failed to produce its required review. The
  skill forbids substituting local roles without explicit caller permission.
- **Recommended next retry focus:** provide new repository evidence by landing
  the bounded runner/discovery milestone in its owning scope, or explicitly
  authorize the orchestrator's degraded local sequential fallback. Then rerun
  the exact scenario listing and TC-00 provenance before TC-07 or any production
  reaction-wire work.
- **Completion safety:** the fresh retry is safe in that it changed no runtime,
  test, gate, native, relay, or graph artifact and preserved all user-owned
  work. It is unsafe to consider Plan 256 implemented or accepted: TC-00,
  independent QA, every causal regression, every named gate, and every device
  closure criterion remain unresolved.
- **Graph refresh:** skipped. No coherent app-owned code change was accepted, so
  the one-time incremental refresh was not applicable.

## Prior Interrupted Executor Handoff (2026-07-11)

- **Executor state:** blocked before TC-00 completion. The initial Executor and
  its resumed turn established the attribution snapshot and added the
  fail-closed proof validator. A fresh replacement Executor confirmed the
  missing discovery seam, but neither context materialized the required runner
  within the bounded wait/progress/settle protocol.
- **Attributable files changed by this execution:**
  `integration_test/one_to_one_reaction_notification_proof_test.dart` (new,
  91 lines) and this plan's preflight/progress/handoff sections. No production,
  relay, native project, gate script, or existing test hunk was changed by the
  Executor roles.
- **Test added:** `head_provenance`, which fails closed without a configured
  artifact and requires clean-build/app/relay hashes, exact
  `message_reaction` event binding, producer/copy/lifecycle/tap route, unrelated
  card rejection, and provider matched-send or confirmed-no-send evidence.
- **Evidence completed:** dirty-overlap SHA-256 and diff-count attribution;
  anchored Graphify/source verification; live device discovery; current gate
  AUTO-classification verification for `_proof_test.dart`; targeted format and
  `dart analyze` checks; scoped `git diff --check`; and Graphify `affected`
  (no reverse dependencies resolved, requiring direct runner/discovery checks).
- **Evidence not completed:** the runner, five scenario listing, reliability
  discovery expansion, clean-current-build TC-00 command/artifact, TC-07
  preflight, every causal RED/GREEN/mutation, every direct/named/family gate, and
  TC-13/14/16 device closure.
- **Failure classification:** `spawn_or_tool_failure`. Two isolated Executor
  contexts remained responsive enough to persist heartbeats, but failed to
  materialize the bounded runner milestone after two materialization recoveries.
  The caller did not authorize degraded local replacement of the missing role.
- **Patch safety:** the partial file is attributable and contains no production
  behavior. It is not evidence of TC-00 success and cannot make the session
  acceptable. Independent QA must verify syntax/fail-closed behavior and the
  missing required evidence before the final blocker verdict.

## Prior Execution Result (2026-07-11)

- **Final verdict:** `blocked`.
- **Invocation topology:** root controller -> fresh isolated Executor -> one
  resumed turn of that Executor -> fresh replacement Executor for the newly
  materialized TC-00 proof -> fresh independent QA attempt. Executor and QA
  never overlapped. `materialization_retries=2`; `fix_passes=0`.
- **Independent QA used:** no completed independent QA verdict. A fresh QA role
  was spawned after the Executor phase, but it produced no persisted review
  artifact within the bounded wait/progress/settle protocol and was interrupted.
- **Local sequential fallback used:** no. The caller did not explicitly permit
  degraded local replacement of either missing role.
- **Files changed by this execution:**
  `integration_test/one_to_one_reaction_notification_proof_test.dart` (new
  fail-closed TC-00 validator) and this plan (preflight, progress, interrupted
  handoff, and result). No production, relay, native project, gate script,
  existing test, matrix, or generated Graphify file was changed by Plan 256
  execution.
- **Tests added or updated:** added
  `head_provenance` in
  `integration_test/one_to_one_reaction_notification_proof_test.dart`. No other
  TC-00..TC-20 regression was added or updated.
- **Evidence ledger:** all commands use repository root
  `/Users/I560101/Project-Sat/mknoon-2/flutter_app` unless the command contains
  an explicit subshell. Console-only commands have no persisted log path.

  | Exact command / ledger source | Exit or result | Classification | Log or artifact |
  |---|---|---|---|
  | `git status --short` | exit 0; extensive pre-existing dirty tree captured | `passed` | preflight overlap hashes/diff counts in this plan |
  | `python3 graphify-arch/tdd_context.py query "Plan 256 execution ownership: ReactionPayload HandleIncomingReactionUseCase extractChatPushMetadata background_message_handler NotificationPreviewResolver ONE_TO_ONE_TESTS ONE_TO_ONE_HOST_TESTS" --profile general --budget 600` | exit 0; anchored, stale only at unrelated `lib/main.dart` | `passed` | console; fingerprint `bf874be415eaf2e3` |
  | `flutter devices --machine` | exit 0; physical Android/iPhones and iOS simulator resolved | `passed` | console |
  | `adb devices -l` | exit 0; `21071FDF600CSC` resolved | `passed` | console |
  | `xcrun simctl list devices available` | exit 0; `DBE8C32E-9F19-4593-860A-B41113791D79` booted | `passed` | console |
  | `flutter emulators` | exit 0; Android AVD `mknoon_play_35` available but not booted | `passed` | console |
  | `dart format --output=none --set-exit-if-changed integration_test/one_to_one_reaction_notification_proof_test.dart` | exit 0; 0 files changed | `passed` | console |
  | `dart analyze integration_test/one_to_one_reaction_notification_proof_test.dart` | exit 0; no issues | `passed` | console |
  | `python3 graphify-arch/tdd_context.py affected integration_test/one_to_one_reaction_notification_proof_test.dart --budget 600` | exit 0; no reverse dependencies resolved, so direct runner/discovery proof remains required | `passed` | console |
  | `git diff --check -- integration_test/one_to_one_reaction_notification_proof_test.dart Test-Flight-Improv/256-1to1-reaction-notification-context-tdd-plan.md` | exit 0 | `passed` | console |
  | `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --list-scenarios` | not run: required runner did not materialize | `blocking_failure` | none |
  | `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --scenario head_provenance --sender emulator-5554 --recipient 21071FDF600CSC --artifact-dir build/reaction_notification_proof/head_provenance` | not run: required runner did not materialize | `blocking_failure` | no TC-00 artifact |
  | `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --scenario android_background_crypto_preflight --recipient 21071FDF600CSC --artifact-dir build/reaction_notification_proof/android_background_crypto_preflight` | not eligible: TC-00 and runner unresolved | `blocking_failure` | none |
  | Every remaining literal command in the existing `Acceptance Gates` block, from the first causal `flutter test ... --plain-name 'reaction preview uses validated actor and semantic body'` through `git diff --check` | not eligible after the mandatory TC-00 stop/go boundary failed to materialize; none is claimed as run | `blocking_failure` | none; exact commands remain verbatim in the governing block above |
  | `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --scenario android_message_unread_lifecycle --sender emulator-5554 --recipient 21071FDF600CSC --artifact-dir build/reaction_notification_proof/android_message_unread_lifecycle` | not eligible | `blocking_failure` | none |
  | `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --scenario android_physical_recipient --sender emulator-5554 --recipient 21071FDF600CSC --artifact-dir build/reaction_notification_proof/android_physical_recipient` | not eligible | `blocking_failure` | none |
  | `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --scenario ios_physical_recipient --sender 21071FDF600CSC --recipient 00008150-001C3C6A3684401C --artifact-dir build/reaction_notification_proof/ios_physical_recipient` | not eligible | `blocking_failure` | none |

- **QA findings and dispositions:** no independent QA findings materialized, so
  the following stable IDs are controller-recorded blockers and are not
  misrepresented as an independent verdict:
  - **B1 (blocking):** required TC-00 runner, discovery expansion, live command,
    and provenance artifact are absent. Reference: `Implementation Steps` 1,
    TC-00, and `Acceptance Gates`. Required disposition: a fresh outer retry
    must materialize the runner first and verify with
    `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart --list-scenarios`
    before running the exact provenance command.
  - **B2 (blocking):** TC-07 and all downstream regressions/direct/named/device
    gates are unresolved because the mandatory TC-00 boundary never completed.
    Required disposition: do not skip TC-00; after it passes, execute the
    existing plan in order beginning with the real-FCM headless-plugin preflight.
  - **B3 (blocking):** the required fresh QA role did not materialize a review
    artifact. Required disposition: the next full retry must end with a fresh
    independent QA inspection of the plan, preflight snapshot, scoped diff,
    evidence ledger, and landed tests.
- **Blocking issues remaining:** B1, B2, and B3. The new proof validator alone
  cannot drive a device, capture provenance, enable typed reaction delivery, or
  satisfy any product done criterion.
- **Non-blocking follow-ups deferred:** none. The plan's existing accepted UX
  differences remain scope notes, not substitutes for missing required proof.
- **Blocker class:** `spawn_or_tool_failure`.
- **Exact blocker:** two bounded Executor contexts failed to materialize the
  TC-00 runner after two attributable materialization recoveries, and the fresh
  independent QA role then failed to materialize its required review. The
  orchestrator cannot replace those roles locally without explicit caller
  permission.
- **Recommended next retry focus:** start a new full-orchestrator run from the
  retained fail-closed proof file; materialize and register only
  `run_1to1_reaction_notification_device.dart`, resolve TC-00 on a clean current
  build, then proceed to TC-07 and the remaining plan. This is a whole-session
  retry owned by the caller/outer pipeline, not a QA fix pass.
- **Completion safety:** the partial patch is safe to retain as test-only,
  syntactically clean scaffolding and made no runtime change. It is unsafe to
  consider Plan 256 implemented or accepted because no producer provenance,
  headless-plugin proof, typed reaction path, regression suite, named gate, or
  independent QA verdict exists.
- **Graph refresh:** skipped. No coherent app-owned production change was
  accepted, so the required one-time post-acceptance incremental refresh was
  not applicable.

## Historical Execution Result (Pre-Review)

- Final verdict: `ready_for_full_orchestrator`
- Execution mode: `tdd-exec (local)`; preflight and assurance selection only,
  with no delegated tasks and no production/test edits.
- Assurance mode: full orchestrator recommended.
- Independent QA: not performed; implementation never reached a coherent,
  attributable diff eligible for QA-only review.
- Resume state: `not_started`. The plan remains evidence-gated, TC-00 producer
  provenance is unresolved. The independent review requested by this historical
  run is now complete; the revised preflight contract above supersedes that
  recommendation.
- Files changed by this run: this plan only, to persist this result.
- Tests added/updated: none.
- Evidence:
  - `git status --short` -> extensive pre-existing dirty tree recorded, including
    scoped overlap in `push_decrypt_preview.dart`, `main.dart`, both gate scripts,
    and `test-gate-definitions.md`.
  - architecture query for the plan -> `confidence=broad`; exact-anchor refinement
    using `ReactionPayload`, `message_reaction`, notification resolvers, and gate
    arrays -> `confidence=anchored` (graph freshness remained stale, so it was
    used only for navigation).
  - targeted current-source inspection -> Dart, relay, and iOS preview resolvers
    still recognize ordinary `new_message` / `group_message` paths but do not yet
    expose the plan's typed reaction path.
  - required TC-00 harness, consolidated pipeline test, and shared reaction
    fixture -> absent from the current worktree.
  - `git diff --check` -> exit 0; the persisted result adds no whitespace error.
- Required RED/GREEN, Go/Swift, family, analyzer, and device commands: intentionally
  not run. TC-00 must precede production edits, but its harness is absent; running
  downstream gates cannot satisfy the evidence gate or create safe attribution.
- Blocking assurance signals: unresolved producer attribution; encrypted wire
  envelope and authenticated relay-boundary changes; retry/staging/dedupe and
  cross-process notification invariants; Android/iOS device/relay proof; several
  production entry routes; and overlapping dirty-tree ownership in planned files.
- QA findings: N/A. No QA-only pass was started because the implementation and
  required evidence ledger do not exist.
- Follow-up: execute TC-00 and the TC-07 background-plugin preflight through a
  managed implementation/QA run with explicit ownership of overlapping files;
  do not skip directly to production wire changes.
- Safety: unsafe to consider complete under lean execution; managed Executor/QA
  isolation and evidence recovery are closure requirements, not optional polish.
