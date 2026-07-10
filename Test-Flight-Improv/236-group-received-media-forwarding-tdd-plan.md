# 236 - Group Received Media Forwarding

Status: execution-ready
Type: New Feature
Spec: free-text intent — forward incoming discussion-group image/video media to contacts or other discussion groups with destination-scoped encryption and no transport-semantic change
Classification: implementation-ready
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | group media viewer/wiring, `ShareTargetPickerWired`, share batch coordinator/tests, group send/listen/offline paths, group model/repository, bridge group helpers, Go bridge/node extra-field flow, migrations/gates, real-crypto integration fixture | Existing share fanout already reuploads per target and applies contact/group access policy. Group messages lack a forwarded marker and group source actions. A backward-compatible encrypted-inner bool needs DB v98 plus narrow Dart/Go-bridge plumbing, not a new libp2p protocol. | Start the pure source/destination policy RED; enforce v96/v97 predecessor versions as execution stop rules before v98 work. |
| 2026-07-10 | Planner | revised plan 228 owner-state/migration-registry contract, plan 232 v97 dependency, share coordinator group-destination persistence seams, migration/full-chain proofs | Group-destination attachments must persist explicit `MediaOwnerLane.group`. Migration 098 must extend the shared production create/upgrade registry introduced by plan 228, and its v97 predecessor fixture must retain every v96 owner/state/index artifact. | Add owner-persistence and complete-predecessor assertions before v98/bridge edits. |
| 2026-07-10 | Replanner (version rebase) | plan 235 audit disposition, this plan's migration/gate rows | Plan 235's counterexample audit allocated DB v98 to its `group_media_deletion_journal`; this plan's forwarded marker is rebased from v98 to v99 (`099_group_messages_is_forwarded`). Predecessor fixture becomes complete v98 (v96 owner/state/index artifacts plus plan 235's journal). | Execute only after v98 lands; all v99 gates below reflect the rebase. |

## Problem And Evidence

- Behavior to improve: a user should be able to forward a selected incoming verified image/video from a `GroupType.chat` conversation to one or more contacts and writable discussion groups, optionally editing its caption.
- Impact: current group media can be viewed but cannot be redistributed inside Mknoon; users must leave the app or manually recreate a send.
- Confirmed reusable picker: `lib/features/share/presentation/screens/share_target_picker_wired.dart:142` loads contacts and writable groups, supports multi-selection, revalidates group eligibility before delivery, and composes an editable caption.
- Confirmed reusable fanout: `lib/features/share/application/share_batch_delivery_coordinator.dart:187` processes the source once and then creates/uploads a new attachment for every target. Contact delivery calls `uploadMedia` then `sendChatMessage`; group delivery resolves membership, derives `allowedPeers`, calls `uploadMedia`, then `sendGroupMessage`.
- Security implication: existing coordinator behavior is the correct boundary — forward decrypted verified source bytes, then create new destination-scoped ciphertext/upload metadata. Reusing the source group's ciphertext, key/nonce, blob id, or allowed-peer list would be a confidentiality bug.
- Confirmed authorization boundary: `_isWritableGroupTarget` rejects archived/dissolved groups, missing membership/keys, and announcement targets for non-admins. This discussion-lane plan narrows that further to `GroupType.chat`; announcement publishing remains owned by the announcement plan.
- Confirmed schema gap: `lib/features/groups/domain/models/group_message.dart` has quote/media fields but no `isForwarded`; the `group_messages` table has no forwarded column.
- Confirmed local-owner prerequisite: revised plan 228 makes attachment owner mandatory because direct and group message IDs can collide. Every newly uploaded group-destination attachment in this flow must persist `MediaOwnerLane.group`; transport payloads must still omit that local field.
- Confirmed wire gap: `SendGroupMessageUseCase`, `bridge_group_helpers.dart`, `group_message_listener.dart`, and `DrainGroupOfflineInboxUseCase` carry quote/media data but no forwarded marker.
- Confirmed narrow Go boundary: `go-mknoon/node/pubsub.go` already preserves arbitrary encrypted payload extras when publishing and rebuilding a received event. `go-mknoon/bridge/bridge.go` parses a whitelist into group message options, so only the bridge parameter/option mapping needs the optional bool; node topic/routing/fanout/crypto algorithms do not.
- Existing real crypto evidence: `go-mknoon/node/pubsub_delivery_test.go::TestGK030PublishGroupMessagePreservesExtraFieldsInReceivedEvent` exercises encrypted two-node extra-field delivery; `integration_test/group_real_crypto_onboarding_test.dart` uses the real Go bridge and is already classified by the group reliability simulator.
- Missing coverage: no source Forward action, destination-lane filter, per-target re-encryption assertion, forwarded marker migration/default, live/offline marker roundtrip, retry preservation, display marker, or real bridge proof exists.
- Refuted finding: a new group publish primitive is not required. The current share coordinator already invokes the existing authorized `SendGroupMessageUseCase`; this plan supplies a typed forward intent and optional payload metadata only.
- Unresolved finding: N/A. Migration ordering is known execution sequencing, not an evidence gap: migration 099 follows plan 228's v96, plan 232's v97, and plan 235's v98 journal, extends plan 228's shared production registry, and must not be renumbered or wired through new duplicate callbacks.
- Affected production, test, migration, bridge, and gate files: group message model/DB mapping/send/listen/drain flows, new migration 099, group media action/picker adapters, share delivery intent/coordinator extensions, narrow Go bridge bool plumbing/tests, group real-crypto proof, full migration chain, and group gate registration.

