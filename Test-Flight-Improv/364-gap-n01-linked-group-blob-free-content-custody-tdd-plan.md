# 364 - GAP-N01 Linked-Group Blob-Free Content Custody

Status: EXECUTION_READY / host-development-unblocked / live-acceptance-blocked / independently reviewed / default-off / not release-eligible
Type: Modification
Planning baseline: `082f5e96f96b4be0362b474884059e0cdeff6399` (clean Plan-363 deferred-authority/survivor-recovery post-execution audit closure; Graphify `681115963b6c3b2a`, 72,965 nodes / 106,907 edges; DB v114; canonical `GROUP_TESTS` 244/244 unique paths)
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` A-18 and OQ-04; GAP-N01 / WP-01 in `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`; successor to Plan 363's linked-group bootstrap and authority foundation
Classification: schema-free expected, blob-free discussion / admin announcement / reaction ADD+REMOVE adopter over Plan-363 authority and protected custody; no group blobs, generic group history, activation, release, or GAP-N01 closure claim
Closure tier: five causal host IDs across four focused concurrent Flutter bundles, four representative mutations, two exact Go protected-kind tests, mandatory DTR/runtime-root contracts, the curated `groups` lane once, and one availability-bounded extension of the existing Android B1b scenario

## Planning Progress

| Time | Role | Evidence inspected | Decision / blocker | Disposition |
|---|---|---|---|---|
| 2026-08-13 | Evidence collector / planner | Graphify TDD context; Plan 363 contract; current group message/reaction sender, retry, replay, notification, runtime and UI owners | Plan 363 is being implemented in the shared worktree, so its final authority serializer, protected handler, graph and gate counts are moving. | Finish the successor contract now, but author no Plan-364 RED until Plan 363 has a clean post-execution audit SHA and the exact shared APIs are revalidated. |
| 2026-08-13 | Custody review | Aggregate group inbox, `AckOrExpiryInboxStore`, signed group replay envelope, message retry payload, reaction replay outbox, node/relay protected parser | Aggregate group storage cannot prove per-physical-recipient ACK or prevent one device from retiring another. Plan 363 adds the correct protected action/backend but only for bootstrap/authority. | Add one `group_content_v1` kind/parser to the incumbent protected lane. Reuse existing message/reaction durable owners; add no action, backend, bridge command, queue or ACK ledger. |
| 2026-08-13 | Sender / retry review | Message recipient resolution, linked transport credential, message reliable command, reaction ADD/REMOVE, failed message and inbox-store retriers | Messages still target logical member IDs; reactions target physical devices but publish before strict custody; current retries may rebuild with account keys/current roster. | Resolve logical actor and physical signer separately, freeze the physical ACL and exact bytes once, persist before egress, converge strict per-recipient custody with zero marked-content pubsub, and retry only stored bytes/survivors. |
| 2026-08-13 | Receive / ordering review | Group replay verification, incoming message/reaction handlers, event log, reaction LWW, P2P staging/ACK, authority races and notification custody | Current timestamps/current roster do not deterministically order delayed content around role/removal/dissolve/key authority, and generic replay outcomes cannot safely decide relay ACK. | Bind content to an authenticated Plan-363 authority version, use a typed apply outcome, retain prerequisites without attempt burn, exact-read back canonical state, and ACK only durable success/duplicate/terminal rejection. |
| 2026-08-13 | Runtime / UI review | Plan-363 restricted runtime/list, full `GroupConversationWired`, pure `GroupConversationScreen`, cold/resume/pause owners | Starting group topics or reusing the full wired controller would expose history/media/settings and account-key fail-open paths. | Add one narrow linked conversation owner over the pure screen, one protected content recovery phase, and no topic/cursor/history/broad runtime owner. |
| 2026-08-13 | Test / gate economy review | Existing group test paths, `GROUP_TESTS`, Go tails, DTR/runtime contracts and B1b runner | Existing files cover every boundary. No migration/SQLCipher/new host path/full-host campaign is justified if the accepted Plan-363 event log can own exact content ordering. | Use four concurrency-4 bundles, four mutations, exact Go tests, one curated groups gate and one upgraded B1b run. Recount after Plan 363; do not duplicate family/device campaigns. |
| 2026-08-13 | Plan-363 closure revalidation | Post-execution audit closure `bb2184fe07121a12d6515d95c32b019e1e8e1151`; current anchored Graphify `d7be06567d488766`; `AuthenticatedGroupAuthorityProof`, exact/bounded authenticated history loaders, `runGroupAuthorityPhase`, protected kind/parser owners, active `LinkedTransportCredential`, restricted runtime callbacks, DB v114 and the canonical `GROUP_TESTS` array | Plan 363 now retains independently signed genesis/prepared/complete authority after relay ACK, resolves exact `(eventAt,eventId,keyEpoch)` versions, shares one non-reentrant per-group phase with protected key repair, and preserves the reviewed schema-free/event-log boundary. Inventory is 244/244 unique paths. The deployed relay still lacks the additive Plan-363 protected-kind allowlists. | Hard host-development stop condition satisfied. Mark `EXECUTION_READY`; pin this SHA/graph/API/count baseline. Relay deployment and a passing Plan-363 B1b remain mandatory before Plan-364 device acceptance, activation or release, but do not block host RED/GREEN development. |
| 2026-08-13 | Sender-history prerequisite audit | Ordinary-primary bootstrap authoring, local protected-authority preparation/activation, paired custody retirement and repository restart | Audit found that the primary signed bootstrap genesis without persisting it and that locally authored authority retained no durable prepared/complete proof after outbox retirement. The earlier `bb2184fe…` pin therefore did not satisfy strict content authoring despite its receiving-side history repair. | Re-block Plan 364. Require atomic sender genesis, atomic local prepared history, projection-proven complete repair before egress/retirement, restart survival, a committed Plan-363 closure and a fresh graph/inventory pin. Production admission remains a separate default-off live gate. |
| 2026-08-13 | Sender-history prerequisite reclosure | Plan-363 closure `7380c7c045596fe17d24589930d92088851ea129`; anchored/current Graphify `fa124fa2c3be08f5`; sender genesis/prepared/complete production paths; focused c4 `+5`; analyzer; canonical inventory | The primary now commits authenticated genesis with bootstrap authoring. Local authority commits prepared with exact protected rows, proves or repairs complete from authenticated history plus durable projection under the shared group phase, and permits no protected egress/retirement beforehand. Genesis/prepared/complete survive owner retirement and repository reconstruction. Inventory remains 244/244; DB remains v114. | Host prerequisite is now satisfied. Restore `EXECUTION_READY / HOST-DEVELOPMENT-UNBLOCKED / LIVE-ACCEPTANCE-BLOCKED` and pin this exact closure. The protected-kind binary is deployed, but admission remains off and was not changed. |
| 2026-08-13 | Common-version and dissolve prerequisite audit | Key rotation sender/A/B histories, zero-target rotation, protected dissolve activation/terminal ordering, custody-complete crash recovery | The `7380c7c…` sender-history closure was durable but still minted a distinct signed key-authority event per recipient and no authority for a protected zero-target rotation. Protected dissolve required an already-dissolved projection during activation even though its terminal commit followed activation, so strict custody could never reach that commit. Plan 364 requires one exact authority version every participant can resolve and a restart-safe terminal authority phase. | Re-block host development. Require one recipient-independent signed key authority retained even with zero deliveries, target qualification only in outer envelopes, and PREPARED -> strict custody -> atomic dissolve projection plus COMPLETE with restart recovery. Keep production admission off. |
| 2026-08-13 | Final Plan-363 prerequisite reclosure | Clean closure `153990d78b94028049bb0290c70f5194c6f7204d`; anchored/current Graphify `06a4d00c3599f606` (72,949 / 106,902); common key proof and zero-target history; atomic key+COMPLETE and dissolve terminal+COMPLETE transactions; focused c4 `+6`; affected preservation `+172`; analyzer; 244/244 inventory | Sender/A/B now retain one exact signed key authority version across repository reconstruction; a zero-target protected rotation retains PREPARED and COMPLETE. Dissolve retains PREPARED plus immutable rows through strict custody and atomically advances terminal projection, COMPLETE history and exact-row retirement; duplicate custody repairs a pre-terminal crash after restart. The stale multiline bootstrap contract is corrected. DB remains v114 and no Plan-364 source was authored. | Host prerequisite is satisfied again. Pin this exact SHA/graph/API/count baseline and restore `EXECUTION_READY / HOST-DEVELOPMENT-UNBLOCKED / LIVE-ACCEPTANCE-BLOCKED`. The relay binary remains deployed, production admission remains off, and B1b/device acceptance/activation/release remain separately blocked. |
| 2026-08-13 | Deferred/restart prerequisite audit | Deferred current-key A/B retry; protected dissolve survivor persistence; rowless zero-target PREPARED recovery; content retrieval wire contract | The `153990d…` closure fixed fresh rotation and terminal dissolve, but deferred distribution still minted target-qualified authority IDs with a fresh retry time, dissolve did not durably retire each accepted target before final commit, and the runner could discover only broadcast-owned work. Alternating availability could therefore livelock and rowless zero-target work could strand. Separately, retrieval does not preserve the outer request custody kind, so a content replay without a signed inner discriminator would be ambiguous. | Re-block host development. Require one stable common deferred proof with target-qualified delivery only, exact survivor-row retirement, bounded authenticated PREPARED-only discovery/recovery, and a signed self-contained inner `group_content_v1` discriminator in Plan 364. Keep production admission off. |
| 2026-08-13 | Deferred/restart prerequisite reclosure | Clean Plan-363 closure `082f5e96f96b4be0362b474884059e0cdeff6399`; anchored/current Graphify `681115963b6c3b2a` (72,965 / 106,907); focused c4 `+10`; affected preservation `+222`; analyzer/format/diff hygiene; 244/244 inventory | Deferred A/B now share one persisted-key-time authority proof across adapter reconstruction while only outer deliveries vary. Each accepted dissolve target is durably retired so restart contacts survivors only; bounded newest-first authenticated PREPARED discovery repairs rowless zero-target key/dissolve work and refuses ambiguous nonempty key ACLs. DB remains v114, no Plan-364 production code was authored, and this plan now requires the signed inner content discriminator. | Host prerequisite is satisfied. Pin this exact SHA/graph/API/count baseline and restore `EXECUTION_READY / HOST-DEVELOPMENT-UNBLOCKED / LIVE-ACCEPTANCE-BLOCKED`. The relay binary remains deployed, admission remains off, and B1b/device acceptance/activation/release remain separately blocked. |

## Execution Progress

| Time | Step | Evidence | Result / next action |
|---|---|---|---|
| 2026-08-13 | Planning | Anchored Graphify planning context plus targeted source verification while Plan 363 is active | Contract drafted in prerequisite-blocked state. Pin the final Plan-363 audit SHA/graph and revalidate the stop conditions before any RED. |
| 2026-08-13 | Independent TDD review | Formal review query; sender/retry, receive/runtime/UI, gate/non-vacuity and overengineering counterexamples | READY after bounded amendments. Recipient-survivor liveness, authority-order reconciliation, retry/transaction atomicity, selector/runtime reachability and proof non-vacuity are closed without expanding the one-kind/existing-owner/four-bundle boundary. |
| 2026-08-13 | Prerequisite closure | Clean Plan-363 audit commit `bb2184fe07121a12d6515d95c32b019e1e8e1151`; current anchored TDD query at `d7be06567d488766`; exact API/kind/runtime/DB/inventory verification | `EXECUTION_READY / HOST-DEVELOPMENT-UNBLOCKED / LIVE-ACCEPTANCE-BLOCKED`. First implementation action is the literal clean-tree/ancestry preflight, then all five Flutter IDs and both exact Go REDs. Do not run B1b until the Plan-363 node/relay allowlists are deployed and its bootstrap journey passes. |
| 2026-08-13 | Plan-363 relay deployment follow-up | Exact linux/amd64 binary SHA-256 `1b2b6a3e1b2a44262754e5423a0ea73b3a19d3b7b8a593d31e07d4ec88ad7812`; Redis-backed systemd service; rollback artifact; live Android pair | The protected-kind binary is deployed and stable, but startup proves ACK-custody admission remains unset/default-off. `StoreAckCustody` rejects at that guard before the kind parser, so B1b was not relaunched into a deterministic failure. Plan 364 remains host-execution-ready; separate S2 admission authorization plus a passing Plan-363 B1b gate device acceptance, activation and release only. |
| 2026-08-13 | Sender-history prerequisite closure | Clean Plan-363 repair/audit commit `7380c7c045596fe17d24589930d92088851ea129`; current anchored TDD review `fa124fa2c3be08f5`; exact sender/history/API/DB/inventory verification | `EXECUTION_READY / HOST-DEVELOPMENT-UNBLOCKED / LIVE-ACCEPTANCE-BLOCKED`. The literal preflight and hygiene baseline now use this closure and allow the five intentional Plan-363/364/index/status/coverage documentation owners. No Plan-364 RED or production code has started. |
| 2026-08-13 | Authority-version/dissolve prerequisite re-block | Exact rotation proof identities, zero-target authority production and protected-dissolve activation ordering at `7380c7c045596fe17d24589930d92088851ea129` | The sender-history commit remains valid but does not satisfy Plan 364's one-version or terminal-phase assumptions. Stop before RED; repair and post-execution-audit Plan 363 first. Production admission remains default-off and orthogonal. |
| 2026-08-13 | Final Plan-363 prerequisite closure | Clean Plan-363 repair/audit commit `153990d78b94028049bb0290c70f5194c6f7204d`; current anchored review `06a4d00c3599f606`; exact common-authority, atomic dissolve, restart, API, DB and inventory verification | `EXECUTION_READY / HOST-DEVELOPMENT-UNBLOCKED / LIVE-ACCEPTANCE-BLOCKED`. The literal preflight and hygiene baseline use this closure and allow only the five intentional Plan-363/364/index/status/coverage documentation owners. Focused c4 `+6`, affected preservation `+172`, targeted analyzer and 244/244 inventory are green; no Plan-364 RED or production code has started. |
| 2026-08-13 | Deferred/restart prerequisite re-block | Exact deferred proof identity/time, two-target receipt progress, rowless PREPARED discovery and retrieval-kind preservation at `153990d78b94028049bb0290c70f5194c6f7204d` | The prior closure remains valid for fresh authority but not for retry/restart liveness or a self-describing content wire. Stop before RED; repair and post-execution-audit Plan 363, then amend the Plan-364 content contract. Production admission remains default-off and orthogonal. |
| 2026-08-13 | Deferred/restart Plan-363 prerequisite closure | Clean Plan-363 repair/audit commit `082f5e96f96b4be0362b474884059e0cdeff6399`; current anchored review `681115963b6c3b2a`; exact deferred common proof, survivor-only dissolve restart, rowless zero-target recovery, API/DB/inventory verification | `EXECUTION_READY / HOST-DEVELOPMENT-UNBLOCKED / LIVE-ACCEPTANCE-BLOCKED`. The literal preflight and hygiene baseline use this closure and allow only the five intentional Plan-363/364/index/status/coverage documentation owners. Focused c4 `+10`, affected preservation `+222`, targeted analyzer, format/diff hygiene and 244/244 inventory are green; no Plan-364 RED or production code has started. |

## Problem And Source-Backed Evidence

- Plan 363 intentionally stops at group bootstrap, signed membership/config/key authority, protected physical-recipient control custody and a read-only linked list. It starts no content ingress or writable conversation.
- `send_group_message_use_case.dart` currently derives logical member peer IDs and excludes the logical sender. A linked author therefore omits its same-account primary sibling and cannot prove physical device obligations.
- `send_group_reaction_use_case.dart` already expands active physical devices, but ADD/REMOVE still stage asynchronously and can publish before durable custody. REMOVE also tolerates a missing bound device in incumbent paths.
- `GroupConversationWired`, Feed, share and failed-message retry currently supply the logical account key while a linked node runs on a distinct transport credential. Go verifies the exact device/transport/public/private signing tuple, so substituting account credentials is not a benign fallback.
- `group:sendReliable` and incumbent Dart fallback start group-inbox store and pubsub concurrently. A topic peer or generic `OK` is not protected custody and cannot retire a physical-recipient obligation.
- `group_messages.inbox_retry_payload` and `group_reaction_replay_outbox.inbox_retry_payload` already persist exact replay bytes and retry authority. They are sufficient if strict linked rows carry an explicit custody contract/kind and are never rebuilt from current roster or crypto.
- Plan 363's protected lane provides recipient-scoped `stored|duplicate`, retrieve, staging and `ack_or_expiry_v1`. It has no content kind by design; `group_authority_v1` must continue rejecting user content.
- Current protected staging may ACK every staged ID after a void replay callback. Group content needs a typed terminal/prerequisite result, fixed-point prerequisite replay and durable canonical/terminal evidence outside the staging row.
- Current message duplicate checks are weaker than the immutable signed content identity. Current reaction state compares timestamp only, so equal-time ADD/REMOVE can converge by arrival order and exact replay can emit a second UI transition.
- `group_event_log` already has exact `(group_id, source_event_id)` replay/conflict authority and a `(group_id,event_type,source_timestamp)` lookup index. Its `sequence` is local insertion order and must not be treated as a global causal order.
- Full `GroupConversationWired` loads account credentials and exposes media/private/share/settings/history callbacks. Plan 364 needs a smaller authority-gated wired owner while reusing the pure conversation screen rendering.
- Plan 363 defers voluntary self-removal because its terminal cleanup has a distinct owner. Plan 364's intentionally narrow linked conversation exposes no leave control, so this separate control-plane workflow remains explicitly deferred rather than being smuggled through the content kind.

Expected production surface, revalidated against the pinned Plan-363 closure:

- `AckCustodyKind`, `P2PServiceImpl`, `P2PInboxCoordinator`, `go-mknoon/node/inbox.go`, and `go-relay-server/ack_custody.go`, with one additive `group_content_v1` kind/parser only
- `go-mknoon/bridge/bridge.go`, its incumbent ACK-custody dispatch test, and relay Redis stored-row reparse; the bridge command and relay request actions remain unchanged
- `group_offline_replay_envelope.dart` and its retry wrapper, extended with a strict custody discriminator: the immutable full ACL lives in the signed envelope, while one mutable pending subset starts equal to that ACL and may shrink only through exact accepted-receipt CAS
- `send_group_message_use_case.dart`, ADD/REMOVE reaction use cases, `retry_failed_group_messages_use_case.dart` and `retry_failed_group_inbox_stores_use_case.dart`
- the existing `group_messages` and `group_reaction_replay_outbox` repositories/helpers plus `group_event_log` exact replay/conflict history; expected DB floor remains the accepted Plan-363 floor
- incoming message/reaction canonical handlers, group listener notification custody and a narrow typed protected-content adapter under Plan 363's authority serializer
- the Plan-363 restricted cold/resume/pause owner and linked group list, plus a narrow linked conversation wired boundary over `GroupConversationScreen`
- the accepted Plan-363 B1b runner; incumbent voluntary-leave/exit-intent behavior remains outside this linked content surface

Stop and re-review before adding a second group selector, v115, a parallel content outbox, per-target ACK rows, a new scheduler, a new relay request action/backend/field, a bridge command, generic group topic/cursor/history startup, or full `GroupConversationWired` on the linked route. One additive signed inner content-authority field/extension is expected because receivers must bind the observed Plan-363 authority version; it is not a new relay request shape. The former hard stop is satisfied by `AuthenticatedGroupAuthorityProof`, `loadAuthenticatedAuthorityVersion`, `loadAuthenticatedGroupAuthorityProofPage`, `dbLoadGroupEventLogEntryExact`, `dbLoadGroupEventLogTypePage` and `runGroupAuthorityPhase`. If implementation cannot transactionally compare reaction state through those bounded event-log seams, stop and revise the schema boundary rather than claiming schema-free closure.

## Graph Grounding Snapshot

- Graph: `graphify-arch`, selected implicitly under repository policy.
- Planning context: anchored/current against committed fingerprint `4bf3025ee64828d0` before active Plan-363 implementation; this is historical planning context, not the Plan-364 execution baseline.
- Planning query: `python3 graphify-arch/tdd_context.py query "Plan 364 linked-group blob-free discussion announcement reaction authoring after Plan 363 authority convergence; exact protected physical-recipient custody, sender transport credential, event-vs-role/remove/dissolve/key ordering, retry, linked runtime and UI" --profile tdd --budget 700`.
- Final review query is recorded after the draft under Reviewer Findings. No graph refresh is performed while Plan 363 owns the dirty shared tree.
- Execution baseline: Plan-363 deferred-authority/survivor-recovery audit closure `082f5e96f96b4be0362b474884059e0cdeff6399`; current Graphify fingerprint `681115963b6c3b2a`, 72,965 nodes / 106,907 edges. The final anchored review returned `confidence=anchored` and `freshness=current` with anchors at `distributeCurrentGroupKeyToDeferredPeer`, `recoverPreparedProtectedGroupDissolve`, `GroupPendingBroadcastRunner` and `recoverLocalPreparedKeyAuthority`.
- Pinned shared boundary: DB v114; `AckCustodyKind.groupBootstrapV1` / `group_bootstrap_v1`, `AckCustodyKind.groupAuthorityV1` / `group_authority_v1`, inner `linked_group_bootstrap_v1`; `AuthenticatedGroupAuthorityProof`, `loadAuthenticatedAuthorityVersion`, `loadAuthenticatedGroupAuthorityProofPage`, exact/bounded DB loaders and `runGroupAuthorityPhase`; `LinkedTransportCredential` active-state authority; restricted `isLinkedBlobFreeRuntime`, `drainLinkedGroupBootstrap` and `drainLinkedDirectMediaBlobCustody` callbacks; canonical `GROUP_TESTS` 244/244 unique paths.

## Scope Contract

### Prerequisite, selector and rollout authority

- Plan 363 is code-complete, post-execution audited and committed at `082f5e96f96b4be0362b474884059e0cdeff6399`; this exact baseline includes sender-side genesis, stable common fresh and deferred key authority including zero-target rotations, locally authored prepared/complete survival, durable dissolve survivor progress, bounded prepared-only restart recovery and the shared non-reentrant phase, and it authorizes Plan-364 host RED/GREEN development. Its protected-kind relay binary is deployed, while production ACK-custody admission remains default-off and still blocks B1b/device acceptance, activation and release.
- Add no new selector. New strict content requires exactly `DirectLinkedDeviceSelector.allowsLinkedDeviceAuthoring && kMultiDeviceSyncEnabled`; `DirectLinkedEventFanoutSelector` is direct-contact-only and may not authorize group content. A Plan-363-initialized explicit self-device roster selects strict custody for both an ordinary primary and an active linked secondary. Check persisted device authority before fallback: initialized authority with either selector disabled, a missing strict signer or missing strict store refuses; only an uninitialized ordinary-primary group retains incumbent behavior byte-for-byte.
- Existing strict content rows drain after selector rollback. A disabled/missing selector may block new authoring but may not rebuild, demote to aggregate group storage, publish without custody, or delete committed retry authority.
- Reader/parser/relay support deploys before authoring activation. Mixed-version negotiation, cohorts, telemetry, kill switches, legacy retirement and release are later WP-07 work.

### Eligible content and exclusions

- Eligible message content is one non-empty sanitized text body with no media descriptor, attachment, voice, GIF, file, private/view-once/disappearing policy, forward provenance, system payload or quoted content. Discussion groups permit every active member; announcement groups permit only an active admin proven at the content's observed authority version.
- Eligible reactions are ADD and REMOVE by an active member against an existing ordinary same-group message. Private/media/system targets, missing targets at authoring, null/unbound sender devices and crossed group targets refuse before local projection, crypto or network.
- Reject any content whose text starts with the reserved `{"__sys":` prefix. It receives durable terminal-reject evidence and exact relay ACK, but no membership/config/key, timeline, unread or notification mutation.
- Group media, voice, private shapes, captions, forwarding, quoted replies, avatar/config edits, group creation/invite/discovery/history/no-intent, feed/posts/contact content runtime and generic pending-system broadcasts remain outside Plan 364. Plan 365 owns group blob/media/voice.

### Logical actor, physical signer and frozen targets

- Resolve one author authority under the accepted successor to `runGroupMembershipMutationLocked`: logical account peer; actual current transport peer; exact device ID; transport signing public/private key; current group/member role; current key epoch; and current authenticated authority version. A linked author uses `LinkedTransportCredential`; an ordinary primary uses the accepted legacy-primary mapping. Account and transport values may not be substituted. Both reaction directions, strict retries and protected key application must enter the same keyed serialization domain; a repository-local mutex or key-listener stream tail is not equivalent.
- Expand only logically eligible joined members into `activeDevicesWithLegacyFallback()`. Exclude the exact authoring transport, not the whole logical account; include its same-account sibling. Exclude revoked, pending, removed, nonjoined and ambiguous identities. Deduplicate and sort physical target peers.
- Freeze one signed `group_offline_replay` envelope and its full physical ACL under the serialized phase. Message identity is the stable message ID; reaction identity is the exact transition ID. The owner insertion API requires the initially persisted sorted pending set to equal that immutable signed ACL exactly, and the only subset mutation API is expected-row accepted-receipt CAS/final completion. Decoder validation proves syntax, nonempty sorted uniqueness, subset relation and current-target membership; it does not pretend a standalone JSON blob proves historical CAS provenance.
- Bind the inner logical actor and outer physical signer/device, exact group, event identity, payload digest, key epoch, observed authority version and sorted physical ACL. Require outer signed epoch = decrypt epoch = inner epoch. Do not trust a sender-declared discussion/announcement capability; derive group type and role from authenticated authority.
- Snapshot authority, targets and a proposed event order under the keyed phase; perform group encryption/signing ephemerally with no DB, local projection or network; then re-enter the phase and re-read every authority/key/target fact. Drift discards the candidate bytes and returns/retries all-zero. An exact recheck atomically persists and reads back the immutable envelope/owner before any network or canonical projection. This closes the crypto-before-owner gap without a preparatory table or holding the group lock across bridge crypto. Authority producers under the same keyed phase must observe and preserve/disposition prepared content before committing their later transition; a pending row may not become invisible merely because its first network attempt has not completed.

### Protected custody, retry and live delivery

- Add exactly one `AckCustodyKind.groupContentV1` / `group_content_v1` branch. The encrypted, transport-signed replay body must itself carry exact `group_content_v1` as a signed, self-contained wire discriminator; the outer ACK-custody request kind selects storage/retrieval but is not retained by retrieval and is never replay authority. Admission, stored-row/Redis reparse and retrieved replay decode all require the inner signed discriminator to match the selected outer/staged capability exactly; missing, crossed or unsigned-only discriminators reject before canonical mutation or ACK. The branch accepts only incumbent replay `payloadType=group_message` and `payloadType=group_reaction`; reaction ADD/REMOVE is bound by the exact signed `notificationExtension.action` and transition ID, not a new payload type. Plan-363 bootstrap/authority parsers continue rejecting content.
- Relay admission and stored-row/Redis reparse use the same recipient-aware parser. Bind authenticated sender transport, exact request recipient in the signed ACL, group, kind and event. Dedupe namespaces stay distinct: messages by message ID; reactions by transition ID, never by the stable reaction-state ID.
- Derive each per-recipient delivery identity from the kind, immutable event ID and exact recipient transport. This is an outer custody identity, not a new DB target hash or signed logical event.
- Extend the existing retry JSON wrapper only for strict Plan-364 content with `custodyContract=ack_or_expiry_v1`, outer `custodyKind=group_content_v1` and exact pending physical targets. Strict decode proves that outer wrapper kind and selected protected capability both equal the signed inner `group_content_v1` discriminator, group/kind match exactly, and pending targets are sorted, unique, nonempty subsets of the immutable signed ACL with every store target in both; owner insertion and the sole expected-row CAS API enforce initial equality and permitted shrinking.
- For messages, use the existing `group_messages` row in its inbox-retry-owned queued state with exact wrapper bytes before first network. It must never enter fresh-envelope failed-message or incomplete-upload rebuilding. For reactions, build and exact-read back the outbox wrapper before network, obtain every strict receipt, then in one existing-DB transaction apply local ADD/REMOVE and exact-mark the outbox stored. A crash after a receipt safely retries storage: `duplicate` while the relay row survives, or fresh `stored` after recipient ACK/delete, with exact receiver dedupe and an idempotent final transaction. A failed or authority-superseded attempt receives a durable non-retry terminal disposition and never mutates canonical reaction state. The UI may be memory-optimistic but must revert on terminal result. Strict rows never remain `needs_build` or rebuild using current roster/account keys.
- Store each pending physical target through the protected action. Add narrow exact payload-replacement CAS helpers to the existing message and reaction owners; after every nonfinal exact `stored|duplicate`, CAS-remove that recipient from only the outer pending subset. The final receipt is never generic CAS-to-empty: exact-check a singleton expected wrapper, then in one SQL transaction consume it and exact-complete the message; for reactions the same transaction also appends/compares event-log evidence, applies canonical ADD/REMOVE with attention state, and marks the outbox stored. Never persist a spontaneously empty wrapper and complete in a later transaction. A crash or CAS failure leaves the old wrapper and safely retargets the recipient: it is `duplicate` while the relay row lives, or a fresh `stored` after recipient ACK deleted that row; receiver event-log/projection dedupe prevents a second effect. Once survivor CAS commits, that recipient is never targeted again. Partial A-success/B-failure leaves immutable signed A+B bytes plus pending B and makes zero live calls. This reuses one existing JSON field/row and adds no per-target table, receipt ledger or second owner; unlike same-pass all-target completion it cannot livelock when recipients alternate availability.
- Protected P2P custody is the sole delivery and authoring-success path for every strict Plan-364 event, primary or linked; make pubsub calls zero. This avoids topic dependence and prevents a marked live event from entering legacy current-roster handlers before protected historical authorization. Do not invoke `group:sendReliable`; generic group `OK`, topic peers or live success cannot settle strict custody. Incumbent unmarked primary traffic remains byte-identical.
- Already-staged retry is state-driven and consults neither authoring selector, roster resolver, key resolver nor crypto. Inject the strict store capability into the incumbent inbox retrier and expose one narrow flags-independent content retry callback in Plan 363's restricted runtime after bootstrap/authority recovery. Exact completion failure, malformed strict wrapper or lost immutable bytes fails closed and cannot remint.
- Give the existing bounded inbox retry scheduler fair progress across message and reaction owners (for example, reserve/alternate at least one slot when both are pending). Do not add a second scheduler.
- An initially frozen ACL may be empty only when the serialized authority snapshot proves no other deliverable physical device exists, making the local event terminal without a retry wrapper. A decoded/spontaneously empty pending wrapper is malformed; normal last-target completion is owned atomically by the final-receipt transaction above. Prerequisite/ambiguous/corrupt empty inputs retain or terminally fail closed according to typed evidence.

### Authority ordering and terminal transitions

- Content declares the exact authenticated Plan-363 authority version it observed, represented by the accepted signed `(eventAt,eventId)` order plus key epoch. A receiver locates the matching signed authority snapshot/history and proves actor role/device/key membership there. Current role alone and local event-log sequence are insufficient. The additive authority version lives inside the encrypted, transport-signed content payload; the relay request grammar remains unchanged.
- Missing bootstrap, key, observed authority version, or target message with no terminal evidence is `prerequisiteWaiting`: keep local stage and relay row, do not increment replay attempts or quarantine even after more than ten drains, and retrigger after each prerequisite commit. A missing reaction target with an exact local-deletion tombstone or `protected_content_terminal` evidence is durably impossible, so terminal-reject and ACK it rather than waiting forever.
- Use deterministic total ordering `(normalized UTC eventAt, eventId)` with the incumbent bounded future-skew rule. This is the project's signed bounded-clock ordering assumption, not a trusted-real-time or Byzantine revocation oracle. A device retaining an old signing key can backdate within the accepted clock model; stronger exclusion requires a new online monotonic protocol and is not claimed here.
- Under the same Plan-363 serialized phase, a durably prepared content event fixes its signed order even when protected transport is still retrying. Authority-first terminalizes content that sorts after or is not authorized by the accepted snapshot. If content was applied before a later-arriving authenticated authority event proves that same event invalid, authority apply invokes one shared compensating reconciliation before exposing the new authority: hide/remove the invalid canonical message or restore the last valid reaction state, reverse its exact unread/display custody, reconcile dependent reactions, and retain terminal event-log evidence so replay cannot resurrect it. Content that sorts before and was authorized by the later transition remains historical. Both arrival orders therefore converge to the same authority-wins state.
- A pending content row cannot leak through generic retry after terminal reconciliation. Completion re-enters the keyed phase and exact-CASes against the recorded order; it never invents a new event time. Authority producers and protected key apply must run the same bounded reconciliation before their new projection becomes writable.
- Cover only the distinct races: announcement vs admin demotion; discussion vs dissolve; reaction vs member/device removal/re-add; content epoch vs key update. Parameterize both arrival orders and restart rather than creating a transition cross-product.
- Voluntary self-removal remains explicitly deferred. The narrow linked surface exposes no info/settings/leave action, and Plan 364 neither changes nor certifies the incumbent exit-intent workflow. A later control-plane plan must move it through Plan 363's protected authority kind before destructive local cleanup; do not smuggle it into `group_content_v1`.

### Canonical receive, exact replay and attention state

- Add one narrow typed protected apply result: `applied`, `exactDuplicate`, `terminalReject`, `prerequisiteWaiting`, or `retryableFailure`. Relay ACK is allowed only for the first three after their durable evidence exists. Retryable/prerequisite rows remain locally staged and relay-owned.
- Run a bounded fixed-point recovery in one cold/resume call: bootstrap -> authority -> inbound messages -> dependent reactions -> outgoing exact content retry -> notification/list/conversation refresh. After each prerequisite commit, revisit older staged prerequisite rows. Stop on no progress; do not require another lifecycle event.
- Reuse canonical message/reaction persistence and notification custody, but do not infer success from existing void/ignored handlers. A protected adapter supplies a typed authenticated-historical-authority capability after proving the exact signed snapshot; only that adapter bypasses incumbent current-roster/current-role/device gates that would reject a valid pre-demotion/pre-removal event. Legacy paths retain those checks byte-for-byte, and canonical shape/target validation still runs. Propagate the typed result after exact readback and durable display readiness or terminal suppression. OS-plugin display success is not required for relay ACK.
- Append/compare protected content in `group_event_log` using reversible domain-separated source keys because the table is unique on `(group_id,source_event_id)` across all event types: `pm1:<base64url(messageId)>`, `pr1:<gr1TransitionId>`, and `pt1:<base64url(kind)>:<base64url(eventOrDeliveryId)>:<reasonDigest>`. The logical message/reaction IDs remain unchanged and are stored in canonical payload. Use fixed event types `protected_message`, `protected_reaction` and `protected_content_terminal`; malformed/crossed envelopes cannot collide across kinds. Terminal payloads contain only bounded envelope/delivery digests and reason codes. Local `sequence` is only tamper-chain order. Exact evidence with a missing projection is repair authority on replay; conflicting same domain source key/payload is terminal tamper and cannot project.
- Commit the exact event-log append/replay decision, canonical message or reaction mutation, and durable unread/display readiness or suppression in one SQL transaction through transaction-scoped helpers. A pre-commit failure is retryable; a committed projection is exactly reconstructible even when relay ACK or hydrated readback fails. Do not append a success/terminal event and mutate its projection in unrelated transactions.
- Combined exact event-log evidence plus canonical message readback compares message ID, group, logical actor, physical transport/device, text, normalized timestamp/order, key epoch, authority version, policy and empty excluded fields. Fields not carried by the canonical message row remain bound in the exact event-log payload; do not accept the incumbent weak group+sender duplicate comparison.
- For strict reactions, require the cross-language grammar `gr1:<32hex-state>:<20-digit-epochMicros>:<32hex-event>`. Both hex parts are the first 32 lowercase hex characters of SHA-256 over canonical UTF-8 JSON arrays: state preimage `["group_reaction_state_v1",groupId,messageId,logicalActorPeerId]`; event preimage `["group_reaction_event_v1",stateDigest,action,emoji,fixedUtcTimestamp]`. The same single value is used by relay dedupe, event-log source identity and canonical exact comparison; do not create a second alias. Higher `(epochMicros,transitionId)` wins, so equal-time ADD/REMOVE converge identically in either arrival order. Enforce future skew and exact grammar/length. The canonical row plus target group reconstructs the current transition ID. Exact replay emits no second UI change.
- Every protected `source_timestamp` and authority cutoff uses one cross-platform fixed-width UTC representation with six fractional digits and `Z`; SQLite lexical range order must equal chronological order at the exact-millisecond and `+1µs` boundary.
- Authority reconciliation queries fixed protected event types in bounded pages from the authority cutoff using the existing `(group_id,event_type,source_timestamp)` index. It exact-compares the signed authority version in canonical payload, terminalizes invalid messages, and rebuilds an invalid reaction from the latest prior valid state-prefix event. At authority arrival, freeze the upper protected-log `sequence` only as a bounded local progress limit. Page/complete terminal facts bind the authority event ID, frozen upper sequence and last processed candidate; sequence is never authorization order. While that reconciliation is pending, all strict ingress/completion and linked content UI for the group stay prerequisite/non-writable. Only an exact complete fact and final in-transaction recheck expose the new authority. Crash/restart resumes from the durable page frontier idempotently; do not add a cursor table or in-memory-only completion bit.
- When an ADD reaches displayed or terminally suppressed custody, write a domain-separated `protected_reaction_display_terminal` event-log fact for that transition in the same transaction that retires display custody. That durable fact survives a newer ADD replacing the sole canonical row. Historical restoration exact-loads it, atomically restores the prior reaction with terminal display suppression, and deletes invalid ADD custody; invalid newer ADD -> authority rollback -> restart never creates a new display row.
- Keep reaction-before-target in protected staging, not the legacy pending-reaction buffer. Target arrival retriggers protected replay; only then apply and ACK.
- Protected content may not mutate member username/profile/config. Display name comes from the accepted authority snapshot, and the roster remains byte-identical.
- Pass logical local account identity separately from the physical recipient. Same-account sibling delivery is a self/outgoing timeline reconciliation with zero unread and zero notification. A non-self fresh message increments installation-local unread once; reactions never increment unread. Fresh non-self ADD may create at most one durable notification, and REMOVE reconciles it once.
- If relay ACK fails after durable apply/duplicate/terminal evidence, redelivery reads that evidence, performs no second projection/unread/UI transition and retries only the exact ACK.

### Restricted linked runtime and writable surface

- Extend only Plan 363's restricted linked runtime. Inject `AckOrExpiryInboxStore` into the strict branch of the incumbent inbox retrier while leaving legacy Bridge behavior byte-identical; wire that capability at primary composition roots and expose one content-only callback to the restricted linked owner. Cold/resume order is protected inbox listener/retrieve -> bootstrap -> authority -> inbound content fixed point -> outgoing exact content retry -> notification/list/conversation refresh. Pause stops content admission, awaits in-flight handlers and retains staged/unacked/outbox rows.
- Start no group topic, aggregate group inbox/cursor/history/gap repair, generic pending-broadcast runner, feed/posts/contact/push/provider/wake/media owner or `startLiveServices` branch for the linked role. Primary behavior remains incumbent unless the strict selector branch is selected.
- Add one injected `onOpenLinkedGroup(groupId)` to the Plan-363 linked list and one narrow linked conversation wired owner. Reuse the pure `GroupConversationScreen`, but filter its timeline/reaction predicate to eligible ordinary blob-free rows only; empty media maps alone do not hide historical captions/quotes/forwards/system rows. Keep all attachment/voice/private/share/quote/info/settings callbacks null.
- The narrow owner supplies only local timeline/read, eligible text send, and ordinary-message reaction ADD/REMOVE. It loads the logical account and actual linked credential separately, requires bootstrap/current membership/key/authority settled, subscribes to authority refresh, and requalifies under the serialized phase at every send/tap.
- Announcement composer is visible only for the authenticated admin role. Active announcement readers may react. Demotion/removal/dissolve/key drift cancels or refuses stale callbacks before persistence/crypto/network.

## TDD Matrix

| ID | RED contract and causal assertions | Existing owners | Baseline expectation |
|---|---|---|---|
| TC-364-01a | Parameterized discussion + announcement authoring resolves logical actor and exact physical signer; includes same-account sibling, expands only eligible active devices, excludes current transport/revoked/nonjoined; candidate crypto is discarded on in-lock recheck drift; exact envelope persists before network with initial pending set equal to its signed ACL; protected receipts converge with zero pubsub; non-admin, selector-off initialized, missing credential and ineligible content are all-zero; uninitialized ordinary-primary control remains incumbent. | `send_group_message_use_case_test.dart`; recipient-eligibility; group replay envelope; messaging smoke | Compile-clean RED against Plan-363 APIs; incumbent selector-off/concurrent reliable tests remain preservation-only outside the strict branch. |
| TC-364-01b | Parameterized message + reaction owners: only accepted-receipt CAS may shrink initial A+B; A accepted/B failed CASes only A, publishes zero and retains immutable signed A+B; crash-before-CAS covers row-live duplicate and ACK-delete/fresh-store A without duplicate receiver effect; committed CAS never retargets A; B final transaction completes with zero roster/key/crypto rebuild; alternating availability cannot livelock; malformed/empty dispositions and terminal supersession fail closed; bounded message/reaction fairness prevents starvation. | failed group-message and inbox-store retry tests; group message/reaction DB/repository helpers | Compile-clean RED; existing exact signed-replay retry and CAS tests remain green. |
| TC-364-02a | ADD/REMOVE use current transport credential and frozen physical ACL, strict custody with zero pubsub; unbound REMOVE refuses; outbox-before-network then all-receipts + local-state/outbox completion is one transaction; post-receipt crash covers relay-row duplicate and ACK-delete/fresh-store with exact receiver/final-transaction idempotence; exact `gr1` grammar, equal-time ADD/REMOVE both orders/restart and millisecond/+1µs index boundary converge; future-skew rejects; exact replay produces zero second UI/notification transition; invalidated latest transition restores prior state without re-notifying a displayed ADD. | ADD/REMOVE use-case tests; reaction DB helper; event-log helper; reaction roundtrip | Compile-clean RED; incumbent legacy reaction behavior stays unchanged off the strict branch. |
| TC-364-03a | Crossed outer/logical/device/key/recipient/group/event/payload/epoch and reserved-system content reject; retrieved bytes with missing, unsigned-only or crossed signed inner `group_content_v1` discriminator reject even when the selected outer/staged custody capability says content; domain-separated event-log keys prevent a message ID from colliding with a valid `gr1` reaction; fixed-point bootstrap/authority/message/reaction replay converges in one lifecycle call; prerequisites survive >10 drains; a target absent without evidence waits while local-deletion/protected-terminal evidence rejects+ACKs; exact/conflicting IDs, ACK failure, self-echo and unread/notification rules converge. Parameterized authority-first/content-first races prove the same final state and valid historical admission through only the typed capability; a multi-page reconciliation crash resumes its exact frontier with ingress/UI gated until completion. | P2P ACK ordering; replay envelope; incoming message/reaction; listener; membership watermark; notification wiring/pipeline; member removal | Compile-clean RED; ordinary topic/aggregate paths and Plan-363 authority-only content rejection remain green. |
| TC-364-04a | Restricted linked cold/resume/pause inserts content between authority and refresh, drains committed rows with selectors off, starts no broad owner/topic/pubsub; linked list tap opens only the narrow capability surface while disabled/missing authority remains non-tappable; system/media/private/quoted rows expose no reaction/send affordance while an ordinary announcement remains reactable; live or reconciling authority revokes the surface; B1b runner contract retains explicit physical-Android-first/emulator-second validation. | bootstrap phase, startup router/home, QR-display/linked-list owner, group conversation, resume/inbox-retry/pause, runner contract | Compile-clean RED for host contract; physical pair is acceptance-only after GREEN. |

No additional modality, per-transition, migration, SQLCipher or device matrix is required. Existing private/media policy tests already prove excluded shapes; curated `groups` owns unchanged GP-026 and P269 preservation. If implementation needs a new test path rather than one of the listed owners, stop, justify it, register it once and update the accepted Plan-363 inventory before proceeding.

## Preservation Sentinels

- `GI-004 group inbox recipients follow current remove and re-add entitlement windows` and `IR-006 group inbox store targets exact active recipients at send time` preserve logical eligibility while TC-364 adds physical expansion.
- `EK004 stores signed offline replay envelope for group_message`, reaction ADD/REMOVE EK004 rows, and `EK004 retry preserves signed group offline replay envelope fields` preserve incumbent signed replay shape.
- The two existing `PGC-010` membership-phase order rows are adapted, not duplicated, to exercise strict content-first and authority-first outcomes.
- Plan-363 `TC-363-01b`, `TC-363-02a` and `TC-363-03a` remain preservation sentinels for bootstrap, authority and restricted runtime after the final accepted implementation names are pinned.
- `TC-361-03b` remains the direct restricted-runtime preservation seam.
- GP-026 live+inbox dedupe and P269 physical group-media ACL remain owned by the single curated `groups` lane; they are not repeated in the focused command.

## Representative Mutations

Run exactly four production mutations serially after GREEN, reverting each before the next:

1. Collapse strict message recipients to logical member IDs and exclude the entire sender account -> `TC-364-01a` RED.
2. Remove per-recipient survivor CAS and require one same-pass all-target success -> `TC-364-01b` alternating-availability/relay-ACK RED.
3. Compare strict reactions by timestamp only, removing the deterministic transition-ID tie break -> `TC-364-02a` RED.
4. ACK a `prerequisiteWaiting` protected content row -> `TC-364-03a` RED.

Do not count parser syntax errors, test-only mutations or paired `or` alternatives. Record the exact selector, failing assertion and revert SHA/diff for each.

## Implementation Order

1. **Complete:** pin and revalidate the clean Plan-363 audit SHA, committed Graphify snapshot, DB floor, authority history/serializer, protected apply/ACK contract, linked credential resolver, runtime callbacks and `groups` inventory. No listed host-boundary incompatibility remains.
2. Author the four Flutter RED bundles and both exact Go REDs. Record compile-clean RED for all five host IDs before production wiring.
3. Add the one protected content kind and shared recipient-aware parser in node/relay, including stored-row Redis reparse and kind-separated dedupe.
4. Add the strict retry-wrapper discriminator, physical author resolver, exact target snapshot, persist-before-network sender branches and state-driven survivor retry/fairness.
5. Add typed protected receive, fixed-point prerequisite replay, exact event-log/canonical readback, deterministic reaction ordering and durable terminal/ACK evidence under the shared authority phase.
6. Add the restricted runtime phase and narrow linked conversation surface; keep voluntary self-removal unavailable and deferred.
7. Reach GREEN, run the four mutations serially, then run the one final focused c4 proof, exact Go proof, mandatory affected gates, one B1b pair if available, hygiene and one incremental Graphify refresh.

## Commands And Gate Cadence

Literal prerequisite preflight against the accepted Plan-363 closure:

```bash
set -euo pipefail
PLAN364_ACCEPTED_BASE='082f5e96f96b4be0362b474884059e0cdeff6399'
PLAN364_EXPECTED_GROUP_PATHS='244'
case "$PLAN364_ACCEPTED_BASE" in *'<'*|*'>'*) exit 1 ;; esac
case "$PLAN364_EXPECTED_GROUP_PATHS" in ''|*[!0-9]*) exit 1 ;; esac
test "$(git rev-parse "$PLAN364_ACCEPTED_BASE^{commit}")" = "$PLAN364_ACCEPTED_BASE"
git merge-base --is-ancestor "$PLAN364_ACCEPTED_BASE" HEAD
test -z "$(git status --porcelain)"
test -z "$(git diff --name-only "$PLAN364_ACCEPTED_BASE"..HEAD | \
  rg -v '^(Test-Flight-Improv/(363-gap-n01-linked-group-self-bootstrap-authority-foundation-tdd-plan|364-gap-n01-linked-group-blob-free-content-custody-tdd-plan|00-INDEX)\.md|UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1\.2_Codebase_Coverage_and_Gaps\.md|STATUS\.md)$')"
