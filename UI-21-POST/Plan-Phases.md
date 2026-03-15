# Posts Implementation Checklist

This plan treats `../kitchen/landing-screen-claude/neighbourhood_spec.md` as the source of product intent. The approved Phase 0 artifact set under `UI-21-POST/`, including `Posts-UI-State-Inventory.md` and its incorporated screenshot references, is the source of implementation contract and visual acceptance for Posts.

## Working Rules

- Build Posts as JSON envelopes over the existing direct send and offline inbox paths in `lib/core/services/p2p_service.dart`, `lib/core/services/p2p_service_impl.dart`, `lib/core/bridge/p2p_bridge_client.dart`, and `lib/core/bridge/go_bridge_client.dart`, but do not treat that as a bulk-broadcast primitive. Posts fanout is still app-owned, per-recipient delivery over single-peer send APIs.
- Lock the delivery model early:
  - `post_create` fanout is one envelope per recipient
  - each recipient gets their own v2 encrypted envelope when an ML-KEM public key is available, otherwise the approved v1 plaintext fallback
  - send, race, inbox fallback, and retry persistence stay feature-owned at the app layer
  - partial recipient failure is expected and must not roll back already-persisted successful recipients
- Do not add a new `go-mknoon/node/node.go` protocol in early phases unless an actual transport gap appears. For this feature, most complexity is product logic, persistence, and UI, not libp2p framing.
- Keep every phase vertically complete: DB migration, router/listener wiring, sender flow, receiver flow, restart behavior, and tests.
- Every phase that adds or changes schema must also bump the DB version in `lib/main.dart`, register the migration there, and add migration-regression coverage for upgrade paths.
- Follow the repo pattern: `domain/`, `application/`, `presentation/`, helper-backed repositories, and `Wired` screens.
- Make live delivery, offline inbox replay, and push-triggered wake-up drain converge into the same Posts ingestion path. Do not create a separate "push-only" code path for posts.
- Reuse the existing conversation voice/media stack where semantics already match. Do not create a second recorder, waveform, upload, or audio-player implementation for Posts when the current app already provides one.

## Strict TDD Rules

- Every phase must follow strict `RED -> GREEN -> REFACTOR`. Do not write production code for a phase slice until the targeted failing tests for that slice exist and have been observed failing.
- Start at the lowest proving layer first:
  - pure logic, payload parsing, model mapping, DB helpers, migrations, and widget-state tests
  - then repository, listener, and use-case integration tests with fakes
  - then simulator or CLI smoke coverage for multi-device, lifecycle, notification, media, and permission flows
- Reuse existing harnesses before inventing new ones:
  - `test/shared/fakes/fake_p2p_network.dart`
  - `test/shared/fakes/fake_p2p_service_integration.dart`
  - the in-memory repositories under `test/shared/fakes/`
  - the existing `integration_test/` flows and `integration_test/scripts/`
- Build a lightweight in-memory Posts repository fake as soon as Phase 1 tests need one. Do not let the first vertical slice couple RED-only tests to SQLite when a fake would prove the behavior faster.
- If a phase needs a new fake, stub, or simulator harness to make RED-first practical, build that harness as the first test task of the phase before production code.
- A phase cannot exit on unit tests alone if it changes any of:
  - inbox replay
  - startup or resume behavior
  - notifications or tap routing
  - media delivery or rendering
  - multi-device delivery
  - location permissions or proximity eligibility
- Refactor only after the new targeted tests are green. Keep refactors phase-scoped and rerun the targeted suite after each refactor step.
- The implementation notes or PR for each phase must record the initial RED evidence: the exact failing test names or commands written before the implementation.

## Phase Control Rules

- Every phase must be split into 3-5 numbered internal slices.
- Every slice must define:
  - prerequisite harnesses or builders that must exist before production edits
  - the RED tests written first for that slice
  - the primary allowed edit set for that slice
  - a mini exit gate before the next slice begins
- A phase is not complete just because the end-to-end smoke test works once. Every internal slice mini gate and the phase command matrix must pass.
- Every phase close-out must record:
  - residual risks
  - explicit deferrals
  - next-phase prerequisites

## Contract and Delivery Baseline

- Phase 0 must lock the Posts wire contract before Phase 1 production code starts.
- The contract artifacts may live as separate docs under `UI-21-POST/` or as locked appendices in this plan, but they must exist in-repo before Phase 1 coding.
- If `neighbourhood_spec.md` and this plan disagree on a v1 product rule, Phase 0 must reconcile the product spec first and then produce the contract artifacts. Phase 1 must not choose between conflicting sources.
- Raw screenshots help with UI implementation, but they do not satisfy the Phase 0 contract gate by themselves.
- If any of these files are missing, the rollout is still blocked in Phase 0 and a Phase 1 implementer must stop rather than infer the missing contract inside Phase 1:
  - `UI-21-POST/Posts-Envelope-Schemas.md`
  - `UI-21-POST/Posts-Ingest-Flow.md`
  - `UI-21-POST/Posts-Feed-Rules.md`
  - `UI-21-POST/Posts-Nearby-Privacy-Contract.md`
  - `UI-21-POST/Posts-UI-State-Inventory.md`
  - `UI-21-POST/Phase-0-Approval.md`
- The contract artifact set must include:
  - exact payload schemas
  - versioning rules
  - required and optional fields
  - sample JSON
  - idempotency keys
  - sender and trust validation rules
  - feed ordering rules
  - live, replay, and notification-ingest flow diagrams
  - UI state inventory or acceptance snapshots
  - explicit approved v1 defaults where the product spec is silent
  - an approval record showing these defaults were ratified, not invented ad hoc during implementation
- Minimum envelope coverage:
  - `post_create`
  - `post_comment`
  - `post_reaction`
  - `post_comment_reaction`
  - `post_presence_update`
  - `post_pass`
  - `post_pin_update`
  - `post_pin_remove`
- Minimum common envelope fields to lock in Phase 0:
  - `type`
  - `version`
  - `event_id`
  - `created_at`
  - `sender_peer_id`
- Minimum entity ids to lock in Phase 0:
  - `post_id`
  - `comment_id`
  - `reaction_id`
  - `pass_id`
  - `pin_event_id`
  - or an explicitly approved equivalent naming scheme
- Canonical convergence and dedupe rules that must be approved before Phase 1:
  - live delivery, inbox replay, and wake-up drain all call the same typed ingest use case path
  - duplicate `post_create` deliveries for the same `post_id` must never render twice
  - child events that arrive before their parent post exists must be staged and reconciled later, not dropped
  - mutable events such as pin updates must have an explicit conflict rule, for example latest approved event wins
  - feed order must be driven by the approved Posts ordering rule, not by whichever transport path happened to deliver first

## File Boundary Discipline

- Every phase must define:
  - inspect-first files
  - primary edit zone
  - avoid-unless-required files
- Edits outside the primary edit zone require a written reason in the phase notes or PR.
- Native bridge or Go files stay in the avoid-unless-required set until a phase explicitly proves an app-layer gap.

## UI Scope That Must Be Carried Through The Phases

- [ ] The post-card design is part of the implementation scope, not a later polish pass. The Posts widgets must cover the full card anatomy from the spec:
  - reshare attribution
  - author row
  - direct-friend badge where applicable
  - scope badge
  - text expansion
  - media rendering
  - action bar
  - expiry footer
- [ ] The feed structure is also in scope:
  - header
  - compose prompt
  - pinned section
  - time-grouped feed
  - caught-up state
- [ ] Compose states are in scope:
  - audience chooser
  - nearby radius chooser
  - nearby availability and error states in compose
  - pick-people selection
  - keep-available toggle
  - post confirmation
- [ ] Post detail states are in scope:
  - comments sheet
  - passed-along cards
  - nearby cards with distance
  - pinned cards
  - own-post management states
- [ ] If any of these UI pieces are intentionally deferred, note that explicitly in the phase exit gate instead of silently dropping them.

## Reference Screenshots

- The visual reference pack currently lives under `UI-21-POST/screenshots/`.
- `Posts-UI-State-Inventory.md` is the normative UI acceptance artifact. Raw screenshots are authoritative only where they are explicitly incorporated there by filename.
- Use the screenshot pack for spacing, hierarchy, sheet height, chip placement, card anatomy, and blocked-state presentation through that inventory artifact.
- Primary screenshot-to-state mapping:
  - `screenshots/01-default-feed.png`: default Posts feed
  - `screenshots/02-friend-text-post.png`: direct-friend text card
  - `screenshots/03-nearby-post-distance.png`: nearby card with distance label
  - `screenshots/04-passed-along-post.png`: pass-along attribution card
  - `screenshots/05-pinned-collapsed.png`: pinned section collapsed
  - `screenshots/06-pinned-expanded.png`: pinned section expanded
  - `screenshots/07-compose-default.png`: compose default state
  - `screenshots/08-compose-nearby-stale.png`: compose blocked stale nearby state
  - `screenshots/09-compose-nearby-ready.png`: compose nearby ready state
  - `screenshots/10-compose-media.png`: compose with media attached
  - `screenshots/11-compose-voice-recording.png`: Posts compose voice recording state
  - `screenshots/12-compose-voice-draft.png`: Posts compose voice draft attached
  - `screenshots/13-comments.png`: comments sheet
  - `screenshots/14-caught-up.png`: caught-up or empty state
  - `screenshots/15-voice-recording.png`: existing 1:1 voice-recording reference for recorder chrome reuse
  - `screenshots/16-voice-message.png`: existing posted voice-message reference
- `Posts-UI-State-Inventory.md` should reference these screenshots explicitly by filename. The contact-sheet images are convenience previews only, not the source of truth.

## Phase 0 Artifact Index

- `UI-21-POST/Posts-Envelope-Schemas.md`: normative wire contract, idempotency, and sender validation
- `UI-21-POST/Posts-Ingest-Flow.md`: live, replay, notification-open, staging, and duplicate handling
- `UI-21-POST/Posts-Feed-Rules.md`: feed ordering, pin ordering, overflow, and reorder triggers
- `UI-21-POST/Posts-Nearby-Privacy-Contract.md`: nearby privacy semantics, persistence, TTL, refresh, and invalidation
- `UI-21-POST/Posts-UI-State-Inventory.md`: screenshot-backed UI state inventory and fallback rules
- `UI-21-POST/Phase-0-Approval.md`: human ratification record for unresolved v1 defaults

## Phase 0 Approval Authority

