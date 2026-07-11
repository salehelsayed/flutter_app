# 236 - Group Received Media Forwarding

Status: IMPLEMENTED — host-green + device-proven (GMF-06D SQLCipher v99 + GMF-11 real-Go-bridge on emulator-5554, 2026-07-10)
Type: New Feature
Spec: free-text intent — forward incoming discussion-group image/video media to contacts or other discussion groups with destination-scoped encryption and no transport-semantic change
Classification: implemented / device-proven
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | group media viewer/wiring, `ShareTargetPickerWired`, share batch coordinator/tests, group send/listen/offline paths, group model/repository, bridge group helpers, Go bridge/node extra-field flow, migrations/gates, real-crypto integration fixture | Existing share fanout already reuploads per target and applies contact/group access policy. Group messages lack a forwarded marker and group source actions. A backward-compatible encrypted-inner bool needs DB v98 plus narrow Dart/Go-bridge plumbing, not a new libp2p protocol. | Start the pure source/destination policy RED; enforce v96/v97 predecessor versions as execution stop rules before v98 work. |
| 2026-07-10 | Planner | revised plan 228 owner-state/migration-registry contract, plan 232 v97 dependency, share coordinator group-destination persistence seams, migration/full-chain proofs | Group-destination attachments must persist explicit `MediaOwnerLane.group`. Migration 098 must extend the shared production create/upgrade registry introduced by plan 228, and its v97 predecessor fixture must retain every v96 owner/state/index artifact. | Add owner-persistence and complete-predecessor assertions before v98/bridge edits. |
| 2026-07-10 | Replanner (version rebase) | plan 235 audit disposition, this plan's migration/gate rows | Plan 235's counterexample audit allocated DB v98 to its `group_media_deletion_journal`; this plan's forwarded marker is rebased from v98 to v99 (`099_group_messages_is_forwarded`). Predecessor fixture becomes complete v98 (v96 owner/state/index artifacts plus plan 235's journal). | Execute only after v98 lands; all v99 gates below reflect the rebase. |
| 2026-07-10 | Counterexample Reviewer / Replanner | current committed Plan-235 closure/v98 registry; group source integrity, share target/upload ordering, picker retry, send/retry wrappers, listener membership buffer, offline history-gap repair, migration/device/gate scripts | The prerequisite warning is stale because Plan 235 and committed v98 are closed. Source hash and destination authority must be refreshed before upload; queued targets belong only to durable retry; multiple retry/replay seams need explicit marker coverage; owner persistence is already GREEN; migration and gate proofs need bounded correction. | Execute the corrected v99 contract below after the committed-HEAD preflight passes. |

## Problem And Evidence

- Behavior to improve: a user should be able to forward a selected incoming verified image/video from a `GroupType.chat` conversation to one or more contacts and writable discussion groups, optionally editing its caption.
- Impact: current group media can be viewed but cannot be redistributed inside Mknoon; users must leave the app or manually recreate a send.
- Confirmed reusable picker: `lib/features/share/presentation/screens/share_target_picker_wired.dart:142` loads contacts and writable groups, supports multi-selection, revalidates group eligibility before delivery, and composes an editable caption.
- Confirmed reusable fanout: `lib/features/share/application/share_batch_delivery_coordinator.dart:187` processes the source once and then creates/uploads a new attachment for every target. Contact delivery calls `uploadMedia` then `sendChatMessage`; group delivery resolves membership, derives `allowedPeers`, calls `uploadMedia`, then `sendGroupMessage`.
- Confirmed forwarding hazards: `GroupReceivedMediaActionsController` reloads owner/status/path but does not hash the current file, although `GroupMediaIntegrityPolicy.validateFileContentHash` is available. The share coordinator falls back to stale picker contact/group objects, performs upload before final send authorization, and lets a thrown target abort later targets.
- Security implication: existing coordinator behavior is the correct boundary — forward decrypted verified source bytes, then create new destination-scoped ciphertext/upload metadata. Reusing the source group's ciphertext, key/nonce, blob id, or allowed-peer list would be a confidentiality bug.
- Confirmed authorization boundary: `_isWritableGroupTarget` rejects archived/dissolved groups, missing membership/keys, and announcement targets for non-admins. This discussion-lane plan narrows that further to `GroupType.chat`; announcement publishing remains owned by the announcement plan.
- Confirmed schema gap: `lib/features/groups/domain/models/group_message.dart` has quote/media fields but no `isForwarded`; the `group_messages` table has no forwarded column.
- Confirmed local-owner prerequisite: revised plan 228 makes attachment owner mandatory because direct and group message IDs can collide. Every newly uploaded group-destination attachment in this flow must persist `MediaOwnerLane.group`; transport payloads must still omit that local field.
- Confirmed wire gap: `SendGroupMessageUseCase`, `bridge_group_helpers.dart`, `group_message_listener.dart`, and `DrainGroupOfflineInboxUseCase` carry quote/media data but no forwarded marker.
- Confirmed narrow Go boundary: `go-mknoon/node/pubsub.go` already preserves arbitrary encrypted payload extras when publishing and rebuilding a received event. `go-mknoon/bridge/bridge.go` parses a whitelist into group message options, so only the bridge parameter/option mapping needs the optional bool; node topic/routing/fanout/crypto algorithms do not.
- Existing real crypto evidence: `go-mknoon/node/pubsub_delivery_test.go::TestGK030PublishGroupMessagePreservesExtraFieldsInReceivedEvent` exercises encrypted two-node extra-field delivery; `integration_test/group_real_crypto_onboarding_test.dart` uses the real Go bridge and is already classified by the group reliability simulator.
- Missing coverage: no source Forward action, dispatch-time source hash verification, destination-lane filter, current contact/group/key/membership validation before upload, per-target exception isolation/re-encryption assertion, forwarded marker migration/default, reliable/fallback/re-drive preservation, membership-buffer/history-gap replay roundtrip, display marker, or real bridge mapping proof exists.
- Refuted finding: a new group publish primitive is not required. The current share coordinator already invokes the existing authorized `SendGroupMessageUseCase`; this plan supplies a typed forward intent and optional payload metadata only.
- Refuted review finding: Plan 236 is not currently prerequisite-blocked. Committed HEAD contains Plan 235's implemented closure, DB v98, migration 098, and one 098 entry in each production registry arm. The stronger committed-HEAD preflight below must remain true when execution starts.
- Unresolved finding: N/A. Migration 099 follows committed v96-v98, extends the shared production registry, and must not be renumbered or wired through duplicate callbacks.
- Affected production, test, migration, bridge, and gate files: group message model/DB mapping/send/listen/drain flows, new migration 099, group media action/picker adapters, share delivery intent/coordinator extensions, narrow Go bridge bool plumbing/tests, group real-crypto proof, full migration chain, and group gate registration.