python3 - "$PLAN364_EXPECTED_GROUP_PATHS" <<'PY'
import re
import sys
from pathlib import Path

text = Path('scripts/run_test_gates.sh').read_text()
block = text.split('readonly GROUP_TESTS=(', 1)[1].split('\n)', 1)[0]
paths = re.findall(r'^\s*"([^"]+\.dart)"\s*$', block, re.MULTILINE)
expected = int(sys.argv[1])
assert len(paths) == expected, (len(paths), expected)
assert len(paths) == len(set(paths)), 'duplicate GROUP_TESTS path'
assert all(Path(path).is_file() for path in paths), 'missing GROUP_TESTS path'
print(f'GROUP_TESTS {len(paths)}/{len(set(paths))} unique')
PY
```

Independent Flutter files must run concurrently where supported to speed feedback. Each `TC-364-*` ID below names exactly one top-level parameterized test whose internal cases cover its table row. These are the four development bundles; do not run the same files whole between RED and GREEN:

```bash
# Sender identity, physical ACL, strict custody-before-live.
flutter test --concurrency=4 \
  test/features/groups/application/send_group_message_use_case_test.dart \
  test/features/groups/application/send_group_message_recipient_eligibility_test.dart \
  test/features/groups/application/group_offline_replay_envelope_test.dart \
  test/features/groups/integration/group_messaging_smoke_test.dart \
  --plain-name 'TC-364-01a protected blob-free group authoring freezes physical custody with zero pubsub'

