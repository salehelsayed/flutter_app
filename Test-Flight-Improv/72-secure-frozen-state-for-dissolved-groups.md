# 1. Title and Type

- Title: Secure Frozen State For Dissolved Groups
- Issue type: `feature-improvement`
- Output doc path: `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups.md`

# 2. Problem Statement

- Users need to trust that a dissolved group is truly over for everyone and that only currently allowed admins can end it.
- The repo already has an admin-initiated dissolve flow, but the user-visible contract is still incomplete: some surfaces already present dissolved groups as read-only history, while other interaction paths still behave like the group may remain active.
- This creates both trust and usability problems. Members cannot reliably tell whether a dissolved group is fully closed, whether any further interaction still counts, or whether they are expected to keep a dead group forever even after it no longer serves a purpose.
- The intended product outcome is simple: a dissolved group becomes permanently frozen for all members, previous history remains viewable, and each user may later delete the dissolved group locally if they no longer want to keep it.

# 3. Impact Analysis

- Affects admins who dissolve temporary, project, or announcement groups and need that action to carry a trustworthy final-state meaning.
- Affects all members of discussion and announcement groups, including members who were offline at the moment of dissolution and later recover state from replay.
- Affects feed, conversation, and group-info surfaces because inconsistent write or reaction affordances can make an ended group look partially active.
- The issue is security-sensitive because dissolve is already presented as a final admin action. If authority or final-state behavior differs across delivery paths, members can no longer trust what “dissolved” means.
- The issue is also a UX dead-end because dissolved history currently remains visible, but the repo evidence does not show a clear follow-up local-delete choice for users who want to clean it up later.

# 4. Current State

- Group info currently shows `Dissolve Group` only for active admins. Once a group is already dissolved, the same screen shows a dissolved status card, keeps previous history as read-only, and hides management controls including `Leave Group`. Evidence: `lib/features/groups/presentation/screens/group_info_screen.dart`, `test/features/groups/presentation/group_info_screen_test.dart`
- The dissolve flow already persists `isDissolved`, `dissolvedAt`, and `dissolvedBy`, saves a readable timeline message such as `Admin dissolved the group`, stores an offline replay envelope for other members, and leaves the topic locally. Evidence: `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `test/features/groups/application/dissolve_group_use_case_test.dart`
- Incoming dissolve system messages also mark the group dissolved, save the same timeline row, and leave the topic. Replayed dissolve events are treated idempotently. Evidence: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/group_message_listener_test.dart`
- Full conversation UI already treats dissolved groups as read-only history: it shows a dissolved badge and banner, hides compose controls, and `sendGroupMessage(...)` rejects new sends for dissolved groups. Incoming messages at or after the dissolve cutoff are also dropped. Evidence: `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`
- Reactions are not currently frozen by dissolution. The group reaction add path validates only group existence, membership, and target message existence; the remove path likewise validates existence and membership without a dissolved-state guard; and the wired conversation screen still exposes reaction selection callbacks independently of `_canWrite`. Evidence: `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/groups/application/remove_group_reaction_use_case.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/remove_group_reaction_use_case_test.dart`
- Feed thread writeability does not currently model dissolved state. `GroupThreadFeedItem.canWrite` only distinguishes announcement admin vs non-admin behavior, and the feed thread builders do not carry `isDissolved` into the thread model. Evidence: `lib/features/feed/domain/models/feed_item.dart`, `lib/features/feed/domain/utils/group_group_messages_into_threads.dart`, `lib/features/feed/presentation/screens/feed_wired.dart`, `lib/features/feed/presentation/screens/feed_screen.dart`
- Membership-event authorization for dissolve is currently broader than a pure “current admin only” rule. The listener accepts the stored group creator as inherently authorized, and the offline replay drain uses the decrypted payload sender identity when replaying system events. Evidence: `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- The repo already has a generic local delete-and-leave primitive and Orbit delete action, but the evidence reviewed here does not show a dissolved-group-facing cleanup affordance in the group info, group conversation, or feed surfaces, or a dissolve-specific local-only contract that tells users they may delete the dissolved group when they want. The visible dissolved-state contract today is “history stays available,” not “history stays available until you choose to delete it.” Evidence: `lib/features/groups/application/delete_group_and_messages_use_case.dart`, `lib/features/orbit/presentation/screens/orbit_wired.dart`, `test/features/groups/application/delete_group_and_messages_use_case_test.dart`, `lib/features/groups/presentation/screens/group_info_screen.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `test/features/groups/presentation/group_info_screen_test.dart`

# 5. Scope Clarification

In scope:

- a trustworthy dissolved-state contract where only currently authorized admins can successfully dissolve a group
- consistent dissolved-state behavior across group info, full conversation, and feed/card surfaces
- a fully frozen post-dissolve experience where members cannot send, react, or perform further group-management actions
- preserving read-only history until each user decides whether to keep or delete the dissolved group locally
- both discussion-group and announcement-group behavior once the group is dissolved

Explicit non-goals:

- redesigning ordinary personal `Leave Group` behavior for active groups
- redefining archive, mute, or other local organization features beyond their relationship to dissolved groups
- adding restore, reopen, transfer-ownership, scheduled-dissolve, or legal-retention product flows
- broad role-management changes that are unrelated to the authority required for dissolution itself

Accepted ambiguities for the later implementation pass:

- exact copy and placement for the local delete affordance after dissolution
- whether local delete is reached from the dissolved group info screen, a list/context action, or another existing cleanup surface
- exact visual styling for frozen-state affordances, as long as all writable and reactive actions clearly disappear or become unavailable

# 6. Test Cases

## Happy Path

- A current admin dissolves an active discussion group, and every member later sees the same final dissolved state with readable history, a clear ended-state indicator, and no remaining way to send or react.
- A current admin dissolves an active announcement group, and both announcement admins and announcement readers converge to the same fully frozen ended state instead of preserving any remaining participation affordances.
- A member who was offline during dissolution later recovers and sees the group as dissolved, keeps pre-dissolve history, and cannot send or react after recovery.
- A user opens a dissolved group, reviews the preserved history, and can later choose to delete that dissolved group locally without changing the dissolved state for anyone else.

## Edge Cases

- A non-admin member cannot dissolve a group, and other members continue to see the group as active.
- A user who originally created the group but is no longer an admin cannot dissolve it once their current role no longer allows that action.
- Duplicate or repeated dissolve deliveries do not create multiple dissolved timeline rows, re-enable any controls, or leave members in inconsistent end states.
- A user who tries to send text, media, or voice after dissolution gets a predictable blocked outcome and does not leave behind ghost messages or partially delivered content.
- A user who tries to add or remove a reaction after dissolution gets a predictable blocked outcome and does not see a transient optimistic reaction that looks accepted.
- Feed cards and inline conversation variants for a dissolved group do not expose compose, attach, quote-reply, or reaction-entry affordances that imply further participation.
- A user who does not want to delete the dissolved group can keep read-only history available without the app pushing them into immediate cleanup.

## Regressions To Preserve

- Active non-dissolved discussion groups keep their current send, media, reaction, invite, and recovery behavior.
- Active announcement groups keep their current admin-only send behavior until an actual dissolve occurs.
- Existing dissolved-group guarantees that already work today stay intact: pre-dissolve history remains viewable, post-dissolve sends are blocked, and recovery still converges offline members into the dissolved state.
- A user’s local delete choice for a dissolved group must not redefine dissolution into a global delete-for-everyone action.

## Coverage Notes

- The implementation pass should not treat this spec as satisfied by one or two happy-path tests. The acceptance bar for this feature includes explicit proof at the unit/use-case, widget/presentation, repo-integration or smoke, and simulator/device layers because dissolve authority and frozen-state behavior must stay consistent across live, replay, recovery, and UI surfaces.
- Existing tests already partially cover the current dissolved-state baseline for history retention and blocked sends: `test/features/groups/application/dissolve_group_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/presentation/group_info_screen_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`
- Unit and use-case coverage is expected to prove at least these contracts:
  - only a currently authorized admin can dissolve, including rejection when the original creator is no longer an admin
  - replayed or recovered dissolve events stay idempotent and do not widen authority through an unauthenticated sender identity
  - dissolved groups block message send, reaction add, and reaction remove paths with a predictable blocked result
  - post-dissolve incoming messages or reactions do not resurrect activity or store misleading state
  - Relevant existing seams include `test/features/groups/application/dissolve_group_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/remove_group_reaction_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
- Widget and presentation coverage is expected to prove that every surfaced entry point shows the same frozen contract after dissolution:
  - the dissolved-group journey exposes the ended-state status and a local-delete choice on an allowed cleanup surface without reviving any management actions
  - full conversation removes compose and reaction-entry affordances while keeping read-only history visible
  - feed cards and inline thread variants model dissolved groups as non-writable and non-reactable
  - Relevant existing seams include `test/features/groups/presentation/group_info_screen_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/feed/domain/models/feed_item_test.dart`, `test/features/feed/domain/utils/group_group_messages_into_threads_test.dart`, `test/features/feed/presentation/screens/feed_screen_test.dart`, `test/features/feed/presentation/screens/feed_wired_test.dart`
- Repo integration and smoke coverage is expected to prove multi-user convergence instead of only local blocking:
  - discussion and announcement groups both converge to the same dissolved frozen state
  - offline recovery and resume still deliver the dissolve final state while blocking any later send or reaction activity
  - post-dissolve reaction paths do not round-trip successfully over live or replay delivery
  - Relevant existing seams include `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_reaction_roundtrip_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, `test/features/groups/integration/announcement_happy_path_test.dart`
- Simulator or device-backed coverage is expected because this feature spans push-drain, recovery, and cross-surface UX:
  - at least one widget-driven `integration_test/` flow should prove dissolve recovery on a running app surface, including reopening the dissolved group, seeing the read-only state, failing send and reaction attempts predictably, and confirming that local delete stays local-only
  - UI-facing device-backed seams to extend or mirror include `integration_test/foreground_group_push_drain_test.dart` and `integration_test/group_recovery_e2e_test.dart`
  - CLI or harness seams such as `integration_test/group_recovery_cli_e2e_test.dart` and `integration_test/group_multi_device_real_harness.dart` can support recovery-orchestration evidence, but should not alone satisfy the user-facing acceptance bar
- No current repo evidence was found for dissolved-group reaction blocking, dissolved-state propagation into feed writeability, a former-admin-or-former-creator dissolve rejection case, an explicit offline replay sender-auth proof for dissolve, or a user-facing local-delete-after-dissolve acceptance case.
