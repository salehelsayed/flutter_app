# 72 - Secure Frozen State For Dissolved Groups Session Breakdown

## Decomposition artifact

- Artifact path:
  `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups.md`
- Decomposition date:
  `2026-04-22`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Downstream execution path

- reuse the existing doc-scoped session plan when safe
- execute the session with `$implementation-execution-qa-orchestrator`
- close the session with `$implementation-closure-audit-orchestrator`
- persist the final program verdict in this breakdown artifact
- this is an implementation-committed gap-closure rollout: Sessions `1`
  through `4` remain code-and-test owned until the repo closes the frozen
  dissolved-group gaps truthfully

## Recommended plan count

- `5`

## Overall closure bar

Report `72` is closed only when the current dissolved-group contract becomes
fully trustworthy across authority, reaction state, feed surfaces, and local
cleanup instead of stopping at "messages no longer send":

- only a currently authorized admin can dissolve a group, including on live
  listener and offline replay paths
- a dissolved group is fully frozen for all members: no new sends, no new
  reactions, no stale callback bypasses, and no later replay that revives
  visible activity
- feed and inline group surfaces model dissolved groups as non-writable and
  non-reactable instead of preserving active-group affordances
- read-only history remains available until each user chooses whether to keep
  it or delete it locally
- the local delete choice for a dissolved group is explicit, truthful, and
  device-local rather than a hidden redefinition of group dissolve
- discussion-group and announcement-group members converge to the same
  post-dissolve frozen contract, including offline recovery paths
- the maintained group docs, matrix rows, and test inventory stop overstating
  the current dissolve closure bar once the repo owns the stricter frozen-state
  behavior

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups.md`
- `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-breakdown.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Current repo facts that govern the split:

- Report `62` already landed durable dissolved-group storage, authenticated
  `group_dissolved` listener handling, post-dissolve send blocking, rejoin
  skipping, and basic dissolved-state UI, so Report `72` should not reopen the
  schema or baseline dissolve publish path without new evidence.
- `dissolveGroup(...)` already blocks non-admin local callers, but the
  remaining trust gap is broader: dissolve authorization on live and replayed
  system events still needs to match a strict current-admin-only rule instead
  of looser creator-based or payload-sender-based assumptions.
- `drain_group_offline_inbox_use_case.dart` still forwards
  `payload['senderId']` into replay handling when present, so replayed system
  events can currently trust decrypted payload identity more than the outer
  transport sender.
- `sendGroupReaction(...)` and `removeGroupReaction(...)` still validate only
  group existence, message existence, and membership; neither checks
  `group.isDissolved`.
- `handleIncomingGroupReaction(...)` currently binds payload sender to
  transport sender, but it does not reject post-dissolve reaction adds/removes
  against the stored dissolved cutoff.
- `GroupThreadFeedItem.canWrite` models only announcement admin-vs-reader
  behavior, and `groupGroupMessagesIntoThreads(...)` does not thread dissolved
  state into the feed thread model.
- `GroupInfoScreen` and `GroupInfoWired` already expose dissolved status and
  hide active management controls, but they do not yet expose a user-facing
  local-delete-after-dissolve cleanup contract.
- `deleteGroupAndMessages(...)` already exists as a local primitive, but today
  it is not owned by a dissolved-group-facing UX contract that makes
  local-only cleanup explicit.

Source-of-truth conflicts that materially affected decomposition:

- Report `62` truthfully closed the first owned dissolve contract, but the
  current Report `72` shows that closure was narrower than the stricter frozen
  state now required across reactions, feed writeability, and cleanup UX. This
  rollout therefore reuses `62` as baseline evidence instead of treating it as
  final proof for every later surface.