## Scope Contract And Guard

In scope:
- Source: one selected incoming verified image/video in `GroupType.chat`; use its caption as the editable initial caption. Carry only stable `(groupId,messageId,attachmentId)` into the picker, then immediately before fanout reload the exact parent and group-owned row, resolve its canonical file, and require `GroupMediaIntegrityPolicy.validateFileContentHash` success against the current stored hash.
- Destinations: one or more contacts and writable `GroupType.chat` groups. Immediately before each upload, reload the target from its repository. A missing contact/group is failure, never stale-picker fallback. Require the current contact encryption key, or current group type/role/membership/key plus exact `allowedPeers`; `sendChatMessage`/`sendGroupMessage` still perform their own final authorization.
- Reuse the existing multi-select picker and `DefaultShareBatchDeliveryCoordinator` through a typed internal `GroupMediaForwardRequest`; do not route internal forwarding through the OS share intent.
- Read source bytes only after the dispatch-time reload/path/hash checks. For every destination, allocate a new attachment/message id and perform a new encrypted upload using that destination's current access policy. Persist every group-destination attachment with explicit `MediaOwnerLane.group`; contact-destination attachment ownership remains plan 232's `direct` contract.
- Isolate each target in its own exception boundary: one thrown target becomes a typed failed result and cannot abort later targets. Return existing sent/queued/failed results without turning partial success into all-success.
- Picker retry retains only failed targets. Sent targets never retry; queued targets are removed from picker selection because their durable stored message/background lane exclusively owns retry with the original message/logical-delivery identity.
- Add `GroupMessage.isForwarded` persisted by migration 099 as `group_messages.is_forwarded INTEGER NOT NULL DEFAULT 0 CHECK (is_forwarded IN (0,1))`.
- Carry optional `isForwarded: true` only inside the existing encrypted group-message payload. Absence, null, or a non-boolean legacy/unknown value decodes as `false`.
- Preserve the marker through outgoing pre-persist, `group:sendReliable`, fallback `group:publish`, `wireEnvelope`, encrypted offline replay plaintext, both durable re-drive callers, Go bridge mapping, live listener, persisted membership-buffer repair, ordinary offline drain, history-gap repair, repository mapping, restart/dedup, and discussion bubble rendering.
- Marker semantics are origin-minimizing: show “Forwarded” but never copy the original sender identity, source group id/name, source message id, or original encryption metadata into the new message.

Must preserve:
- Existing share batch per-target result and durable background behavior -> `test/features/share/application/share_batch_delivery_coordinator_test.dart`; `GREEN sentinel`.
- Existing failed-only picker retry and queued-target durable ownership -> `share_target_picker_wired_test.dart`; `GREEN sentinel` strengthened by TC-236-05.
- Group media hash/encryption validation -> named media tests in `send_group_message_use_case_test.dart`; `GREEN sentinel`.
- Announcement non-admin authorization and reader read-only behavior -> group send/wired sentinels.
- Legacy group messages decode/persist/render with `isForwarded == false` -> migration and live/offline compatibility rows.
- Existing Go encrypted extra-field delivery -> `TestGK030PublishGroupMessagePreservesExtraFieldsInReceivedEvent`; preservation/extension row.
- Plan 228 owner/local-state columns, exact indexes, replay preservation and production create/upgrade registry remain intact through v97, v98, and v99 -> TC-236-03O/06/06D.

Hard `Do not`:
- Do not add a pubsub topic, message type, outer routing field, new recipient/fanout rule, new retry/inbox protocol, or change group key distribution, membership authorization, relay, or libp2p delivery semantics.
- Do not modify `go-mknoon/node` production behavior; the node's existing encrypted-extra preservation is sufficient. Narrow `go-mknoon/bridge` JSON-to-options bool plumbing is allowed and must be covered.
- Do not reuse source ciphertext, key, nonce, upload id, storage locator, or `allowedPeers` for a destination.
- Do not omit, infer, or serialize attachment ownership: group destinations require local `MediaOwnerLane.group`, `unresolved` is invalid for new saves, and owner state never enters encrypted payloads.
- Do not forward pending, failed, quarantined, missing, expired, view-once-consumed, or protected media.
- Do not include `GroupType.announcement` or `GroupType.qa` targets; announcement forwarding/publishing belongs to its dedicated plan.
- Do not silently mark OS Save/Share, ordinary sends, retries, or imported inbound OS shares as forwarded.
- Do not propagate original-author identity, source-conversation/message/attachment IDs, source ciphertext/key/nonce/hash, source owner, or source access metadata into destination wire, replay, or retry maps.

Deferred / accepted difference:
- Contact-destination persistence/rendering of `messages.is_forwarded` is owned by plan 232 (`Test-Flight-Improv/232-1to1-received-media-forwarding-tdd-plan.md`); this plan proves that a group-origin request invokes that accepted contact lane.
- Announcement-origin/announcement-target forwarding is owned by plan 240 and may reuse migration 099 only after it preserves announcement author/admin rules.
- Multi-attachment album forwarding is deferred; the contract forwards the viewer-selected attachment and an editable caption to multiple destinations.
- Private/protected forwarding policy is owned by plans 234/238; until those land, only ordinary eligible media is supported.
- OS external Share remains plan 227/235 behavior and never creates the internal forwarded marker.

