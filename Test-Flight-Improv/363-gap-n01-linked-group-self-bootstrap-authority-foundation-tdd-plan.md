# 363 - GAP-N01 Linked-Group Self-Bootstrap And Authority-Convergence Foundation

Status: IMPLEMENTED / host-verified / live-deployment-blocked / default-off / not release-eligible
Type: Modification
Planning baseline: `17e90bfcef5b74a7f4055225403f8cdf297f7bd1` (clean Plan-362 post-execution audit-hygiene closure over source/receipt closure `051e26d5aefca8dc2f89d8d8c6d83113187c9ed5`; Graphify `4bf3025ee64828d0`, 72,428 nodes / 106,174 edges)
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` A-18 and OQ-04; GAP-N01 / WP-01 in `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`; successor to Plan 362's direct event/blob fanout slice
Classification: schema-free, group-scoped same-account linked-installation bootstrap plus receive-only group authority convergence; no group content authoring, media, activation, release, or GAP-N01 closure claim
Closure tier: four focused concurrent host bundles, four representative mutations, two exact protected-custody Go tests, mandatory DTR/runtime-root checks, the curated `groups` lane once, and one availability-bounded physical-Android + Android-emulator upgrade of the existing B1b scenario

## Planning Progress

| Time | Role | Evidence inspected | Decision / blocker | Disposition |
|---|---|---|---|---|
| 2026-08-12 | Evidence collector / planner | Graphify TDD context; Plan-360 linked identity/QR authority; Plan-361 physical/logical resolver and restricted runtime; active Plan-362 tree; group member device roster, invite, replay, key, pending-broadcast and B1b owners | Plan 362 is being implemented in the shared tree, so its final SHA, DB floor, runtime APIs and graph do not yet exist. | Plan the successor now, but block every RED until Plan 362 is cleanly implemented, audited, committed and revalidated. |
| 2026-08-12 | Production reachability review | `announceRestoredDeviceToGroups`, retired group hydration contract, `StartupRouter`, linked setup/FTE surfaces, and `_importGroupShellForB1b` | A fresh linked installation has no group, member or key rows. Local-only announce/rejoin cannot discover a missing group, and the current B1b shell import is test-only teleportation. | Add one explicit group-scoped self-bootstrap from the existing dual-signed QR; do not claim generic discovery, history hydration or activation. |
| 2026-08-12 | Custody / restart review | Legacy `group_store`, `GroupInboxBackend`, protected ACK-or-expiry P2P lane, `pending_group_broadcasts`, pending key-distribution rows, invite live/offline ordering and P2P typed staging | Aggregate group inbox custody has no per-device ACK and can evict/merge rows; generic `OK` cannot prove non-destructive custody. Existing protected P2P store/retrieve/ACK already owns the required per-physical-recipient contract. | Add only strict group-bootstrap and group-authority kinds/parsers to the existing action/backend. Reuse existing durable group rows; no new table, ledger, ACK state or relay action. |
| 2026-08-12 | Atomicity / trust review | Pending sibling admission; automatic key redistribution; sequential invite materialization; hard-coded joined role; account-vs-transport signing; role/removal/dissolve/key-update paths | Admission currently reopens key distribution and deletes the trust row before bootstrap custody. Fresh invite persistence can partially save group/member/key and forces `member`, which is unsafe for a same-account admin. | Persist admitted roster plus exact bootstrap wire authority atomically, suppress the incumbent distribution bypass, and add one atomic receiver materializer that preserves the exact self role. |
| 2026-08-12 | Product-scope review | Initial proposal combining bootstrap, discussion, announcement and reactions; physical-recipient event fanout; authority races | Writable group events are not safe until a fresh linked installation can materialize a group and converge membership/role/removal/dissolve/key authority. Combining both mechanisms creates too many new trust and runtime boundaries for one economical plan. | Plan 363 ends at a production-reachable read-only group authority foundation. Plan 364 owns blob-free discussion/announcement/reaction authoring; Plan 365 owns group blobs/media/voice. |
| 2026-08-12 | Test / gate review | Existing group/admission/invite/system-transition/runtime tests; group curated inventory; protected-custody Go tails; B1b runner; DTR-18 and runtime-root contracts | Existing test files and schemas are sufficient. One migrated B1b journey is the only distinct physical seam; no migration/SQLCipher/new host path/family/full-host gate is justified. | Use five host IDs across four concurrent bundles, four mutations, exact Go RED/GREEN, mandatory DTR/runtime roots, curated `groups` once and one Android pair. Run independent Flutter files with concurrency 4 wherever supported. |
| 2026-08-12 | Independent TDD review | Architecture counterexamples, bootstrap reachability, selector conjunction, relay semantics, source-current limits, UI route, literal paths/commands and gate economy | Review rejected the initial writable-event scope and the legacy group-inbox premise. The bounded protected-custody + atomic-bootstrap + read-only-authority split closes those findings without v115, a new scheduler or a general group shell. | `PREREQUISITE_BLOCKED / CONTRACT_READY`; only Plan 362's clean closure and final shared-API/Graphify revalidation remain. |
| 2026-08-13 | Final Plan-362 closure and successor revalidation | Plan-362 source/receipt closure `051e26d5aefca8dc2f89d8d8c6d83113187c9ed5`, terminal audit-hygiene closure `17e90bfcef5b74a7f4055225403f8cdf297f7bd1`; committed/current Graphify `4bf3025ee64828d0` (72,428 nodes / 106,174 edges); DB v114 floor, linked-installation authority, protected `AckCustodyKind`/`AckOrExpiryInboxStore`, direct survivor authority and restricted runtime seams; live curated inventories | Plan 362 changes only the direct media adopter and preserves the group bootstrap/custody boundaries assumed here. The post-commit review query is anchored/current. Host `1to1` discovers 126 paths; the canonical `GROUP_TESTS` array contains 244 unique Flutter paths plus its incumbent registered Go bridge tail. No Plan-363 source or test is authored. | Prerequisite satisfied. Mark `EXECUTION_READY`, pin the exact audit-hygiene SHA/fingerprint, retain the reviewed c4-focused/serial-curated cadence, and do not refresh Graphify again until Plan 363 has a coherent code change. |

## Execution Progress

| Time | Step | Evidence | Result / next action |
|---|---|---|---|
| 2026-08-12 | Planning and independent review | Anchored Graphify planning/review queries plus targeted source verification; active Plan-362 worktree | Contract ready for its blocked state. After Plan 362 closes, pin its clean audit SHA and already-refreshed committed graph, revalidate the exact shared APIs/counts once without refreshing, then author the four semantic RED bundles and exact Go REDs. |
| 2026-08-13 | Prerequisite unblock | Clean Plan-362 audit-hygiene closure `17e90bfcef5b74a7f4055225403f8cdf297f7bd1`; source/receipt closure `051e26d5aefca8dc2f89d8d8c6d83113187c9ed5`; current anchored Graphify `4bf3025ee64828d0`; direct/linked/protected-custody API and gate-inventory verification | `EXECUTION_READY`. No Graphify refresh and no Plan-363 acceptance gate were required for the docs-only unblock. First implementation action is the literal clean-tree/ancestry preflight, then the four semantic RED bundles and exact Go REDs. |
| 2026-08-13 | Production implementation | Selected-group SELF verification over the existing dual-signed QR; atomic legacy+linked roster/bootstrap intent; deterministic secure-key staging plus atomic group/member/key materialization; strict group-bootstrap/group-authority custody in Dart, node and relay; prepared physical-recipient authority for device/member/role/removal/dissolve/key transitions; prerequisite-waiting replay; linked restricted runtime and read-only UI | Code-complete on the reviewed schema-free boundary. Ordinary QR parsing and all-legacy group behavior remain incumbent; linked group content, media, history and activation remain unreachable. |
| 2026-08-13 | Causal and focused proof | Four independent source mutations each re-red their owning Plan-363 row and were reverted. The final 31-file selector-on Flutter command ran at concurrency 4 and closed all five named rows plus preservation sentinels at `+9`, with every required ID observed and zero skips. Exact node `TestTC363GroupProtectedCustodyKinds` and relay `TestRelayNotificationClosure_GroupProtectedCustodyKinds` passed. | Atomicity, exact kind/target validation, generic-push refusal, authority convergence, restricted startup and B1b runner discovery are host-verified. |
| 2026-08-13 | Gates and hygiene | Discovery and relay-rollout shell contracts PASS; DTR-18 c4 `+5`; `runtime-roots` PASS; final once-only curated `groups` gate `+4119` plus bridge/node/relay/toolchain tails PASS. The first loaded groups run reproduced the pre-implementation background storage deadline flake; its contract-authorized test-only scale was tuned `8 -> 16`, the exact test passed, and the complete groups gate then passed. Analyzer reports no issues; Dart/Go format, baseline/unstaged/staged diff checks and mutation-marker scan are clean. | Required host acceptance is green. No completeness, `1to1`, core/feature/full `host-all`, performance, SQLCipher, iOS or extra device gate was run. |
| 2026-08-13 | Availability-bounded B1b | Live matrix: physical Pixel 6 `21071FDF600CSC` plus Android emulator `emulator-5554`. Runner discovery selected only B1b. The real journey produced the linked QR, created the ordinary-primary group, authored the bootstrap and retained its durable row, but the deployed relay rejected every attempt to store the additive protected bootstrap kind with `INBOX_ERROR`; both roles then timed out waiting for custody and the linked repository correctly remained empty. | `LIVE_DEPLOYMENT_BLOCKED`: targets were available, so this is not N/A. Do not downgrade to generic group storage. Deploy the Plan-363 node/relay kind allowlists before repeating B1b or enabling authoring; release eligibility remains false. |
| 2026-08-13 | Graph and closure record | One incremental architecture refresh processed 66 changed code files and closed at 72,778 nodes / 106,641 edges. Exact-anchor review over `handleProtectedGroupAuthority` and `authorLinkedGroupBootstrap` is current at fingerprint `2044b6ea0d86f131`; index, status and GAP-N01 coverage record the same bounded result. | `IMPLEMENTED / HOST_VERIFIED / LIVE_DEPLOYMENT_BLOCKED / DEFAULT-OFF / NOT RELEASE-ELIGIBLE`. No activation, writable group content/media, UX-013 or GAP-N01 closure claim. |

## Problem And Source-Backed Evidence

- Plan 360 creates a distinct linked transport credential and a dual-signed QR, while Plan 361/362 provide restricted direct-event/blob infrastructure. None creates local group/member/key state on a fresh linked installation.
- `announceRestoredDeviceToGroups` enumerates local groups only. The retired hydration wrapper deliberately does not acquire missing group config, membership or keys. The existing B1b harness calls `_importGroupShellForB1b`, so it cannot certify a production fresh-install route.
- `GroupMember.activeDevicesWithLegacyFallback` already models physical recipient transports. The group-scoped bootstrap must preserve the logical account member while adding its linked physical device; it must not create a second logical member.
- The incumbent pending-sibling Verify path admits the device, reopens/drains current-key distribution and deletes the pending row. That can send key traffic before the full bootstrap is durably owned and leaves no retry intent after ambiguous custody.
- The ordinary invite sender is live-first and falls back to generic inbox storage. Neither path returns the exact `ack_or_expiry_v1 stored|duplicate` proof required before sender authority may retire.
- Fresh invite materialization currently writes group, members and key sequentially and hard-codes `myRole: member`. A crash can leave partial authority, and an admin's linked installation can silently lose its role.
- The legacy group inbox is one aggregate row/ACL with no per-recipient ACK contract. Duplicate stores merge recipient ACLs and capacity may evict an older row, so it cannot prove that physical recipient A's completion leaves B's obligation durable.
- The protected P2P lane already provides per-recipient non-destructive store, retrieve, local stage and exact ACK. Adding strict group kinds/parser rules reuses this mechanism; it does not require a new action, backend, table, scheduler, wire field or native command.
- `pending_group_broadcasts` already persists exact signed text, a stable source ID and frozen recipients without an FK. `group_pending_key_distributions` already persists current-key distribution intent. They can own exact protected bootstrap/authority retries without v115.
- The linked startup path deliberately omits generic group recovery, and a no-contact linked identity falls into QR/FTE surfaces with no group home. A production bootstrap would remain inert without one narrow read-only group status/list route and exact cold/resume recovery ordering.
- Group control traffic must keep the logical account as actor while the outer protected envelope uses the current transport credential. Substituting the account key/peer for the physical transport breaks relay authentication; substituting the transport for the actor creates a second logical member.
- A bootstrap snapshot is authenticated and fresh at issuance, but an absent receiver has no oracle for the sender's later state. Plan 363 therefore converges signed membership/config/key authority and exposes only read-only group state. Writable discussion, admin announcement and reaction authoring wait for Plan 364's event-vs-authority races.

Expected production surface, subject to final Plan-362 revalidation:

- the existing Plan-360 direct linked QR validator/producer, a strict group-scoped SELF-bootstrap parser/entry in `GroupInfoWired`, pending sibling admission, and no contact/direct-binding mutation
- the existing pending sibling, pending group broadcast and pending key-distribution repositories/helpers, with the smallest transaction-capable group repository interfaces for authoring and materialization
- the existing group invite package/auth crypto reused under a distinct `linked_device_bootstrap_v1` purpose; ordinary group invite behavior remains byte-identical
- `AckCustodyKind`, P2P service/coordinator typed routing, `go-mknoon/node/inbox.go` and `go-relay-server/ack_custody.go`, with additive `group_bootstrap_v1` and `group_authority_v1` kinds only
- the incumbent add/role/remove/dissolve/key-update/device-announce authority producers and receivers through one narrow protected group-authority adapter; no group content event adapter
- production bootstrap, startup router, application cold/resume/pause owners, and one restricted linked read-only group status/list surface; no group topic subscription in this foundation
- the existing B1b runner and `group_multi_device_real_harness.dart`; no new runner, APK, camera-tap dependency or third device

Stop and re-review before adding v115, a parallel group outbox, per-target ACK rows, a target hash, a general discovery/history sync service, a second group selector, a new relay action/field/backend, a Dart/native bridge command, writable group content, group media/voice/private, feed/posts/contact runtime, push/provider wake, or release activation.

## Graph Grounding Snapshot

- Graph: `graphify-arch`. Both original planning/review queries were anchored against fingerprint `488091ffcb7bae21`; that remains historical planning context only.
- Final unblock: Plan-362 source/receipt closure `051e26d5aefca8dc2f89d8d8c6d83113187c9ed5` carries the single final incremental refresh at fingerprint `4bf3025ee64828d0` (72,428 nodes / 106,174 edges); docs-only audit-hygiene closure `17e90bfcef5b74a7f4055225403f8cdf297f7bd1` reconciles the terminal plan and coverage state without changing graph bytes. The post-commit successor query was anchored/current; direct target-survivor authority remains v114-persisted, linked role authority remains fail-closed, and the protected custody API remains additive. Raw source verification found no incompatible group-boundary change.
- Planning query: `python3 graphify-arch/tdd_context.py query "Plan 363 GAP-N01 group and announcement linked-device fanout after Plan 362 direct media fanout: sendGroupMessage sendAnnouncement group pubsub reliable inbox custody group multi-device sibling roster device keys ACK retry receive ordering and media blobs" --profile tdd --budget 700`.
- Review query: `python3 graphify-arch/tdd_context.py query "Review Plan 363 linked-group self-bootstrap and blob-free discussion announcement reaction convergence for production reachability, trust boundaries, custody ordering, retry durability, linked runtime, missing tests and overengineering; anchors send_group_invite_use_case.dart send_group_message_use_case.dart drain_group_offline_inbox_use_case.dart run_b1b_sibling_device_convergence.dart" --profile review --budget 800`.
- Final unblock completed without refresh: the exact baseline/fingerprint/counts are pinned above and the already-refreshed graph plus Plan-362 target/auth/runtime APIs were revalidated once. Plan 363 performs one incremental refresh only after its coherent code change.

## Scope Contract

### Prerequisite, selectors and rollout authority

- Author RED only from `17e90bfcef5b74a7f4055225403f8cdf297f7bd1` or a descendant whose intervening files are this Plan-363 artifact, `00-INDEX.md` and `STATUS.md`, after the literal preflight below. Plan 362 is code-complete, post-execution audited and clean.
- Add no new selector. Producing the QR on the linked installation and receiving bootstrap there require active persisted linked authority; the ordinary primary's selected-group scan/Verify requires both existing `MKNOON_ENABLE_DIRECT_LINKED_DEVICES=true` and `MKNOON_ENABLE_MULTI_DEVICE_SYNC=true` authorities but does not require a local copy of the remote credential. Mixed-selector, missing linked receiver credential, linked-role scanner, missing own membership and disabled cases are all-zero before crypto, DB or network.
- The scanner is available only on an ordinary-primary installation for its current own membership. An active linked secondary may display its QR on the restricted linked surface but cannot scan, stage or Verify its own credential.
- Once exact linked group device authority or protected custody exists, its bootstrap/authority retry, receive and terminal drain is state-driven and continues after either selector rolls back. Selector rollback cannot demote to generic invite/group inbox or erase persisted authority.
- This is controlled upgraded-installation code closure. It does not negotiate remote capability, activate cohorts, close UX-013/GAP-N01, or promise old-client interoperability. Relay-first deployment of the additive strict kind allowlists precedes any future activation.

### Group-scoped self-bootstrap authoring

- Reuse the exact Plan-360 dual-signed QR document, purpose and domain. Because the ordinary parser deliberately returns `selfScan` early, add a group-entry SELF verifier that consumes the same QR bytes and performs full structure, account/device key, dual-signature and age/skew validation. Do not add a second QR format or producer. Require distinct linked transport/device and exact installation ML-KEM; crossed account/key/device/transport/signature/time inputs refuse.
- Keep the ordinary contact/direct QR parser unchanged: a self scan remains `selfScan`, creates no contact and writes no direct binding. The selected-group path keeps the fully verified QR document/tuple in memory through explicit confirm; it does not pre-stage v85. Crash/cancel before the atomic authoring transaction leaves zero and requires a rescan.
- Derive `defaultGroupWelcomeKeyPackageIdForDevice(deviceId)` and use the QR ML-KEM public key as the existing key-package public material. Do not add storage for values derivable from the authenticated QR.
- Confirm under the incumbent group membership lock. Re-read the current nondissolved group, local self member/role, latest key and both selector authorities; compare the in-memory authenticated target tuple again. The ordinary primary need not own the remote installation's persisted credential; that credential is requalified by the linked receiver. A pre-existing ordinary `device_announce` v85 row is never proof of a QR scan: an exact conflict refuses and requires rescan. Already dissolved, self-removed, ambiguous or drifted state refuses before candidate persistence or network.
- If the self member has no explicit devices, retain its incumbent legacy device identity and append the linked device. Adding only the linked device would make the explicit roster authoritative and silently drop the primary. Existing exact linked identity is idempotent; a conflicting device/transport/key tuple refuses.
- Build a distinct primary-account-signed/encrypted `linked_device_bootstrap_v1` envelope over that already-authenticated tuple outside the SQL write transaction. Factor `DatabaseExecutor` bodies beneath the incumbent pending-sibling and pending-broadcast wrappers, then in one narrow transaction re-read and compare every input, insert/compare the exact `PendingSiblingDevice`, persist the exact legacy+linked roster and insert the exact protected bootstrap outbox, or commit nothing. The row stores the immutable bootstrap envelope in `sys_text`, the linked transport in the outer pending-recipient list and a stable source/bootstrap ID; after commit v85 is only retained retry intent hidden by the active roster, not QR-proof authority. Suppress its generic Verify/delete/key-drain route. No QR proof column or v115 is needed.
- Suppress the incumbent sibling-admission current-key reopen/drain for this path. The bootstrap package is the first group-key path and includes the current config, exact members/self role and current key encrypted to the linked installation's ML-KEM key.
- Keep `PendingSiblingDevice` as durable bootstrap intent after Verify. Hide it from `GroupInfoWired` once its exact linked device is active so the user is not prompted twice; the protected recovery runner still loads it. Reject remains a pre-admission operation only.
- Store to the linked physical transport through `AckOrExpiryInboxStore` with `AckCustodyKind.groupBootstrapV1`; this protected lane is the Plan-363 delivery path, with no racing live/group-topic send. Only exact `stored|duplicate` plus `ack_or_expiry_v1` may atomically exact-compare and delete both the bootstrap outbox and pending intent in one SQL transaction. A failure at either delete leaves both owners intact. Generic `OK`, missing strict capability, full, false, throw or ambiguous response retains exact bytes and returns retryable—not success.
- Retry opens the exact persisted envelope and target before selector/QR/group crypto; it never re-mints against a newer roster/key. A later explicit replacement requires a new bootstrap ID under the group lock. Pending bootstrap is also an outbound readiness barrier: no protected group authority is stored to that physical target until bootstrap custody is accepted and the paired owners close atomically.

### Protected group custody and durable authority

- Extend the existing protected action with two kinds only: `group_bootstrap_v1` and `group_authority_v1`. Update Dart, node and relay kind allowlists/parsers; keep `store_custody_v1`, `retrieve_custody_pending_v1`, `ack_custody_v1`, request fields, Redis backend, bridge command and native bindings unchanged.
- Use one kind-aware protected-envelope dedupe parser for admission, memory/Redis duplicate scans and promotion/reconciliation. Its key includes the custody kind namespace and logical bootstrap/transition identity, and every call also binds the request's exact `toPeerID`; bootstrap and authority IDs cannot collide. The relay validates only the exact clear outer type/version/ID, authenticated sender transport, target and allowed kind/recipient projection—it never claims to inspect encrypted logical authority. For bootstrap, authenticated outer sender must equal the logical primary account; a linked transport cannot author it. After local staging, the typed receiver verifies the signed/encrypted logical self or actor, group, bootstrap/transition ID, purpose/device tuple and immutable physical ACL. Unknown kinds, extra/missing keys, malformed IDs, sender/target mismatch and content-message/reaction kinds refuse.
- Allowed authority transitions are only those required to keep the later authoring boundary trustworthy: device announce, member add/config, member role change, admin-authored member removal, group dissolve and group key update. Voluntary self-removal remains deferred to Plan 364 because its incumbent exit-intent cleanup is a separate terminal owner. Discussion, announcement content, reactions, media, history and generic pending-system kinds are ineligible in Plan 363.
- The relay continues to own one protected row per physical recipient. The same signed source ID may be stored to A and B; duplicate is exact per recipient; A's ACK/expiry cannot remove, uncharge or mutate B. Capacity remains non-destructive, and rejected-full cannot evict an older protected row.
- Reuse `pending_group_broadcasts` as exact signed-wire authority. The immutable signed envelope freezes its complete sorted active physical ACL (legacy fallback included, only current sender transport excluded), while the existing outer `recipient_peer_ids` is the exact mutable survivor set. Each strict `stored|duplicate` receipt removes only that physical target; a crash before the update safely replays it as `duplicate`; roster changes add nobody; zero survivors retires the row. No accepted-target ledger is needed.
- Per-device encrypted authority such as group-key update uses one exact incumbent pending-broadcast row per physical target with a deterministic target-qualified row and delivery `source_message_id`: a canonical length-prefixed encoding of kind + common signed transition ID + recipient transport. The signed inner transition ID remains common, satisfying v86's unique `(group_id, source_message_id)` without a new column or target hash. Existing `group_pending_key_distributions` remains the latest-key intent owner; it may produce those exact rows only after requalifying current group/member/device authority under lock. It finalizes only after every required current target has exact protected custody.
- Every authority producer freezes the complete pre-transition physical ACL and persists a signed prepared outbox before the local mutation; after the local commit it activates/drains those same bytes through protected per-target custody and retains exact survivors on partial failure. Admin removal therefore includes every removed member device, and a crash between local deletion and activation cannot lose the prepared authority. Historical/null pending rows keep their incumbent behavior; only explicit Plan-363 protected kinds use this ordering. There is no Plan-363 pubsub/live authority send.
- Logical membership/config transitions remain signed by the account authority. The protected outer envelope is signed/attributed by the actual current transport credential. Legacy primary equality remains valid; linked transport/account inequality is required and tested. A linked installation may emit only its existing signed `device_announce` after bootstrap; it cannot author membership, role, dissolve or key transitions in this plan. Other members still apply the incumbent explicit trust decision—no fleet-wide auto-admission.
- Sender-side minting refuses dissolved/self-removed authority under lock. A queued bootstrap is authenticated only as fresh at issuance; the receiver does not invent a remote-current oracle. If a later signed terminal/role/key transition exists, protected authority replay converges it before any future writable surface. Do not invent a device-revoke transition: `device_announce` remains the only linked-authored device control, and explicit trust remains incumbent.
- A self-invalidating terminal transition cannot depend on the ordinary pending-broadcast runner after local state changes. Dissolve first persists its exact prepared signed authority and obtains protected custody for every frozen physical survivor while the preterminal authority is still valid; only then may the same serialized owner commit terminal local state and retire the prepared row. Strict-store refusal retains the prepared transition and leaves local authority unchanged. Nonterminal controls retain normal survivor retry.

### Receiver atomicity, ordering and reauthorization

- The P2P coordinator stages every protected bootstrap/authority envelope locally before calling its typed group handler and ACKs the relay only after the handler reports durable applied/duplicate/terminal rejection. Transient missing-bootstrap/key/lock/DB failures retain the local row and relay custody.
- Bootstrap receive verifies outer ordinary-primary sender equals the inner logical account, the primary account signature over the authenticated target tuple, exact local linked transport/device/ML-KEM tuple, envelope purpose and the current local linked credential. QR dual signatures/freshness were consumed at scan and are not persisted or reverified at receive; delayed custody validates the bootstrap envelope's own issued-at/expiry contract rather than incorrectly reapplying the QR's scan TTL. It creates no contact/direct binding and never accepts an ordinary invite as a self-bootstrap.
- Add one narrow `commitLinkedGroupBootstrap(group, members, key)` repository owner under the group lock, following the incumbent accepted-reentry choreography for external key material: decrypt/build outside SQL; write to a stable bootstrap-ID-qualified owned secure-store address; then one SQL transaction CASes authority and inserts the group, exact members/devices and key row referencing that address. Exact hydrated read-back precedes handler success/relay ACK. Pre-commit secure-write or SQL-refusal failure exposes no SQL authority and best-effort purges the deterministic staging orphan. A crash/readback failure after the SQL commit may retain the complete matching authoritative projection, but never a partial one; it sends no ACK, and exact replay hydrates that projection as duplicate before ACK. Derive `myRole` from the accepted self member and skip push/NSE/topic mirrors, join timeline, notification, avatar/media download, history request and contact mutation.
- Exact replay is idempotent. A fully matching existing projection returns duplicate; partial state from no owned transition is repaired only when every existing fact is an exact subset of the same signed bootstrap; crossed group/member/role/key authority refuses rather than overwrites. Every failure leaves either no authoritative SQL projection plus a deterministic staging cleanup owner, or one complete exact authoritative projection that replay can read back—never partial authority.
- Authority arriving before bootstrap remains locally staged and relay-unacked in an explicit prerequisite-waiting state which neither increments the generic replay-attempt counter nor quarantines at ten attempts. After bootstrap commits, apply staged protected authority in signed order under the incumbent membership mutation lock, then ACK its exact relay entry; ACK failure retains terminal local evidence for exact retry. Bootstrap-first and authority-first both converge exactly once after arbitrarily many waiting drains. Do not subscribe to the group topic or admit user content before Plan 364.
- Re-read current local group/member/device authority inside every durable authority apply transaction. Role/removal/dissolve/key transition first blocks or terminalizes a stale later transition; apply first commits once and the later authority transition then wins. Duplicate live plus protected replay yields one canonical state and no duplicate notification/timeline.
- A bootstrap stored before source dissolve may materialize and then immediately apply the signed dissolve on late recovery, leaving a terminal read-only shell. Plan 363 does not claim receive-time source-current validation beyond signed freshness-at-issue and subsequent authority convergence.

### Restricted runtime and production UI

- Extend the linked restricted runtime only with typed protected bootstrap/authority retrieve-stage-apply-ACK, exact pending bootstrap/authority/key-distribution retry, and a read-only linked group status/list projection.
- Cold/resume order is strict: direct P2P protected listener/retrieve -> atomic bootstrap materialization -> protected authority replay/drain -> refresh the read-only linked group list. Pause stops/flushes only those exact owners. Cold restart does not join group topics; discovery, hydration, history sync and user-content receive remain deferred.
- Do not consume the deferred-runtime one-shot latch while no identity exists: return deferred/false so it can rearm. After `LinkedDeviceSetupWired` durably commits the active linked credential, one setup-success callback starts the restricted runtime. `StartupRouter` checks ACTIVE linked authority before contact-count/FTE routing and exposes QR + read-only group status; a fresh linked/no-contact installation never falls into generic FTE or generic group startup.
- The active linked/no-contact route exposes its existing account QR plus the narrow group status/list. Before bootstrap it shows waiting/empty state; after materialization it refreshes without restarting generic services. It does not reuse Feed/Orbit or expose `GroupConversationWired`, composer, announcement editor, media/voice/private controls or group settings.
- Generic `startLiveServices`, group cursor/history drain, broad group listener/rejoin recovery, invite discovery, contact/key repair, pending historical system broadcast runner, push/provider/wake, posts/feed and media owners remain zero on the linked role. Primary startup and existing ordinary group UI remain byte-identical.
- Committed exact Plan-363 rows drain after selector rollback, but selector-off cannot start a new QR/bootstrap. No writable group-content capability becomes reachable until Plan 364.

### Explicit exclusions and successor boundary

- Plan 363 does not send or receive user-authored discussion text, admin announcements, reaction ADD/REMOVE, group media/voice/private, membership authoring from linked, history/no-intent content, avatars, group creation, generic invites, contact hydration or sibling discovery.
- Plan 364 may enable blob-free discussion/announcement/reaction authoring only after pinning this plan's authority APIs and proving event-vs-role/removal/dissolve/key ordering. Plan 365 owns group blob/media/voice fanout and per-final-recipient blob lifetime.
- Activation, capability negotiation, mixed-version rollout, relay deployment telemetry, hard remote recall and GAP-N01/UX-013 release closure remain later work.

## TDD Contract - Necessary Tests Only

| ID | Existing causal owners | Compile-clean RED / required GREEN | Representative mutation | Baseline expectation |
|---|---|---|---|---|
| `TC-363-01a` | `direct_linked_device_addressing_foundation_test.dart`; `manage_pending_sibling_device_test.dart`; `admit_sibling_device_use_case_test.dart`; `group_info_wired_test.dart`; `group_pending_broadcast_repository_test.dart`; `pending_sibling_devices_db_helpers_test.dart`; `groups_db_helpers_test.dart` | The same Plan-360 QR bytes remain ordinary-parser `selfScan`/no mutation yet pass the selected-group verifier only after full dual-signature/time checks; tampered/expired inputs refuse, while the ordinary primary needs no local copy of the remote credential. Scan-to-precommit crash leaves zero; an announce-seeded v85 row cannot bootstrap. Confirm derives key-package material, preserves legacy+linked devices, suppresses generic Verify/key drain, and atomically commits v85 intent + roster + exact bootstrap outbox while hiding intent. Mixed selectors, linked scanner, drift and injected insert failure are all-zero. | Mutation 1: omit the legacy-primary device when the first explicit linked device is saved -> roster assertion red. | Semantic RED before production wiring. |
| `TC-363-01b` | `send_group_invite_use_case_test.dart`; `handle_incoming_group_invite_use_case_test.dart`; `group_invite_listener_test.dart`; `group_repository_impl_test.dart`; `p2p_service_inbox_ack_ordering_test.dart`; `p2p_service_impl_test.dart` | Exact persisted bootstrap bytes use protected custody only and clear outbox+intent atomically only on strict `stored|duplicate`; failure of either delete retains both. Restart retries exact bytes with selectors/crypto unavailable. Typed receive stages before ACK, uses deterministic secure-key staging plus one authoritative SQL commit/read-back, and preserves exact role. Secure-write/SQL-refusal leaves no SQL authority; post-commit crash/readback failure may leave the complete matching projection but no ACK, and replay hydrates it as duplicate. No failure exposes partial authority. Conflicting authority and ordinary invite purpose refuse. | Mutations 2-3: (2) replace the staged atomic materializer with sequential visible group/member/key writes and hard-code `member`; (3) clear one bootstrap owner after generic/ambiguous store success. The crash/role and custody-negative assertions red independently. | Semantic RED before strict adapter/materializer. |
| `TC-363-02a` | `group_pending_broadcast_runner_test.dart`; `group_pending_broadcast_repository_test.dart`; `group_pending_key_distribution_repository_impl_test.dart`; `add_group_member_use_case_test.dart`; `update_group_member_role_use_case_test.dart`; `remove_group_member_use_case_test.dart`; `group_info_wired_test.dart`; `dissolve_group_use_case_test.dart`; `rotate_and_distribute_group_key_use_case_test.dart`; `group_key_update_listener_test.dart`; `group_message_listener_test.dart`; both restored-device announce tests | Parameterized authority controls freeze the pre-transition physical ACL, persist prepared bytes before mutation/network, preserve logical actor/transport signer split, require strict receipts and retry exact target-qualified rows. Admin removal includes the removed linked target and survives a crash between local commit/outbox activation. Pending bootstrap blocks outbound authority to that target. Inbound authority-before-bootstrap survives more than ten recovery drains without attempt/quarantine/relay ACK, then applies once and ACKs after bootstrap; ACK failure retries exactly. Dissolve gets all frozen strict custody before local terminal commit. Device announce is the only linked-authored control and remains explicitly trusted. | No additional mutation; the protected parser/recipient mutation is owned by `TC-363-03a`, while this row supplies direct behavior proof. | Semantic RED before protected authority adapter; thin adapters, not a transition cross-product. |
| `TC-363-03a` | `production_application_bootstrap_phase_contract_test.dart`; `startup_router_test.dart`; `startup_router_home_surface_test.dart`; `handle_app_resumed_group_recovery_test.dart`; `handle_app_resumed_group_inbox_retry_test.dart`; `handle_app_paused_group_test.dart` | No identity defers/rearms startup; an actual `LinkedDeviceSetupWired` successful submit (folded into the existing home-surface owner) invokes restricted runtime once; active linked authority routes before contacts/FTE. Cold/resume/pause follows protected bootstrap -> authority replay -> list refresh; flags-off drains committed work. Topic rejoin, Feed/Orbit/conversation/composer/media/history/broad group/push owners remain zero; primary path is unchanged. | Mutation 4: route `group_authority_v1` through aggregate `group_store` instead of protected per-target custody -> A-ACK/B-preservation and typed-runtime assertions red. | Semantic RED for runtime/UI; no new test path. |
| `TC-363-04a` | `invite_reliability_runner_contract_test.dart` and existing B1b runner/harness | Host contract requires two distinct live Android IDs, physical first/emulator second, both selectors, no defaults, and terminal pre-build rejection for missing/duplicate/reversed/non-Android IDs. Acceptance invokes production `setUpLinkedSecondaryInstallation`/`LinkedInstallationAuthority`, produces QR through the Plan-360 production builder/source, exchanges it via `AndroidAppSignalBroker`, starts with an empty group repository, bootstraps without shell import/topic join/content send, closes and reopens the same DB+secure store, then converges one protected dissolve into a terminal read-only shell. | No separate mutation; physical boundary is acceptance-only. | Host runner contract RED before registration; device journey after GREEN only. |

The table defines the complete four-mutation budget. Run those four only, one at a time, revert immediately, and rerun the mapped named causal selector. Do not create modality, platform or transition-kind mutation matrices.

Preservation is intentionally narrow:

- `TC-360-03a` keeps the ordinary direct QR self-scan/contact boundary unchanged.
- Existing ordinary device-bound group invite identity (`P269 accepts signed config-bound sender transport distinct from account identity`) remains unchanged.
- Existing account-signed `device_announce` continues to HOLD, not auto-admit, a sibling device through the curated `groups` lane.
- `GP-026` live+inbox dedupe, `P269` physical group-media ACL and current message/reaction behavior likewise run once through the curated `groups` lane; they are not duplicated in the focused batch.
- No migration/SQLCipher test exists because no schema or encrypted-DB boundary changes. No new Dart test path or host registration is expected.

## Implementation Sequence

1. **Unblock only after Plan 362 closes.** Replace every placeholder with the exact Plan-362 audit SHA, pin its committed Graphify fingerprint/counts, revalidate target/auth/runtime APIs and live group/host inventories, then commit Plan-363/index/status docs. Do not refresh Graphify at this docs-only boundary.
2. **Record all REDs before their owners.** Author `TC-363-01a`, `01b`, `02a`, `03a` and host `04a` compile-clean semantic REDs plus the exact node/relay REDs. Record failure cause and negative delta; no production workaround may precede its RED.
3. **Implement self-bootstrap durability.** Add the selected-group SELF verifier/primary UI entry over the exact existing QR bytes, exact pending intent semantics, derived key package, atomic roster+outbox transaction, strict bootstrap sender and deterministic secure-key-staging/SQL materializer. Suppress the incumbent key-distribution bypass.
4. **Extend the existing protected lane.** Add exactly the two strict kinds/parsers through Dart, node and relay. Keep action/backend/bridge/native shapes unchanged. Implement per-recipient parser/admission/duplicate/ACK behavior and typed local routing.
5. **Converge authority, not content.** Add one protected authority adapter to the incumbent pending broadcast/key-distribution owners and thinly route add/role/remove/dissolve/key/device-announce controls. Keep linked content authoring and generic group runtime unavailable.
6. **Wire restricted runtime and read-only route.** Enforce no-identity deferral, setup-success startup and cold/resume/pause protected-custody ordering; keep topic/content listeners stopped and expose only the linked QR/status list. Upgrade B1b to empty-repository QR bootstrap, preserve-storage reopen and exact authority recovery using physical Android + emulator topology.
7. **Mutation/review pass.** Run the four exact mutations serially, revert each, then one non-vacuous focused c4 proof, mandatory DTR c4, exact shell/runtime-root checks and curated `groups` once.
8. **Close honestly.** Run the one availability-bounded B1b journey, analyzer/format/Go/diff hygiene and one incremental Graphify refresh/review. Record receipts in this plan, index, status and the GAP coverage doc without claiming content authoring, activation or GAP closure.

## Gate Cadence - Necessary Tests Only

- Run independent multi-file Flutter test bundles with `--concurrency=4` wherever the runner supports it to speed feedback. Serialize only worktree mutations, script-owned curated gates and the shared-device journey.
- One final filtered c4 batch replaces whole-file GREEN reruns. It must prove every new host ID ran and none was skipped.
- Run the two exact protected-custody Go tests while developing; register the node test in the existing group Go regex and the relay test under the existing `TestRelayNotificationClosure_` prefix. The final curated `groups` gate then exercises those registrations once; do not add a new Go tail or broad Go package run.
- DTR's two files are mandatory and run together with concurrency 4 because production bootstrap/application-root consumers are in scope. Run `runtime-roots` once because a new production linked surface/root is intentional.
- Run `groups` once. Do not run completeness, `1to1`, core-host-all, feature-host-all, full host-all, performance, SQLCipher, iOS, a standalone group-media gate/suite/device scenario or a second device scenario; existing group-media sentinels inside the one curated `groups` lane remain allowed. Plan 362 owns the preceding full direct dependency-wave `host-all`; the next full host sweep belongs to the later group/content closure wave, not this foundation plan.

## Acceptance Commands

Run only after Plan 362 is audit-closed and the Plan-363 planning docs are committed:

```bash
set -euo pipefail
PLAN363_ACCEPTED_BASE='17e90bfcef5b74a7f4055225403f8cdf297f7bd1'
test "$PLAN363_ACCEPTED_BASE" = '17e90bfcef5b74a7f4055225403f8cdf297f7bd1'
test "$(git rev-parse "$PLAN363_ACCEPTED_BASE^{commit}")" = "$PLAN363_ACCEPTED_BASE"
git merge-base --is-ancestor "$PLAN363_ACCEPTED_BASE" HEAD
test -z "$(git status --porcelain)"
test -z "$(git diff --name-only "$PLAN363_ACCEPTED_BASE"..HEAD | \
  grep -Ev '^(Test-Flight-Improv/363-gap-n01-linked-group-self-bootstrap-authority-foundation-tdd-plan\.md|Test-Flight-Improv/00-INDEX\.md|STATUS\.md)$')"