## Scope Contract And Guard

In scope:
- Source: one selected incoming verified image/video in `GroupType.chat`; use its caption as the editable initial caption.
- Destinations: one or more contacts and writable `GroupType.chat` groups. Revalidate destination eligibility immediately before each send.
- Reuse the existing multi-select picker and `DefaultShareBatchDeliveryCoordinator` through a typed internal `GroupMediaForwardRequest`; do not route internal forwarding through the OS share intent.
- Read source bytes only after path/integrity revalidation. For every destination, allocate a new attachment/message id and perform a new encrypted upload using that destination's current access policy. Persist every group-destination attachment with explicit `MediaOwnerLane.group`; contact-destination attachment ownership remains plan 232's `direct` contract.
- Return existing per-target sent/queued/failed results without turning partial success into all-success or retrying successful targets.
- Add `GroupMessage.isForwarded` persisted by migration 099 as `group_messages.is_forwarded INTEGER NOT NULL DEFAULT 0 CHECK (is_forwarded IN (0,1))`.
- Carry optional `isForwarded: true` only inside the existing encrypted group-message payload. Absence, null, or a non-boolean legacy/unknown value decodes as `false`.
- Preserve the marker through outgoing pre-persist/retry, Go bridge mapping, live listener, offline inbox drain, repository mapping, and discussion bubble rendering.
- Marker semantics are origin-minimizing: show “Forwarded” but never copy the original sender identity, source group id/name, source message id, or original encryption metadata into the new message.

Must preserve:
- Existing share batch per-target result and durable background behavior -> `test/features/share/application/share_batch_delivery_coordinator_test.dart`; `GREEN sentinel`.
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
- Do not propagate original-author identity or source-conversation metadata.

Deferred / accepted difference:
- Contact-destination persistence/rendering of `messages.is_forwarded` is owned by plan 232 (`Test-Flight-Improv/232-1to1-received-media-forwarding-tdd-plan.md`); this plan proves that a group-origin request invokes that accepted contact lane.
- Announcement-origin/announcement-target forwarding is owned by plan 240 and may reuse migration 099 only after it preserves announcement author/admin rules.
- Multi-attachment album forwarding is deferred; the contract forwards the viewer-selected attachment and an editable caption to multiple destinations.
- Private/protected forwarding policy is owned by plans 234/238; until those land, only ordinary eligible media is supported.
- OS external Share remains plan 227/235 behavior and never creates the internal forwarded marker.