- Unresolved v1 defaults that are not explicitly stated in `neighbourhood_spec.md` must be approved by a named human, not self-approved by an implementation agent or review agent.
- Default approval authority is the requesting maintainer or delegated human feature owner for this rollout.
- The ratification artifact is `UI-21-POST/Phase-0-Approval.md`.
- Phase 0 approval is not complete until that file records:
  - the named human approver
  - the approval date
  - the exact artifact set being approved
- AI-authored drafts may prepare the contract docs, but they do not count as final approval on their own.

## Phase 0 Assumptions

- `Posts` is the final feature name.
- `Posts` is its own primary tab in the app shell. Do not treat this as an open nav experiment later.
- `People Nearby` means direct friends inside a radius, not strangers.
- Friend-of-friend content only arrives through explicit pass-along.
- Pass-along is one explicit extra hop in v1, not an open-ended reshare chain.
- Pinned posts have no preset expiry in v1.
- There is no persistent privacy panel on the Posts feed.
- Settings owns the persistent nearby/privacy controls, and compose shows nearby status only when it affects posting.
- Contact eligibility rules are locked in v1:
  - Posts audience selection uses active direct contacts only
  - blocked contacts are excluded from `All Friends`, `Pick People`, and `People Nearby`
  - archived contacts are excluded from audience pickers and nearby eligibility
  - incoming Posts envelopes from blocked direct contacts are rejected before persistence
  - incoming Posts envelopes from archived direct contacts may persist, but notifications are suppressed

Remaining cleanup before coding:

- [ ] Keep reshared trust context simple in v1: no mutual-friends badge on reshared posts, only the `passed this along` attribution line.
- [ ] Keep reactions simple in v1: heart-only on posts and comments. Do not inherit the broader emoji-reaction model from chat.

### Phase 0 Required Outputs

- [ ] Check in an approved payload-contract artifact, for example `UI-21-POST/Posts-Envelope-Schemas.md`, that includes exact JSON schemas, required fields, sample payloads, versioning rules, and idempotency keys for every Posts envelope.
- [ ] `Posts-Envelope-Schemas.md` must also include an explicit `Approved V1 Semantics` section that resolves:
  - `post_reaction` event shape, heart toggle semantics, and idempotency scope
  - `post_comment_reaction` event shape, heart toggle semantics, and idempotency scope
  - `post_pin_update` authority, replace-versus-patch behavior, and remove or tombstone semantics
  - active pinned-post edit transport semantics in v1
  - original-author-only authority for both `post_pin_update` and `post_pin_remove`
  - one visible sender-side `Remove` action in v1, with one canonical `post_pin_remove.reason` value unless a later product change explicitly expands it
  - notification-open payload contract for post targets and comment-entry targets
  - pass-along engagement semantics for comments, hearts, delivery recipients, and expiry effects
- [ ] Check in an ingest-flow artifact, for example `UI-21-POST/Posts-Ingest-Flow.md`, that covers:
  - live delivery
  - inbox replay
  - notification-open routing
  - out-of-order child-event staging
  - duplicate delivery handling
- [ ] Check in an approved feed-rules artifact that locks:
  - feed ordering
  - pin ordering
  - duplicate-merge behavior
  - conflict resolution for mutable events
- [ ] `Posts-Feed-Rules.md` must also include an `Approved Ordering Keys and Tie-Breakers` section that resolves:
  - direct-post ordering key
  - pass-along ordering key
  - pin ordering key
  - collapsed-header overflow winner rules for pins and avatars
  - whether edits, comments, pin updates, removals, or reshares reorder existing cards
  - chronological section boundaries, timezone rules, and day-rollover behavior for `Right now`, `Earlier today`, and `Yesterday`
- [ ] Check in an approved nearby/privacy contract artifact, for example `UI-21-POST/Posts-Nearby-Privacy-Contract.md`, that resolves:
  - how the product promise of "~200m area" maps to the encoded coarse snapshot
  - whether local nearby snapshots persist across app close
  - what "sharing stops when app is closed" means in v1
  - freshness TTL
  - startup and resume refresh behavior
  - invalidation rules when permission, sharing, or services change
  - the final `post_presence_update` payload assumptions that later phases may rely on
- [ ] Check in a UI state inventory or approved acceptance snapshots for:
  - default feed
  - direct-friend post card
  - nearby post card
  - pass-along post card
  - compose default
  - compose nearby blocked state
  - media draft state
  - voice draft state
  - comments sheet
  - pinned collapsed and expanded states
  - and map each accepted state to the corresponding file under `UI-21-POST/screenshots/` where one exists
- [ ] Check in a Phase 0 approval record at `UI-21-POST/Phase-0-Approval.md` that names the human approver and the approved artifact set.
- [ ] Do not start Phase 1 until all six Phase 0 artifact files exist on disk and the approval record is filled in. If any are missing, the assignee is still doing Phase 0 work even if the intent was "start Phase 1".

### Phase 0 Acceptance Commands

- [ ] `test -f UI-21-POST/Posts-Envelope-Schemas.md`
- [ ] `test -f UI-21-POST/Posts-Ingest-Flow.md`
- [ ] `test -f UI-21-POST/Posts-UI-State-Inventory.md`
- [ ] `test -f UI-21-POST/Posts-Feed-Rules.md`
- [ ] `test -f UI-21-POST/Posts-Nearby-Privacy-Contract.md`
- [ ] `test -f UI-21-POST/Phase-0-Approval.md`
- [ ] `rg -n "Approved V1 Semantics|post_reaction|post_comment_reaction|post_pin_update|notification-open payload|pass-along engagement" UI-21-POST/Posts-Envelope-Schemas.md`
- [ ] `rg -n "Approved Ordering Keys and Tie-Breakers|direct-post ordering key|pass-along ordering key|pin ordering key|overflow winner|reorder|Right now|Earlier today|Yesterday|timezone|rollover" UI-21-POST/Posts-Feed-Rules.md`
- [ ] `rg -n "~200m|lat_e3|lng_e3|app close|sharing stops|freshness|startup|resume|invalidate|post_presence_update" UI-21-POST/Posts-Nearby-Privacy-Contract.md`
- [ ] `rg -n "^Approved by: .+" UI-21-POST/Phase-0-Approval.md`
- [ ] `rg -n "^Approved on: .+" UI-21-POST/Phase-0-Approval.md`
- [ ] `rg -n "^Approved artifact set: .+" UI-21-POST/Phase-0-Approval.md`
- [ ] `bash -lc '! rg -n "TBD|TODO|OPEN QUESTION|decide later|later decision" UI-21-POST/Posts-Envelope-Schemas.md UI-21-POST/Posts-Ingest-Flow.md UI-21-POST/Posts-Feed-Rules.md UI-21-POST/Posts-Nearby-Privacy-Contract.md UI-21-POST/Posts-UI-State-Inventory.md'`

### Phase 0 Review Checklist

- [ ] File existence is necessary but not sufficient. A reviewer must verify that `Posts-Envelope-Schemas.md` explicitly resolves the wire semantics the product spec does not define on its own:
  - `post_reaction` and `post_comment_reaction` event shape and toggle semantics
  - `post_pin_update` authority, replace-versus-patch behavior, and remove or tombstone semantics
  - original-author-only authority for `post_pin_update` and `post_pin_remove`
  - one visible sender-side `Remove` action in v1 with one canonical `post_pin_remove.reason`
  - per-recipient idempotency scope for `post_create` fanout and later engagement events
  - notification-open target payload contract for posts and comment-entry routing
  - pass-along engagement semantics for comments, hearts, and expiry effects
- [ ] A reviewer must reject Phase 0 if those semantics are merely engineer-proposed. The Phase 0 artifacts must record approved v1 defaults or approval owner and date, not just a drafted interpretation.
- [ ] A reviewer must verify that `Posts-Feed-Rules.md` explicitly resolves the ordering and overflow rules the source spec leaves implicit:
  - direct-post ordering key
  - pass-along ordering key, including whether it sorts by original post time or pass time
  - pin ordering
  - which pins and avatars win collapsed-header overflow
  - whether edits, pin updates, comments, or reshares reorder cards
  - chronological section boundaries and timezone rollover behavior
- [ ] A reviewer must verify that the nearby or privacy contract is reconciled before approving `post_presence_update`:
  - how the product promise of "~200m" maps to the actual encoded coarse snapshot
  - whether local nearby snapshots persist across app close
  - whether "sharing stops when app is closed" means no new presence broadcast, immediate invalidation, or both
  - freshness TTL and startup or resume refresh behavior
  - the final sender and receiver semantics that the Phase 3 implementation details are allowed to assume
- [ ] A reviewer must reject Phase 0 if the nearby/privacy contract leaves app-close behavior, snapshot persistence, or refresh behavior open to implementation interpretation.
- [ ] A reviewer must reject Phase 0 if `Phase-0-Approval.md` does not name a human approver and the exact artifact set ratified.

### Agent Skills

- Primary: `$senior-ui-ux-designer`
- Also use: `$future-mobile-chat-social-ux`
- Use this phase to lock the trust-context and UI-scope assumptions before implementation starts. Do not write production code in Phase 0.

## Phase 1: Direct-Friend Posts MVP

Outcome: a real Posts tab where direct friends can publish text posts to `All Friends` or `Pick People`, receive them live or via inbox replay, and see them after app restart.

Phase start condition: all required Phase 0 artifact files exist in `UI-21-POST/` and `Phase-0-Approval.md` is filled in by a named human approver. If not, stop and complete Phase 0 instead of backfilling contract decisions inside Phase 1 slices.

### Internal Slices

- Slice 1: contract lock, router, core schema, duplicate-create handling, and fake repo.
  Prerequisite harnesses: in-memory Posts repository fake.
  RED tests first: router parsing for `post_create`, duplicate `post_id` ingest, `027_posts_core` migration, fake repository contract tests.
  Allowed edit zone: `lib/core/services/incoming_message_router.dart`, `lib/core/database/migrations/027_posts_core.dart`, `lib/core/database/helpers/posts_*`, `lib/features/posts/domain/**`, `lib/features/posts/application/handle_incoming_post_use_case.dart`, phase-local fakes.
  Mini exit gate: `post_create` routes into one canonical ingest path and duplicate deliveries for the same `post_id` persist once.