```

Author and run the four compile-clean semantic RED/GREEN bundles. Every supported multi-file command uses concurrency 4:

```bash
# Self-QR, trust intent and atomic authoring.
flutter test --concurrency=4 \
  test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart \
  test/features/groups/application/manage_pending_sibling_device_test.dart \
  test/features/groups/application/admit_sibling_device_use_case_test.dart \
  test/features/groups/presentation/group_info_wired_test.dart \
  test/features/groups/domain/repositories/group_pending_broadcast_repository_test.dart \
  test/core/database/helpers/pending_sibling_devices_db_helpers_test.dart \
  test/core/database/helpers/groups_db_helpers_test.dart \
  --plain-name 'TC-363-01a group-scoped self bootstrap atomically owns exact roster and protected intent'

# Protected bootstrap send, typed receive and atomic materialization.
flutter test --concurrency=4 \
  test/features/groups/application/send_group_invite_use_case_test.dart \
  test/features/groups/application/handle_incoming_group_invite_use_case_test.dart \
  test/features/groups/application/group_invite_listener_test.dart \
  test/features/groups/domain/repositories/group_repository_impl_test.dart \
  test/core/services/p2p_service_inbox_ack_ordering_test.dart \
  test/core/services/p2p_service_impl_test.dart \
  --plain-name 'TC-363-01b protected self bootstrap commits atomically before exact relay ACK'

