# 257 - Group And Announcement Reaction Notification Context And Unread Lifecycle

Status: implementation complete — focused, groups, feature, core, and paired
Android device gates are green; the required relay update is deployed and live;
physical-iOS TC-16 remains unexecuted after this Android-only verification; the
repo-wide analyzer baseline remains blocked by unrelated dirty-tree warning/info
reclassification with zero errors
Type: Bug
Spec: free-text intent — group-discussion and announcement reaction
notifications must identify the group, reactor, and reaction without
masquerading as a new message; only the author of the reacted-to message should
be notified; reaction activity must not inflate message-unread state
Classification: implementation-gated (Android device evidence accepted; iOS evidence open)
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-11 22:55 CEST | Evidence Collector | `group_message_listener.dart`, `group_reaction_payload.dart`, send/remove use cases, Plan 127 and exact tests | Plan 127's live group ADD notification is present and GREEN, and the same listener is used for `GroupType.chat` and `GroupType.announcement`. | Trace offline replay, relay push, Android/iOS preview, recipient selection, route identity, and unread state. |
| 2026-07-11 22:58 CEST | Evidence Collector | `inbox.go`, Dart push resolver/handler, Swift NSE, group read repository, Orbit/Main routing | Offline `group_reaction` is pushed as `group_message` to all replay recipients; ADD and REMOVE are not distinguished; reaction plaintext lacks group/actor display context; group mark-read emits no Orbit refresh event. | Define one shared group-family contract rather than duplicate chat/announcement plans. |
| 2026-07-11 22:59 CEST | Planner validation | exact Plan-127 ADD/REMOVE tests, announcement happy path, TC-203-04, live device matrix | All four literal filters selected one test and passed. Physical Pixel, Android AVD, physical iPhones, and an iOS simulator are currently available. | Emit causal host/relay/native rows plus availability-bounded Android and iOS closure. |
| 2026-07-11 23:10 CEST | Planner sufficiency audit | Test Contract, cadence, registration, 1:1 preservation sentinels | The two exact direct ADD/REMOVE filters each selected one test and passed. Every TC row now has an honest HEAD label, mutation target, literal gate/registration route, and real-boundary owner; no migration or destructive-data leg applies. | Mark execution-ready and hand to independent TDD review. |
| 2026-07-11 23:24 CEST | Independent TDD review | listener fixtures, signed replay envelope, group/node/relay fanout, Android headless engine, iOS NSE, dedupe/tone, gates | Pre-revision verdict `plan-fixes-required`: the existing ADD fixture contradicted author-only behavior; the proposed signed hint broke old readers; transition identity, multi-device recipients, foreground drain, and real native boundaries were incomplete. | Apply the bounded deltas below and rerun all five review lenses before execution. |

## TDD Review Result

- Pre-revision verdict: `plan-fixes-required`; the shared group/announcement
  direction was sound, but the planned wire, recipient, and boundary proofs
  could go green with a broken rollout.
- Post-revision verdict: `ready`; classification remains
  `implementation-ready` and the core remote misclassification/all-recipient
  gap is `confirmed`.
- Disposition: `execute`, after Plan 256's shared notification identity, atomic
  lease, and Android background-plugin seams land.
- Five-lens rerun after revision: evidence/classification `clear`; causal tests
  `clear`; bypass/scope `clear`; gate integrity `clear`; boundary/reversibility
  `clear` with iOS passive-defense limitations stated explicitly.
- Blind-spot hits corrected: B-1 optional-extension compatibility/rollback,
  B-2 foreground-drain and headless-engine bypasses, B-3 fixture and relay
  authority overclaims, B-4 lane/runner commands, B-5 transition-id and atomic
  claim races, B-6 durable markers, B-7 background crypto/provider fallback,
  B-8 multi-device/APNs proof, B-9 passive NSE behavior, and B-10 old/new plus
  Android/iOS parity.

## Problem And Evidence

- Behavior to improve: when a member reacts to a message in a group discussion
  or announcement, the author of that message must receive one
  conversation-scoped notification. Its title is the group/announcement name
  and its body is `<reactor> reacted <emoji> to your message`. It must never be
  displayed as `New Message` or sent to uninvolved group members.
- Impact: the current remote path loses the event type and context, may wake
  every group member for a reaction, may wake for REMOVE, and can leave the
  recipient unable to distinguish a reaction from a new group message.
  Separately, a group/announcement message opened from a notification can be
  marked read in SQLCipher without refreshing the Orbit node beneath the route.
- Confirmed landed behavior: Plan 127 added
  `GroupMessageListener._maybeNotifyGroupReaction` at
  `lib/features/groups/application/group_message_listener.dart:4503-4618`.
  The live path uses the group as title, resolves the reactor from the roster,
  includes the emoji, honors mute/viewing/tone gates, and keeps REMOVE silent.
  Exact ADD and REMOVE tests selected and passed during planning.
- Confirmed announcement reuse: `sendGroupReaction` explicitly permits any
  member to react in announcement groups
  (`send_group_reaction_use_case.dart:83-99`), and the listener's notification
  code has no group-type branch. The announcement happy-path reaction test
  selected and passed. There is no announcement-specific notification test,
  so the shared behavior is source-confirmed but not explicitly locked.
- Confirmed remote root cause: `GroupReactionPayload` encrypts only
  event/target/emoji/action/sender/timestamp and carries no group name or
  reactor username (`group_reaction_payload.dart:7-65`). The send/remove paths
  stage `payloadType=group_reaction` for the group inbox
  (`send_group_reaction_use_case.dart:269-332`;
  `remove_group_reaction_use_case.dart:213-276`). The relay then fans out every
  stored group replay and `buildGroupPushMessage` hard-codes
  `type=group_message` (`go-relay-server/inbox.go:407-468,1155-1229`).
  It does not distinguish ADD from REMOVE.
- Confirmed preview failure: Dart and the iOS NSE branch only on
  `new_message` / `group_message` and parse decrypted group plaintext as a
  message (`push_decrypt_preview.dart:26-49,90-165`;
  `NotificationPreviewResolver.swift:149-183,261-335`). Decrypted reaction JSON
  has no `text`, `groupName`, or `senderUsername`, so the resolver yields a
  generic/fake message preview; the production Android background resolver is
  also installed without a group decrypt callback
  (`background_message_handler.dart:38-57,181`). The safe fallback is therefore
  `New Message` / `You have a new message`.
- Confirmed recipient-selection bug: live
  `_maybeNotifyGroupReaction` checks self-reactor, mute, and active view, but
  never verifies that the local user authored `reaction.messageId`. The relay
  uses the full replay-recipient ACL as the push-recipient list. Thus a group
  bystander can receive the same reaction alert as the target author.
- Confirmed fixture defect: the existing Plan-127 ADD test makes the target and
  reactor the same peer and injects no local identity. It cannot remain
  unchanged under a fail-closed author gate. The copy/REMOVE sentinel must be
  corrected so the target is authored by local `peer-self` and the reactor is a
  different member; missing identity gets its own silent sentinel.
- Confirmed transition-identity defect: group ADD ids are deterministic for
  group/target/actor/emoji, while memory and Redis inbox backends reject the
  same message id with different bytes. ADD -> REMOVE -> same-emoji ADD can
  therefore conflict on the second ADD. Notification/replay identity must use a
  unique transition id persisted once with the outbox item; the deterministic
  reaction id remains application-state identity.
- Confirmed signed-wire constraint: the v1 reader reconstructs the exact
  canonical `signedPayload` and rejects byte mismatch
  (`group_offline_replay_envelope.dart:388-415`). Adding hint fields to that
  payload would make a new envelope unreadable by old clients. Notification
  hints must be a separately versioned/signed optional extension while the base
  v1 payload remains byte-for-byte stable.
- Confirmed relay-authority/multi-device constraint: the relay authenticates
  only the sending transport peer and receives a sender-declared recipient set;
  it has no roster or target-message history. An author account may have several
  active transport devices, while push tokens are transport-peer scoped. The
  relay can verify hint signature and subset parity, not independently prove
  target authorship; a conforming sender must nominate every active author
  device and every receiving client must verify local state before display.
- Confirmed Android engine gap: production group background resolution has no
  decrypt callback, and the Go MethodChannel is registered only by
  `MainActivity`, not FlutterFire's headless engine. Exact killed-process emoji
  copy therefore requires the Plan-256 every-engine background crypto plugin
  extended with group decrypt, plus native/real-FCM proof.
- Confirmed foreground bypass: a successful foreground group drain returns
  `drained`, after which `main.dart` does not invoke notification fallback. The
  reaction is persisted but a user outside the group sees no contextual alert.
  The post-drain notification decision must join the shared author/dedupe gate.
