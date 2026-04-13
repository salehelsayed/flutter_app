# Discussion and Announcement Test Matrix Row Breakdown

## Recommended Plan Count

- recommended plan count: 121
- default posture held: one matrix row = one session, plus explicit shared prerequisite sessions where multiple unresolved rows depend on the same repo-owned capability or harness
- added prerequisite sessions: 3
- added closure-only sessions: 0

## Decomposition Artifact

- artifact path: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
- generated from source matrix: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- generated on: 2026-04-11
- workflow executed in order: Matrix Intake -> Row Inventory -> Evidence Map -> Row Disposition -> Dependency Pass -> Breakdown Write
- adjacent breakdown present at intake: yes
- source rows inventoried: 118
- ordered sessions written: 121
- unresolved row-owned sessions remaining after decomposition: 17
- unresolved shared prerequisite sessions remaining after decomposition: 3
- repo-external or device-lab proof rows intentionally left evidence-gated: none
- repo-owned simulator / local-relay exploratory proof rows intentionally left evidence-gated: none
- note: this refresh removes the stale completed-rollout verdict and reopens the remaining unresolved matrix rows into implementation-committed row-owned work with explicit shared prerequisites where the blocker is repo-owned; the `Matrix Row Inventory` remains the decomposition-time intake table, while the runnable truth for this rollout now lives in the `Session Ledger` and `Ordered Session Breakdown`

## Overall Closure Bar

- overall verdict: `closed`
- closure bar: satisfied on 2026-04-12. Matrix unresolved count is 0, session-ledger unresolved count is 0, repo-owned verification is green, the final primary-iOS reruns for `MD-004` and `UX-009` are persisted, and unsupported rows remain explicit but non-blocking.
- row-owned truth rule: later closure must report final truth per source row id, not only per subsystem or seam.
- implementation-committed gap-closure rule: unresolved row-owned sessions cannot finish as `accepted_with_explicit_follow_up`; only truly repo-external or device-lab-only proof rows may remain `evidence-gated`.
- unsupported rows rule: rows classified `unsupported_product_scope` stay explicitly out of implementation scope unless product scope changes.

## Current Controller Status

- latest resolved controller action in this refresh: final deployed-relay acceptance completion was persisted after the primary iOS reruns for `MD-004` and `UX-009` landed green and all repo-owned verification stayed green
- latest source-matrix truth alignment in this refresh: `MD-004` now cites the earlier spare `iPhone 16e` proof plus `/private/tmp/acceptance_20260412/group_multi_device_real_primary_ios.log`, and `UX-009` now cites the earlier spare `iPhone 16e` proof plus `/private/tmp/acceptance_20260412/notification_open_ui_primary_ios.log`
- next runnable session by current ledger: none; final program acceptance is complete
- current blocker state: `none`
- degraded local continuation mode: completed closure successfully; multi-relay wrappers were rerun and truthfully skipped in `/private/tmp/acceptance_20260412/lane7.log` and `/private/tmp/acceptance_20260412/lane8.log` because no two-relay `MKNOON_RELAY_ADDRESSES` environment was configured

## Source Of Truth

- primary matrix: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- repo coverage inventory: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- create / send / receive / invite / recovery docs:
  - `Test-Flight-Improv/Group-Chat-Feature/C4-01-Create-Discussion.md`
  - `Test-Flight-Improv/Group-Chat-Feature/C4-02-Send-Message.md`
  - `Test-Flight-Improv/Group-Chat-Feature/C4-03-Receive-Message.md`
  - `Test-Flight-Improv/Group-Chat-Feature/C4-04-Invite-And-Join.md`
  - `Test-Flight-Improv/Group-Chat-Feature/C4-05-Recovery-And-Reliability.md`
- audit context: `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`
- current repo code and tests override stale prose when they materially disagree.

## Matrix Row Inventory

| source row id | scenario | priority | source section or table | provisional row disposition | intended session id |
|---|---|---|---|---|---|
| CB-001 | Blank-name create auto-generates a stable, readable group name | P1 | Create, Bootstrap, and Configuration Truth | covered_in_repo | CB-001 |
| CB-002 | Create blocks over-limit selection before any local or bridge state is created | P0 | Create, Bootstrap, and Configuration Truth | covered_in_repo | CB-002 |
| CB-003 | Partial per-member add failure during create yields a truthful successful subset only | P0 | Create, Bootstrap, and Configuration Truth | needs_tests_only | CB-003 |
| CB-004 | Create-time invite degradation is explicit when node is stopped, recipient has no ML-KEM key, or direct send fails | P0 | Create, Bootstrap, and Configuration Truth | needs_code_and_tests | CB-004 |
| CB-005 | Post-create `group:updateConfig` or `members_added` publish failure does not leave ghost local membership | P0 | Create, Bootstrap, and Configuration Truth | needs_code_and_tests | CB-005 |
| CB-006 | Create-time description support is honest | P1 | Create, Bootstrap, and Configuration Truth | needs_tests_only | CB-006 |
| CB-007 | Persisted topic namespace matches the real `/mknoon/group/{groupId}` namespace | P1 | Create, Bootstrap, and Configuration Truth | needs_code_and_tests | CB-007 |
| CB-008 | Group create never reports success into a locally keyless state | P0 | Create, Bootstrap, and Configuration Truth | needs_code_and_tests | CB-008 |
| DV-001 | Create discussion group successfully | P0 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-001 |
| DV-002 | Create announcement group successfully with admin-only compose | P0 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-002 |
| DV-003 | Adding members shows immediate feedback and a durable in-chat add-members event | P0 | Membership Visibility and Invite Lifecycle | needs_code_and_tests | DV-003 |
| DV-004 | Accepting a pending invite creates a durable join / acceptance event visible to existing members | P0 | Membership Visibility and Invite Lifecycle | needs_code_and_tests | DV-004 |
| DV-005 | Invite decline and expiry leave no ghost membership or ghost access | P0 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-005 |
| DV-006 | Removing a member updates lists and creates a durable removal event for remaining members | P0 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-006 |
| DV-007 | Removed member converges to removed state after offline reconnect | P0 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-007 |
| DV-008 | Voluntary leave creates a durable `X left the group` event visible to remaining members | P1 | Membership Visibility and Invite Lifecycle | needs_code_and_tests | DV-008 |
| DV-009 | Duplicate invite preview for the same group replaces the earlier pending row instead of duplicating cards | P1 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-009 |
| DV-010 | Blocked, unknown, or sender-mismatch invites are rejected without ghost pending or joined state | P0 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-010 |
| DV-011 | Pending-invite route target opens the review surface until the group is actually joined | P1 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-011 |
| DV-012 | Accepting or declining an invite on one device does not incorrectly clear the sibling device pending row | P1 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-012 |
| DV-013 | Partial invite fan-out result is explicit per recipient | P0 | Membership Visibility and Invite Lifecycle | needs_code_and_tests | DV-013 |
| DV-014 | Batch add with no latest group key is explicit and does not silently look like completed onboarding | P0 | Membership Visibility and Invite Lifecycle | needs_code_and_tests | DV-014 |
| DV-015 | Remove, rotate, and re-invite gives the rejoined member the correct rotated epoch | P0 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-015 |
| DV-016 | New-member history boundary stays future-only except for the explicitly allowed post-join replay contract | P0 | Membership Visibility and Invite Lifecycle | covered_in_repo | DV-016 |
| ID-001 | Creator/admin identity resolves to username instead of raw peer ID when a username exists | P0 | Identity, Roles, Avatars, and Mixed-Social-Graph Behavior | needs_code_and_tests | ID-001 |
| ID-002 | Member list and conversation surfaces show consistent participant identity, including avatars, for current members | P1 | Identity, Roles, Avatars, and Mixed-Social-Graph Behavior | needs_code_and_tests | ID-002 |
| ID-003 | Once membership exists, non-friend members can still read and write in the same discussion group | P0 | Identity, Roles, Avatars, and Mixed-Social-Graph Behavior | needs_tests_only | ID-003 |
| ID-004 | Supported onboarding path exists for non-friend participants when product scope says mixed-social-graph groups are allowed | P1 | Identity, Roles, Avatars, and Mixed-Social-Graph Behavior | needs_repo_evidence | ID-004 |
| ID-005 | Admin promotion and demotion update permissions, badges, and visible timeline history consistently | P0 | Identity, Roles, Avatars, and Mixed-Social-Graph Behavior | covered_in_repo | ID-005 |
| ID-006 | Sole-admin leave stays blocked until a valid admin state exists | P0 | Identity, Roles, Avatars, and Mixed-Social-Graph Behavior | covered_in_repo | ID-006 |
| ID-007 | Explicit admin transfer or ownership handoff behaves cleanly if the feature exists | P2 | Identity, Roles, Avatars, and Mixed-Social-Graph Behavior | unsupported_product_scope | ID-007 |
| ID-008 | Duplicate re-add, duplicate invite, or stale membership replay does not create duplicate member rows or duplicate timeline spam | P1 | Identity, Roles, Avatars, and Mixed-Social-Graph Behavior | needs_tests_only | ID-008 |
| ID-009 | Invite-carried avatar metadata persists and resolves cleanly after accept | P1 | Identity, Roles, Avatars, and Mixed-Social-Graph Behavior | needs_tests_only | ID-009 |
| ID-010 | Non-friend fallback identity and avatar remain readable when full avatar sharing is unavailable | P1 | Identity, Roles, Avatars, and Mixed-Social-Graph Behavior | needs_code_and_tests | ID-010 |
| CX-001 | Long-pressing a supported group message opens one coherent context surface, not only a detached reaction bar | P1 | Long-Press Context Actions and Overlay Parity | needs_code_and_tests | CX-001 |
| CX-002 | Group long-press reply entry reaches the existing quote-reply path for supported messages | P1 | Long-Press Context Actions and Overlay Parity | needs_code_and_tests | CX-002 |
| CX-003 | Group long-press copy action copies exact text for supported rows and dismisses cleanly | P1 | Long-Press Context Actions and Overlay Parity | needs_code_and_tests | CX-003 |
| CX-004 | Unsupported group edit/delete actions stay honestly hidden without blocking the rest of the context surface | P1 | Long-Press Context Actions and Overlay Parity | needs_code_and_tests | CX-004 |
| CX-005 | Local-only long-press actions remain available even when reactions are unavailable | P1 | Long-Press Context Actions and Overlay Parity | needs_code_and_tests | CX-005 |
| CX-006 | Any future group long-press overlay preserves swipe-to-quote, reaction toggles, and current row rendering | P1 | Long-Press Context Actions and Overlay Parity | needs_code_and_tests | CX-006 |
| CX-007 | Group action parity stays consistent regardless of whether the conversation was entered from `Orbit`, `Feed`, or a notification anchor | P1 | Long-Press Context Actions and Overlay Parity | needs_tests_only | CX-007 |
| UI-001 | Each group message renders as one clear bubble without a doubled or stacked-card artifact | P1 | Message Rendering and Visual Stability | needs_code_and_tests | UI-001 |
| UI-002 | Row-shell stability survives quote enrichment, reaction updates, media auto-download, and replay enrichment | P1 | Message Rendering and Visual Stability | needs_tests_only | UI-002 |
| RX-001 | Tapping a visible group reaction chip reveals which members reacted and with which emoji | P1 | Reaction Transparency and Participant Identity | needs_code_and_tests | RX-001 |
| RX-002 | Inspecting a group reaction cluster is non-destructive and does not silently remove the viewer's own reaction | P1 | Reaction Transparency and Participant Identity | needs_code_and_tests | RX-002 |
| RX-003 | Reaction participant identity stays readable even when reaction rows only persist peer IDs or when reactors are non-friends | P1 | Reaction Transparency and Participant Identity | needs_code_and_tests | RX-003 |
| RX-004 | Reaction inspection parity is preserved across `Orbit` and `Feed` entry points | P1 | Reaction Transparency and Participant Identity | needs_code_and_tests | RX-004 |
| RX-005 | Inline Feed group-thread reactions and permissions behave coherently if inline interaction stays in scope | P1 | Reaction Transparency and Participant Identity | needs_code_and_tests | RX-005 |
| RX-006 | Live, replayed, and post-rotation reactions remain truthful after resume/rejoin | P1 | Reaction Transparency and Participant Identity | needs_tests_only | RX-006 |
| MM-001 | Discussion members can send text, media, replies, and reactions to all current members | P0 | Messaging, Compose, Media, Voice, and Delivery Truth | covered_in_repo | MM-001 |
| MM-002 | Announcement groups enforce admin-only compose while readers still see and react | P0 | Messaging, Compose, Media, Voice, and Delivery Truth | covered_in_repo | MM-002 |
| MM-003 | Voice-only send is supported, empty non-media send is blocked, and announcement readers never expose stale send/record controls | P1 | Messaging, Compose, Media, Voice, and Delivery Truth | covered_in_repo | MM-003 |
| MM-004 | Quote reply survives send, render, failure, and retry paths without losing user intent | P1 | Messaging, Compose, Media, Voice, and Delivery Truth | covered_in_repo | MM-004 |
| MM-005 | Media upload failure leaves a truthful failed/retryable row, and targeted retry/delete only affects that row | P1 | Messaging, Compose, Media, Voice, and Delivery Truth | covered_in_repo | MM-005 |
| MM-006 | The sender-facing state machine stays honest across publish success, publish timeout, no-peer fallback, inbox failure, and retry | P0 | Messaging, Compose, Media, Voice, and Delivery Truth | covered_in_repo | MM-006 |
| MM-007 | Publish timeout plus inbox success remains successful in UI and storage | P0 | Messaging, Compose, Media, Voice, and Delivery Truth | covered_in_repo | MM-007 |
| MM-008 | Publish-success pending rows finalize only through an owned path, not silent drift | P1 | Messaging, Compose, Media, Voice, and Delivery Truth | needs_tests_only | MM-008 |
| MM-009 | Zero-peer plus inbox-fail sends recover through one explicit retry owner and never get stranded between retry lanes | P1 | Messaging, Compose, Media, Voice, and Delivery Truth | needs_code_and_tests | MM-009 |
| MM-010 | Discussion and announcement sends survive background, route unmount, and zero-peer fallback with honest final status | P0 | Messaging, Compose, Media, Voice, and Delivery Truth | needs_tests_only | MM-010 |
| MM-011 | Legacy `topicPeers == null` bridge compatibility preserves truthful terminal state | P1 | Messaging, Compose, Media, Voice, and Delivery Truth | covered_in_repo | MM-011 |
| MM-012 | Send rules during active group recovery are explicit and intentional | P1 | Messaging, Compose, Media, Voice, and Delivery Truth | needs_tests_only | MM-012 |
| MM-013 | Non-friend member media delivery works the same as friend media delivery once membership exists | P0 | Messaging, Compose, Media, Voice, and Delivery Truth | needs_tests_only | MM-013 |
| MM-014 | Share-to-group respects write eligibility and partial-failure truth across writable groups | P1 | Messaging, Compose, Media, Voice, and Delivery Truth | covered_in_repo | MM-014 |
| MM-015 | Announcement sends after key rotation still use the new epoch and remain deliverable | P1 | Messaging, Compose, Media, Voice, and Delivery Truth | covered_in_repo | MM-015 |
| RC-001 | Live receive plus replay dedupe prevents duplicate visible rows when pubsub and inbox both deliver the same message | P0 | Receive, Rendering, Notification, and Conversation Integrity | covered_in_repo | RC-001 |
| RC-002 | Duplicate replay enriches missing quote/media metadata rather than creating a second row | P1 | Receive, Rendering, Notification, and Conversation Integrity | covered_in_repo | RC-002 |
| RC-003 | Unknown-group, unauthorized-sender, post-removal, and post-dissolve messages do not appear beyond allowed cutoffs | P0 | Receive, Rendering, Notification, and Conversation Integrity | covered_in_repo | RC-003 |
| RC-004 | Sequential messages, delayed delivery, and burst traffic preserve ordering and avoid user-visible loss within supported capacity | P1 | Receive, Rendering, Notification, and Conversation Integrity | covered_in_repo | RC-004 |
| RC-005 | A sibling device for the same user stores own live publishes as local sent history | P1 | Receive, Rendering, Notification, and Conversation Integrity | covered_in_repo | RC-005 |
| RC-006 | Media auto-download and row upsert do not create duplicate rows or destroy scroll/context | P1 | Receive, Rendering, Notification, and Conversation Integrity | needs_tests_only | RC-006 |
| RC-007 | Notification anchors open the group and highlight the targeted message context | P1 | Receive, Rendering, Notification, and Conversation Integrity | covered_in_repo | RC-007 |
| RC-008 | Notification truth suppresses own-message, active-conversation, and recent-remote-push duplicate alerts | P1 | Receive, Rendering, Notification, and Conversation Integrity | covered_in_repo | RC-008 |
| RC-009 | Decryption failure or payload-parse failure creates no ghost message and remains diagnosable | P1 | Receive, Rendering, Notification, and Conversation Integrity | needs_code_and_tests | RC-009 |
| RC-010 | Dispatcher overflow or high-burst receive load has an owned contract and monitoring story | P1 | Receive, Rendering, Notification, and Conversation Integrity | needs_code_and_tests | RC-010 |
| RY-001 | Cold-start rejoin and drain re-establish live delivery exactly once | P0 | Recovery, Replay, Retention, and Offline Privacy | covered_in_repo | RY-001 |
| RY-002 | Foreground resume runs rejoin, drain, stuck-send recovery, upload retry, failed-send retry, and inbox retry in the intended order | P1 | Recovery, Replay, Retention, and Offline Privacy | covered_in_repo | RY-002 |
| RY-003 | Paused / hidden lifecycle pre-commits `sending` rows to failed so later recovery can pick them up | P0 | Recovery, Replay, Retention, and Offline Privacy | covered_in_repo | RY-003 |
| RY-004 | Watchdog or node-requested recovery acknowledges only after a clean rejoin | P1 | Recovery, Replay, Retention, and Offline Privacy | covered_in_repo | RY-004 |
| RY-005 | Archived groups still drain/rejoin as intended while dissolved groups stay read-only and skipped from rejoin | P1 | Recovery, Replay, Retention, and Offline Privacy | covered_in_repo | RY-005 |
| RY-006 | Multi-page cursor drain recovers backlog exactly once across pages and cursor continuation | P1 | Recovery, Replay, Retention, and Offline Privacy | covered_in_repo | RY-006 |
| RY-007 | Partition heal and delayed delivery converge without duplicates and resume live delivery | P0 | Recovery, Replay, Retention, and Offline Privacy | needs_code_and_tests | RY-007 |
| RY-008 | Recovery does not burst all joined groups at once | P1 | Recovery, Replay, Retention, and Offline Privacy | covered_in_repo | RY-008 |
| RY-009 | Long-offline mixed-window recovery keeps retained backlog, drops expired non-system backlog, still applies old system membership events, and surfaces truthful retention messaging | P1 | Recovery, Replay, Retention, and Offline Privacy | covered_in_repo | RY-009 |
| RY-010 | Replay without `GroupMessageListener` or without `reactionRepo` never silently claims full convergence | P1 | Recovery, Replay, Retention, and Offline Privacy | needs_code_and_tests | RY-010 |
| RY-011 | Invite-accept drain includes offline reactions in the same user-visible catch-up window, or the deferred model is explicitly owned | P1 | Recovery, Replay, Retention, and Offline Privacy | needs_code_and_tests | RY-011 |
| RY-012 | Invite acceptance that returns `bridgeError` still converges to a live joined group without needing the invite row again | P1 | Recovery, Replay, Retention, and Offline Privacy | needs_code_and_tests | RY-012 |
| RY-013 | Offline group replay payloads stored on the relay are opaque to relay operators | P0 | Recovery, Replay, Retention, and Offline Privacy | needs_tests_only | RY-013 |
| RY-014 | Encrypted replay remains seamless for text, replies, image, video, GIF/file, and recorded voice | P0 | Recovery, Replay, Retention, and Offline Privacy | needs_code_and_tests | RY-014 |
| RY-015 | Encrypted replay respects add/remove/leave membership boundaries | P0 | Recovery, Replay, Retention, and Offline Privacy | needs_code_and_tests | RY-015 |
| RY-016 | Encrypted replay remains reliable through retry, resume, cursor drain, reconnect, and dedupe | P0 | Recovery, Replay, Retention, and Offline Privacy | needs_code_and_tests | RY-016 |
| MD-001 | Same-user live publishes on a sibling device store as local sent history without duplicate unread or notification confusion | P1 | Multi-Device and Cross-Surface Convergence | covered_in_repo | MD-001 |
| MD-002 | Membership updates converge across sibling devices without duplicate local membership or role drift | P1 | Multi-Device and Cross-Surface Convergence | covered_in_repo | MD-002 |
| MD-003 | Mute, unread, and local notifications stay device-local across sibling devices | P1 | Multi-Device and Cross-Surface Convergence | covered_in_repo | MD-003 |
| MD-004 | True device/simulator multi-device E2E proves sibling-device behavior beyond in-memory fakes | P1 | Multi-Device and Cross-Surface Convergence | covered_in_repo | MD-004 |
| MD-005 | Message-level behavior stays consistent when entering the same group from `Orbit`, `Feed`, or push | P1 | Multi-Device and Cross-Surface Convergence | needs_tests_only | MD-005 |
| MD-006 | Group-message and group-invite push routes navigate to the correct surface | P1 | Multi-Device and Cross-Surface Convergence | covered_in_repo | MD-006 |
| SV-001 | Only current members can publish discussion messages; unauthorized peers do not create visible rows | P0 | Security, Validator, Bridge-Contract, and Observability | covered_in_repo | SV-001 |
| SV-002 | Announcement readers cannot bypass write restrictions via stale callbacks or raw publish | P0 | Security, Validator, Bridge-Contract, and Observability | covered_in_repo | SV-002 |
| SV-003 | Removed members are only accepted for delayed pre-cutoff traffic, not post-cutoff traffic | P0 | Security, Validator, Bridge-Contract, and Observability | covered_in_repo | SV-003 |
| SV-004 | Replay attack with tampered timestamps or reordered envelopes does not create duplicate visible messages or bypass cutoffs | P1 | Security, Validator, Bridge-Contract, and Observability | needs_code_and_tests | SV-004 |
| SV-005 | Tampered payload, wrong key, tampered nonce, or tampered ciphertext creates no visible message and yields diagnosable rejection | P1 | Security, Validator, Bridge-Contract, and Observability | needs_code_and_tests | SV-005 |
| SV-006 | Previous-key grace during rotation accepts legitimate in-flight traffic without reopening indefinite stale-key access | P1 | Security, Validator, Bridge-Contract, and Observability | needs_code_and_tests | SV-006 |
| SV-007 | Concurrent key-rotation races across admins converge to one final usable epoch | P1 | Security, Validator, Bridge-Contract, and Observability | needs_code_and_tests | SV-007 |
| SV-008 | Concurrent remove/promote or remove/rotate conflicts converge to one final visible member/admin map and usable key state | P1 | Security, Validator, Bridge-Contract, and Observability | needs_tests_only | SV-008 |
| SV-009 | Description pass-through between Dart and Go is explicit and tested if create-time description is supported | P2 | Security, Validator, Bridge-Contract, and Observability | unsupported_product_scope | SV-009 |
| SV-010 | Topic namespace / `topicName` contract between Go and Dart is explicit and tested | P1 | Security, Validator, Bridge-Contract, and Observability | needs_tests_only | SV-010 |
| SV-011 | Flow-event names and payload shapes for group timing/recovery/retry observability are pinned | P2 | Security, Validator, Bridge-Contract, and Observability | needs_tests_only | SV-011 |
| SV-012 | Native dispatcher overflow or dropped diagnostics are surfaced to monitoring instead of remaining silent | P2 | Security, Validator, Bridge-Contract, and Observability | needs_tests_only | SV-012 |
| UX-001 | Per-group mute suppresses notifications without dropping delivery | P1 | Quality-of-Life and Higher-Level Product Capabilities | covered_in_repo | UX-001 |
| UX-002 | Dissolving the group keeps history readable but blocks further writing | P1 | Quality-of-Life and Higher-Level Product Capabilities | covered_in_repo | UX-002 |
| UX-003 | Search inside group history works if the feature exists | P2 | Quality-of-Life and Higher-Level Product Capabilities | unsupported_product_scope | UX-003 |
| UX-004 | Pinning and unpinning important messages works if the feature exists | P2 | Quality-of-Life and Higher-Level Product Capabilities | unsupported_product_scope | UX-004 |
| UX-005 | Per-message edit, delete, or tombstone works if the feature exists | P2 | Quality-of-Life and Higher-Level Product Capabilities | unsupported_product_scope | UX-005 |
| UX-006 | Read receipts or reader counts work if the feature exists | P2 | Quality-of-Life and Higher-Level Product Capabilities | unsupported_product_scope | UX-006 |
| UX-007 | Member-level moderation such as mute or ban works if the feature exists | P2 | Quality-of-Life and Higher-Level Product Capabilities | unsupported_product_scope | UX-007 |
| UX-008 | Scheduled announcements, edit-after-send, delete-after-send, or analytics work if the feature exists | P2 | Quality-of-Life and Higher-Level Product Capabilities | unsupported_product_scope | UX-008 |
| UX-009 | Local-relay / simulator exploratory push trigger path for group message and group invite is verified if push is in scope | P1 | Quality-of-Life and Higher-Level Product Capabilities | covered_in_repo | UX-009 |
| UX-010 | Share-target picker shows only writable groups and respects announcement read-only filtering | P1 | Quality-of-Life and Higher-Level Product Capabilities | covered_in_repo | UX-010 |