- Stable matrix and audit docs already describe dissolve as covered, but the
  current code evidence still leaves open gaps around post-dissolve reactions,
  feed participation affordances, and local-only cleanup. Final closure must
  refresh those notes rather than accept the older wording as enough.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Tighten dissolve authority to current-admin-only across local, live, and replay paths` | `implementation-ready` | `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-1-plan.md` | none | `accepted` | `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-breakdown.md`, `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-1-plan.md` | Accepted on `2026-04-22`: live/replay `group_dissolved` now require a current admin member, replayed system events trust the outer sender over payload `senderId`, and the local use case stayed unchanged because the new former-creator regression proved the existing `myRole` guard was already sufficient. |
| `2` | `Freeze post-dissolve reactions across send, remove, receive, and group-conversation entry points` | `implementation-ready` | `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-2-plan.md` | `1` | `accepted` | `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-breakdown.md`, `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-2-plan.md` | Accepted on `2026-04-22`: send/remove reaction use cases now return a dedicated dissolved blocked result, incoming live/replayed reactions at or after the dissolve cutoff are ignored, discussion and announcement regressions prove the freeze contract, and `GroupConversationWired` now keeps active announcement readers reactive while removing stale reaction-entry affordances for dissolved groups. |
| `3` | `Propagate dissolved frozen-state truth into feed thread models and inline group surfaces` | `implementation-ready` | `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-3-plan.md` | `2` | `accepted` | `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-breakdown.md`, `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-3-plan.md` | Accepted on `2026-04-22`: feed group thread models now carry dissolved truth, active announcement readers stay read-only for compose while keeping reaction entry, dissolved feed cards and long-press overlays no longer imply participation, and stale optimistic feed reactions restore truthful state when dissolve races the callback. |
| `4` | `Ship a truthful local-delete-after-dissolve cleanup flow with device-backed proof` | `implementation-ready` | `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-4-plan.md` | `1`, `2`, `3` | `accepted` | `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-breakdown.md`, `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-4-plan.md` | Accepted on `2026-04-22`: Group Info now exposes explicit local-only dissolved cleanup, `deleteGroupAndMessages(...)` keeps that cleanup device-local without publishing `group:leave`, smoke coverage proves offline peers can keep or delete recovered dissolved history truthfully, and `integration_test/group_recovery_e2e_test.dart` provides the required device-backed Group Info acceptance proof. |
| `5` | `Refresh maintained dissolve docs and persist the final frozen-state verdict` | `closure-only` | `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-5-plan.md` | `1`, `2`, `3`, `4` | `accepted` | `Test-Flight-Improv/11-group-discussion-use-case-audit.md`, `Test-Flight-Improv/09-network-group-messaging.md`, `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`, `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-breakdown.md`, `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-5-plan.md` | Accepted on `2026-04-22`: the maintained audit, network, matrix, gate-definition, and inventory docs now describe the current-admin-only dissolve, reaction freeze, feed frozen-state, and local-only cleanup contract truthfully without widening frozen named gates. |

## Pipeline progress

- `2026-04-22`: Reusable doc-72 breakdown artifact created locally after the
  bounded decomposition fallback. Session `1` is the first runnable session.
- `2026-04-22`: Session `1` plan created at
  `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-1-plan.md`
  and accepted after landing the dissolve-specific listener auth tightening,
  replay system-event sender binding fix, and the new former-creator / replay
  spoof regressions. Verification passed with:
  - `flutter test test/features/groups/application/dissolve_group_use_case_test.dart`
  - `flutter test test/features/groups/application/group_message_listener_test.dart`
  - `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `./scripts/run_test_gates.sh groups`
- `2026-04-22`: Session `2` plan created at
  `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-2-plan.md`
  and accepted after landing dissolved reaction send/remove guards, incoming
  reaction dissolve-cutoff rejection, discussion-and-announcement reaction
  freeze regressions, and the dissolved/stale-callback reaction-entry hardening
  in `GroupConversationWired`. Verification passed with:
  - `flutter test test/features/groups/application/send_group_reaction_use_case_test.dart`
  - `flutter test test/features/groups/application/remove_group_reaction_use_case_test.dart`
  - `flutter test test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
  - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`
  - `flutter test test/features/groups/integration/group_reaction_roundtrip_test.dart`
  - `flutter test test/features/groups/integration/announcement_happy_path_test.dart`
  - `./scripts/run_test_gates.sh groups`