# Survivor retry/fairness plus reaction ADD/REMOVE ordering.
flutter test --concurrency=4 \
  test/features/groups/application/retry_failed_group_messages_use_case_test.dart \
  test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart \
  test/features/groups/application/send_group_reaction_use_case_test.dart \
  test/features/groups/application/remove_group_reaction_use_case_test.dart \
  test/core/database/helpers/group_messages_db_helpers_reliability_test.dart \
  test/features/groups/domain/repositories/group_message_repository_impl_test.dart \
  test/core/database/helpers/reactions_db_helpers_test.dart \
  test/core/database/helpers/group_event_log_db_helpers_test.dart \
  test/features/groups/integration/group_reaction_roundtrip_test.dart \
  --name 'TC-364-01b|TC-364-02a'

# Typed receive, authority races and exact observables.
flutter test --concurrency=4 \
  test/core/services/p2p_service_inbox_ack_ordering_test.dart \
  test/features/groups/application/group_offline_replay_envelope_test.dart \
  test/features/groups/application/handle_incoming_group_message_use_case_test.dart \
  test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart \
  test/features/groups/application/group_message_listener_test.dart \
  test/features/groups/application/group_membership_event_watermark_test.dart \
  test/features/groups/application/group_notification_display_outbox_wiring_test.dart \
  test/features/groups/integration/group_reaction_notification_pipeline_test.dart \
  test/features/groups/application/member_removal_integration_test.dart \
  --plain-name 'TC-364-03a protected content applies in authenticated authority order before exact ACK'