# Physical-recipient authority convergence.
flutter test --concurrency=4 \
  test/features/groups/application/group_pending_broadcast_runner_test.dart \
  test/features/groups/domain/repositories/group_pending_broadcast_repository_test.dart \
  test/features/groups/domain/repositories/group_pending_key_distribution_repository_impl_test.dart \
  test/features/groups/application/add_group_member_use_case_test.dart \
  test/features/groups/application/update_group_member_role_use_case_test.dart \
  test/features/groups/application/remove_group_member_use_case_test.dart \
  test/features/groups/presentation/group_info_wired_test.dart \
  test/features/groups/application/dissolve_group_use_case_test.dart \
  test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart \
  test/features/groups/application/group_key_update_listener_test.dart \
  test/features/groups/application/group_message_listener_test.dart \
  test/features/groups/application/announce_restored_device_use_case_test.dart \
  test/features/groups/application/announce_restored_device_on_startup_test.dart \
  --plain-name 'TC-363-02a protected group authority converges physical devices before content is enabled'

# Restricted runtime/read-only route plus B1b runner contract.
flutter test --concurrency=4 \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  test/features/identity/presentation/screens/startup_router_test.dart \
  test/features/identity/presentation/screens/startup_router_home_surface_test.dart \
  test/core/lifecycle/handle_app_resumed_group_recovery_test.dart \
  test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart \
  test/core/lifecycle/handle_app_paused_group_test.dart \
  test/integration/invite_reliability_runner_contract_test.dart \
  --name 'TC-363-03a|TC-363-04a'