- Slice 2: sender flow plus direct live receiver ingest.
  Prerequisite harnesses: in-memory Posts repository fake plus direct-delivery fake network harness and per-recipient delivery fixture.
  RED tests first: `send_post_use_case` fanout, partial-recipient success plus inbox fallback, direct receiver ingest through `post_listener.dart`, repository round-trip for persisted posts and recipient delivery state.
  Allowed edit zone: `lib/features/posts/**`, `lib/main.dart` listener construction or start points only, phase-local repository tests.
  Mini exit gate: device A sends a direct-friend post, recipient statuses persist correctly, and device B renders the same local model without replay involved.
- Slice 3: inbox replay plus notification-open target handoff.
  Prerequisite harnesses: fake pending post-target store, notification-open harness, feed card focus or scroll helper.
  RED tests first: inbox replay convergence, pending post-target routing from local tap, `onMessageOpenedApp`, `getInitialMessage`, and terminated local fallback launch, repo-observed target settle or timeout fallback, focused post selection after ingest.
  Allowed edit zone: `lib/main.dart` including `_onNotificationTap`, `lib/features/identity/presentation/startup_router.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `lib/core/notifications/notification_service.dart`, `lib/core/notifications/flutter_notification_service.dart`, notification routing files, feed shell-owner files, integration fake harnesses.
  Mini exit gate: replay and notification-open land on the same local post and focus it through the Posts tab.
- Slice 4: shell ownership, Posts tab UI, compose, and Pick People.
  Prerequisite harnesses: shell-controller test harness plus picker widget harness.
  RED tests first: shell tab ownership tests, Posts tab switching, compose-sheet widget states, pick-people picker selection and submit states, blocked or archived contact exclusion in the picker.
  Allowed edit zone: `lib/features/feed/**`, `lib/features/settings/**`, `lib/features/posts/presentation/**`, nav asset or manifest declarations, widget tests.
  Mini exit gate: the app can open and return to the Posts tab without ad hoc tab switching in child screens.

### Prerequisite Harnesses

- [ ] In-memory Posts repository fake.
- [ ] Fake pending post-target store or shell-controller test harness.
- [ ] Notification-open harness for local tap, `onMessageOpenedApp`, and `getInitialMessage`.
- [ ] Per-recipient delivery fixture or fake fanout harness for partial-success and inbox-fallback tests.
- [ ] Feed card focus or scroll test helper for targeted post selection.

### Scope Boundaries

- Inspect first:
  - `lib/main.dart`
  - `lib/features/identity/presentation/startup_router.dart`
  - `lib/core/services/incoming_message_router.dart`
  - `lib/features/feed/presentation/widgets/feed_navigation_bar.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/settings/presentation/screens/settings_wired.dart`
- Primary edit zone:
  - `lib/features/posts/**`
  - `lib/core/services/incoming_message_router.dart`
  - `lib/main.dart`
  - feed shell or tab-owner files under `lib/features/feed/`
- Avoid unless required:
  - `go-mknoon/**`
  - unrelated conversation or group send logic
  - existing chat media playback internals outside reuse wrappers

### Agent Skills

- Primary: `$flutter-feature-module-implementer`
- Also use: `$flutter-sqlite-migrations-and-repositories`, `$mobile-notification-routing-and-deep-linking`, `$flutter-test-orchestrator`
- Use `$senior-ui-ux-designer` only if the implemented Posts tab, card anatomy, or compose flow drifts from the UI scope above.

### Transport and routing

- [ ] Extend `lib/core/services/incoming_message_router.dart` with a `postCreateStream` and route `type == 'post_create'`.
- [ ] Keep `lib/core/services/p2p_service.dart` and `lib/core/services/p2p_service_impl.dart` unchanged at the API level, but do not reduce Posts sending to one generic `sendMessage()` loop. Reuse the existing single-peer delivery semantics through a Posts-owned fanout orchestrator:
  - per-recipient envelope build
  - recipient-specific v2 ML-KEM encryption when available, otherwise approved v1 plaintext fallback
  - direct send or race path first, then inbox fallback
  - persisted per-recipient delivery status for partial success, retry, and restart visibility
- [ ] Do not add new bridge commands in `lib/core/bridge/go_bridge_client.dart`, `lib/core/bridge/p2p_bridge_client.dart`, `go-mknoon/bridge/bridge.go`, or `go-mknoon/node/node.go` for this phase.

### Notifications and replay

- [ ] Wire Posts into the existing app startup and wake-up paths so inbox-drained post payloads are handled exactly like live post payloads:
  - `lib/main.dart`
  - `lib/features/identity/presentation/startup_router.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
- [ ] Add one pending post-target handoff path that all notification entry points use:
  - local notification taps from `NotificationService.onNotificationTap`
  - warm-start opens from `FirebaseMessaging.onMessageOpenedApp`
  - terminated-start opens from `getInitialMessage` via `handleInitialRemoteMessage`
  - terminated-start opens from Android local fallback notifications created in `background_message_handler.dart`
- [ ] Keep that post-target flow explicit:
  - parse and store the target post id and optional focus state
  - trigger inbox drain
  - do not treat `drainOfflineInbox()` return as replay-complete, because it only awaits the first inbox page before background continuation
  - instead wait until the Posts repository or listener layer observes the target post locally, with a bounded timeout and fallback UI state
  - then select the Posts tab and scroll or focus the card
  - do not navigate directly to a post detail route before local ingest finishes
- [ ] Add Posts notification handling by following the same local notification pattern already used by chat and groups:
  - `lib/core/notifications/notification_service.dart`
  - `lib/core/notifications/flutter_notification_service.dart`
  - `lib/features/push/application/background_message_handler.dart`
- [ ] Extend `lib/features/push/application/background_push_notification_fallback.dart` for post payloads instead of relying on the current closed message-type switch and generic fallback path.
- [ ] Generalize notification payload routing so it can open a post target, not only a 1:1 contact or conversation target.
- [ ] Update `_MyAppState._onNotificationTap` in `lib/main.dart` so post payloads are explicitly dispatched instead of falling through to contact lookup.
- [ ] Change the local notification callback contract from contact-specific naming to generic route-target payload semantics:
  - `NotificationService.onNotificationTap`
  - `FlutterNotificationService.onNotificationTap`
  - any startup or fallback handoff that currently assumes the payload is a contact peer id
- [ ] Add explicit cold-start recovery for terminated launches from local fallback notifications, not only live notification tap callbacks. If `flutter_local_notifications` needs app-launch details or a startup handoff path, build that in this phase and funnel it through the same pending post-target store.
- [ ] Decide the initial tap target for a post notification in this phase: open the Posts tab and scroll to the post, not a conversation route.

### Database

- [ ] Bump the database version in `lib/main.dart`.
- [ ] Add a new migration file such as `lib/core/database/migrations/027_posts_core.dart`.
- [ ] Register the migration in `lib/main.dart`.
- [ ] Add helper files for the new tables, for example:
  - `lib/core/database/helpers/posts_db_helpers.dart`
  - `lib/core/database/helpers/post_recipients_db_helpers.dart`
- [ ] Start with the minimum core schema:
  - `posts`
  - `post_recipients`
  - `post_feed_state` or equivalent local state for hide/read/delivery bookkeeping
- [ ] Make `post_recipients` concrete enough for app-owned fanout and retry visibility:
  - recipient peer id
  - delivery status
  - last attempt timestamp
  - delivery path or ack state where relevant
  - last error or retry bookkeeping
- [ ] Keep post storage separate from `messages` and `media_attachments`. The existing conversation tables are optimized for thread chat, not broadcast posts.

### Domain and application

- [ ] Add a new feature module under `lib/features/posts/`.
- [ ] Create domain models for post identity, author, audience, expiry, and receiver scope, for example:
  - `lib/features/posts/domain/models/post_model.dart`
  - `lib/features/posts/domain/models/post_audience.dart`
- [ ] Add repository interfaces and implementations:
  - `lib/features/posts/domain/repositories/post_repository.dart`
  - `lib/features/posts/domain/repositories/post_repository_impl.dart`
- [ ] Add core use cases:
  - `lib/features/posts/application/send_post_use_case.dart`
  - `lib/features/posts/application/load_posts_feed_use_case.dart`
  - `lib/features/posts/application/handle_incoming_post_use_case.dart`
- [ ] Add a listener similar to the existing message listeners:
  - `lib/features/posts/application/post_listener.dart`
- [ ] Make `send_post_use_case.dart` own per-recipient fanout semantics instead of assuming a transport broadcast:
  - build the eligible recipient set first
  - exclude blocked and archived contacts from `All Friends`, `Pick People`, and later nearby qualification
  - encrypt or serialize per recipient using the approved Phase 0 contract
  - persist partial-recipient results without rolling back successful deliveries
  - keep retry bookkeeping restart-safe through `post_recipients`
- [ ] Make `post_listener.dart` enforce the sender-side contact rules on receive:
  - reject blocked direct-contact senders before persistence
  - suppress notifications for archived direct contacts while still allowing the repo policy above

### App wiring

- [ ] In `lib/main.dart`, construct the Posts repository and listener beside the existing conversation, reaction, group, and introduction wiring.
- [ ] Start the Posts listener from the same app lifecycle point where the other listeners are started.
- [ ] Keep the listener ordering simple: router first, then typed listeners.
- [ ] Add a shell-level tab and target owner under `lib/features/feed/` instead of letting `FeedWired`, `SettingsWired`, and notification handlers switch tabs ad hoc:
  - one source of truth for `activeTab`
  - initial tab selection on app boot
  - pending post-target handoff after notification opens
  - tab changes returned from Settings or sibling surfaces
- [ ] Thread Posts dependencies through the concrete app-shell constructors that currently carry typed repos and listeners:
  - `MyApp` in `lib/main.dart`
  - `lib/features/identity/presentation/startup_router.dart`
  - `FirstTimeExperienceWired` call sites inside `StartupRouter`
  - `_buildPendingShareRoute` in `StartupRouter`
  - `_buildSharePickerRoute` in `lib/main.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/qr_code/presentation/screens/qr_scanner_wired.dart`
- [ ] If Posts or nearby replay hooks are added to `lib/core/lifecycle/handle_app_resumed.dart`, change its named-parameter signature and all call sites together. Do not tack on hidden global lookups.
- [ ] Add Posts teardown to `_MyAppState.dispose()` in `lib/main.dart`.
- [ ] Extend `IncomingMessageRouter.dispose()` so every new post-related `StreamController` is closed there too.

### UI

- [ ] Add a Posts feature surface:
  - `lib/features/posts/presentation/screens/posts_screen.dart`
  - `lib/features/posts/presentation/screens/posts_wired.dart`
  - `lib/features/posts/presentation/widgets/post_card.dart`
  - `lib/features/posts/presentation/widgets/compose_post_sheet.dart`
- [ ] Host the composer as a Posts-owned sheet or route. Do not model it on `lib/features/conversation/presentation/screens/conversation_wired.dart`, because chat compose is inline rather than a bottom sheet.
- [ ] Use `lib/features/groups/presentation/screens/contact_picker_wired.dart` as the closest existing analogue for `Pick People`, then adapt it for active direct-contact multi-select. Do not reuse `share_target_picker_wired.dart`, which is for OS share intents.
- [ ] Make the `Pick People` selector explicitly exclude blocked and archived contacts. Do not rely on whichever helper happens to power the first implementation.
- [ ] Add Posts to `lib/features/feed/presentation/widgets/feed_navigation_bar.dart`.
- [ ] Add a real Posts nav asset such as `assets/icons/nav_posts.svg` before wiring the tab. The nav bar is SVG-asset backed today.
- [ ] Replace scattered bare tab strings with a shared tab-id constant or equivalent typed source of truth before adding `posts`.
- [ ] Update any surfaces that embed the nav bar and tab state:
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/qr_code/presentation/screens/qr_scanner_wired.dart`
  - `lib/features/settings/presentation/screens/settings_wired.dart`
  - `lib/features/settings/presentation/screens/settings_screen.dart`
- [ ] Update the route handoff sites that need to reopen or seed the app shell with the correct active tab:
  - `lib/features/identity/presentation/startup_router.dart`
  - `FirstTimeExperienceWired` builders in `StartupRouter`
  - `_buildPendingShareRoute` in `StartupRouter`
  - `_buildSharePickerRoute` in `lib/main.dart`
- [ ] Posts is the new fourth tab beside Feed, Remember, and Orbit in Phase 1. Do not rename Feed or move the conversation list as part of this rollout, and do not leave tab ownership implicit inside `FeedWired`.
- [ ] Phase 1 post-card minimum design coverage:
  - direct-friend card
  - `Pick People` scoped card
  - empty/caught-up state
  - compose sheet
  - basic feed time-grouping
  - post-confirmation copy for `All Friends` and `Pick People`

### Tests and exit gate

- [ ] Start RED with targeted failing tests for:
  - `post_create` routing and payload parsing
  - the `027_posts_core` migration and DB helpers
  - `send_post`, `load_posts_feed`, and `handle_incoming_post`
  - `PostsWired`, compose-sheet, shell-tab ownership, and empty or caught-up widget states
- [ ] If Phase 1 needs new fakes, add the in-memory Posts repository fake first so routing and use-case tests can start RED without SQLite.
- [ ] Add router tests for `post_create`.
- [ ] Add repository and migration tests for the new core tables.
- [ ] Add integration-with-fakes coverage that proves live delivery and offline inbox replay converge into the same local repository path.
- [ ] Add integration-with-fakes coverage that proves per-recipient partial failure is persisted correctly:
  - one recipient succeeds while another falls back to inbox
  - restart preserves retry-visible status
  - successful recipients are not rolled back by later failures
- [ ] Add a 2-device smoke flow: create post on device A, receive live on device B, then repeat with B offline and verify inbox replay on resume.
- [ ] Add a push-wake smoke check: simulated remote wake-up triggers inbox drain and the post lands in the same local repository path as a live delivery.
- [ ] Add notification tests that cover the explicit `post_create` fallback path in `background_push_notification_fallback.dart`.
- [ ] Add notification-open tests for the shared pending post-target flow:
  - local notification tap
  - `onMessageOpenedApp`
  - `getInitialMessage`
  - Android terminated launch from a local fallback notification
  - all four must wait for repo-observed local ingest or timeout fallback, then land on the Posts tab with the target post focused
- [ ] Add sender-policy tests:
  - blocked senders are rejected before persistence
  - archived senders suppress notifications
  - pickers exclude blocked and archived contacts
- [ ] Add a repeatable simulator or CLI-backed Phase 1 smoke command under `integration_test/` or `integration_test/scripts/`.
- [ ] Exit only when the Posts tab works without any debug-only shortcuts.

### Required Acceptance Commands

- [ ] If any referenced test directory, file, or smoke script does not exist at phase start, creating it is part of this phase deliverables.
- [ ] `flutter test test/features/posts/phase1`
- [ ] `flutter test test/core/services/incoming_message_router_posts_test.dart`
- [ ] `flutter test integration_test/posts_phase1_fake_test.dart`
- [ ] `bash integration_test/scripts/posts_phase1_smoke.sh`

## Phase 2: Comments, Reactions, Media, and Expiry

Outcome: posts behave like a real feed item, not just a one-shot text broadcast, and normal posts age out according to the spec.

### Internal Slices

- Slice 1: comments base path, generic orphan child-event staging, reconciliation, and comment-sheet rendering.
  Prerequisite harnesses: fake Posts engagement listener harness plus orphan-event fixture builder.
  RED tests first: orphan comment event staging when parent post is missing, staged comment reconciliation after parent post ingest, comment persistence helpers, comment-sheet widget states.
  Allowed edit zone: `lib/core/database/migrations/028_posts_engagement.dart`, `lib/core/database/helpers/post_comments_*`, new orphan-event helpers, `lib/features/posts/application/handle_incoming_post_use_case.dart`, `lib/features/posts/application/send_post_comment_use_case.dart`, `lib/features/posts/presentation/widgets/comments_sheet.dart`.
  Mini exit gate: comments persist, replay, and render under one post without media, and orphan child events are staged instead of dropped.
- Slice 2: heart-only reactions on posts and comments.
  Prerequisite harnesses: fake Posts engagement listener harness plus recipient-set fixture builder.
  RED tests first: post-heart idempotency, comment-heart idempotency, reaction fanout against the persisted recipient set, engagement listener update streams.
  Allowed edit zone: `lib/features/posts/application/post_*reaction*`, `lib/features/posts/domain/**`, engagement listeners, reaction-related DB helpers, router tests.
  Mini exit gate: repeated deliveries are idempotent and heart state stays consistent after restart.
- Slice 3: media attach, upload, receive hydration, and restart restore.
  Prerequisite harnesses: fake media upload or download adapter with `allowedPeers` inspection and attachment hydration fixture.
  RED tests first: post-media upload metadata, `allowedPeers` built from the persisted recipient set, receive hydration from pending to local-path-ready, restart restore of hydrated cards, quality-preference-aware media processing.
  Allowed edit zone: `lib/features/posts/application/attach_post_media_use_case.dart`, post-media helpers or repos, extracted shared media wrappers, `lib/core/media/**` wrappers touched for Posts reuse, `lib/features/settings/application/image_quality_preference_use_cases.dart` consumers in Posts compose, integration fixtures.
  Mini exit gate: image, video, and voice posts hydrate into renderable local cards after replay and restart.
- Slice 4: expiry lifecycle plus engagement-triggered extension.
  Prerequisite harnesses: fake clock or time provider.
  RED tests first: fake-clock countdown states, comment-triggered expiry extension, expired-post sweep, cleanup of expired attachment metadata and files.
  Allowed edit zone: posts lifecycle helpers, expiry columns or repos, countdown widgets, cleanup use cases, fake clock harnesses.
  Mini exit gate: countdown, comment-triggered expiry reset, and expired cleanup all agree on the same stored timestamps.

### Prerequisite Harnesses

- [ ] Fake Posts engagement listener harness.
- [ ] Fake media upload or download adapter with `allowedPeers` inspection.
- [ ] Attachment hydration fixture with pending and hydrated attachment states.
- [ ] Fake clock or time provider for expiry tests.

### Scope Boundaries

- Inspect first:
  - `lib/features/conversation/application/reaction_listener.dart`
  - `lib/features/conversation/application/send_reaction_use_case.dart`
  - `lib/features/conversation/application/chat_message_listener.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/conversation/application/upload_media_use_case.dart`
  - `lib/core/media/media_file_manager.dart`
  - `lib/features/settings/application/image_quality_preference_use_cases.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
- Primary edit zone:
  - `lib/features/posts/**`
  - shared media wrappers or extracted helpers needed for Posts reuse
  - `lib/main.dart`
  - `lib/core/services/incoming_message_router.dart`
- Avoid unless required:
  - existing chat or group UI behavior outside shared-extraction work
  - relay or Go upload transport
  - unrelated settings or onboarding surfaces

### Agent Skills

- Primary: `$flutter-feature-module-implementer`
- Also use: `$flutter-sqlite-migrations-and-repositories`, `$flutter-test-orchestrator`
- Use `$senior-ui-ux-designer` only if comments, media rendering, or compose interaction quality needs a deliberate refinement pass.

### Transport and routing

- [ ] Extend `lib/core/services/incoming_message_router.dart` with typed streams for:
  - `post_comment`
  - `post_reaction`
  - `post_comment_reaction`
- [ ] Keep the transport path app-layer only. Still no new Go bridge command unless attachments expose a real limitation.

### Database

- [ ] Bump the database version in `lib/main.dart` and register the Phase 2 migration there.
- [ ] Add a migration such as `lib/core/database/migrations/028_posts_engagement.dart`.
- [ ] Add helper files for:
  - `lib/core/database/helpers/post_comments_db_helpers.dart`
  - `lib/core/database/helpers/post_reactions_db_helpers.dart`
  - `lib/core/database/helpers/post_comment_reactions_db_helpers.dart`
  - `lib/core/database/helpers/post_media_db_helpers.dart`
  - `lib/core/database/helpers/post_pending_child_events_db_helpers.dart`
- [ ] Add tables for:
  - `post_comments`
  - `post_reactions`
  - `post_comment_reactions`
  - `post_media_attachments`
  - `post_pending_child_events`
- [ ] Extend the `posts` schema or companion helpers for expiry bookkeeping:
  - `expires_at`
  - `last_engagement_at`
  - local cleanup bookkeeping for expired rows and attached media
- [ ] Store post media separately from conversation media. Do not overload `message_id` semantics from `lib/core/database/helpers/media_attachments_db_helpers.dart`.
- [ ] Keep the post-media schema field-compatible with conversation attachments for audio and video metadata:
  - `mime`
  - `size`
  - `media_type`
  - `duration_ms`
  - `local_path`
  - `download_status`
  - `waveform`

### Domain and application

- [ ] Add models and repos for comments, comment counts, heart-only reactions, comment-heart state, post media, and expiry lifecycle.
- [ ] Implement one generic orphan child-event staging path in this phase and reuse it later for pin events instead of creating phase-specific staging logic:
  - stage child envelopes keyed by `post_id`, `event_type`, and `event_id`
  - reconcile staged rows immediately after a parent post is ingested
  - delete or mark staged rows as consumed after successful reconciliation
- [ ] Add a typed Posts engagement listener layer instead of treating router streams as the final ingress step:
  - `post_comment_listener.dart`
  - `post_reaction_listener.dart`
  - or a combined `post_engagement_listener.dart`
- [ ] Make the engagement listener do the same class of work the current chat and reaction listeners do:
  - validate sender and trust context
  - persist to repos
  - emit typed UI updates
  - trigger notification decisions where needed
- [ ] Add use cases:
  - `send_post_comment_use_case.dart`
  - `send_post_reaction_use_case.dart`
  - `send_post_comment_reaction_use_case.dart`
  - `load_post_comments_use_case.dart`
  - `attach_post_media_use_case.dart`
  - `stage_orphan_post_child_event_use_case.dart`
  - `reconcile_pending_post_child_events_use_case.dart`
- [ ] Add expiry lifecycle use cases:
  - reset or extend expiry when a new comment lands
  - sweep expired posts and their local attachments
  - load feed items with the current countdown state
- [ ] Keep post reactions heart-only in v1, including comment hearts. Do not mirror the conversation emoji-reaction system.
- [ ] Lock the multi-recipient engagement rule now:
  - persist the canonical recipient set for each post at creation time
  - reuse that stored set for comment and reaction fanout instead of recomputing audience later
  - include the original author in engagement delivery even when the audience is otherwise stored as recipients
  - use the same recipient set to build media `allowedPeers` for post attachments and later engagement blobs
- [ ] Keep voice as part of generic post-media handling. Do not add a separate `send_post_voice_use_case.dart` unless Posts later needs behavior that truly diverges from the existing media pipeline.
- [ ] Do not call `lib/features/conversation/application/send_voice_message_use_case.dart` directly from Posts. It is conversation-specific. Reuse its lower-level pieces and orchestration pattern instead of cloning its logic.
- [ ] Do not call `lib/features/conversation/application/upload_media_use_case.dart` as-is with a fake recipient peer id. Extract or wrap the shared upload logic so Posts can upload once and fan out with post-specific allowlists instead of 1:1 recipient semantics.
- [ ] Extend `lib/core/media/media_file_manager.dart` or add a sibling helper so post media uses a post-scoped path scheme. Do not store Posts attachments under `media/<contactPeerId>/...`.
- [ ] Reuse existing media infrastructure where it already works:
  - `lib/core/media/image_processor.dart`
  - `lib/core/media/media_picker.dart`
  - `lib/core/media/media_file_manager.dart`
  - `lib/core/media/amplitude_buffer.dart`
  - `lib/core/media/normalize_amplitude.dart`
  - `lib/core/media/audio_recorder_service.dart`
  - `lib/core/media/record_audio_recorder_service.dart`
  - `lib/core/media/downsample_waveform.dart`
  - `lib/features/conversation/application/upload_media_use_case.dart`
  - `lib/features/conversation/domain/models/audio_recording.dart`
  - `lib/features/conversation/domain/models/media_attachment.dart`
  - `lib/features/conversation/presentation/widgets/recording_overlay.dart`
  - `lib/shared/widgets/media/audio_player_widget.dart`
  - `lib/shared/widgets/media/*`
- [ ] Honor the app's existing media quality preferences in Posts compose:
  - load image and video quality from `image_quality_preference_use_cases.dart`
  - pass those preferences through the same processing path used by current media compose flows
  - do not invent Posts-only image or video quality settings in v1
- [ ] If `RecordingOverlay` is reused directly, extract or move the shared recorder chrome out of `lib/features/conversation/` first. Do not create a long-term cross-feature import from Posts into a conversation-only presentation folder.
- [ ] Fix the existing `AudioRecorderService.start()` signature mismatch before routing Posts recording through the interface, but lock behavior instead of just types:
  - preserve the current default-path fallback behavior used by the production recorder when the caller does not provide a meaningful path
  - update the interface, implementation, fakes, and tests together so Posts and existing chat or group recording flows stay consistent

### App wiring

- [ ] Construct and start the Posts engagement listener(s) in `lib/main.dart` beside the current chat, reaction, and group listeners.
- [ ] Dispose of the new engagement listener(s) in `_MyAppState.dispose()`.
- [ ] Treat router streams as the first hop only. Posts comments and reactions should reach the UI through the typed engagement listener layer, not directly from `IncomingMessageRouter`.

### Notifications and lifecycle

- [ ] Add notification handling for the original poster when new `post_comment` or `post_reaction` events arrive, and route taps into the relevant post or comments surface instead of a conversation thread.
- [ ] Run the expired-post sweep from a predictable lifecycle point such as app startup, app resume, and feed open so auto-delete behavior does not depend on a background job that v1 does not have.
- [ ] Lock a post-media hydration policy now instead of leaving receive behavior implicit:
  - v1 should auto-download received post attachments after ingest or replay, mirroring chat and group media handling
  - persist hydrated local paths so restart restores renderable cards
  - re-emit updated post models after hydration so feed widgets refresh without a full reload

### UI

- [ ] Add a comments sheet under `lib/features/posts/presentation/widgets/comments_sheet.dart`.
- [ ] Add post-specific media layout widgets only where the Posts card chrome differs. Do not fork shared media playback just to restyle it.
- [ ] Reuse shared media viewers where possible instead of duplicating image and video presentation logic.
- [ ] Cover the spec's image-post variant:
  - multi-image carousel
  - horizontal swipe navigation inside the card, matching the reference interaction in the `Noor` post from the `30-posts` mock
  - dot indicators
  - current-image counter badge
- [ ] Cover the spec's video-post variant:
  - thumbnail
  - play overlay
  - duration badge
  - inline progress state
- [ ] Reuse `lib/shared/widgets/media/audio_player_widget.dart` for voice-post playback. If Posts needs different padding or framing, wrap it rather than cloning it.
- [ ] Make the compose attachment entry points match the current product contract:
  - `Media` opens image/video picking
  - `Voice` enters inline voice-note recording in the compose sheet
- [ ] Reuse the current voice-note pipeline for capture:
  - `AudioRecorderService` / `RecordAudioRecorderService` for recording
  - `RecordingOverlay` as the base inline recording state
  - `downsample_waveform.dart` for waveform persistence
- [ ] It is acceptable for Posts to use a different entry gesture than 1:1 chat. Reuse the recorder stack even if Posts starts recording from a dedicated `Voice` attachment button instead of the chat mic's long-press affordance.
- [ ] After stopping a recording, show the voice clip as an attached draft preview in compose before posting. Do not send immediately on record stop unless the product contract changes.
- [ ] Update the compose sheet to support attachments while staying within the spec's "one media type per post" rule.
- [ ] Keep Posts media attach behavior aligned with existing Settings-driven quality behavior for both image and video processing.
- [ ] Add heart-only reactions on comments inside the comments sheet.
- [ ] Render the expiry footer and countdown state on cards, and update it when comments extend the post lifetime.

### Tests and exit gate

- [ ] Start RED with targeted failing tests for:
  - `post_comment`, `post_reaction`, and `post_comment_reaction` payload parsing
  - comment, reaction, comment-heart, expiry, and post-media persistence helpers and repos
  - `send_post_comment`, `send_post_reaction`, `send_post_comment_reaction`, expiry lifecycle, `load_post_comments`, and media-attach use cases
  - comments-sheet, image-carousel, video-card, expiry-footer, and compose-attachment widget states
- [ ] Add payload parsing tests for `post_comment`, `post_reaction`, and `post_comment_reaction`.
- [ ] Add staging tests for orphan child events:
  - missing-parent comment stages instead of dropping
  - missing-parent reaction stages instead of dropping
  - parent post ingest reconciles and clears staged rows
- [ ] Add DB tests that verify comment insertion resets expiry bookkeeping and expired posts clean up attached media rows.
- [ ] Add integration-with-fakes coverage for comment replay after offline drain, reaction idempotency, comment-heart idempotency, expiry sweep, notification routing, and media metadata restore after restart.
- [ ] Add integration tests that prove the persisted post recipient set is reused for:
  - comment fanout
  - reaction fanout
  - media `allowedPeers`
- [ ] Add media-processing tests that prove Posts uses the stored image and video quality preferences instead of hard-coded compression defaults.
- [ ] Add 2-device tests for image, video, and voice post delivery, comment replay after offline inbox drain, comment-heart behavior, reaction idempotency, and hydrated media restore after restart.
- [ ] Add a repeatable simulator or CLI-backed media-post smoke command that covers image, video, and voice flows.
- [ ] Exit only when media posts, comment hearts, and expiry lifecycle all behave correctly after restart and replay.

### Required Acceptance Commands

- [ ] If any referenced test directory, file, or smoke script does not exist at phase start, creating it is part of this phase deliverables.
- [ ] `flutter test test/features/posts/phase2`
- [ ] `flutter test test/core/services/incoming_message_router_posts_engagement_test.dart`
- [ ] `flutter test integration_test/posts_phase2_fake_test.dart`
- [ ] `bash integration_test/scripts/posts_phase2_smoke.sh`

## Phase 3: People Nearby and Privacy

Outcome: nearby-scoped posts work with real location privacy rules instead of a UI-only radius selector.

### Internal Slices

- Slice 1: DB-backed nearby privacy state plus Settings controls.
  Prerequisite harnesses: fake nearby-settings repository fixture plus widget harness for Settings and compose availability.
  RED tests first: DB-backed nearby-sharing state reads and writes, Settings toggles through the repository, compose availability reflects the stored state without a second preference source.
  Allowed edit zone: nearby DB helpers or repos, `lib/features/settings/**`, `lib/features/posts/domain/posts_privacy_settings.dart`, related widget tests.
  Mini exit gate: one stored source of truth drives compose availability and Settings state.
- Slice 2: local location service, permission flow, and silent lifecycle refresh rules.
  Prerequisite harnesses: fake location service, fake permission-state adapter, lifecycle harness for startup and resume without prompts.
  RED tests first: startup or resume refresh never prompts, compose or Settings-triggered refresh may prompt, denied and denied-forever transitions behave correctly.
  Allowed edit zone: `lib/features/posts/application/nearby_location_service.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, startup hooks, Android manifest or iOS plist changes, permission harnesses.
  Mini exit gate: startup and resume refresh do not prompt, while compose and Settings can.
- Slice 3: nearby presence ingest and friend-snapshot persistence.
  Prerequisite harnesses: fake permission-state adapter plus nearby presence event fixture builder.
  RED tests first: `post_presence_update` validation, direct-friend snapshot persistence, immediate invalidation when sharing is disabled or services are lost.
  Allowed edit zone: nearby-presence listener, router, nearby DB helpers, `lib/main.dart` listener wiring, presence integration tests.
  Mini exit gate: direct-friend presence updates persist and invalidation happens immediately on sharing or permission loss.
- Slice 4: sender qualification, recipient persistence, distance labels, and replay safety.
  Prerequisite harnesses: fake location service, fake clock or freshness builder, replay fixture builder.
  RED tests first: radius qualification, blocked or archived contact exclusion, persisted recipient locking, distance label rendering from stored snapshots, offline replay without requalification.
  Allowed edit zone: nearby eligibility service or use cases, posts repositories, nearby UI widgets, replay tests.
  Mini exit gate: recipients are locked at send time and replay never recomputes eligibility.

### Prerequisite Harnesses

- [ ] Fake location service with deterministic coordinates.
- [ ] Fake permission-state adapter covering granted, denied, denied forever, and services-off.
- [ ] Fake clock or freshness builder.
- [ ] Lifecycle harness for startup and resume without prompts.

### Scope Boundaries

- Inspect first:
  - `lib/core/lifecycle/handle_app_resumed.dart`
  - `lib/features/identity/presentation/startup_router.dart`
  - `lib/features/contacts/domain/models/contact_model.dart`
  - `lib/features/settings/presentation/screens/settings_wired.dart`
  - `lib/features/settings/presentation/screens/settings_screen.dart`
  - secure-storage preference helpers under `lib/features/settings/application/`
- Primary edit zone:
  - `lib/features/posts/**`
  - settings files needed for nearby controls
  - `lib/main.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
  - `lib/core/services/incoming_message_router.dart`
- Avoid unless required:
  - conversation/contact persistence unrelated to nearby
  - general preference helpers for non-Posts settings
  - Go bridge or native location code beyond manifest or plist changes

### Agent Skills

- Primary: `$mobile-location-privacy-and-eligibility`
- Also use: `$flutter-feature-module-implementer`, `$flutter-sqlite-migrations-and-repositories`, `$flutter-test-orchestrator`
- Use `$mobile-notification-routing-and-deep-linking` only if nearby/privacy changes require new notification payloads or tap targets.

Why this is a real phase: `lib/features/contacts/domain/models/contact_model.dart` exists, but it currently has no location fields or nearby-presence model, there are no settings controls for location/privacy, and there is no persistence layer for proximity eligibility. This is not just a filter on the receiver's feed.

### Product and data model

- [ ] These Phase 3 implementation details are not self-authorizing. Phase 0 must reconcile the nearby/privacy contract in the product spec and contract artifacts before `post_presence_update` is approved.
- [ ] Lock the Phase 3 implementation contract before coding:
  - use `geolocator` in `pubspec.yaml` for foreground location access and distance calculation in v1
  - do not add `permission_handler`; keep permission flow inside the location service layer
  - do not add background location, geofencing, or always-on tracking in v1
- [ ] Keep the audience rule as sender-side recipient selection using the freshest known friend locations.
- [ ] Nearby eligibility inherits the Phase 1 contact policy:
  - only active direct contacts may qualify
  - blocked contacts never qualify
  - archived contacts do not qualify for nearby fanout in v1
- [ ] Represent shared nearby presence as a rounded coordinate snapshot, not precise live tracking:
  - store and transmit `lat_e3` and `lng_e3` rounded to 3 decimal places
  - include `captured_at` and reported `accuracy_m`
  - use the same coarse snapshot for card distance labels and nearby eligibility
- [ ] Set the v1 freshness rule now: a nearby snapshot is fresh for 30 minutes, then becomes ineligible until refreshed.
- [ ] Set the v1 refresh cadence now:
  - refresh local nearby presence on app startup and app resume only when permission is already granted and location services are available
  - refresh when the Posts screen opens if the current snapshot is stale
  - refresh when the user selects `People Nearby` in compose and the snapshot is stale
  - do not run periodic background refresh jobs in v1
- [ ] Keep startup and resume refresh silent and non-interactive:
  - never trigger a location permission prompt from startup or resume recovery
  - only interactive Settings or compose actions may request permission
- [ ] Invalidate nearby presence immediately, not only by TTL:
  - when nearby sharing is turned off
  - when OS permission is revoked
  - when device location services are disabled
  - when the stored local snapshot is explicitly cleared
- [ ] Keep coarse location data out of `ContactModel` unless it becomes a first-class contact property. Prefer a Posts-specific nearby presence table.
- [ ] Persist recipient qualification results at send time so inbox replay does not re-run the nearby filter later with different location data.
- [ ] Persist the sender snapshot used for eligibility on the post record so later pass-along checks use the original nearby anchor, not a new location sample.

### Platform dependencies and permissions

- [ ] Add `geolocator` to `pubspec.yaml`.
- [ ] Add Android foreground location permissions in `android/app/src/main/AndroidManifest.xml`:
  - `ACCESS_COARSE_LOCATION`
  - `ACCESS_FINE_LOCATION`
- [ ] Add iOS foreground usage copy in `ios/Runner/Info.plist`:
  - `NSLocationWhenInUseUsageDescription`
- [ ] Keep the v1 permission flow explicit:
  - request location only when the user enables nearby sharing in Settings or chooses `People Nearby` in compose
  - if permission is denied, keep nearby posting disabled and explain why in UI
  - if permission is denied forever, show an `Open Settings` action instead of retrying blindly
- [ ] Keep nearby browsing passive in v1: users can still read already-delivered nearby posts without granting location, but they cannot publish new nearby posts or refresh nearby participation without permission.

### Database

- [ ] Bump the database version in `lib/main.dart` and register the Phase 3 migration there.
- [ ] Add a migration such as `lib/core/database/migrations/029_posts_nearby.dart`.
- [ ] Add helper files for nearby state, for example:
  - `lib/core/database/helpers/post_location_presence_db_helpers.dart`
  - `lib/core/database/helpers/post_privacy_state_db_helpers.dart`
- [ ] Add local tables for:
  - last known coarse friend location snapshot keyed by friend peer id
  - local user nearby sharing state
  - location freshness timestamp and last permission status
- [ ] Make the nearby schema concrete enough for replay-safe behavior:
  - friend snapshot rows store `peer_id`, `lat_e3`, `lng_e3`, `captured_at`, `accuracy_m`, and `updated_at`
  - local privacy state stores `sharing_enabled`, `permission_state`, `last_local_lat_e3`, `last_local_lng_e3`, and `last_local_captured_at`
  - `posts` or `post_recipients` stores the sender snapshot and radius metadata used at qualification time
- [ ] Treat the DB-backed nearby privacy state as the single source of truth for sharing enablement and freshness. Do not introduce a parallel SecureKeyStore boolean for nearby sharing.

### Domain and application

- [ ] Add nearby-specific models and repos under `lib/features/posts/`:
  - `contact_presence_snapshot.dart`
  - `posts_privacy_settings.dart`
  - `nearby_eligibility_service.dart`
- [ ] Add a wrapper over `geolocator` under `lib/features/posts/` instead of calling the plugin from widgets:
  - `nearby_location_service.dart`
- [ ] Add use cases for:
  - refreshing own coarse location
  - computing eligible recipients for a nearby post
  - expiring stale location snapshots
- [ ] Add a nearby-presence listener layer for `post_presence_update` envelopes instead of writing presence rows straight from the router:
  - validate and persist direct-friend snapshots
  - emit refresh signals for nearby eligibility consumers
- [ ] Hook resume behavior into `lib/core/lifecycle/handle_app_resumed.dart` so nearby state is refreshed when the app becomes active again.
- [ ] When nearby refresh is added to `handleAppResumed`, update its named-parameter signature and callers explicitly instead of reaching into nearby state through globals.
- [ ] Add a typed presence envelope for nearby participation, for example `post_presence_update`, and route it through `lib/core/services/incoming_message_router.dart`.
- [ ] Keep nearby presence fanout limited to direct friends only. Do not relay presence to friends-of-friends.

### App wiring

- [ ] Construct and start the nearby-presence listener in `lib/main.dart` beside the other typed listeners.
- [ ] Dispose of the nearby-presence listener in `_MyAppState.dispose()`.
- [ ] Make Settings read and write nearby-sharing state through the Posts nearby repository, not through a separate preference helper in secure storage.

### Settings and UI

- [ ] Add nearby/location controls to Settings:
  - `lib/features/settings/presentation/screens/settings_wired.dart`
  - `lib/features/settings/presentation/screens/settings_screen.dart`
  - new widgets such as `posts_nearby_settings_card.dart`
- [ ] Remove any feed-level privacy status panel from the Posts screen. Do not mirror nearby state persistently in feed chrome.
- [ ] Update the compose sheet to be the only contextual nearby status surface:
  - disable `People Nearby` posting when location sharing is off or stale
  - show inline nearby status and next-step actions in compose instead of a feed banner or panel
- [ ] Make the compose error states explicit:
  - permission missing
  - device location services off
  - nearby sharing off in Settings
  - nearby snapshot stale and refresh in progress
- [ ] Make the stale nearby CTA explicit in compose copy and interaction:
  - the blocked stale state should clearly tell the user `Refresh nearby before posting`
  - the primary next action in that state should be `Refresh nearby`
- [ ] Render nearby distance labels on eligible cards using the same stored coarse snapshot and distance calculation used for qualification.
- [ ] Keep the privacy copy concrete:
  - nearby uses approximate location only
  - nearby does not expose live maps or strangers
  - nearby sharing is with direct friends only
  - the feed itself does not need a persistent privacy summary

### Bridge and Go

- [ ] Keep `go-mknoon/bridge/bridge.go` and `go-mknoon/node/node.go` unchanged unless nearby delivery proves too slow with normal envelopes.
- [ ] If a later optimization is needed, add it only after measuring a real bottleneck. Do not front-load native complexity here.

### Tests and exit gate

- [ ] Start RED with targeted failing tests for:
  - fresh vs stale snapshot eligibility
  - rounded-coordinate distance decisions around the configured radius boundaries
  - permission missing, denied forever, and device-location-off states
  - Settings and compose-sheet UI state when nearby is unavailable or stale
- [ ] Add deterministic location-service and permission-state fakes before production code so Phase 3 can stay strict TDD.
- [ ] Add tests for stale vs fresh location eligibility.
- [ ] Add tests for rounded-coordinate distance eligibility around the 500m and 1km thresholds.
- [ ] Add tests for privacy-off behavior, immediate nearby invalidation, and app-resume refresh behavior.
- [ ] Add tests for permission denied and denied-forever UI behavior.
- [ ] Add tests that startup and resume refresh stay silent when permission is missing instead of prompting.
- [ ] Add integration-with-fakes coverage for nearby presence updates, stale-snapshot expiry, and replay-safe recipient qualification.
- [ ] Add a 2-device test where only friends inside the chosen radius receive the post.
- [ ] Add an offline replay test where a recipient who qualified at send time still receives the nearby post after coming back online, without recomputing eligibility on replay.
- [ ] Add a repeatable simulator smoke command for permission flow plus nearby send eligibility.
- [ ] Exit only when nearby posts are privacy-correct, not just visually labeled.

### Required Acceptance Commands

- [ ] If any referenced test directory, file, or smoke script does not exist at phase start, creating it is part of this phase deliverables.
- [ ] `flutter test test/features/posts/phase3`
- [ ] `flutter test test/core/services/incoming_message_router_posts_presence_test.dart`
- [ ] `flutter test integration_test/posts_phase3_fake_test.dart`
- [ ] `bash integration_test/scripts/posts_phase3_smoke.sh`

## Phase 4: Pass Along and Extended-Network Delivery

Outcome: a friend can explicitly pass a post along, and the receiver sees trustworthy attribution instead of system-driven stranger discovery.

### Internal Slices

- Slice 1: pass contract, original snapshot shape, and trust validation.
  Prerequisite harnesses: original-post snapshot fixture plus sender-mismatch fixture builder.
  RED tests first: invalid payload shape, transport sender mismatch rejection, unknown direct-contact passing friend rejection, original snapshot parsing.
  Allowed edit zone: pass models, pass payload schema tests, `handle_incoming_passed_post_use_case.dart`, router tests.
  Mini exit gate: invalid or mismatched pass envelopes are rejected before persistence.
- Slice 2: sender pass flow and explicit one-hop rule.
  Prerequisite harnesses: three-peer fake network builder plus eligible-post pass fixture.
  RED tests first: eligible post pass flow, blocked pass action for `Pick People`, one-hop rule enforcement, outgoing payload snapshot completeness.
  Allowed edit zone: pass send use case, Posts card pass action UI, pass-related repos, widget tests.
  Mini exit gate: only eligible posts can be passed and the payload contains the renderable original snapshot.
- Slice 3: receiver ingest, local dedupe, and feed rendering.
  Prerequisite harnesses: duplicate-delivery injector plus original-post snapshot fixture.
  RED tests first: duplicate pass deliveries merge by original post identity, stable attribution after merge, friend-of-friend render from the embedded original snapshot.
  Allowed edit zone: Posts feed loading or merge helpers, pass repos, dedupe logic, receiver widget tests, fake network duplication fixtures.
  Mini exit gate: duplicate pass deliveries merge into one local item with stable attribution.
- Slice 4: original-author share counts and related UI states.
  Prerequisite harnesses: share-count fixture builder.
  RED tests first: sender-only share count visibility, receiver non-visibility, persisted share-count updates after new pass events.
  Allowed edit zone: author-management widgets, pass repos, own-post models, widget tests.
  Mini exit gate: the original author sees share counts without exposing them as social proof to receivers.

### Prerequisite Harnesses

- [ ] Three-peer fake network builder.
- [ ] Duplicate-delivery injector for pass envelopes.
- [ ] Original-post snapshot fixture for receiver rendering tests.

### Scope Boundaries

- Inspect first:
  - `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - `lib/features/feed/application/load_feed_use_case.dart`
  - `lib/features/feed/application/feed_store.dart`
  - `lib/features/contacts/domain/models/contact_model.dart`
- Primary edit zone:
  - `lib/features/posts/**`
  - `lib/core/services/incoming_message_router.dart`
  - `lib/main.dart`
  - feed-loading code touched only if Posts snapshots need explicit merge points
- Avoid unless required:
  - existing contact or introduction rules outside trust validation parallels
  - group chat reconstruction logic
  - Go or bridge transport framing

### Agent Skills

- Primary: `$flutter-feature-module-implementer`
- Also use: `$flutter-sqlite-migrations-and-repositories`, `$flutter-test-orchestrator`
- Use `$senior-ui-ux-designer` only if pass-along attribution, scope badges, or trust-chain readability need focused refinement.

### Transport and routing

- [ ] Extend `lib/core/services/incoming_message_router.dart` with `post_pass`.
- [ ] Keep pass-along as a regular message envelope sent through the same P2P and inbox path.

### Database

- [ ] Bump the database version in `lib/main.dart` and register the Phase 4 migration there.
- [ ] Add a migration such as `lib/core/database/migrations/030_posts_pass_along.dart`.
- [ ] Add helper files for:
  - `lib/core/database/helpers/post_passes_db_helpers.dart`
  - `lib/core/database/helpers/post_origin_db_helpers.dart`
- [ ] Persist enough metadata to render:
  - a fully renderable original-post snapshot
  - original author
  - pass-along actor
  - original audience scope
  - original nearby radius if applicable

### Domain and application

- [ ] Add models for pass-along attribution and origin chain.
- [ ] Add use cases:
  - `pass_post_along_use_case.dart`
  - `handle_incoming_passed_post_use_case.dart`
- [ ] Before Phase 4 coding starts, lock the pass-along engagement model in the approved Phase 0 contract artifacts:
  - whether pass recipients can comment and heart
  - who receives those engagement events
  - whether those events reset the original post expiry
  - whether pass-along expands the post's effective engagement recipient set or uses a narrower author or passer-scoped rule
- [ ] Enforce spec rules in application code, not UI only:
  - pass-along is a single extra hop in v1
  - transport sender must match the passing friend in the payload
  - the passing friend must still be a known direct contact locally
  - `Pick People` posts cannot be passed along
  - nearby-scoped reshares keep the original radius anchor
- [ ] Keep the pass-along payload renderable without network reconstruction:
  - include the original post content snapshot needed to render the card locally
  - do not depend on fetching or inferring the original post later from a missing direct-contact thread
  - do not add mutual-friend badge metadata in v1
- [ ] Persist an anonymous sender-side share count for the original author's own cards. Receivers still only see attribution, not a social-proof badge.
- [ ] Lock the pass-along dedupe rule now:
  - dedupe repeated deliveries by original post identity, not by transport message id alone
  - do not create multiple feed cards for the same original post when duplicates or repeated pass deliveries arrive
  - if a duplicate pass arrives later, merge or ignore it without destabilizing the visible attribution line in v1

### UI

- [ ] Update post cards to show:
  - pass-along attribution
  - no mutual-friends badge on reshared posts
  - correct scope badge combinations
- [ ] Show the original poster's share count only on their own cards and management states.
- [ ] Hide or disable the pass-along action on `Pick People` posts in the Posts card widget.
- [ ] Ensure passed-along items render in the same feed ordering as direct posts.

### Bridge and Go

- [ ] No dedicated Go transport changes planned in this phase.
- [ ] If payload growth becomes a problem, measure it first in `go-mknoon/bridge/bridge_test.go` and `go-mknoon/integration/*` before changing native code.

### Tests and exit gate

- [ ] Start RED with targeted failing tests for:
  - pass-along rule enforcement in application code
  - origin-chain and attribution persistence
  - post-card and detail-state rendering for passed-along content, including sender-only share counts
- [ ] Add tests that prove `Pick People` posts cannot be reshared.
- [ ] Add tests that prove v1 pass-along stops after one explicit extra hop.
- [ ] Add tests that reject pass envelopes when the passing friend does not match `message.from` or is not a known direct contact.
- [ ] Add tests that prove nearby pass-along still respects the original radius.
- [ ] Add tests that duplicate pass deliveries merge into one local feed item instead of creating multiple cards.
- [ ] Add integration-with-fakes coverage for original author -> passing friend -> receiving friend-of-friend before running device smoke.
- [ ] Add 3-device integration coverage: original author, passing friend, receiving friend-of-friend.
- [ ] Add a repeatable simulator or CLI-backed 3-device pass-along smoke command.
- [ ] Exit only when the trust chain is visible and rules are enforced serverless.

### Required Acceptance Commands

- [ ] If any referenced test directory, file, or smoke script does not exist at phase start, creating it is part of this phase deliverables.
- [ ] `flutter test test/features/posts/phase4`
- [ ] `flutter test test/core/services/incoming_message_router_posts_pass_test.dart`
- [ ] `flutter test integration_test/posts_phase4_fake_test.dart`
- [ ] `bash integration_test/scripts/posts_phase4_smoke.sh`

## Phase 5: Pinned Posts and Lifecycle Controls

Outcome: standing offers behave correctly across normal feed, pinned section, dismissal, sender edits, and sender removal.

### Internal Slices

- Slice 1: pin router contract, schema, and persistence.
  Prerequisite harnesses: pin-event fixtures plus orphan child-event staging reuse fixture.
  RED tests first: pin-envelope routing and parsing, orphan pin-event staging before parent post exists, staged pin-event reconciliation after parent post ingest, pin dedupe rules.
  Allowed edit zone: `lib/core/services/incoming_message_router.dart`, pin DB helpers, orphan child-event staging reuse, router tests, pin fixture builders.
  Mini exit gate: `post_pin_update` and `post_pin_remove` route, persist, and dedupe correctly.
- Slice 2: sender pin, edit, and remove flows.
  Prerequisite harnesses: sender pin-event fixtures.
  RED tests first: sender pin creation, sender edit propagation, sender remove propagation, sender-side state transitions.
  Allowed edit zone: pin send or edit use cases, pin repositories, sender management widgets, related tests.
  Mini exit gate: sender-side actions update local state and outgoing envelopes consistently.
- Slice 3: receiver pinned section, dismiss, and restart restore.
  Prerequisite harnesses: local dismissal fixture and persistence builder.
  RED tests first: local-only dismiss persistence, restart restore for active pins and dismissals, normal-feed plus pinned-section consistency.
  Allowed edit zone: receiver pin widgets, pin repositories, restart tests, pinned-section builders.
  Mini exit gate: receiver dismiss is local-only and restart-safe.
- Slice 4: collapsed-header details, active-pins banner, and `Message [name]` action.
  Prerequisite harnesses: pinned-section widget harness with collapsed and expanded states.
  RED tests first: stacked-avatar header states, active-pins compose banner, `Message [name]` button behavior and visibility, overflow badge rendering.
  Allowed edit zone: Posts pinned widgets, compose widgets, widget tests only for pinned UI chrome.
  Mini exit gate: all pinned-specific UI states render from persisted state, not ad hoc widget logic.

### Prerequisite Harnesses

- [ ] Pin-event fixtures for `post_pin_update` and `post_pin_remove`.
- [ ] Local dismissal fixture and persistence builder.
- [ ] Pinned-section widget harness with collapsed and expanded states.

### Scope Boundaries

- Inspect first:
  - `lib/core/services/incoming_message_router.dart`
  - `test/core/services/incoming_message_router_test.dart`
  - current Posts widgets under `lib/features/posts/presentation/widgets/`
- Primary edit zone:
  - `lib/features/posts/**`
  - `lib/core/services/incoming_message_router.dart`
  - `lib/main.dart`
  - router tests and Posts widget tests
- Avoid unless required:
  - unrelated feed-thread card logic outside shared styling helpers
  - chat or group pin analogues if they are not shared
  - native transport layers

### Agent Skills

- Primary: `$flutter-feature-module-implementer`
- Also use: `$flutter-sqlite-migrations-and-repositories`, `$flutter-test-orchestrator`
- Use `$senior-ui-ux-designer` only if pinned-section hierarchy, management affordances, or dismissal clarity need a targeted polish pass.

### Transport and routing

- [ ] Extend `lib/core/services/incoming_message_router.dart` with:
  - `post_pin_update`
  - `post_pin_remove`
- [ ] Keep pin-update and pin-remove delivery on the same direct-send and inbox path as other Posts envelopes.

### Database

- [ ] Bump the database version in `lib/main.dart` and register the Phase 5 migration there.
- [ ] Add a migration such as `lib/core/database/migrations/031_posts_pins.dart`.
- [ ] Add helper files for:
  - `lib/core/database/helpers/post_pins_db_helpers.dart`
  - `lib/core/database/helpers/post_pin_dismissals_db_helpers.dart`
- [ ] Persist:
  - active pin state
  - sender pin updates/removals
  - local dismissals per receiver

### Domain and application

- [ ] Add use cases:
  - `pin_post_use_case.dart`
  - `remove_pin_use_case.dart`
  - `dismiss_pin_use_case.dart`
  - `edit_pinned_post_use_case.dart`
- [ ] V1 sender edits for active pinned posts reuse `post_pin_update` with full-snapshot replace semantics. Do not add a separate `post_edit` envelope in v1.
- [ ] Only the original post author may send `post_pin_update` or `post_pin_remove`.
- [ ] The sender-visible destructive action stays a single `Remove` action in v1, backed by one canonical `post_pin_remove.reason`.
- [ ] Add incoming handlers for `post_pin_update` and `post_pin_remove`.
- [ ] Reuse the generic orphan child-event staging path from Phase 2 for early-arriving pin events. Do not create a second pin-only staging store.
- [ ] Make sure a sender removal updates both the pinned section and the regular feed entry correctly.

### UI

- [ ] Add a pinned section and full-screen "see all" flow under `lib/features/posts/presentation/widgets/`.
- [ ] Match the collapsed pinned-header design from the spec:
  - stacked author avatars
  - `+N` overflow badge when needed
- [ ] Add sender-only management affordances for edit/remove.
- [ ] Add receiver-only dismiss behavior that stays local.
- [ ] Add the compact pinned-card action set, including `Message [name]` for direct contact follow-up from a pin.
- [ ] Add the compose-time active-pins banner and manage affordance when the author already has active pinned posts.
- [ ] Ensure pinned posts still appear in the normal feed for the initial 24-hour window.

### Tests and exit gate

- [ ] Start RED with targeted failing tests for:
  - `post_pin_update` and `post_pin_remove` routing and payload parsing
  - pin lifecycle state transitions and persistence
  - sender edit/remove propagation
  - pinned-section, stacked-avatar header, compose-banner, and local-dismiss widget states
- [ ] Add router tests for `post_pin_update` and `post_pin_remove`.
- [ ] Add staging tests for orphan pin events that arrive before the parent post.
- [ ] Add tests for local dismiss persistence.
- [ ] Add tests for sender edit/remove propagation.
- [ ] Add tests for the sender-only active-pins banner and `Message [name]` pinned-card action.
- [ ] Add integration-with-fakes coverage for sender edit/remove and receiver-only local dismiss interacting correctly.
- [ ] Add restart coverage: pinned posts and dismissals must survive app restart.
- [ ] Add a repeatable simulator or CLI-backed pinned-post lifecycle smoke command.
- [ ] Exit only when pinned posts behave as standing offers, not duplicated or orphaned records.

### Required Acceptance Commands

- [ ] If any referenced test directory, file, or smoke script does not exist at phase start, creating it is part of this phase deliverables.
- [ ] `flutter test test/features/posts/phase5`
- [ ] `flutter test test/core/services/incoming_message_router_posts_pins_test.dart`
- [ ] `flutter test integration_test/posts_phase5_fake_test.dart`
- [ ] `bash integration_test/scripts/posts_phase5_smoke.sh`

## Final Hardening Gate

Outcome: all phase deliverables, command matrices, and carry-forward items are consolidated into a repeatable regression gate that is strong enough for unattended execution and review.

### Internal Slices

- Slice 1: build missing test trees, smoke scripts, and regression harnesses referenced by earlier phases.
  Prerequisite harnesses: shared regression script wrapper plus empty end-to-end fixture builder.
  RED tests first: missing-path checks for phase command targets, failing smoke-script entrypoints, empty regression harness placeholders.
  Allowed edit zone: `test/features/posts/**`, `test/core/services/**`, `integration_test/**`, `integration_test/scripts/**`, supporting test-only builders or fixtures.
  Mini exit gate: every referenced phase command target exists on disk and fails for product reasons only, not because the file or script is missing.
- Slice 2: run and stabilize the full Posts regression matrix across routing, replay, notifications, media, nearby, pass-along, and pins.
  Prerequisite harnesses: aggregate Posts fake-network builder plus end-to-end fixture builder.
  RED tests first: full-sequence end-to-end regression, replay or dedupe regressions, notification-open regressions, restart-recovery regressions.
  Allowed edit zone: test harnesses and scripts first, then minimal bug-fix edits in `lib/features/posts/**`, `lib/main.dart`, feed shell-owner files, and router wiring if tests expose real regressions.
  Mini exit gate: the end-to-end Posts regression suite passes without phase-local skips or manual data surgery.
- Slice 3: finalize residual-risk ledger, explicit deferrals, and conditional native regression coverage.
  Prerequisite harnesses: residual-risk artifact template plus conditional native regression wrapper.
  RED tests first: conditional native regression commands if app-layer changes forced native edits, plus checks that residual-risk and deferral artifacts exist.
  Allowed edit zone: `UI-21-POST/**`, regression docs, Go tests only if native code changed, smoke scripts or CI wrappers for final command execution.
  Mini exit gate: residual risks, deferrals, and next-phase or post-launch prerequisites are written down, and native regression is either green or explicitly not applicable.

### Prerequisite Harnesses

- [ ] Aggregate Posts fake-network builder that can cover live, replay, duplicate delivery, and notification-open cases in one suite.
- [ ] Shared regression script wrapper for running the per-phase smoke scripts in sequence.
- [ ] End-to-end fixture builder that can seed posts, comments, nearby state, pass-along, and pins without manual setup.

### Scope Boundaries

- Inspect first:
  - `test/features/posts/**`
  - `test/core/services/**`
  - `integration_test/**`
  - `integration_test/scripts/**`
  - `UI-21-POST/**`
- Primary edit zone:
  - test trees, integration harnesses, smoke scripts, and regression docs
  - minimal production fixes only where the regression matrix exposes a real bug
- Avoid unless required:
  - broad feature refactors unrelated to failing regressions
  - Go or bridge changes unless app-layer verification proves a native regression is relevant

### Agent Skills

- Primary: `$flutter-test-orchestrator`
- Also use: `$mobile-notification-routing-and-deep-linking`
- Use `$mobile-network-resilience-qa` for simulator or device validation of replay, startup, resume, and notification-triggered catch-up.

- [ ] Add feature-level tests under `test/features/posts/`.
- [ ] Add router coverage for every post envelope in `test/core/services/`.
- [ ] Add migration regression coverage for every new DB version touched in `lib/main.dart`.
- [ ] Add at least one end-to-end integration flow under `integration_test/` for the full sequence:
  - create post
  - receive post
  - comment
  - pass along
  - pin
  - restart and recover state
- [ ] Add notification coverage for:
  - foreground local notification
  - background push fallback notification
  - tap-through into the Posts surface
- [ ] Add targeted Go-side regression tests only if native changes were actually made:
  - `go-mknoon/bridge/bridge_test.go`
  - `go-mknoon/integration/local_relay_harness_test.go`
  - additional `go-mknoon/integration/*` tests only when a native behavior changes
- [ ] Keep at least one repeatable CLI or simulator command per user-visible Posts smoke scenario and document those commands in the phase notes or PR.

### Required Acceptance Commands

- [ ] If any referenced test directory, file, or smoke script does not exist at hardening start, creating it is part of the hardening deliverables.
- [ ] `flutter test test/features/posts`
- [ ] `flutter test test/core/services`
- [ ] `flutter test integration_test/posts_full_regression_test.dart`
- [ ] `bash integration_test/scripts/posts_full_regression_smoke.sh`
- [ ] If native bridge or Go files changed in this phase: `if [ -d go-mknoon ]; then (cd go-mknoon && go test ./...); fi`

## Recommended Delivery Order

1. Phase 1
2. Phase 2
3. Phase 3
4. Phase 4
5. Phase 5

This order keeps the hardest ambiguity out of the first vertical slice. It gives you a real Posts feature quickly, then adds engagement, then privacy-sensitive nearby logic, then trust-mediated extended reach, and finally long-lived pin lifecycle.