Dependencies:
- Plan 230 typed viewer action/callback contract and plan 235 group received-media action policy/surface.
- Plan 232 contact forwarded-marker contract for contact destinations.
- Ordered database prerequisites: plan 228 owns v96 plus the shared production create/upgrade migration registry, plan 232 owns v97, and plan 235 owns v98 (`group_media_deletion_journal`); this plan exclusively owns v99 and appends it to that registry. The v98 predecessor fixture must include v96 `owner_lane`, bookmark/playback columns, both exact media-owner indexes, and plan 235's journal table. Evidence-gated private-media plans reserve no fixed version.
- Existing `ShareTargetPickerWired`, `DefaultShareBatchDeliveryCoordinator`, group send authorization, and Go encrypted-extra preservation.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-236-01 | Forward appears only for selected incoming verified ordinary media in `GroupType.chat`. | `test/features/groups/application/group_media_forward_policy_test.dart::GMF-01 only eligible incoming discussion media can forward` | host unit / table-driven source/group/attachment state plus abstract policy-allow fixture | HEAD compile RED: policy absent -> only the exact eligible row exposes Forward without requiring a concrete plan-238 lifecycle model | remove incoming/group-type/integrity/policy guard -> GMF-01 red | `flutter test test/features/groups/application/group_media_forward_policy_test.dart --plain-name 'GMF-01 only eligible incoming discussion media can forward'`; add file to `GROUP_TESTS` |
| TC-236-02 | Forward opens the existing multi-target picker with contacts and writable discussion groups only, then revalidates each chosen target. | `test/features/groups/presentation/group_media_forward_flow_test.dart::GMF-02 picker filters and revalidates forwarding destinations` | host widget/application / contacts + chat/announcement/qa/archived/dissolved groups | HEAD compile RED: no group-forward flow -> only contact/chat targets render; revoked eligibility yields typed failure before upload | reuse the broad share filter without the `GroupType.chat` boundary or skip final revalidation -> GMF-02 red | focused flow test; add file to `GROUP_TESTS` |
| TC-236-03 | Every selected target receives a separately uploaded/re-encrypted attachment with a new id and destination-current access policy. | `test/features/share/application/share_batch_delivery_coordinator_test.dart::GMF-03 group origin forward reencrypts independently for every target` | host integration / real temp source + fake uploader/contact/group senders | HEAD RED: typed forward metadata absent -> upload calls have distinct ids/crypto metadata; contact and each group's recipients/allowed peers are exact | reuse any blob/key/nonce/id/allowedPeers across targets -> GMF-03 red | existing share coordinator test AUTO + add named file to `GROUP_TESTS` if split |
| TC-236-03O | Every newly forwarded attachment saved under a group destination carries `MediaOwnerLane.group`; the local owner never enters the payload, and a pre-existing same-message-ID direct attachment remains isolated. | `test/features/share/application/share_batch_delivery_coordinator_test.dart::GMF-03O group forward persists group owner without wire leakage or direct collision` | host integration / recording media repository plus v96 fixture with a pre-existing direct collision row, one contact and two group destinations | HEAD compile RED: typed owner is absent at the coordinator/save seam -> each group save records `group`, the contact delegates to plan 232's direct path, wire maps omit owner, and group per-message load excludes the direct same-ID row | omit owner, pass `direct`/`unresolved`, serialize owner, or load by untyped message id -> GMF-03O red | `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart --plain-name 'GMF-03O group forward persists group owner without wire leakage or direct collision'`; include in `GROUP_TESTS` group subset |
| TC-236-04 | The selected attachment and original caption seed the request; editing/clearing the caption affects every new target message without mutating the source. | `test/features/groups/presentation/group_media_forward_flow_test.dart::GMF-04 editable caption and selected item are forwarded without source mutation` | host widget/integration / multi-media source message | HEAD RED -> only viewer-selected attachment is sent, edited caption is used per target, source row/files are unchanged | forward every source attachment or write edited caption back to source -> GMF-04 red | focused group flow test; `GROUP_TESTS` |
| TC-236-05 | Partial success remains per-target and retry resubmits failed/queued targets only, preserving one forwarded marker on each new message. | `test/features/share/application/share_batch_delivery_coordinator_test.dart::GMF-05 forward reports partial results and does not duplicate successful targets` | host application / deterministic sent, queued, failed senders | HEAD partial GREEN for generic fanout but no forward identity -> retry target set and stable delivery token/message identity are exact | collapse result to all-success or retry a successful target -> GMF-05 red | existing share coordinator test AUTO; include in `GROUP_TESTS` group subset |
| TC-236-06 | Migration 099 appends exactly once to plan 228's shared production create/upgrade registry, adds constrained non-null default-false `is_forwarded`, and preserves a complete v98 predecessor including all v96 owner/state/index artifacts and plan 235's journal table. | `test/core/database/migrations/099_group_messages_is_forwarded_test.dart::GMF-06 v99 extends production registries and preserves the complete v98 predecessor` | host migration / `sqflite_common_ffi`, production registry functions, fresh DB plus v98 fixture with direct/group/unresolved rows, bookmark/playback state, both v96 indexes and the v98 journal | HEAD compile/SQL RED: migration absent -> registry create and v98 upgrade reach 99 exactly once; forwarded default/check/mapping/idempotence pass; legacy media rows, owner/state values, `idx_media_attachments_owner_message` plus `idx_media_attachments_owner_bookmark_message`, and `group_media_deletion_journal` are unchanged | create a parallel migration callback, omit one registry arm, use an incomplete v98 fixture, or drop/change a v96/v98 artifact -> GMF-06 red | `flutter test test/core/database/migrations/099_group_messages_is_forwarded_test.dart --plain-name 'GMF-06 v99 extends production registries and preserves the complete v98 predecessor'`; AUTO `core-host-all`; does **not** claim SQLCipher closure |
| TC-236-06D | The same shared-registry v98->v99 upgrade and fresh/full chain behave correctly on production `sqflite_sqlcipher`, including preservation of v96 attachment ownership/state/indexes and the v98 journal. | `integration_test/group_forwarded_marker_db_proof_test.dart::GMF-06D real SQLCipher v99 extends registries and preserves v96 media ownership state` | device integration / password-protected `sqflite_sqlcipher`, complete v98 predecessor DB + fresh-chain DB | HEAD device RED: migration/proof absent -> `PRAGMA table_info/index_info`, v96 direct/group/unresolved and bookmark/playback rows, default false, explicit true, invalid integer rejection, second invocation, close/reopen mapping, `user_version=99`, and both production registry paths pass | remove default/check, bypass/duplicate a registry arm, lose/reclassify v96 state, or fail rerun/reopen -> GMF-06D red | add an exact `classify_path` `group/test` rule and group reliability-sim array entry; required closure alongside GMF-11 |
| TC-236-07 | Outgoing group forward persists and retries `isForwarded=true`, while ordinary sends remain false. | `test/features/groups/domain/usecases/send_group_message_use_case_test.dart::GMF-07 forwarded marker survives pre-persist publish and retry payloads` | host application / fake repository, bridge, inbox, retry scheduler | HEAD RED: model/payload field absent -> DB row and every encrypted-inner payload attempt carry true only for forward intent | set all media messages true or drop marker on retry -> GMF-07 red | existing send-use-case test; existing `GROUP_TESTS` entry |
| TC-236-08 | Live incoming group events decode/persist typed true; absent/null/non-bool values safely become false. | `test/features/groups/application/group_message_listener_test.dart::GMF-08 live forwarded marker roundtrips with legacy false fallback` | host application / encrypted event maps and real repository fake | HEAD RED -> exact bool persists; malformed/absent marker does not crash or become true | coerce string `"true"` or default absence to true -> GMF-08 red | existing listener test; add/retain `GROUP_TESTS` registration |
| TC-236-09 | Offline inbox catch-up preserves the same marker/default and dedup/replay behavior. | `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GMF-09 offline forwarded marker matches live decoding and replay dedup` | host application / group offline envelope fixture | HEAD RED -> true survives drain; legacy/malformed false; repeated envelope produces one row | omit offline mapping or bypass existing message-id dedup -> GMF-09 red | existing drain test; existing `GROUP_TESTS` entry |
| TC-236-10 | Discussion bubble renders one “Forwarded” indicator for true and none for legacy/ordinary messages; Info does not reveal origin. | `test/features/groups/presentation/group_conversation_screen_test.dart::GMF-10 forwarded label is truthful and origin minimizing` | host widget / true,false,legacy message fixtures with sentinel origin secrets | HEAD RED: marker/model absent -> label parity is exact and sentinel source identity/id never renders | label every media message or render original-author metadata -> GMF-10 red | existing screen test; existing `GROUP_TESTS` entry |
| TC-236-11 | The optional bool survives the real Go bridge encrypted group envelope, and the existing node delivers it as an encrypted extra without protocol changes. | `integration_test/group_real_crypto_onboarding_test.dart::GMF-11 forwarded marker survives real Go bridge group encryption and legacy absence defaults false`; `go-mknoon/node/pubsub_delivery_test.go::TestGMF11ForwardedMarkerUsesExistingEncryptedExtraPath` | device integration + host two-node Go fixture | HEAD RED: bridge whitelist drops marker -> true returns after real encrypt/decrypt; absent returns false; node extra-delivery test passes without node production edit | drop the bridge option, move marker outside encrypted payload, or alter it in received event -> GMF-11 red | existing integration path is group reliability-sim classified; add exact Go test to `groups` gate command |
| TC-236-12 | Announcement read/write rules and targets remain unchanged; this flow never publishes there even for admins. | `test/features/groups/presentation/group_media_forward_flow_test.dart::GMF-12 discussion forwarding excludes announcements without changing their existing authoring rules` | host widget/application + existing announcement sentinels | HEAD announcement rules GREEN/no forward flow -> announcement never appears as this flow's target; existing admin/non-admin tests remain green | broaden destination predicate or alter announcement `canWrite` -> GMF-12/sentinel red | `GROUP_TESTS`; existing send/wired announcement tests |
| TC-236-13 | Internal Forward is distinct from OS Share and ordinary send; only an explicit accepted forward creates the marker. | `test/features/groups/application/group_media_forward_intent_test.dart::GMF-13 only explicit internal forward sets forwarded provenance` | host unit / ordinary send, OS share, canceled picker, accepted forward intents | HEAD compile RED -> exactly accepted internal forward yields true | infer forwarded from media presence or any share entry point -> GMF-13 red | add file to `GROUP_TESTS` |
| TC-236-14 | The transport boundary is limited to optional encrypted metadata and contains no topic/auth/fanout/retry changes. | `test/features/groups/integration/group_forwarding_transport_boundary_test.dart::GMF-14 forwarding changes only approved marker plumbing` | host source-contract / allowlist of Dart/Go bridge files and forbidden tokens | HEAD compile RED: contract absent -> diff/source allowlist accepts group model/send/listen/db, bridge bool mapping, tests; rejects node production/topic/recipient/key changes | edit `go-mknoon/node` production or introduce new publish/channel method -> GMF-14 red | add file to `GROUP_TESTS`; run `git diff -- go-mknoon/node` as acceptance evidence |

