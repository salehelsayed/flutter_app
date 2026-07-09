# 232 - 1:1 Received Media Forwarding

Status: execution-ready
Type: New Feature
Spec: free-text intent — forward incoming direct-chat images/videos to selected contacts or groups with editable captions, multi-target fan-out, dedup, and fresh encryption
Classification: implementation-ready
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | `graphify-arch` query/path; share picker/screen/route/coordinator and tests; `ShareIntent`; direct message/payload/send/receive/dedup code and tests; media encryption round trip; DB version/migrations; simulator discovery | Existing picker/caption/multi-target and direct dedup/encryption primitives are usable. Missing pieces are an internal forward draft/launcher, provenance threading, UI, and local marker persistence. No Go/libp2p behavior change is justified. | Land after DB v96; add direct-forward RED tests and DB v97 proof before production edits. |

## Problem And Evidence

- Behavior to improve: a user must be able to forward a received 1:1 image/video (the current viewer item, or all visual attachments from the message bubble) to one or more eligible contacts/groups, preview the selection, and keep/remove/edit its caption.
- Impact: users currently must export and reattach media manually, losing in-app flow and increasing duplicate/error risk.
- Confirmed picker mechanism: `ShareTargetPickerScreen` already accepts contacts, groups, independent selected-id sets, editable `captionController`, file paths, and one Send action (`lib/features/share/presentation/screens/share_target_picker_screen.dart:19-51`, `:63-70`).
- Confirmed target mechanism: `ShareTargetPickerWired` loads active contacts and writable groups and stores selections in sets (`share_target_picker_wired.dart:107-120`, `:142-162`); `ShareTargetSelection.key` namespaces contact/group ids (`share_target_selection.dart:27-43`).
- Confirmed fan-out mechanism: `DefaultShareBatchDeliveryCoordinator.deliver` processes shared media once and iterates each target at `share_batch_delivery_coordinator.dart:163-217`. Its contact leg creates a fresh attachment id and runs `uploadMedia` per target before `sendChatMessage` (`:279-357`); its group leg intentionally uses existing `sendGroupMessage` (`:382-485`).
- Confirmed encryption/dedup mechanism: `sendChatMessage` accepts a propagated `dedupKey` (`send_chat_message_use_case.dart:241-265`), defaults normal sends to their own fresh id, and writes the key inside the encrypted v2 payload (`:414-490`). The receiver dedups a re-minted forward by sender/contact/key and re-mints the fresh-id receipt (`handle_incoming_chat_message_use_case.dart:419-447`).
- Confirmed preservation coverage: `two_user_message_exchange_test.dart:1298-1397` proves forward re-mint dedup over the v2 fake transport and explicitly records that no forward UI exists; `one_to_one_media_encryption_round_trip_test.dart:208-291` proves attachment ciphertext/key metadata round-trip.
- Confirmed current gap: `ShareIntent` models only external text/files and has no internal provenance (`lib/core/services/share_intent_model.dart:1-55`); neither the direct conversation nor viewer exposes Forward; `ConversationMessage`/`MessagePayload` have no forwarded marker.
- Existing coverage: picker tests prove caption edits, target selection, partial failures, and close behavior; coordinator tests prove one preprocessing pass, result truthfulness, and existing group delivery. None threads a stored direct message's source dedup key or renders a Forwarded marker.
- Missing coverage: source-item eligibility, launcher wiring, internal provenance, selection dedup under forwarding, fresh per-target attachment crypto, DB/wire marker durability, retry/reopen rendering, and explicit Go boundary preservation.
- Refuted findings: a new Go/libp2p forward command is not needed. Forwarded content is a normal fresh direct/group send through existing use cases; direct-only provenance rides the already-encrypted Dart payload. Go transport remains opaque to it.
- Refuted findings: receiver dedup does not need a new algorithm. The existing tier-2 `dedupKey` contract was built for a forward that re-mints id/timestamp.
- Unresolved findings: N/A for the direct-recipient contract. Group-destination marker/dedup behavior is deliberately owned by plan 236 rather than guessed here.
- Affected production, test, and gate files: new internal forward draft/launcher; `ShareIntent`; share coordinator/picker; direct message/payload/send/receive/model/render code; migration 097/main/version; focused share/conversation/migration/device tests; 1:1 gate arrays and simulator discovery.