- Confirmed route/dedupe mismatch: the outer replay `messageId` is the reaction
  event id, while the live local route anchors the reacted-to message. Remote
  routing currently treats that event id as the group target
  (`notification_route_target.dart:153-180,229-285`), so remote/live dedupe keys
  differ and a tap cannot reliably highlight the reacted-to message.
- Confirmed cross-process caveat: the current tone tracker is explicitly
  foreground/in-memory, Android background group ids are per-message, and iOS
  NSE suppression can only return passive/silent content. The plan must use the
  shared atomic/durable identity/lease from Plan 256 and describe iOS as one
  audible alert/thread, not promise the NSE can delete an already delivered
  card.
- Confirmed unread gap: reactions already live in `ReactionRepository` rather
  than `GroupMessageRepository`, and PGC-016 proves replayed reactions do not
  become messages. Ordinary incoming group messages correctly light the Orbit
  node (TC-203-04 selected and passed). However,
  `GroupMessageRepositoryImpl.markAsRead` only updates SQLCipher
  (`group_message_repository_impl.dart:507-524`); unlike the 1:1 repository it
  emits no read event. Main's notification route pushes
  `GroupConversationWired` directly (`main.dart:4201-4290`), bypassing the
  Orbit-owned push callback that refreshes a group on pop
  (`orbit_wired.dart:2785-2846`).