### Test Notes

- TC-236-03 must assert new ciphertext-enabling inputs, not merely multiple uploader call counts. The destination contact/group peer set and every attachment id must be distinct and current.
- TC-236-03O uses a literal direct/group parent-ID collision. A recording repository must reject missing/unresolved ownership; the group destination cannot be proven by a fake that accepts any enum.
- TC-236-06 is deliberately structural host coverage only. Its predecessor is not a hand-built v97 approximation: it includes the v96 owner/bookmark/playback columns, exact indexes and collision rows, then v97 artifacts. TC-236-06D repeats that contract on password-protected `sqflite_sqlcipher`, closes/reopens, and exercises the shared production create/upgrade registry.
- TC-236-11 is the real bridge/device closure claim; TC-236-06D separately closes the production SQLCipher boundary. Host fakes prove mapping logic but cannot replace either boundary.
- The source-contract allowlist in TC-236-14 should be path- and symbol-specific so an unrelated comment cannot satisfy it and a protocol edit cannot hide behind a broad “no new API” assertion.

## Implementation Steps

1. Verify accepted/landed plans 228/230/235/232 and migrations 096-098; stop if the database is not exactly v98, plan 228's shared production registry or owner-aware repository contract is absent, or the contact marker contract differs. Ordinary eligible media can proceed; future private-media restrictions extend the central policy when accepted.
2. Snapshot `git status --short`; add TC-236-01 and run its named causal RED before production edits.
3. Add the pure source/destination forward policy and typed `GroupMediaForwardRequest`; adapt the existing picker/coordinator while narrowing group destinations to `GroupType.chat` and revalidating before upload.
4. Pass the viewer-selected verified source to existing per-target upload/send code. Save every group-destination attachment with `MediaOwnerLane.group`, delegate contact ownership to plan 232, and assert that neither ownership nor source encryption/access metadata crosses the wire.
5. After the complete v96-v98 stop rule passes, add migration 099, bump the app database version to 99, append 099 to plan 228's shared production create/upgrade registry, and map `GroupMessage.isForwarded` with default false. Do not create a new hand-maintained registry/callback chain. Add structural host TC-236-06 and real-engine device TC-236-06D with complete predecessor artifacts.
6. Thread the optional bool through pre-persist/retry, existing encrypted inner group payload, Dart bridge helper, narrow Go bridge params/options, live listener, offline drain, and UI. Do not edit Go node production behavior.
7. Extend the existing Go extra-field test and real bridge integration test; register the pinned Go command in the `groups` gate. Add an exact `classify_path` `group/test` record for `group_forwarded_marker_db_proof_test.dart`; retain the existing exact group record for `group_real_crypto_onboarding_test.dart`.
8. Run focused GREEN, mutation re-reds, SQLCipher migration, Go, group/feature/core, device crypto, announcement preservation, analyzer, and hygiene gates.