# Restricted runtime/UI plus the existing B1b host runner contract.
flutter test --concurrency=4 \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  test/features/identity/presentation/screens/startup_router_test.dart \
  test/features/identity/presentation/screens/startup_router_home_surface_test.dart \
  test/features/qr_code/presentation/screens/qr_display_wired_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart \
  test/core/lifecycle/handle_app_resumed_group_recovery_test.dart \
  test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart \
  test/core/lifecycle/handle_app_paused_group_test.dart \
  test/integration/invite_reliability_runner_contract_test.dart \
  --plain-name 'TC-364-04a linked runtime exposes only protected blob-free group content'
```

Exact Go RED/GREEN; missing registration and false-positive package success must fail:

```bash
set -euo pipefail
plan364_go_log="$(mktemp)"
trap 'rm -f "$plan364_go_log"' EXIT
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node \
  -list '^TestTC364GroupContentProtectedCustody$' | \
  rg -x 'TestTC364GroupContentProtectedCustody')
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . \
  -list '^TestRelayNotificationClosure_GroupContentProtectedCustody$' | \
  rg -x 'TestRelayNotificationClosure_GroupContentProtectedCustody')
(set -o pipefail; (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge \
  -run '^TestDispatchInboxAckCustodyContract$' -count=1 -v) | tee "$plan364_go_log")