## Scope Contract And Guard

In scope:
- Add `ForwardProvenance` to `ShareIntent` as an optional internal-only value containing only `dedupKey`; external OS intents keep it null. Presence means the direct destination message is forwarded. Never include original sender identity, username, conversation id, or caption history.
- Build provenance with `sourceMessage.dedupKey ?? sourceMessage.id`; resolve only completed, locally available visual attachments. Viewer forwards the current attachment; bubble Forward includes all eligible visual attachments from that message.
- Inject one launcher callback into the direct conversation layer so it opens the existing `buildShareTargetPickerRoute` with the internal `ShareIntent`; keep broad contact/group dependencies outside the pure screen.
- Keep the existing picker preview/search/multi-select/partial-failure behavior and initialize its caption field from the source message text; empty, edited, or replaced caption is authoritative.
- On a direct contact target, pass the propagated dedup key and `isForwarded: true` into `sendChatMessage`; every target receives a fresh message id, timestamp, attachment/blob id, and encryption material.
- Add local/wire `isForwarded` (legacy absence = false) to `MessagePayload` and `ConversationMessage`; the field rides v1 compatibility JSON and the encrypted v2 inner payload, never the v2 outer envelope.
- Reserve DB v97 after plan 228's DB v96: `messages.is_forwarded INTEGER NOT NULL DEFAULT 0 CHECK (is_forwarded IN (0,1))`, idempotent PRAGMA guard, model map/copy support, onCreate/onUpgrade wiring, and full-chain coverage.
- Render a localized marker on direct forwarded rows without identifying or linking the original sender.

Must preserve:
- Multi-target selections remain unique and failed-only retry selection remains truthful -> existing share picker/coordinator tests plus TC-232-03/04.
- Fresh per-target media upload/encryption and ciphertext-only relay custody -> TC-232-06 plus existing 1:1 encryption sentinel.
- Tier-2 dedup's sender/contact discriminator, fresh receipt, and genuine-repeat behavior -> existing `two_user_message_exchange_test.dart` sentinel plus TC-232-05.
- External inbound share handling has null provenance and unchanged behavior -> `test/features/share/integration/share_to_contact_smoke_test.dart`; `GREEN sentinel`.
- Existing group target send permissions, allowed-peer encryption, offline queue, retry, and background-task lifecycle -> TC-232-13.

Hard `Do not`:
- Do not edit `go-mknoon/`, `go-relay-server/`, P2P routing/races, inbox protocols, relay media framing, group publish/auth/retry, or transport timeouts.
- Do not reuse the source attachment id/blob id/key/nonce or send decrypted source key material to another recipient.
- Do not expose original sender identity or dedup key in UI, diagnostics, the v2 outer envelope, native share metadata, or group payloads.
- Do not forward pending, missing, evicted, integrity-failed, expired, or policy-protected media; offer the appropriate download/unavailable path instead.
- Do not add `is_forwarded` to `group_messages` or `GroupMessagePayload` in this plan.
- Do not reinterpret external OS Share as internal Forward; they remain separate actions and flows.