- `2026-04-22`: Session `2` follow-up correction kept announcement readers
  read-only for compose while preserving reaction entry in
  `GroupConversationWired`. Targeted verification passed with:
  - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`
- `2026-04-22`: Session `3` plan created at
  `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-3-plan.md`
  and accepted after threading `isDissolved` and `canReact` through feed group
  thread models, aligning feed banners and long-press overlays with the
  conversation frozen-state contract, restoring stale optimistic feed reaction
  state on `groupDissolved`, and repairing the Orbit badge fixture in
  `feed_wired_test.dart` so the suite stays truthful after `2026-04-22`.
  Verification passed with:
  - `flutter test test/features/feed/domain/models/feed_item_test.dart`
  - `flutter test test/features/feed/domain/utils/group_group_messages_into_threads_test.dart`
  - `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
  - `flutter test test/features/feed/application/load_feed_use_case_test.dart`
  - `flutter test test/features/feed/application/feed_projection_test.dart`
  - `./scripts/run_test_gates.sh feed`
- `2026-04-22`: Session `4` plan created at
  `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-4-plan.md`
  and accepted after landing the Group Info local-delete affordance,
  dissolved-only device-local cleanup wiring in
  `deleteGroupAndMessages(...)`, widget proof that cancel/confirm behavior
  stays truthful, the dissolved cleanup smoke extension, and the device-backed
  offline-recovery acceptance flow in `integration_test/group_recovery_e2e_test.dart`.
  Verification passed with:
  - `flutter test test/features/groups/application/delete_group_and_messages_use_case_test.dart`
  - `flutter test test/features/groups/presentation/group_info_screen_test.dart`
  - `flutter test test/features/groups/presentation/group_info_wired_test.dart`
  - `flutter test test/features/groups/integration/group_membership_smoke_test.dart`
  - `flutter test integration_test/group_recovery_e2e_test.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469`
  - `./scripts/run_test_gates.sh groups`
- `2026-04-22`: Session `5` plan created at
  `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-5-plan.md`
  and accepted after refreshing the maintained audit, network, matrix,
  gate-definition, and inventory docs to reflect the landed frozen-state
  contract without widening named gates. This was a doc-only closure pass, so
  it re-used the same-day accepted Session `3` and Session `4` evidence:
  - `./scripts/run_test_gates.sh feed`
  - `flutter test test/features/groups/application/delete_group_and_messages_use_case_test.dart`
  - `flutter test test/features/groups/presentation/group_info_screen_test.dart`
  - `flutter test test/features/groups/presentation/group_info_wired_test.dart`
  - `flutter test test/features/groups/integration/group_membership_smoke_test.dart`
  - `flutter test integration_test/group_recovery_e2e_test.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469`
  - `./scripts/run_test_gates.sh groups`

## Final program verdict

- Status:
  `closed`
- Last updated:
  `2026-04-22`
- Why:
  - Sessions `1` through `5` are accepted
  - current repo evidence now covers current-admin-only dissolve authority,
    post-dissolve reaction freeze, truthful frozen feed/group affordances, and
    explicit device-local cleanup after offline recovery
  - maintained docs and matrix rows now match the landed frozen-state
    contract without widening the frozen named gates

## Ordered session breakdown

### Session 1

- Title:
  `Tighten dissolve authority to current-admin-only across local, live, and replay paths`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-1-plan.md`
- Exact scope:
  - require dissolve authorization to hinge on current admin membership across
    the local use case, live `group_dissolved` listener handling, and replayed
    system events
  - reject the former-creator / former-admin dissolve case explicitly instead
    of relying on older creator-based trust assumptions
  - bind replayed dissolve and related system-event handling to the authenticated
    outer sender identity rather than a decrypted payload sender field whenever
    those sources can diverge
  - keep the already-landed durable dissolve state, timeline row, idempotent
    duplicate handling, send blocking, and rejoin skipping intact
- Why it is its own session:
  - this is the highest-risk trust seam in Report `72`, and it must close
    before later UI and cleanup work can be accepted as truthful
  - the affected code and tests already cluster around one authority/replay
    family, so splitting it smaller would create bookkeeping without giving a
    safer verified state
- Likely code-entry files:
  - `lib/features/groups/application/dissolve_group_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `test/features/groups/application/dissolve_group_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Likely direct tests/regressions:
  - `flutter test test/features/groups/application/dissolve_group_use_case_test.dart`
  - `flutter test test/features/groups/application/group_message_listener_test.dart`
  - `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `flutter test test/features/groups/integration/group_membership_smoke_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
- Matrix/closure docs to update when done:
  - refresh
    `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-breakdown.md`
  - defer stable doc and matrix note changes to Session `5`
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 2

- Title:
  `Freeze post-dissolve reactions across send, remove, receive, and group-conversation entry points`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-2-plan.md`
