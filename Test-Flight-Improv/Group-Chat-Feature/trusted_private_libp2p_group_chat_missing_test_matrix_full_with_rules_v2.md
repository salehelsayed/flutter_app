# Trusted Private libp2p Group Chat Missing Test Matrix with Coverage Rules v2

This split contains rows moved out of the high-value launch matrix: all P1/P2 rows plus the deferred P0 rows `RP-011`, `MD-005`, and `OS-003` from the review analysis.

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

- This file contains rows moved out of the high-value split: all **P1** and **P2** rows, plus deferred **P0** rows `RP-011`, `MD-005`, and `OS-003`.
- Treat **P1** rows here as medium-value rollout/backlog candidates, not the current 83-row high-value set.
- Treat **P2** and **Unsupported** rows here as roadmap or scope-change references unless product scope changes.
- FR references in the Notes column indicate the requirement group covered by the missing test row.


## Group Lifecycle, Metadata, Schema, and Governance Truth

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| GL-003 | Group name validation covers length, encoding, profanity, and reserved names | Validation policy is configured with max length, accepted encodings, reserved names, and blocked terms. | 1. Try empty, over-limit, invalid Unicode, reserved, profane, and normal names. 2. Create and update groups through the app APIs. | Invalid names fail before local or bridge state is created; valid names persist and render consistently. | P1 | Partial | Required | Required | Recommended | N/A | N/A | FR-006. Inventory shows empty-name and update empty-name guards, but not full naming policy. |
| GL-004 | Profile update permission policy is enforced per field | Group policy can allow all members, moderators, admins, or owners to update profile fields. | 1. Attempt name, avatar, description, topic, and settings updates from each role. 2. Replay the same updates remotely. | Only roles allowed for the specific field can update it; unauthorized local and remote updates leave state unchanged and produce safe errors. | P1 | Partial | Required | Required | N/A | Recommended | Recommended | FR-007, FR-008, FR-078, FR-079. Current metadata tests prove admin/non-admin only. |
| GL-006 | Trusted group type matrix stays explicit for discussion and announcement | Trusted private groups support only the configured private group types, currently discussion and/or announcement. | 1. Create each supported private type. 2. Exercise send, reply, membership, notification, and moderation behavior for each role. 3. Attempt unsupported broadcast or mixed-mode creation if any API path exists. | Supported private types have clear write/read contracts; unsupported public, broadcast, or mixed modes are rejected or hidden. | P1 | Partial | Required | Required | Recommended | Recommended | Recommended | FR-010. Scope is narrowed to private discussion/announcement semantics; broadcast/mixed/public-room type tests are non-gating unless product scope changes. |
| GL-007 | One-member group behavior is deterministic and user-visible | A group has only one remaining member after leaves or removals. | 1. Remove or leave until one member remains. 2. Attempt send, invite, archive, dissolve, and delete. 3. Restart and sync. | The group either remains valid, is marked local-only, or is closed by policy; the UI and membership state agree. | P1 | Partial | Required | Required | Recommended | N/A | Recommended | FR-012. Sole-admin leave is tested, but single-member group semantics are not fully proven. |
| GL-010 | Deterministic conflict resolution for simultaneous metadata updates | A and B can both submit authorized metadata changes while partitioned. | 1. Partition peers. 2. Apply conflicting name/avatar/description changes. 3. Heal and sync. | All peers converge to the same chosen metadata or a clear conflict state using deterministic rules. | P1 | Open | Required | Required | N/A | Required | Recommended | FR-018. Existing metadata update coverage does not cover simultaneous conflict resolution. |
| GL-011 | Group schema migration and required protocol version advertisement | A device with older local group schema or protocol data starts after an upgrade. | 1. Seed old schema/protocol group state. 2. Run migration. 3. Join, sync, send, and inspect advertised protocol version. | Old groups migrate safely and peers that need a newer protocol see an explicit safe upgrade path. | P1 | Partial | Required | Required | Recommended | Recommended | N/A | FR-019, FR-020, FR-262. DB migrations exist, but app protocol-version advertisement is not pinned. |
| GL-012 | Optional create-time profile fields remain hidden or round-trip if enabled | Product scope enables description, avatar, or topic during create. | 1. Create a group with each profile field. 2. Inspect local DB, invite preview, Go bridge payload, and remote surfaces. | Description, avatar, and topic either round-trip consistently for trusted members or remain explicitly hidden/unsupported; no public preview is exposed. | P2 | Unsupported | Required | Recommended | N/A | N/A | N/A | FR-005. Trusted-private scope removes public preview concerns but still needs a guard if these fields appear in create, invite, or sync payloads. |

## libp2p Topology, Topics, Discovery, and Protocol Negotiation

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| LP-004 | Known-peer exchange and address update persistence | Peers advertise new multiaddrs during group sync. | 1. Exchange signed known-peer lists. 2. Update a peer address. 3. Restart and reconnect without bootstrap. | Stored Peer IDs and multiaddrs update only from authorized trusted group state and improve reconnect without exposing the member list outside the invited set. | P1 | Partial | Required | Required | N/A | Required | Recommended | FR-027, FR-028, FR-242. In trusted-private scope, known-peer exchange must stay membership-bound rather than public. |
| LP-005 | Identify integration and peerstore snapshots survive restart | A and B learn addresses through libp2p identify. | 1. Connect peers. 2. Capture identify data. 3. Persist peerstore snapshot. 4. Restart without fresh discovery. | The app can reconnect from persisted useful peerstore data and ignores stale or unauthorized identify information. | P1 | Open | Required | Required | N/A | Required | N/A | FR-029, FR-030. No dedicated identify or peerstore snapshot tests were found. |
| LP-008 | Hole punching attempts direct connectivity and falls back safely | Peers start behind NAT or relay-only paths with hole punching enabled. | 1. Establish relayed connectivity. 2. Trigger hole punching. 3. Observe direct upgrade, fallback, and diagnostics. | Direct connectivity is attempted when supported; failure leaves the relayed encrypted path usable and visible diagnostics remain safe. | P1 | Open | Recommended | Required | N/A | Required | Recommended | FR-033, FR-034. Current inventory shows direct-address preference, not hole punching behavior. |
| LP-009 | Connectivity mode detection drives user-safe state | Peers can be public, relayed, private-network-only, or offline. | 1. Simulate each mode. 2. Open diagnostics and conversation surfaces. 3. Send and sync. | The app distinguishes mode-specific states for trusted peers without exposing sensitive multiaddrs or peer internals in normal UI. | P1 | Open | Required | Required | Recommended | Required | Recommended | FR-034, FR-339, FR-270. Useful for seamless private-group troubleshooting without leaking low-level peer data. |
| LP-012 | Unsupported protocol rejection exposes safe upgrade guidance | X only supports an older or unknown group protocol. | 1. X connects and attempts group protocol messages. 2. Inspect diagnostics and UI error. | The peer is gracefully rejected, no sensitive group data leaks, and users see a safe upgrade message if action is needed. | P1 | Open | Required | Required | Recommended | Required | N/A | FR-038, FR-262, FR-270. |