## Risks And Blind Spots

- Cross-group confidentiality -> TC-236-03 fails if any source ciphertext/key/nonce/blob/allowed-peer metadata is reused.
- Authorization can change while picker is open -> TC-236-02/12 require send-time revalidation.
- Partial fanout/retry can duplicate messages -> TC-236-05 verifies target-scoped result and retry identity behavior.
- Migration ordering may collide with sibling lanes -> TC-236-06/06D and the execution stop rule reserve v99 only after v96-v98.
- Attachment ownership can be omitted during destination fanout -> TC-236-03O proves explicit group persistence, direct delegation and local-only serialization with a same-ID collision.
- Live/offline schema drift -> TC-236-08/09 use the same typed bool/default matrix.
- Forward provenance can become a privacy leak -> TC-236-10/13 ban original sender/source ids and mark only explicit forwards.
- Lifecycle / derived-state durability: marker is canonical durable state in `group_messages`, not UI-derived; TC-236-06/06D and TC-236-07..10 cover restart paths.
- Sibling-surface consistency: viewer action and destination bubble use the same request/marker semantics; TC-236-01/10/13.
- Destructive-action side effects: N/A — forwarding creates new destination messages and never mutates/deletes the source; TC-236-04 asserts that preservation.
- Invariant re-verification under new transitions: target membership/key and source eligibility are checked again immediately before each upload/send.
- Transport scope creep -> TC-236-11/14 plus `git diff -- go-mknoon/node` prove existing libp2p semantics remain untouched.