- Exact scope:
  - add dissolved-state guards to `sendGroupReaction(...)` and
    `removeGroupReaction(...)` so post-dissolve reaction mutation is rejected
    predictably instead of published optimistically
  - reject incoming live or replayed reaction add/remove payloads that occur at
    or after the dissolved cutoff instead of letting reaction state mutate
    after the group has ended
  - ensure `GroupConversationWired` and the shipped conversation UI do not
    leave stale reaction-entry callbacks active for dissolved groups while
    preserving non-mutating history and reaction inspection if that inspection
    already exists
  - prove the same blocked reaction contract for both discussion and
    announcement groups without reopening the broader reaction-inspection UX
- Why it is its own session:
  - the reaction pipeline is a separate application seam from dissolve
    authority and from feed projection, and it has its own direct regression
    family
  - closing reaction mutation first gives later feed and cleanup sessions one
    stable frozen-state contract to project outward
- Likely code-entry files:
  - `lib/features/groups/application/send_group_reaction_use_case.dart`
  - `lib/features/groups/application/remove_group_reaction_use_case.dart`
  - `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  - `test/features/groups/application/send_group_reaction_use_case_test.dart`
  - `test/features/groups/application/remove_group_reaction_use_case_test.dart`
  - `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/features/groups/integration/group_reaction_roundtrip_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/integration/announcement_happy_path_test.dart`
- Likely direct tests/regressions:
  - `flutter test test/features/groups/application/send_group_reaction_use_case_test.dart`
  - `flutter test test/features/groups/application/remove_group_reaction_use_case_test.dart`
  - `flutter test test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
  - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`
  - `flutter test test/features/groups/integration/group_reaction_roundtrip_test.dart`
  - `flutter test test/features/groups/integration/group_resume_recovery_test.dart`
  - `flutter test test/features/groups/integration/announcement_happy_path_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
- Matrix/closure docs to update when done:
  - refresh
    `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-breakdown.md`
  - defer stable doc and matrix note changes to Session `5`
- Dependency on earlier sessions:
  - Session `1` must be accepted so the authority contract is already
    trustworthy before reaction-freeze proof lands
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 3

- Title:
  `Propagate dissolved frozen-state truth into feed thread models and inline group surfaces`
- Session id:
  `3`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-3-plan.md`
- Exact scope:
  - thread dissolved-state facts through the group feed model so feed cards and
    inline group surfaces no longer derive writeability from announcement role
    alone
  - remove or disable compose, attach, quote-reply, and reaction-entry
    affordances for dissolved groups in feed-owned inline group surfaces while
    preserving readable history and other non-mutating views
  - keep active discussion groups and active announcement-reader/admin behavior
    unchanged outside the dissolved case
  - add direct feed-domain, projection, and presentation proof that dissolved
    groups remain visible as read-only history without looking writable
- Why it is its own session:
  - this is the feed/surface projection seam, which has different direct tests
    and a different named gate from the core group reaction application work
  - it should land only after Session `2` establishes the frozen reaction
    contract the feed surfaces are supposed to honor
- Likely code-entry files:
  - `lib/features/feed/domain/models/feed_item.dart`
  - `lib/features/feed/domain/utils/group_group_messages_into_threads.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/widgets/feed_card.dart`
  - `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
  - `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
  - `test/features/feed/domain/models/feed_item_test.dart`
  - `test/features/feed/domain/utils/group_group_messages_into_threads_test.dart`
  - `test/features/feed/presentation/screens/feed_screen_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/feed/application/load_feed_use_case_test.dart`
  - `test/features/feed/application/feed_projection_test.dart`
- Likely direct tests/regressions:
  - `flutter test test/features/feed/domain/models/feed_item_test.dart`
  - `flutter test test/features/feed/domain/utils/group_group_messages_into_threads_test.dart`
  - `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
  - `flutter test test/features/feed/application/load_feed_use_case_test.dart`
  - `flutter test test/features/feed/application/feed_projection_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh feed`
  - `./scripts/run_test_gates.sh groups` if execution touches shared group
    conversation or shared group reaction callback code in addition to feed
    projection