## Invitations, Join Flows, and Device Admission

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| IJ-004 | Invite-link creation is disabled by default or constrained if explicitly enabled | Trusted private groups use direct identity-bound invites unless product explicitly enables invite links. | 1. Attempt invite-link creation through UI, service API, bridge, and replayed remote event. 2. If links are enabled, test rotation, invalidation, max uses, expiry, assigned role, and identity/domain restrictions. | By default, link creation is rejected or hidden. If enabled, links are bounded, revocable, signed, non-enumerable, and cannot become open public joins. | P1 | Open | Required | Required | Recommended | Recommended | N/A | FR-049, FR-050, FR-051. Trusted-private scope changes this from feature coverage to a guard against accidental public-room admission. |
| IJ-006 | Offline invite retrieval through mailbox or store-and-forward peer | C is offline when A sends an invite. | 1. Store an encrypted invite for C. 2. Bring C online through mailbox retrieval. 3. Accept or decline. | C sees a pending invite after retrieval; relay/mailbox peers cannot read sensitive invite contents. | P1 | Partial | Required | Required | Recommended | Required | Recommended | FR-052, FR-053, FR-209. Direct and pending invite tests exist, but mailbox retrieval privacy is not fully covered. |
| IJ-007 | Invite reject versus ignore behavior has no accidental side effects | C receives a valid invite. | 1. Reject in one run. 2. Ignore or dismiss in another. 3. Inspect pending rows, sender-visible state, and notifications. | Reject removes or records the invite per policy; ignore dismisses locally without leaking a rejection or joining. | P1 | Partial | Required | Required | N/A | N/A | Recommended | FR-057, FR-058. Decline exists; ignore/dismiss and sender-side side effects are not directly proven. |
| IJ-008 | Public join-request workflow is hidden or rejected for trusted-private groups | Groups are not discoverable public rooms; only identity-bound invites are in release scope. | 1. Attempt to submit join requests without an invite through UI, API, and network payloads. 2. Attempt admin approval of an unsolicited request if a stale surface exists. | Uninvited join requests do not create pending state, notifications, key material, or admin workload; any stale UI/API route returns a safe unsupported result. | P1 | Open | Required | Required | Recommended | Recommended | N/A | FR-059, FR-060. Trusted-private scope de-scopes public join queues but still needs guard tests if any route exists. |

## Roles, Permissions, Membership Changes, Bans, and Leaving

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| RP-001 | Configured trusted-group role model behavior is explicit | The product defines the trusted-group role set, such as owner, admin, moderator, member, read-only member, and banned/removed identity if supported. | 1. For each configured role, attempt invite, approve/add, send, announce, pin, edit group info, change roles, remove, ban, rotate keys, and close. 2. Replay remote actions from each role. | Every configured role has deterministic permissions; unconfigured public-room roles are unavailable and cannot be used through stale payloads. | P1 | Partial | Required | Required | Recommended | Recommended | Recommended | FR-071, FR-073. Trusted-private scope may use a smaller role set, but all exposed roles still require explicit tests. |
| RP-002 | Custom permission flags override role names safely | Permission flags can be granted independently from role labels. | 1. Assign capabilities such as invite, pin, remove, or rotate without changing role. 2. Execute local and remote actions. | Permission flags control behavior consistently and never grant broader authority than configured. | P1 | Open | Required | Required | Recommended | Recommended | Recommended | FR-072, FR-073, FR-078, FR-079. Keep P1 unless custom flags are used to enforce removal, invite, send, or key-rotation authority; then promote to P0. |
| RP-008 | Group read-only mode is distinct from announcement groups | A enables read-only mode in a discussion group. | 1. Members attempt sends, reactions, replies, and media. 2. Authorized announcers post. | The whole group becomes read-only except authorized senders, with UI controls and remote validation matching. | P1 | Partial | Required | Required | Recommended | Recommended | Recommended | FR-085, FR-136. Announcement mode is covered, but general read-only mode is not. |
| RP-009 | Silent local leave later publishes or remains local by policy | B leaves while offline or bridge publish fails. | 1. Leave offline. 2. Restart. 3. Reconnect and sync with A. | B sees a truthful local-left state; the leave event is published later if policy allows, or clearly remains local-only. | P1 | Open | Required | Required | Recommended | Required | Recommended | FR-088, FR-087. |
| RP-011 | Ban and unban lifecycle blocks rejoin and future key material | A bans C and later unbans C. | 1. Ban C. 2. C attempts direct invite, link join, mailbox replay, and sync. 3. Unban and re-invite. | Banned identities cannot rejoin or receive future keys until unbanned; unban follows policy and is visible to authorized viewers. | P0 | Open | Required | Required | Required | Recommended | Required | FR-091, FR-092, FR-094, FR-105, FR-179. Even in trusted groups, ban/revoke paths are security-sensitive if exposed; otherwise treat as removal-only policy and keep ban UI/API hidden. |
| RP-012 | Ban and removal scope covers trusted identities, devices, Peer IDs, and invite tokens | Ban or removal policy is configured for trusted private groups. | 1. Remove or ban by user identity, device identity, Peer ID, and invite token where supported. 2. Attempt rejoin or publish through each scoped identity. 3. Inspect key updates. | All supported scopes block future admission and key material for the intended subject without blocking unrelated trusted members. | P1 | Open | Required | Required | N/A | Recommended | Recommended | FR-093, FR-104, FR-105. |
| RP-013 | Removal and ban reasons are stored and shown by visibility policy | A removes or bans C with a reason. | 1. Enter a reason. 2. Inspect timeline, moderator audit view, member view, and C view. | Reasons are persisted, redacted, or shown exactly according to policy. | P2 | Open | Required | Required | N/A | N/A | Recommended | FR-098, FR-099. Reason text is useful but not release-blocking for trusted-private groups unless moderation policy requires it. |
| RP-015 | Orphaned group recovery rules are explicit | All admins disappear, delete devices, or become unreachable. | 1. Simulate no reachable admin/owner. 2. Attempt invite, remove, promote, and close. | If all owners/admins disappear, the app follows the configured trusted-group policy, such as no recovery, creator recovery, or explicit manual recovery, without silently granting control. | P1 | Open | Required | Required | N/A | Recommended | Recommended | FR-100, FR-101. Trusted group members do not imply automatic privilege inheritance. |