Deferred / accepted difference:
- A group destination receives the forwarded content/caption through the existing coordinator, but group marker persistence/rendering and group-specific dedup are owned by `Test-Flight-Improv/236-group-received-media-forwarding-tdd-plan.md` (DB v98 after this plan's v97). Until 236 lands, direct-to-group delivery is allowed but must not fake a marker.
- Announcement-source/destination forwarding policy is owned by `Test-Flight-Improv/240-announcement-received-media-forwarding-tdd-plan.md`.
- Multi-message/multi-source forwarding from Shared Media selection belongs to evidence-gated `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan.md`; this plan owns one source message/current viewer item per launch.

Dependencies:
- Plan 228 must land first and leave production at DB v96; this plan exclusively reserves DB v97.
- `Test-Flight-Improv/230-shared-typed-media-viewer-tdd-plan.md` supplies typed current-item action callbacks.
- Existing `ShareTargetPickerWired`, `DefaultShareBatchDeliveryCoordinator`, direct `dedupKey`, upload encryption, and send/retry contracts.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-232-01 | A received direct visual message builds an eligible forward draft with exact paths, caption, and `dedupKey ?? id`; viewer chooses current item while bubble chooses all visual siblings. | `test/features/conversation/application/build_received_media_forward_test.dart::builds current-item and whole-message forward drafts without provenance leakage` | application host / temp files and table message fixture | HEAD compile RED: forward draft/use case absent -> expected item set, caption, and internal key; no sender identity in draft serialization/diagnostics | use source id even when a dedup key exists, include audio, or include sender identity -> TC-232-01 red | `flutter test test/features/conversation/application/build_received_media_forward_test.dart --plain-name 'builds current-item and whole-message forward drafts without provenance leakage'`; AUTO + add file to `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS` |
| TC-232-02 | Missing/pending/evicted/integrity-failed/protected media never opens the picker or starts delivery. | `test/features/conversation/application/build_received_media_forward_test.dart::ineligible source media fails closed before the picker` | application host / table fixture + launcher spy | HEAD compile RED -> typed reason and zero launcher/coordinator calls for every state | treat any non-null path as eligible -> TC-232-02 red | `flutter test test/features/conversation/application/build_received_media_forward_test.dart --plain-name 'ineligible source media fails closed before the picker'`; AUTO + both 1:1 arrays |
| TC-232-03 | Direct conversation Forward opens the existing picker once with media preview and an editable/removable source caption. | `test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart::forward action launches existing picker with editable source caption` | widget host / injected launcher and fake typed viewer | HEAD causal RED: no Forward action/launcher -> exact files/provenance reach launcher; edited/empty caption is delivered, original message is unchanged | pass stale page item, ignore edited caption, or mutate source text -> TC-232-03 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart`; AUTO + add file to both 1:1 arrays |
| TC-232-04 | Contacts/groups are multi-selectable exactly once per namespaced key; stale/unwritable groups are removed before delivery and partial failure retains only failed targets. | `test/features/share/presentation/share_target_picker_wired_test.dart::internal forward dedups mixed targets and retains failed-only retry selection` | widget host / existing picker harness + recording coordinator | HEAD partial RED: generic selection works but no internal provenance path -> one unique delivery per selected key, filtered group absent, failed-only selection preserved | replace sets with lists or skip pre-send group revalidation -> TC-232-04 red | `flutter test test/features/share/presentation/share_target_picker_wired_test.dart --plain-name 'internal forward dedups mixed targets and retains failed-only retry selection'`; AUTO (`feature-host-all`) + add/retain file in both 1:1 arrays |
| TC-232-05 | Every direct target gets a fresh id/timestamp while the source dedup key and forwarded marker reach `sendChatMessage`. | `test/features/share/application/share_batch_delivery_coordinator_test.dart::direct forward remints identity and propagates source dedup plus marker per target` | application host / two contacts, recording send/upload seams | HEAD causal RED: `ShareIntent` has no provenance and coordinator cannot pass marker/key -> two fresh sends carry the shared source key and `isForwarded=true` | omit dedup key, reuse one message id, or drop marker -> TC-232-05 red | `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart --plain-name 'direct forward remints identity and propagates source dedup plus marker per target'`; AUTO (`feature-host-all`) + add file to both 1:1 arrays |
| TC-232-06 | Media preprocessing happens once, but each direct target gets a new blob id and independently generated encryption key/nonce; source bytes/key metadata remain unchanged. | `test/features/share/application/share_batch_delivery_coordinator_test.dart::multi-target media forward preprocesses once and encrypts/uploads separately per contact` | `GREEN sentinel` strengthened / host temp files + content-transforming bridge | Existing external batch path is expected GREEN for preprocess-once/per-target upload -> remains GREEN for internal provenance with distinct ids/keys and no plaintext upload | hoist one uploaded attachment across targets or reuse prepared key/nonce -> TC-232-06 red | `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart --plain-name 'multi-target media forward preprocesses once and encrypts/uploads separately per contact'`; AUTO + both 1:1 arrays |
| TC-232-07 | `isForwarded` defaults false for legacy input, round-trips v1/v2 inner JSON, and is absent with dedup/original-sender data from the encrypted outer envelope. | `test/features/conversation/domain/models/message_payload_test.dart::forward marker is legacy-safe inner-only and carries media plus dedup` | domain host / payload codecs + fake v2 envelope | HEAD causal RED: field absent -> legacy false; true survives both codecs; v2 outer exposes only existing routing fields | put marker/key in outer envelope or default missing to true -> TC-232-07 red | `flutter test test/features/conversation/domain/models/message_payload_test.dart --plain-name 'forward marker is legacy-safe inner-only and carries media plus dedup'`; AUTO (`feature-host-all`) + retain file in both 1:1 arrays |
| TC-232-08 | DB v97 adds `is_forwarded` with false default/check, preserves v96 rows, maps/copies the field, and is run-twice idempotent. | `test/core/database/migrations/097_direct_message_forwarded_test.dart::v96 to v97 preserves messages and adds forwarded state idempotently` | migration host structural SQLite + real SQLCipher closure in TC-232-09 | HEAD RED: migration/column/version absent -> PRAGMA/default/check, before/after rows, map round trip, run twice, and version 97 pass | omit default/check/PRAGMA guard or bump version without both registry arms -> TC-232-08 red | `flutter test test/core/database/migrations/097_direct_message_forwarded_test.dart`; AUTO (`test/core/**`) + add file to both 1:1 arrays |
| TC-232-09 | The production-style encrypted v96->v97 chain, encrypted-inner receive, close/reopen, and second migration run preserve the forwarded marker and source key in real SQLCipher. | `integration_test/direct_forwarded_marker_sqlcipher_proof_test.dart::v96 to v97 forwarded marker survives encrypted receive close reopen and migration rerun` | Android+iOS device proof / real `sqflite_sqlcipher`, real repository helpers, fake message crypto only | HEAD device RED: v97 and marker absent -> on each platform the encrypted DB upgrades, proves encrypted PRAGMA/before-after rows, receives a v2 marker, closes/reopens, returns `isForwarded=true`, preserves rows, and reruns migration | skip onUpgrade/onCreate, drop receive reconstruction, omit map field, or open plaintext -> TC-232-09 red | `flutter test integration_test/direct_forwarded_marker_sqlcipher_proof_test.dart -d "$ANDROID_DEVICE_ID"` and `-d "$IOS_DEVICE_ID"`; new dedicated manual/device file with one exact `1to1` discovery record |
| TC-232-10 | A direct forwarded row renders one localized Forwarded marker with no original-sender attribution; ordinary rows render none. | `test/features/conversation/presentation/widgets/letter_card_test.dart::direct forwarded marker is attribution-free and legacy rows stay unmarked` | widget host / incoming/outgoing direct rows | HEAD causal RED: model/widget marker absent -> marker count and semantics pass in en/de/ar; sender/source key absent | render marker for every media row or display original sender/id -> TC-232-10 red | `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart --plain-name 'direct forwarded marker is attribution-free and legacy rows stay unmarked'`; existing `ONE_TO_ONE_TESTS`; retain/add file in `ONE_TO_ONE_HOST_TESTS` |
| TC-232-11 | Failed/queued forwarded direct sends retain marker, dedup key, fresh id, and encrypted wire envelope through retry and reopen. | `test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart::queued forward retries without losing marker key or reminting identity` | host integration / fake inbox failure then recovery + repository reopen | HEAD compile RED: no forward delivery/marker -> original forward row transitions once and receiver gets one marked row; retry reuses id/envelope | rebuild forward as a normal send or mint a new id/key on retry -> TC-232-11 red | `flutter test test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart`; AUTO + add file to both 1:1 arrays |
| TC-232-12 | Existing tier-2 receiver dedup still drops repeated forwards by source key, re-mints the fresh-id receipt, and preserves a genuine repeat. | `test/features/conversation/integration/two_user_message_exchange_test.dart::a forward (copied dedupKey, re-minted id+timestamp) does not double-card on the receiver, and a genuine repeat still persists` | `GREEN sentinel` / existing two-user v2 fake transport | GREEN on HEAD -> remains GREEN after real forward UI/coordinator threading | hash content, drop sender/contact discriminator, or fail to pass provenance key -> sentinel red | `flutter test test/features/conversation/integration/two_user_message_exchange_test.dart --plain-name 'a forward (copied dedupKey, re-minted id+timestamp) does not double-card on the receiver, and a genuine repeat still persists'`; existing both 1:1 arrays |
| TC-232-13 | A selected group target continues through the existing writable-group/background-task/upload/send path with no direct-marker or transport mutation. | `test/features/share/application/share_batch_delivery_coordinator_test.dart::group forward target preserves existing publish permissions queue and background-task contract` | `GREEN sentinel` / existing fake group repositories/bridge | Existing group share behavior GREEN -> same content/caption is delivered; direct `isForwarded` is not passed to group payload before plan 236 | call direct `sendChatMessage`, add group marker here, or bypass writable-group check -> TC-232-13 red | `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart --plain-name 'group forward target preserves existing publish permissions queue and background-task contract'`; AUTO; run `./scripts/run_test_gates.sh groups` as destination preservation |
| TC-232-14 | The direct forwarding slice changes no Go/libp2p/relay behavior and uses only existing Dart send/upload contracts. | `test/features/conversation/application/direct_media_forward_transport_boundary_test.dart::direct forwarding imports no go bridge routing inbox or group payload implementation` | host source-contract test | HEAD compile RED: target sources absent -> forbidden imports/calls and Go diff paths are unchanged from the recorded dirty-tree baseline | add a P2P command, Go edit dependency, or relay-forward API -> TC-232-14 red | `flutter test test/features/conversation/application/direct_media_forward_transport_boundary_test.dart`; AUTO + add file to both 1:1 arrays; baseline status+binary-diff comparison below required for Go/relay paths |
| TC-232-15 | Forward action, caption, target count, marker, and partial-result strings are localized and accessible in Arabic/German without overflow. | `test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart::forward flow is localized RTL-safe and semantics-labelled` | widget host / 320x568 de/ar fixtures | HEAD causal RED: action/marker copy absent -> all keys readable/reachable and no exception | hardcode English or use a fixed non-scrollable action surface -> TC-232-15 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart --plain-name 'forward flow is localized RTL-safe and semantics-labelled'`; AUTO + both 1:1 arrays; existing direct ARB parity command |

### Test Notes

- TC-232-05 discriminates source provenance from normal sends: the two destination messages must have different ids/timestamps but the same propagated source key. A normal repeated send control must carry its own fresh key.
- TC-232-06 asserts distinct blob ids and key/nonces, not merely two `uploadMedia` calls. The source's stored encryption metadata must remain byte-equal before/after.
- TC-232-09 uses real SQLCipher but does not claim real ML-KEM/AES behavior; existing encryption tests remain sentinels. No relay or two-device run is required for a local schema/wire-marker contract.

## Implementation Steps

1. Snapshot `git status --short`; verify plan 228 has landed as DB v96 and migration id 097 is still free. Add TC-232-01..08 and TC-232-10..15 before production edits.
2. Add `ForwardProvenance`/draft building and the injected direct-conversation launcher; adapt plan-230 viewer and bubble Forward actions. Stop-if media must be recovered through a new transport path.
3. Thread optional provenance through `ShareIntent`, picker, and contact coordinator; keep the group branch unchanged and provenance-free until plan 236.
4. Add `isForwarded` to direct payload/model/send/receive/retry/render paths, with legacy false and v2-inner-only privacy.
5. Add DB v97 migration, both production registry arms, model mapping, full-chain test, and the real-SQLCipher TC-232-09 device case. Stop-if HEAD is not v96 or another plan owns v97.
6. Add l10n, register new headline tests in both 1:1 arrays and the dedicated SQLCipher proof under exactly `1to1`; run focused GREEN, sentinels, group-destination preservation, device proof, mutations, and hygiene.

## Risks And Blind Spots

- Reusing source encryption material would leak recipient-scoped custody -> TC-232-06.
- Provenance could leak sender identity or a linkable key outside encryption -> TC-232-01/07/10.
- A retry could remint identity and defeat dedup/status convergence -> TC-232-11/12.
- Lifecycle / derived-state durability: TC-232-09/11 close and reopen database/repository state.
- Sibling-surface consistency: TC-232-01/03 compare viewer-current versus bubble-all behavior; external OS Share remains separate.
- Destructive-action side effects: N/A — forwarding creates new rows/files and must not mutate the source; TC-232-01/03/06 assert source preservation.
- Invariant re-verification under new transitions: picker retries revalidate writable groups and failed-only selections in TC-232-04; queued resend reuses its stored envelope in TC-232-11.
- Cross-lane marker parity is intentionally staged -> plan 236 owns group DB v98, plan 240 owns announcement policy.

## Acceptance Gates

```bash
# Snapshot and migration precondition
git status --short
git status --short --untracked-files=all -- go-mknoon go-relay-server > /tmp/plan-232-go-relay-status.before
git diff --binary -- go-mknoon go-relay-server > /tmp/plan-232-go-relay-diff.before
rg -n '^const int currentIdentityDatabaseVersion = 96;$' lib/core/database/app_database_version.dart

# First causal RED; expect non-zero because forward draft/provenance types are absent
flutter test test/features/conversation/application/build_received_media_forward_test.dart --plain-name 'builds current-item and whole-message forward drafts without provenance leakage'

# Focused host GREEN; expect exit 0 and zero failed tests
flutter test test/features/conversation/application/build_received_media_forward_test.dart
flutter test test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart
flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart
flutter test test/features/share/presentation/share_target_picker_wired_test.dart
flutter test test/features/conversation/domain/models/message_payload_test.dart
flutter test test/core/database/migrations/097_direct_message_forwarded_test.dart
flutter test test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart
flutter test test/features/conversation/application/direct_media_forward_transport_boundary_test.dart

# Preservation/named gates; expect exit 0 and registered target selection
flutter test test/features/conversation/integration/two_user_message_exchange_test.dart --plain-name 'a forward (copied dedupKey, re-minted id+timestamp) does not double-card on the receiver, and a genuine repeat still persists'
flutter test test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart
flutter test test/features/share/integration/share_to_contact_smoke_test.dart
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh 1to1 --list
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh core-host-all
./scripts/run_host_test_gates.sh feature-host-all

# Real SQLCipher closure; each physical-platform run exits 0 and preserves the encrypted DB
flutter devices --machine
test -n "$ANDROID_DEVICE_ID"
test -n "$IOS_DEVICE_ID"
flutter test integration_test/direct_forwarded_marker_sqlcipher_proof_test.dart -d "$ANDROID_DEVICE_ID"
flutter test integration_test/direct_forwarded_marker_sqlcipher_proof_test.dart -d "$IOS_DEVICE_ID"
./scripts/check_reliability_simulation_discovery.sh --records-tsv | rg '1to1.*direct_forwarded_marker_sqlcipher_proof_test.dart'

# Scope/hygiene
git status --short --untracked-files=all -- go-mknoon go-relay-server | cmp -s - /tmp/plan-232-go-relay-status.before
git diff --binary -- go-mknoon go-relay-server | cmp -s - /tmp/plan-232-go-relay-diff.before
flutter analyze
git diff --check
```

## Device/Relay Proof Profile

- Profile: single-device SQLCipher proof repeated on Android and iOS; no relay and no second user/device are required.
- Boundary being proven: the real `sqflite_sqlcipher` plugin applies DB v97 over an encrypted v96 database and persists `is_forwarded` through encrypted-inner receive, close/reopen, and idempotent rerun. Host SQLite does not substitute for this at-rest boundary.
- Live availability check: `flutter devices --machine` on 2026-07-09 observed at least one physical Android and physical iOS device; availability and selected IDs must be rechecked at execution.
- Required setup: plan 228 DB v96 implemented; physical device unlocked; per-test temporary encrypted database/password; no relay credentials, peer, or media server.
- Closure role: required migration/persistence closure only; host tests own picker/dedup/encryption-decision behavior.
- `$ANDROID_DEVICE_ID` and `$IOS_DEVICE_ID`: required explicitly so the two platform runs cannot accidentally target the same/default device.
- Registration: add only `integration_test/direct_forwarded_marker_sqlcipher_proof_test.dart` to the appropriate manual/device inventory and give that exact path one `1to1` discovery record. Do not add `1to1` classification to the broad mixed `migration_database_sqlcipher_capability_test.dart`.
- Discovery command: `./scripts/check_reliability_simulation_discovery.sh --records-tsv | rg '1to1.*direct_forwarded_marker_sqlcipher_proof_test.dart'` -> exactly one 1:1 record for the dedicated path.
- Closure command: the two platform-specific `flutter test ... --plain-name ...` commands above -> exit 0, zero failed tests, close/reopen preserved row, second migration run succeeded.
- Deferred device work: no real-relay/real-crypto campaign; existing media encryption and two-user host integrations are the proportionate sentinels because this plan changes no cryptographic or transport algorithm.

## Execution Interpretation And Done Criteria

- Expected RED: TC-232-01 compile-fails because internal forward draft/provenance APIs do not exist.
- Green sentinel: existing direct dedup, direct media encryption round trip, inbound external share, and group share tests remain green.
- Pre-existing dirty tree / known failure: record at execution start; unrelated current changes in messaging/push/graph outputs are not plan scope.
- Environment blocker: losing one physical platform blocks TC-232-09 closure on that platform; it does not justify replacing the proof with host SQLite.
- Scope drift: any Go/relay/P2P/group-payload edit, v97 collision, original-sender attribution, or source-key reuse blocks completion.

- [ ] Every behavior has a named causal test or explicit sentinel.
- [ ] DB v97 has PRAGMA/default/check, before/after, run-twice, onCreate/onUpgrade, full-chain, and Android+iOS SQLCipher evidence.
- [ ] Forward source, caption, multi-target, failed-only retry, marker, dedup, and fresh per-target encryption tests pass.
- [ ] New host tests are selected by both 1:1 arrays; the device test is discoverable under `1to1`.
- [ ] Representative provenance, id/key reuse, marker-drop, retry-remint, and transport-boundary mutations re-red.
- [ ] `flutter analyze` has no new issues; `git diff --check` and Go/relay no-diff guard are clean.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `flutter test test/features/conversation/application/build_received_media_forward_test.dart --plain-name 'builds current-item and whole-message forward drafts without provenance leakage'`.
- Preservation command: `flutter test test/features/conversation/integration/two_user_message_exchange_test.dart --plain-name 'a forward (copied dedupKey, re-minted id+timestamp) does not double-card on the receiver, and a genuine repeat still persists'`.
- Manual registration: add new direct-forward host files to both 1:1 arrays; add the dedicated `direct_forwarded_marker_sqlcipher_proof_test.dart` to the manual/device inventory with one exact `1to1` discovery record. No new group array entry for direct-owned tests and no broad SQLCipher-file reclassification.
- Migration: DB v97 `messages.is_forwarded`; host structural migration test plus required Android/iOS real-SQLCipher full-chain/reopen proof.
- Boundary closure: two single-device SQLCipher runs; no relay/real-network/Go proof because those behaviors are unchanged.
- Unresolved evidence: none. Group marker/dedup is an explicit deferred owner (plan 236), not an unowned gap in this direct-recipient plan.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plan and DB v96 dependency | contract extraction |