grep -Eq '^--- PASS: TestDispatchInboxAckCustodyContract \(' "$plan364_go_log"
: > "$plan364_go_log"
(set -o pipefail; (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node \
  -run '^TestTC364GroupContentProtectedCustody$' -count=1 -v) | tee "$plan364_go_log")
grep -Eq '^--- PASS: TestTC364GroupContentProtectedCustody \(' "$plan364_go_log"
: > "$plan364_go_log"
(set -o pipefail; (cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . \
  -run '^TestRelayNotificationClosure_GroupContentProtectedCustody$' \
  -count=1 -v) | tee "$plan364_go_log")
grep -Eq '^--- PASS: TestRelayNotificationClosure_GroupContentProtectedCustody \(' "$plan364_go_log"
rm -f "$plan364_go_log"
trap - EXIT
```

After all four mutations re-red and are reverted, run one deduplicated final focused invocation. Require all five host IDs and reject skipped Plan-364 rows:

```bash
plan364_flutter_log="$(mktemp)"
trap 'rm -f "$plan364_flutter_log"' EXIT
if ! (set -o pipefail; flutter test --concurrency=4 --reporter expanded \
  test/features/groups/application/send_group_message_use_case_test.dart \
  test/features/groups/application/send_group_message_recipient_eligibility_test.dart \
  test/features/groups/application/group_offline_replay_envelope_test.dart \
  test/features/groups/integration/group_messaging_smoke_test.dart \
  test/features/groups/application/retry_failed_group_messages_use_case_test.dart \
  test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart \
  test/features/groups/application/group_pending_broadcast_runner_test.dart \
  test/features/groups/application/send_group_reaction_use_case_test.dart \
  test/features/groups/application/remove_group_reaction_use_case_test.dart \
  test/core/database/helpers/group_messages_db_helpers_reliability_test.dart \
  test/features/groups/domain/repositories/group_message_repository_impl_test.dart \
  test/core/database/helpers/reactions_db_helpers_test.dart \
  test/core/database/helpers/group_event_log_db_helpers_test.dart \
  test/features/groups/integration/group_reaction_roundtrip_test.dart \
  test/features/groups/domain/repositories/group_repository_impl_test.dart \
  test/core/services/p2p_service_inbox_ack_ordering_test.dart \
  test/features/groups/application/handle_incoming_group_message_use_case_test.dart \
  test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart \
  test/features/groups/application/group_message_listener_test.dart \
  test/features/groups/application/group_membership_event_watermark_test.dart \
  test/features/groups/application/group_notification_display_outbox_wiring_test.dart \
  test/features/groups/integration/group_reaction_notification_pipeline_test.dart \
  test/features/groups/application/member_removal_integration_test.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  test/features/identity/presentation/screens/startup_router_test.dart \
  test/features/identity/presentation/screens/startup_router_home_surface_test.dart \
  test/features/qr_code/presentation/screens/qr_display_wired_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart \
  test/core/lifecycle/handle_app_resumed_group_recovery_test.dart \
  test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart \
  test/core/lifecycle/handle_app_paused_group_test.dart \
  test/integration/invite_reliability_runner_contract_test.dart \
  --name 'TC-364-|TC-363-01b|TC-363-02a|TC-363-03a|GI-004|IR-006|EK004 retry preserves signed group offline replay envelope fields|TC-361-03b' | \
  tee "$plan364_flutter_log"); then
  exit 1