- Standards rubric:
  - reaction attention is activity about an existing message, not an unread
    message, so it must not alter message counts or message-unread accessibility;
  - notify the target author, not every participant; all members still receive
    the reaction data needed for conversation convergence;
  - retain one stable notification/thread per group and update it rather than
    producing one card per reaction
    ([Android conversations](https://developer.android.com/develop/ui/views/notifications/conversations),
    [Apple thread identifiers](https://developer.apple.com/documentation/usernotifications/unnotificationcontent/threadidentifier));
  - keep group name, username, emoji, and target text encrypted; an OS extension
    or trusted local state may resolve the private preview.
- Existing coverage: Plan-127 group listener cases cover live ADD, REMOVE,
  mute, self, and active-view behavior; ordinary group push preview has Dart,
  Swift, Go, routing, and remote/local dedupe coverage; announcement happy path
  proves member reactions are legal; PGC-016 and TC-203-04 protect reaction vs
  message storage and incoming-message Orbit state. These do not prove a typed
  remote reaction card, author-only wake, announcement notification copy, or
  notification-tap Orbit clearing.
- Missing coverage: no test classifies `group_reaction` at the relay push seam,
  suppresses REMOVE push, separates replay recipients from the sole
  notification recipient, renders reaction copy on Android/iOS, preserves a
  target-message route plus event-id dedupe, or proves chat/announcement unread
  lifecycle on a real phone.
- Refuted findings:
  - `Group reactions are entirely unfixed` is refuted: the live/local group
    ADD path is implemented and its exact test is GREEN.
  - `Announcements need an independent transport fix` is refuted: announcement
    reactions use the same payload, replay, listener, push, route, and group
    message repository as discussion reactions.
  - `Reaction state should light the existing unread orbit` is refuted by the
    repository/widget contract: the orbit count is unread incoming messages.
- Unresolved findings: N/A for the causal mechanism. No deployed group or
  announcement reaction card was captured during planning, but current source
  deterministically constructs the wrong remote classification and recipient
  fanout. Device proof remains required acceptance evidence, not a root-cause
  evidence gate.
- Affected production, test, and gate files:
  `group_reaction_payload.dart`, `send_group_reaction_use_case.dart`,
  `remove_group_reaction_use_case.dart`,
  `group_offline_replay_envelope.dart`, optional signed notification-extension
  codec, outbox/transition identity, `group_message_listener.dart`, foreground
  group drain/remote-message handling,
  `group_message_repository.dart` / implementation,
  `orbit_wired.dart`, `go-mknoon/node/group_inbox.go`, relay memory/Redis
  backends and `inbox.go`, push-token capabilities, `push_decrypt_preview.dart`,
  `background_push_notification_fallback.dart`,
  `background_message_handler.dart`, `notification_route_target.dart`,
  shared deterministic identity/atomic claim/durable tone helpers,
  `remote_notification_identity.dart`, `flutter_notification_service.dart`,
  Plan-256 Android background plugin group method and Kotlin tests,
  `NotificationPreviewResolver.swift`, `NotificationService.swift`,
  `AppDelegate.swift`, `NotificationTapUITests.swift`, focused tests,
  shared fixtures, group/device gate registration, notification matrix, and
  current test map.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `bf874be415eaf2e3`;
  `stale:lib/features/conversation/application/received_media_action_controller.dart`.
- Independent review query: `confidence=anchored` at `GROUP_TESTS`,
  `_maybeNotifyGroupReaction`, and `GroupMessageRepositoryImpl`; the same stale
  unrelated file meant current source remained authoritative. Command:
  `python3 graphify-arch/tdd_context.py query "Counterexample audit Plan 257 GROUP_TESTS _maybeNotifyGroupReaction GroupMessageRepositoryImpl group_reaction signed replay recipient fanout background notification NSE multi-device compatibility" --profile review --budget 800`.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "Group discussions and announcements emoji reaction notifications: incoming ADD reaction sender and emoji copy, background/terminated push support, notification routing, unread semantics, GroupMessageListener announcement group types, relay eligibility, exact tests and GROUP_TESTS registration" --profile tdd --budget 700`.
- Anchors: the compact query anchored `groupMessageListener` only through
  `share_target_picker_wired.dart:69` and surfaced share-target files rather
  than the listener implementation.
- Surfaced proof/gate files: `share_target_picker_wired_test.dart` and its
  GROUP_TESTS / AUTO feature-host registrations; these were not load-bearing
  for the notification conclusion.
- Graph gaps requiring source search: group reaction listener, offline replay,
  relay group push, Android/iOS preview, author selection, route identity, and
  group read/Orbit seams were absent from compact output and were verified in
  current source.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Use one shared implementation for `GroupType.chat` and
  `GroupType.announcement`. Each surface receives explicit tests and device
  scenarios, but production logic must not be duplicated by group type.
- Notify only the author of the reacted-to message. The reactor, uninvolved
  members, removed/non-current members, unknown authors, and a user already
  viewing the group are not push candidates or audible/banner recipients.
  Valid reaction state still converges to every eligible member. A missing
  local identity fails closed; an already-delivered iOS item may only be made
  passive as documented below.
- Preserve offline reaction convergence for every eligible replay recipient.
  Resolve the complete active transport-device replay set before signing and
  pass that exact set to the Go store call. Introduce a separately signed,
  optional versioned notification extension; keep the base v1 signed payload
  byte-for-byte stable and never narrow replay custody to the author.
- Keep group/announcement name and reactor display name recipient-owned: Android
  reads SQLCipher group/roster state; iOS mirrors group display/type, current
  member display names, local account/device ids, mute, and a bounded set of
  locally authored target ids into shared Keychain/App Group state. Emoji stays
  encrypted and is used only after parity. Cover create/rename, member display
  update/removal, mute/unmute, target create/delete/retention expiry, dissolve,
  failed projection writes, and launch backfill/restart cleanup.
- Separate deterministic reaction-state id from a unique transition/replay event
  id allocated once and persisted with the outbox item. ADD -> REMOVE -> same-
  emoji ADD gets three event ids; an exact retry reuses its event id. Relay
  custody, push dedupe, claims, and route metadata use the transition id; local
  reaction upsert/removal uses state identity.
- Preserve base-v1/plaintext binding: top-level base `messageId` and encrypted
  inner `id` remain the deterministic state/tombstone id expected by old
  readers. Add encrypted optional `eventId` and cross-check it with the signed
  extension's transition id on new readers. The upgraded relay backend prefers
  that extension id only for group-reaction custody/dedupe; legacy envelopes
  fall back to base `messageId`. Do not put transition id into base
  `messageId`, which would trigger `payload_message_mismatch` on old readers.
- The optional signed notification extension contains transition id, exact
  ADD/REMOVE hint, target id, reactor account/transport identity, the complete
  replay transport set hash, and `notificationRecipientTransportPeerIds` for
  every active device of the target-author account. It is bound to the unchanged
  base-envelope hash/signature. Old readers ignore it; new readers verify it.
- Emit typed `group_reaction` ADD push only to capable target-author transport
  devices that are a subset of the exact replay device set, behind default-off
  `group_reaction_v1`. Store REMOVE/malformed/legacy reactions silently. The
  relay guarantee is authenticated sender + signed self-consistency + subset;
  it does not independently prove target authorship. Recipient local state is
  the display authority. When reactor account equals target-author account, the
  extension nominates no devices, so a sibling device never receives an own-
  reaction alert.
- Render title `<group or announcement name>` and body
  `<reactor> reacted <emoji> to your message`. A recognized reaction decrypt
  failure may use trusted local actor/group state and omit the emoji; otherwise
  it uses reaction-specific safe copy. APNs carries a fixed silent
  `New reaction` / `Someone reacted to your message` timeout/oversize fallback,
  never `New Message`; no private display fields cross the provider boundary.
- Route a reaction card to `group:<id>|message:<targetMessageId>` while using
  the separate reaction event id for dedupe, event claims, and exact replay.
- Preserve stable per-group Android notification identity/category and iOS
  thread identifier. Reuse Plan 256's deterministic id, atomic event claim, and
  durable tone lease: Android replaces one group card; iOS guarantees one
  audible alert/thread while a passive same-thread duplicate may remain.
- After a successful foreground `group_reaction` drain, run the same
  author/mute/active-view/atomic-claim decision before returning `drained`; do
  not rely on the ordinary fallback-only branch.
- Keep group/announcement reaction activity out of unread-message accounting.
  Add a group conversation-read event so a successful notification-open route
  clears the ordinary-message Orbit node after `markAsRead` changes rows.
  Delivery or dismissal alone must not clear it.
- Add host, Go, Swift, group-lane, device-artifact, discovery, matrix, and
  current-test-map coverage.

Must preserve:

- Live ADD copy/route/emoji, REMOVE silence, mute, own-reaction, and active-view
  suppression -> corrected Plan-127 fixtures with locally authored target plus
  explicit missing-identity fail-closed coverage.
- Reaction data converges to all eligible group devices even though only active
  devices of the target-author account are push candidates ->
  `group_reaction_roundtrip_test.dart` and the storage-vs-wake discriminator.
- Ordinary group/announcement messages keep sender-prefixed preview, relay
  fanout, mute/membership eligibility, route/tap, and remote/local dedupe ->
  TC-10.
- Removed/dissolved/unknown-member and target-deleted reaction rules remain
  unchanged -> `handle_incoming_group_reaction_use_case_test.dart`.
- 1:1 reaction behavior stays owned by Plan 256 ->
  `handle_incoming_reaction_use_case_test.dart::only target author is notified
  while both target directions persist` and `::incoming REMOVE reaction does
  NOT notify`; no direct
  transport edits in Plan 257.

Hard `Do not`:

- Do not send reaction notifications to every replay recipient. Do not reduce
  replay storage/ACL recipients to the target author.
- Do not put group/announcement name, reactor username, emoji, original message
  text, media metadata, or generated/private preview copy in clear relay/FCM/
  APNs fields. Only the fixed non-private typed reaction fallback is allowed in
  provider alert copy.
- Do not trust outer action, author, target, or actor hints as content
  authority. They may select a wake; decrypted/local parity decides storage and
  display.
- Do not notify for REMOVE, stale/exact duplicate ADD, self-reaction,
  bystander, missing/deleted target, unknown/removed member, dissolved group,
  muted group, or active group.
- Do not claim that a reactor signature proves target authorship. Do not compare
  account ids directly to transport-device recipient ids or select only one of
  an author's active devices.
- Do not suppress self-notification by excluding only the sending transport;
  exclude every device of the reactor account when it is also the target-author
  account.
- Do not modify the base v1 canonical signed payload, allocate a new transition
  id on retry, or use deterministic reaction-state id as relay custody identity.
- Do not enable typed group reaction wake for an incapable device or before the
  default-off relay rollout flag is enabled.
- Do not create a synthetic `GroupMessage`, increment group unread count, or
  relabel reaction activity as an unread message.
- Do not clear message unread state on notification display or dismissal; only
  a successful real conversation-open read commit may clear it.
- Do not add a DB migration, notification channel, permission prompt, reply
  action, or parallel announcement-only notification pipeline.
- Do not use `am force-stop` in push proof; use `am kill` plus an empty
  `pidof` assertion.

Deferred / accepted difference:

- Original target-message text remains absent from reaction notifications.
  Actor + emoji + group name + correct target route is the accepted
  privacy-preserving context.
- Full Android MessagingStyle/shortcuts and iOS Communication Notifications
  remain an app-wide presentation follow-up.
- A separate unseen-reaction badge/activity inbox remains a future product
  plan; it must not reuse message-unread Orbit semantics.
- iOS NSE cannot delete an alert already delivered. Mute, non-author, malformed,
  late-stale, and duplicate defense yields no sound/banner and may leave a
  passive Notification Center item; the relay's zero-send recipient policy is
  the primary boundary.

Dependencies:

- Plan 256 and Plan 257 form the reaction-notification dependency wave because
  both touch shared route, preview, native, identity, and card metadata seams.
  Preferred landing order is Plan 256 first, then rebase Plan 257 onto any
  shared typed-reaction helpers. Plan 257 must keep group payload/recipient
  semantics independent and must not copy direct-only logic. Plan 257 requires
  Plan 256's deterministic identity, atomic/durable claim/tone store, and
  every-engine Android background plugin; it extends the plugin with group
  decrypt parity rather than adding a second channel.
- Mixed-version rollout is relay-first: deploy silent classification and
  optional-extension parsing with typed push disabled; ship clients that read
  both forms and register `group_reaction_v1`; enable typed wake only after
  capability coverage. Rollback disables typed push while all envelopes remain
  stored/readable. An old relay is not a valid closure target for client hint
  enablement because it still misclassifies/fans out reactions.
- Device closure needs a staging relay running the candidate group-push build,
  valid FCM/APNs tokens, and the available targets below. No deployment is
  authorized by this plan.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-00 | The landed live discussion ADD copy/route/emoji and REMOVE silence survive after correcting the invalid fixture: target author=`peer-self`, reactor=`peer-sender`, and local identity is explicit. | Revised existing `group_message_listener_test.dart::127-Bug-D: incoming ADD group reaction notifies (route + emoji)` and exact REMOVE case | Host application GREEN sentinel / in-memory group, message, reaction, notification repos | Existing copy test is GREEN but target/reactor are the same peer; corrected fixture must remain GREEN through author filtering. | Keep the old self-authored fixture, replace copy with generic text, drop target route, or notify REMOVE -> TC-00 red. | Literal exact commands; file already in GROUP_TESTS/AUTO. Fixture correction is required, not optional cleanup. |
| TC-01 | A live group reaction notifies only when explicit local identity authored the target; bystander/reactor/missing-identity instances stay silent while every eligible member persists the reaction. | `group_message_listener_test.dart::group reaction notifies target author but not reactor or bystander`; `::missing local identity fails closed for reaction notification` | Host application / three identities over shared fake event | HEAD notifies any non-reactor and has no self-id seam -> only target author has one contextual notification; all three retain state. | Remove author comparison, fail open on missing identity, or narrow persistence to author -> TC-01 red. | Existing GROUP_TESTS + AUTO; exact commands below. |
| TC-02 | Announcement member reaction uses the shared author-only policy: the admin/announcement author sees announcement title + reactor + emoji; another reader stays silent. | `test/features/groups/application/group_message_listener_test.dart::announcement reaction notifies only announcement author with group context` | Host application causal RED plus landed-copy sentinel / `GroupType.announcement` fixture | HEAD reuses the landed copy but lacks author filtering, so the reader notification assertion is RED -> author gets one, reader gets zero, both retain the reaction. | Branch announcements to generic copy, block legal member reactions, or notify every reader -> TC-02 red. | `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name 'announcement reaction notifies only announcement author with group context'`; existing GROUP_TESTS + AUTO feature-host. |
| TC-03 | Base v1 signed replay bytes and base `messageId == inner.id` binding remain unchanged; encrypted optional `eventId` matches a separately signed notification extension carrying transition/action/target/device hints. | envelope compatibility tests; send/remove notification-extension tests; frozen old reader | Host domain/application / real envelope JSON and fake signing | HEAD lacks extension; changing base messageId/payload breaks old reader -> new reader verifies event parity, old reader accepts/ignores optional fields, legacy input remains readable, forbidden fields absent. | Put transition id in base messageId, insert hint into v1 `signedPayload`, fail to bind extension, leak display data, or reject legacy -> TC-03 red. | Exact files AUTO feature-host; explicitly register load-bearing payload/send/remove tests in GROUP_TESTS. |
| TC-04 | Relay stores one transition for the full signed replay-device set and sends ciphertext-only `group_reaction` push to every capable active transport device of the nominated target-author account—two in the fixture—and no bystander/REMOVE/legacy/self-account device. | `TestGroupInboxStore_ReactionAddPushesAllAuthorDevicesOnly`; `TestGroupInboxHandler_ReactionHintBindsAuthenticatedSenderAndExactRecipientSet`; node signed-set parity test | Go relay/node / two author devices + bystander + sibling-device self-reaction, recording backend/tokens, framed handler | HEAD pushes `group_message` to all; GREEN stores full ACL, pushes both other-author devices only, nominates none when reactor account is author, verifies sender/set/capability/flag, and does not claim relay-proven authorship. | Use account id as token id, choose one author device, exclude only sender transport, derive recipients after signing, trust conflicting set, or push REMOVE -> TC-04 red. | Pinned-toolchain Go tests in relay and go-mknoon; outside Flutter globs. |
| TC-05 | Android group reaction resolution uses SQLCipher group/roster/target-author state and Plan-256's every-engine plugin group-decrypt method; exact emoji copy is allowed only after parity, otherwise trusted local semantic copy. | Dart resolver/handler tests; Kotlin group-decrypt registration/parity test; real-FCM group preflight | Host push + native + device preflight | HEAD has no production group callback/headless channel -> group/actor/emoji on validated success; no-emoji fallback on crypto failure; missing/muted/non-author suppressed. | Use Activity-only channel, sender display fields, fake-only callback, or message fallback -> TC-05 red. | Dart AUTO; exact Gradle task; TC-15 closes real boundary. |
| TC-06 | iOS NSE reads projected group/roster/local-device/mute/authored-target state, validates extension/decrypted parity before atomic claim, uses fixed silent typed provider fallback, and treats rejection as passive/no-sound defense. | Swift resolver projection/fallback/invalid-first tests plus Dart create/rename/member-remove/mute/target-delete/dissolve/failure/backfill lifecycle tests | Swift XCTest + host integration / shared fixture, fake Keychain, real claim filesystem | HEAD parses as group message -> valid exact group/actor/emoji/thread; timeout/oversize never says New Message; invalid first copy cannot poison valid second; stale/absent/muted/non-author may leave passive item only; projection self-heals/prunes. | Claim before validation, use sender names, omit any deletion/backfill callsite, return generic fallback, or promise NSE deletion -> TC-06 red. | Direct xcodebuild + exact Dart projection tests; physical TC-16. |
| TC-07 | Route target, encrypted/signed transition event id, and base deterministic reaction-state id remain distinct across Dart/Go/Swift: target navigates, relay prefers transition for custody/dedupe, base state id preserves old-reader binding/local upsert. | route/identity tests plus shared fixture and ADD-REMOVE-ADD roundtrip | Host core/Go/Swift parity | HEAD conflates ids -> all three remain stable; new relay prefers extension event; legacy relay/reader sees base id; cross-language keys agree. | Put transition in base messageId, key dedupe by target/state on new relay, use transition as route target, or regenerate on retry -> TC-07 red. | Core AUTO; Go/Swift direct fixture. |
| TC-08 | Concurrent remote/live/drained copies have one atomic announcement winner and durable tone lease; a successful foreground drain outside the group posts the contextual author notification, while active view remains silent. | barrier-controlled group pipeline tests for remote/live and foreground drain | Host integration / real listener + drain/foreground dispatcher, atomic store, fake clock/plugin | HEAD foreground drain is silent and current claims are non-durable -> one announcement in every order, distinct event silent inside lease, state once, active-view zero. | Return `drained` before notify decision, use fallback-only path, claim before validation, or allocate per-event card -> TC-08 red. | Pipeline pinned in GROUP_TESTS + AUTO. |
| TC-09 | Existing mute, active-view, self, removed/non-current member, dissolved group, missing/deleted target, stale, and duplicate suppression remain effective for chat and announcement reactions. | `group_message_listener_test.dart::127-Bug-D: incoming ADD group reaction notifies (route + emoji)`; `::incoming REMOVE group reaction does NOT notify`; `::ADD reaction in a MUTED group does NOT notify`; `::own reaction (mesh echo) does NOT self-notify`; `::reaction is suppressed while viewing the group conversation`; `handle_incoming_group_reaction_use_case_test.dart::rejects reaction from unknown sender without storing ghost reaction`; `::ignores add reactions at or after the dissolve cutoff`; `::GMA-07R locally deleted exact group parent cannot refill reaction buffers`; `resolve_group_notification_route_target_use_case_test.dart::RED: suppresses FCM display for a current member of a MUTED group` | Host GREEN sentinels / existing fakes and repository fixtures | GREEN on HEAD -> remain GREEN after new remote producer and author gate. | Bypass local eligibility, notify a non-upsert, or allow removed/dissolved target -> TC-09 red. | The literal `--plain-name '127-Bug-D'` and focused file commands below plus `./scripts/run_test_gates.sh groups`; AUTO feature-host. |
| TC-10 | Ordinary group/announcement message preview/fanout/routing/mute/dedupe, all-member reaction convergence, and 1:1 ADD/REMOVE behavior remain unchanged. | Existing ordinary preview/Go/Swift/dedupe tests; group roundtrip; announcement happy path; direct reaction sentinels | Host/Go/Swift GREEN sentinels | GREEN on HEAD -> unchanged after typed group reaction support. | Route ordinary/direct events through group-reaction filter, narrow replay ACL, or alter ordinary ids/thread -> TC-10 red. | Payload/send/remove/roundtrip are newly pinned in GROUP_TESTS; announcement happy path remains exact + AUTO/optional inventory; direct/shared files run exactly as listed. |
| TC-11 | Reaction receipt/display/dismissal never creates a group message or changes unread count/satellites/`unread message` semantics for either chat or announcement. | `test/features/groups/integration/group_reaction_notification_pipeline_test.dart::chat and announcement reactions leave message unread state unchanged`; existing `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::PGC-016 group_reaction without reactionRepo does not persist a message` | Host integration GREEN sentinel / in-memory message/reaction repositories and mounted Orbit | HEAD storage separation is GREEN -> zero stays zero; existing genuine unread count stays exact through reaction receipt/display/dismissal. | Insert a synthetic group message, derive unread from activity, or clear real unreads on display/dismiss -> TC-11 red. | Pipeline file GROUP_TESTS + AUTO feature-host; drain file already GROUP_TESTS. |
| TC-12 | `markAsRead` emits a group id only when incoming rows change, and Orbit refreshes the matching chat/announcement node when a notification-routed `GroupConversationWired` commits the read. | `test/features/groups/domain/repositories/group_message_repository_impl_test.dart::markAsRead emits group read event only when rows changed`; `test/features/orbit/presentation/screens/orbit_group_unread_notification_wired_test.dart::notification-routed read clears chat and announcement nodes` | Host repository/widget / real repository delegates plus in-memory event source, real Orbit and routed group conversation | HEAD has no group read-event source and a main-owned route can leave the node stale -> changed rows emit once and clear only the matching node; zero-row re-mark emits nothing. | Remove repository emission, Orbit subscription, real conversation mark-read, or replace it with a harness-only refresh -> TC-12 red. | Repository file already GROUP_TESTS/AUTO; new Orbit file added to GROUP_TESTS and AUTO feature-host. |
| TC-13 | On Android with B already on Orbit, ordinary discussion messages drive `0 -> 1 -> 1 after card dismissal -> 2 -> 0 after notification tap/read`, and returning to Orbit is unlit. | `integration_test/group_announcement_reaction_notification_proof_test.dart::android_group_message_unread_lifecycle` via device runner | Paired-device manual/device-only preservation proof / emulator sender + physical Android recipient, real relay/FCM/SQLCipher/UIAutomator | Arrival and DB read are expected GREEN on HEAD, but notification-routed Orbit clearing has no existing composed proof -> full lifecycle must pass; host TC-12 owns the causal RED. | Clear on dismiss, skip real route/read, or hide the widget without changing SQLCipher -> TC-13 red. | Device-proof AUTO classification plus literal `--scenario android_group_message_unread_lifecycle` command below; registered under group discovery. |
| TC-14 | The same ordinary-message unread lifecycle holds for `GroupType.announcement` with admin sender and member recipient. | `integration_test/group_announcement_reaction_notification_proof_test.dart::android_announcement_message_unread_lifecycle` via device runner | Paired-device manual/device-only preservation proof / emulator admin sender + physical Android member recipient | Shared arrival/read behavior is expected GREEN on HEAD, but there is no announcement composed proof -> the same count/satellite/dismiss/tap/read sequence must pass; TC-12 guards the shared causal seam. | Special-case announcement out of read events or clear on card display -> TC-14 red. | Device-proof AUTO classification plus literal `--scenario android_announcement_message_unread_lifecycle` command below; no iOS needed because this app-state behavior is shared. |
| TC-15 | With Android target author killed but not force-stopped, discussion and announcement reactions use the real headless group-decrypt plugin, replace the same group card across distinct transitions, tap the target, and create no message unread state. | two Android proof scenarios plus artifact validator | Paired-device / emulator reactor + physical target author, real relay/FCM/SQLCipher/plugin/group crypto | HEAD can show generic group_message and lacks headless decrypt -> exact trusted group/actor/emoji copy, route/event/state ids, zero REMOVE/duplicate/unread; TC-04 owns multi-device/bystander fanout. | Activity-only plugin, generic fallback, wrong id, per-event card, or synthetic unread -> TC-15 red. | Fully automated runner invokes proof and validator; no user taps. |
| TC-16 | Physical iOS NSE renders a valid announcement reaction from projected local context plus decrypted emoji, preserves group thread/target/transition identity, never exposes `New Message`, and yields one audible alert with no unread mutation. | iOS announcement proof plus exact `NotificationTapUITests` method/artifact validator | iOS-specific / Android reactor + physical iPhone author, real relay/APNs/NSE/group crypto | HEAD parses as group_message -> exact copy/thread/route, typed silent timeout fallback, zero forbidden fields/unread. A passive same-thread duplicate is recorded, not misreported as a second alert. | Use provider New Message, sender-authored display, claim before eligibility, or count passive defense as full suppression -> TC-16 red. | Device AUTO + manual scenario + physical xcodebuild selector. |
| TC-17 | ADD -> REMOVE -> same-emoji ADD keeps base state/tombstone ids compatible but uses three extension transition ids through upgraded memory/Redis custody; exact retry reuses envelope/id and is idempotent. | group send/remove outbox test; relay memory/Redis extraction/conflict test | Host Dart + Go backends / unchanged base binding, persisted outbox transition | HEAD dedupes by base ADD id and conflicts -> upgraded relay prefers extension event for three stores; final state ADD; retry duplicate-not-conflict; frozen old reader still accepts each envelope. | Change base binding, use state id in upgraded backend, allocate retry id, or skip Redis/old-reader leg -> TC-17 red. | Exact Dart plus pinned Go memory/Redis tests. |
| TC-18 | Mixed-version/rollback contract: old reader accepts new base+optional extension, new reader accepts legacy; old relay mode stores reaction silently; incapable devices get no typed push; flag-off rollback preserves custody. | frozen reader tests; `TestGroupReactionCapabilityRolloutAndRollback` | Host Dart/Go / old/new fixtures and default-off flag | GREEN proves relay-first ordering and byte-compatible base v1. | Change base signature, enable client hints against old relay, push legacy device, or drop storage on rollback -> TC-18 red. | Exact Dart and pinned Go command; wave rollout evidence. |
| TC-19 | A two-device target-author account maps to both active transport peers, while bystander and all same-account self-reaction devices get no push; a false author hint is rejected locally. If reaction reaches an author sibling before its target sync, it remains unclaimed/buffered and notifies once only after the target materializes. | node/relay multi-device test plus recipient local-eligibility/target-order pipeline test | Host Go + Dart/Swift / account != transport ids, reaction-before-target barrier | GREEN sends both other-author device tokens, zero for sibling self-reaction, documents relay trust boundary, rejects false hint, and preserves reaction-before-target for one later eligible display. | Compare account to transport id, select origin only, exclude only sender device, claim before target validation, clear missing-target entry, or claim sender signature proves authorship -> TC-19 red. | Direct Go plus pipeline/Swift exact tests. |
| TC-20 | Foreground remote group/announcement reaction drain outside the target conversation notifies the local author exactly once; active-view, bystander, malformed, and live-race copies stay silent. | `group_reaction_notification_pipeline_test.dart::foreground drained reaction still runs contextual notification gate` | Host integration / real foreground handler + drain + listener | HEAD returns `drained` before display -> author gets zero. GREEN joins shared atomic gate after successful persistence. | Notify before persistence, call ordinary fallback, or return early after drain -> TC-20 red. | Pipeline in GROUP_TESTS/AUTO; exact command below. |

### Test Notes

- TC-01/04 use two discriminators: every eligible member persists the reaction,
  while only active devices of the target-author account have candidate
  notification sends. A test that narrows storage recipients is invalid.
- The optional notification extension is signed by the reactor and bound to the
  unchanged base envelope. The relay verifies authenticated sender, signature,
  exact replay-set parity, capability, and candidate subset only. It cannot
  prove target authorship; Android/iOS local target-author state is mandatory
  defense, and TC-19 demonstrates the malicious-hint limit explicitly.
- TC-07 keeps target-message id, unique transition event id, and deterministic
  reaction-state id distinct. Equal targets/state ids with distinct transition
  ids are distinct events; exact retries reuse the same transition id/bytes.
- TC-08 uses barrier-controlled simultaneous calls and runs the real foreground
  `drained` branch. Sequential remote-first/live-first calls alone are
  insufficient for an atomicity claim.
- TC-11/12 separate reaction activity, OS-card lifecycle, and message read
  state. A reaction tap may clear pre-existing genuine group-message unreads
  only because the real conversation was opened and `markAsRead` completed.
- TC-13/14 dismiss the first card, verify unread state remains, then send a
  second message and tap its replacement card. This proves dismissal is not a
  read receipt.
- TC-15/16 require the runner to invoke the named proof and a separate artifact
  validator. App/SQLCipher/relay/provider/XCUITest artifacts are authoritative;
  runner-authored success booleans are rejected.

## Implementation Steps

1. Snapshot `git status --short` and preserve unrelated work. Correct the
   TC-00 fixture, add TC-01..12 and TC-17..20 plus shared fixtures before
   production edits, and record causal Dart/Go/Swift/Kotlin REDs and existing
   preservation GREENs.
2. Reuse Plan 256's every-engine Android plugin and prove group-decrypt parity
   in a real FCM headless callback before enabling typed group push. Stop-if the
   plugin is Activity-only or alters the main Go event callback.
3. Introduce a unique outbox-persisted transition id while retaining base
   `messageId == inner.id` state/tombstone binding. Add optional encrypted
   `eventId`; reuse the existing outbox key column for new transition ids so no
   schema migration is needed, while legacy queued rows remain readable. Make
   upgraded relay dedupe prefer the signed extension event id and prove
   ADD-REMOVE-same ADD/exact retry through memory and Redis plus frozen old reader.
4. Keep the base v1 signed replay payload byte-identical. Add a versioned,
   separately signed notification extension bound to the base envelope. Resolve
   the complete active replay transport set before signing and pass the same set
   to Go; close both old/new reader directions.
5. Change live `_maybeNotifyGroupReaction` to require that the local identity
   authored the target message. Keep reaction application/stream emission for
   every eligible member, fail closed on missing identity, and preserve the
   existing suppression gates.
6. Split group replay storage candidates from push candidates at relay. Store
   the full exact transport set; after sender/signature/set/capability/flag
   checks, push typed ADD to every nominated active author device. Store
   REMOVE/malformed/legacy silently. Do not claim relay-proven authorship.
7. Add typed reaction preview/fallback/route/identity handling in Dart and the
   iOS NSE. Reuse Plan-256 shared helpers where landed, but retain group-specific
   symmetric key and recipient-owned group/roster/mute/authored-target
   projections. Add fixed silent provider fallback and validate before claim.
8. Join successful foreground drains to the same author/active/atomic-claim
   notification decision. Use transition id for claims/custody, target id for
   navigation, state id for reaction upsert, stable group id for Android card,
   and shared durable tone lease for sound.
9. Add `GroupConversationReadEventSource` (or equivalent narrow typed
   contract) to the production/in-memory group message repositories. Emit only
   when unread rows change; subscribe in Orbit and refresh the exact group.
10. Add payload/send/remove/roundtrip, consolidated pipeline, and new Orbit
   files to GROUP_TESTS. Register runner/proof/validator paths in both
   `classify_path` and `expand_record_to_checks`, and all five scenarios in
   `check_reliability_simulation_discovery.sh`. Update
   `test-gate-definitions.md`, `52-notification-journey-test-matrix.md`, and
   `_current-test-map.md`.
11. Run focused GREEN, representative mutation re-red, exact preservation,
   groups, feature/core family sweeps, Go/Swift direct gates, then TC-13..16 on
   a staging relay running the candidate build.

## Risks And Blind Spots

- Replay convergence could be accidentally narrowed with push fanout -> TC-01,
  TC-04, and TC-10 require all-member persistence plus author-only notification.
- A malicious member can sign a self-consistent false author hint because the
  relay lacks target history -> TC-03/04 do not overclaim relay authority;
  TC-19 requires recipient local rejection/passive defense. A target-author-
  issued capability would be a separate stronger protocol.
- Remote/live copies can double-alert because route target and event identity
  differ -> TC-07/08 separate the two identifiers and prove both arrival orders.
- Deterministic state id can conflict after remove/re-add -> TC-17 separates the
  transition id and proves both relay backends plus exact retry.
- Mixed clients/relays can reject or misfanout -> TC-03/18 preserve base v1,
  require relay-first default-off rollout, and make flag-off rollback store
  silently.
- Account/device identity mismatch can lose sibling-device alerts -> TC-04/19
  use two active author transports plus a bystander and exact signed/store set
  parity.
- Android background crypto/local DB access may be unavailable -> TC-05 permits
  a trusted actor/no-emoji semantic fallback, never generic message copy;
  TC-15 closes the real SQLCipher/native boundary.
- iOS simulator injection does not prove NSE execution -> Swift host proof plus
  physical APNs TC-16.
- Lifecycle / derived-state durability: TC-11 reconstructs unread state from
  message rows; TC-12 emits/replays read refresh; TC-13/14 prove dismissal,
  route, read, and return on a real phone.
- Sibling-surface consistency: explicit chat and announcement host/device rows
  share production logic; ordinary group messages and 1:1 reactions are
  preservation boundaries.
- Destructive-action side effects: N/A — no user data is deleted; REMOVE stays
  a reaction tombstone/replay event and is merely notification-silent.
- Invariant re-verification under new transitions: TC-03/04/09 re-check legacy,
  mismatch, removed/dissolved, mute, duplicate, and REMOVE behavior; TC-17/18
  add remove-readd, retry, downgrade, and rollback transitions.

## Gate Cadence

- Per-plan closure: focused Dart/Go/Swift/Kotlin tests, exact preservation sentinels,
  `./scripts/run_test_gates.sh groups`,
  `./scripts/run_host_test_gates.sh feature-host-all`, and
  `./scripts/run_host_test_gates.sh core-host-all`. Both family sweeps are
  justified because production changes span `lib/features/**` and
  `lib/core/notifications/**`.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the Plan-256 + Plan-257
  reaction-notification dependency wave, and once at final rollout/release
  closure.
- Shared tests outside feature/core globs: run relay/node Go, Swift, Android
  plugin parity,
  `test/integration/group_notification_dedupe_integration_test.dart`, discovery,
  and device artifact validation directly.

## Acceptance Gates

```bash
# Snapshot before execution; preserve unrelated changes.
git status --short

# First Dart causal RED: HEAD parses reaction plaintext as a group message.
flutter test test/features/push/application/push_decrypt_preview_test.dart \
  --plain-name 'group reaction preview uses local group actor and decrypted emoji'

# Recipient-policy RED: HEAD notifies a non-reactor bystander.
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name 'group reaction notifies target author but not reactor or bystander'
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name 'missing local identity fails closed for reaction notification'

# Foreground drain RED: HEAD returns drained before contextual display.
flutter test test/features/groups/integration/group_reaction_notification_pipeline_test.dart \
  --plain-name 'foreground drained reaction still runs contextual notification gate'

# Transition RED: deterministic ADD id conflicts after remove/re-add.
flutter test test/features/groups/application/send_group_reaction_use_case_test.dart \
  --plain-name 'ADD remove same ADD persists unique transition ids and exact retry reuses one'

# Relay/node RED: HEAD derives recipients after signing and pushes group_message
# to every replay device, including REMOVE.
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test -count=1 \
  -run 'GroupInbox(Store|Handler)_Reaction|GroupReactionTransition' ./...)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -count=1 \
  -run 'GroupReaction.*SignedRecipientSet' ./node/...)

# Read-event RED: HEAD has no group read-event emission contract.
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name 'markAsRead emits group read event only when rows changed'

# Android every-engine group decrypt parity; Plan 256 already owns the generic
# real-FCM registration preflight.
(cd android && ./gradlew :background_push_crypto:testDebugUnitTest \
  --tests 'com.mknoon.background_push_crypto.BackgroundPushCryptoPluginTest.groupDecryptMatchesGoFixture')

# Focused Dart GREEN; exit 0 with zero failures.
flutter test \
  test/features/groups/domain/models/group_reaction_payload_test.dart \
  test/features/groups/application/group_offline_replay_envelope_test.dart \
  test/features/groups/application/send_group_reaction_use_case_test.dart \
  test/features/groups/application/remove_group_reaction_use_case_test.dart \
  test/features/groups/application/group_message_listener_test.dart \
  test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart \
  test/features/groups/application/drain_group_offline_inbox_use_case_test.dart \
  test/features/groups/domain/repositories/group_message_repository_impl_test.dart \
  test/features/groups/integration/group_notification_projection_lifecycle_test.dart \
  test/features/groups/integration/group_reaction_notification_pipeline_test.dart \
  test/features/groups/integration/group_reaction_roundtrip_test.dart \
  test/features/groups/integration/announcement_happy_path_test.dart \
  test/features/orbit/presentation/screens/orbit_group_unread_notification_wired_test.dart \
  test/features/orbit/presentation/screens/orbit_wired_test.dart \
  test/features/push/application/handle_foreground_remote_message_use_case_test.dart \
  test/features/push/application/push_decrypt_preview_test.dart \
  test/features/push/application/background_push_notification_fallback_test.dart \
  test/features/push/application/background_message_handler_test.dart \
  test/features/push/application/resolve_group_notification_route_target_use_case_test.dart \
  test/core/notifications/notification_route_target_test.dart \
  test/core/notifications/remote_notification_identity_test.dart \
  test/core/notifications/flutter_notification_service_test.dart \
  test/core/notifications/recent_remote_notification_gate_test.dart

# Relay/node/privacy GREEN; two author devices only, full exact replay storage,
# transition retry/remove-readd, capability rollback, zero private plaintext.
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test -count=1 \
  -run 'GroupReaction|GroupInbox(Store|Handler)_Reaction|BuildGroupPushMessage' ./...)
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test -count=1 \
  -run 'GroupReaction(Transition|CapabilityRolloutAndRollback).*' ./...)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -count=1 \
  -run 'GroupReaction.*(SignedRecipientSet|TwoAuthorDevices)' ./node/...)
flutter test test/security/forbidden_field_classifier_test.dart

# Swift resolver/identity GREEN on the available simulator.
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,id=DBE8C32E-9F19-4593-860A-B41113791D79' CODE_SIGNING_ALLOWED=NO -only-testing:RunnerTests/NotificationPreviewResolverTests

# Exact GREEN preservation sentinels; each filter selects at least one test.
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name '127-Bug-D: incoming ADD group reaction notifies (route + emoji)'
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name '127-Bug-D: incoming REMOVE group reaction does NOT notify'
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name '127-Bug-D'
flutter test test/features/groups/integration/announcement_happy_path_test.dart --plain-name 'announcement happy path: create, admin send, reader read-only receive, member react'
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name 'TC-203-04 an incoming group message lights the group ring node (unread badge + semantics)'
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PGC-016 group_reaction without reactionRepo does not persist a message'
flutter test test/features/push/application/push_decrypt_preview_test.dart --plain-name 'decrypts group ciphertext preview with sender-prefixed body'
flutter test test/integration/group_notification_dedupe_integration_test.dart
flutter test test/features/conversation/application/handle_incoming_reaction_use_case_test.dart --plain-name 'only target author is notified while both target directions persist'
flutter test test/features/conversation/application/handle_incoming_reaction_use_case_test.dart --plain-name 'incoming REMOVE reaction does NOT notify'

# Registration/discovery; consolidated host test and all five device scenarios listed.
./scripts/run_test_gates.sh completeness-check
sed -n '/^readonly GROUP_TESTS=(/,/^)/p' scripts/run_test_gates.sh | \
  rg -F 'test/features/groups/domain/models/group_reaction_payload_test.dart'
sed -n '/^readonly GROUP_TESTS=(/,/^)/p' scripts/run_test_gates.sh | \
  rg -F 'test/features/groups/application/send_group_reaction_use_case_test.dart'
sed -n '/^readonly GROUP_TESTS=(/,/^)/p' scripts/run_test_gates.sh | \
  rg -F 'test/features/groups/application/remove_group_reaction_use_case_test.dart'
sed -n '/^readonly GROUP_TESTS=(/,/^)/p' scripts/run_test_gates.sh | \
  rg -F 'test/features/groups/integration/group_reaction_roundtrip_test.dart'
sed -n '/^readonly GROUP_TESTS=(/,/^)/p' scripts/run_test_gates.sh | \
  rg -F 'test/features/groups/integration/group_reaction_notification_pipeline_test.dart'
sed -n '/^readonly GROUP_TESTS=(/,/^)/p' scripts/run_test_gates.sh | \
  rg -F 'test/features/orbit/presentation/screens/orbit_group_unread_notification_wired_test.dart'
dart run integration_test/scripts/run_group_reaction_notification_device.dart --list-scenarios
./scripts/check_reliability_simulation_discovery.sh

# Runner/proof binding and artifact validation; app/SQLCipher/relay/provider
# records are authoritative, not runner-authored booleans.
dart run integration_test/scripts/run_group_reaction_notification_device.dart \
  --validate-artifacts build/group_reaction_notification_proof

# Physical iOS notification boundary after the runner prepares peers/provider.
xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS,id=00008150-001C3C6A3684401C' \
  -only-testing:RunnerUITests/NotificationTapUITests/testAnnouncementReactionNotificationTap

# Per-plan curated/family gates; exit 0 and zero failures.
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all
./scripts/run_host_test_gates.sh core-host-all

# Hygiene; no new analyzer issues or whitespace errors.
./scripts/check_flutter_analyze_baseline.sh
git diff --check
```

## Device/Relay Proof Profile

- Profile: os-notification-device-lab.
- Boundary being proven: real group replay custody, target-author FCM/APNs
  delivery, transition-id custody, background-plugin execution, SQLCipher
  group/roster/mute/target eligibility, real group crypto, iOS NSE execution,
  OS card copy/thread, automated tap, target route, reaction application, and
  ordinary-message Orbit unread lifecycle. TC-04/19 separately prove two active
  author devices versus a bystander and full replay-set parity on host backends.
- Live availability check (2026-07-11 22:59 CEST):
  `flutter devices --machine`, `adb devices -l`, `flutter emulators`, and
  `xcrun simctl list devices available` found physical Pixel 6
  `21071FDF600CSC`, Android AVD `mknoon_play_35` (runtime
  `emulator-5554` when booted), physical iPhones
  `00008150-001C3C6A3684401C`, `00008110-00184D622289801E`, and
  `00008030-001A6D2801BB802E`, plus booted iPhone 16e simulator
  `DBE8C32E-9F19-4593-860A-B41113791D79`. Re-resolve immediately before proof;
  unavailable targets are N/A under project policy.
- Required setup: clean candidate builds, automated permission grants, unique
  admin/member identities, accepted group membership, staging relay running the
  Plan-257 binary with typed wake default-off until client capability is
  registered, valid capability-bearing push tokens, clear notification trays,
  real crypto
  frameworks/plugins, redacted timestamped app/relay/provider logs, and no
  concurrent use of selected targets.
- Two-peer default: all non-iOS scenarios use reactor/sender A =
  `emulator-5554` and target-author/recipient B = `21071FDF600CSC`. The harness
  creates the correct group type and roles, authors the target on B, reacts on
  A, controls lifecycle/shade/tap/navigation, and asserts artifacts with no
  user taps.
- iOS-specific topology: TC-16 uses Android member/reactor A =
  `21071FDF600CSC` and physical iPhone admin/author B =
  `00008150-001C3C6A3684401C`. A physical iPhone is required only for genuine
  APNs/NSE proof; XCUITest drives permissions, termination, card inspection,
  tap, and return.
- Closure role: TC-13..16 are required while their targets are available.
- `FLUTTER_DEVICE_ID`: insufficient; each scenario requires explicit sender,
  recipient, relay/provider config, group type, and role assignment.
- Registration:
  `integration_test/group_announcement_reaction_notification_proof_test.dart`
  uses the existing `_proof_test.dart` device classification. The runner must
  invoke the proof and separate artifact validator. Register the runner in both
  `classify_path` and `expand_record_to_checks`, then register
  scenarios `android_group_message_unread_lifecycle`,
  `android_announcement_message_unread_lifecycle`,
  `android_group_reaction_recipient`,
  `android_announcement_reaction_recipient`, and
  `ios_announcement_reaction_recipient` under group discovery.
- Discovery command:
  `dart run integration_test/scripts/run_group_reaction_notification_device.dart --list-scenarios && flutter devices --machine && adb devices -l && flutter emulators && xcrun simctl list devices available`
  -> all five scenarios and selected target ids listed.
- Android chat unread closure:
  `dart run integration_test/scripts/run_group_reaction_notification_device.dart --scenario android_group_message_unread_lifecycle --sender emulator-5554 --recipient 21071FDF600CSC --artifact-dir build/group_reaction_notification_proof/android_group_message_unread_lifecycle`
  -> SQLCipher/UI unread and satellites `0 -> 1 -> 1 after dismiss -> 2 -> 0
  after tap/read`, real route/read marker, both messages visible, unlit on
  return.
- Android announcement unread closure: same command with
  `--scenario android_announcement_message_unread_lifecycle` and matching
  artifact directory -> identical lifecycle with admin sender/member reader.
- Android reaction closure: run the same runner once with
  `--scenario android_group_reaction_recipient` and once with
  `--scenario android_announcement_reaction_recipient` -> each exits 0 with one
  target-author `<group>` / `Alice reacted 👍 to your message` card, typed
  transition event id distinct from target/state id, target route, stored
  reaction, a second distinct transition replacing the same group card, zero
  REMOVE/duplicate/unread card,
  and empty recipient `pidof` before delivery/tap. No `am force-stop`; TC-04,
  not this two-peer leg, proves zero bystander push.
- iOS closure:
  `dart run integration_test/scripts/run_group_reaction_notification_device.dart --scenario ios_announcement_reaction_recipient --sender 21071FDF600CSC --recipient 00008150-001C3C6A3684401C --artifact-dir build/group_reaction_notification_proof/ios_announcement_reaction_recipient`
  -> NSE decrypt success, exact announcement/actor/emoji copy, group thread,
  target route, transition dedupe, typed silent timeout fallback, zero forbidden
  fields/unread mutation, and one audible alert. Any retained second item is
  passive in the same thread.
- Deferred device work: a three-member physical bystander run is optional; the
  author-vs-replay-recipient decision is deterministically closed by TC-01/04.
  Unavailable OS/API bands are N/A.

## Execution Interpretation And Done Criteria

- Expected RED: TC-01 notifies a bystander/missing-identity instance; TC-03 has
  no compatible optional extension; TC-04 pushes every replay device and REMOVE
  as `group_message`; TC-05 lacks headless group decrypt; TC-06 renders generic
  copy; TC-07 conflates identities; TC-17 conflicts on re-add; TC-20 loses the
  foreground-drained alert; TC-12 has no group read event.
- Green sentinel: TC-00 preserves landed live copy/REMOVE silence; TC-02
  preserves announcement reuse while adding author filtering; TC-09/10 preserve
  suppression, ordinary messages, and all-member convergence; TC-11 preserves
  message-only unread semantics.
- Pre-existing dirty tree / known failure: extensive unrelated plan, media,
  database, native, Graphify, l10n, test, and gate work existed at planning
  time. Do not revert, absorb, or reformat it. Planning probes named above
  selected and passed.
- Environment blocker: none for Android closure. The staging manifest/provider
  configuration was supplied, the paired Android runner completed on explicitly
  discovered emulator and USB targets, and TC-13..15 artifacts are accepted.
  Physical-iOS TC-16 was not run because this verification request was scoped to
  emulators and USB-connected Android; it remains an open iOS-specific closure
  row rather than a failure or N/A.
- Scope drift: narrowing reaction replay recipients, changing announcement
  write policy, adding a reaction badge, changing ordinary message copy, a DB
  migration, or broad app-wide notification presentation blocks completion and
  requires a separate decision.

- [x] Every TC-00..20 behavior has its named automated test/proof.
- [x] Causal RED, focused GREEN, and representative mutation re-red are
      recorded.
- [x] Relay/node prove full exact replay-device storage plus every capable active
      target-author device—and no REMOVE/bystander/legacy device—receives typed
      push with zero private plaintext.
- [x] Chat and announcement copy, recipient, route, dedupe, mute, and unread
      semantics pass at host/native tiers.
- [x] GROUP_TESTS, device discovery, notification matrix, and current test map
      are synchronized.
- [x] TC-13, TC-14, and both Android TC-15 discussion/announcement scenarios
      have accepted live artifacts from an emulator sender plus physical Android
      recipient, with real relay/FCM/SQLCipher/UI automation evidence.
- [ ] Physical-iOS TC-16 has not been executed in this Android-only verification.
- [x] TC-17/18 close remove-readd/exact retry and old/new/rollback; TC-19 closes
      multi-device identity and relay-authority limits; TC-20 closes foreground
      drain.
- [x] Groups, justified feature/core sweeps, Plan-257 scoped analysis, and
      tracked/untracked whitespace checks pass.
- [ ] The repo-wide analyzer baseline matches exactly. The settled run has zero
      analyzer errors but reports 337 unrelated new warning/info classifications
      and 374 removed baseline entries from concurrent dirty-tree harness work;
      the baseline was not rewritten to hide that drift.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command:
  `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name 'group reaction notifies target author but not reactor or bystander'`.
- Preservation command:
  `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name '127-Bug-D' && flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name 'TC-203-04 an incoming group message lights the group ring node (unread badge + semantics)'`.
- Registration: payload/send/remove/roundtrip,
  `group_reaction_notification_pipeline_test.dart`,
  `orbit_group_unread_notification_wired_test.dart`, and the device criteria
  test are in `GROUP_TESTS`; the proof/runner/validator and all five scenarios
  are present in both canonical reliability discovery expansion sites and the
  test documentation is synchronized.
- Migration: none; no database version or SQLCipher schema change.
- Boundary closure: Go relay + Swift NSE host contracts and paired Android
  physical/emulator chat and announcement scenarios are accepted; the planned
  physical-iPhone announcement NSE proof remains pending as TC-16.
- Per-plan gates: exact tests, groups, feature-host-all, core-host-all; the
  Plan-256 + Plan-257 dependency wave and final release each own one full
  `host-all`.
- Implemented: discussion and announcement reactions share an author-only
  contextual notification gate; typed remote ADD wakes eligible author devices
  while REMOVE/bystander/legacy paths stay silent; signed optional extension
  compatibility and distinct transition identity are pinned; group read emits
  the Orbit refresh event without turning reactions into unread messages.
- Refuted: neither a Plan-256 scope expansion nor separate chat/announcement
  implementation plans match the current architecture.
- Unresolved evidence: Android real-provider/device evidence is closed. Physical
  iOS TC-16 remains open if full cross-platform Plan-257 closure is requested.
  The repository analyzer baseline also needs its unrelated
  harness-consolidation debt reconciled by the owning work before it can pass
  globally.
- Review state: independent `$tdd-review` completed on 2026-07-11. Its fixture,
  optional-wire, transition-id, multi-device, foreground-drain, native-engine,
  iOS limitation, rollout, and gate deltas are implemented and covered by the
  focused host/native evidence below.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-12 | RED/GREEN implementation | Group listener/send/remove/envelope, notification projection/routing, Orbit/read event, relay/node, Android plugin, iOS NSE | Plan-required causal REDs were made GREEN; representative eligibility, identity, retry, and compatibility mutations re-red before restoration | Author-only chat/announcement copy, foreground and killed-process routing, distinct transition/state/target ids, REMOVE silence, unread preservation, and notification-routed Orbit refresh are implemented | Production and deterministic boundary work complete | Finish proportional acceptance gates |
| 2026-07-12 | Focused host/native verification | 25 focused Dart files; `go-relay-server`; `go-mknoon/node`; Android `background_push_crypto`; Swift resolver | Consolidated Dart bundle: 753 tests passed; Go relay/node focused gates passed; Android plugin tests passed; Swift resolver: 39 tests passed | TC-00..12 and TC-17..20 deterministic contracts are green, including frozen pre-extension v1-reader compatibility | No deterministic blocker recorded | Complete curated lane reruns |
| 2026-07-12 | Device harness/validator | Plan-257 capture/runner/criteria, SQLCipher probe, `NotificationTapUITests.swift` | Criteria: 22/22 passed; post-hardening shell contract passed; scoped analyze clean; iOS XCUITest `build-for-testing` succeeded | Five scenarios are registered; Android raw capture and physical-iOS identity/membership/target/card/tap seams are implemented and reject marker-only, stale, unlaunched-retry, or transition-mismatched evidence | No accepted device artifact without staging authority | Supply a valid redacted manifest and relay/provider credentials, then run TC-13..16 |
| 2026-07-12 15:34 CEST | Availability-bounded device attempt | explicit Android sender `emulator-5554`, recipient `21071FDF600CSC`; physical iOS remains available for its separate row | Runner exited 78 and persisted `status=configuration_blocked`, `stage=configuration`, `detail=staging_manifest_required` before capture | Honest non-success verdict; host/native evidence was not promoted to device proof | Configuration-blocked, not N/A and not a missing automation seam | Rerun only when staging/provider configuration is available |
| 2026-07-12 | Final curated lanes | groups, `feature-host-all`, `core-host-all`, analyzer/diff, Graphify | groups: 2,031 Flutter tests plus Go bridge/node passed; `feature-host-all`: 757/757 commands passed; `core-host-all`: 306/306 commands passed; settled Plan-257 scoped analysis found no issues; tracked and untracked whitespace checks passed; incremental architecture graph refreshed | All required deterministic and proportional Plan-257 lanes are green | Repo-wide analyzer comparison exits nonzero with zero errors, 337 unrelated new warning/info classifications, and 374 removed entries | Reconcile the unrelated analyzer baseline in its owning work; do not broaden this plan |
| 2026-07-12 18:19 CEST | Relay payload-size RED/GREEN and deployment | `go-relay-server/reaction_push.go`, `inbox.go`, `group_reaction_push_test.go`; EC2 `relay-server` | `TestGroupReactionPushProjectsOnlyTheRecipientPlatformPayload` red before platform projection and green after it; full relay suite passed; Go 1.25 build deployed and service restarted | Android sends exclude APNs custom data and iOS sends exclude Android/top-level data, keeping typed reaction FCM payloads below the provider limit | Live service active with both reaction flags enabled; SHA-256 `e278de338500cd3089255943a43bfcdc51c7f6b2de954bd71517402d29da1f80` | Preserve the pinned Go 1.25 build until the separate Go 1.26/quic-go compatibility issue is resolved |
| 2026-07-12 19:36 CEST | Paired Android ordinary-message preservation | `android_group_message_unread_lifecycle`, `android_announcement_message_unread_lifecycle`; emulator sender + USB Pixel `21071FDF600CSC` | Both raw runners passed and both persisted artifacts revalidated as `VALID` under TC-13/TC-14 | Discussion and announcement unread state followed `0 -> 1 -> 1 after dismiss -> 2 -> 0 after notification tap/read`; return to Orbit was unlit and SQLCipher state agreed | Accepted artifacts: `build/group_reaction_notification_proof/android_group_message_unread_lifecycle/` and `android_announcement_message_unread_lifecycle/` | None for Android ordinary-message preservation |
| 2026-07-12 19:36 CEST | Paired Android reaction proof | `android_group_reaction_recipient`, `android_announcement_reaction_recipient`; sender `emulator-5556`, recipient `21071FDF600CSC` | Discussion capture completed, then its initial same-run validation exposed the stale command-journal probe contract; after the state-preserving probe/validator fix its persisted artifact revalidated as `VALID`. The announcement full runner passed, and its artifact also revalidated as `VALID`; provider logs show two attempt-1 sends per ADD/REMOVE/ADD scenario | Exact `Alice reacted 👍 to your message` context, stable group-card replacement, cold-tap target routing, zero reaction unread/synthetic message rows, REMOVE silence, distinct transitions, exact-byte retry, and real headless SQLCipher/native decrypt are accepted for discussion and announcement | Accepted artifacts: `build/group_reaction_notification_proof/android_group_reaction_recipient/` and `android_announcement_reaction_recipient/`; shared-journal payload-size errors outside these capture windows belong to concurrent direct-media traffic | Physical-iOS TC-16 remains separate and open |
| 2026-07-12 19:52 CEST | Regression sufficiency and final focused verification | background group-key hydration, notification-open drain isolation, state-preserving exact-redrive probe, production marker/validator contracts, relay platform projection | Focused 12-file Flutter bundle: 208 tests passed; graph-affected route/staging/dedupe bundle: 61 tests passed; exact Plan-257 analysis: no issues; relay `go test -count=1 ./...` passed; `go-mknoon/node` passed in 449.006s; Android group-decrypt fixture test `BUILD SUCCESSFUL`; four artifact validators passed | Regressions now fail on raw secure-key references, cold-tap drain exceptions, app-erasing retry probes, stale proof markers, cross-platform payload duplication, notification copy/identity/unread drift, adjacent route/dedupe drift, or invalid artifact provenance | Sufficient layered coverage for the Android bug and relay boundary; broad `scripts/run_test_gates.sh` intentionally not rerun per user instruction | Run physical-iOS TC-16 only if cross-platform closure is requested |