```

Run the exact Go RED/GREEN after authoring both tests. Exact list and PASS checks make missing selectors fail closed:

```bash
set -euo pipefail
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node \
  -list '^TestTC363GroupProtectedCustodyKinds$' | \
  rg -x 'TestTC363GroupProtectedCustodyKinds')
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . \
  -list '^TestRelayNotificationClosure_GroupProtectedCustodyKinds$' | \
  rg -x 'TestRelayNotificationClosure_GroupProtectedCustodyKinds')

plan363_go_log="$(mktemp)"
trap 'rm -f "$plan363_go_log"' EXIT
(set -o pipefail; \
  (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node \
    -run '^TestTC363GroupProtectedCustodyKinds$' -count=1 -v) | \
  tee "$plan363_go_log")
grep -Eq '^--- PASS: TestTC363GroupProtectedCustodyKinds \(' "$plan363_go_log"
: > "$plan363_go_log"
(set -o pipefail; \
  (cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . \
    -run '^TestRelayNotificationClosure_GroupProtectedCustodyKinds$' \
    -count=1 -v) | tee "$plan363_go_log")
grep -Eq '^--- PASS: TestRelayNotificationClosure_GroupProtectedCustodyKinds \(' "$plan363_go_log"
rm -f "$plan363_go_log"
trap - EXIT
```

After all four mutations re-red and are reverted, run one final focused concurrent proof; do not rerun the files whole afterward:

```bash
plan363_flutter_log="$(mktemp)"
trap 'rm -f "$plan363_flutter_log"' EXIT
if ! (set -o pipefail; flutter test --concurrency=4 --reporter expanded \
  test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart \
  test/core/database/helpers/groups_db_helpers_test.dart \
  test/core/database/helpers/pending_sibling_devices_db_helpers_test.dart \
  test/core/services/p2p_service_inbox_ack_ordering_test.dart \
  test/core/services/p2p_service_impl_test.dart \
  test/features/groups/application/manage_pending_sibling_device_test.dart \
  test/features/groups/application/admit_sibling_device_use_case_test.dart \
  test/features/groups/presentation/group_info_wired_test.dart \
  test/features/groups/application/send_group_invite_use_case_test.dart \
  test/features/groups/application/handle_incoming_group_invite_use_case_test.dart \
  test/features/groups/application/group_invite_listener_test.dart \
  test/features/groups/domain/repositories/group_repository_impl_test.dart \
  test/features/groups/domain/repositories/group_pending_broadcast_repository_test.dart \
  test/features/groups/domain/repositories/group_pending_key_distribution_repository_impl_test.dart \
  test/features/groups/application/group_pending_broadcast_runner_test.dart \
  test/features/groups/application/add_group_member_use_case_test.dart \
  test/features/groups/application/update_group_member_role_use_case_test.dart \
  test/features/groups/application/remove_group_member_use_case_test.dart \
  test/features/groups/application/dissolve_group_use_case_test.dart \
  test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart \
  test/features/groups/application/group_key_update_listener_test.dart \
  test/features/groups/application/group_message_listener_test.dart \
  test/features/groups/application/announce_restored_device_use_case_test.dart \
  test/features/groups/application/announce_restored_device_on_startup_test.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  test/features/identity/presentation/screens/startup_router_test.dart \
  test/features/identity/presentation/screens/startup_router_home_surface_test.dart \
  test/core/lifecycle/handle_app_resumed_group_recovery_test.dart \
  test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart \
  test/core/lifecycle/handle_app_paused_group_test.dart \
  test/integration/invite_reliability_runner_contract_test.dart \
  --name 'TC-363-|TC-360-03a|P269 accepts signed config-bound sender transport distinct from account identity' | \
  tee "$plan363_flutter_log"); then
  exit 1