fi
for plan364_new_id in \
  TC-364-01a TC-364-01b TC-364-02a TC-364-03a TC-364-04a; do
  test "$(grep -Fc -- "$plan364_new_id" "$plan364_flutter_log")" -eq 1 || exit 1
done
for plan364_id in TC-364-01a TC-364-01b TC-364-02a TC-364-03a TC-364-04a \
  TC-363-01b TC-363-02a TC-363-03a GI-004 IR-006 \
  'EK004 retry preserves signed group offline replay envelope fields' TC-361-03b; do
  grep -Fq -- "$plan364_id" "$plan364_flutter_log" || exit 1
done
if grep -E \
  '~[0-9]+:.*(TC-364-|TC-363-01b|TC-363-02a|TC-363-03a|GI-004|IR-006|EK004 retry preserves signed group offline replay envelope fields|TC-361-03b)' \
  "$plan364_flutter_log" >/dev/null; then exit 1; fi
rm -f "$plan364_flutter_log"
trap - EXIT
```

Run only the affected mandatory contracts and curated lane once:

```bash
set -euo pipefail
flutter test --concurrency=4 \
  test/unit/dtr18_placement_closure_contract_test.dart \
  test/unit/dtr18_layering_relocation_contract_test.dart
bash scripts/test/relay_ack_custody_rollout_contract_test.sh
./scripts/run_test_gates.sh runtime-roots
./scripts/run_test_gates.sh groups
```

Extend the existing group Go-tail regex to include `TC364`. In `relay_ack_custody_rollout_contract_test.sh`, extract the body of `run_group_forwarding_go_bridge_gate`, require exactly one `go test ./bridge ./node -run` selector there, and exact-match that selector with `TC364`; a comment or unrelated occurrence must not pass. Extend `TestDispatchInboxAckCustodyContract` for bridge allowlist threading. The relay test remains automatically selected by `^TestRelayNotificationClosure_`. The existing B1b registration/discovery contract is unchanged and is not rerun unless implementation actually edits its dispatcher/discovery registry. Do not add a new Go tail, run a standalone group-media gate, or run `groups` twice.

After separately authorized production ACK-custody admission is enabled and Plan 363's B1b production bootstrap/reopen journey passes, extend that same scenario with one offline blob-free discussion delivery, one reaction ADD/REMOVE round trip, then its existing protected terminal authority. The protected-kind binary is already deployed; the remaining admission/B1b prerequisite blocks only the device leg, not Plan-364 host development. Host tests cover announcement policy; no second announcement/device scenario is needed. Resolve and pin the live matrix at execution time:

```bash
set -euo pipefail
flutter devices --machine
adb devices -l
PLAN364_PHYSICAL_ANDROID_ID='<USB_ANDROID_ID>'
PLAN364_EMULATOR_ANDROID_ID='<ANDROID_EMULATOR_ID>'
test "$PLAN364_PHYSICAL_ANDROID_ID" != '<USB_ANDROID_ID>'
test "$PLAN364_EMULATOR_ANDROID_ID" != '<ANDROID_EMULATOR_ID>'