Dependencies:
- Plan 230 typed viewer action/callback contract and committed/implemented Plan 235 group received-media action policy/surface plus DB v98 journal.
- Plan 232 contact forwarded-marker contract for contact destinations.
- Ordered database prerequisites: plan 228 owns v96 plus the shared production create/upgrade registry, plan 232 owns v97, and committed Plan 235 owns v98 (`group_media_deletion_journal`); this plan exclusively owns v99. The v98 predecessor fixture must include v96 owner/viewer state and indexes, a direct `messages.is_forwarded=1` row, populated v98 journal rows/indexes, and non-default group-message quote/retry/transport/logical-delivery/backoff state plus all named group-message indexes. Evidence-gated private-media plans reserve no fixed version.
- Existing `ShareTargetPickerWired`, `DefaultShareBatchDeliveryCoordinator`, group send authorization, and Go encrypted-extra preservation.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-236-01 | Forward appears only for selected incoming verified ordinary media in `GroupType.chat`. | `test/features/groups/application/group_media_forward_policy_test.dart::GMF-01 only eligible incoming discussion media can forward` | host unit / table-driven source/group/attachment state plus abstract policy-allow fixture | HEAD compile RED: policy absent -> only the exact eligible row exposes Forward without requiring a concrete plan-238 lifecycle model | remove incoming/group-type/integrity/policy guard -> GMF-01 red | `flutter test test/features/groups/application/group_media_forward_policy_test.dart --plain-name 'GMF-01 only eligible incoming discussion media can forward'`; add file to `GROUP_TESTS` |
| TC-236-01R | After picker delay, dispatch reloads the exact parent and group-owned attachment, resolves the current file, and verifies its SHA-256 against the stored content hash before any target lookup or upload. | `test/features/groups/application/group_media_forward_policy_test.dart::GMF-01R dispatch reloads exact group source and verifies current file hash` | host application / mutable parent+owner-aware media repositories, real temp file/hash, upload and picker spies | HEAD causal RED: current Plan-235 action adapter checks metadata/existence only -> exact current bytes proceed; changed bytes/hash, wrong group/owner/id, missing parent/file, or ineligible state produce zero upload/delivery | trust viewer path/state, check existence only, skip `validateFileContentHash`, or accept an unresolved/direct collision -> GMF-01R red | `flutter test test/features/groups/application/group_media_forward_policy_test.dart --plain-name 'GMF-01R dispatch reloads exact group source and verifies current file hash'`; same new file in `GROUP_TESTS` |
| TC-236-02 | Forward opens the picker with contacts and writable discussion groups only, then reloads and revalidates every selected destination immediately before its upload. | `test/features/groups/presentation/group_media_forward_flow_test.dart::GMF-02 picker filters and revalidates current forwarding destinations before upload` | host widget/application / mutable contacts plus chat/announcement/qa/archived/dissolved groups, memberships and keys, upload spies | HEAD compile RED -> only contact/chat targets render; a missing contact never falls back to picker data; revoked contact key or group existence/type/role/membership/key fails before upload; current allowed peers reach upload | use `repo.get(...) ?? pickerTarget`, reuse broad share filter, validate only in `send*`, or upload with stale peers/key -> GMF-02 red | `flutter test test/features/groups/presentation/group_media_forward_flow_test.dart --plain-name 'GMF-02 picker filters and revalidates current forwarding destinations before upload'`; add file to `GROUP_TESTS` |
| TC-236-03 | Every qualified target receives a separately uploaded/re-encrypted attachment with a fresh id and destination-current access policy; destination wire/replay/retry maps contain no source provenance or crypto/owner metadata. | `test/features/share/application/share_batch_delivery_coordinator_test.dart::GMF-03 group origin forward reencrypts independently and keeps provenance local` | host integration / real verified temp source, raw upload/contact/group sender recorders, decoded wire/retry maps | HEAD RED: typed group-forward request/marker absent -> contact and group uploads have distinct blob/key/nonce/message identities and exact current recipients/allowed peers; among forward-source data only the edited caption and newly minted media plus marker are added to normal destination routing/sender fields | reuse blob/key/nonce/id/allowedPeers, serialize source ids/author/hash/owner/key, or derive upload policy from picker state -> GMF-03 red | `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart --plain-name 'GMF-03 group origin forward reencrypts independently and keeps provenance local'`; add existing suite to `GROUP_TESTS` |
| TC-236-03E | A thrown contact/group target becomes one failed result and later targets still execute in order; sent/queued results remain truthful. | `test/features/share/application/share_batch_delivery_coordinator_test.dart::GMF-03E target exceptions are isolated without aborting later forwards` | host application / first/middle throwing targets followed by sent/queued targets | HEAD causal RED: coordinator loop has no per-target catch -> complete ordered result list with one failure and later calls observed | move try/catch around the whole loop, abort after throw, or collapse queued/failed to success -> GMF-03E red | `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart --plain-name 'GMF-03E target exceptions are isolated without aborting later forwards'`; same `GROUP_TESTS` registration |
| TC-236-03O | Existing group-destination owner persistence and wire omission remain correct; a strengthened same-parent-ID direct collision stays isolated. | `test/features/share/application/share_batch_delivery_coordinator_test.dart::GMF-03O existing group owner persistence remains local and collision safe` | `GREEN sentinel` strengthened / real existing coordinator path, strict media repository, same-ID direct control, contact plus group destinations | GREEN on HEAD: current test already saves `MediaOwnerLane.group` and omits local wire state -> collision strengthening remains GREEN; contact continues through plan 232 direct ownership | remove owner-scoped save/load, serialize owner, or let direct collision replace/load as group -> sentinel red | `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart --plain-name 'GMF-03O existing group owner persistence remains local and collision safe'`; add existing suite to `GROUP_TESTS` |
| TC-236-04 | The selected attachment and original caption seed the request; editing/clearing the caption affects every new target message without mutating the source. | `test/features/groups/presentation/group_media_forward_flow_test.dart::GMF-04 editable caption and selected item are forwarded without source mutation` | host widget/integration / multi-media source message | HEAD RED -> only viewer-selected attachment is sent, edited caption is used per target, source row/files are unchanged | forward every source attachment or write edited caption back to source -> GMF-04 red | `flutter test test/features/groups/presentation/group_media_forward_flow_test.dart --plain-name 'GMF-04 editable caption and selected item are forwarded without source mutation'`; `GROUP_TESTS` |
| TC-236-05 | Partial success remains per-target; picker retry retains only failed targets. Queued targets leave selection and remain exclusively owned by durable retry with their original message/logical-delivery identity and marker. | `test/features/share/presentation/share_target_picker_wired_test.dart::GMF-05 picker retries failed only and leaves queued forward to durable retry` plus coordinator result assertions | host widget/application / deterministic sent, queued and failed group/contact targets | HEAD generic failed-only behavior GREEN but group marker absent -> only failed target is resubmitted; queued/sent target calls stay one; queued persisted identity/marker is unchanged | retain queued/sent targets, remint queued identity, or collapse result to all-success -> GMF-05 red | `flutter test test/features/share/presentation/share_target_picker_wired_test.dart --plain-name 'GMF-05 picker retries failed only and leaves queued forward to durable retry'`; add picker/coordinator suites to `GROUP_TESTS` |
| TC-236-06 | Migration 099 appends exactly once to both production registry arms, adds constrained default-false `is_forwarded`, and preserves a complete populated v98 predecessor. | `test/core/database/migrations/099_group_messages_is_forwarded_test.dart::GMF-06 v99 extends registries and preserves populated complete v98 state` | host migration / production registries, fresh DB plus v98 fixture with direct/group/unresolved media state/indexes, `messages.is_forwarded=1`, populated journal/indexes, and group quote/retry/transport/logical-delivery/backoff values plus named group indexes | HEAD SQL RED: 099 absent -> fresh/create and v98 upgrade reach 99; actual 099 entry reruns non-vacuously; default/check/map pass; every populated predecessor value and index is unchanged | duplicate/omit 099, invoke a vacuous 99->99 registry range, use an empty journal or skeletal group row, remove CHECK, or drop predecessor state/index -> GMF-06 red | `flutter test test/core/database/migrations/099_group_messages_is_forwarded_test.dart --plain-name 'GMF-06 v99 extends registries and preserves populated complete v98 state'`; AUTO `core-host-all`; structural only |
| TC-236-06D | Real SQLCipher upgrades complete v98 to v99, rejects wrong password and requested v99->v98 downgrade, then correctly reopens v99 with every predecessor and marker artifact unchanged. | `integration_test/group_forwarded_marker_db_proof_test.dart::GMF-06D encrypted v99 rejects downgrade and preserves complete group predecessor` | pinned single-device integration / password-protected `sqflite_sqlcipher`, same populated v98 fixture plus fresh chain | HEAD device RED -> non-empty `PRAGMA cipher_version`; upgrade/default/true/CHECK/actual-entry rerun pass; wrong password and downgrade fail; final correct reopen remains `user_version=99` with direct marker, journal rows/indexes, group values/indexes, media state and forwarded marker unchanged | accept wrong password/downgrade, reset version, bypass registry, use plaintext, or lose any populated predecessor -> GMF-06D red | exact `flutter test -d "$FLUTTER_DEVICE_ID" ... --plain-name 'GMF-06D encrypted v99 rejects downgrade and preserves complete group predecessor'` command in Acceptance Gates; one exact `group/test` record |
| TC-236-07 | A new group forward carries true through pre-persist, `group:sendReliable`, fallback `group:publish`, `wireEnvelope`, encrypted offline replay plaintext and final row; ordinary sends remain false. | `test/features/groups/application/send_group_message_use_case_test.dart::GMF-07 forwarded marker survives reliable fallback wire and replay payloads` | host application / recording bridge modes, decoded wire and decrypted fake replay plaintext, real repository fake | HEAD RED: field/plumbing absent -> every named payload seam carries the same true marker and no source provenance; ordinary controls omit/false | pass marker only to reliable or fallback, omit wire/replay, set ordinary media true, or leak source metadata -> GMF-07 red | `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GMF-07 forwarded marker survives reliable fallback wire and replay payloads'`; add suite to `GROUP_TESTS` |
| TC-236-07R | Both stored-row re-drive callers preserve the forwarded marker and original message/logical-delivery identity when rebuilding `sendGroupMessage`. | `test/features/groups/application/retry_failed_group_messages_use_case_test.dart::GMF-07R failed group retry preserves forwarded identity` plus `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart::GMF-07U incomplete upload retry preserves forwarded identity` | host application / persisted forwarded+ordinary rows, recording send seam, repository reopen | HEAD causal RED after marker exists: callers currently omit it -> each re-drive passes original true/id/logical id/timestamp; ordinary remains false and no duplicate row appears | default marker false, remint identity/timestamp, or cover only one caller -> corresponding retry test red | the two exact `--plain-name` commands in Acceptance Gates; add both suites to `GROUP_TESTS` |
| TC-236-08 | Live decode/persist and durable membership-buffer save/restart/flush preserve typed true; absent/null/non-bool values remain false, dedup yields one row, and flushed durable entries are deleted. | `test/features/groups/application/group_message_listener_test.dart::GMF-08 live and membership repair preserve forwarded marker across restart` | host application / encrypted live maps, pending-membership repository reopen, membership repair/flush | HEAD RED -> exact bool survives live and persisted buffer reconstruction; legacy false matrix holds; flush persists once and removes pending record | omit marker when serializing persisted message, coerce string true, duplicate on flush, or leave durable pending row -> GMF-08 red | `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name 'GMF-08 live and membership repair preserve forwarded marker across restart'`; add suite to `GROUP_TESTS` |
| TC-236-09 | Ordinary offline drain and history-gap repair preserve the same marker/default across restart and repeated replay. | `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GMF-09 ordinary drain and history gap repair preserve forwarded replay dedup` | host application / ordinary offline envelope plus validated history-range fixture, listener/direct paths, repository reopen | HEAD RED -> true survives both paths; legacy/malformed false; repeating either source produces one durable row after restart | map only ordinary drain, omit marker in history-gap handoff, bypass dedup, or recreate false after reopen -> GMF-09 red | `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GMF-09 ordinary drain and history gap repair preserve forwarded replay dedup'`; add suite to `GROUP_TESTS` |
| TC-236-10 | Discussion bubble renders one “Forwarded” indicator for true and none for legacy/ordinary messages; Info does not reveal origin. | `test/features/groups/presentation/group_conversation_screen_test.dart::GMF-10 forwarded label is truthful and origin minimizing` | host widget / true,false,legacy message fixtures with sentinel origin secrets | HEAD RED: marker/model absent -> label parity is exact and sentinel source identity/id never renders | label every media message or render original-author metadata -> GMF-10 red | `flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'GMF-10 forwarded label is truthful and origin minimizing'`; existing `GROUP_TESTS` entry |
| TC-236-11 | The optional bool maps through both Go bridge group commands, survives real encrypted bridge roundtrip, and relies on the existing node encrypted-extra behavior without node production edits. | `go-mknoon/bridge/bridge_test.go::TestGMF11ForwardedMarkerMapsToPublishOptions`; `integration_test/group_real_crypto_onboarding_test.dart::GMF-11 forwarded marker survives real Go bridge group encryption and legacy absence defaults false`; existing `go-mknoon/node/pubsub_delivery_test.go::TestGK030PublishGroupMessagePreservesExtraFieldsInReceivedEvent` | host Go bridge mapping + host two-node node sentinel + pinned single-device real bridge | HEAD RED: bridge params/options whitelist drops marker -> both `group:sendReliable` and `group:publish` options include true; real encrypted roundtrip returns true/legacy false; GK030 remains GREEN | map only one command, move marker outside encrypted options, alter node production, or accept string true | the three exact Go/device commands in Acceptance Gates; Go subgate wired into `groups` and `all`; device path exact-classified |
| TC-236-12 | Announcement read/write rules and targets remain unchanged; this flow never publishes there even for admins. | `test/features/groups/presentation/group_media_forward_flow_test.dart::GMF-12 discussion forwarding excludes announcements without changing their existing authoring rules` | host widget/application + existing announcement sentinels | HEAD announcement rules GREEN/no forward flow -> announcement never appears as this flow's target; existing admin/non-admin tests remain green | broaden destination predicate or alter announcement `canWrite` -> GMF-12/sentinel red | `flutter test test/features/groups/presentation/group_media_forward_flow_test.dart --plain-name 'GMF-12 discussion forwarding excludes announcements without changing their existing authoring rules'`; `GROUP_TESTS` |
| TC-236-13 | Internal Forward is distinct from OS Share and ordinary send; only an explicit accepted forward creates the marker. | `test/features/groups/application/group_media_forward_intent_test.dart::GMF-13 only explicit internal forward sets forwarded provenance` | host unit / ordinary send, OS share, canceled picker, accepted forward intents | HEAD compile RED -> exactly accepted internal forward yields true | infer forwarded from media presence or any share entry point -> GMF-13 red | `flutter test test/features/groups/application/group_media_forward_intent_test.dart --plain-name 'GMF-13 only explicit internal forward sets forwarded provenance'`; add file to `GROUP_TESTS` |
| TC-236-14 | The transport boundary is limited to optional encrypted metadata and contains no topic/auth/fanout/retry changes. | `test/features/groups/integration/group_forwarding_transport_boundary_test.dart::GMF-14 forwarding changes only approved marker plumbing` | host source-contract / allowlist of Dart/Go bridge files and forbidden tokens | HEAD compile RED: contract absent -> diff/source allowlist accepts group model/send/listen/db, bridge bool mapping, tests; rejects node production/topic/recipient/key changes | edit `go-mknoon/node` production or introduce new publish/channel method -> GMF-14 red | `flutter test test/features/groups/integration/group_forwarding_transport_boundary_test.dart`; add file to `GROUP_TESTS`; node baseline diff below |