## Row Traceability Rule

- every source row maps to exactly one session id in this artifact; no duplicate or seam-bucket collapse was introduced.
- session ids preserve the source row ids verbatim because every row id is filename-safe.
- shared prerequisite sessions use `PREREQ-...` ids, but they do not replace row-owned closure; each dependent source row still keeps its own session id and must be closed separately in the source matrix.
- later closure work must report final truth per source row, even when multiple rows touch the same code-entry files or test harnesses.

## Session Ledger

| session id | source row id | priority | row disposition | session classification | execution ownership | dependency | intended plan file |
|---|---|---|---|---|---|---|---|
| PREREQ-GROUP-OFFLINE-REPLAY | shared prerequisite | P0 | shared_prerequisite | accepted | opaque encrypted replay envelopes plus cross-stack drain and retrieve compatibility now land end-to-end across Flutter, `go-mknoon/node`, and `go-relay-server` | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-PREREQ-GROUP-OFFLINE-REPLAY-plan.md |
| PREREQ-GROUP-PROOF-HARNESS | shared prerequisite | P0 | shared_prerequisite | accepted | `group_security_harness_test.go` now centralizes raw-envelope mutation, local-node connect/publish, and grace-fixture helpers, and the existing decryption-failure / grace suites now reuse that seam directly | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-PREREQ-GROUP-PROOF-HARNESS-plan.md |
| PREREQ-GROUP-DISPATCHER-OVERFLOW | shared prerequisite | P1 | shared_prerequisite | accepted | dispatcher pressure and overflow diagnostics now surface through the Go dispatcher and Flutter monitoring contracts under burst load | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-PREREQ-GROUP-DISPATCHER-OVERFLOW-plan.md |
| CB-002 | CB-002 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-002-plan.md |
| CB-003 | CB-003 | P0 | covered_in_repo | accepted | tests landed in create_group_with_members_use_case_test.dart | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-003-plan.md |
| CB-004 | CB-004 | P0 | covered_in_repo | accepted | create flow now returns explicit invite-degradation warnings instead of implying full success | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-004-plan.md |
| CB-005 | CB-005 | P0 | covered_in_repo | accepted | create/add-member flows now roll back config-sync ghost membership and surface publish degradation honestly | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-005-plan.md |
| CB-008 | CB-008 | P0 | covered_in_repo | accepted | keyless create now rolls back local state and fails honestly | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-008-plan.md |
| DV-001 | DV-001 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-001-plan.md |
| DV-002 | DV-002 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-002-plan.md |
| DV-003 | DV-003 | P0 | covered_in_repo | accepted | add-member flows now persist durable `members_added` timeline rows and keep completion feedback truthful | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-003-plan.md |
| DV-004 | DV-004 | P0 | covered_in_repo | accepted | invite accept now publishes and persists a durable `member_joined` event that existing members can render | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-004-plan.md |
| DV-005 | DV-005 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-005-plan.md |
| DV-006 | DV-006 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-006-plan.md |
| DV-007 | DV-007 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-007-plan.md |
| DV-010 | DV-010 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-010-plan.md |
| DV-013 | DV-013 | P0 | covered_in_repo | accepted | batch invite flows now return per-recipient outcomes and explicit warning text | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-013-plan.md |
| DV-014 | DV-014 | P0 | covered_in_repo | accepted | missing-latest-key onboarding is now surfaced explicitly in create and add-member flows | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-014-plan.md |
| DV-015 | DV-015 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-015-plan.md |
| DV-016 | DV-016 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-016-plan.md |
| ID-001 | ID-001 | P0 | covered_in_repo | accepted | creator username now persists through create, exports in `groupConfig`, and renders for other members | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-001-plan.md |
| ID-003 | ID-003 | P0 | covered_in_repo | stale/already-covered | no execution because existing non-contact membership-driven send coverage is already direct enough | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-003-plan.md |
| ID-005 | ID-005 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-005-plan.md |
| ID-006 | ID-006 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-006-plan.md |
| MM-001 | MM-001 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-001-plan.md |
| MM-002 | MM-002 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-002-plan.md |
| MM-006 | MM-006 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-006-plan.md |
| MM-007 | MM-007 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-007-plan.md |
| MM-010 | MM-010 | P0 | covered_in_repo | stale/already-covered | no execution because background/unmount/zero-peer send coverage is already direct | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-010-plan.md |
| MM-013 | MM-013 | P0 | covered_in_repo | stale/already-covered | no execution because non-friend media delivery is already covered by the real sender-path recovery suite | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-013-plan.md |
| RC-001 | RC-001 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-001-plan.md |
| RC-003 | RC-003 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-003-plan.md |
| RY-001 | RY-001 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-001-plan.md |
| RY-003 | RY-003 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-003-plan.md |
| RY-007 | RY-007 | P0 | covered_in_repo | stale/already-covered | no execution because the existing partition-heal recovery proof is already direct enough | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-007-plan.md |
| RY-013 | RY-013 | P0 | needs_tests_only | accepted | relay-backed group replay now stores only opaque encrypted envelopes with the approved minimal wrapper | PREREQ-GROUP-OFFLINE-REPLAY | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-013-plan.md |
| RY-014 | RY-014 | P0 | needs_code_and_tests | accepted | encrypted replay now preserves quotes plus image, video, GIF, file, and audio payloads through drain and resume | PREREQ-GROUP-OFFLINE-REPLAY | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-014-plan.md |
| RY-015 | RY-015 | P0 | needs_code_and_tests | accepted | encrypted replay now respects remove, leave, and re-invite membership windows with rotated-epoch access boundaries | PREREQ-GROUP-OFFLINE-REPLAY | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-015-plan.md |
| RY-016 | RY-016 | P0 | needs_code_and_tests | accepted | encrypted replay now survives cursor drain, dedupe, retry, resume, reconnect, and partition-heal recovery without a degraded owner split | PREREQ-GROUP-OFFLINE-REPLAY | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-016-plan.md |
| SV-001 | SV-001 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-001-plan.md |
| SV-002 | SV-002 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-002-plan.md |
| SV-003 | SV-003 | P0 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-003-plan.md |
| CB-001 | CB-001 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-001-plan.md |
| CB-006 | CB-006 | P1 | covered_in_repo | accepted | create surface now proves no description field exists, create payload omits `description`, and later metadata remains edit-time only | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-006-plan.md |
| CB-007 | CB-007 | P1 | covered_in_repo | accepted | creator fallback now persists canonical `/mknoon/group/$groupId` and create-path tests pin stored topic parity | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-007-plan.md |
| DV-008 | DV-008 | P1 | covered_in_repo | accepted | voluntary leave now broadcasts a truthful self-removal event that remaining members persist as `left the group` history | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-008-plan.md |
| DV-009 | DV-009 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-009-plan.md |
| DV-011 | DV-011 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-011-plan.md |
| DV-012 | DV-012 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-012-plan.md |
| ID-002 | ID-002 | P1 | covered_in_repo | accepted | member-list identity now reuses `UserAvatar`, matching conversation rows | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-002-plan.md |
| ID-004 | ID-004 | P1 | unsupported_product_scope | stale/already-covered | no execution because the row is out of current product scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-004-plan.md |
| ID-008 | ID-008 | P1 | covered_in_repo | stale/already-covered | no execution because duplicate add/invite/replay coverage already closes the row-owned contract | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-008-plan.md |
| ID-009 | ID-009 | P1 | covered_in_repo | stale/already-covered | no execution because invite-avatar persistence and post-accept refresh coverage already closes the row-owned contract | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-009-plan.md |
| ID-010 | ID-010 | P1 | covered_in_repo | accepted | fallback identity now stays readable with `RingAvatar` on both group surfaces | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-010-plan.md |
| CX-001 | CX-001 | P1 | covered_in_repo | accepted | group messages now open the shared `MessageContextOverlay` with a selected-message preview and coherent action surface | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-001-plan.md |
| CX-002 | CX-002 | P1 | covered_in_repo | accepted | long-press reply now routes through the existing group quote-reply callback | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-002-plan.md |
| CX-003 | CX-003 | P1 | covered_in_repo | accepted | long-press copy now writes exact text, dismisses once, and shows copied feedback | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-003-plan.md |
| CX-004 | CX-004 | P1 | covered_in_repo | accepted | unsupported edit/delete actions stay hidden while the rest of the group context surface remains available | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-004-plan.md |
| CX-005 | CX-005 | P1 | covered_in_repo | accepted | local-only reply/copy actions remain available even when group reactions are unavailable | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-005-plan.md |
| CX-006 | CX-006 | P1 | covered_in_repo | accepted | the shared overlay preserves swipe-to-quote, reaction selection, and current row rendering contracts | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-006-plan.md |
| CX-007 | CX-007 | P1 | covered_in_repo | accepted | Orbit, Feed, and notification-anchor entry points now have direct long-press parity proof against the same shared group conversation surface | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-007-plan.md |
| UI-001 | UI-001 | P1 | covered_in_repo | accepted | current `LetterCard` host already renders one row shell; row-owned screen regressions now prove that contract directly | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UI-001-plan.md |
| UI-002 | UI-002 | P1 | covered_in_repo | accepted | row-owned screen regressions now prove reaction/media enrichment keeps the same single-shell host after re-render | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UI-002-plan.md |
| RX-001 | RX-001 | P1 | covered_in_repo | accepted | group chips now open a dedicated participant-inspection sheet with direct proof on shared group surfaces | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-001-plan.md |
| RX-002 | RX-002 | P1 | covered_in_repo | accepted | inline chip inspection is now non-destructive and long-press reaction bars remain the explicit mutation path | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-002-plan.md |
| RX-003 | RX-003 | P1 | covered_in_repo | accepted | inspection now resolves `You`, group-member usernames, and readable peer-id fallback from membership state | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-003-plan.md |
| RX-004 | RX-004 | P1 | covered_in_repo | accepted | Orbit and Feed entry tests now prove the same reaction-inspection contract on the shared group conversation surface | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-004-plan.md |
| RX-005 | RX-005 | P1 | covered_in_repo | accepted | inline Feed group chips now route to inspection on discussion and announcement-reader cards without diverging from the shared surface contract | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-005-plan.md |
| RX-006 | RX-006 | P1 | covered_in_repo | accepted | reaction recovery now has direct live, replay, and post-rotation proof across resume/rejoin flows | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-006-plan.md |
| MM-003 | MM-003 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-003-plan.md |
| MM-004 | MM-004 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-004-plan.md |
| MM-005 | MM-005 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-005-plan.md |
| MM-008 | MM-008 | P1 | covered_in_repo | stale/already-covered | no execution because pending publish-success ownership is already pinned by existing send regressions | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-008-plan.md |
| MM-009 | MM-009 | P1 | covered_in_repo | accepted | zero-peer plus inbox-fail sends now have direct retry-owner proof across unit and integration recovery paths | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-009-plan.md |
| MM-011 | MM-011 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-011-plan.md |
| MM-012 | MM-012 | P1 | covered_in_repo | accepted | active-recovery send rules now have direct discussion-allowed and announcement-blocked proof on the real sender path | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-012-plan.md |
| MM-014 | MM-014 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-014-plan.md |
| MM-015 | MM-015 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-015-plan.md |
| RC-002 | RC-002 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-002-plan.md |
| RC-004 | RC-004 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-004-plan.md |
| RC-005 | RC-005 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-005-plan.md |
| RC-006 | RC-006 | P1 | covered_in_repo | stale/already-covered | no execution because existing upsert/download/scroll tests already close the row-owned contract | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-006-plan.md |
| RC-007 | RC-007 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-007-plan.md |
| RC-008 | RC-008 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-008-plan.md |
| RC-009 | RC-009 | P1 | needs_code_and_tests | accepted | wrong-key, tampered-nonce, and malformed-payload failures now stay off the group message callback path while Flutter exposes owned diagnostic routing through `groupDiagnosticEventStream` | PREREQ-GROUP-PROOF-HARNESS | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-009-plan.md |
| RC-010 | RC-010 | P1 | needs_code_and_tests | accepted | high-burst dispatcher pressure and overflow now have an owned diagnostic contract instead of silent native drops | PREREQ-GROUP-DISPATCHER-OVERFLOW | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-010-plan.md |
| RY-002 | RY-002 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-002-plan.md |
| RY-004 | RY-004 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-004-plan.md |
| RY-005 | RY-005 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-005-plan.md |
| RY-006 | RY-006 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-006-plan.md |
| RY-008 | RY-008 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-008-plan.md |
| RY-009 | RY-009 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-009-plan.md |
| RY-010 | RY-010 | P1 | covered_in_repo | accepted | supported replay callers now carry full dependencies and invite-accept no longer drains in a silent no-`reactionRepo` state | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-010-plan.md |
| RY-011 | RY-011 | P1 | covered_in_repo | accepted | invite acceptance now replays backlog reactions in the same immediate catch-up window through the shipped accept flow | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-011-plan.md |
| RY-012 | RY-012 | P1 | covered_in_repo | accepted | bridgeError accept now has direct accepted-but-degraded proof plus later rejoin-and-drain closure without the invite row | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-012-plan.md |
| MD-001 | MD-001 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-001-plan.md |
| MD-002 | MD-002 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-002-plan.md |
| MD-003 | MD-003 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-003-plan.md |
| MD-004 | MD-004 | P1 | covered_in_repo | stale/already-covered | earlier spare iPhone 16e proof plus final primary-iOS deployed-relay rerun persisted on 2026-04-12 | integration_test/scripts/run_group_multi_device_real.dart; /tmp/md004_group_multi_device_real_rerun8_20260412.log; /private/tmp/acceptance_20260412/group_multi_device_real_primary_ios.log | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-004-plan.md |
| MD-005 | MD-005 | P1 | covered_in_repo | accepted | notification-anchor reaction parity now joins the existing Orbit and Feed surface proof on the shared conversation route | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-005-plan.md |
| MD-006 | MD-006 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-006-plan.md |
| SV-004 | SV-004 | P1 | needs_code_and_tests | accepted | replay/timestamp-tamper regressions now prove same-`messageId` replays cannot rewrite accepted rows after removal or dissolve cutoffs, and multi-page inbox replay with a tampered timestamp still stores one visible row | PREREQ-GROUP-PROOF-HARNESS | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-004-plan.md |
| SV-005 | SV-005 | P1 | needs_code_and_tests | accepted | wrong-key, tampered-nonce, tampered-ciphertext, and malformed-payload node regressions now prove no ghost `group_message:received` event escapes, while the existing bridge diagnostic stream keeps the rejection diagnosable on Flutter's owned path | PREREQ-GROUP-PROOF-HARNESS | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-005-plan.md |
| SV-006 | SV-006 | P1 | needs_code_and_tests | accepted | grace-window tests now prove previous-epoch traffic still emits `group_message:received` during grace and stays non-deliverable after expiry, with existing Flutter listener and receive-use-case tests covering the visible receive path for any accepted message event | PREREQ-GROUP-PROOF-HARNESS | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-006-plan.md |
| SV-007 | SV-007 | P1 | needs_code_and_tests | accepted | competing same-generation key updates now collapse to one stored key while existing higher-epoch and rotated-send proofs keep the final epoch converged and usable | PREREQ-GROUP-PROOF-HARNESS | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-007-plan.md |
| SV-008 | SV-008 | P1 | covered_in_repo | stale/already-covered | no execution because conflict-convergence and rotated re-invite coverage is already direct enough | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-008-plan.md |
| SV-010 | SV-010 | P1 | covered_in_repo | accepted | bridge helper and creator-path regressions now pin one canonical `/mknoon/group/...` contract across create, persistence, and join callers | CB-007 | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-010-plan.md |
| UX-001 | UX-001 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-001-plan.md |
| UX-002 | UX-002 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-002-plan.md |
| UX-009 | UX-009 | P1 | covered_in_repo | stale/already-covered | earlier spare iPhone 16e proof plus final primary-iOS deployed-relay rerun persisted on 2026-04-12 | integration_test/scripts/run_notification_open_ui_smoke.dart; /tmp/ux009_notification_open_ui_smoke_20260412_rerun16e_drive.log; /private/tmp/acceptance_20260412/notification_open_ui_primary_ios.log | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-009-plan.md |
| UX-010 | UX-010 | P1 | covered_in_repo | stale/already-covered | no execution because already covered | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-010-plan.md |
| ID-007 | ID-007 | P2 | unsupported_product_scope | stale/already-covered | no execution because the row is out of current product scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-007-plan.md |
| SV-009 | SV-009 | P2 | unsupported_product_scope | stale/already-covered | no execution because the row is out of current product scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-009-plan.md |
| SV-011 | SV-011 | P2 | needs_tests_only | accepted | existing group send/rejoin/drain/retry tests now pin stable begin/success/skip/error/timing flow-event names and required detail keys | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-011-plan.md |
| SV-012 | SV-012 | P2 | needs_tests_only | accepted | dispatcher overflow diagnostics now reach Flutter diagnostics and flow logs without remaining silent | PREREQ-GROUP-DISPATCHER-OVERFLOW | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-012-plan.md |
| UX-003 | UX-003 | P2 | unsupported_product_scope | stale/already-covered | no execution because the row is out of current product scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-003-plan.md |
| UX-004 | UX-004 | P2 | unsupported_product_scope | stale/already-covered | no execution because the row is out of current product scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-004-plan.md |
| UX-005 | UX-005 | P2 | unsupported_product_scope | stale/already-covered | no execution because the row is out of current product scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-005-plan.md |
| UX-006 | UX-006 | P2 | unsupported_product_scope | stale/already-covered | no execution because the row is out of current product scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-006-plan.md |
| UX-007 | UX-007 | P2 | unsupported_product_scope | stale/already-covered | no execution because the row is out of current product scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-007-plan.md |
| UX-008 | UX-008 | P2 | unsupported_product_scope | stale/already-covered | no execution because the row is out of current product scope | none | Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-008-plan.md |