## Messaging, Ordering, Editing, Deletion, Reactions, Mentions, and Drafts

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| MS-006 | Quote preview handles missing, deleted, and undecryptable references safely | B replies to a message C has not synced or cannot decrypt. | 1. Deliver reply before parent. 2. Delete or tombstone parent. 3. Trigger key failure for parent. | The reply shows a safe placeholder or later enriches when available without exposing unauthorized content. | P1 | Partial | Required | Required | Recommended | Recommended | Recommended | FR-116, FR-117, FR-308, FR-309. Quoted IDs are covered; preview fallback is broader. |
| MS-009 | Reaction validation covers deleted targets and permission changes | B reacts to existing, deleted, missing, and unauthorized message targets. | 1. React before and after target deletion. 2. Remove send/reaction permission. 3. Replay reactions. | Reactions only apply to valid targets when sender has permission; deleted targets reject or hide reactions by policy. | P1 | Partial | Required | Required | N/A | Recommended | Recommended | FR-125, FR-126, FR-359. Unknown target is covered; deleted target policy is not. |
| MS-010 | Mentions for members, roles, and everyone obey permissions | Group supports mentions. | 1. Send member, role, and everyone mentions as allowed and disallowed users. 2. Inspect notifications and counts. | Member, role, and everyone mentions notify only according to trusted-group policy and never enable unpermitted broad alerts. | P1 | Open | Required | Required | Recommended | Recommended | Recommended | FR-127, FR-128. Trusted groups still need @everyone and role-wide mention controls to prevent accidental disruption. |
| MS-011 | Link previews honor privacy; admin link restrictions are scope-dependent | Link previews are enabled or link restrictions are configured. | 1. Send links with previews enabled, disabled, and restricted. 2. Use suspicious URLs. | Preview generation never leaks browsing metadata or plaintext outside the device/policy boundary; admin link restrictions are tested only if exposed. | P2 | Open | Required | Required | N/A | Recommended | N/A | FR-129, FR-294. Trusted-private scope downgrades public-room link moderation, but privacy of preview generation remains important if enabled. |
| MS-012 | Markdown or rich text rendering is sanitized and consistent | Formatting is enabled. | 1. Send plain text, Markdown, rich text, bidi controls, and malformed markup. 2. Compare render surfaces. | Formatting follows policy, unsafe markup is sanitized, and all surfaces render consistently. | P1 | Open | Required | Required | N/A | N/A | N/A | FR-130. Sanitization remains relevant in trusted groups because malformed formatting can still break rendering or links. |
| MS-013 | Message length and oversized payload limits are enforced consistently | Message and transport size limits are configured. | 1. Send boundary, over-boundary, emoji-heavy, media-only, and combined payloads. 2. Deliver oversized remote payloads. | Oversized content is rejected before expensive work locally and rejected safely on receive without crashing. | P1 | Open | Required | Required | Recommended | Recommended | N/A | FR-131, FR-151, FR-261. |
| MS-014 | Invalid encoding and malformed payloads never crash UI or listener | X sends invalid encoding, malformed JSON, and partial encrypted payloads. | 1. Inject malformed text and payloads through PubSub, sync, and inbox. 2. Observe diagnostics and UI. | Malformed content is rejected or quarantined and never produces broken visible rows or crashes. | P1 | Partial | Required | Required | Recommended | Required | N/A | FR-133, FR-260. Malformed and bidi cases exist, but invalid encoding across all ingress paths is broader. |
| MS-016 | Drafts persist per group and survive restart without leaking | B writes drafts in multiple groups. | 1. Create drafts with text and attachments. 2. Restart app. 3. Leave/remove group and inspect drafts. | Drafts are scoped per group, survive restart where allowed, and are cleared or blocked when membership is lost. | P1 | Open | Required | Required | N/A | N/A | N/A | FR-135, FR-197, FR-220. |
| MS-017 | Pending, queued, failed, local-only, and cancelled statuses are truthful | A sends while offline, with no peers, with inbox failure, and then cancels. | 1. Exercise each send-status path. 2. Retry and cancel pending sends. 3. Inspect UI and DB. | Status labels accurately reflect whether content left the device, reached network, synced, failed, or was cancelled. | P1 | Partial | Required | Required | Recommended | Recommended | Recommended | FR-200, FR-201, FR-215, FR-265. Status/retry coverage exists; cancellation and local-only UI are missing. |