### Test Notes

- TC-236-01R computes SHA-256 from the exact resolved file immediately before delivery. Metadata presence plus `File.exists` is insufficient because bytes can change after the viewer first qualified them.
- TC-236-02 validates current target authority before each upload; existing send use cases remain the final authorization gate. A missing repository target is failure, never `?? pickerTarget` fallback.
- TC-236-03 asserts fresh ciphertext-enabling inputs and decoded destination maps, not uploader counts. Target peer sets and ids are current/distinct; every source identifier, author, owner, hash, key and access list is absent.
- TC-236-03O is a strengthened GREEN sentinel over the already-landed owner save. Its literal direct/group parent-ID collision must pass through a strict repository; do not claim the basic owner behavior is RED.
- TC-236-05 treats queued as durably owned work, not a picker failure. TC-236-07R separately proves both background re-drive callers preserve the original marker and identity.
- TC-236-06 is structural host coverage only. Its group row gives non-default values to `quoted_message_id`, `wire_envelope`, `inbox_stored`, `inbox_retry_payload`, `transport_peer_id`, `last_send_attempt_at`, `logical_delivery_id`, `retry_attempt_count`, and `next_eligible_at`; it preserves `idx_group_messages_group`, `idx_group_messages_ts`, `idx_group_messages_logical_delivery`, and `idx_group_messages_group_ts`. The populated journal preserves both `idx_group_media_deletion_journal_group_message` and `idx_group_media_deletion_journal_operation`; direct forwarded and exact media owner/viewer state/indexes also survive. TC-236-06D repeats that state on SQLCipher, rejects wrong password/downgrade, then proves an unchanged v99 reopen.
- TC-236-06D must use the production registry callbacks and production `onDatabaseVersionChangeError` downgrade guard (or the same opener that installs them). A test-owned throw or plaintext database cannot satisfy the row.
- TC-236-08/09 use repository reopen/new listener instances so membership-buffer and history-gap assertions cannot pass only through in-memory state.
- TC-236-11 is the real bridge/device closure claim; TC-236-06D separately closes the production SQLCipher boundary. Host fakes prove mapping logic but cannot replace either boundary.
- The source-contract allowlist in TC-236-14 should be path- and symbol-specific so an unrelated comment cannot satisfy it and a protocol edit cannot hide behind a broad “no new API” assertion.