- Matrix/closure docs to update when done:
  - refresh
    `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-breakdown.md`
  - defer stable doc and matrix note changes to Session `5`
- Dependency on earlier sessions:
  - Session `2` must be accepted so feed surfaces project the final
    post-dissolve reaction/write contract instead of a temporary partial state
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 4

- Title:
  `Ship a truthful local-delete-after-dissolve cleanup flow with device-backed proof`
- Session id:
  `4`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-4-plan.md`
- Exact scope:
  - choose one shipped cleanup entry point for dissolved groups, preferably the
    existing group-info surface unless current repo evidence proves another
    surface is safer, and expose an explicit local-delete-after-dissolve action
  - make the cleanup copy truthful: users may keep the dissolved history, or
    they may delete it locally later, and that delete is not a new group-wide
    dissolve signal
  - wire `deleteGroupAndMessages(...)` or a tighter replacement so local delete
    remains device-local, does not publish new membership or dissolve side
    effects, and does not accidentally reopen send/rejoin behavior
  - add the required widget-driven/device-backed dissolved-group flow proving
    offline recovery into read-only history, visible local cleanup, and
    local-only deletion semantics
- Why it is its own session:
  - this is a user-facing cleanup contract, not just another freeze guard, and
    it carries the extra device-backed acceptance bar called out by the source
    doc
  - keeping it separate avoids mixing surface-projection work with the deeper
    local-delete semantics and acceptance harness work
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_info_screen.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
  - `lib/features/groups/application/delete_group_and_messages_use_case.dart`
  - `lib/features/groups/application/leave_group_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  - `test/features/groups/application/delete_group_and_messages_use_case_test.dart`
  - `test/features/groups/presentation/group_info_screen_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `integration_test/group_recovery_e2e_test.dart`
- Likely direct tests/regressions:
  - `flutter test test/features/groups/application/delete_group_and_messages_use_case_test.dart`
  - `flutter test test/features/groups/presentation/group_info_screen_test.dart`
  - `flutter test test/features/groups/presentation/group_info_wired_test.dart`
  - `flutter test test/features/groups/integration/group_membership_smoke_test.dart`
  - `flutter test integration_test/group_recovery_e2e_test.dart -d <device>`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
- Matrix/closure docs to update when done:
  - refresh
    `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-breakdown.md`
  - defer stable doc, inventory, and gate-definition updates to Session `5`
- Dependency on earlier sessions:
  - Sessions `1`, `2`, and `3` must be accepted so the cleanup surface is
    layered onto a truthful frozen-state contract instead of a still-partial
    dissolve implementation
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

### Session 5

- Title:
  `Refresh maintained dissolve docs and persist the final frozen-state verdict`
- Session id:
  `5`
- Session classification:
  `closure-only`
- Intended plan file:
  `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-5-plan.md`
- Exact scope:
  - refresh the maintained audit, network, matrix, and inventory docs so they
    describe the stricter dissolved frozen-state contract truthfully instead of
    stopping at "send is blocked"
  - reconcile the relevant dissolved-state notes in
    `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`,
    especially `UX-002`, `UX-014`, `RC-003`, and `RY-005`, so they cite
    current-admin-only dissolve authority, reaction freeze, feed non-writeable
    projection, and local-only cleanup evidence without overclaiming beyond the
    landed behavior
  - classify any new direct suites in `Test-Flight-Improv/test-gate-definitions.md`
    without widening frozen named gates accidentally
  - rerun the focused direct suites, required named gates, and the
    device-backed dissolved-group flow from Session `4`, then persist the final
    program verdict for Report `72`
- Why it is its own session:
  - maintained docs should move only after all repo-owned code and proof gaps
    are already closed
  - this session has one closure purpose: align the long-lived docs and the
    final program verdict with the landed frozen-state evidence
- Likely code-entry files:
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`
  - `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-breakdown.md`
- Likely direct tests/regressions:
  - reuse the same-day accepted direct suites from Sessions `1` through `4`
  - rerun the focused device-backed dissolved-group flow from Session `4`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh feed`
- Matrix/closure docs to update when done:
  - all maintained docs listed above
- Dependency on earlier sessions:
  - Sessions `1`, `2`, `3`, and `4` must already be accepted
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