## Announcement-Specific Product Behavior

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| AN-002 | Announcement reply policy allow, restrict, or disable | Group policy configures announcement replies. | 1. Try replies as admin, announcer, member, and restricted member under each policy. | Replies follow policy and the composer accurately enables or disables reply controls. | P1 | Open | Required | Required | Recommended | Recommended | Recommended | FR-139. |
| AN-003 | Announcement pinning and pinned-item sync | A can pin an announcement. | 1. Pin, unpin, and sync pinned announcements. 2. New member joins. | Pinned announcements converge for existing and new members and remain subject to permissions. | P1 | Open | Required | Required | Recommended | Recommended | Recommended | FR-140, FR-067. |
| AN-004 | Announcement priority levels affect display and notifications | Announcements can be normal, important, or urgent. | 1. Send each priority. 2. Inspect badges, ordering, mute behavior, and notification payload. | Priority is preserved through send, sync, storage, and UI and applies only configured notification overrides. | P1 | Open | Required | Required | Recommended | Recommended | Recommended | FR-141, FR-144, FR-226. |
| AN-006 | Urgent announcement override respects privacy and mute policy | B has muted discussion messages or mention-only notifications. | 1. Send normal, important, and urgent announcements. 2. Inspect notification privacy settings. | Only allowed urgent announcements override mute; hidden-content settings still apply. | P1 | Open | Required | Required | Recommended | Recommended | Recommended | FR-144, FR-223, FR-224, FR-227. |

## Media Transfer, Safety, Integrity, and Cache Behavior

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| MD-005 | Chunked transfer resumes from verified chunks | Large media transfer can be interrupted. | 1. Start upload/download. 2. Interrupt after some chunks. 3. Resume from another peer or same peer. | Only verified chunks are reused, progress resumes without duplication, and corrupted chunks are redownloaded. | P0 | Partial | Required | Required | Recommended | Required | Recommended | FR-156, FR-157, FR-158, FR-370. Relay media round-trip exists; chunk/resume behavior is not pinned. |
| MD-006 | Media deduplication by encrypted content hash or content ID | Same media arrives via live, inbox, sync, and resend. | 1. Send duplicate media descriptors. 2. Replay live and offline paths. 3. Inspect local cache. | Only one local media object is stored where hashes match, and references remain correct. | P1 | Partial | Required | Required | N/A | Recommended | N/A | FR-159. Duplicate-message media dedupe exists; content-level dedupe is broader. |
| MD-007 | Encrypted thumbnails and preview privacy | Thumbnail generation is enabled. | 1. Send media with generated thumbnails. 2. Inspect inbox/store/relay payloads and previews before decrypt. | Thumbnails are encrypted or omitted according to policy and do not leak sensitive content to relays or non-members. | P1 | Open | Required | Required | N/A | Recommended | Recommended | FR-160, FR-227. |
| MD-008 | Autoplay policy for video, GIF, and voice | Autoplay settings vary per device or group. | 1. Send GIF, video, and voice. 2. Toggle autoplay settings and open surfaces. | Media playback follows local and group policy without auto-downloading suspicious or oversized content. | P1 | Open | Required | Required | N/A | N/A | Recommended | FR-161, FR-285. |
| MD-009 | Voice waveform and duration metadata are encrypted and accurate | Voice notes include duration or waveform metadata. | 1. Send voice with waveform. 2. Replay and inspect metadata. 3. Tamper duration. | Voice metadata displays accurately after decrypt and tampering fails validation. | P2 | Partial | Required | Recommended | N/A | N/A | Recommended | FR-162. Voice note relay exists; waveform metadata is not directly covered. |
| MD-010 | Media expiration, retention, and cleanup | Group policy expires media after a configured period. | 1. Send media. 2. Advance beyond expiry. 3. Open old messages and sync. | Expired media is cleaned from cache or marked unavailable while message history remains truthful. | P1 | Open | Required | Required | N/A | N/A | N/A | FR-163, FR-250. |

## Encryption, Key Epochs, Identity Verification, and Secret Handling

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|

## Offline Delivery, Sync, Reconnect, and History Repair

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| OS-002 | Retry uses bounded exponential backoff and per-peer/per-group limits | Network and peer failures repeat. | 1. Force repeated publish, sync, relay, and media failures. 2. Inspect retry schedule and cancellation. | Retries back off within configured bounds, stop at limits, and do not hammer failing peers or groups. | P1 | Open | Required | Required | N/A | Required | N/A | FR-199, FR-266, FR-272, FR-273. |
| OS-003 | Direct peer sync protocol supports ranges, heads, and integrity verification | B misses messages and events while offline. | 1. Request sync by sequence, timestamp, hash chain, and known heads. 2. Tamper response. | Only signed, authorized, hash-verified sync responses apply, and missing ranges are requested accurately. | P0 | Open | Required | Required | Recommended | Required | Recommended | FR-202, FR-204, FR-205. |
| OS-004 | Sync pagination and backpressure protect peers | A large history sync is needed. | 1. Request many pages concurrently. 2. Exceed per-peer limits. 3. Resume after throttling. | History pages are bounded, cursor-safe, and backpressure prevents resource exhaustion. | P1 | Partial | Required | Required | N/A | Required | N/A | FR-206, FR-207, FR-280. Inbox pagination exists; peer backpressure is not complete. |
| OS-007 | Anti-entropy sync converges state heads periodically | Peers have divergent event heads after partition. | 1. Diverge membership, metadata, messages, receipts, and keys. 2. Run anti-entropy. | Peers compare known heads and converge or surface conflicts deterministically. | P1 | Open | Required | Required | N/A | Required | Recommended | FR-214, FR-017. |
| OS-011 | Offline media metadata versus content availability is truthful | B receives message metadata before media content is downloaded. | 1. Receive media descriptor while content unavailable. 2. Open conversation. 3. Download later. | UI clearly distinguishes received message metadata from unavailable media content and updates after download. | P1 | Partial | Required | Required | Recommended | Recommended | Recommended | FR-210, FR-264, FR-313. |
| OS-013 | Local-only messages are visibly distinct until they leave the device | A sends while app is offline or no peers and no inbox path exists. | 1. Create local-only messages. 2. Restart. 3. Reconnect and retry or cancel. | Users can tell which messages have not left the device and can retry or delete them safely. | P1 | Partial | Required | Required | Recommended | N/A | Recommended | FR-215, FR-201, FR-265. |