## Implementation Steps

1. Verify committed HEAD contains Plan 235's implemented closure, DB v98, migration 098, and exactly one 098 entry in each production registry arm; also verify landed plans 228/230/232. Stop if worktree v98 differs from committed HEAD, a prerequisite closure regresses, or the contact marker contract differs.
2. Snapshot `git status --short`; add TC-236-01 and run its named causal RED before production edits.
3. Add TC-236-01R/02 before adapting the picker/coordinator. Implement a typed stable source identity, dispatch-time parent/owner/file/hash verification, `GroupType.chat` filtering, and current contact/group/key/membership/type revalidation immediately before upload. Stop if this requires trusting picker objects, skipping the current SHA-256 verifier, or changing group authorization protocols.
4. Add TC-236-03/03E and preserve the GREEN TC-236-03O. Pass only the verified source file into per-target isolated upload/send attempts; allocate fresh destination crypto/ids, preserve explicit local owners, and assert that source/owner/access metadata enters no wire/retry map.
5. Add TC-236-05/07/07R before marker production edits. Make picker retry failed-only; thread the marker through pre-persist, reliable/fallback/wire/replay maps and both durable re-drive callers while preserving queued identity.
6. After the committed-v98 stop rule passes, add migration 099, bump to 99, append exactly once to both shared registry arms, and map `GroupMessage.isForwarded` default false. Add populated complete-predecessor host TC-236-06 and SQLCipher TC-236-06D with cipher/wrong-password/downgrade/reopen proof.
7. Add TC-236-08/09/10/13 and thread the bool through live decode, durable membership buffer, ordinary offline drain, history-gap repair, repository/restart/dedup and UI. Do not edit Go node production behavior.
8. Add the named Go bridge mapping test, retain GK030 as the node sentinel, and extend the real bridge integration. Wire exact bridge+node commands into `run_test_gates.sh` `groups` and `all`; classify both device paths through exact discovery only.
9. Register every modified/new host suite in `GROUP_TESTS`; run focused GREEN, representative mutations, group/core gates, SQLCipher and bridge device legs, announcement sentinels, analyzer and hygiene.

## Risks And Blind Spots

