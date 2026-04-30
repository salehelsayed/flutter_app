# Trusted Private libp2p Group Chat Missing Test Matrix with Coverage Rules

This file now keeps only the 49 rows considered valuable after the current implementation review on 2026-04-30. Rows moved out by that review were copied to `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules_v1.md` so they remain available without driving near-term work.

## Scope

This file is the trusted-private update to `libp2p_group_chat_missing_test_matrix_full_with_rules.md`.

It uses the same matrix style as `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md` and remains a gap-focused addendum to the current group-chat `test-inventory.md`.

The product assumption for this version is:

- groups are **private, invite-only, and intended for trusted users**
- groups are **not public chat rooms**
- public listing, public discoverability, open auto-join, public join requests, and public-room anti-spam/reporting workflows are **not release-scope capabilities** unless explicitly enabled later
- trusted members are still authorized only while their membership, device, role, and encryption epoch are current
- relays, bootstrap/rendezvous infrastructure, mailbox/store-and-forward peers, logs, diagnostics, and push bridges are **not trusted with plaintext**

That scope reduces the priority of public-room abuse and moderation tests, but it does **not** remove the need for authorization, identity binding, key rotation, removed-device isolation, replay protection, offline sync repair, message/media integrity, notification privacy, and truthful UI states.

## Source bundle used