## Notifications, Unread State, Receipts, and Privacy

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| NT-002 | Per-group notification settings include mute, mention-only, and privacy variants | B configures notification preferences. | 1. Toggle mute, mention-only, sender hidden, content hidden, group hidden, and media preview hidden. 2. Receive messages. | Notification eligibility and content match the exact per-group preferences. | P1 | Partial | Required | Required | Recommended | N/A | Recommended | FR-223, FR-224, FR-225, FR-227. Mute exists; full settings matrix is missing. |
| NT-003 | Unread and mention counts converge across sync and mark-read | B receives normal and mentioned messages across live, inbox, and replay. | 1. Receive messages. 2. Mark group read. 3. Sync sibling device. | Unread and mention counts are accurate, deduped, and scoped per group and device policy. | P1 | Partial | Required | Required | Recommended | Recommended | Recommended | FR-228, FR-229, FR-230, FR-220. |
| NT-007 | OS-state group notification matrix closes device-lab gap | Real devices are available in foreground, background, locked, and resumed states. | 1. Trigger group, announcement, media, mention, mute, and urgent notifications in each OS state. | Routing, privacy, drain, and open-target behavior are correct in every OS state. | P1 | Partial | N/A | Required | Recommended | N/A | Required | FR-221 through FR-227. Inventory lists OS-state group notification matrix as residual device-lab coverage. |

## Local Database, Migrations, Event Log, Search, and State Recovery

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| DB-003 | Message, media, peer, and pending-operation indexes are pinned | Large local stores contain many groups, messages, media, peers, and operations. | 1. Query by group, message ID, author, timestamp, thread, sync sequence, media hash, peer, and pending type. | Indexes support required queries and avoid cross-group leakage or unstable ordering. | P1 | Partial | Required | Recommended | N/A | N/A | N/A | FR-240, FR-241, FR-242, FR-243. Basic queries exist, but index coverage is not explicit. |
| DB-005 | Local corruption detection and safe repair | Local DB or state hash is corrupted. | 1. Corrupt message, event, key, and group-state rows. 2. Restart and sync. | Corruption is detected and repaired through resync or safe reset without exposing broken UI state. | P1 | Open | Required | Required | N/A | Recommended | N/A | FR-247, FR-248. |
| DB-007 | Retention, cache eviction, media cleanup, and secure-delete best effort | Retention policy and local cache limits are configured. | 1. Age messages and media. 2. Trigger cleanup. 3. Inspect DB and file cache. | Retention and eviction remove or mark data according to policy, including best-effort secure deletion of plaintext caches. | P1 | Partial | Required | Required | N/A | N/A | N/A | FR-250, FR-328. Backlog retention exists; cache eviction and secure-delete are broader. |
| DB-009 | Local full-text search and search-index privacy | Search is enabled. | 1. Index decrypted messages. 2. Search by content and group. 3. Inspect index storage and post-delete behavior. | Search returns allowed local results only and protects indexes according to device security policy. | P1 | Open | Required | Required | N/A | N/A | N/A | FR-252, FR-253. Inventory explicitly calls out group message full-text search as untested. |
| DB-010 | State snapshots and event replay rebuild group state | A group has a long event history. | 1. Create snapshots. 2. Delete derived state. 3. Rebuild from event log plus snapshots. | Rebuilt state matches canonical group metadata, membership, permissions, and epoch hash. | P1 | Open | Required | Required | N/A | N/A | N/A | FR-254, FR-255, FR-017. |
| DB-011 | Pending-operation store covers joins, key commits, sync, and media retries | Operations are pending during crash or offline state. | 1. Queue sends, invites, joins, commits, sync requests, and media retries. 2. Restart. | All pending operations resume, expire, or cancel according to policy without duplicate side effects. | P1 | Partial | Required | Required | N/A | Recommended | N/A | FR-243. Pending sends and retries exist; joins, commits, and sync requests are broader. |