- Cross-group confidentiality -> TC-236-03 fails if any source ciphertext/key/nonce/blob/allowed-peer metadata is reused.
- Source bytes can change after viewer qualification -> TC-236-01R requires a current resolved-file hash immediately before delivery.
- Authorization can change while picker is open -> TC-236-02/12 require repository-backed pre-upload revalidation and retain final send authorization.
- A target exception can abort later targets -> TC-236-03E isolates each attempt and preserves ordered typed results.
- Partial fanout/retry can duplicate messages -> TC-236-05 keeps queued work out of picker retry; TC-236-07R preserves durable identity in both re-drive callers.
- Migration ordering may collide with sibling lanes -> TC-236-06/06D and the execution stop rule reserve v99 only after v96-v98.
- Attachment ownership can regress during destination fanout -> GREEN TC-236-03O preserves explicit group persistence, direct delegation and local-only serialization with a same-ID collision.
- Live/offline/repair schema drift -> TC-236-08/09 cover live, membership buffer, ordinary drain and history-gap paths through restart/dedup.
- Forward provenance can become a privacy leak -> TC-236-10/13 ban original sender/source ids and mark only explicit forwards.
- Lifecycle / derived-state durability: marker is canonical durable state in `group_messages`, not UI-derived; TC-236-06/06D, 07/07R, 08 and 09 cover persisted/restart paths.
- Sibling-surface consistency: viewer action and destination bubble use the same request/marker semantics; TC-236-01/10/13.
- Destructive-action side effects: N/A — forwarding creates new destination messages and never mutates/deletes the source; TC-236-04 asserts that preservation.
- Invariant re-verification under new transitions: target membership/key and source eligibility are checked again immediately before each upload/send.
- Transport scope creep -> TC-236-11/14 plus `git diff -- go-mknoon/node` prove existing libp2p semantics remain untouched.

## Gate Cadence

- Per-plan closure: run focused Plan-236 tests, the curated `groups` lane gate (including the exact bridge/node Go subgate), `core-host-all` for the migration/registry change, and the SQLCipher/real-bridge device legs. The same Go subgate is wired into `all` for later aggregate closure but `all` is not rerun here.
- `feature-host-all` and full `host-all` are not individual Plan-236 closure gates.
- Full `host-all` runs once after the ordered migration/forwarding wave (`232 → 235 → 236 → 240`) and once at final rollout closure.

## Acceptance Gates

```bash
# Committed predecessor closure; do not create v99 from dirty-only or incomplete v98 state
git show HEAD:Test-Flight-Improv/235-group-received-media-core-actions-tdd-plan.md | rg '^Status: IMPLEMENTED'
if git show HEAD:Test-Flight-Improv/235-group-received-media-core-actions-tdd-plan.md | rg -q '^- \[ \]'; then exit 1; fi
git show HEAD:lib/core/database/app_database_version.dart | rg '^const int currentIdentityDatabaseVersion = 98;$'
rg -n '^const int currentIdentityDatabaseVersion = 98;$' lib/core/database/app_database_version.dart
git cat-file -e HEAD:lib/core/database/migrations/098_group_media_deletion_journal.dart
test "$(git show HEAD:lib/core/database/production_migration_registry.dart | rg -c "ProductionMigrationEntry\(98, '098_group_media_deletion_journal'")" -eq 2
git diff --quiet HEAD -- \
  lib/core/database/app_database_version.dart \
  lib/core/database/migrations/098_group_media_deletion_journal.dart \
  lib/core/database/production_migration_registry.dart \
  Test-Flight-Improv/235-group-received-media-core-actions-tdd-plan.md

# Snapshot before execution
git status --short
git status --short --untracked-files=all -- go-mknoon/node \
  ':(exclude,glob)go-mknoon/node/*_test.go' \
  ':(exclude,glob)go-mknoon/node/**/*_test.go' \
  > /tmp/plan-236-go-node-production-status.before
git diff --binary -- go-mknoon/node \
  ':(exclude,glob)go-mknoon/node/*_test.go' \
  ':(exclude,glob)go-mknoon/node/**/*_test.go' \
  > /tmp/plan-236-go-node-production-diff.before

# First causal RED; expect non-zero because policy/request types are absent
flutter test test/features/groups/application/group_media_forward_policy_test.dart --plain-name 'GMF-01 only eligible incoming discussion media can forward'

# Focused host GREEN
flutter test test/features/groups/application/group_media_forward_policy_test.dart
flutter test test/features/groups/application/group_media_forward_intent_test.dart
flutter test test/features/groups/presentation/group_media_forward_flow_test.dart
flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart --plain-name 'GMF-'
flutter test test/features/share/presentation/share_target_picker_wired_test.dart --plain-name 'GMF-05'
flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GMF-07'
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name 'GMF-07R'
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name 'GMF-07U'
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name 'GMF-08'
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GMF-09'
flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'GMF-10'
flutter test test/features/groups/integration/group_forwarding_transport_boundary_test.dart

# Plan-228 owner/registry preservation plus structural v99 registration (device SQLCipher proof follows below)
flutter test test/core/database/helpers/media_attachments_db_helpers_test.dart --plain-name 'owner scoped load and delete isolate equal direct and group message ids'
flutter test test/features/conversation/domain/models/media_attachment_test.dart --plain-name 'owner and library state are local only across map and wire serialization'
flutter test test/core/database/integration/full_migration_chain_test.dart --plain-name 'production create and v95 upgrade registries include media library state v96'
flutter test test/core/database/migrations/098_group_media_deletion_journal_test.dart
flutter test test/core/database/migrations/099_group_messages_is_forwarded_test.dart
flutter test test/core/database/integration/full_migration_chain_test.dart

# Non-vacuous Go bridge mapping + unchanged-node encrypted-extra sentinel
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run '^TestGMF11ForwardedMarkerMapsToPublishOptions$' -count=1)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestGK030PublishGroupMessagePreservesExtraFieldsInReceivedEvent$' -count=1)

# Registered host families and preservation
group_files=(
  test/features/groups/application/group_media_forward_policy_test.dart
  test/features/groups/application/group_media_forward_intent_test.dart
  test/features/groups/presentation/group_media_forward_flow_test.dart
  test/features/share/application/share_batch_delivery_coordinator_test.dart
  test/features/share/presentation/share_target_picker_wired_test.dart
  test/features/groups/application/send_group_message_use_case_test.dart
  test/features/groups/application/retry_failed_group_messages_use_case_test.dart
  test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart
  test/features/groups/application/group_message_listener_test.dart
  test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
  test/features/groups/presentation/group_conversation_screen_test.dart
  test/features/groups/integration/group_forwarding_transport_boundary_test.dart
)
for file in "${group_files[@]}"; do
  test "$(awk '/^readonly GROUP_TESTS=\(/,/^\)/' scripts/run_test_gates.sh | rg -F -x -c "  \"$file\"")" -eq 1
done
test "$(rg -c '^run_group_forwarding_go_bridge_gate\(\) \{$|^      run_group_forwarding_go_bridge_gate$' scripts/run_test_gates.sh)" -eq 3
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh core-host-all
flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'returns unauthorized for non-admin in announcement group'

# Discover exact classifier records, then pin one available compatible target for both one-device boundaries
records_file="$(mktemp)"
./scripts/check_reliability_simulation_discovery.sh --records-tsv >"$records_file"
test "$(awk -F '\t' '$1 == "group" && $2 == "test" && $3 == "integration_test/group_forwarded_marker_db_proof_test.dart" { n++ } END { print n + 0 }' "$records_file")" -eq 1
test "$(awk -F '\t' '$1 == "group" && $2 == "test" && $3 == "integration_test/group_real_crypto_onboarding_test.dart" { n++ } END { print n + 0 }' "$records_file")" -eq 1
test "$(awk -F '\t' '$1 == "unclassified" && ($3 == "integration_test/group_forwarded_marker_db_proof_test.dart" || $3 == "integration_test/group_real_crypto_onboarding_test.dart") { n++ } END { print n + 0 }' "$records_file")" -eq 0
rm -f "$records_file"
sim_plan="$(mktemp)"
./scripts/run_reliability_simulations.sh group --list >"$sim_plan"
test "$(rg -F -c 'integration_test/group_forwarded_marker_db_proof_test.dart' "$sim_plan")" -eq 1
test "$(rg -F -c 'integration_test/group_real_crypto_onboarding_test.dart' "$sim_plan")" -eq 1
rm -f "$sim_plan"
flutter devices --machine > /tmp/plan-236-flutter-devices.json
adb devices -l || true
xcrun simctl list devices available || true
: "${FLUTTER_DEVICE_ID:?set FLUTTER_DEVICE_ID to one available compatible target from the inventories above}"
rg -F "$FLUTTER_DEVICE_ID" /tmp/plan-236-flutter-devices.json
flutter test -d "$FLUTTER_DEVICE_ID" integration_test/group_forwarded_marker_db_proof_test.dart --plain-name 'GMF-06D encrypted v99 rejects downgrade and preserves complete group predecessor'
flutter test -d "$FLUTTER_DEVICE_ID" integration_test/group_real_crypto_onboarding_test.dart --plain-name 'GMF-11 forwarded marker survives real Go bridge group encryption and legacy absence defaults false'

# Hygiene
git status --short --untracked-files=all -- go-mknoon/node \
  ':(exclude,glob)go-mknoon/node/*_test.go' \
  ':(exclude,glob)go-mknoon/node/**/*_test.go' \
  | cmp -s - /tmp/plan-236-go-node-production-status.before
git diff --binary -- go-mknoon/node \
  ':(exclude,glob)go-mknoon/node/*_test.go' \
  ':(exclude,glob)go-mknoon/node/**/*_test.go' \
  | cmp -s - /tmp/plan-236-go-node-production-diff.before
flutter analyze
git diff --check
```