## Gate Cadence

- Per-plan closure: run focused Plan-236 tests, the curated `groups` lane gate, `core-host-all` for the migration/registry change, and the exact Go, SQLCipher, and real-bridge proof legs.
- `feature-host-all` and full `host-all` are not individual Plan-236 closure gates.
- Full `host-all` runs once after the ordered migration/forwarding wave (`232 → 235 → 236 → 240`) and once at final rollout closure.

## Acceptance Gates

```bash
# Accepted predecessor contracts plus execution stop rule; do not create v99 until source version is exactly 98
test -f Test-Flight-Improv/228-shared-media-library-bookmark-persistence-tdd-plan.md
test -f Test-Flight-Improv/230-shared-typed-media-viewer-tdd-plan.md
test -f Test-Flight-Improv/232-1to1-received-media-forwarding-tdd-plan.md
test -f Test-Flight-Improv/235-group-received-media-core-actions-tdd-plan.md
rg -n '^const int currentIdentityDatabaseVersion = 98;$' lib/core/database/app_database_version.dart

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
flutter test test/features/groups/domain/usecases/send_group_message_use_case_test.dart --plain-name 'GMF-07'
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name 'GMF-08'
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GMF-09'
flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'GMF-10'
flutter test test/features/groups/integration/group_forwarding_transport_boundary_test.dart

# Plan-228 owner/registry preservation plus structural v99 registration (device SQLCipher proof follows below)
flutter test test/core/database/helpers/media_attachments_db_helpers_test.dart --plain-name 'owner scoped load and delete isolate equal direct and group message ids'
flutter test test/features/conversation/domain/models/media_attachment_test.dart --plain-name 'owner and library state are local only across map and wire serialization'
flutter test test/core/database/integration/full_migration_chain_test.dart --plain-name 'production create and v95 upgrade registries include media library state v96'
flutter test test/core/database/migrations/099_group_messages_is_forwarded_test.dart
flutter test test/core/database/integration/full_migration_chain_test.dart

# Go bridge/node proof; node tests may extend, production must match its recorded baseline
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge ./node -run 'GMF11|GK030' -count=1)

# Registered host families and preservation
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh core-host-all
flutter test test/features/groups/domain/usecases/send_group_message_use_case_test.dart --plain-name 'returns unauthorized for non-admin in announcement group'

# Discover and close both production SQLCipher and real Go bridge boundaries on an available target
flutter devices --machine
./scripts/check_reliability_simulation_discovery.sh --records-tsv | rg '^group\ttest\tintegration_test/group_forwarded_marker_db_proof_test\.dart\t'
./scripts/check_reliability_simulation_discovery.sh --records-tsv | rg '^group\ttest\tintegration_test/group_real_crypto_onboarding_test\.dart\t'
./scripts/run_reliability_simulations.sh group --list | rg 'group_(forwarded_marker_db_proof|real_crypto_onboarding)_test.dart'
flutter test -d "$FLUTTER_DEVICE_ID" integration_test/group_forwarded_marker_db_proof_test.dart --plain-name 'GMF-06D real SQLCipher v99 extends registries and preserves v96 media ownership state'
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
- Boundary being proven: (1) migration 099 extends the shared production create/upgrade registry and preserves complete v96-v98 ownership/state/index/journal artifacts plus forwarded default/mapping/idempotence/reopen behavior on password-protected `sqflite_sqlcipher`; (2) the native Go bridge accepts optional `isForwarded`, places it in already encrypted group payload extras, and returns it through real decryption/event mapping; legacy absence remains false.
- Live availability check: `flutter devices --machine`; no fixed id is assumed. A target without the production SQLCipher plugin blocks TC-236-06D, and a missing compatible bridge framework/target blocks TC-236-11; neither becomes GREEN by proxy.
- Required setup: one simulator/device with the production `sqflite_sqlcipher` plugin and real-Go group crypto fixture, built Go bridge framework, test identity/group keys supplied by `group_real_crypto_onboarding_test.dart`; DB proof creates/deletes its own password-protected files and no external relay account is required.
- Closure role: both device rows are required. Host SQLite cannot prove SQLCipher, and host listener/drain fakes plus Go unit tests cannot prove the native bridge framework.
- `FLUTTER_DEVICE_ID`: sufficient for the one-device bridge case; export it to a live returned id.
- Registration: edit `classify_path` in `scripts/check_reliability_simulation_discovery.sh` to add the exact `integration_test/group_forwarded_marker_db_proof_test.dart` path to the group reliability-device case (`record "group" ... "test"`); keep the existing exact group record for `group_real_crypto_onboarding_test.dart`. Add the DB proof to the group simulator array. Both must appear in records and group `--list`.
- Discovery commands: the two literal `--records-tsv | rg` checks in Acceptance Gates followed by `./scripts/run_reliability_simulations.sh group --list | rg 'group_(forwarded_marker_db_proof|real_crypto_onboarding)_test.dart'`.
- Closure commands: the GMF-06D and GMF-11 `flutter test -d "$FLUTTER_DEVICE_ID" ...` commands in Acceptance Gates.
- Deferred device work: none for this marker boundary; end-to-end multi-recipient UI fanout remains host-deterministic because it uses existing delivery primitives rather than a new transport.

## Execution Interpretation And Done Criteria

- Expected RED: TC-236-01 fails to compile because group media forward policy/request types do not exist.
- Green sentinels: generic share partial-result tests, group media validation, announcement authorization/read-only behavior, and GK030 encrypted-extra delivery remain green.
- Pre-existing dirty tree / known failure: record from execution-time snapshot; do not absorb unrelated changes.
- Execution stop rule: v96-v98 and plans 228/230/232/235 must land before the v99 implementation step; do not steal, renumber, or duplicate their shared migration registry/owner contracts. This known order does not make the plan evidence-gated.
- Environment blocker: no compatible SQLCipher target or bridge framework blocks the corresponding TC-236-06D/11 row and final device closure, not host implementation evidence.
- Scope drift: Go node production, pubsub topics, group membership/key rules, retry protocol, announcement targets, original-author metadata, or shared-ciphertext reuse blocks execution for replanning.

- [ ] Every behavior has a named causal test or justified real-boundary proof.
- [ ] First RED, focused GREEN, representative mutation re-red, and preservation outcomes are recorded.
- [ ] Migration 099 extends the shared production registry exactly once and passes structural host plus real-SQLCipher device idempotence, complete-v98 preservation, legacy-default, explicit-true, reopen, full-chain, and mapping checks.
- [ ] Every destination uses a new attachment/upload/encryption access context and current authorization.
- [ ] Every group-destination attachment persists `MediaOwnerLane.group`; no local owner enters the wire and same-ID direct rows remain isolated.
- [ ] Live, offline, retry, repository, and UI marker semantics agree; absence/malformed values are false.
- [ ] No original sender/source metadata propagates and OS Share never sets the marker.
- [ ] Go node production status/binary diff exactly matches the pre-execution baseline (node tests may extend); Go bridge and real device crypto proofs pass.
- [ ] Announcement sentinels, registered group/feature/core gates, analyzer, and hygiene pass.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `flutter test test/features/groups/application/group_media_forward_policy_test.dart --plain-name 'GMF-01 only eligible incoming discussion media can forward'`.
- Preservation commands: `flutter test test/features/conversation/domain/models/media_attachment_test.dart --plain-name 'owner and library state are local only across map and wire serialization'`, `flutter test test/core/database/integration/full_migration_chain_test.dart --plain-name 'production create and v95 upgrade registries include media library state v96'`, and `flutter test test/features/groups/domain/usecases/send_group_message_use_case_test.dart --plain-name 'returns unauthorized for non-admin in announcement group'`.
- Harness registration: add new group tests to `GROUP_TESTS`; add exact `GOTOOLCHAIN=go1.25.0 go test ./bridge ./node -run 'GMF11|GK030' -count=1` execution to the `groups` gate; retain the exact real-crypto group classification and add an exact `classify_path` group/test record plus simulator-array entry for `group_forwarded_marker_db_proof_test.dart`. Record/compare node-production-only status and binary diff while excluding allowed `*_test.go` changes.
- Migration: exclusively v99 `group_messages.is_forwarded`; append to plan 228's shared production registry after a complete v98 predecessor containing v96 owner/state/index artifacts and plan 235's v98 `group_media_deletion_journal`; announcement plan 240 may reuse the column but not change this migration's semantics.
- Boundary closure: host per-target encryption/access assertions + structural host migration + real-SQLCipher device migration/full-chain + two-node Go extra delivery + single-device real-Go-bridge encrypted marker proof.
- Unresolved evidence: none; predecessor order is an execution stop rule and unavailable device is an environment blocker.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | revised plan-228 owner/registry dependency recorded; rebased to v99 after plan 235 claimed v98 | plans 228/230/232/235 and complete migrations v96-v98 must land before v99 step | first causal RED, then verify owner contract and shared registry predecessor |