## Error Handling, Retry Behavior, Recovery Prompts, Audit, and Observability

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ER-003 | Unsupported protocol errors show safe upgrade guidance | A peer cannot negotiate required protocol version. | 1. Attempt group action with unsupported version. 2. Inspect user-facing message. | The user sees a safe upgrade or incompatibility message without internal protocol dumps. | P1 | Open | Required | Required | Recommended | Required | N/A | FR-262, FR-038, FR-270. |
| ER-006 | Offline error classification distinguishes network, peer, relay, permission, and crypto causes | Different failure causes are injected. | 1. Force offline network, no peers, relay unavailable, permission denied, and crypto failure. 2. Inspect UI and retry behavior. | Errors map to distinct safe states and correct recovery actions. | P1 | Open | Required | Required | Recommended | Required | Recommended | FR-274, FR-275. |
| ER-007 | Recovery prompts guide rejoin, key reset, or device verification | A repair requires user action. | 1. Force missing epoch, revoked device, identity change, and corrupt local state. 2. Open conversation. | The UI tells users exactly whether to rejoin, reset keys, verify device, or contact an admin. | P1 | Open | Required | Required | Recommended | N/A | Recommended | FR-275, FR-305, FR-324. |
| ER-008 | Admin audit log records, signs, retains, and gates visibility | Administrative actions occur. | 1. Invite, approve, remove, ban, role-change, delete, rotate, and close. 2. Inspect audit as owner, admin, member, and removed user. | Audit entries are signed or tamper-evident, retained by policy, and visible only to authorized roles. | P1 | Open | Required | Required | N/A | N/A | Recommended | FR-336, FR-337, FR-338, FR-330. Trusted-private groups still need signed admin/moderation logs for membership, role, and key events if those events are user-visible or recoverable. |
| ER-009 | Local diagnostics expose connected peers, sync, protocol, and relay status safely | Diagnostics screen or export is available. | 1. Change peer, sync, protocol, and relay states. 2. Inspect diagnostics. | Diagnostics are accurate enough for support but redact sensitive group membership, addresses, and secrets. | P1 | Open | Required | Required | N/A | Required | N/A | FR-339, FR-344. |
| ER-010 | Privacy-preserving reliability and rejection metrics are bounded and redacted | Telemetry or local metrics are enabled. | 1. Generate sends, rejects, invalid signatures, rate limits, and blocked peers. 2. Inspect metrics payloads. | Metrics record useful counts for invalid signatures, rejected messages, rate-limit hits, blocked peers, and sync failures without identifying private group membership or message content. | P2 | Open | Required | Required | N/A | Required | N/A | FR-340, FR-341. Public abuse telemetry is de-scoped; local reliability/security counters remain useful and privacy-sensitive. |
| ER-011 | Health checks and peer quality tracking influence sync choices | Peers have varied latency, reliability, and usefulness. | 1. Run ping/liveness and sync attempts. 2. Track peer quality. 3. Choose repair source. | Reliable peers are preferred for sync and poor peers are deprioritized without blocking group recovery. | P1 | Open | Required | Required | N/A | Required | N/A | FR-342, FR-343. |
| ER-014 | Group flow-event contract inventory pins names and required detail keys | Flow events are emitted for group send, sync, recovery, retry, and diagnostics. | 1. Run each flow. 2. Validate event family names, detail keys, and redaction. | Observability contracts do not drift and remain privacy-safe. | P1 | Partial | Required | Required | N/A | N/A | N/A | Inventory gap 10.2 plus FR-271 and FR-341. Several flow-event files exist, but the inventory says no dedicated contract inventory. |
| ER-015 | Dispatcher pressure and overflow diagnostics stay separated from message callbacks | Go dispatcher is overloaded. | 1. Generate bounded and overflowing bursts. 2. Observe Flutter callbacks, diagnostics, and UI. | Overflow emits diagnostics only, never fake message callbacks, and UI can show safe degraded state if needed. | P1 | Partial | Required | Required | N/A | Required | N/A | FR-271, FR-341. Go bridge pressure tests exist; user-facing degraded-state coverage remains broader. |

## Abuse Prevention, Moderation, Limits, and Safety

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| AB-001 | Basic burst limits protect trusted groups from accidental storms | Trusted members/devices can send messages, media, and invites. | 1. Burst sends, media uploads, and invite creation from one trusted device. 2. Burst from multiple trusted devices. 3. Inspect UI, retry state, and remote acceptance. | The app throttles or queues bursts without data loss, duplicated notifications, UI lockups, or accidental open admission; limits are user-safe and configurable. | P1 | Open | Required | Required | Recommended | Recommended | N/A | FR-276, FR-277, FR-278. Trusted-private scope downgrades anti-spam gating but keeps accidental-burst protection for reliability. |
| AB-002 | libp2p connection and stream limits protect resource use in private groups | X opens many connections and streams. | 1. Exceed connection and stream limits. 2. Continue normal group traffic from B. | Resource limits prevent runaway dials/streams from stale, buggy, or unauthorized peers while preserving normal trusted-member delivery and sync. | P1 | Partial | Required | Required | Recommended | Required | N/A | FR-279, FR-280, FR-295. DoS-hardening is lower priority than public rooms but still needed for stable private P2P operation. |
| AB-003 | Connection gating and local block effects cover removed or blocked trusted peers | B blocks X or X is denylisted. | 1. Block X. 2. X sends direct invites, group messages, reactions, and sync requests. | Blocked or removed peers cannot keep opening group streams or triggering notifications; local block behavior remains local and does not corrupt group membership. | P1 | Partial | Required | Required | Recommended | Required | Recommended | FR-281, FR-288, FR-289, FR-103. Focus is member-level removal/blocking, not public-room enforcement. |
| AB-005 | Message flood rendering is suppressed or batched | A group receives a high-volume flood. | 1. Deliver many valid and invalid messages quickly. 2. Open conversation. | UI remains responsive, avoids notification storms, and batches rendering where policy says. | P1 | Open | Required | Required | Recommended | Recommended | Recommended | FR-284, FR-236. |
| AB-008 | Attachment and link restrictions are enforced by admins | A configures attachment and link restrictions. | 1. Restrict images, videos, files, and links. 2. Attempt posts from each role. | Restricted content is blocked before publish and remote replays are rejected. | P2 | Open | Required | Required | Recommended | Recommended | Recommended | FR-293, FR-294. Attachment/link posting restrictions are non-gating unless admins can configure them for trusted groups. |
| AB-010 | Trusted invite admission does not rely on Peer ID alone | A peer can present a Peer ID, application identity key, device key, and invite or membership event. | 1. Attempt admission using only a Peer ID. 2. Attempt admission with mismatched app identity, device key, or invite binding. 3. Attempt normal trusted invite admission. | Admission requires current application-level identity/device authorization in addition to Peer ID; normal trusted invites still succeed. | P1 | Open | Required | Required | Recommended | Recommended | Recommended | FR-171, FR-316, FR-317, FR-331. This is a private-group identity-binding guard. |