## Device/Relay Proof Profile

- Profile: single-device production SQLCipher + real-Go-bridge integration; the supporting two-node encrypted pubsub proof runs as a host Go test.
- Boundary being proven: (1) migration 099 extends the shared registry over populated complete v98 state on password-protected SQLCipher, reports non-empty cipher version, rejects wrong password and v99->v98 downgrade, and correctly reopens unchanged at v99; (2) the native Go bridge accepts optional `isForwarded`, places it in already encrypted group payload extras, and returns it through real decryption/event mapping; legacy absence remains false.
- Live availability check: write `flutter devices --machine`, `adb devices -l`, and available `simctl` targets, explicitly export one returned compatible `FLUTTER_DEVICE_ID`, and verify that exact ID occurs in the Flutter inventory before either command. A missing compatible target blocks the corresponding row; it never becomes GREEN by proxy.
- Required setup: one simulator/device with the production `sqflite_sqlcipher` plugin and real-Go group crypto fixture, built Go bridge framework, test identity/group keys supplied by `group_real_crypto_onboarding_test.dart`; DB proof creates/deletes its own password-protected files and no external relay account is required.
- Closure role: both device rows are required. Host SQLite cannot prove SQLCipher, and host listener/drain fakes plus Go unit tests cannot prove the native bridge framework.
- `FLUTTER_DEVICE_ID`: sufficient because each row is single-device; it is not a peer-pair selector. Both commands use the same explicitly validated ID unless one target cannot provide both plugins, in which case pin and validate a separate ID immediately before that command.
- Registration: add only an exact `classify_path` `record "group" ... "test"` for `group_forwarded_marker_db_proof_test.dart`; retain the existing exact group record for `group_real_crypto_onboarding_test.dart`. There is no group simulator array—the runner derives its plan from classifier records.
- Discovery commands: the literal exact-count TSV and group `--list` assertions in Acceptance Gates.
- Closure commands: the GMF-06D and GMF-11 `flutter test -d "$FLUTTER_DEVICE_ID" ...` commands in Acceptance Gates.
- Deferred device work: none for this marker boundary; end-to-end multi-recipient UI fanout remains host-deterministic because it uses existing delivery primitives rather than a new transport.

## Execution Interpretation And Done Criteria

- Expected RED: TC-236-01 fails to compile because group media forward policy/request types do not exist.
- Green sentinels: existing group-owner persistence/collision isolation, generic share partial-result tests, group media validation, announcement authorization/read-only behavior, and GK030 encrypted-extra delivery remain green.
- Pre-existing dirty tree / known failure: record from execution-time snapshot; do not absorb unrelated changes.
- Execution stop rule: the committed-HEAD preflight must continue to prove implemented Plan 235, DB/migration v98, exact registry entries, and no worktree-only prerequisite edits before v99 work begins. Those prerequisites are currently satisfied, so the plan remains implementation-ready rather than prerequisite-blocked.
- Environment blocker: no compatible SQLCipher target or bridge framework blocks the corresponding TC-236-06D/11 row and final device closure, not host implementation evidence.
- Scope drift: Go node production, pubsub topics, group membership/key rules, retry protocol, announcement targets, original-author metadata, or shared-ciphertext reuse blocks execution for replanning.