fi
for plan363_host_id in \
  TC-363-01a TC-363-01b TC-363-02a TC-363-03a TC-363-04a \
  TC-360-03a \
  'P269 accepts signed config-bound sender transport distinct from account identity'; do
  grep -Fq -- "$plan363_host_id" "$plan363_flutter_log" || exit 1
done
if grep -E \
  '~[0-9]+:.*(TC-363-|TC-360-03a|P269 accepts signed config-bound sender transport distinct from account identity)' \
  "$plan363_flutter_log" >/dev/null; then
  exit 1
fi
rm -f "$plan363_flutter_log"
trap - EXIT
```

Run mandatory DTR and the directly affected shell/curated gates once:

```bash
set -euo pipefail
flutter test --concurrency=4 \
  test/unit/dtr18_placement_closure_contract_test.dart \
  test/unit/dtr18_layering_relocation_contract_test.dart
bash scripts/test/reliability_simulation_discovery_contract_test.sh
bash scripts/test/relay_ack_custody_rollout_contract_test.sh
./scripts/run_test_gates.sh runtime-roots
./scripts/run_test_gates.sh groups
```

Extend `relay_ack_custody_rollout_contract_test.sh` to assert that the existing
group `go-mknoon ./bridge ./node` regex contains `TC363`; this makes permanent
node registration non-vacuous without a new tail. The `groups` gate then runs
that node selector and automatically discovers the relay test under
`^TestRelayNotificationClosure_`. It also owns unchanged `device_announce`,
`GP-026` and `P269` preservation files. Add B1b to
`requires_explicit_multi_device_ids()`; the already-required discovery shell
must prove discovery/registration, the required-ID placeholder and missing-env
exit 64 before Dart. `TC-363-04a` owns distinct/live/Android/physical-first
topology validation in the B1b runner itself; do not duplicate that parser in
the generic dispatcher. Do not add a standalone relay sweep or second groups
run.

Resolve the live matrix and run the existing B1b scenario exactly once with an explicit Android pair:

```bash
set -euo pipefail
flutter devices --machine
adb devices -l
PLAN363_PHYSICAL_ANDROID_ID='<USB_ANDROID_ID>'
PLAN363_EMULATOR_ANDROID_ID='<ANDROID_EMULATOR_ID>'
test "$PLAN363_PHYSICAL_ANDROID_ID" != '<USB_ANDROID_ID>'
test "$PLAN363_EMULATOR_ANDROID_ID" != '<ANDROID_EMULATOR_ID>'