## UI System State, User-Facing Truth, and Accessibility

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| UI-001 | Group-created and metadata-changed system messages are consistent | A creates and updates group info. | 1. Create group. 2. Change name, avatar, description, and settings. 3. Open conversation, feed, and member list. | System messages and metadata surfaces agree and avoid duplicate or stale entries. | P1 | Partial | Required | Required | Recommended | N/A | Recommended | FR-296, FR-302. Metadata timeline exists; group-created system-message coverage is unclear. |
| UI-002 | Leave, remove, ban, unban, and role-change visibility follows policy | Membership and role events occur. | 1. Trigger leave, remove, ban, unban, promote, and demote. 2. Compare member, removed user, and moderator views. | Each viewer sees the correct system messages, badges, and audit links according to policy. | P1 | Partial | Required | Required | Recommended | N/A | Recommended | FR-298, FR-299, FR-300, FR-301. Leave/remove/role coverage exists; ban/unban is missing. |
| UI-004 | Offline banner and syncing indicator reflect real connection and sync state | App transitions through offline, relay-only, syncing, and caught-up states. | 1. Toggle network and sync progress. 2. Open group list and conversation. | Banners and indicators match actual connectivity and sync progress without masking send failures. | P1 | Open | Required | Required | Recommended | Required | Recommended | FR-306, FR-307, FR-034. |
| UI-006 | Pending invites and trusted moderation controls are complete; join-request UI is hidden | Trusted private groups support direct invites and member/admin actions; public join requests are out of scope. | 1. Display incoming and outgoing direct invites. 2. Display remove, ban if supported, role, and restriction controls by role. 3. Search for public join-request surfaces. | Invite and moderation controls appear only to authorized roles; public join-request UI is hidden or safely unsupported. | P1 | Partial | Required | Required | Recommended | N/A | Recommended | FR-310, FR-311, FR-312. Join request controls are non-gating except as hidden-route guards. |
| UI-007 | Media upload/download progress and retry controls are truthful | Media upload or download fails mid-transfer. | 1. Upload and download media. 2. Interrupt. 3. Retry, cancel, and resume. | Progress, retry, cancel, and unavailable states match actual transfer state. | P1 | Partial | Required | Required | Recommended | Recommended | Recommended | FR-313, FR-314, FR-264, FR-370. Some retry coverage exists; full progress UI is not complete. |
| UI-008 | Accessibility for system messages, errors, and actions | Assistive technologies are enabled. | 1. Navigate member list, conversation, system messages, context actions, error banners, and media controls. | Labels, roles, focus order, and announcements are usable and accurate for assistive technologies. | P1 | Open | Required | Required | Recommended | N/A | N/A | FR-315. |
| UI-009 | Sensitive action confirmation prevents accidental destructive changes | A can remove, ban, delete, close, rotate links, or rotate keys. | 1. Trigger each destructive action. 2. Cancel and confirm. | Destructive actions require confirmation and cancellation leaves state unchanged. | P1 | Open | Required | Required | Recommended | N/A | Recommended | FR-333, FR-014, FR-091, FR-181. |
| UI-010 | Private profile fields are not over-shared in group surfaces | Members have public and private profile fields. | 1. Create group with privacy settings. 2. Inspect member list, invite preview, notifications, and diagnostics. | Only permitted profile fields are shared with group members and external infrastructure. | P1 | Open | Required | Required | N/A | N/A | Recommended | FR-327, FR-319, FR-320. |

## Security, Privacy, Metadata Controls, Backup, and Secret Controls

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SP-005 | Secure delete best effort and plaintext memory lifetime | Plaintext messages and media are decrypted locally. | 1. View content. 2. Close, delete, evict, or logout. 3. Inspect caches where feasible. | Plaintext caches are cleared by policy and decrypted content lifetime is minimized. | P1 | Open | Required | Recommended | N/A | N/A | N/A | FR-328, FR-329. |
| SP-008 | Private discovery and mailbox flows do not leak contact graph | Trusted private groups use private peer discovery, bootstrap, rendezvous, relay, or mailbox mechanisms. | 1. Create overlapping private groups. 2. Inspect discovery records, mailbox pickup, relay metadata, diagnostics, and logs. 3. Query as non-member X. | Non-members and infrastructure cannot derive shared group membership or contact graph beyond unavoidable routing metadata. | P1 | Open | Required | Required | Recommended | Required | N/A | FR-320, FR-318, FR-321. Public discovery is de-scoped, but private discovery still has contact-graph leakage risk. |

