# Trusted Private libp2p Group Chat Missing Test Matrix - Moved Rows v1

This file contains rows moved out of the active trusted-private group-chat matrix during the current implementation review on 2026-04-30. These rows are preserved for traceability, but they are not considered near-term verification gaps for the implemented feature.

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

- This file contains the 34 rows removed from the active trusted-private group-chat gap matrix on 2026-04-30.
- These rows are not deleted because they may still be useful as historical context or future review material.
- They should not drive near-term work unless a future bug report, product decision, or implementation change makes the row relevant again.
- The active retained matrix remains in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`.

## Move reasons

- Already covered or no new current-code work: `GL-001`, `GL-002`, `GL-008`, `GL-009`, `LP-001`, `MS-001`, `AN-008`, `MD-001`, `MD-002`, `MD-003`, `MD-004`, `MD-011`, `MD-012`, `EK-001`, `EK-002`, `EK-013`, `OS-001`, `OS-005`, `OS-008`, `OS-009`, `NT-001`, `NT-006`, `DB-001`
- Product primitive or deferred behavior outside this review: `IJ-012`, `RP-010`, `RP-016`, `EK-007`, `EC-005`
- Evidence-gated or not in the current Flutter-owned path: `LP-006`, `LP-007`, `LP-011`, `OS-010`, `OS-012`
- Not retained after current implementation review: `RP-003`

## Group Lifecycle, Metadata, Schema, and Governance Truth

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| GL-001 | Group ID uniqueness and duplicate-create safety | A can create groups; a collision or duplicate create event can be injected. | 1. Force two create attempts to use the same candidate `group_id`. 2. Replay the same signed create event. 3. Inspect local group rows, topic subscriptions, and timeline. | Only one canonical group exists, no duplicate topic subscription is created, and duplicate create events are idempotent or rejected according to policy. | P0 | Partial | Required | Required | Recommended | Recommended | N/A | FR-002, FR-346. Current create coverage proves happy path, but not collision or duplicate create-event handling. |
| GL-002 | Initial membership state includes creator device identity and signed initial epoch | A creates a group from a device with known user, device, and Peer ID identities. | 1. Create the group. 2. Inspect persisted group, member, key, and event state. 3. Verify signature, role, join timestamp, device identity, and epoch. | The creator is the initial owner/admin, the exact creating device is recorded, and the initial epoch and membership event can be verified after restart. | P0 | Partial | Required | Required | Required | N/A | Recommended | FR-003, FR-004, FR-062, FR-016. Existing tests save creator/admin and key, but do not prove device identity or a signed canonical initial state event. |
| GL-008 | Deletion, closure, and tombstone prevent resurrection | A group can be locally deleted, globally closed, or dissolved. | 1. Delete or close the group. 2. Replay old messages, metadata, member events, and key updates. 3. Sync from another peer. | Closed/deleted state is represented by a durable tombstone where required; old state cannot resurrect the group or produce new visible messages. | P0 | Partial | Required | Required | Required | Recommended | Recommended | FR-013, FR-014, FR-015, FR-365. Dissolve idempotency exists, but full tombstone and resurrection policy is broader. |
| GL-009 | Settings versioning, actor signature, and canonical group state hash | Groups have mutable settings, permissions, membership, and epoch state. | 1. Apply a settings change. 2. Verify signed actor, monotonic version, and canonical hash. 3. Replay and tamper with the change. | Every settings change is signed, versioned, and reflected in the canonical state hash; replay/tamper attempts fail closed. | P0 | Open | Required | Required | Recommended | Recommended | Recommended | FR-016, FR-017, FR-330. No dedicated settings-version or canonical state-hash tests appear in the inventory. |

## libp2p Topology, Topics, Discovery, and Protocol Negotiation

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| LP-001 | Group PubSub topic derivation avoids human-readable metadata | A creates groups with sensitive names and descriptions. | 1. Create groups with sensitive names. 2. Inspect topic names, rendezvous namespaces, logs, and diagnostics. | Topic and rendezvous names derive from `group_id` or a privacy-preserving transform and do not expose human-readable group metadata. | P0 | Partial | Required | Required | Recommended | Required | N/A | FR-021, FR-022, FR-318. Go tests cover topic naming, but not sensitive metadata leakage across logs and discovery records. |
| LP-006 | Private bootstrap and rendezvous fallback when no trusted peers are reachable | A device has no currently reachable known group peers but may use approved bootstrap, rendezvous, relay, or mailbox infrastructure. | 1. Clear known reachable peers. 2. Attempt reconnect through configured private bootstrap/rendezvous/relay/mailbox paths. 3. Inspect metadata and error states. | The device can regain contact when infrastructure is available; fallback records do not expose group name, member list, plaintext, or open-join capabilities. | P0 | Partial | Required | Required | Recommended | Required | Recommended | FR-026, FR-031, FR-318. This remains important for trusted groups because discoverability is private but reconnection must still work. |
| LP-007 | Relay-assisted group delivery keeps content end-to-end encrypted | A and B can communicate only through a relay. | 1. Force direct dialing failure. 2. Send text, media metadata, key updates, invites, and sync traffic through relay. 3. Inspect relay-visible payload. | Relays can help trusted members connect, but relays only see minimized routing metadata and cannot decrypt messages, media, invites, or sync payloads. | P0 | Partial | Required | Required | Required | Required | Required | FR-032, FR-166, FR-168, FR-321. Trusted users do not make relay/mailbox peers trusted for content. |
| LP-011 | Versioned protocol IDs and negotiation for all group streams | Peers support different app protocol versions. | 1. Open group sync, invite, media, receipt, and key-exchange streams. 2. Negotiate compatible and incompatible versions. | Compatible versions select a supported protocol ID; incompatible peers are rejected safely before state mutation. | P0 | Open | Required | Required | Recommended | Required | Recommended | FR-036, FR-037, FR-038. |

## Invitations, Join Flows, and Device Admission

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| IJ-012 | Device-specific admission distinguishes new human member from new device | B adds a second device; D is a new human member. | 1. Add B2 through self-authentication or admin approval. 2. Add D through invite. 3. Inspect member rows, device keys, and permissions. | B2 is bound to B without duplicating human membership; D appears as a distinct member and receives only allowed key material. | P0 | Partial | Required | Required | Recommended | Recommended | Required | FR-069, FR-070, FR-170, FR-194. Multi-device policy exists, but admission approval is not proven. |

## Roles, Permissions, Membership Changes, Bans, and Leaving

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| RP-003 | Owner protection and ownership handoff cannot orphan the group | A is the last owner, with or without other admins. | 1. Attempt demotion, removal, leave, and ownership transfer. 2. Sync peers. | The group never enters an ownerless/adminless state unless an explicit ownerless governance policy allows it. | P0 | Partial | Required | Required | Recommended | Recommended | Recommended | FR-074, FR-100, FR-347. Last-admin guard exists; owner semantics and simultaneous owner transfers do not. |
| RP-010 | Remove one device without removing the whole member | B has two devices in the group. | 1. Remove B2 only. 2. Rotate keys. 3. Verify B1 can continue and B2 cannot decrypt or send. | Specific device removal revokes that device, preserves the member account, and excludes the revoked device from future epochs. | P0 | Open | Required | Required | Recommended | Recommended | Required | FR-090, FR-094, FR-179, FR-194, FR-323. |
| RP-016 | Rejoin policy after removal and after ban differs correctly | C is removed in one run and banned in another. | 1. Try reinvite and join after removal. 2. Try the same after ban. | Removed users can rejoin only if policy permits; banned users remain blocked until unbanned. | P0 | Partial | Required | Required | Recommended | Recommended | Required | FR-104, FR-105. Re-add after removal exists; ban policy is missing. |

## Messaging, Ordering, Editing, Deletion, Reactions, Mentions, and Drafts

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| MS-001 | Message ID collision handling under rapid, offline, and multi-device sends | A, B, and B2 can send many messages at the same time. | 1. Force generated ID collision and rapid sends. 2. Replay duplicate IDs with different content. 3. Sync all devices. | Collisions are detected and resolved or rejected without overwriting trusted messages. | P0 | Partial | Required | Required | Recommended | Required | Recommended | FR-108, FR-188. ID generation exists; collision safety is not directly tested. |

## Announcement-Specific Product Behavior

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| AN-008 | Announcement media background-task coverage is unskipped | Announcement with media is sent while background tasks are active. | 1. Enable previously skipped background-task cases. 2. Send announcement media. 3. Observe lifecycle and order-recording bridge. | Background begin/end, media metadata, and order-recording bridge behavior are covered without skipped tests. | P0 | Partial | Recommended | Required | Recommended | N/A | Recommended | FR-136, FR-146, FR-150. Inventory calls out skipped `group_conversation_wired_bg_task_test.dart` rows. |

## Media Transfer, Safety, Integrity, and Cache Behavior

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| MD-001 | Media MIME allowlist and dangerous type rejection | Allowed and blocked MIME types are configured. | 1. Send image, video, voice, spoofed MIME, executable, and malformed type. 2. Replay remotely. | Only allowed media types are accepted; dangerous or spoofed media is blocked before display or storage. | P0 | Open | Required | Required | Recommended | Recommended | N/A | FR-146, FR-147, FR-148, FR-152, FR-165. |
| MD-002 | Per-media and total-message size limits apply on send and receive | Media size limits are configured. | 1. Send boundary and oversized media. 2. Deliver oversized remote and inbox payloads. | Oversized media is rejected safely and does not trigger downloads, crashes, or misleading sent states. | P0 | Open | Required | Required | Recommended | Recommended | Recommended | FR-151, FR-261, FR-285. |
| MD-003 | Encrypted content hash and thumbnail hash are verified before display | Media metadata contains hashes and encrypted content IDs. | 1. Download valid media. 2. Tamper chunk, hash, thumbnail, and metadata. | Only verified media is displayed or saved; failed hash/decrypt checks quarantine the item. | P0 | Partial | Required | Required | Recommended | Recommended | Recommended | FR-150, FR-155, FR-165. Media persistence exists; integrity verification before display is broader. |
| MD-004 | Each media object uses a distinct encryption key or derivation context | A sends multiple media attachments in one message and across messages. | 1. Capture encrypted media descriptors. 2. Verify key separation or context separation. 3. Attempt cross-object decrypt. | Compromise or reuse of one media key does not decrypt unrelated media objects. | P0 | Open | Required | Required | N/A | N/A | N/A | FR-153, FR-154. |
| MD-011 | Removed members do not receive future media keys or content | C is removed before A sends media. | 1. Remove C and rotate keys. 2. Send media. 3. C attempts download/decrypt from live, sync, and relay. | C cannot access future media descriptors, keys, or decrypted content. | P0 | Partial | Required | Required | Recommended | Recommended | Required | FR-094, FR-164, FR-179. Removed-member key exclusion exists; media-specific proof is missing. |
| MD-012 | Unsafe media quarantine and retry UI | Media fails validation, hash check, decrypt, or local safety checks. | 1. Deliver failing media variants. 2. Open message row. 3. Retry after repair. | The UI shows unavailable/quarantined media with safe retry controls and never renders untrusted content. | P0 | Open | Required | Required | Recommended | Recommended | Recommended | FR-165, FR-264, FR-313, FR-314. |

## Encryption, Key Epochs, Identity Verification, and Secret Handling

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| EK-001 | Secure libp2p channels are required before group protocol messages | A peer attempts group protocol traffic over secure and insecure channels. | 1. Disable or downgrade secure channel. 2. Attempt invite, sync, media, and publish. | Insecure channels cannot exchange group protocol messages; failures are logged safely. | P0 | Open | Required | Required | Recommended | Required | N/A | FR-167, FR-316. |
| EK-002 | Application-layer encryption protects relay, mailbox, and stored sync payloads | Relay, mailbox, and store-and-forward peers can inspect their stored bytes. | 1. Send text, media, invite, receipts, and key events through storage paths. 2. Inspect stored payloads. | Non-member infrastructure cannot read message content, media keys, invite secrets, or private group state. | P0 | Partial | Required | Required | Required | Required | Required | FR-166, FR-168, FR-318. Encrypted wire envelope coverage exists; complete storage-path privacy remains broader. |
| EK-007 | Scheduled and manual key rotations preserve epoch continuity | Periodic and manual rotation are configured. | 1. Run scheduled rotation. 2. Trigger manual rotation. 3. Send before and after. | Epoch numbers advance monotonically, all current members receive keys, and old/new messages bind to correct epochs. | P0 | Partial | Required | Required | Recommended | Recommended | Recommended | FR-174, FR-180, FR-181. Manual/scheduled rotations are not fully covered. |
| EK-013 | Obsolete keys are deleted and secrets use secure storage | Key retention policy is configured. | 1. Rotate keys and leave/remove members. 2. Inspect local DB and secure storage. | Obsolete secrets are deleted according to policy and ordinary tables do not hold plaintext secrets. | P0 | Open | Required | Required | Recommended | N/A | N/A | FR-191, FR-192, FR-193, FR-249, FR-334. |

## Offline Delivery, Sync, Reconnect, and History Repair

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| OS-001 | Offline send queue publishes in deterministic order after restart | B creates multiple offline messages and restarts before reconnect. | 1. Queue text, quote, reaction, and media sends offline. 2. Restart. 3. Reconnect and publish. | Queued operations publish in deterministic valid order without losing drafts, IDs, or attachment state. | P0 | Partial | Required | Required | Recommended | Required | Recommended | FR-196, FR-197, FR-198. Retry/resume exists; deterministic queued-order after restart needs direct proof. |
| OS-005 | Store-and-forward and mailbox peers keep offline content encrypted | Designated peers store messages and invites for offline members. | 1. Store text, media descriptors, invites, and receipts. 2. Retrieve as recipient. 3. Inspect storage peer data. | Offline storage enables retrieval without exposing plaintext or unauthorized group metadata. | P0 | Partial | Required | Required | Recommended | Required | Required | FR-208, FR-209, FR-053, FR-168. |
| OS-008 | Offline sender removed remotely before reconnect cannot publish stale sends | B queues sends offline; A removes B while B is offline. | 1. B queues messages. 2. A removes B and rotates keys. 3. B reconnects. | B verifies membership before publication and queued sends fail locally without reaching the group. | P0 | Open | Required | Required | Recommended | Required | Required | FR-216, FR-217, FR-349. |
| OS-009 | Irrecoverable epoch gap creates safe undecryptable placeholders | B misses multiple key epochs and cannot recover one. | 1. Deliver encrypted messages for missing epochs. 2. Fail key repair. 3. Open conversation. | Affected messages are marked undecryptable with safe UI and no plaintext guesswork. | P0 | Open | Required | Required | Recommended | Recommended | Recommended | FR-218, FR-219, FR-263, FR-308. |
| OS-010 | Same-account multi-device sync covers messages, read state, keys, drafts, and membership | B has two enrolled devices or deterministic device identities. | 1. Join on B1. 2. Add B2. 3. Send, read, draft, rotate key, and change membership. | Both devices converge on allowed shared state while device-local state remains device-specific. | P0 | Partial | Recommended | Required | Recommended | Required | Recommended | FR-220. Use deterministic integration first; real-device proof is non-gating unless multi-device launch scope explicitly requires it. |
| OS-012 | Real bridge/GossipSub network partition heals with backlog and live delivery | A, B, and C are on a real or simulator network. | 1. Partition B. 2. Send split-window backlog. 3. Heal and send live message. | Missed backlog replays in order and post-heal live delivery works without duplicates. | P0 | Partial | N/A | Required | Recommended | Required | Required | FR-202, FR-212, FR-213. Inventory notes host coverage and residual real partition-heal proof. |

## Notifications, Unread State, Receipts, and Privacy

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| NT-001 | Push bridge is encrypted or metadata-minimized | Mobile push bridge is enabled. | 1. Trigger text, media, mention, and announcement pushes. 2. Inspect push payloads. | Push payloads expose only allowed metadata and honor hidden sender/content/group settings. | P0 | Partial | Required | Required | Recommended | Recommended | Required | FR-222, FR-227, FR-318. Push routing exists; privacy-minimized payload matrix is incomplete. |
| NT-006 | Notification dedupe across PubSub, sync, push, and foreground drain | Same message arrives through multiple paths. | 1. Deliver same message live, via inbox, via foreground push drain, and via sync. 2. Inspect notifications and unread. | The user receives at most one notification and counts update exactly once. | P0 | Partial | Required | Required | Required | Recommended | Required | FR-236. Foreground drain dedupe exists; full PubSub/sync/push matrix remains broader. |

## Local Database, Migrations, Event Log, Search, and State Recovery

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| DB-001 | Original group table creation migrations before 026 are tested | A clean database is migrated from pre-group versions. | 1. Run migrations that create groups, group messages, members, and keys. 2. Insert and query baseline rows. | Original group tables are created idempotently with expected columns, defaults, and constraints. | P0 | Open | Required | Required | Recommended | N/A | N/A | FR-237, FR-238. Inventory explicitly calls out missing migration coverage before 026. |

## Edge Cases, Invalid Actions, and Fork Handling

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| EC-005 | Malicious fork detection identifies incompatible signed state from same actor | A malicious or compromised actor signs conflicting events. | 1. Deliver two incompatible signed commits or role/state changes from same actor. 2. Sync peers. | Forks are detected, quarantined, resolved, or surfaced with clear warning according to policy. | P0 | Open | Required | Required | Recommended | Required | Recommended | FR-363, FR-364. |

## Status

These rows were moved out of the active matrix during the 2026-04-30 review. Keep them as reference material only; they should stay out of the near-term verification set unless fresh implementation evidence makes a row relevant again.