- [x] Every behavior has a named causal test or justified real-boundary proof.
- [x] First RED, focused GREEN, representative mutation re-red, and preservation outcomes are recorded.
- [x] Migration 099 extends both registry arms exactly once and passes populated complete-v98 structural preservation plus real-SQLCipher cipher/wrong-password/downgrade/reopen/idempotence/default/true/CHECK/full-chain checks.
- [x] Dispatch reloads/hash-verifies the exact source; every destination reloads current contact/group/key/membership/type before a fresh upload; target exceptions remain isolated.
- [x] Existing group-destination `MediaOwnerLane.group` persistence remains GREEN; no local/source authority enters destination wire/retry maps and same-ID direct rows stay isolated.
- [x] Reliable/fallback/wire/replay, both durable re-drive callers, live membership repair, ordinary drain, history-gap repair, repository/restart/dedup and UI marker semantics agree; absence/malformed values are false.
- [x] No original sender/source metadata propagates and OS Share never sets the marker.
- [x] Go node production status/binary diff matches baseline; exact bridge mapping and GK030 node tests run non-vacuously from both `groups` and `all` wiring; real device bridge proof passes.
- [x] Every modified/new host suite is in `GROUP_TESTS`; announcement, groups/core, analyzer and hygiene gates pass.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `flutter test test/features/groups/application/group_media_forward_policy_test.dart --plain-name 'GMF-01 only eligible incoming discussion media can forward'`.
- Preservation commands: `flutter test test/features/conversation/domain/models/media_attachment_test.dart --plain-name 'owner and library state are local only across map and wire serialization'`, `flutter test test/core/database/integration/full_migration_chain_test.dart --plain-name 'production create and v95 upgrade registries include media library state v96'`, and `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'returns unauthorized for non-admin in announcement group'`.
- Harness registration: register every named group/share/send/listener/drain/retry suite exactly once in `GROUP_TESTS`; add a named Go bridge option-mapping test and run separate exact bridge/node commands from the `groups` and `all` cases; classify both device paths only through exact `group/test` records. Record/compare node-production-only status and binary diff while excluding allowed `*_test.go` changes.
- Migration: exclusively v99 `group_messages.is_forwarded`; append after a populated complete v98 predecessor containing v96 media state/indexes, direct forwarded state, populated Plan-235 journal/indexes, and all non-default group message/index state; close with fail-closed downgrade and correct v99 reopen. Announcement Plan 240 may reuse the column but not change migration semantics.
- Boundary closure: host per-target encryption/access assertions + structural host migration + real-SQLCipher device migration/full-chain + two-node Go extra delivery + single-device real-Go-bridge encrypted marker proof.
- Unresolved evidence: none; committed prerequisites currently pass the stop rule, while unavailable compatible device state remains only an execution environment blocker.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | Plan 235 implemented/committed; HEAD and worktree at v98 with migration/registry present; v99 reserved here | committed-HEAD preflight must remain green at execution start | run preflight, then first causal RED |
| 2026-07-10 | preflight + snapshot | committed HEAD, /tmp/plan-236-go-node-production-*.before | all preflight gates PASS; node baselines empty | 235 IMPLEMENTED at HEAD, v98 + 2x registry entries, no worktree drift; dirty tree = pre-existing plan/graphify files (other sessions live — pathspec-only git ops) | proceed | first causal RED |
| 2026-07-10 | RED->GREEN 01/01R/13 | group_media_forward_intent.dart, group_media_forward_policy.dart (policy + GroupMediaForwardSourceGate + request builder), coordinator deliverGroupMediaForward + per-target catch | GMF-01 compile RED observed, then all GREEN | gate has sync fileExists/hash seams for widget tests (GMF-01R pins real defaults); interface change fixed 4 coordinator fakes | - | picker/viewer wiring |
| 2026-07-10 | RED->GREEN 02/04/12 | picker forward mode (chat-only filter, deliverGroupMediaForward dispatch, caption seed), route param, group_conversation_wired viewer Forward + launcher + fallback route, main/orbit/feed wiring, group_media_forward_flow_test.dart | 3/3 GREEN; 199-test wired+picker suites GREEN | testWidgets fake-async landmine: real dart:io hash streams stall -> sync gate seams injected; re-pumped picker needs UniqueKey or State reuse skips _loadTargets | - | coordinator tests |
| 2026-07-10 | RED->GREEN 03/03E/03O + model/migration/marker plumbing | GroupMessage.isForwarded, 099 migration + version 99 + both registry arms, bridge_group_helpers, send_group_message_use_case (wire/inbox/prePersist/reliable/publish), both retry callers, coordinator group lane marker | GMF-03 compile RED observed; coordinator suite 16/16 GREEN | full-success send clears wireEnvelope by design -> GMF-03 retry-map assert uses retained inboxRetryPayload (custody-fail); TC-236-07 owns the full seam matrix | - | GMF-05/06/07 |
| 2026-07-10 | GREEN 05/06/07/07R/07U | picker GMF-05, 099_group_messages_is_forwarded_test.dart, GMF-07 in send suite, GMF-07R/07U in retry suites | all GREEN; full-chain 13/13 after 3 version-pin bumps (97->99 maintenance, same as 235 did) | uploads-retry fake needs willReturnForPath per resolved path | - | receive paths |
| 2026-07-10 | GREEN 08/09/10 | listener wireIsForwarded + persisted-buffer serialization, handle_incoming isForwarded, drain 5 replay maps, GMF-08/09 tests, group screen LetterCard isForwarded + GMF-10 | all GREEN; 385-test listener/drain/incoming suites GREEN after fixture bump | plan-235 real-DB fixtures pinned v98 -> bumped to currentIdentityDatabaseVersion (is_forwarded column); drain advances synthetic since-cursor between calls -> later fake pages keyed at stored cursor | - | Go + boundary |
| 2026-07-10 | GREEN 11/14 + device proofs | bridge.go IsForwarded param + shared opts map, TestGMF11 (Go), GMF-11 integration extension, group_forwarding_transport_boundary_test.dart, group_forwarded_marker_db_proof_test.dart | TestGMF11 + GK030 + full ./bridge suite GREEN; GMF-06D PASSED and GMF-11 PASSED on emulator-5554 (inventory written, ID validated) | GMF-11 decrypts the reliable envelope's nested `encrypted` {ciphertext,nonce}; empty durable recipient set -> no relay needed | - | harness + gates |
| 2026-07-10 | gate-parallelism hardening | group_media_forward_policy_test, share_batch_delivery_coordinator_test, group_media_forward_flow_test | groups gate run 3: 1856 tests ZERO failures + Go subgate GREEN | first two gate runs flaked 2 wired/flow tests: suites' teardowns deleted the SHARED FakeMediaFileManager.testRootPath while parallel suites read it -> my 3 suites moved to PRIVATE per-test systemTemp dirs (absolute localPath passes resolveStoredPath through) and stopped deleting the shared root | - | core-host-all + commit |
| 2026-07-10 | harness + closure | GROUP_TESTS +11 files, run_group_forwarding_go_bridge_gate (def + groups + all = 3 exact), classifier group/test record for db proof, discovery TSV + group --list assertions PASS | preservation 4/4 GREEN; node status/binary baselines UNCHANGED; git diff --check clean; mutations: GMF-01 (drop chat guard) RED, GMF-01R (skip hash) RED, GMF-07 (drop publish marker) RED — each reverted, focused GREEN restored | GMF-03E HEAD-RED evidence recorded as mutation semantics (catch landed with the 01R slice before its test) | groups gate + core-host-all + analyzer running | final gates, commit |