## APIs, Integration Contracts, Configuration, and Test Hooks

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| API-002 | Event subscription API normalizes state changes without duplicates | UI subscribes to group state changes. | 1. Deliver PubSub, direct sync, store-and-forward, and local events. 2. Observe UI streams. | The UI receives one normalized event per logical change with no duplicate rendering. | P1 | Partial | Required | Required | Recommended | Recommended | N/A | FR-367, FR-369. Listener streams exist; full normalized receive-pipeline API is broader. |
| API-003 | Send API returns local message ID immediately for optimistic UI | A sends through success and failure branches. | 1. Call send while online, offline, no peers, oversized, and unauthorized. 2. Inspect return and stored row. | Valid sends return a local ID immediately; invalid sends do not create misleading optimistic rows. | P1 | Partial | Required | Required | Recommended | N/A | N/A | FR-368, FR-201. ID generation and pre-persist are covered; API-level contract should be pinned. |
| API-004 | Media API covers upload, download, cancel, resume, decrypt, preview, and delete | Media API is exposed. | 1. Exercise each media API operation with success, failure, cancel, and resume. | Media API maintains progress, integrity, and access-control invariants across operations. | P1 | Partial | Required | Required | Recommended | Recommended | N/A | FR-370. Upload/download coverage exists; cancel/resume/delete/decrypt/preview matrix is incomplete. |
| API-005 | Invite API covers create, revoke, accept, reject, and list | Invite API is exposed. | 1. Create, list, revoke, accept, reject, expire, and replay invites. | Invite APIs enforce authorization, identity binding, expiry, revocation, and replay policy. | P1 | Partial | Required | Required | Recommended | Recommended | N/A | FR-371. Create/accept/decline are covered; revoke and list are missing. |
| API-006 | Permission, key-state, and notification APIs are queryable | UI needs enablement and status data. | 1. Query current permissions, epoch state, verification state, and notification eligibility. | APIs return current safe state for UI enablement without leaking secrets or stale permissions. | P1 | Open | Required | Required | Recommended | N/A | N/A | FR-372, FR-373, FR-375. |
| API-008 | Search and migration APIs are explicit | Search and migration APIs are exposed. | 1. Query search where enabled. 2. Run migration routines across old group versions. | Search and migration APIs enforce policy and are safe to call repeatedly. | P2 | Open | Required | Required | N/A | N/A | N/A | FR-377, FR-378. |
| API-009 | Test hooks simulate offline, churn, conflicts, invalid signatures, and key rotation | Automated tests need deterministic fixtures. | 1. Use hooks to simulate offline, peer churn, partitions, invalid signatures, clock skew, and key rotations. | Hooks make hard states deterministic without weakening production security or leaking test-only behavior into release. | P1 | Partial | Required | Required | N/A | Required | N/A | FR-379. Fakes exist, but requirement-level hooks for all listed conditions are incomplete. |

## Edge Cases, Invalid Actions, and Fork Handling

| Test ID | Scenario | Preconditions | Steps | Expected Result | Priority | Current status | Unit | Integration | Smoke | Fake Network | 3-Party E2E | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| EC-002 | Add existing, remove nonexistent, and delete nonexistent behavior is idempotent or rejected by policy | A applies duplicate or nonexistent operations. | 1. Add existing member. 2. Remove nonexistent member. 3. Delete nonexistent message. 4. Replay remotely. | Outcomes follow explicit API policy and never corrupt membership, timeline, or message state. | P1 | Partial | Required | Required | N/A | Recommended | N/A | FR-355, FR-356, FR-357. Add duplicate is covered; remove/delete policies need broader coverage. |

## Recommended trusted-private smoke suite for gap closure

The smallest new smoke suite should prove these rows first:

| Smoke ID | Rows | Purpose |
|---|---|---|
| `TP-SMOKE-02` | `RP-011` | Removed, left, banned, or revoked devices cannot keep receiving, publishing, dialing, or resurrecting group state. |
| `TP-SMOKE-04` | `OS-003` | Offline sends, sync gaps, partitions, stale queued sends, and missed key epochs recover or surface truthful placeholders. |
| `TP-SMOKE-05` | `MD-005` | Media in trusted groups still enforces type, size, encryption, hash integrity, resume integrity, removed-member access, and quarantine rules. |
| `TP-SMOKE-06` | `UI-004`, `UI-009` | Notifications and UI states stay private, deduplicated, accessible, and truthful for encryption, offline, undecryptable, deleted, and destructive-action cases. |
| `TP-SMOKE-07` | `SP-008` | Private discovery, relay/bootstrap fallback, protocol negotiation, duplicate PubSub handling, and metadata minimization work without public-room leakage. |

## Suggested implementation order for trusted-private gap closure

1. Close private admission and authorization gates first: none remaining in this split.
2. Close removal, device revocation, key rotation, and tombstone rows next: `RP-011`.
3. Close offline, sync, and state-convergence rows: `OS-003`.
4. Close media and message correctness rows: `MS-013`, `MS-014`, `MD-005`.
5. Close UI, notification, diagnostics, and database integrity rows: `UI-004`, `UI-009`, `ER-006`, `ER-009`.
6. Keep trusted-private negative guard rows only where they protect invite-only admission, authorization, or private discovery from accidental public/open behavior.

## Removed Non-Fitting Rows

Rows for de-scoped product capabilities were removed from the active matrix instead of kept as implementation backlog: delegated moderation tokens, message threads, message edit/delete, scheduled send, mixed-mode announcement discussions, announcement acknowledgements, announcement edit/delete audit, generic file attachments, read/delivery receipts, history/debug export, screenshot/export policy, secret export, backup product flows, public reporting, public-room anti-spam, full transport matrices, MLS-like commits, forward-secrecy/post-compromise-recovery claims, safety-number UX, remote/runtime configuration APIs, broad peer-scoring/abuse scoring, public API umbrella rows, and broad device-lab media matrices.

## Notes for implementation

- Prefer extending existing suites where the inventory already has adjacent coverage, especially `group_message_listener_test.dart`, `send_group_message_use_case_test.dart`, `handle_incoming_group_message_use_case_test.dart`, `accept_pending_group_invite_use_case_test.dart`, `group_key_update_listener_test.dart`, `group_resume_recovery_test.dart`, Go PubSub validator suites, and bridge tests.
- Treat direct invites as the trusted-private default. Tests should prove invites are signed, identity-bound, device-aware, revocable, expiring, and non-replayable.
- Treat all non-members, removed devices, relays, mailbox peers, bootstrap peers, stale peers, and diagnostics paths as untrusted for plaintext and group secrets.
- Use fake-network tests for deterministic partitions, duplicate deliveries, stale peers, relay-only behavior, and protocol-incompatible peers before adding slower real-device E2E.
- Reserve real-device or device-lab gates for relay privacy, removed-member isolation, offline recovery, and notification privacy; avoid adding broad device-lab proof as a default row requirement.
- Treat any test that inspects payloads, diagnostics, or push payloads as a privacy test: assert that secrets, plaintext, private group names, full member lists, and sensitive peer addresses are absent, not just that the operation succeeds.
- For trusted-private guard rows, write tests only if the API, config, network handler, or UI surface exists. Otherwise, avoid adding product-scope reminders as failing release gates.