## Ordered Session Breakdown

### Session PREREQ-GROUP-OFFLINE-REPLAY
- source row id: `shared prerequisite for RY-013, RY-014, RY-015, and RY-016`
- scenario title: Encrypted, membership-aware group offline replay exists end-to-end across Flutter, `go-mknoon/node`, and `go-relay-server`
- source section: Shared prerequisite
- row disposition: `shared_prerequisite`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-PREREQ-GROUP-OFFLINE-REPLAY-plan.md`
- exact scope: Replace plaintext relay-backed group replay storage with opaque encrypted envelopes plus the membership and epoch metadata needed for authorized replay, then land the cross-stack retrieval and Flutter drain compatibility that dependent row sessions need. This prerequisite session does not close any dependent source row by itself.
- execution ownership: accepted locally after degraded continuation tightened the replay contract in place, landed one shared opaque stored-envelope path for all current group inbox callers, and kept the same breakdown artifact as the controller source of truth
- proof ownership: repo-owned across Flutter, `go-mknoon/node`, and `go-relay-server`
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/groups/application/remove_group_reaction_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/core/bridge/bridge_group_helpers.dart`, `go-mknoon/bridge/bridge.go`, `go-mknoon/node/group_inbox.go`, `go-relay-server/inbox.go`, `go-relay-server/backend_memory.go`, `go-relay-server/backend_redis.go`
- existing tests or current proof: `group_offline_replay_envelope.dart` now materializes opaque encrypted replay envelopes on the Flutter side; the replay batch passed across `drain_group_offline_inbox_use_case_test.dart`, `send_group_message_use_case_test.dart`, `send_group_reaction_use_case_test.dart`, `remove_group_reaction_use_case_test.dart`, `accept_pending_group_invite_use_case_test.dart`, `dissolve_group_use_case_test.dart`, `group_info_wired_test.dart`, and `group_resume_recovery_test.dart`; `go-mknoon/node/group_inbox_test.go`, `go-relay-server/group_inbox_test.go`, and `go-relay-server/backend_redis_test.go` passed and now prove the opaque relay payload survives request marshaling plus shared-store and Redis cursor retrieval without exposing plaintext.
- likely missing tests: none for the shared prerequisite contract after the current Flutter, Go node, and relay gates passed
- likely named gates: Unit (Required), Integration (Required), Fake Network (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: update this breakdown prerequisite entry and `test-inventory.md`; dependent source rows `RY-013`, `RY-014`, `RY-015`, and `RY-016` stay open until their own row-owned sessions land

### Session PREREQ-GROUP-PROOF-HARNESS
- source row id: `shared prerequisite for RC-009, SV-004, SV-005, SV-006, and SV-007`
- scenario title: Shared tamper, replay, wrong-key, wrong-nonce, and key-rotation proof harnesses exist for group traffic
- source section: Shared prerequisite
- row disposition: `shared_prerequisite`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-PREREQ-GROUP-PROOF-HARNESS-plan.md`
- exact scope: Add deterministic raw-envelope and key-epoch harnesses that can drive tampered ciphertext, wrong-key, wrong-nonce, replay/reorder, previous-key grace, and concurrent rotation-race scenarios through the Go node and Flutter intake surfaces. This prerequisite session prepares the proof surface; it does not mark dependent source rows accepted.
- execution ownership: accepted locally with a dedicated shared Go test harness plus targeted rewiring of the existing decryption-failure and grace suites
- proof ownership: repo-owned across Flutter and `go-mknoon/node`
- likely code-entry files: `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/group_inbox_test.go`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`
- existing tests or current proof: `go-mknoon/node/group_security_harness_test.go` now provides shared event-wait, raw publish, local-node connect, raw-envelope mutation, and grace-fixture helpers; `pubsub_decryption_failure_test.go` and `pubsub_key_rotation_grace_test.go` now consume those helpers, and the targeted Go node gate passed under local continuation.
- likely missing tests: replay/reorder injectors and the row-owned acceptance assertions for `RC-009`, `SV-004`, `SV-005`, `SV-006`, and `SV-007` still belong to those dependent sessions
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: update this breakdown prerequisite entry and `test-inventory.md`; dependent source rows `RC-009`, `SV-004`, `SV-005`, `SV-006`, and `SV-007` stay open until their own row-owned sessions land

### Session PREREQ-GROUP-DISPATCHER-OVERFLOW
- source row id: `shared prerequisite for RC-010 and SV-012`
- scenario title: Dispatcher overflow observability and high-burst proof exist for group receive paths
- source section: Shared prerequisite
- row disposition: `shared_prerequisite`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-PREREQ-GROUP-DISPATCHER-OVERFLOW-plan.md`
- exact scope: Surface native dispatcher queue-depth and drop diagnostics through owned observability contracts, then add a high-burst proof harness that can drive overflow and near-overflow conditions into the Flutter-facing receive path. This prerequisite session unblocks the dependent row-owned sessions but does not close them.
- execution ownership: accepted locally after the dispatcher now emits coalesced pressure and overflow diagnostics and Flutter routes those diagnostics into owned monitoring surfaces
- proof ownership: repo-owned across Flutter and `go-mknoon/node`
- likely code-entry files: `go-mknoon/node/event_dispatcher.go`, `go-mknoon/node/node.go`, `go-mknoon/node/pubsub_test.go`, `lib/core/utils/flow_event_emitter.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `test/core/utils/flow_event_emitter_test.dart`
- existing tests or current proof: `go-mknoon/node/event_dispatcher.go` now emits `group:dispatcher_pressure` and `group:dispatcher_overflow`; `go-mknoon/node/node_test.go` passed and now proves those diagnostics carry queue-depth, dropped-count, and last-event data under burst load; `go_bridge_client_test.dart` passed and now proves `group:dispatcher_overflow` reaches Flutter diagnostics and flow logs without invoking the group message callback.
- likely missing tests: none for the shared prerequisite contract after the current Go and Flutter gates passed
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: update this breakdown prerequisite entry and `test-inventory.md`; dependent source rows `RC-010` and `SV-012` stay open until their own row-owned sessions land

### Session CB-002
- source row id: `CB-002`
- scenario title: Create blocks over-limit selection before any local or bridge state is created
- source section: Create, Bootstrap, and Configuration Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-002-plan.md`
- exact scope: Preserve the current repo truth for source row CB-002 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/update_group_metadata_use_case.dart`, `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- existing tests or current proof: The test inventory shows limit enforcement for create and add paths, and the C4 create flow calls out pre-limit checking before bridge create. Current repo references: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/presentation/create_group_picker_wired_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CB-002; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CB-003
- source row id: `CB-003`
- scenario title: Partial per-member add failure during create yields a truthful successful subset only
- source section: Create, Bootstrap, and Configuration Truth
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-003-plan.md`
- exact scope: Add row-specific regression proof for source row CB-003 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/update_group_metadata_use_case.dart`, `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- existing tests or current proof: Current repo coverage now includes a direct failure-injection regression proving the truthful successful subset contract for this row. Current repo references: `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/presentation/create_group_picker_wired_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none for the row-owned contract after the current create-with-members regression landed
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CB-003; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CB-004
- source row id: `CB-004`
- scenario title: Create-time invite degradation is explicit when node is stopped, recipient has no ML-KEM key, or direct send fails
- source section: Create, Bootstrap, and Configuration Truth
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-004-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row CB-004 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/update_group_metadata_use_case.dart`, `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- existing tests or current proof: Current repo coverage now includes direct create-time invite degradation proof and explicit UI warning feedback. Repo references: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/presentation/screens/create_group_picker_wired.dart`, `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/send_group_invite_use_case_test.dart`, `test/features/groups/presentation/create_group_picker_wired_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none for the row-owned contract after the current create-time degradation warnings landed
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CB-004; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CB-005
- source row id: `CB-005`
- scenario title: Post-create `group:updateConfig` or `members_added` publish failure does not leave ghost local membership
- source section: Create, Bootstrap, and Configuration Truth
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-005-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row CB-005 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/update_group_metadata_use_case.dart`, `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- existing tests or current proof: Current repo coverage now proves config-sync rollback and honest publish degradation handling for create/add-member flows. Repo references: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/presentation/screens/contact_picker_wired.dart`, `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/presentation/contact_picker_wired_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none for the row-owned contract after the rollback and warning regressions landed
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CB-005; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CB-008
- source row id: `CB-008`
- scenario title: Group create never reports success into a locally keyless state
- source section: Create, Bootstrap, and Configuration Truth
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-008-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row CB-008 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/update_group_metadata_use_case.dart`, `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- existing tests or current proof: Current repo coverage now proves keyless create rolls back the partially created group and fails honestly. Repo references: `lib/features/groups/application/create_group_use_case.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none for the row-owned contract after the keyless-create rollback regression landed
- likely named gates: Unit (Required), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CB-008; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-001
- source row id: `DV-001`
- scenario title: Create discussion group successfully
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-001-plan.md`
- exact scope: Preserve the current repo truth for source row DV-001 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: Strong current create coverage is called out in the audit and test inventory. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Recommended), Integration (Required), Smoke (Required), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-001; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-002
- source row id: `DV-002`
- scenario title: Create announcement group successfully with admin-only compose
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-002-plan.md`
- exact scope: Preserve the current repo truth for source row DV-002 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: Covered by announcement-path tests and the current matrix. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Smoke (Required), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-002; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-003
- source row id: `DV-003`
- scenario title: Adding members shows immediate feedback and a durable in-chat add-members event
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-003-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row DV-003 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: Current repo coverage now proves durable add-member history across listener, picker, and recipient surfaces. Repo references: `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/contact_picker_wired.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/presentation/contact_picker_wired_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none for the row-owned contract after durable `members_added` persistence and recipient smoke coverage landed
- likely named gates: Unit (Required), Integration (Required), Smoke (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-003; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-004
- source row id: `DV-004`
- scenario title: Accepting a pending invite creates a durable join / acceptance event visible to existing members
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-004-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row DV-004 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: Current repo coverage now proves durable invite-accept join history across accept, listener, and end-to-end invite paths. Repo references: `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none for the row-owned contract after durable `member_joined` publish/persist coverage landed
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-004; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-005
- source row id: `DV-005`
- scenario title: Invite decline and expiry leave no ghost membership or ghost access
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-005-plan.md`
- exact scope: Preserve the current repo truth for source row DV-005 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: Already covered by listener, accept/decline, and invite-round-trip tests. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-005; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-006
- source row id: `DV-006`
- scenario title: Removing a member updates lists and creates a durable removal event for remaining members
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-006-plan.md`
- exact scope: Preserve the current repo truth for source row DV-006 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: Current repo coverage already proves the removal path and recipient-side timeline persistence. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Recommended), Integration (Required), Smoke (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-006; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-007
- source row id: `DV-007`
- scenario title: Removed member converges to removed state after offline reconnect
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-007-plan.md`
- exact scope: Preserve the current repo truth for source row DV-007 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: Explicitly covered in replay/recovery and membership smoke coverage. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Required), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-007; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-010
- source row id: `DV-010`
- scenario title: Blocked, unknown, or sender-mismatch invites are rejected without ghost pending or joined state
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-010-plan.md`
- exact scope: Preserve the current repo truth for source row DV-010 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: The C4 invite flow and test inventory both document blocked-sender, unknown-sender, and sender-mismatch guards. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-010; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-013
- source row id: `DV-013`
- scenario title: Partial invite fan-out result is explicit per recipient
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-013-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row DV-013 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: Current repo coverage now pins per-recipient batch invite outcomes and explicit user-visible warning text for create and add-member flows. Repo references: `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/presentation/screens/contact_picker_wired.dart`, `test/features/groups/application/send_group_invite_use_case_test.dart`, `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/presentation/contact_picker_wired_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none for the row-owned contract after the explicit batch-result regressions landed
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-013; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-014
- source row id: `DV-014`
- scenario title: Batch add with no latest group key is explicit and does not silently look like completed onboarding
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-014-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row DV-014 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: Current repo coverage now pins the explicit no-latest-key warning contract for create and add-member flows instead of silently presenting normal onboarding. Repo references: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/presentation/screens/contact_picker_wired.dart`, `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/presentation/create_group_picker_wired_test.dart`, `test/features/groups/presentation/contact_picker_wired_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none for the row-owned contract after the explicit no-key warning regressions landed
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-014; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-015
- source row id: `DV-015`
- scenario title: Remove, rotate, and re-invite gives the rejoined member the correct rotated epoch
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-015-plan.md`
- exact scope: Preserve the current repo truth for source row DV-015 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: The invite-round-trip integration coverage already includes this path. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Recommended), Integration (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-015; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-016
- source row id: `DV-016`
- scenario title: New-member history boundary stays future-only except for the explicitly allowed post-join replay contract
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-016-plan.md`
- exact scope: Preserve the current repo truth for source row DV-016 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: Called out directly by the invite-round-trip integration tests. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-016; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session ID-001
- source row id: `ID-001`
- scenario title: Creator/admin identity resolves to username instead of raw peer ID when a username exists
- source section: Identity, Roles, Avatars, and Mixed-Social-Graph Behavior
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-001-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row ID-001 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/presentation/group_info_wired_test.dart`
- existing tests or current proof: Current repo coverage now proves the creator/admin username is persisted at group creation, carried into generated `groupConfig`, and rendered as `Admin` for non-self viewers instead of falling back to `peer-admin`. Repo references: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/create_group_with_members_use_case.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/presentation/group_info_wired_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none for the row-owned creator-identity contract after the persistence and member-list regressions landed
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row ID-001; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session ID-003
- source row id: `ID-003`
- scenario title: Once membership exists, non-friend members can still read and write in the same discussion group
- source section: Identity, Roles, Avatars, and Mixed-Social-Graph Behavior
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-003-plan.md`
- exact scope: Add row-specific regression proof for source row ID-003 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/groups/presentation/widgets/group_avatar.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/home/application/identity_avatar_resolver.dart`, `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/groups/application/group_avatar_storage.dart`
- existing tests or current proof: Existing repo coverage is already direct enough: `group_messaging_smoke_test.dart` proves non-friend member fan-out, `group_test_user.dart` avoids contact-repo shortcuts, and `send_group_message_use_case.dart` routes by stored group membership. Current repo references: `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/shared/fakes/group_test_user.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none; current direct non-contact membership-driven coverage is sufficient
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row ID-003; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session ID-005
- source row id: `ID-005`
- scenario title: Admin promotion and demotion update permissions, badges, and visible timeline history consistently
- source section: Identity, Roles, Avatars, and Mixed-Social-Graph Behavior
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-005-plan.md`
- exact scope: Preserve the current repo truth for source row ID-005 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/groups/presentation/widgets/group_avatar.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/home/application/identity_avatar_resolver.dart`, `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/groups/application/group_avatar_storage.dart`
- existing tests or current proof: Explicitly covered by `group_info_wired_test.dart` and listener coverage per the audit. Current repo references: `group_info_wired_test.dart`, `test/features/groups/presentation/group_info_wired_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/application/group_avatar_storage_test.dart`, `test/features/groups/integration/group_multi_device_convergence_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row ID-005; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session ID-006
- source row id: `ID-006`
- scenario title: Sole-admin leave stays blocked until a valid admin state exists
- source section: Identity, Roles, Avatars, and Mixed-Social-Graph Behavior
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-006-plan.md`
- exact scope: Preserve the current repo truth for source row ID-006 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/groups/presentation/widgets/group_avatar.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/home/application/identity_avatar_resolver.dart`, `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/groups/application/group_avatar_storage.dart`
- existing tests or current proof: Membership smoke and leave-group coverage already prove the sole-admin guard. Current repo references: `test/features/groups/presentation/group_info_wired_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/application/group_avatar_storage_test.dart`, `test/features/groups/integration/group_multi_device_convergence_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row ID-006; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-001
- source row id: `MM-001`
- scenario title: Discussion members can send text, media, replies, and reactions to all current members
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-001-plan.md`
- exact scope: Preserve the current repo truth for source row MM-001 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: Strong current coverage exists across send, receive, reaction, and smoke tests. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Recommended), Integration (Required), Smoke (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-001; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-002
- source row id: `MM-002`
- scenario title: Announcement groups enforce admin-only compose while readers still see and react
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-002-plan.md`
- exact scope: Preserve the current repo truth for source row MM-002 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: This is one of the strongest current shipped contracts. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Smoke (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-002; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-006
- source row id: `MM-006`
- scenario title: The sender-facing state machine stays honest across publish success, publish timeout, no-peer fallback, inbox failure, and retry
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-006-plan.md`
- exact scope: Preserve the current repo truth for source row MM-006 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: The send use-case matrix is already heavily covered in tests. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Smoke (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-006; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-007
- source row id: `MM-007`
- scenario title: Publish timeout plus inbox success remains successful in UI and storage
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-007-plan.md`
- exact scope: Preserve the current repo truth for source row MM-007 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: Explicitly covered in the send use case and wired UI tests. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-007; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-010
- source row id: `MM-010`
- scenario title: Discussion and announcement sends survive background, route unmount, and zero-peer fallback with honest final status
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-010-plan.md`
- exact scope: Add row-specific regression proof for source row MM-010 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: Existing repo coverage is already direct enough: `group_conversation_wired_bg_task_test.dart` covers discussion and announcement sends across route unmount, lock, and zero-peer fallback branches with honest final status. Current repo references: `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none; current bg-task and zero-peer coverage is sufficient
- likely named gates: Unit (Required), Integration (Required), Smoke (Required), Fake Network (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-010; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-013
- source row id: `MM-013`
- scenario title: Non-friend member media delivery works the same as friend media delivery once membership exists
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-013-plan.md`
- exact scope: Add row-specific regression proof for source row MM-013 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: Existing repo coverage is already direct enough: `group_resume_recovery_test.dart` exercises non-friend media recovery through the real sender path, and the shared harness keeps group transport independent from friendship edges. Current repo references: `test/features/groups/integration/group_resume_recovery_test.dart`, `test/shared/fakes/group_test_user.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none; current non-friend media delivery coverage is sufficient
- likely named gates: Unit (Recommended), Integration (Required), Smoke (Recommended), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-013; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RC-001
- source row id: `RC-001`
- scenario title: Live receive plus replay dedupe prevents duplicate visible rows when pubsub and inbox both deliver the same message
- source section: Receive, Rendering, Notification, and Conversation Integrity
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-001-plan.md`
- exact scope: Preserve the current repo truth for source row RC-001 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- existing tests or current proof: Strongly covered in handle-incoming and resume-recovery tests. Current repo references: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/notifications/notification_route_target_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended), Fake Network (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RC-001; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RC-003
- source row id: `RC-003`
- scenario title: Unknown-group, unauthorized-sender, post-removal, and post-dissolve messages do not appear beyond allowed cutoffs
- source section: Receive, Rendering, Notification, and Conversation Integrity
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-003-plan.md`
- exact scope: Preserve the current repo truth for source row RC-003 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- existing tests or current proof: The inventory shows direct cutoff and dissolve-boundary coverage. Current repo references: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/notifications/notification_route_target_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RC-003; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-001
- source row id: `RY-001`
- scenario title: Cold-start rejoin and drain re-establish live delivery exactly once
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-001-plan.md`
- exact scope: Preserve the current repo truth for source row RY-001 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: Startup-rejoin smoke coverage already exists. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Recommended), Integration (Required), Smoke (Recommended), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-001; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-003
- source row id: `RY-003`
- scenario title: Paused / hidden lifecycle pre-commits `sending` rows to failed so later recovery can pick them up
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-003-plan.md`
- exact scope: Preserve the current repo truth for source row RY-003 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: `handleAppPaused` group tests explicitly cover this preventive reliability hook. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-003; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-007
- source row id: `RY-007`
- scenario title: Partition heal and delayed delivery converge without duplicates and resume live delivery
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-007-plan.md`
- exact scope: Preserve the current repo truth for source row RY-007 only and keep its existing partition-heal proof attached to this row without inventing a broader device-lab requirement.
- execution ownership: no execution because the existing proof is already direct enough
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: `group_resume_recovery_test.dart` already has a direct partition-heal regression proving the partitioned member misses split-window live delivery, drains stored backlog in cursor order after heal, and resumes later live delivery without duplicate visible rows. Supporting recovery coverage remains in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, and `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended), Fake Network (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-007; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-013
- source row id: `RY-013`
- scenario title: Offline group replay payloads stored on the relay are opaque to relay operators
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `needs_tests_only`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-013-plan.md`
- exact scope: After encrypted replay lands, prove the relay stores only opaque group replay payloads plus the intentionally approved minimal wrapper and never exposes plaintext message or membership content to relay operators.
- execution ownership: accepted locally after the replay prerequisite landed and the relay-storage contract was pinned directly in Go node and relay tests
- proof ownership: repo-owned across `go-mknoon/node` and `go-relay-server`
- likely code-entry files: `go-mknoon/node/group_inbox.go`, `go-mknoon/node/group_inbox_test.go`, `go-relay-server/group_inbox_store.go`, `go-relay-server/group_inbox_test.go`
- existing tests or current proof: `group_offline_replay_envelope.dart` now stores only the approved replay wrapper plus ciphertext and nonce, `go-mknoon/node/group_inbox_test.go` proves the request marshaling path preserves that opaque envelope exactly, and `go-relay-server/group_inbox_test.go` plus `backend_redis_test.go` prove shared-store and Redis-backed retrieval preserve the same opaque payload across cursor pages.
- likely missing tests: none for the row-owned opacity contract after the current Go and relay gates passed
- likely named gates: Unit (Required), Integration (Required), Fake Network (Required)
- dependency on earlier sessions: `PREREQ-GROUP-OFFLINE-REPLAY`
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-013; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-014
- source row id: `RY-014`
- scenario title: Encrypted replay remains seamless for text, replies, image, video, GIF/file, and recorded voice
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `needs_code_and_tests`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-014-plan.md`
- exact scope: Close content-type parity on the encrypted replay path for text, quote replies, image, video, GIF/file attachments, and recorded voice without regressing current rendering, download, or retry behavior.
- execution ownership: accepted locally with one shared encrypted replay envelope path plus direct drain and resume parity assertions for the supported content classes
- proof ownership: repo-owned across Flutter, `go-mknoon/node`, and `go-relay-server`
- likely code-entry files: `go-mknoon/node/group_inbox.go`, `go-relay-server/group_inbox_store.go`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`
- existing tests or current proof: `drain_group_offline_inbox_use_case_test.dart` now proves encrypted replay preserves `quotedMessageId` plus image, video, GIF, file, and audio attachments through the real drain path, and `group_resume_recovery_test.dart` keeps missed announcement replay, real voice delivery, and post-rotation delivery readable after resume; the replay batch rerun passed with the mixed-media encrypted drain regression included.
- likely missing tests: none for the row-owned content-parity contract after the current replay batch passed
- likely named gates: Unit (Required), Integration (Required), Smoke (Required), Fake Network (Required), 3-Party E2E (Required)
- dependency on earlier sessions: `PREREQ-GROUP-OFFLINE-REPLAY`
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-014; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-015
- source row id: `RY-015`
- scenario title: Encrypted replay respects add/remove/leave membership boundaries
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `needs_code_and_tests`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-015-plan.md`
- exact scope: Close membership-window enforcement for encrypted replay so newly added members cannot decrypt unauthorized older backlog and removed or departed peers cannot decrypt newer replay beyond the valid cutoff or key epoch.
- execution ownership: accepted locally with replay-aware membership cutoffs, durable leave publication, and rotated re-invite proofs
- proof ownership: repo-owned across Flutter, `go-mknoon/node`, and `go-relay-server`
- likely code-entry files: `go-mknoon/node/group_inbox.go`, `go-mknoon/node/group_inbox_test.go`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`
- existing tests or current proof: `group_resume_recovery_test.dart` now proves removed offline members drain the replayed removal, lose access, and cannot send after resume while remaining members keep only the before-cutoff backlog; `group_info_wired_test.dart` now proves leave emits a durable left-the-group event before local cleanup; `invite_round_trip_test.dart` passed and now proves remove -> rotate -> re-invite plus offline re-invite recovery on the rotated epoch only.
- likely missing tests: none for the row-owned membership-window contract after the current integration and wired gates passed
- likely named gates: Unit (Required), Integration (Required), Fake Network (Required), 3-Party E2E (Required)
- dependency on earlier sessions: `PREREQ-GROUP-OFFLINE-REPLAY`
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-015; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-016
- source row id: `RY-016`
- scenario title: Encrypted replay remains reliable through retry, resume, cursor drain, reconnect, and dedupe
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `needs_code_and_tests`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-016-plan.md`
- exact scope: Close parity between encrypted replay and the current plaintext recovery stack across retry, resume, cursor pagination, reconnect, live-plus-replay dedupe, and exactly-once backlog application.
- execution ownership: accepted locally after the encrypted replay path passed the existing recovery-owner suites plus the replay-specific partition, cursor, retry, and dedupe regressions
- proof ownership: repo-owned across Flutter, `go-mknoon/node`, and `go-relay-server`
- likely code-entry files: `go-mknoon/node/group_inbox.go`, `go-mknoon/node/group_inbox_test.go`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`
- existing tests or current proof: `drain_group_offline_inbox_use_case_test.dart` now proves cursor continuation and encrypted replay drain behavior directly, `group_resume_recovery_test.dart` now proves multi-page replay with tampered timestamps still stores one row, partition heal resumes without duplicates, and zero-peer inbox failure stays on the failed-message retry owner, and the current-session reruns of `rejoin_group_topics_use_case_test.dart`, `retry_failed_group_inbox_stores_use_case_test.dart`, `handle_app_resumed_group_recovery_test.dart`, and `handle_app_resumed_group_inbox_retry_test.dart` keep the rejoin and retry owners pinned.
- likely missing tests: none for the row-owned reliability contract after the current recovery and lifecycle gates passed
- likely named gates: Unit (Required), Integration (Required), Smoke (Recommended), Fake Network (Required), 3-Party E2E (Required)
- dependency on earlier sessions: `PREREQ-GROUP-OFFLINE-REPLAY`
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-016; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-001
- source row id: `SV-001`
- scenario title: Only current members can publish discussion messages; unauthorized peers do not create visible rows
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-001-plan.md`
- exact scope: Preserve the current repo truth for source row SV-001 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `lib/core/utils/push_diagnostics_logger.dart`
- existing tests or current proof: The validator and membership-smoke coverage together already prove the membership gate story. Current repo references: `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/announcement_happy_path_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/domain/models/group_invite_payload_test.dart`, `test/features/groups/domain/models/group_message_payload_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-001; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-002
- source row id: `SV-002`
- scenario title: Announcement readers cannot bypass write restrictions via stale callbacks or raw publish
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-002-plan.md`
- exact scope: Preserve the current repo truth for source row SV-002 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `lib/core/utils/push_diagnostics_logger.dart`
- existing tests or current proof: The current tests already cover read-only mode plus stale callback protection. Current repo references: `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/announcement_happy_path_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/domain/models/group_invite_payload_test.dart`, `test/features/groups/domain/models/group_message_payload_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-002; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-003
- source row id: `SV-003`
- scenario title: Removed members are only accepted for delayed pre-cutoff traffic, not post-cutoff traffic
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-003-plan.md`
- exact scope: Preserve the current repo truth for source row SV-003 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `lib/core/utils/push_diagnostics_logger.dart`
- existing tests or current proof: Directly covered in incoming-message and resume-recovery tests. Current repo references: `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/announcement_happy_path_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/domain/models/group_invite_payload_test.dart`, `test/features/groups/domain/models/group_message_payload_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-003; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CB-001
- source row id: `CB-001`
- scenario title: Blank-name create auto-generates a stable, readable group name
- source section: Create, Bootstrap, and Configuration Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-001-plan.md`
- exact scope: Preserve the current repo truth for source row CB-001 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/update_group_metadata_use_case.dart`, `lib/features/groups/application/group_config_payload.dart`, `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- existing tests or current proof: Covered by `create_group_with_members_use_case_test.dart` auto-name cases and create-picker coverage in `test-inventory.md`. Current repo references: `create_group_with_members_use_case_test.dart`, `test-inventory.md`, `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/presentation/create_group_picker_wired_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CB-001; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CB-006
- source row id: `CB-006`
- scenario title: Create-time description support is honest
- source section: Create, Bootstrap, and Configuration Truth
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-006-plan.md`
- exact scope: Pin the shipped no-create-description contract across the create picker, create use cases, and later metadata surfaces without broadening this rollout into a new create-time description feature.
- execution ownership: widget and flow regressions landed locally; no product-scope broadening was introduced
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/create_group_picker_screen.dart`, `lib/features/groups/presentation/screens/create_group_picker_wired.dart`, `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`
- existing tests or current proof: `test/features/groups/presentation/widgets/group_name_panel_test.dart` now proves the shipped create surface exposes only the name field, `test/features/groups/presentation/create_group_picker_wired_test.dart` proves the create payload omits `description`, and `test/features/groups/presentation/group_info_wired_test.dart` continues to cover later edit-time description updates.
- likely missing tests: none; the row-owned create-surface honesty contract is now directly pinned
- likely named gates: Unit (Required), Integration (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CB-006; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CB-007
- source row id: `CB-007`
- scenario title: Persisted topic namespace matches the real `/mknoon/group/{groupId}` namespace
- source section: Create, Bootstrap, and Configuration Truth
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CB-007-plan.md`
- exact scope: Replace the creator-side `group-$groupId` fallback with the canonical `/mknoon/group/$groupId` namespace or an equivalent Go-returned `topicName`, then prove create, persistence, and rejoin flows stay aligned with the real topic the node joined.
- execution ownership: code and tests landed locally; creator fallback now persists the canonical namespace instead of `group-$groupId`
- proof ownership: repo-owned across Flutter and the `go-mknoon/node` topic contract
- likely code-entry files: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `go-mknoon/node/config.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- existing tests or current proof: `lib/features/groups/application/create_group_use_case.dart` now falls back to `/mknoon/group/$groupId`, `test/features/groups/application/create_group_use_case_test.dart` proves creator-path persistence stays on that namespace when the bridge omits `topicName`, and `test/features/groups/application/rejoin_group_topics_use_case_test.dart` already proves rejoin callers consume the stored `topicName`.
- likely missing tests: none required for the row-owned creator-path drift contract; rejoin callers already consume persisted topic state
- likely named gates: Unit (Required), Integration (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CB-007; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-008
- source row id: `DV-008`
- scenario title: Voluntary leave creates a durable `X left the group` event visible to remaining members
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-008-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row DV-008 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: Current repo coverage now proves truthful voluntary-leave history for local and remaining-member surfaces, including the non-admin self-removal listener path. Repo references: `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `test/features/groups/presentation/group_info_wired_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/shared/fakes/group_test_user.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none for the row-owned contract after truthful self-removal broadcast and remaining-member persistence landed
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-008; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-009
- source row id: `DV-009`
- scenario title: Duplicate invite preview for the same group replaces the earlier pending row instead of duplicating cards
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-009-plan.md`
- exact scope: Preserve the current repo truth for source row DV-009 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: `PendingGroupInviteRepository` upserts by `group_id`; the listener test inventory already calls this out. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-009; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-011
- source row id: `DV-011`
- scenario title: Pending-invite route target opens the review surface until the group is actually joined
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-011-plan.md`
- exact scope: Preserve the current repo truth for source row DV-011 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: `resolveGroupNotificationRouteTarget()` and the current C4 invite doc explicitly define this route behavior. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Recommended), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-011; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session DV-012
- source row id: `DV-012`
- scenario title: Accepting or declining an invite on one device does not incorrectly clear the sibling device pending row
- source section: Membership Visibility and Invite Lifecycle
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-DV-012-plan.md`
- exact scope: Preserve the current repo truth for source row DV-012 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_membership_timeline_message.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
- existing tests or current proof: The accept/decline tests explicitly cover sibling-device pending-row independence. Current repo references: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row DV-012; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session ID-002
- source row id: `ID-002`
- scenario title: Member list and conversation surfaces show consistent participant identity, including avatars, for current members
- source section: Identity, Roles, Avatars, and Mixed-Social-Graph Behavior
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-002-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row ID-002 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/conversation/presentation/widgets/letter_card.dart`, `test/features/groups/presentation/group_info_screen_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`
- existing tests or current proof: Current repo coverage now proves member-list and conversation surfaces render participant identity with the same shared avatar component family. Repo references: `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/conversation/presentation/widgets/letter_card.dart`, `test/features/groups/presentation/group_info_screen_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none for the row-owned cross-surface identity contract after the shared-avatar regression landed
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row ID-002; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session ID-004
- source row id: `ID-004`
- scenario title: Supported onboarding path exists for non-friend participants when product scope says mixed-social-graph groups are allowed
- source section: Identity, Roles, Avatars, and Mixed-Social-Graph Behavior
- row disposition: `unsupported_product_scope`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-004-plan.md`
- exact scope: Keep source row ID-004 explicitly out of implementation scope while non-friend onboarding stays unshipped; only row-specific truth-alignment and scope proof belong here.
- execution ownership: no execution because the row is out of current product scope
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/create_group_picker_wired.dart`, `lib/features/groups/presentation/screens/contact_picker_wired.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`, `test/features/groups/presentation/create_group_picker_wired_test.dart`, `test/features/groups/presentation/contact_picker_wired_test.dart`
- existing tests or current proof: Current repo scope keeps non-friend onboarding unsupported: create and add-member flows load only active contacts, and invite intake rejects unknown senders instead of creating pending or joined state. Repo references: `lib/features/groups/presentation/screens/create_group_picker_wired.dart`, `lib/features/groups/presentation/screens/contact_picker_wired.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`, `test/features/groups/presentation/create_group_picker_wired_test.dart`, `test/features/groups/presentation/contact_picker_wired_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`
- likely missing tests: none for the current out-of-scope contract; broader onboarding proof belongs only after product scope changes
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row ID-004; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session ID-008
- source row id: `ID-008`
- scenario title: Duplicate re-add, duplicate invite, or stale membership replay does not create duplicate member rows or duplicate timeline spam
- source section: Identity, Roles, Avatars, and Mixed-Social-Graph Behavior
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-008-plan.md`
- exact scope: Add row-specific regression proof for source row ID-008 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/groups/presentation/widgets/group_avatar.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/home/application/identity_avatar_resolver.dart`, `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/groups/application/group_avatar_storage.dart`
- existing tests or current proof: Existing repo coverage already closes the duplicate membership/timeline contract through duplicate re-add, duplicate invite, and stale membership replay regressions. Current repo references: `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none; current duplicate add/invite/replay coverage is sufficient
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row ID-008; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session ID-009
- source row id: `ID-009`
- scenario title: Invite-carried avatar metadata persists and resolves cleanly after accept
- source section: Identity, Roles, Avatars, and Mixed-Social-Graph Behavior
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-009-plan.md`
- exact scope: Add row-specific regression proof for source row ID-009 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/groups/presentation/widgets/group_avatar.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/home/application/identity_avatar_resolver.dart`, `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/groups/application/group_avatar_storage.dart`
- existing tests or current proof: Existing repo coverage already closes the row-owned contract: invite-avatar persistence is pinned in `handle_incoming_group_invite_use_case_test.dart`, and the accept path reuses the same materialized payload before the feed-side avatar refresh assertions consume it. Current repo references: `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `test/features/feed/presentation/screens/feed_wired_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none; current invite-avatar persistence and refresh coverage is sufficient
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row ID-009; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session ID-010
- source row id: `ID-010`
- scenario title: Non-friend fallback identity and avatar remain readable when full avatar sharing is unavailable
- source section: Identity, Roles, Avatars, and Mixed-Social-Graph Behavior
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-010-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row ID-010 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/home/presentation/widgets/ring_avatar.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/conversation/presentation/widgets/letter_card.dart`, `test/features/groups/presentation/group_info_screen_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`
- existing tests or current proof: Current repo coverage now proves both group surfaces keep readable participant names and fall back to deterministic `RingAvatar` when no profile photo is available. Repo references: `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/home/presentation/widgets/ring_avatar.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/conversation/presentation/widgets/letter_card.dart`, `test/features/groups/presentation/group_info_screen_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none for the row-owned fallback identity contract after the readable ring-avatar regressions landed
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row ID-010; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CX-001
- source row id: `CX-001`
- scenario title: Long-pressing a supported group message opens one coherent context surface, not only a detached reaction bar
- source section: Long-Press Context Actions and Overlay Parity
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-001-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row CX-001 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/conversation/presentation/widgets/message_context_overlay.dart`, `lib/features/conversation/presentation/widgets/reaction_display.dart`
- existing tests or current proof: `group_conversation_screen.dart` now routes group long-press through the shared `MessageContextOverlay`, and `group_conversation_screen_test.dart` directly proves the selected-message preview, reaction bar, reply/copy actions, and single coherent overlay surface.
- likely missing tests: none for the row-owned contract after the shared group overlay proof landed
- likely named gates: Unit (Recommended), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CX-001; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CX-002
- source row id: `CX-002`
- scenario title: Group long-press reply entry reaches the existing quote-reply path for supported messages
- source section: Long-Press Context Actions and Overlay Parity
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-002-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row CX-002 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/conversation/presentation/widgets/message_context_overlay.dart`, `lib/features/conversation/presentation/widgets/reaction_display.dart`
- existing tests or current proof: `group_conversation_screen_test.dart` now directly proves the long-press reply action enters the existing group quote-reply callback with the correct message id.
- likely missing tests: none for the row-owned contract after the direct long-press reply regression landed
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CX-002; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CX-003
- source row id: `CX-003`
- scenario title: Group long-press copy action copies exact text for supported rows and dismisses cleanly
- source section: Long-Press Context Actions and Overlay Parity
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-003-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row CX-003 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/conversation/presentation/widgets/message_context_overlay.dart`, `lib/features/conversation/presentation/widgets/reaction_display.dart`
- existing tests or current proof: `group_conversation_screen_test.dart` now directly proves long-press copy writes exact multiline/emoji text to the clipboard, dismisses the overlay, and shows copied feedback.
- likely missing tests: none for the row-owned contract after the direct copy regression landed
- likely named gates: Unit (Required), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CX-003; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CX-004
- source row id: `CX-004`
- scenario title: Unsupported group edit/delete actions stay honestly hidden without blocking the rest of the context surface
- source section: Long-Press Context Actions and Overlay Parity
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-004-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row CX-004 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/conversation/presentation/widgets/message_context_overlay.dart`, `lib/features/conversation/presentation/widgets/reaction_display.dart`
- existing tests or current proof: the shared group overlay now opens without exposing unsupported edit/delete actions, and `group_conversation_screen_test.dart` proves reply/copy remain available while those actions stay hidden.
- likely missing tests: none for the row-owned contract after the honest-hidden-action regression landed
- likely named gates: Unit (Required), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CX-004; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CX-005
- source row id: `CX-005`
- scenario title: Local-only long-press actions remain available even when reactions are unavailable
- source section: Long-Press Context Actions and Overlay Parity
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-005-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row CX-005 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/conversation/presentation/widgets/message_context_overlay.dart`, `lib/features/conversation/presentation/widgets/reaction_display.dart`
- existing tests or current proof: `group_conversation_screen_test.dart` and `group_conversation_wired_test.dart` now directly prove reply/copy remain available when the reaction callback or wired `reactionRepo` is absent.
- likely missing tests: none for the row-owned contract after the no-reaction long-press regressions landed
- likely named gates: Unit (Required), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CX-005; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CX-006
- source row id: `CX-006`
- scenario title: Any future group long-press overlay preserves swipe-to-quote, reaction toggles, and current row rendering
- source section: Long-Press Context Actions and Overlay Parity
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-006-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row CX-006 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/conversation/presentation/widgets/message_context_overlay.dart`, `lib/features/conversation/presentation/widgets/reaction_display.dart`
- existing tests or current proof: `group_conversation_screen_test.dart` now proves long-press reaction selection still routes through the existing callback, while the same suite keeps direct swipe-to-quote and row-render coverage on the shared group row host.
- likely missing tests: none for the row-owned contract after the preservation regressions landed
- likely named gates: Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CX-006; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session CX-007
- source row id: `CX-007`
- scenario title: Group action parity stays consistent regardless of whether the conversation was entered from `Orbit`, `Feed`, or a notification anchor
- source section: Long-Press Context Actions and Overlay Parity
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-CX-007-plan.md`
- exact scope: Add row-specific regression proof for source row CX-007 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/conversation/presentation/widgets/message_context_overlay.dart`, `lib/features/conversation/presentation/widgets/reaction_display.dart`
- existing tests or current proof: `orbit_wired_test.dart`, `feed_wired_test.dart`, and `group_conversation_wired_test.dart` now directly prove Orbit, Feed, and notification-anchor entry all land on the shared group conversation surface with the same long-press reply/copy contract.
- likely missing tests: none for the row-owned cross-surface parity contract after the new route-entry regressions landed
- likely named gates: Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row CX-007; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UI-001
- source row id: `UI-001`
- scenario title: Each group message renders as one clear bubble without a doubled or stacked-card artifact
- source section: Message Rendering and Visual Stability
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UI-001-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row UI-001 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/shared/widgets/media/media_grid.dart`, `lib/shared/widgets/media/media_thumbnail_image.dart`, `lib/features/feed/domain/utils/group_messages_into_threads.dart`
- existing tests or current proof: `group_conversation_screen_test.dart` now proves each row keeps exactly one row-local `BackdropFilter` across base text, quoted/reaction, and media variants, which matches the current single-shell `LetterCard` host in `group_conversation_screen.dart`.
- likely missing tests: none for the row-owned single-shell contract after the new row-scoped shell regressions landed
- likely named gates: Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UI-001; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UI-002
- source row id: `UI-002`
- scenario title: Row-shell stability survives quote enrichment, reaction updates, media auto-download, and replay enrichment
- source section: Message Rendering and Visual Stability
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UI-002-plan.md`
- exact scope: Add row-specific regression proof for source row UI-002 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/shared/widgets/media/media_grid.dart`, `lib/shared/widgets/media/media_thumbnail_image.dart`, `lib/features/feed/domain/utils/group_messages_into_threads.dart`
- existing tests or current proof: `group_conversation_screen_test.dart` now re-renders the same group row through media and reaction enrichment and proves the row still owns exactly one shell after the update.
- likely missing tests: none for the row-owned enrichment-stability contract after the new shell regression landed
- likely named gates: Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UI-002; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RX-001
- source row id: `RX-001`
- scenario title: Tapping a visible group reaction chip reveals which members reacted and with which emoji
- source section: Reaction Transparency and Participant Identity
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-001-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row RX-001 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/groups/application/remove_group_reaction_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/feed/application/feed_reaction_store.dart`
- existing tests or current proof: `group_reaction_details_sheet.dart` now renders a dedicated participant-inspection surface, and `group_conversation_wired_test.dart`, `feed_wired_test.dart`, and `orbit_wired_test.dart` directly prove visible group chips reveal readable participant detail instead of mutating immediately.
- likely missing tests: none for the row-owned participant-disclosure contract after the inspection-sheet regressions landed
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RX-001; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RX-002
- source row id: `RX-002`
- scenario title: Inspecting a group reaction cluster is non-destructive and does not silently remove the viewer's own reaction
- source section: Reaction Transparency and Participant Identity
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-002-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row RX-002 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/groups/application/remove_group_reaction_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/feed/application/feed_reaction_store.dart`
- existing tests or current proof: `group_conversation_screen.dart` and `feed_screen.dart` now route inline chip taps to inspection while long-press reaction bars remain the explicit mutation path, and `group_conversation_wired_test.dart` directly proves chip inspection does not remove stored reactions.
- likely missing tests: none for the row-owned non-destructive inspection contract after the chip-routing split landed
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RX-002; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RX-003
- source row id: `RX-003`
- scenario title: Reaction participant identity stays readable even when reaction rows only persist peer IDs or when reactors are non-friends
- source section: Reaction Transparency and Participant Identity
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-003-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row RX-003 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/groups/application/remove_group_reaction_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/feed/application/feed_reaction_store.dart`
- existing tests or current proof: `group_reaction_details_sheet.dart` now resolves `You`, group-member usernames, and readable truncated peer-id fallback from membership state, and `group_conversation_wired_test.dart` directly proves those identity outcomes from peer-id-only reaction rows.
- likely missing tests: none for the row-owned readable-identity contract after the membership-backed lookup regressions landed
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RX-003; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RX-004
- source row id: `RX-004`
- scenario title: Reaction inspection parity is preserved across `Orbit` and `Feed` entry points
- source section: Reaction Transparency and Participant Identity
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-004-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row RX-004 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/groups/application/remove_group_reaction_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/feed/application/feed_reaction_store.dart`
- existing tests or current proof: `orbit_wired_test.dart` and `feed_wired_test.dart` now directly prove Orbit and Feed route entry both land on the shared group conversation surface with the same reaction-inspection sheet contract and participant identity mapping.
- likely missing tests: none for the row-owned Orbit/Feed entry parity contract after the new route-entry regressions landed
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RX-004; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RX-005
- source row id: `RX-005`
- scenario title: Inline Feed group-thread reactions and permissions behave coherently if inline interaction stays in scope
- source section: Reaction Transparency and Participant Identity
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-005-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row RX-005 only; do not merge neighboring gaps into this session.
- execution ownership: code changes and tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `feed_screen.dart`, `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/groups/application/remove_group_reaction_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/feed/application/feed_reaction_store.dart`
- existing tests or current proof: `feed_screen.dart` now routes inline group chips through a dedicated inspection callback while long-press still owns explicit reaction mutation, `feed_screen_test.dart` proves discussion and announcement-reader cards both keep inspection available, and `feed_wired_test.dart` keeps Feed-to-conversation inspection parity against the shared surface.
- likely missing tests: none for the row-owned inline Feed reaction contract after the dedicated inspection regressions landed
- likely named gates: Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RX-005; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RX-006
- source row id: `RX-006`
- scenario title: Live, replayed, and post-rotation reactions remain truthful after resume/rejoin
- source section: Reaction Transparency and Participant Identity
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RX-006-plan.md`
- exact scope: Add row-specific regression proof for source row RX-006 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_reaction_use_case.dart`, `lib/features/groups/application/remove_group_reaction_use_case.dart`, `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/feed/application/feed_reaction_store.dart`
- existing tests or current proof: `test/features/groups/integration/group_reaction_roundtrip_test.dart` proves live reaction fan-out, and `test/features/groups/integration/group_resume_recovery_test.dart` now proves live-plus-replay reaction dedupe after resume plus post-rotation reaction recovery on a rotated message after rejoin. Supporting unit coverage still exists in `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/remove_group_reaction_use_case_test.dart`, and `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`.
- likely missing tests: none for the row-owned resume/rejoin reaction contract after the new recovery regressions landed
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RX-006; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-003
- source row id: `MM-003`
- scenario title: Voice-only send is supported, empty non-media send is blocked, and announcement readers never expose stale send/record controls
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-003-plan.md`
- exact scope: Preserve the current repo truth for source row MM-003 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: The test inventory has direct wired-path proof for these guards. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-003; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-004
- source row id: `MM-004`
- scenario title: Quote reply survives send, render, failure, and retry paths without losing user intent
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-004-plan.md`
- exact scope: Preserve the current repo truth for source row MM-004 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: Current tests cover quote send, render, and failure-restoration behavior. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-004; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-005
- source row id: `MM-005`
- scenario title: Media upload failure leaves a truthful failed/retryable row, and targeted retry/delete only affects that row
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-005-plan.md`
- exact scope: Preserve the current repo truth for source row MM-005 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: The wired-path tests already cover targeted retry/delete and durable media staging. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-005; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-008
- source row id: `MM-008`
- scenario title: Publish-success pending rows finalize only through an owned path, not silent drift
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-008-plan.md`
- exact scope: Add row-specific regression proof for source row MM-008 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: Existing repo coverage already pins the owned pending-to-sent promotion path: the send use-case tests cover the pending branch and later promotion, and the implementation keeps that transition inside `_finalizeSuccessfulPublishInboxStoreInBackground()`. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none; current pending-ownership coverage is sufficient
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-008; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-009
- source row id: `MM-009`
- scenario title: Zero-peer plus inbox-fail sends recover through one explicit retry owner and never get stranded between retry lanes
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-009-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row MM-009 only; do not merge neighboring gaps into this session.
- execution ownership: tests only after local inspection confirmed the retry-owner split already existed in repo code
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: `test/features/groups/application/send_group_message_use_case_test.dart` already pins the zero-peer plus inbox-fail branch, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart` now proves the failed row recovers through the failed-message retry owner, and `test/features/groups/integration/group_resume_recovery_test.dart` now proves inbox-store retry skips that failed row while failed-message retry recovers it in place and restores offline delivery.
- likely missing tests: none for the row-owned retry-owner contract after the new zero-peer recovery regressions landed
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-009; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-011
- source row id: `MM-011`
- scenario title: Legacy `topicPeers == null` bridge compatibility preserves truthful terminal state
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-011-plan.md`
- exact scope: Preserve the current repo truth for source row MM-011 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: Directly covered in send use-case tests per the inventory. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-011; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-012
- source row id: `MM-012`
- scenario title: Send rules during active group recovery are explicit and intentional
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-012-plan.md`
- exact scope: Add row-specific regression proof for source row MM-012 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: `test/features/groups/application/send_group_message_use_case_test.dart` now proves discussion sends remain allowed while recovery is active, `test/features/groups/presentation/group_conversation_wired_test.dart` already proves stale writer callbacks cannot bypass read-only announcement mode, and `test/features/groups/integration/group_resume_recovery_test.dart` now proves the real `GroupConversationWired` sender path keeps discussion sendable while blocking announcement-admin sends without leaving a stranded local bubble.
- likely missing tests: none for the row-owned active-recovery send contract after the new discussion-plus-announcement acceptance proof landed
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-012; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-014
- source row id: `MM-014`
- scenario title: Share-to-group respects write eligibility and partial-failure truth across writable groups
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-014-plan.md`
- exact scope: Preserve the current repo truth for source row MM-014 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: The test inventory includes share-target filtering, partial-failure truth, and background-task group share coverage. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-014; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MM-015
- source row id: `MM-015`
- scenario title: Announcement sends after key rotation still use the new epoch and remain deliverable
- source section: Messaging, Compose, Media, Voice, and Delivery Truth
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MM-015-plan.md`
- exact scope: Preserve the current repo truth for source row MM-015 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`, `lib/features/groups/presentation/widgets/group_compose_area.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/compose_area.dart`
- existing tests or current proof: Covered by rotation and resume-recovery announcement tests in the inventory. Current repo references: `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MM-015; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RC-002
- source row id: `RC-002`
- scenario title: Duplicate replay enriches missing quote/media metadata rather than creating a second row
- source section: Receive, Rendering, Notification, and Conversation Integrity
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-002-plan.md`
- exact scope: Preserve the current repo truth for source row RC-002 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- existing tests or current proof: Explicitly covered by incoming-message tests. Current repo references: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/notifications/notification_route_target_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RC-002; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RC-004
- source row id: `RC-004`
- scenario title: Sequential messages, delayed delivery, and burst traffic preserve ordering and avoid user-visible loss within supported capacity
- source section: Receive, Rendering, Notification, and Conversation Integrity
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-004-plan.md`
- exact scope: Preserve the current repo truth for source row RC-004 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- existing tests or current proof: Current smoke coverage includes ordering, delayed delivery, and burst handling. Current repo references: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/notifications/notification_route_target_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Recommended), Integration (Required), Smoke (Recommended), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RC-004; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RC-005
- source row id: `RC-005`
- scenario title: A sibling device for the same user stores own live publishes as local sent history
- source section: Receive, Rendering, Notification, and Conversation Integrity
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-005-plan.md`
- exact scope: Preserve the current repo truth for source row RC-005 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- existing tests or current proof: The multi-device convergence tests already prove this behavior. Current repo references: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/notifications/notification_route_target_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RC-005; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RC-006
- source row id: `RC-006`
- scenario title: Media auto-download and row upsert do not create duplicate rows or destroy scroll/context
- source section: Receive, Rendering, Notification, and Conversation Integrity
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-006-plan.md`
- exact scope: Add row-specific regression proof for source row RC-006 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- existing tests or current proof: Existing repo coverage is already direct enough: incoming duplicate replay saves missing media attachments, the listener joins in-flight shared downloads, and the wired conversation keeps row upserts scroll-stable without duplicate rows. Current repo references: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none; current media-enrichment and scroll-preservation coverage is sufficient
- likely named gates: Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RC-006; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RC-007
- source row id: `RC-007`
- scenario title: Notification anchors open the group and highlight the targeted message context
- source section: Receive, Rendering, Notification, and Conversation Integrity
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-007-plan.md`
- exact scope: Preserve the current repo truth for source row RC-007 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- existing tests or current proof: Explicitly covered by group conversation wired tests. Current repo references: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/notifications/notification_route_target_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RC-007; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RC-008
- source row id: `RC-008`
- scenario title: Notification truth suppresses own-message, active-conversation, and recent-remote-push duplicate alerts
- source section: Receive, Rendering, Notification, and Conversation Integrity
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-008-plan.md`
- exact scope: Preserve the current repo truth for source row RC-008 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- existing tests or current proof: Already covered by listener notification tests and the existing matrix. Current repo references: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/core/notifications/notification_route_target_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RC-008; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RC-009
- source row id: `RC-009`
- scenario title: Decryption failure or payload-parse failure creates no ghost message and remains diagnosable
- source section: Receive, Rendering, Notification, and Conversation Integrity
- row disposition: `needs_code_and_tests`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-009-plan.md`
- exact scope: Use the shared tamper harness to close the app-level no-ghost-message contract for decryption and payload-parse failures, including explicit diagnostic routing from the Go node into Flutter-owned receive surfaces.
- execution ownership: accepted locally after landing Flutter bridge diagnostics routing plus the shared-harness wrong-nonce Go proof
- proof ownership: repo-owned across Flutter and `go-mknoon/node`
- likely code-entry files: `go-mknoon/node/pubsub_decryption_failure_test.go`, `go-mknoon/node/group_security_harness_test.go`, `lib/core/bridge/bridge.dart`, `lib/core/bridge/go_bridge_client.dart`, `test/core/bridge/go_bridge_client_test.dart`
- existing tests or current proof: `pubsub_decryption_failure_test.go` now proves wrong-key, tampered-nonce, and malformed-payload failures emit diagnostics without a `group_message:received` side effect, and `go_bridge_client_test.dart` now proves `group:decryption_failed` plus `group:payload_parse_failed` reach Flutter's owned diagnostics stream without invoking the group message callback.
- likely missing tests: none for the row-owned contract after the current Go / Dart bridge proofs landed
- likely named gates: Unit (Required), Integration (Recommended), Fake Network (Recommended)
- dependency on earlier sessions: `PREREQ-GROUP-PROOF-HARNESS`
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RC-009; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RC-010
- source row id: `RC-010`
- scenario title: Dispatcher overflow or high-burst receive load has an owned contract and monitoring story
- source section: Receive, Rendering, Notification, and Conversation Integrity
- row disposition: `needs_code_and_tests`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RC-010-plan.md`
- exact scope: After the dispatcher overflow prerequisite lands, define and prove the supported high-burst receive contract so the product cannot appear healthy while silently dropping user-visible group traffic.
- execution ownership: accepted locally after the dispatcher prerequisite landed and the row-owned contract was pinned on the emitted diagnostics instead of silent native dropping
- proof ownership: repo-owned across Flutter and `go-mknoon/node`
- likely code-entry files: `go-mknoon/node/event_dispatcher.go`, `go-mknoon/node/node.go`, `go-mknoon/node/pubsub_test.go`, `lib/core/utils/flow_event_emitter.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`
- existing tests or current proof: `go-mknoon/node/node_test.go` now proves bounded bursts emit `group:dispatcher_pressure` and `group:dispatcher_overflow` diagnostics with queue-depth, dropped-count, and last-event data, and `go_bridge_client_test.dart` now proves those overflow diagnostics surface to Flutter diagnostics and flow logs instead of being mistaken for healthy receive-path delivery.
- likely missing tests: none for the row-owned high-burst contract after the current Go and Flutter gates passed
- likely named gates: Unit (Required), Integration (Recommended), Fake Network (Recommended)
- dependency on earlier sessions: `PREREQ-GROUP-DISPATCHER-OVERFLOW`
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RC-010; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-002
- source row id: `RY-002`
- scenario title: Foreground resume runs rejoin, drain, stuck-send recovery, upload retry, failed-send retry, and inbox retry in the intended order
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-002-plan.md`
- exact scope: Preserve the current repo truth for source row RY-002 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: The lifecycle tests explicitly pin the ordered resume flow. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-002; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-004
- source row id: `RY-004`
- scenario title: Watchdog or node-requested recovery acknowledges only after a clean rejoin
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-004-plan.md`
- exact scope: Preserve the current repo truth for source row RY-004 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: Pending retrier and recovery tests already pin the ack semantics. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-004; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-005
- source row id: `RY-005`
- scenario title: Archived groups still drain/rejoin as intended while dissolved groups stay read-only and skipped from rejoin
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-005-plan.md`
- exact scope: Preserve the current repo truth for source row RY-005 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: The inventory explicitly notes archived inclusion and dissolved exclusion in recovery tests. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-005; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-006
- source row id: `RY-006`
- scenario title: Multi-page cursor drain recovers backlog exactly once across pages and cursor continuation
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-006-plan.md`
- exact scope: Preserve the current repo truth for source row RY-006 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: Existing recovery tests already cover multi-page drain and cursor continuation. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-006; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-008
- source row id: `RY-008`
- scenario title: Recovery does not burst all joined groups at once
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-008-plan.md`
- exact scope: Preserve the current repo truth for source row RY-008 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: The recovery integration tests already call out multi-group throttle behavior. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Recommended), Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-008; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-009
- source row id: `RY-009`
- scenario title: Long-offline mixed-window recovery keeps retained backlog, drops expired non-system backlog, still applies old system membership events, and surfaces truthful retention messaging
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-009-plan.md`
- exact scope: Preserve the current repo truth for source row RY-009 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: Already covered in the current matrix and in recovery tests. Current repo references: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, `test/core/lifecycle/handle_app_paused_group_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-009; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-010
- source row id: `RY-010`
- scenario title: Replay without `GroupMessageListener` or without `reactionRepo` never silently claims full convergence
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-010-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row RY-010 only; do not merge neighboring gaps into this session.
- execution ownership: repaired invite-accept replay wiring and direct row-owned proof
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: Supported replay callers in `main.dart`, `startup_router.dart`, `handle_app_resumed.dart`, `prepare_notification_route_target_use_case.dart`, `group_list_wired.dart`, and `orbit_wired.dart` now all carry the full replay dependencies. Direct row-owned proof now lives in `test/features/groups/application/accept_pending_group_invite_use_case_test.dart` and `test/features/groups/presentation/group_list_wired_test.dart`, which pin the previously degraded invite-accept path with a real `GroupMessageListener` and `reactionRepo`.
- likely missing tests: none; direct row-owned coverage now exists
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-010; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-011
- source row id: `RY-011`
- scenario title: Invite-accept drain includes offline reactions in the same user-visible catch-up window, or the deferred model is explicitly owned
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-011-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row RY-011 only; do not merge neighboring gaps into this session.
- execution ownership: invite-accept catch-up now closes on the repaired replay wiring plus direct tests
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: `test/features/groups/application/accept_pending_group_invite_use_case_test.dart` now proves invite acceptance drains backlog reactions when `reactionRepo` is supplied, and `test/features/groups/presentation/group_list_wired_test.dart` proves the shipped accept flow persists the replayed backlog message and reaction before the pending invite row disappears.
- likely missing tests: none; direct row-owned coverage now exists
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-011; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session RY-012
- source row id: `RY-012`
- scenario title: Invite acceptance that returns `bridgeError` still converges to a live joined group without needing the invite row again
- source section: Recovery, Replay, Retention, and Offline Privacy
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-RY-012-plan.md`
- exact scope: Implement and prove the exact user-visible contract in source row RY-012 only; do not merge neighboring gaps into this session.
- execution ownership: accepted on direct row-owned proof without product-code changes
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `lib/features/groups/application/group_recovery_gate.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- existing tests or current proof: `test/features/groups/application/accept_pending_group_invite_use_case_test.dart` now proves `bridgeError` leaves the group persisted while clearing the pending invite row, `test/features/groups/presentation/group_list_wired_test.dart` proves the shipped accept surface tells the user recovery is still catching up, and `test/features/groups/integration/invite_round_trip_test.dart` proves a later `rejoinGroupTopics(...)` plus `drainGroupOfflineInboxForGroup(...)` recovery converges without recreating the invite row.
- likely missing tests: none; direct row-owned coverage now exists
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row RY-012; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MD-001
- source row id: `MD-001`
- scenario title: Same-user live publishes on a sibling device store as local sent history without duplicate unread or notification confusion
- source section: Multi-Device and Cross-Surface Convergence
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-001-plan.md`
- exact scope: Preserve the current repo truth for source row MD-001 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/domain/models/group_multi_device_policy.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/feed/application/load_group_feed_snapshot_use_case.dart`, `lib/features/orbit/application/load_orbit_groups_use_case.dart`
- existing tests or current proof: Multi-device convergence tests already cover same-user sent-history behavior. Current repo references: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/core/notifications/notification_route_target_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MD-001; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MD-002
- source row id: `MD-002`
- scenario title: Membership updates converge across sibling devices without duplicate local membership or role drift
- source section: Multi-Device and Cross-Surface Convergence
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-002-plan.md`
- exact scope: Preserve the current repo truth for source row MD-002 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/domain/models/group_multi_device_policy.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/feed/application/load_group_feed_snapshot_use_case.dart`, `lib/features/orbit/application/load_orbit_groups_use_case.dart`
- existing tests or current proof: Explicitly covered by multi-device convergence tests. Current repo references: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/core/notifications/notification_route_target_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MD-002; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MD-003
- source row id: `MD-003`
- scenario title: Mute, unread, and local notifications stay device-local across sibling devices
- source section: Multi-Device and Cross-Surface Convergence
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-003-plan.md`
- exact scope: Preserve the current repo truth for source row MD-003 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/domain/models/group_multi_device_policy.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/feed/application/load_group_feed_snapshot_use_case.dart`, `lib/features/orbit/application/load_orbit_groups_use_case.dart`
- existing tests or current proof: Called out directly in the multi-device convergence tests. Current repo references: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/core/notifications/notification_route_target_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MD-003; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MD-004
- source row id: `MD-004`
- scenario title: True device/simulator multi-device E2E proves sibling-device behavior beyond in-memory fakes
- source section: Multi-Device and Cross-Surface Convergence
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-004-plan.md`
- exact scope: Preserve the closed simulator/emulator multi-device proof surface for MD-004 on the primary Android pair `emulator-5554` + `emulator-5556` or the primary iOS pair `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` (`iPhone Air`) + `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` (`iPhone 17`), keeping the earlier spare `1B098DFF-6294-407A-A209-BBF360893485` (`iPhone 16e`) proof and the final primary-iOS deployed-relay rerun both attached to the row.
- execution ownership: no execution because already proven
- proof ownership: repo-owned simulator/emulator exploratory harness
- likely code-entry files: `lib/features/groups/domain/models/group_multi_device_policy.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/feed/application/load_group_feed_snapshot_use_case.dart`, `lib/features/orbit/application/load_orbit_groups_use_case.dart`
- existing tests or current proof: Closed on 2026-04-12 with earlier spare-target proof in `/tmp/md004_group_multi_device_real_rerun8_20260412.log`, then final primary-iOS deployed-relay rerun in `/private/tmp/acceptance_20260412/group_multi_device_real_primary_ios.log`, where sibling and primary both finished `All tests passed!` before `[ORCH] MD-004 proof completed successfully`.
- likely missing tests: none; proof is captured and the row is now closed
- likely named gates: Integration (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none in-repo; depends on external proof owner or device-lab / native / relay harness
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MD-004; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MD-005
- source row id: `MD-005`
- scenario title: Message-level behavior stays consistent when entering the same group from `Orbit`, `Feed`, or push
- source section: Multi-Device and Cross-Surface Convergence
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-005-plan.md`
- exact scope: Add only the missing push-entry reaction-inspection proof needed to close the exact row-owned entry-point contract without broadening into unrelated push-trigger or device-lab work.
- execution ownership: accepted on direct row-owned proof with one narrow widget-test addition
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/domain/models/group_multi_device_policy.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/feed/application/load_group_feed_snapshot_use_case.dart`, `lib/features/orbit/application/load_orbit_groups_use_case.dart`
- existing tests or current proof: `orbit_wired_test.dart` and `feed_wired_test.dart` already pin long-press and reaction-inspection parity after Orbit and Feed entry. `group_conversation_wired_test.dart` now adds direct notification-anchor reaction inspection on the same shared group conversation surface, while `app_root_notification_open_test.dart`, `resolve_group_notification_route_target_use_case_test.dart`, and `chat_and_group_push_open_flow_test.dart` keep the push-entry route and catch-up contract aligned with that surface.
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MD-005; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session MD-006
- source row id: `MD-006`
- scenario title: Group-message and group-invite push routes navigate to the correct surface
- source section: Multi-Device and Cross-Surface Convergence
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-006-plan.md`
- exact scope: Preserve the current repo truth for source row MD-006 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/domain/models/group_multi_device_policy.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`, `lib/features/feed/application/load_group_feed_snapshot_use_case.dart`, `lib/features/orbit/application/load_orbit_groups_use_case.dart`
- existing tests or current proof: Current notification-route and push-navigation tests already cover the mapping. Current repo references: `test/features/groups/integration/group_multi_device_convergence_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/core/notifications/notification_route_target_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Integration (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row MD-006; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-004
- source row id: `SV-004`
- scenario title: Replay attack with tampered timestamps or reordered envelopes does not create duplicate visible messages or bypass cutoffs
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-004-plan.md`
- exact scope: Use the shared replay/tamper harness to close replay-attack resistance for reordered or timestamp-tampered envelopes, including dedupe integrity and remove/dissolve cutoff enforcement on the Flutter-visible receive path.
- execution ownership: code changes and tests after `PREREQ-GROUP-PROOF-HARNESS` lands
- proof ownership: repo-owned across Flutter and `go-mknoon/node`
- likely code-entry files: `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/group_inbox_test.go`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`
- existing tests or current proof: `test-inventory.md` still calls this out as an explicit security gap; current receive tests cover normal dedupe and cutoff behavior, but not malicious replay/reorder injection.
- likely missing tests: replay/reorder injectors, timestamp-tamper regressions, and cutoff-bypass attempts that must not create a second visible row
- likely named gates: Unit (Required), Integration (Recommended), Fake Network (Recommended)
- dependency on earlier sessions: `PREREQ-GROUP-PROOF-HARNESS`
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-004; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-005
- source row id: `SV-005`
- scenario title: Tampered payload, wrong key, tampered nonce, or tampered ciphertext creates no visible message and yields diagnosable rejection
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-005-plan.md`
- exact scope: Close the wrong-key, wrong-nonce, and tampered-ciphertext rejection contract so malformed encrypted group traffic is rejected without a visible ghost row and with owned diagnostics that downstream observability can rely on.
- execution ownership: code changes and tests after `PREREQ-GROUP-PROOF-HARNESS` lands
- proof ownership: repo-owned across Flutter and `go-mknoon/node`
- likely code-entry files: `go-mknoon/node/pubsub_decryption_failure_test.go`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- existing tests or current proof: Go-side crypto coverage already exercises tampered ciphertext and nonce failures, but the inventory still calls out missing group-message app-level rejection proof.
- likely missing tests: direct wrong-key, wrong-nonce, and tampered-ciphertext no-ghost-message regressions on the Flutter intake path plus diagnosable rejection assertions
- likely named gates: Unit (Required), Integration (Recommended), Fake Network (Recommended)
- dependency on earlier sessions: `PREREQ-GROUP-PROOF-HARNESS`
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-005; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-006
- source row id: `SV-006`
- scenario title: Previous-key grace during rotation accepts legitimate in-flight traffic without reopening indefinite stale-key access
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-006-plan.md`
- exact scope: Close the current-or-previous-key grace contract during rotation so one legitimate in-flight old-epoch message may still land while indefinite stale-key access stays rejected.
- execution ownership: code changes and tests after `PREREQ-GROUP-PROOF-HARNESS` lands
- proof ownership: repo-owned across Flutter and `go-mknoon/node`
- likely code-entry files: `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`
- existing tests or current proof: `C4-03` documents current-or-previous-key grace behavior and `go-mknoon/node/pubsub_key_rotation_grace_test.go` exists, but the matrix still lacks row-owned closure proof on the user-visible app contract.
- likely missing tests: one legitimate in-flight old-epoch acceptance case, one stale-window rejection case, and Flutter-visible parity assertions after rotation
- likely named gates: Unit (Required), Integration (Recommended), Fake Network (Recommended)
- dependency on earlier sessions: `PREREQ-GROUP-PROOF-HARNESS`
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-006; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-007
- source row id: `SV-007`
- scenario title: Concurrent key-rotation races across admins converge to one final usable epoch
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `needs_code_and_tests`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-007-plan.md`
- exact scope: Use the shared key-race harness to close concurrent admin rotation convergence so the group ends in one final usable epoch instead of splitting into incompatible key truth.
- execution ownership: code changes and tests after `PREREQ-GROUP-PROOF-HARNESS` lands
- proof ownership: repo-owned across Flutter and `go-mknoon/node`
- likely code-entry files: `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/group_inbox_test.go`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`
- existing tests or current proof: The inventory explicitly calls out key-rotation race coverage as missing even though adjacent membership and re-invite paths are already covered.
- likely missing tests: competing admin rotation fixtures, final-epoch convergence assertions, and sendability proof after the race resolves
- likely named gates: Unit (Required), Integration (Recommended), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: `PREREQ-GROUP-PROOF-HARNESS`
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-007; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-008
- source row id: `SV-008`
- scenario title: Concurrent remove/promote or remove/rotate conflicts converge to one final visible member/admin map and usable key state
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-008-plan.md`
- exact scope: Add row-specific regression proof for source row SV-008 without broadening scope beyond the exact user-visible contract in this row.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `lib/core/utils/push_diagnostics_logger.dart`
- existing tests or current proof: Existing repo coverage already closes the conflict-convergence contract through concurrent admin-change/remove flows and rotated re-invite recovery. Current repo references: `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- likely missing tests: none; current convergence coverage is sufficient
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-008; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-010
- source row id: `SV-010`
- scenario title: Topic namespace / `topicName` contract between Go and Dart is explicit and tested
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `covered_in_repo`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-010-plan.md`
- exact scope: After the creator-path fix lands, pin the canonical `topicName` contract across the create response, persisted group row, and join/rejoin callers so Dart and Go cannot drift again.
- execution ownership: bridge-helper and creator-path regressions now pin one canonical `topicName` contract across create, persistence, and join callers
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `test/features/groups/application/create_group_use_case_test.dart`, `test/features/groups/application/rejoin_group_topics_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- existing tests or current proof: `test/core/bridge/bridge_group_helpers_test.dart` already pins the canonical `/mknoon/group/...` create response and join payload contract, and `test/features/groups/application/create_group_use_case_test.dart` now proves the creator fallback and persisted row stay on that same namespace when `topicName` is omitted.
- likely missing tests: none; the Go/Dart `topicName` contract is now directly pinned on the creator and join helper boundaries
- likely named gates: Unit (Required), Integration (Recommended)
- dependency on earlier sessions: `CB-007`
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-010; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UX-001
- source row id: `UX-001`
- scenario title: Per-group mute suppresses notifications without dropping delivery
- source section: Quality-of-Life and Higher-Level Product Capabilities
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-001-plan.md`
- exact scope: Preserve the current repo truth for source row UX-001 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, `lib/features/push/application/show_notification_use_case.dart`
- existing tests or current proof: Strong current coverage already exists for mute behavior. Current repo references: `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/groups/application/dissolve_group_use_case_test.dart`, `test/features/share/application/handle_share_intent_use_case_test.dart`, `test/features/share/application/share_batch_delivery_coordinator_test.dart`, `test/core/notifications/notification_push_tap_navigate_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UX-001; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UX-002
- source row id: `UX-002`
- scenario title: Dissolving the group keeps history readable but blocks further writing
- source section: Quality-of-Life and Higher-Level Product Capabilities
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-002-plan.md`
- exact scope: Preserve the current repo truth for source row UX-002 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, `lib/features/push/application/show_notification_use_case.dart`
- existing tests or current proof: Already covered in dissolve and membership/replay tests. Current repo references: `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/groups/application/dissolve_group_use_case_test.dart`, `test/features/share/application/handle_share_intent_use_case_test.dart`, `test/features/share/application/share_batch_delivery_coordinator_test.dart`, `test/core/notifications/notification_push_tap_navigate_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UX-002; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UX-009
- source row id: `UX-009`
- scenario title: Local-relay / simulator exploratory push trigger path for group message and group invite is verified if push is in scope
- source section: Quality-of-Life and Higher-Level Product Capabilities
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-009-plan.md`
- exact scope: Preserve the closed local-relay / simulator exploratory proof surface for UX-009 on the primary Android pair `emulator-5554` + `emulator-5556` or the primary iOS pair `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` (`iPhone Air`) + `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` (`iPhone 17`), keeping the earlier spare `1B098DFF-6294-407A-A209-BBF360893485` (`iPhone 16e`) proof and the final primary-iOS deployed-relay rerun both attached to the row.
- execution ownership: no execution because already proven
- proof ownership: repo-owned simulator/emulator exploratory harness
- likely code-entry files: `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, `lib/features/push/application/show_notification_use_case.dart`
- existing tests or current proof: Closed on 2026-04-12 with earlier spare-target proof in `/tmp/ux009_notification_open_ui_smoke_20260412_rerun16e_drive.log`, then final primary-iOS deployed-relay rerun in `/private/tmp/acceptance_20260412/notification_open_ui_primary_ios.log`, where both `iPhone Air` and `iPhone 17` passed and the run ended with `[DONE] Notification-open UI smoke passed on all selected devices.`.
- likely missing tests: none; proof is captured and the row is now closed
- likely named gates: Integration (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none; depends on the local-relay simulator/emulator push harness and the listed Android/iOS targets
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UX-009; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UX-010
- source row id: `UX-010`
- scenario title: Share-target picker shows only writable groups and respects announcement read-only filtering
- source section: Quality-of-Life and Higher-Level Product Capabilities
- row disposition: `covered_in_repo`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-010-plan.md`
- exact scope: Preserve the current repo truth for source row UX-010 only and keep its existing evidence attached to this row without merging adjacent coverage.
- execution ownership: no execution because already covered
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, `lib/features/push/application/show_notification_use_case.dart`
- existing tests or current proof: Explicitly covered by cross-feature share tests in the inventory. Current repo references: `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/groups/application/dissolve_group_use_case_test.dart`, `test/features/share/application/handle_share_intent_use_case_test.dart`, `test/features/share/application/share_batch_delivery_coordinator_test.dart`, `test/core/notifications/notification_push_tap_navigate_test.dart`
- likely missing tests: none; current direct coverage is cited below
- likely named gates: Unit (Required), Integration (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UX-010; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session ID-007
- source row id: `ID-007`
- scenario title: Explicit admin transfer or ownership handoff behaves cleanly if the feature exists
- source section: Identity, Roles, Avatars, and Mixed-Social-Graph Behavior
- row disposition: `unsupported_product_scope`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-ID-007-plan.md`
- exact scope: Keep source row ID-007 explicitly out of implementation scope while the capability stays unsupported; only row-specific truth-alignment and scope proof belong here.
- execution ownership: no execution because the row is out of current product scope
- proof ownership: product-scope excluded in the current repo contract
- likely code-entry files: `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/presentation/widgets/group_member_row.dart`, `lib/features/groups/presentation/widgets/group_avatar.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/home/application/identity_avatar_resolver.dart`, `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/groups/application/group_avatar_storage.dart`
- existing tests or current proof: The audit and current matrix both say explicit ownership handoff is not yet landed. Current scope proof: `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`, `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- likely missing tests: none while the capability stays out of scope
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row ID-007; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-009
- source row id: `SV-009`
- scenario title: Description pass-through between Dart and Go is explicit and tested if create-time description is supported
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `unsupported_product_scope`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-009-plan.md`
- exact scope: Keep source row SV-009 explicitly out of implementation scope while the capability stays unsupported; only row-specific truth-alignment and scope proof belong here.
- execution ownership: no execution because the row is out of current product scope
- proof ownership: product-scope excluded in the current repo contract
- likely code-entry files: `lib/features/groups/application/create_group_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/domain/models/group_message_payload.dart`, `lib/core/utils/push_diagnostics_logger.dart`
- existing tests or current proof: `test-inventory.md` explicitly flags description pass-through as a Go/Dart boundary gap. Current scope proof: `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`, `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- likely missing tests: none while the capability stays out of scope
- likely named gates: Unit (Required), Integration (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-009; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-011
- source row id: `SV-011`
- scenario title: Flow-event names and payload shapes for group timing/recovery/retry observability are pinned
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `needs_tests_only`
- session classification: `implementation-ready`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-011-plan.md`
- exact scope: Pin the group flow-event names and payload shapes for send, rejoin, retry, and drain timing and failure emissions without widening this row into unrelated new observability features.
- execution ownership: tests only
- proof ownership: Flutter-owned in the current repo
- likely code-entry files: `lib/core/utils/flow_event_emitter.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`, `lib/features/groups/application/retry_failed_group_messages_use_case.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, `test/core/utils/flow_event_emitter_test.dart`, `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- existing tests or current proof: `test-inventory.md` explicitly calls out missing flow-event contract inventory coverage even though the group recovery and retry code already emits timing and failure events.
- likely missing tests: event-name and payload-shape assertions for send, rejoin, retry, and drain flows, plus matrix/doc truth alignment once those contracts are pinned
- likely named gates: Unit (Required), Integration (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-011; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session SV-012
- source row id: `SV-012`
- scenario title: Native dispatcher overflow or dropped diagnostics are surfaced to monitoring instead of remaining silent
- source section: Security, Validator, Bridge-Contract, and Observability
- row disposition: `needs_tests_only`
- session classification: `accepted`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-SV-012-plan.md`
- exact scope: After dispatcher overflow observability lands, pin the monitoring-facing contract so dropped native events or diagnostics cannot remain silent to the owned metrics and flow-event surfaces.
- execution ownership: accepted locally after the shared overflow prerequisite exposed the diagnostic events and Flutter proved the monitoring path explicitly
- proof ownership: repo-owned across Flutter and `go-mknoon/node`
- likely code-entry files: `go-mknoon/node/event_dispatcher.go`, `lib/core/utils/flow_event_emitter.dart`, `lib/core/utils/push_diagnostics_logger.dart`, `test/core/utils/flow_event_emitter_test.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- existing tests or current proof: `go-mknoon/node/node_test.go` now proves overflow diagnostics are emitted with dropped-count and queue-depth data, and `go_bridge_client_test.dart` now proves `group:dispatcher_overflow` reaches Flutter's diagnostics stream and flow logs instead of remaining silent.
- likely missing tests: none for the row-owned monitoring contract after the current Go and Flutter gates passed
- likely named gates: Unit (Required), Integration (Recommended), Fake Network (Recommended)
- dependency on earlier sessions: `PREREQ-GROUP-DISPATCHER-OVERFLOW`
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row SV-012; test-inventory.md when new or clarified proof lands; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UX-003
- source row id: `UX-003`
- scenario title: Search inside group history works if the feature exists
- source section: Quality-of-Life and Higher-Level Product Capabilities
- row disposition: `unsupported_product_scope`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-003-plan.md`
- exact scope: Keep source row UX-003 explicitly out of implementation scope while the capability stays unsupported; only row-specific truth-alignment and scope proof belong here.
- execution ownership: no execution because the row is out of current product scope
- proof ownership: product-scope excluded in the current repo contract
- likely code-entry files: `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, `lib/features/push/application/show_notification_use_case.dart`
- existing tests or current proof: The audit and inventory both say group search is not landed. Current scope proof: `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`, `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- likely missing tests: none while the capability stays out of scope
- likely named gates: Unit (Required), Integration (Required), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UX-003; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UX-004
- source row id: `UX-004`
- scenario title: Pinning and unpinning important messages works if the feature exists
- source section: Quality-of-Life and Higher-Level Product Capabilities
- row disposition: `unsupported_product_scope`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-004-plan.md`
- exact scope: Keep source row UX-004 explicitly out of implementation scope while the capability stays unsupported; only row-specific truth-alignment and scope proof belong here.
- execution ownership: no execution because the row is out of current product scope
- proof ownership: product-scope excluded in the current repo contract
- likely code-entry files: `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, `lib/features/push/application/show_notification_use_case.dart`
- existing tests or current proof: Not landed according to the audit. Current scope proof: `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`, `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- likely missing tests: none while the capability stays out of scope
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UX-004; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UX-005
- source row id: `UX-005`
- scenario title: Per-message edit, delete, or tombstone works if the feature exists
- source section: Quality-of-Life and Higher-Level Product Capabilities
- row disposition: `unsupported_product_scope`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-005-plan.md`
- exact scope: Keep source row UX-005 explicitly out of implementation scope while the capability stays unsupported; only row-specific truth-alignment and scope proof belong here.
- execution ownership: no execution because the row is out of current product scope
- proof ownership: product-scope excluded in the current repo contract
- likely code-entry files: `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, `lib/features/push/application/show_notification_use_case.dart`
- existing tests or current proof: Not landed according to the audit. Current scope proof: `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`, `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- likely missing tests: none while the capability stays out of scope
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UX-005; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UX-006
- source row id: `UX-006`
- scenario title: Read receipts or reader counts work if the feature exists
- source section: Quality-of-Life and Higher-Level Product Capabilities
- row disposition: `unsupported_product_scope`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-006-plan.md`
- exact scope: Keep source row UX-006 explicitly out of implementation scope while the capability stays unsupported; only row-specific truth-alignment and scope proof belong here.
- execution ownership: no execution because the row is out of current product scope
- proof ownership: product-scope excluded in the current repo contract
- likely code-entry files: `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, `lib/features/push/application/show_notification_use_case.dart`
- existing tests or current proof: Not landed according to the audit. Current scope proof: `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`, `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- likely missing tests: none while the capability stays out of scope
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Recommended)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UX-006; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UX-007
- source row id: `UX-007`
- scenario title: Member-level moderation such as mute or ban works if the feature exists
- source section: Quality-of-Life and Higher-Level Product Capabilities
- row disposition: `unsupported_product_scope`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-007-plan.md`
- exact scope: Keep source row UX-007 explicitly out of implementation scope while the capability stays unsupported; only row-specific truth-alignment and scope proof belong here.
- execution ownership: no execution because the row is out of current product scope
- proof ownership: product-scope excluded in the current repo contract
- likely code-entry files: `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, `lib/features/push/application/show_notification_use_case.dart`
- existing tests or current proof: Not landed according to the audit. Current scope proof: `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`, `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- likely missing tests: none while the capability stays out of scope
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UX-007; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

### Session UX-008
- source row id: `UX-008`
- scenario title: Scheduled announcements, edit-after-send, delete-after-send, or analytics work if the feature exists
- source section: Quality-of-Life and Higher-Level Product Capabilities
- row disposition: `unsupported_product_scope`
- session classification: `stale/already-covered`
- intended plan file: `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-UX-008-plan.md`
- exact scope: Keep source row UX-008 explicitly out of implementation scope while the capability stays unsupported; only row-specific truth-alignment and scope proof belong here.
- execution ownership: no execution because the row is out of current product scope
- proof ownership: product-scope excluded in the current repo contract
- likely code-entry files: `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/application/dissolve_group_use_case.dart`, `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, `lib/features/push/application/show_notification_use_case.dart`
- existing tests or current proof: Not landed according to the audit. Current scope proof: `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`, `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- likely missing tests: none while the capability stays out of scope
- likely named gates: Unit (Required), Integration (Required), Fake Network (Recommended), 3-Party E2E (Required)
- dependency on earlier sessions: none
- matrix or closure docs to update when done: Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md row UX-008; Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md

## Downstream Execution Path

- use this artifact as the row-granular source for later plan generation.
- create doc-scoped plan files as `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-<session-id>-plan.md` adjacent to the source matrix.
- execute sessions in this order unless a later controller has an explicit reason to pause: `PREREQ-GROUP-OFFLINE-REPLAY`, `PREREQ-GROUP-PROOF-HARNESS`, `PREREQ-GROUP-DISPATCHER-OVERFLOW`, then all P0 rows in source order, then all P1 rows in source order, then all P2 rows in source order while honoring explicit dependencies.
- dependent row-owned sessions must not advance past `accepted` until their prerequisite sessions are accepted and the source matrix row is updated to `Closed` or `Covered` with concrete evidence.
- do not merge adjacent rows into seam buckets during execution unless the strict merge rule is re-evaluated and still preserves exact row traceability; shared prerequisite sessions do not satisfy row-owned closure by themselves.
- when a row closes, update the source matrix row status with concrete evidence and refresh this breakdown only if the row disposition, dependency structure, or execution ordering materially changes.

## Final program acceptance

- final program verdict:
  `closed`
- docs updated:
  `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`,
  `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`,
  `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
- what is now resolved:
  the source matrix, test inventory, and session breakdown now persist final closure. Full Flutter host-side, `go-mknoon`, and `go-relay-server` suites are green; Android background reconnect, transport E2E, WiFi relay fallback smoke, media stable-ID smoke, group recovery E2E, soak E2E, notification-open UI on the primary iOS pair, and `MD-004` real multi-device on the primary iOS pair are green; `MD-004` and `UX-009` retain the earlier spare-device proof alongside the final primary-pair reruns
- still-open blocker for safe continuation:
  `none`
- stop reason for this controller pass:
  final program acceptance completed and was persisted after the 2026-04-12 primary-iOS deployed-relay reruns and green repo-owned verification
- explicit open work that remains:
  shared prerequisite sessions: none
  row-owned implementation sessions: none
  device-lab / simulator multi-device evidence rows: none
  simulator / local-relay exploratory proof rows: none
  multi-relay failover / relay-chaos wrappers: ran and skipped truthfully because no two-relay `MKNOON_RELAY_ADDRESSES` environment was configured; they are not counted as multi-relay proof
  unsupported rows remain explicit and non-blocking in the ledger and source matrix: `ID-004`, `ID-007`, `SV-009`, `UX-003`, `UX-004`, `UX-005`, `UX-006`, `UX-007`, `UX-008`