- `test-inventory.md`
- `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- Functional requirements catalog supplied in the prompt, `FR-001` through `FR-380`
- Previous generated matrix: `libp2p_group_chat_missing_test_matrix_full_with_rules.md`

## Actors

- **A** = group creator, owner, admin, or authorized moderator
- **B** = active trusted group member on one device
- **C** = invitee, rejoiner, removed member, banned identity, or sibling device
- **D** = prospective trusted member not yet in the group
- **X** = unauthorized, stale, compromised, buggy, relay, mailbox, storage, or protocol-incompatible peer

## Status legend

- **Partial** = adjacent or lower-level coverage exists in the current inventory, but the full user-visible or protocol-visible requirement is not directly proven.
- **Open** = no dedicated coverage was found in the current inventory for the stated behavior.
- **Unsupported** = outside the trusted-private release scope; keep it excluded from release gates unless product scope changes.

## Priority guide

- **P0** = release-blocking trust, privacy, safety, authorization, crypto, admission, or state-convergence contract for trusted private groups.
- **P1** = important before broad trusted-private rollout or before claiming complete group-chat reliability.
- **P2** = roadmap, policy-dependent, or public-room-style capability; add coverage when intentionally enabled.

## Coverage policy used in this matrix

### Coverage legend

- **Required** = should exist before treating the row as production-ready.
- **Recommended** = high-value proof but not always required for the first trusted-private release gate.
- **N/A** = do not force this layer for the row.

### Rules

**Unit**
Use for deterministic logic: validation, permission checks, state conflict resolution, replay protection, epoch decisions, notification eligibility, error classification, metadata minimization, configuration guards, and API payload shape.

**Integration**
Use for most rows where trust depends on local persistence, application services, bridge payloads, and UI-visible state.

**Smoke**
Keep small and release-blocking. Smoke should prove the core trusted-private user journey and the highest-risk failure modes, not every branch.

**Fake Network**
Use when the risk is peer discovery, PubSub duplication, relay fallback, sync gaps, partitions, store-and-forward behavior, stale removed peers, or protocol-incompatible peer traffic.

**3-Party E2E**
Use for flows users perceive across A/B/C devices: create, direct invite, join, removal, key rotation, media, notifications, history sync, and multi-device convergence.

## Current repo execution note (2026-04-30)

The current inventory is strong on discussion and announcement happy paths, direct send/receive, pending invites, admin-only announcement writes, role promotion/demotion, removals, key rotation basics, replay dedupe, inbox drain, retry/resume, media scaffolding, Go-side PubSub validation, and several decryption-failure paths.

For a trusted-private group launch, the remaining release-sensitive gaps are concentrated in: private-only admission guards, invite revocation/replay, device-specific admission, local-and-remote authorization on every mutation, removed-device isolation, membership/key epoch convergence, offline sync repair, message ordering, media safety, notification/privacy correctness, event-log/database integrity, and UI truthfulness.

Public/discoverable group behaviors, open join queues, broad public anti-spam, report workflows, and public-room moderation policies are de-scoped unless the product explicitly enables them later. This matrix keeps only trusted-private guard rows where they protect invite-only admission or authorization.

## Matrix interpretation

- This file contains only the 49 retained rows that map to plausible current-code regressions or missing verification around the implemented trusted-private group chat behavior.
- Rows moved to `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules_v1.md` are preserved for traceability, but they are not part of the immediate gap-closure set.
- A retained row does not automatically mean the product should add new behavior. It means the existing behavior is important enough to verify so users are not disappointed by regressions.
- Rows intentionally exclude public group, untrusted membership, admin/moderation, group invite links, server roster authority, and generic P2P transport tests unless they directly protect trusted-private group-chat behavior.

## Group Lifecycle, Metadata, Schema, and Governance Truth

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| GL-005 | Private-only visibility and discoverability are enforced | The release scope is trusted, private, invite-only groups; public listing/discoverability is disabled. | 1. Create a trusted private group. 2. Query every discovery, listing, preview, and join surface as D and X. 3. Attempt public/discoverable creation flags and open join routes. | Only invited/authorized identities can discover usable group metadata or join material; public listing, public previews, and open joins are rejected or hidden. | P0 | Open | Required | Required | Recommended | Recommended | Recommended | FR-009, FR-059, FR-319, FR-332. Trusted-private scope changes this from public/discoverable coverage to a release guard that proves public-room behavior is not accidentally exposed. |

## libp2p Topology, Topics, Discovery, and Protocol Negotiation

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| LP-002 | PubSub authorization is enforced before accept or forward | X is not a member, is stale, or has been removed. | 1. X publishes message, reaction, metadata, membership, and key events. 2. Observe local accept, forward, and diagnostics behavior. | Unauthorized traffic is rejected before state mutation or forwarding; diagnostics are privacy-safe and rate-limited. | P0 | Partial | Required | Required | Required | Required | Recommended | FR-023, FR-039, FR-079, FR-103. Validator coverage exists, but not the full event-family and forward-path matrix. |
| LP-003 | Unsubscribe after leave, removal, ban, and deletion | B leaves; C is removed or banned; a group is deleted or dissolved. | 1. Trigger each exit path. 2. Inspect active subscriptions and discovery loops. 3. Publish after exit. | Exited devices are unsubscribed and do not receive or process future group topic traffic. | P0 | Partial | Required | Required | Recommended | Required | Recommended | FR-025, FR-086, FR-089, FR-091, FR-014. Existing leave tests call bridge leave but do not prove all exit paths stop live delivery. |
| LP-013 | Duplicate PubSub handling covers hash, ID, and sequence collisions | Live PubSub and sync deliver the same payload or malicious duplicates. | 1. Deliver duplicate messages with same ID, same hash, and conflicting sequence. 2. Compare DB, UI, notifications, and receipts. | Duplicates are ignored or enriched deterministically without double rows, double notifications, or overwritten trusted fields. | P0 | Partial | Required | Required | Required | Required | Recommended | FR-040, FR-244. Dart receive dedupe is strong; Go PubSub duplicate and receipt/notification dimensions remain broader. |

## Invitations, Join Flows, and Device Admission

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| IJ-001 | Invite payload completeness and privacy | A sends an invite to C. | 1. Create direct and offline invites. 2. Inspect encrypted and decrypted payloads. 3. Verify preview, permissions, expiration, device allowance, and key-material reference. | Invites include enough data for the intended invitee to evaluate and accept the private group, but never expose member lists, keys, peer addresses, or history beyond policy. | P0 | Partial | Required | Required | Recommended | Recommended | Recommended | FR-043, FR-055, FR-318. Trusted-private scope allows safe preview metadata for the invited identity only. |
| IJ-002 | Invite signature, inviter authorization, and stale inviter rejection | A can invite; B has no invite permission or was removed. | 1. Send signed invites from A, B, and a removed B. 2. Tamper inviter fields. 3. Accept from C. | Only authorized signed invites are stored or accepted; stale or tampered inviter payloads fail closed. | P0 | Partial | Required | Required | Required | Recommended | Recommended | FR-044, FR-045, FR-172, FR-348. Sender mismatch and unknown sender are covered, but signed-invite authorization is not complete. |
| IJ-003 | Invite revocation and revoked-accept failure | A has a pending invite for C. | 1. Revoke the invite. 2. Deliver delayed direct and mailbox copies. 3. Attempt accept. | Revoked invites are removed from pending surfaces and cannot be accepted even if replayed later. | P0 | Open | Required | Required | Recommended | Recommended | Recommended | FR-047, FR-351. |
| IJ-005 | Invite reuse policy and replay protection | Single-use, multi-use, and link invites can be configured. | 1. Accept an invite once. 2. Replay the same credential from same and different devices. 3. Try after expiry. | Reuse follows policy exactly; single-use and expired credentials cannot create duplicate or unauthorized membership. | P0 | Open | Required | Required | Recommended | Required | Recommended | FR-046, FR-048, FR-065, FR-188, FR-352. |
| IJ-009 | Open auto-join is disabled for trusted-private groups | A peer presents a token, link, stale invite, or copied join payload without identity-bound authorization. | 1. Attempt auto-join with valid-looking but unbound tokens. 2. Attempt auto-join with copied or replayed payloads. 3. Inspect membership, key, and notification state. | No member, device, key, or local group state is created unless a current signed invite is bound to the accepting identity/device. | P0 | Open | Required | Required | Required | Required | Recommended | FR-061, FR-064, FR-065, FR-268. This is a trusted-private release gate because open admission would break the product model. |
| IJ-010 | Concurrent joins converge membership and epoch state | C and D join at nearly the same time from different peers. | 1. Deliver concurrent join events and welcomes. 2. Sync all peers. 3. Send after convergence. | Concurrent direct invites and accepts converge membership and epoch state without admitting unintended identities or overwriting trusted member roles. | P0 | Open | Required | Required | Recommended | Required | Required | FR-066, FR-174, FR-185. Remains P0 because trusted direct invites can still race across devices. |
| IJ-011 | New-member sync includes only authorized state and history | C joins after metadata, role, pin, and history changes. | 1. Send pre-join messages and update metadata/permissions. 2. C joins. 3. Sync and inspect C state. | New trusted members receive only policy-allowed metadata, membership, permissions, pinned items, and history; pre-join history remains inaccessible if policy says so. | P0 | Partial | Required | Required | Recommended | Required | Required | FR-067, FR-068, FR-205. Trusted status after admission does not imply entitlement to all prior history. |
| IJ-013 | Invite bound to wrong identity or device fails safely | C has an invite bound to a different user, device, or Peer ID. | 1. Attempt accept from the wrong identity and wrong device. 2. Replay via sync/mailbox. | Accept fails without creating group state or leaking key material. | P0 | Partial | Required | Required | Recommended | Recommended | Recommended | FR-042, FR-043, FR-353. Transport-sender mismatch exists; identity/device-bound invites need direct coverage. |
| IJ-014 | Welcome/key package delivery failure leaves clear pending repair state | C accepts invite but welcome/key material delivery fails or is stale. | 1. Accept with missing, stale, or undecryptable welcome material. 2. Trigger repair sync. | C does not join into an unusable silent state; the UI shows repair or rejoin requirements. | P0 | Partial | Required | Required | Recommended | Recommended | Recommended | FR-063, FR-064, FR-186, FR-187, FR-275. |

## Roles, Permissions, Membership Changes, Bans, and Leaving

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| RP-004 | Every mutating action is authorized locally and again on receive | A, B, C, and X attempt every mutating group action. | 1. Exercise create, update, invite, approve, send, react, pin, remove, ban, rotate, close, and metadata edits. 2. Replay as remote events. | Unauthorized actions are blocked before local side effects and revalidated on receive before applying remote state. | P0 | Partial | Required | Required | Required | Required | Recommended | FR-078, FR-079, FR-317. Many individual guards exist, but no complete trusted-private action matrix is pinned. |
| RP-005 | Stale permission rejection after demotion, removal, or role race | B queues actions while authorized, then loses permission before publish or receive. | 1. Queue invite, send, metadata, role, and key actions. 2. Demote/remove B. 3. Reconnect and publish queued actions. | Actions signed under stale state are rejected or rechecked before publication and cannot mutate group state. | P0 | Partial | Required | Required | Recommended | Required | Recommended | FR-080, FR-082, FR-350, FR-216, FR-217. |
| RP-006 | Permission escalation protection | B has limited moderation permission. | 1. B tries to grant themselves or others higher permissions. 2. Replay remote role changes. | Members cannot grant permissions they do not possess, and forged/escalated role changes are rejected. | P0 | Open | Required | Required | Recommended | Recommended | Recommended | FR-083. |
| RP-014 | Voluntary leave key rotation policy is enforced | B leaves a group where post-leave access to future content is blocked by policy. | 1. B leaves. 2. A sends after leave. 3. B replays and attempts decrypt. | If policy requires rotation on leave, B cannot decrypt post-leave content; remaining members converge on the new epoch. | P0 | Open | Required | Required | Recommended | Recommended | Required | FR-096, FR-174, FR-175. |
| RP-017 | Removed peer isolation blocks continued publishing and dialing | C is removed but keeps publishing to the old topic and dialing peers. | 1. Remove C. 2. C publishes live messages, sync requests, media, and key events. 3. Observe connections and local rejection behavior. | Peers disconnect, block, or ignore C according to policy; no new rows or keys are accepted. | P0 | Partial | Required | Required | Recommended | Required | Recommended | FR-103, FR-259, FR-281. |
| RP-018 | Membership add, remove, and role conflicts converge deterministically | A and B perform conflicting membership actions while partitioned. | 1. Concurrently add/remove/promote/demote C. 2. Heal partition. 3. Sync all peers. | Every peer converges on the same membership and permission state with clear conflict diagnostics if needed. | P0 | Partial | Required | Required | Recommended | Required | Required | FR-102, FR-269. Key conflict coverage exists; membership conflict coverage remains incomplete. |

## Messaging, Ordering, Editing, Deletion, Reactions, Mentions, and Drafts

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| MS-002 | Message author, device identity, and Peer ID binding are verified | B sends from a valid device; X spoofs B or uses mismatched Peer ID. | 1. Deliver valid, spoofed, and device-mismatched messages. 2. Inspect validators and stored author fields. | Every stored message has verifiable author and device identity bound to the transport Peer ID. | P0 | Partial | Required | Required | Required | Required | Recommended | FR-109, FR-171, FR-316. |
| MS-003 | Clock skew does not corrupt message order | A, B, and C have skewed clocks. | 1. Send messages with past, future, and normal client timestamps. 2. Sync through live and inbox paths. | Receive timestamps and ordering rules prevent impossible timeline jumps or state corruption while preserving useful client-time display. | P0 | Open | Required | Required | Recommended | Required | Recommended | FR-110, FR-111, FR-361. |
| MS-004 | Deterministic ordering and causal references under concurrent sends | A, B, and C send concurrently and reply to recent messages. | 1. Send concurrent messages across partitions. 2. Include parent or previous-state references. 3. Heal and sync. | All peers render a deterministic order and replies remain attached to the right causal parent. | P0 | Open | Required | Required | Recommended | Required | Required | FR-112, FR-113, FR-114. |
| MS-018 | Messages created during key rotation bind to exactly one valid epoch | A rotates key while B sends. | 1. Start rotation. 2. Send before, during, and after epoch commit. 3. Deliver out of order. | Each message is bound to a specific epoch and is sent, queued, or rejected according to current validity. | P0 | Partial | Required | Required | Recommended | Required | Required | FR-175, FR-176, FR-177, FR-360. Member-removal rotation is covered; send/rotation race needs direct stress coverage. |

## Encryption, Key Epochs, Identity Verification, and Secret Handling

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| EK-003 | Member identity key, device key, and Peer ID binding are enforced | B rotates devices or Peer IDs; X spoofs identity fields. | 1. Bind valid device to member identity. 2. Attempt spoofed Peer ID and device key mismatch. | Only correctly bound identities can send, receive key updates, or apply membership events. | P0 | Partial | Required | Required | Recommended | Required | Recommended | FR-169, FR-170, FR-171, FR-316. |
| EK-004 | Signature verification covers every security-relevant event type | Messages, invites, membership, roles, settings, key updates, and audit events are signed. | 1. Tamper each event family. 2. Replay with valid and invalid signatures. | Every invalid signature is rejected before local state mutation and produces privacy-safe diagnostics. | P0 | Partial | Required | Required | Required | Required | Recommended | FR-172, FR-256, FR-330. Some Go validator coverage exists; full event-family matrix is missing. |
| EK-005 | Unknown future epoch messages queue and trigger key sync repair | B receives a message encrypted for an epoch not yet known. | 1. Deliver future-epoch message. 2. Deliver missing epoch transitions. 3. Attempt decrypt. | Future messages are queued or marked pending until key sync completes, then decrypt or become safely undecryptable. | P0 | Open | Required | Required | Recommended | Required | Recommended | FR-176, FR-218, FR-219. |
| EK-006 | Stale epoch messages from invalid senders are rejected | C sends after removal or after stale epoch expiry. | 1. Remove C and rotate keys. 2. Deliver old-epoch and grace-window messages. 3. Expire grace and replay. | Only policy-allowed grace traffic is accepted; stale or unauthorized epoch traffic is rejected. | P0 | Partial | Required | Required | Recommended | Required | Recommended | FR-177, FR-349. Go grace tests exist; app-level sender validity and UI outcome need broader coverage. |
| EK-011 | Welcome messages and key packages are validated before admission | C joins with valid, stale, malformed, and weak key packages. | 1. Submit each key package. 2. Attempt welcome decrypt and first send. | Only valid key packages are admitted and welcome material decrypts on the intended device. | P0 | Partial | Required | Required | Recommended | Recommended | Recommended | FR-186, FR-187, FR-063. Invite-key flow exists; key package validation is not complete. |
| EK-012 | Replay protection covers messages, commits, invites, and key packages | X replays old encrypted payloads and key artifacts. | 1. Replay each artifact family with same and modified metadata. 2. Observe DB, epoch, and diagnostics. | Replays are rejected or idempotent and cannot roll back membership, permissions, or keys. | P0 | Partial | Required | Required | Required | Required | Recommended | FR-188, FR-189, FR-190. Message replay and nonce tests exist; commits, invites, and key packages remain broader. |

## Offline Delivery, Sync, Reconnect, and History Repair

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| OS-006 | Partial history, gap detection, and multi-peer gap repair | B only receives some pages or one peer lacks history. | 1. Create missing ranges. 2. Detect gaps. 3. Repair from multiple peers. | The UI marks partial history honestly and repairs gaps without duplicate or out-of-order rows. | P0 | Open | Required | Required | Recommended | Required | Recommended | FR-211, FR-212, FR-213. |

## Local Database, Migrations, Event Log, Search, and State Recovery

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| DB-002 | Signed append-only or tamper-evident local event log | Remote group events are applied locally. | 1. Persist membership, metadata, messages, roles, and key commits. 2. Tamper and replay. | The local event log detects tampering and can explain applied state without silent mutation. | P0 | Open | Required | Required | Recommended | N/A | N/A | FR-239, FR-330. |
| DB-004 | Transactional update boundaries survive crash | Message insert, receipt update, and sync cursor update happen together. | 1. Crash between each operation boundary. 2. Restart and repair. | No half-applied state causes duplicate messages, lost receipts, or advanced cursors without rows. | P0 | Partial | Required | Required | Recommended | N/A | N/A | FR-245, FR-246. Crash-window send durability exists; transaction coverage for all update groups is broader. |
| DB-006 | Plaintext secret keys are excluded from ordinary message tables | Secret keys, media keys, and recovery material exist locally. | 1. Store and rotate keys. 2. Inspect group, message, media, and event tables. | Secrets are stored only in approved secure storage, not ordinary tables. | P0 | Open | Required | Required | Recommended | N/A | N/A | FR-249, FR-192, FR-334. |
| DB-012 | Idempotent apply covers every remote event type | Remote events can be delivered multiple times. | 1. Apply duplicate messages, metadata, roles, joins, leaves, bans, deletes, receipts, media, and commits. | Applying the same event repeatedly produces the same local state and no duplicate visible timeline spam. | P0 | Partial | Required | Required | Recommended | Recommended | Recommended | FR-244. Several idempotency tests exist; all-event coverage is incomplete. |

## Error Handling, Retry Behavior, Recovery Prompts, Audit, and Observability

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ER-001 | Invalid signature diagnostics are privacy-safe and actionable | X sends invalid signatures for every event family. | 1. Inject invalid signatures. 2. Inspect logs, metrics, and UI. | Invalid items are rejected, counted, and logged without secret material or sensitive peer addresses. | P0 | Partial | Required | Required | Recommended | Required | N/A | FR-256, FR-271, FR-341. Some validator diagnostics exist; full app/Go/logging coverage remains broader. |
| ER-002 | Unknown and removed sender quarantine has no ghost UI rows | X is unknown or removed. | 1. Send valid-looking messages, media, reactions, and receipts. 2. Observe quarantine, notifications, and DB. | Unknown or removed sender traffic is rejected or quarantined without visible ghost messages or notifications. | P0 | Partial | Required | Required | Recommended | Required | Recommended | FR-258, FR-259. Incoming unknown-member tolerance exists; quarantine policy is not complete. |
| ER-004 | Decryption failure triggers key repair and safe placeholder UI | B receives undecryptable content. | 1. Deliver wrong-key, missing-key, future-epoch, and tampered payloads. 2. Trigger repair. | The app does not crash, does not create plaintext rows, attempts key sync where possible, and shows a safe placeholder when unrecoverable. | P0 | Partial | Required | Required | Recommended | Required | Recommended | FR-263, FR-275, FR-308. Go diagnostics exist; UI repair path is not complete. |
| ER-005 | Safe error messages never expose secrets or sensitive peer data | Failures occur across invite, sync, media, key, discovery, and bridge paths. | 1. Force each error. 2. Capture snackbar, logs, diagnostics export, and flow events. | User-visible errors are actionable and never expose keys, raw encrypted blobs, internal dumps, or sensitive multiaddrs. | P0 | Open | Required | Required | Recommended | N/A | N/A | FR-270, FR-344. |

## Abuse Prevention, Moderation, Limits, and Safety

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| AB-006 | Suspicious or oversized media does not auto-download | X sends suspicious media descriptors. | 1. Deliver large, mismatched, dangerous, and untrusted media. 2. Inspect auto-download behavior. | Suspicious media remains blocked or manual-only until validation passes. | P0 | Open | Required | Required | Recommended | Recommended | Recommended | FR-285, FR-152, FR-165. |

## UI System State, User-Facing Truth, and Accessibility

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| UI-003 | Key change, encryption status, and verification warnings are visible | A key rotates or identity changes. | 1. Rotate key. 2. Change device identity. 3. Open group security surfaces. | Users see clear encrypted-state, verified-member, identity-change, and key-change warnings. | P0 | Open | Required | Required | Recommended | N/A | Recommended | FR-303, FR-304, FR-305, FR-195. |
| UI-005 | Undecryptable placeholders are safe and policy-compliant | Messages cannot decrypt or are unavailable because the required key/material is missing. | 1. Deliver undecryptable content. 2. Open all surfaces. | Placeholders do not reveal content, explain repair where possible, and do not break layout. | P0 | Partial | Required | Required | Recommended | N/A | Recommended | FR-308, FR-309, FR-263. Decryption diagnostics exist; UI placeholder coverage is missing. |

## Security, Privacy, Metadata Controls, Backup, and Secret Controls

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SP-001 | Peer authentication and request authorization cover every protocol | X connects with valid transport but no group authorization. | 1. Attempt invite, sync, media, receipt, key, and diagnostics requests. | Every request authenticates the peer and authorizes against current group state before processing. | P0 | Partial | Required | Required | Required | Required | Recommended | FR-316, FR-317. PubSub validator coverage exists; every request protocol is broader. |
| SP-002 | Metadata minimization covers topics, discovery, relays, push, and diagnostics | Sensitive group membership and names exist. | 1. Inspect topic names, discovery records, relay addresses, push payloads, logs, and diagnostics. | The app exposes only unavoidable metadata and documents or warns about relay-visible participation metadata. | P0 | Partial | Required | Required | Recommended | Required | Recommended | FR-318, FR-319, FR-320, FR-321. |
| SP-003 | Secure random generation is used for IDs, keys, nonces, tokens, and salts | Random artifacts are generated repeatedly. | 1. Generate many group IDs, keys, nonces, invite tokens, and salts. 2. Check uniqueness and source constraints. | Artifacts are generated from cryptographically secure randomness and collision rates stay within policy. | P0 | Partial | Required | Recommended | N/A | N/A | N/A | FR-322, FR-002, FR-190. Group key/nonce tests exist; all artifact classes are not covered. |

## Edge Cases, Invalid Actions, and Fork Handling

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| EC-001 | Invite expiry, revocation, wrong identity, and already-used errors are distinct | C attempts invalid invite accepts. | 1. Accept expired, revoked, wrong-identity, malformed, and already-used invites. 2. Inspect UI and local state. | Each failure is classified safely and no group/key state is created. | P0 | Partial | Required | Required | Recommended | Recommended | Recommended | FR-267, FR-351, FR-352, FR-353. Expiry is covered; revocation, wrong identity, and already-used are not. |
| EC-003 | Future-dated or future-epoch events queue, expire, or reject safely | X or delayed peers deliver future events. | 1. Send future timestamp, future epoch, and missing-dependency events. 2. Later deliver dependencies or let them expire. | Future state does not corrupt current state and resolves only when dependencies become valid. | P0 | Open | Required | Required | Recommended | Required | Recommended | FR-361, FR-176. |
| EC-004 | Old but valid events apply only if they do not conflict with finalized newer state | Delayed old events arrive after newer state is finalized. | 1. Apply newer remove, role, key, and tombstone events. 2. Deliver older valid messages and membership updates. | Old events are accepted only within policy cutoffs and cannot roll back finalized newer state. | P0 | Partial | Required | Required | Recommended | Required | Recommended | FR-362, FR-080. Some removed/dissolve cutoffs exist; full old-event matrix is not complete. |
| EC-006 | Replayed tombstones cannot corrupt current state | Old delete, leave, remove, ban, unban, and dissolve tombstones are replayed. | 1. Replay tombstones before and after rejoin/reinvite. 2. Inspect state. | Tombstone replay is idempotent and cannot delete current valid membership or messages outside its scope. | P0 | Partial | Required | Required | Recommended | Recommended | Recommended | FR-365, FR-015. Dissolve replay exists; all tombstone types need coverage. |
| EC-007 | Role change after demotion and invite after removal are rejected across offline replay | B is demoted or removed while queued actions exist. | 1. B queues role changes and invites. 2. A demotes/removes B. 3. B reconnects and publishes. | Queued stale actions fail locally and remotely and do not create invites, role changes, or audit confusion. | P0 | Partial | Required | Required | Recommended | Required | Recommended | FR-348, FR-350, FR-080. |

## Recommended trusted-private smoke suite for gap closure

These smoke specs are intentionally scenario-level. Each can assert multiple matrix rows while keeping runtime bounded.

| Smoke ID | Purpose | Covers |
|---|---|---|
| TP-SMOKE-01 | Create a trusted-private group, add trusted contacts, reject non-trusted identities, and keep membership deterministic across restart. | `GL-005`, `IJ-002`, `IJ-003`, `IJ-009`, `IJ-013` |
| TP-SMOKE-02 | Send while one member is offline, restart multiple clients, replay history exactly once, and preserve pinned chat metadata. | `LP-002`, `LP-003`, `RP-017`, `EC-006` |
| TP-SMOKE-03 | Exercise group encryption, sender attribution, corrupted payload rejection, unknown-key handling, and multi-device sender continuity. | `EK-003`, `EK-004`, `EK-005`, `EK-012`, `SP-001` |
| TP-SMOKE-04 | Force relay churn and sync gaps, then verify group history and unread state recover without duplicates. | `OS-006` |
| TP-SMOKE-05 | Verify suspicious or oversized group media stays blocked before persistence and delivery side effects. | `AB-006` |
| TP-SMOKE-06 | Render mixed group history, unread separators, and message actions after restart and replay. | `UI-003`, `UI-005` |
| TP-SMOKE-07 | Preserve lifecycle, profile, and device-level state across leave, rejoin, rename, restart, and relay recovery. | `LP-013`, `SP-002` |

## Removed non-fitting rows from earlier broad matrix ideas

The following test ideas were intentionally not included because they require semantics outside trusted-private direct membership:

- Public discoverable groups.
- Open joins by room code or invite link.
- Server-authoritative admin/moderator role management.
- Kicking/banning arbitrary members in a public room.
- Bot accounts and webhooks.
- Federated group search.
- Full generic relay/load testing with no group-chat assertion.
- Cosmetic theme tests with no group-chat correctness risk.
- Payment, entitlement, or subscription behavior.

## Suggested implementation order

1. Membership and trusted-contact gating: `GL-005`, `IJ-002`, `IJ-003`, `IJ-005`, `IJ-009`, `IJ-013`, `RP-004`, `RP-005`, `RP-006`, `SP-001`.
2. Persistence and replay: `LP-003`, `RP-014`, `RP-017`, `EK-003`, `EK-004`, `EK-011`, `EK-012`, `EC-006`.
3. Offline, restart, and relay recovery: `OS-006`, `RP-018`, `DB-012`.
4. Media and metadata: `MS-002`, `MS-003`, `MS-004`, `MS-018`.
5. UI, DB resilience, and error surfaces: `UI-003`, `UI-005`, `DB-002`, `DB-004`, `DB-006`, `ER-005`.