RELIABILITY_MULTI_DEVICE_IDS="$PLAN364_PHYSICAL_ANDROID_ID,$PLAN364_EMULATOR_ANDROID_ID" \
  ./scripts/run_test_gates.sh reliability-sim group --list \
  --only integration_test/scripts/run_b1b_sibling_device_convergence.dart
RELIABILITY_MULTI_DEVICE_IDS="$PLAN364_PHYSICAL_ANDROID_ID,$PLAN364_EMULATOR_ANDROID_ID" \
  ./scripts/run_test_gates.sh reliability-sim group \
  --only integration_test/scripts/run_b1b_sibling_device_convergence.dart
```

Use one discovered USB Android physical device first and one Android emulator second. The automated runner owns setup, permissions, actions and assertions. If that topology is unavailable, record `N/A (target unavailable by project policy)`; do not substitute an iPhone, require taps/third hardware, or block on an unavailable OS/API band.

Final hygiene, using the accepted Plan-363 SHA literally in a fresh shell:

```bash
set -euo pipefail
plan364_base_ref='082f5e96f96b4be0362b474884059e0cdeff6399'
case "$plan364_base_ref" in *'<'*|*'>'*) exit 1 ;; esac
flutter analyze
plan364_dart_list="$(mktemp)"
plan364_go_list="$(mktemp)"
plan364_gofmt_log="$(mktemp)"
trap 'rm -f "$plan364_dart_list" "$plan364_go_list" "$plan364_gofmt_log"' EXIT
{
  git diff --name-only --diff-filter=ACMR "$plan364_base_ref"...HEAD -- '*.dart'
  git diff --name-only --diff-filter=ACMR -- '*.dart'
  git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
  git ls-files --others --exclude-standard -- '*.dart'
} | sort -u > "$plan364_dart_list"
test ! -s "$plan364_dart_list" || \
  xargs dart format --output=none --set-exit-if-changed < "$plan364_dart_list"
{
  git diff --name-only --diff-filter=ACMR "$plan364_base_ref"...HEAD -- '*.go'
  git diff --name-only --diff-filter=ACMR -- '*.go'
  git diff --cached --name-only --diff-filter=ACMR -- '*.go'
  git ls-files --others --exclude-standard -- '*.go'
} | sort -u > "$plan364_go_list"
test ! -s "$plan364_go_list" || xargs gofmt -l < "$plan364_go_list" > "$plan364_gofmt_log"
test ! -s "$plan364_gofmt_log"
rm -f "$plan364_dart_list" "$plan364_go_list" "$plan364_gofmt_log"
trap - EXIT
git diff --check "$plan364_base_ref"...HEAD
git diff --check
git diff --cached --check
./graphify-arch/refresh_arch_graph.sh --incremental
python3 graphify-arch/tdd_context.py query \
  "Review Plan 364 linked-group protected blob-free content custody: physical signer and ACL, exact retry, authority order, typed receive ACK, reaction convergence, restricted runtime and narrow UI" \
  --profile review --budget 800