RELIABILITY_MULTI_DEVICE_IDS="$PLAN363_PHYSICAL_ANDROID_ID,$PLAN363_EMULATOR_ANDROID_ID" \
  ./scripts/run_test_gates.sh reliability-sim group --list \
  --only integration_test/scripts/run_b1b_sibling_device_convergence.dart
RELIABILITY_MULTI_DEVICE_IDS="$PLAN363_PHYSICAL_ANDROID_ID,$PLAN363_EMULATOR_ANDROID_ID" \
  ./scripts/run_test_gates.sh reliability-sim group \
  --only integration_test/scripts/run_b1b_sibling_device_convergence.dart
```

The generic dispatcher rejects missing explicit IDs before Dart. The B1b runner itself must reject wrong ordering, duplicates and non-Android/unavailable IDs before build; pass both existing selectors to both roles; invoke the production `setUpLinkedSecondaryInstallation`/`LinkedInstallationAuthority` path; produce the QR through the production Plan-360 builder/source; exchange its JSON through `AndroidAppSignalBroker`; and remove every iOS default/comment. Its B1b path removes manual restored-identity transport setup, `_importGroupShellForB1b`, `callGroupJoinWithConfig`, device announce/topic drain and `sendGroupMessage`; it adds a non-destructive close/reopen seam which preserves the same encrypted DB and secure store, then verifies protected dissolve recovery. If the required pair is unavailable, record `N/A (target unavailable by project policy)`; do not substitute an iPhone, require a third device, wait for unavailable hardware or use camera taps.

Final static and Graphify hygiene:

```bash
set -euo pipefail
plan363_base_ref='17e90bfcef5b74a7f4055225403f8cdf297f7bd1'
flutter analyze
plan363_dart_list="$(mktemp)"
trap 'rm -f "$plan363_dart_list"' EXIT
{
  git diff --name-only --diff-filter=ACMR "$plan363_base_ref"...HEAD -- '*.dart'
  git diff --name-only --diff-filter=ACMR -- '*.dart'
  git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
  git ls-files --others --exclude-standard -- '*.dart'
} | sort -u > "$plan363_dart_list"
test ! -s "$plan363_dart_list" || \
  xargs dart format --output=none --set-exit-if-changed < "$plan363_dart_list"