git diff --check "$plan364_base_ref"...HEAD
git diff --check
git diff --cached --check
git status --short
```

Do not run a migration/SQLCipher leg, standalone group-media suite, `1to1`, core-host-all, feature-host-all, performance or full `host-all` for this schema-free group-content slice. Full `host-all` remains a once-per-dependency-wave and final-release obligation under repository policy.

## Risks, Stops And Reversibility

- Strict group content is not safe if any caller can use account credentials on a linked transport, publish before all physical receipts, rebuild after restart, or settle from generic `OK`. Centralize and fail closed rather than enumerate UI-only guards.
- The exact Go surface is expected to include `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/inbox_ack_custody_test.go`, `go-mknoon/node/inbox.go`, `go-mknoon/node/inbox_ack_custody_test.go`, `go-relay-server/ack_custody.go`, `go-relay-server/backend_redis.go` and `go-relay-server/ack_custody_protocol_test.go`; hygiene derives every changed Go path so an additional parser/helper cannot escape formatting.
- Event-vs-authority ordering inherits the documented bounded-clock trust model. Do not describe it as a cryptographic real-time revocation oracle.
- Event-log exact identity is durable evidence, but its insertion `sequence` is not global order. Never authorize from sequence alone.
- Protected terminal evidence may contain only bounded canonical identifiers/digests, never plaintext secrets or keys. The signed/encrypted replay remains in the incumbent encrypted DB owner.
- If the schema-free reaction comparator cannot be exact and bounded, stop before implementation. One explicit additive migration is safer than an unbounded event-log scan or arrival-order convergence, but it requires a revised plan and SQLCipher proof.
- Selector rollback is reversible because it blocks only new authoring; committed strict rows continue to converge. Relay/parser support is additive and remains deployed before any future activation.

## Done Criteria

- [x] Plan 363 is cleanly implemented and post-execution audited at `082f5e96f96b4be0362b474884059e0cdeff6399`; its committed Graphify `681115963b6c3b2a`, DB v114, stable common fresh/deferred sender/A/B key authority including zero-target rotations, restart-safe two-phase dissolve with durable survivor progress, bounded prepared-only recovery, sender/receiver history, credential/protected-runtime APIs and 244/244 `groups` inventory are pinned and revalidated before RED.
- [ ] Eligible discussion/admin-announcement/reaction authoring resolves logical actor plus exact physical signer, freezes all eligible physical targets including same-account siblings, persists exact bytes before egress, converges every strict receipt and makes zero pubsub calls for marked content.
- [ ] Existing message/reaction owners retain immutable full signed authority plus an exact-CAS mutable pending-recipient subset across partial success, relay ACK/delete, crash and selector rollback without a new table/ledger, roster/key/crypto rebuild, singular/aggregate demotion or starvation.
- [ ] One additive content kind/parser binds sender, recipient, ACL, group, event, payload and epoch consistently in admission and stored-row/Redis reparse; the signed replay body carries a self-contained exact inner `group_content_v1` discriminator that retrieval validates independently of the non-retained outer request kind; missing/crossed discriminators reject and bootstrap/authority namespaces remain separate.
- [ ] Typed receive, fixed-point prerequisite recovery, one-transaction event-log/projection/attention commit and durable ACK evidence converge message/reaction replay exactly once without attempt burn, duplicate UI/unread/notification effects or content-to-authority mutation.
- [ ] Announcement demotion, member/device removal/re-add, dissolve and key-update races converge under the accepted signed authority order in both arrival orders; later authority transactionally reconciles any invalid earlier projection and the bounded-clock trust limit is recorded honestly.
- [ ] The narrow linked surface exposes no voluntary-leave control; voluntary self-removal remains explicitly assigned to later protected control-plane work and cannot enter the content kind.
- [ ] The linked runtime starts only exact protected content recovery/retry after bootstrap+authority, and the narrow conversation exposes only eligible text and reactions with live authority requalification.
- [ ] Exactly four mutations re-red independently and are reverted. All independent multi-file Flutter commands run with concurrency 4 wherever supported to speed feedback; the final focused proof is non-vacuous and has zero Plan-364 skips.
- [ ] Both exact Go tests, DTR c4, the rollout contract, runtime roots and one curated `groups` gate pass once; the discovery contract runs only if dispatcher/discovery registration changes. No unjustified migration/SQLCipher/family/full-host gate is run.
- [ ] The accepted B1b Android pair adds one offline discussion and reaction round trip, or records availability-policy N/A without substituting unavailable hardware.
- [ ] Analyzer, changed-Dart and Go formatting, three diff checks and one post-change Graphify refresh/review are clean; index/status/GAP coverage record actual evidence while media/history/activation/GAP-N01/release remain open.

## Reviewer Findings

### Lens 1 - Architecture and production reachability

- Review confirmed one additive `group_content_v1` protected kind over Plan 363 is the smallest production-reachable slice. Because retrieval does not preserve the request's custody kind, the signed replay must also be self-describing with an exact inner `group_content_v1` discriminator; outer/staged selection alone is insufficient. The existing aggregate group inbox, group topics and full wired conversation are rejected because they cannot provide recipient-independent ACK, historical-authority apply, or a restricted linked surface.
- Review made strict marked content protected-P2P-only with zero pubsub. This removes the concurrent `group:sendReliable` bypass and keeps unmarked ordinary-primary behavior unchanged.

### Lens 2 - Trust and failure ordering

- Review separated logical actor from physical signer/recipient; pinned the exact two-selector conjunction; required one shared keyed serializer for messages, reactions, retries, key apply and authority; and made candidate crypto subject to an in-lock recheck before persistence.
- Review closed alternating-recipient liveness with immutable signed ACL plus CAS-derived pending survivors, distinguished relay-row duplicate from ACK-delete fresh storage, and required the final reaction receipt/projection/outbox/event-log/attention transition to be one transaction.
- Review rejected arrival-dependent authorization. Typed historical authority plus bounded reconciliation now makes authority-first and content-first converge; fixed UTC, `gr1` transition grammar, domain-separated event-log keys, durable display suppression and reconciliation frontiers make restart behavior explicit. The bounded-clock threat limit is stated rather than overstated.

### Lens 3 - Test sufficiency and non-vacuity

- Five top-level parameterized host IDs across four concurrency-4 bundles cover sender, survivor retry/fairness, reactions, receive/order and restricted runtime/UI. Exact ID cardinality, preservation presence and skip rejection make the final focused proof non-vacuous.
- Exact bridge/node/relay tests and permanent Go-tail registration cover kind threading, recipient parser/dedupe and Redis stored-row reparse. Mandatory DTR/runtime roots and one curated `groups` pass are sufficient; one B1b extension is the only distinct device seam.

### Lens 4 - Economy and reversibility

- Review removed same-pass full-list retry, optional live publish, voluntary-leave adoption and generic discovery reruns. Existing message/reaction/event-log owners carry the contract without a new table, scheduler, target ledger or bridge command.
- No migration/SQLCipher, standalone group-media, 1:1, core/feature/full-host, performance, iOS or second device campaign is justified. Independent Flutter tests explicitly run concurrently at four wherever supported; mutations, curated gates and device work stay serial.
- Sender/retry, receiver/runtime/UI and gate reviewers all returned READY after the bounded amendments; literal cited paths exist, all seven Bash fences parse, and the final focused path list is deduplicated.

## Arbiter Decision

`EXECUTION_READY / HOST-DEVELOPMENT-UNBLOCKED / LIVE-ACCEPTANCE-BLOCKED.` The proposed Plan 364 boundary is one
protected blob-free content kind over Plan 363's authority foundation, with
existing message/reaction/event-log owners, a typed receive decision and one
narrow linked conversation. `$tdd-review` finds the contract coherent,
sufficient and necessary-only after the recorded amendments. Plan-363's clean
audit closure satisfies the host-development prerequisite; default-off
production ACK-custody admission and B1b remain separate blockers for device
acceptance, activation and release only.

## Handoff

- Current state: `EXECUTION_READY / HOST-DEVELOPMENT-UNBLOCKED / LIVE-ACCEPTANCE-BLOCKED`; Plan 363 is pinned at `082f5e96f96b4be0362b474884059e0cdeff6399`, Graphify `681115963b6c3b2a`, DB v114 and `GROUP_TESTS` 244/244. Deferred common-proof retry, dissolve survivor progress and prepared-only zero-target recovery are closed. No Plan-364 RED or production implementation has started.
- Live-acceptance action: obtain separate S2 production-admission authorization/operations evidence, enable ACK custody only for Plan-363 B1b on the already deployed Redis-backed relay, and restore it to off immediately afterward. Persistent admission requires a separately authorized rollout decision; B1b still precedes Plan-364 device acceptance, activation or release. Do not downgrade to aggregate storage while admission is pending.
- First execution action: run the literal preflight, then author `TC-364-01a`, `01b`, `02a`, `03a`, `04a` and both exact Go REDs before production wiring.
- Runtime economy: run independent Flutter files concurrently with `--concurrency=4` whenever supported to speed feedback; keep mutations, curated gates and the device pair serial.
- Successor work: Plan 365 owns group media/blob/voice and per-final-recipient blob lifetime. Later work owns group history/no-intent, activation, mixed-version rollout, legacy retirement and final GAP-N01/release closure.