rm -f "$plan363_dart_list"
trap - EXIT
test -z "$(gofmt -l \
  go-mknoon/node/inbox.go \
  go-mknoon/node/inbox_ack_custody_test.go \
  go-relay-server/ack_custody.go \
  go-relay-server/ack_custody_protocol_test.go)"
git diff --check "$plan363_base_ref"...HEAD
git diff --check
git diff --cached --check
./graphify-arch/refresh_arch_graph.sh --incremental
python3 graphify-arch/tdd_context.py query \
  "Review Plan 363 linked-group self-bootstrap and protected authority convergence: QR trust, atomic roster/outbox, atomic materialization, protected kinds, physical/logical signing, terminal authority, restricted runtime and B1b route" \
  --profile review --budget 800
git diff --check "$plan363_base_ref"...HEAD
git diff --check
git diff --cached --check
git status --short
```

## Risks, Stops, And Reversibility

- A generic inbox/live success is not protected custody. Any path that clears intent without exact `ack_or_expiry_v1 stored|duplicate` is a correctness defect.
- The bootstrap package is sensitive group/key authority. It must be encrypted to the exact linked installation and staged locally before relay ACK; logs/artifacts may contain only redacted IDs and hashes.
- Sender SQL transactions must not include bridge crypto or network. Candidate facts are built first, then requalified and committed atomically, then transported.
- One bootstrap snapshot cannot prove remote state forever. The plan deliberately keeps linked UI read-only and converges signed authority; it does not pretend to solve event-vs-authority ordering before Plan 364.
- Protected kinds are additive but old nodes/relays reject them. Keep deployment/authoring default-off and deploy reader/parser support before later activation; do not downgrade to aggregate group storage.
- Existing pending rows are the durable authority. Do not add an accepted-target ledger merely to optimize duplicate stores; exact duplicate receipts make full-list retry bounded and safe.
- If Plan 362 changes the linked role, target resolver, P2P coordinator staging or DB floor incompatibly; if the incumbent tables cannot atomically own exact bootstrap bytes; if group materialization cannot be one transaction; or if strict group parsers require a new wire action/native export, stop and re-plan before RED.

## Done Criteria

- [x] Plan 362 is cleanly implemented at source/receipt closure `051e26d5aefca8dc2f89d8d8c6d83113187c9ed5` and audit-hygiene closed at `17e90bfcef5b74a7f4055225403f8cdf297f7bd1`; current Graphify `4bf3025ee64828d0` (72,428 nodes / 106,174 edges), shared APIs and live inventories are revalidated, and plan/index/status move to `EXECUTION_READY` before RED.
- [x] An ordinary primary can scan the fresh linked installation's exact existing QR for one current group, with both selectors and no contact/direct-binding mutation; linked/self/crossed inputs refuse.
- [x] Verify preserves legacy+linked device authority and atomically owns exact protected bootstrap bytes plus durable intent before network; ambiguous custody cannot clear either owner.
- [x] Protected bootstrap and authority kinds bind exact physical sender/recipient and logical group/account authority through the existing action/backend; relay ACK/capacity/duplicate behavior is recipient-independent.
- [x] Fresh receiver materialization uses deterministic secure-key staging plus one authoritative SQL commit/read-back, preserves exact role, is idempotent and ACKs only afterward; authority-before/bootstrap-before/restart/terminal races converge without visible partial authority.
- [x] Membership/config/role/removal/dissolve/key/device authority converges through physical recipients while logical/transport signatures stay distinct; no user content becomes writable.
- [x] Restricted linked cold/resume/pause exposes only QR + read-only group status and exact bootstrap/authority recovery; generic group/feed/posts/contact/media/history/push owners remain zero and primary behavior is unchanged.
- [x] Four exact mutations re-red independently and are reverted. Independent multi-file tests use concurrency 4 wherever supported; final focused c4 proof is non-vacuous.
- [x] Exact node/relay protected-kind tests, mandatory DTR c4, discovery shell, runtime roots and one curated `groups` lane pass once. No migration/SQLCipher/completeness/1to1/core/feature/full-host/performance/extra-Go gate is run.
- [ ] The existing B1b journey proves empty linked group repo -> automated QR bootstrap -> atomic key/group materialization -> offline protected authority convergence on an available physical Android + emulator, or is recorded N/A exactly under project policy. `LIVE_DEPLOYMENT_BLOCKED`: both targets were available, but the deployed relay rejected the new protected kind with `INBOX_ERROR`; the durable bootstrap was retained and no unsafe fallback was taken.
- [x] Analyzer, changed-Dart format, Go format, three diff checks and one post-change Graphify refresh/review are clean; index/status/GAP coverage record the actual receipt while activation, writable group events, media, UX-013 and GAP-N01 remain open.

## Reviewer Findings

### Lens 1 - Production reachability and scope

- Review rejected an already-provisioned-only group slice because the only current fresh-device path imports a test shell. One explicit group-scoped self-bootstrap is required for production reachability.
- Review also rejected combining that bootstrap with writable discussion/announcement/reactions. The accepted boundary is read-only authority convergence; content authoring moves to Plan 364.

### Lens 2 - Durable authority and custody

- Aggregate group inbox cannot prove independent recipient ACK-or-expiry and is not reused for strict authority. Two additive kinds on the incumbent protected P2P lane are the smallest safe mechanism.
- Existing pending sibling, pending broadcast and pending key-distribution rows supply every required durable fact. No v115, second ledger, ACK state or target hash is justified.

### Lens 3 - Trust, atomicity and alternate paths

- The selected-group SELF verifier requires both existing selectors and fully validates the exact existing QR bytes; only QR production/linked receive requires the linked installation's persisted authority, while ordinary contact QR behavior remains unchanged.
- Roster+bootstrap-outbox authoring and group/member/key materialization each receive one narrow transaction. Incumbent early key distribution and sequential/hard-coded-role materialization are explicitly bypassed and causally tested.
- Logical account authority and physical transport authentication remain separate across bootstrap, control events and receipts.

### Lens 4 - Runtime and test economy

- One read-only group status/list makes the bootstrap observable without importing Feed/Orbit/conversation/media surfaces. Topic rejoin and all user-content receive remain excluded with discovery/history.
- Five host IDs across four concurrent bundles, four mutations, two exact Go tests, mandatory DTR/runtime roots, one curated group lane and one upgraded B1b scenario cover the distinct boundaries. Multi-file Flutter tests run concurrently at 4 wherever supported.

### Lens 5 - Claims and reversibility

- Fresh-at-issue bootstrap plus subsequent signed authority convergence is the honest claim. There is no invented receive-time source-current oracle, writable event safety, mixed-version activation or release claim.
- Selector rollback continues persisted recovery but cannot create new authority. Old protected-kind readers fail closed; no unsafe fallback is permitted.

## Arbiter Decision

`IMPLEMENTED / HOST_VERIFIED / LIVE_DEPLOYMENT_BLOCKED / DEFAULT-OFF / NOT
RELEASE-ELIGIBLE.` The bounded foundation is code-complete and its causal host,
Go, curated-gate, static and graph evidence is green. The available Android pair
proved production QR creation and durable bootstrap authoring, then the deployed
relay failed closed because it does not yet admit the additive protected kinds.
That deployment must be updated before B1b can close; generic group storage is
not an acceptable fallback. Writable discussion, announcements and reactions
remain Plan 364, group blobs remain Plan 365, and no activation or GAP-N01
closure is claimed.

## Handoff

- Current state: `IMPLEMENTED / HOST_VERIFIED / LIVE_DEPLOYMENT_BLOCKED / DEFAULT-OFF / NOT RELEASE-ELIGIBLE`; all required code and host acceptance are complete, and Graphify is current at `2044b6ea0d86f131` (72,778 nodes / 106,641 edges).
- Deployment action: deploy the additive `group_bootstrap_v1` and `group_authority_v1` node/relay allowlists, then rerun the single discovered B1b scenario on the physical Pixel 6 plus `emulator-5554`. Do not enable authoring before that proof passes.
- Receipt boundary: final focused c4 `+9`, 4/4 mutation re-reds reverted, exact node/relay PASS, DTR c4 `+5`, discovery/runtime-roots/contracts PASS, curated groups `+4119` plus all Go tails, analyzer/format/diff clean, and one incremental Graphify refresh/review.
- Safety disposition: the failed live store retained durable bootstrap authority, the linked repository stayed empty, and no generic-storage downgrade or activation was introduced.
- Successor work: Plan 364 owns blob-free group discussion/announcement/reaction authoring after authority convergence; Plan 365 owns group media/blob/voice; later plans own history/no-intent, activation, capability rollout and final GAP-N01/release closure.
