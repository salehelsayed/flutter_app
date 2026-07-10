# 232 - 1:1 Received Media Forwarding

Status: accepted
Type: New Feature
Spec: free-text intent — forward incoming direct-chat images/videos to selected contacts or groups with editable captions, multi-target fan-out, dedup, and fresh encryption
Classification: implemented and independently QA-accepted
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | `graphify-arch` query/path; share picker/screen/route/coordinator and tests; `ShareIntent`; direct message/payload/send/receive/dedup code and tests; media encryption round trip; DB version/migrations; simulator discovery | Existing picker/caption/multi-target and direct dedup/encryption primitives are usable. Missing pieces are an internal forward draft/launcher, provenance threading, UI, and local marker persistence. No Go/libp2p behavior change is justified. | Land after DB v96; add direct-forward RED tests and DB v97 proof before production edits. |
| 2026-07-10 | Planner | revised plan 228 DB v96 owner/replay/index/production-registry contract; plan 229 evicted contract; forward source and destination save seams | DB v97 must extend the one shared production create/upgrade registry, its predecessor fixtures must contain all v96 owner/state/index artifacts, and direct/group destination saves must pass their exact owner. | Strengthen migration, source eligibility, destination ownership and retry-preservation fixtures before execution. |
| 2026-07-10 | Counterexample Reviewer / Replanner | receiver dedup SQL/handler, real share contact leg, direct edit/render seams, private-media model gap, production registries/opener, gate/discovery scripts | Source-message dedup provenance is unsafe across separate forward actions. The receiver algorithm remains valid if each explicit action mints one stable operation token. Real contact-leg, edit/render, migration, registration and availability gates need bounded causal tightening. | Execute the revised operation-scoped contract below; defer private/expiry eligibility to plan 234. |

## Problem And Evidence

- Behavior to improve: a user must be able to forward a received 1:1 image/video (the current viewer item, or all visual attachments from the message bubble) to one or more eligible contacts/groups, preview the selection, and keep/remove/edit its caption.
- Impact: users currently must export and reattach media manually, losing in-app flow and increasing duplicate/error risk.
- Confirmed picker mechanism: `ShareTargetPickerScreen` already accepts contacts, groups, independent selected-id sets, editable `captionController`, file paths, and one Send action (`lib/features/share/presentation/screens/share_target_picker_screen.dart:19-51`, `:63-70`).
- Confirmed target mechanism: `ShareTargetPickerWired` loads active contacts and writable groups and stores selections in sets (`share_target_picker_wired.dart:107-120`, `:142-162`); `ShareTargetSelection.key` namespaces contact/group ids (`share_target_selection.dart:27-43`).
- Confirmed fan-out mechanism: `DefaultShareBatchDeliveryCoordinator.deliver` processes shared media once and iterates each target at `share_batch_delivery_coordinator.dart:163-217`. Its contact leg creates a fresh attachment id and runs `uploadMedia` per target before `sendChatMessage` (`:279-357`); its group leg intentionally uses existing `sendGroupMessage` (`:382-485`).
- Confirmed encryption/dedup mechanism: `sendChatMessage` accepts a propagated `dedupKey` (`send_chat_message_use_case.dart:241-265`), defaults normal sends to their own fresh id, and writes the key inside the encrypted v2 payload (`:414-490`). The receiver dedups by sender/contact/key and re-mints the fresh-id receipt (`handle_incoming_chat_message_use_case.dart:419-447`). That algorithm is reusable, but the key must identify one explicit forward operation rather than the source message.
- Confirmed dedup defect: `dbExistsMessageByDedupKey` compares only `(contact_peer_id,sender_peer_id,dedup_key)` and the handler drops a match before comparing caption/media. Reusing `sourceMessage.dedupKey ?? sourceMessage.id` across later explicit forwards can suppress a legitimate second attachment selection or caption.
- Confirmed preservation coverage: `two_user_message_exchange_test.dart:1298-1397` proves re-minted-id delivery dedup but currently locks the unsafe source-key interpretation; it must become the operation-A/operation-B causal row below. `one_to_one_media_encryption_round_trip_test.dart:208-291` remains the attachment ciphertext/key sentinel.
- Confirmed current gap: `ShareIntent` models only external text/files and has no internal provenance (`lib/core/services/share_intent_model.dart:1-55`); neither the direct conversation nor viewer exposes Forward; `ConversationMessage`/`MessagePayload` have no forwarded marker.
- Confirmed dependency change: plan 228 makes attachment save/load/delete/failure transitions require `MediaOwnerLane.direct/group`, retains ambiguous legacy rows as `unresolved`, and extracts one production migration registry used by create, upgrade and tests. Plan 232 must extend those seams rather than add new callbacks in `main.dart`.
- Existing coverage: picker tests prove caption edits, target selection, partial failures, and close behavior; coordinator tests prove one preprocessing pass, result truthfulness, and existing group delivery. None threads operation-scoped forward provenance or renders a Forwarded marker.
- Missing coverage: operation-scoped dedup across distinct actions, direct-owner/incoming source eligibility and unresolved exclusion, launcher wiring, production contact-leg provenance, exact direct/group destination ownership, fresh per-target attachment crypto, complete-v96 predecessor and shared-registry DB/wire marker durability, downgrade preservation, edit/retry/render propagation, exact dual-array registration, l10n integrity, external-share negative, and explicit Go boundary preservation.
- Refuted findings: a new Go/libp2p forward command is not needed. Forwarded content is a normal fresh direct/group send through existing use cases; direct-only provenance rides the already-encrypted Dart payload. Go transport remains opaque to it.
- Refuted prior plan claim: a source-message key is not a safe forward-operation identity. The existing receiver algorithm and encrypted-inner `dedupKey` field remain sufficient once the sender mints one random token per explicit forward action and reuses it only for that action's fan-out/retry/redelivery.
- Unresolved findings: N/A for the direct-recipient contract. Group-destination marker/dedup behavior is deliberately owned by plan 236 rather than guessed here.
- Affected production, test, and gate files: new internal forward draft/launcher; `ShareIntent`; share coordinator/picker; direct message/payload/send/receive/model/render code; migration 097/main/version; focused share/conversation/migration/device tests; 1:1 gate arrays and simulator discovery.

## Scope Contract And Guard

In scope:
- Add `ForwardProvenance` to `ShareIntent` as an optional internal-only value containing only `operationDedupKey`; external OS intents keep it null. Presence means the direct destination message is forwarded. Never include source message/dedup identity, original sender, username, conversation id, or caption history.
- Mint one random operation token when each explicit Forward action begins. Keep that token in the draft/`ShareIntent` across the action's multi-target fan-out and failed-only picker retry; queued wire-envelope retry/redelivery reuses it. Reopening Forward later from the same source mints a new token, including current-item versus later bubble-all or edited-caption actions.
- Resolve through `MediaOwnerLane.direct` and require an incoming, completed, locally available visual source. Outgoing, missing or `unresolved` ownership fails before picker/delivery. Viewer forwards the current attachment; bubble Forward includes all eligible visual attachments from that message.
- Inject one launcher callback into the direct conversation layer so it opens the existing `buildShareTargetPickerRoute` with the internal `ShareIntent`; keep broad contact/group dependencies outside the pure screen.
- Keep the existing picker preview/search/multi-select/partial-failure behavior and initialize its caption field from the source message text; empty, edited, or replaced caption is authoritative.
- On a direct contact target, pass the operation token and `isForwarded: true` into the real `sendChatMessage` leg; every new attachment save/transition carries `MediaOwnerLane.direct`, and every target receives a fresh message id, timestamp, attachment/blob id, and encryption material. The existing group branch passes `MediaOwnerLane.group`; announcements remain group-backed.
- `editChatMessage` must preserve the original row's operation token and forwarded marker in its encrypted edit payload and persisted sender/receiver rows. An edit is the same logical destination message, not a new forward action.
- Add local/wire `isForwarded` (legacy absence = false) to `MessagePayload` and `ConversationMessage`; the field rides v1 compatibility JSON and the encrypted v2 inner payload, never the v2 outer envelope.
- Reserve DB v97 after plan 228's DB v96: `messages.is_forwarded INTEGER NOT NULL DEFAULT 0 CHECK (is_forwarded IN (0,1))`, idempotent PRAGMA guard, model map/copy support, and registration exactly once in plan 228's shared production create/upgrade registry. The v96 predecessor fixture must contain `owner_lane`, bookmark/playback columns, `idx_media_attachments_owner_message`, `idx_media_attachments_owner_bookmark_message`, and direct/group/unresolved rows before 097 runs.
- Render a localized marker on direct forwarded rows without identifying or linking the original sender.

Must preserve:
- Multi-target selections remain unique and failed-only retry selection remains truthful -> existing share picker/coordinator tests plus TC-232-03/04.
- Fresh per-target media upload/encryption and ciphertext-only relay custody -> TC-232-06 plus existing 1:1 encryption sentinel.
- Tier-2 dedup's sender/contact discriminator and fresh receipt remain unchanged; two separate forward operations from one source both persist while redelivery of either operation dedups -> TC-232-12.
- External inbound share handling has null provenance, `isForwarded=false`, and a fresh ordinary dedup key -> strengthened real-contact control plus `test/features/share/integration/share_to_contact_smoke_test.dart`; `GREEN sentinel`.
- Existing group target send permissions, allowed-peer encryption, offline queue, retry, and background-task lifecycle -> TC-232-13.
- Plan 228 bookmark/playback/completed-path/owner state and plan 229 `evicted` state survive ordinary receive/retry replay; explicit local-state actions alone may clear/change them -> TC-232-11 plus plan 228 TC-228-08 and plan 229 TC-229-12.

Hard `Do not`:
- Do not edit `go-mknoon/`, `go-relay-server/`, P2P routing/races, inbox protocols, relay media framing, group publish/auth/retry, or transport timeouts.
- Do not reuse the source attachment id/blob id/key/nonce or send decrypted source key material to another recipient.
- Do not expose original sender identity or dedup key in UI, diagnostics, the v2 outer envelope, native share metadata, or group payloads.
- Do not derive a forward dedup token from the source message id/dedup key or reuse one token across separate user actions.
- Do not forward outgoing, pending, missing, evicted, integrity-failed, or unresolved-owner media; offer the appropriate download/unavailable path instead.
- Do not add `is_forwarded` to `group_messages` or `GroupMessagePayload` in this plan.
- Do not reinterpret external OS Share as internal Forward; they remain separate actions and flows.
- Do not default source/destination ownership, expose or mutate `unresolved` attachments, call an untyped media seam, recreate migration lists in `main.dart`, or drop/reorder any v96 owner/state/index artifact while adding v97.

Deferred / accepted difference:
- A group destination receives the forwarded content/caption through the existing coordinator, but group marker persistence/rendering and group-specific dedup are owned by `Test-Flight-Improv/236-group-received-media-forwarding-tdd-plan.md` (DB v99 after Plan 235's v98). Until 236 lands, direct-to-group delivery is allowed but must not fake a marker.
- Announcement-source/destination forwarding policy is owned by `Test-Flight-Improv/240-announcement-received-media-forwarding-tdd-plan.md`.
- Multi-message/multi-source forwarding from Shared Media selection belongs to evidence-gated `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan.md`; this plan owns one source message/current viewer item per launch.
- Protected, consumed, and expired eligibility is owned by evidence-gated Plan 234's central private-media action policy. Plan 232 must expose/use its ordinary action qualification seam when that policy lands, but must not invent private-state fields or test-only flags now.

Dependencies:
- Revised plan 228 must land first and leave production at DB v96 with one shared create/upgrade registry, explicit owner-aware repository APIs, fail-closed unresolved rows, replay-safe viewer state, and both named owner indexes; this plan exclusively reserves DB v97 and appends to that registry.
- Plan 229 must land before the `evicted` eligibility/replay assertions execute; its local status remains absent from wire provenance.
- `Test-Flight-Improv/230-shared-typed-media-viewer-tdd-plan.md` supplies typed current-item action callbacks.
- Existing `ShareTargetPickerWired`, `DefaultShareBatchDeliveryCoordinator`, direct `dedupKey`, upload encryption, and send/retry contracts.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-232-01 | Each explicit Forward action on a received direct-owned visual message mints one random operation token, selects the exact current item or visual siblings, and leaks no source identity. Reopening Forward from the same source mints a different token. | `test/features/conversation/application/build_received_media_forward_test.dart::builds direct owned drafts with a fresh operation token per explicit action` | application host / temp files, direct/group same-message-ID rows, deterministic token source and strict owner-recording repository | HEAD compile RED: forward draft/use case absent -> one action shares one token across its draft, a second action differs, direct lookup yields the expected files/caption, and the group collision is absent | derive the token from source id/dedup, reuse it on reopen, omit direct owner, include group collision/audio, or leak sender/owner -> TC-232-01 red | `flutter test test/features/conversation/application/build_received_media_forward_test.dart --plain-name 'builds direct owned drafts with a fresh operation token per explicit action'`; AUTO + add file to `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS` |
| TC-232-02 | Outgoing, missing, pending/downloading, evicted, integrity-failed, or unresolved-owner media never opens the picker or starts delivery. | `test/features/conversation/application/build_received_media_forward_test.dart::ineligible or unresolved source media fails closed before the picker` | application host / direction+status+owner table fixture, strict repository, launcher spy | HEAD compile RED -> typed reason and zero launcher/coordinator/media-mutation calls for every representable state; unresolved remains unchanged | trust a non-null path, ignore `isIncoming`, or default unresolved to direct -> TC-232-02 red | `flutter test test/features/conversation/application/build_received_media_forward_test.dart --plain-name 'ineligible or unresolved source media fails closed before the picker'`; AUTO + both 1:1 arrays |
| TC-232-03 | Direct conversation Forward opens the existing picker once with media preview and an editable/removable source caption. | `test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart::forward action launches existing picker with editable source caption` | widget host / injected launcher and fake typed viewer | HEAD causal RED: no Forward action/launcher -> exact files/provenance reach launcher; edited/empty caption is delivered, original message is unchanged | pass stale page item, ignore edited caption, or mutate source text -> TC-232-03 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart`; AUTO + add file to both 1:1 arrays |
| TC-232-04 | Contacts/groups are multi-selectable exactly once per namespaced key; stale/unwritable groups are removed before delivery; a failed-only retry retains the original action token and only failed targets. | `test/features/share/presentation/share_target_picker_wired_test.dart::internal forward keeps operation identity for failed-only retry` | widget host / existing picker harness + recording coordinator | HEAD partial RED: generic selection works but no internal provenance path -> unique delivery per selected key, filtered group absent, failed-only selection and original token preserved | mint a token on retry, replace sets with lists, or skip pre-send group revalidation -> TC-232-04 red | `flutter test test/features/share/presentation/share_target_picker_wired_test.dart --plain-name 'internal forward keeps operation identity for failed-only retry'`; AUTO + add/retain file in both 1:1 arrays |
| TC-232-05 | The coordinator uses its production contact leg (`sendToContactFn == null`): each direct target gets a fresh id/timestamp/attachment while the action token, forwarded marker and direct owner reach encrypted send, persistence, and attachment rows. | `test/features/share/application/share_batch_delivery_coordinator_test.dart::production contact leg remints identity and persists forward provenance per target` | application host / two contacts, real `_sendToContact`, passthrough message crypto, captured/decrypted inner envelopes, real message/media repositories; `processSharedMediaFn` may isolate unrelated image processing | HEAD causal RED: provenance absent -> two fresh persisted sends and attachments share only the action token, carry `isForwarded=true` and direct owner; an external-share control has null provenance, false marker, and fresh ordinary key | install `sendToContactFn`, drop provenance before `sendChatMessage`, omit/flip owner, reuse ids, or mark external Share forwarded -> TC-232-05 red | `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart --plain-name 'production contact leg remints identity and persists forward provenance per target'`; AUTO + add file to both 1:1 arrays |
| TC-232-06 | Media preprocessing happens once, but each direct target gets a new blob id and independently generated encryption key/nonce; source bytes/key metadata remain unchanged. | `test/features/share/application/share_batch_delivery_coordinator_test.dart::multi-target media forward preprocesses once and encrypts/uploads separately per contact` | `GREEN sentinel` strengthened / host temp files + content-transforming bridge | Existing external batch path is expected GREEN for preprocess-once/per-target upload -> remains GREEN for internal provenance with distinct ids/keys and no plaintext upload | hoist one uploaded attachment across targets or reuse prepared key/nonce -> TC-232-06 red | `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart --plain-name 'multi-target media forward preprocesses once and encrypts/uploads separately per contact'`; AUTO + both 1:1 arrays |
| TC-232-07 | `isForwarded` defaults false for legacy input, round-trips v1/v2 inner JSON, and is absent with dedup/original-sender data from the encrypted outer envelope. | `test/features/conversation/domain/models/message_payload_test.dart::forward marker is legacy-safe inner-only and carries media plus dedup` | domain host / payload codecs + fake v2 envelope | HEAD causal RED: field absent -> legacy false; true survives both codecs; v2 outer exposes only existing routing fields | put marker/key in outer envelope or default missing to true -> TC-232-07 red | `flutter test test/features/conversation/domain/models/message_payload_test.dart --plain-name 'forward marker is legacy-safe inner-only and carries media plus dedup'`; AUTO (`feature-host-all`) + retain file in both 1:1 arrays |
| TC-232-08 | DB v97 adds `is_forwarded` and has exactly one 097 entry in each shared production create/upgrade registry, ordered immediately after 096. Fresh create, v96 upgrade, and a direct invocation of the actual 097 entry are stable. | `test/core/database/migrations/097_direct_message_forwarded_test.dart::actual 097 entry extends complete v96 idempotently` plus `test/core/database/integration/full_migration_chain_test.dart::production registries contain one ordered direct forwarded v97 entry` | migration/integration host / shared registry entries, fresh DB and complete v96 fixture with direct/group/unresolved rows and both named indexes | HEAD RED: entry/column/version absent -> exact registry counts/order, PRAGMA/default/invalid insert+update CHECK/map, fresh create and v96 upgrade pass; invoke the selected 097 entry twice and preserve all v96 state/indexes | call `runProductionOnUpgrade(97,97)`, duplicate an entry, handcraft an incomplete v96 schema, remove CHECK, or drop/reorder v96 artifacts -> TC-232-08 red | `flutter test test/core/database/migrations/097_direct_message_forwarded_test.dart test/core/database/integration/full_migration_chain_test.dart`; AUTO + add migration file to both 1:1 arrays |
| TC-232-09 | Real SQLCipher upgrades v96->v97, rejects a requested v97->v96 open, rejects the wrong password, and then reopens v97 with marker plus complete v96 owner/viewer state unchanged. | `integration_test/direct_forwarded_marker_sqlcipher_proof_test.dart::encrypted v97 rejects downgrade and wrong password then preserves forwarded owner state` | single-device proof on one available target per Android/iOS family / real `sqflite_sqlcipher`, production registry, complete v96 fixture, real repositories | HEAD device RED -> non-empty `PRAGMA cipher_version`; exact v96 artifacts survive upgrade; downgrade request fails closed; wrong password cannot query; correct reopen preserves marker/owner/bookmark/playback/path; actual 097 entry rerun is stable | reset version, accept wrong password, use plaintext SQLite, call a vacuous 97->97 upgrade, or lose v96 state -> TC-232-09 red | explicit `flutter test ... -d <selected-id>` for each available family; dedicated path has exactly one `ignored` discovery record and zero `1to1`/`unclassified` records |
| TC-232-10 | A direct forwarded row renders one localized attribution-free marker; ordinary rows render none. The real `ConversationScreen` receives one of each and renders exactly one marker on the forwarded card. | `test/features/conversation/presentation/widgets/letter_card_test.dart::direct forwarded marker is attribution-free and legacy rows stay unmarked` plus `test/features/conversation/presentation/screens/conversation_screen_test.dart::screen marks only the forwarded conversation row` | widget host / card fixture plus two-row production screen construction | HEAD causal RED -> marker count/semantics pass in en/de/ar; real screen propagates true and false correctly; source identity/token absent | test only `LetterCard`, hardcode either flag at screen construction, mark every media row, or show source identity -> TC-232-10 red | both named widget commands; existing `ONE_TO_ONE_TESTS`, retain/add both files in `ONE_TO_ONE_HOST_TESTS` |
| TC-232-11 | Failed/queued forwarded direct sends retain the operation token, marker, fresh id, encrypted envelope and direct ownership through retry/reopen; ordinary replay preserves bookmark/playback/completed path and later `evicted`. | `test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart::queued forward retry preserves operation identity direct owner and local media state` | host integration / fake inbox failure then recovery, real owner-aware media repository, local-state mutation and repository reopen | HEAD compile RED -> original row transitions once and receiver gets one marked direct-owned row; retry reuses its stored id/envelope/token; replay does not erase local state | rebuild as a new action, mint a token/id/key, omit direct owner, or replace local state with defaults -> TC-232-11 red | named integration command; AUTO + add file to both 1:1 arrays |
| TC-232-11E | Editing a forwarded direct message preserves its operation token and marker through the encrypted edit payload, sender persistence, and receiver existing-row update. | `test/features/conversation/application/send_chat_message_use_case_test.dart::edit preserves forwarded marker and operation dedup token end to end` | application host / real edit wrapper, passthrough crypto, sender DB and receiver handler | HEAD causal RED: edit wrapper omits original dedup/marker -> captured inner edit and both rows remain forwarded with the original token | default edited dedup to message id, clear marker, or only assert controller arguments -> TC-232-11E red | named application test; retain existing file in both 1:1 arrays |
| TC-232-12 | Two explicit operations forwarding the same source attachment and caption to the same recipient both persist because their operation tokens differ; redelivery of either operation is acknowledged and deduped by its token. | `test/features/conversation/integration/two_user_message_exchange_test.dart::same content explicit forwards persist while each operation redelivery key dedups` | host integration / existing two-user encrypted-v2 fake transport: operation A(content X), duplicate A, operation B(same content X/new token), duplicate B; assert keyed-duplicate event | Existing source-key sentinel is causally RED after rewrite -> two identical-content cards persist, one per explicit operation; neither redelivery adds a card; fresh-id receipts and keyed-dedup events are correct | derive token from source, fall back to content dedup for keyed arrivals, or mint on redelivery -> TC-232-12 red | named integration command; existing both 1:1 arrays; existing DB-helper tests retain sender/contact discriminator coverage |
| TC-232-13 | A selected group target continues through the existing writable-group/background-task/upload/send path, saves every destination attachment with `MediaOwnerLane.group`, and adds no direct marker or transport mutation. | `test/features/share/application/share_batch_delivery_coordinator_test.dart::group forward target preserves publish contract and saves group owner` | `GREEN sentinel` strengthened / existing fake group repositories/bridge + strict media-owner recorder | Existing group share behavior GREEN -> same content/caption is delivered; every save/failure transition records group owner; direct `isForwarded` is not passed to group payload before plan 236 | call direct send, omit/flip group owner, invent announcement owner, add group marker here, or bypass writable-group check -> TC-232-13 red | `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart --plain-name 'group forward target preserves publish contract and saves group owner'`; AUTO; exact sentinel replaces a broad group-family sweep |
| TC-232-14 | The direct forwarding slice changes no Go/libp2p/relay behavior and uses only existing Dart send/upload contracts. | `test/features/conversation/application/direct_media_forward_transport_boundary_test.dart::direct forwarding imports no go bridge routing inbox or group payload implementation` | host source-contract test | HEAD compile RED: target sources absent -> forbidden imports/calls and Go diff paths are unchanged from the recorded dirty-tree baseline | add a P2P command, Go edit dependency, or relay-forward API -> TC-232-14 red | `flutter test test/features/conversation/application/direct_media_forward_transport_boundary_test.dart`; AUTO + add file to both 1:1 arrays; baseline status+binary-diff comparison below required for Go/relay paths |
| TC-232-15 | Forward action, caption, target count, marker, and partial-result strings are localized and accessible in Arabic/German without overflow. | `test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart::forward flow is localized RTL-safe and semantics-labelled` | widget host / 320x568 de/ar fixtures | HEAD causal RED: action/marker copy absent -> all keys readable/reachable and no exception | hardcode English or use a fixed non-scrollable action surface -> TC-232-15 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart --plain-name 'forward flow is localized RTL-safe and semantics-labelled'`; AUTO + both 1:1 arrays; existing direct ARB parity command |

### Test Notes

- TC-232-05 must leave `sendToContactFn` null so the production `_sendToContact` leg executes. Passthrough crypto may expose the captured inner envelope, and `processSharedMediaFn` may isolate image preprocessing because TC-232-06 owns that boundary.
- Within one action, destination messages have different ids/timestamps/attachments but the same operation token. A later explicit action from the same source and an external OS Share each carry a fresh token/key.
- TC-232-06 asserts distinct blob ids and key/nonces, not merely two `uploadMedia` calls. The source's stored encryption metadata must remain byte-equal before/after.
- TC-232-08 selects the real registry entry by version/name and calls its migration body twice. `runProductionOnUpgrade(97,97)` is forbidden evidence because its version guard runs nothing. Exact-one assertions apply to both registry lists; ordering is relative to 096 so later plans may append 098+.
- TC-232-09 uses real SQLCipher but does not claim real ML-KEM/AES behavior. Its downgrade check proves the current fail-closed opener, not compatibility with an old v96 binary; plan 228's no-supported-downgrade release floor remains authoritative. No relay or two-device run is required.
- Protected/consumed/expired fixtures are intentionally absent until plan 234 supplies representable state and one central action-eligibility contract.

## Implementation Steps

1. Snapshot `git status --short`; verify plan 228 has landed at DB v96 and 097 is free. Write the causal operation-A/operation-B RED, draft eligibility RED, real-contact-leg RED, and v97 registry RED before production edits.
2. Add `ForwardProvenance.operationDedupKey`, an injectable random token source, draft building, and the direct-conversation launcher. Mint once per explicit action; preserve it only through that action's picker retry and queued redelivery.
3. Thread provenance through `ShareIntent`, picker, and the production contact coordinator. Reload the direct-owned incoming source before launch, pass exact direct/group destination ownership, and keep group marker/provenance behavior deferred to plan 236.
4. Add `isForwarded` to direct payload/model/send/receive/retry/edit/render paths, with legacy false, v2-inner-only privacy, and a real `ConversationScreen` wiring assertion.
5. Append migration 097 exactly once to both shared production registries; prove complete-v96 upgrade, direct actual-entry rerun, CHECK enforcement, current-opener downgrade refusal, wrong-password failure, and correct reopen on available device families. Stop if HEAD is not v96, the shared registry is absent, or 097 is owned.
6. Add l10n, register every new host test in both 1:1 arrays, register the SQLCipher proof as exactly one ignored/manual record, run focused gates, proportional `core-host-all`, available-device proof, mutations, and hygiene.

## Risks And Blind Spots

- Reusing source encryption material would leak recipient-scoped custody -> TC-232-06.
- Provenance could leak sender/source identity or a linkable token outside encryption -> TC-232-01/07/10.
- Reusing a source key across explicit actions can discard a legitimate forward; reminting within retry can duplicate one -> TC-232-01/04/11/12.
- Lifecycle / derived-state durability: TC-232-09/11 close and reopen database/repository state while preserving complete v96 owner/local state and later evicted state.
- Sibling-surface consistency: TC-232-01/03 compare viewer-current versus bubble-all behavior; TC-232-05 keeps external OS Share separate; TC-232-10 covers screen-to-card wiring.
- Destructive-action side effects: N/A — forwarding creates new rows/files and must not mutate the source; TC-232-01/03/06 assert source preservation.
- Invariant re-verification under new transitions: picker retries retain one action token in TC-232-04; queued resend reuses its stored envelope in TC-232-11; edits preserve token/marker in TC-232-11E.
- Cross-lane marker parity is intentionally staged -> plan 235 owns DB v98, plan 236 owns group DB v99, and plan 240 owns announcement policy.

## Gate Cadence

- Per-plan closure runs the focused forwarding/picker/payload/migration tests, exact direct/group preservation sentinels, the curated `1to1` gate, `core-host-all`, discovery, and the availability-bounded SQLCipher device proof. `core-host-all` is justified by DB v97 and the shared production migration registry.
- Do not run `feature-host-all` or full `host-all` as Plan 232 acceptance. Full `host-all` runs once after the complete forwarding/migration wave, and again at final received-media rollout closure; the wave runner owns that aggregate evidence.

## Acceptance Gates

```bash
# Snapshot and migration precondition
git status --short
git status --short --untracked-files=all -- go-mknoon go-relay-server > /tmp/plan-232-go-relay-status.before
git diff --binary -- go-mknoon go-relay-server > /tmp/plan-232-go-relay-diff.before
rg -n '^const int currentIdentityDatabaseVersion = 96;$' lib/core/database/app_database_version.dart

# First causal RED after adding the named test; expect non-zero because operation-scoped forward APIs are absent
flutter test test/features/conversation/application/build_received_media_forward_test.dart --plain-name 'builds direct owned drafts with a fresh operation token per explicit action'

# Focused host GREEN; expect exit 0 and zero failed tests
flutter test test/features/conversation/application/build_received_media_forward_test.dart
flutter test test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart
flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart
flutter test test/features/share/presentation/share_target_picker_wired_test.dart
flutter test test/features/conversation/domain/models/message_payload_test.dart
flutter test test/core/database/migrations/097_direct_message_forwarded_test.dart
flutter test test/core/database/integration/full_migration_chain_test.dart --plain-name 'production registries contain one ordered direct forwarded v97 entry'
flutter test test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart
flutter test test/features/conversation/application/direct_media_forward_transport_boundary_test.dart
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart --plain-name 'edit preserves forwarded marker and operation dedup token end to end'
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart --plain-name 'direct forwarded marker is attribution-free and legacy rows stay unmarked'
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name 'screen marks only the forwarded conversation row'
flutter test test/l10n/l10n_integrity_test.dart

# Preservation/named gates
flutter test test/features/conversation/integration/two_user_message_exchange_test.dart --plain-name 'same content explicit forwards persist while each operation redelivery key dedups'
flutter test test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart
flutter test test/features/share/integration/share_to_contact_smoke_test.dart
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh core-host-all

# Exact array registration; inspect only the named arrays, then prove host planner selection without rerunning its suite
host_files=(
  test/features/conversation/application/build_received_media_forward_test.dart
  test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart
  test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart
  test/features/conversation/application/direct_media_forward_transport_boundary_test.dart
  test/core/database/migrations/097_direct_message_forwarded_test.dart
)
for file in "${host_files[@]}"; do
  test "$(awk '/^readonly ONE_TO_ONE_TESTS=\(/,/^\)/' scripts/run_test_gates.sh | rg -F -x -c "  \"$file\"")" -eq 1
  test "$(awk '/^readonly ONE_TO_ONE_HOST_TESTS=\(/,/^\)/' scripts/run_host_test_gates.sh | rg -F -x -c "  \"$file\"")" -eq 1
done
host_plan="$(mktemp)"
./scripts/run_host_test_gates.sh 1to1 --dry-run >"$host_plan"
for file in "${host_files[@]}"; do
  test "$(rg -F -c "$file" "$host_plan")" -eq 1
done
rm -f "$host_plan"

# Availability-bounded real SQLCipher closure; select one target per available OS family
flutter devices --machine > /tmp/plan-232-flutter-devices.json
adb devices -l || true
xcrun simctl list devices available || true
test -n "${PLAN232_ANDROID_DEVICE_ID:-}${PLAN232_IOS_DEVICE_ID:-}"
if test -n "${PLAN232_ANDROID_DEVICE_ID:-}"; then
  flutter test integration_test/direct_forwarded_marker_sqlcipher_proof_test.dart -d "$PLAN232_ANDROID_DEVICE_ID" --plain-name 'encrypted v97 rejects downgrade and wrong password then preserves forwarded owner state'
fi
if test -n "${PLAN232_IOS_DEVICE_ID:-}"; then
  flutter test integration_test/direct_forwarded_marker_sqlcipher_proof_test.dart -d "$PLAN232_IOS_DEVICE_ID" --plain-name 'encrypted v97 rejects downgrade and wrong password then preserves forwarded owner state'
fi

# Dedicated migration proof stays outside reliability-sim execution
records_file="$(mktemp)"
./scripts/check_reliability_simulation_discovery.sh --records-tsv >"$records_file"
test "$(awk -F '\t' '$1 == "ignored" && $2 == "ignored" && $3 == "integration_test/direct_forwarded_marker_sqlcipher_proof_test.dart" { n++ } END { print n + 0 }' "$records_file")" -eq 1
test "$(awk -F '\t' '$1 == "1to1" && $3 == "integration_test/direct_forwarded_marker_sqlcipher_proof_test.dart" { n++ } END { print n + 0 }' "$records_file")" -eq 0
test "$(awk -F '\t' '$1 == "unclassified" && $3 == "integration_test/direct_forwarded_marker_sqlcipher_proof_test.dart" { n++ } END { print n + 0 }' "$records_file")" -eq 0
rm -f "$records_file"

# Scope/hygiene
git status --short --untracked-files=all -- go-mknoon go-relay-server | cmp -s - /tmp/plan-232-go-relay-status.before
git diff --binary -- go-mknoon go-relay-server | cmp -s - /tmp/plan-232-go-relay-diff.before
flutter analyze
git diff --check
```

## Device/Relay Proof Profile

- Profile: one-device local SQLCipher proof on one selected available target per supported Android/iOS family; no relay, second peer, or user-driven phone interaction is required.
- Boundary being proven: real `sqflite_sqlcipher` applies v97 over complete encrypted v96 state, reports a non-empty `PRAGMA cipher_version`, rejects wrong-password access and a requested downgrade, then correctly reopens with owner/bookmark/playback/path/index/marker state intact. Host SQLite does not substitute for this boundary.
- Availability: resolve `flutter devices --machine`, `adb devices -l`, and available `simctl` targets at execution. Prefer a controllable physical Android target; Android emulator and iOS simulator are valid for this single-device plugin proof. Pin one ID per available family. An unavailable family is N/A rather than blocking the other family; a failure on a selected target is a blocker.
- Required setup: plan 228 DB v96 and a per-test temporary encrypted database/password. The test creates and reopens its own DB and must need no manual unlock, navigation, or taps.
- Closure role: required migration/persistence closure only; host tests own picker/dedup/encryption-decision behavior.
- Registration: add only the dedicated path to the manual/device inventory with exactly one `ignored` discovery record. It must have zero `1to1` and `unclassified` records so generic `reliability-sim` cannot accidentally execute it.
- Closure command: each selected-family command exits 0 with non-empty cipher version, wrong-password and downgrade refusal, correct reopen, preserved state, and non-vacuous actual-097 rerun.
- Deferred device work: no real-relay/real-crypto campaign; existing media encryption and two-user host integrations remain the proportionate sentinels because this plan changes no cryptographic or transport algorithm.

## Execution Interpretation And Done Criteria

- Expected RED: TC-232-01 compile-fails because internal forward draft/provenance APIs do not exist.
- Green sentinel: existing direct dedup, direct media encryption round trip, inbound external share, and group share tests remain green.
- Pre-existing dirty tree / known failure: record at execution start; unrelated current changes in messaging/push/graph outputs are not plan scope.
- Environment interpretation: an unavailable OS family is N/A after inventory; at least one supported target must run TC-232-09, and failure on a selected target blocks closure. Host SQLite cannot replace the proof.
- Scope drift: any Go/relay/P2P/group-payload edit, v97 collision, original-sender attribution, source-derived operation token, or private-media test-only flag blocks completion.

- [x] Every behavior has a named causal test or explicit sentinel.
- [x] DB v97 has exactly one ordered entry in each shared registry, enforced CHECK/default/map, complete-v96 preservation, non-vacuous actual-entry rerun, current-opener downgrade refusal, wrong-password failure, and available-device SQLCipher evidence.
- [x] Two distinct actions from one source both persist; retry/redelivery of either keeps its action token and dedups; editing preserves marker/token.
- [x] Source/direction, caption, multi-target, failed-only retry, production contact leg, render wiring, external-share negative, and fresh per-target encryption tests pass.
- [x] New host tests occur exactly once in both 1:1 arrays and the host planner dry-run selects them; the device proof has exactly one `ignored` record and zero executable reliability-sim classifications.
- [x] Representative source-token reuse, retry-remint, contact-leg bypass, marker/edit drop, id/key reuse, CHECK removal, vacuous migration rerun, and transport-boundary mutations re-red.
- [x] `flutter analyze` has no new issues; `git diff --check` and Go/relay no-diff guard are clean.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED: `flutter test test/features/conversation/application/build_received_media_forward_test.dart --plain-name 'builds direct owned drafts with a fresh operation token per explicit action'` after adding that test.
- Preservation command: `flutter test test/features/conversation/integration/two_user_message_exchange_test.dart --plain-name 'same content explicit forwards persist while each operation redelivery key dedups'`.
- Registration: add new host files exactly once to both 1:1 arrays; add the SQLCipher path as one ignored/manual discovery record, not an executable `1to1` record.
- Migration: append DB v97 `messages.is_forwarded` exactly once after 096 in each shared registry, preserve complete v96 state, invoke the actual 097 entry for rerun proof, and close wrong-password/downgrade/reopen behavior on available device families.
- Boundary closure: availability-bounded single-device SQLCipher runs; no relay/real-network/Go or two-phone proof because those behaviors are unchanged.
- Unresolved evidence: none. Group marker/dedup is an explicit deferred owner (plan 236), and private/expiry eligibility is explicitly owned by plan 234.

## Execution Preflight Contract

- Validated at: 2026-07-10 12:17 CEST.
- Source of truth and exact scope: this plan's `Scope Contract And Guard`, `Test Contract`, `Acceptance Gates`, device profile, and done criteria, subject to repository `AGENTS.md` precedence. Implement only received direct-media forwarding, optional internal forwarding provenance, direct marker persistence/rendering, DB v97, l10n, the named tests, and their required registrations.
- Dependency/precondition evidence: `currentIdentityDatabaseVersion` is exactly 96; migration 096 occurs once in each shared production registry; owner-lane/local-viewer state, evicted-state preservation, and typed viewer Forward action seams exist; no migration 097 or `is_forwarded`/`isForwarded` owner exists at preflight.
- Code-entry files: `lib/core/services/share_intent_model.dart`; `lib/features/share/application/share_batch_delivery_coordinator.dart`; share picker route/screen/wired files; direct conversation application/model/repository/screen/wired/card files named by the plan; `lib/core/database/app_database_version.dart`; `lib/core/database/production_migration_registry.dart`; new migration 097; ARB localization files; named gate/discovery scripts. New bounded direct-forward application files are allowed where required by the plan.
- Regressions required first: TC-232-01/02 draft and eligibility tests; TC-232-05 production-contact provenance test; TC-232-08 actual-registry migration test; TC-232-12 operation-A/duplicate-A/operation-B/duplicate-B rewrite. The first named TC-232-01 slice must be observed RED before production edits.
- Required direct tests and named gates: every command in `Acceptance Gates`, including focused tests, the curated `1to1` gate, `core-host-all`, exact array/discovery checks, availability-bounded SQLCipher device proof, `flutter analyze`, `git diff --check`, and the Go/relay baseline guards. `feature-host-all` and full `host-all` are explicitly not per-plan gates.
- Known-failure interpretation: no known failure is pre-authorized. Any required failure must be persisted and triaged before a fix or classification. An unavailable OS family is N/A by repository policy; a selected target failure is blocking, and at least one supported target must execute the SQLCipher proof.
- Live device matrix: Android physical `21071FDF600CSC`, Android emulator `emulator-5554`, connected iPhones, and available iOS simulators were discovered. Prefer the physical Android and one controllable iOS simulator for the single-device proof; pin exact IDs.
- Done criteria: all plan checkboxes resolve with required evidence, no blocking QA finding remains, the diff is coherent and attributable, no Go/relay scope change occurs, and the durable `Execution Result` records the final verdict and ledger.
- Non-goals and guard: no Go/relay/P2P/group-payload behavior, private/expiry model, group marker, announcement policy, shared-media batch forwarding, source attribution, or migration-list recreation in `main.dart`.
- Scoped pre-existing worktree: baseline is `/tmp/plan-232-worktree.before` (47 entries). Existing target-plan edits plus unrelated Test-Flight plans, Graphify outputs/tooling, `info.plist`, and group conversation/action files/tests are user-owned and must be preserved. Go/relay baselines are empty at `/tmp/plan-232-go-relay-status.before` and `/tmp/plan-232-go-relay-diff.before`.
- Graph grounding: anchored compact query found `DefaultShareBatchDeliveryCoordinator`, `ConversationMessage`, and `MessagePayload`; source verification confirmed share route, direct send/edit, conversation screen/card, and shared migration registry. The graph was stale only for an unrelated group screen test and did not surface migration/UI anchors in-budget; those are explicit source-verified graph gaps, not evidence gaps.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-10 14:44 CEST | Executor fix pass 2 focused triage (`fix_passes = 2`) | DB-backed B9 retry test and shared real repository fixture; no production file touched | `flutter test test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart` exited 1; `/tmp/plan-232-fix2-b9-roundtrip.log`; failure occurs while applying playback state because the strengthened fixture still models an image | focused triage is the same one-test file; `dbUpdateMediaPlaybackPosition` correctly rejects playback state for `mediaType: image`; classification `pending_triage` | fixture-model mismatch caused by this B9 strengthening, not a production defect; the durable DB/repository seam has not yet reached retry execution | make the causal visual fixture a video so bookmark and playback are both representable, rerun the same exact file, and persist any later failure before repair |
| 2026-07-10 14:45 CEST | Executor fix pass 2 focused triage (`fix_passes = 2`) | durable B9 test after using a video fixture; sender repository status/envelope transition | rerun of `flutter test test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart` exited 1 at the test's `wireEnvelope == null` precondition; `/tmp/plan-232-fix2-b9-roundtrip-rerun.log` | focused triage is the same one-test file; the fake's first successful send retained relay-inbox custody and its durable envelope, while B9 intentionally needs the later failed-message leg to rebuild without one; classification `pending_triage` | fixture transition assumption, not a production defect; durable upload retry completed and persisted the envelope as designed | clear the envelope and set failed status together through `MessageRepository.saveMessage`, close/reopen, assert null after rehydration, then rerun the exact B9 file |
| 2026-07-10 14:46 CEST | Executor fix pass 2 focused triage (`fix_passes = 2`) | B9 durable sender media row after real incomplete-upload retry and second close/reopen; no production edit attempted | second rerun of `flutter test test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart` exited 1 at preserved-path assertion; `/tmp/plan-232-fix2-b9-roundtrip-rerun2.log` | bookmark, playback, identity, owner, marker/token, and upload crypto rehydrated, but `localPath` became null after the incomplete-upload save; inspecting the production upload result and atomic DB merge to distinguish fixture output from a causal defect; classification `pending_triage` | possible session-revealed production defect, not yet classified; no fix until the real upload return contract is compared with the fixture | inspect `upload_media_use_case.dart` result and `dbSaveMediaAttachmentPreservingLocalState`; if production always returns the local path, repair the fixture only, otherwise make the smallest causal production fix and rerun affected evidence |
| 2026-07-10 14:49 CEST | Executor fix pass 2 materialization recovery (`fix_passes = 2`, `materialization_retries = 1`) | `upload_media_use_case.dart` result contract, atomic media merge, B9 fake upload result; test/fixture only | production inspection completed: `uploadMedia` initializes `storedPath = localFilePath` and always returns it on success (or the durable relative replacement); the B9 fake returned `originalAttachment.localPath == null` and was unrealistic | fixture-only correction now returns the closure's `localFilePath`; no production defect and no production change; next evidence is the exact B9 rerun | B9-only recovery remains active; prior pending-path triage is classified `fixture-caused`; all unrelated/concurrent paths and broad evidence remain excluded | rerun the B9 file, then the two complete retry suites, hygiene and Go/relay guards; persist `## Fix Pass 2 Evidence` and hand back `ready_for_qa` or `blocked` |
| 2026-07-10 14:51 CEST | Executor fix pass 2 completion (`fix_passes = 2`, `materialization_retries = 1`) | strengthened DB-backed B9 integration, minimum shared fixture reopen/message-repository support, plan evidence; production untouched | B9 integration passed; complete failed-message suite passed 32 tests; complete incomplete-upload suite passed 30 tests; `git diff --check` and both Go/relay baseline comparisons exited 0 | exact logs `/tmp/plan-232-fix2-{b9-roundtrip-green,retry-failed,retry-incomplete,diff-check,go-relay-status.after,go-relay-diff.after}.log` except the two guard artifacts use `.after` without `.log`; scoped status is `/tmp/plan-232-fix2-scoped-status.log` | `ready_for_qa`; B9 is resolved for Executor handoff, no production defect/change occurred, and no broad/device/analyzer/mutation/registration/Graphify evidence was rerun | persist `## Fix Pass 2 Evidence` and return to a fresh independent QA Reviewer; do not claim the final plan verdict |
| 2026-07-10 14:57 CEST | Independent QA review after fix pass 2 | full plan/preflight/prior QA/fix evidence; B9 test; shared real-DB fixture; production repository/helpers and retry seams; persisted logs/scope guards | independent exact rerun `flutter test test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart` exited 0; `/tmp/plan-232-qa-fix2-b9-rerun.log`; current `git diff --check` and both Go/relay baseline comparisons also pass | inspected file-backed close/reopen implementation, fresh repository construction, owner-aware local-state mutations, production mapping/helpers, both real retry calls, and exactly-once receiver assertions | `pass`; B9 is causally resolved, no blocking finding remains, and no production/test edit was made by QA | persist `## QA Review — Fix Pass 2`; return the no-blocker handoff to the controller for the final incremental Graphify refresh and verdict |
| 2026-07-10 14:59 CEST | Controller acceptance | coherent Plan 232 implementation, all persisted Executor/QA evidence, final architecture graph | `./graphify-arch/refresh_arch_graph.sh --incremental` exited 0; 40 changed code files processed, graph written with 45,315 nodes/70,718 edges, TDD overlay refreshed with 1,195 files/12,027 named tests/920 production targets | `/tmp/plan-232-final-graph-refresh.log`; final `git diff --check` and Go/relay preflight comparisons pass | `accepted`; no blocker remains after two fix passes and fresh independent QA | persist this final execution result and leave unrelated dirty-tree work untouched |

## Executor Evidence

### Disposition

- Executor status: `ready_for_qa`.
- Initial Executor pass only; `fix_passes = 0`.
- Independent QA has not run in this role. The parent controller owns the fresh QA Reviewer and the single post-acceptance Graphify refresh.

### Attributable change set

- Forward draft and delivery: `lib/core/services/share_intent_model.dart`, new `lib/features/conversation/application/build_received_media_forward.dart`, and `lib/features/share/application/share_batch_delivery_coordinator.dart`.
- Direct marker/wire/retry behavior: `ConversationMessage`, `MessagePayload`, `send_chat_message_use_case.dart`, `handle_incoming_chat_message_use_case.dart`, both full-send retry use cases, and dedup contract comments in `message_repository.dart`.
- UI: `conversation_screen.dart`, `conversation_wired.dart`, `letter_card.dart`, `message_context_overlay.dart`, and generated/localized English, German, and Arabic marker copy.
- Persistence: DB version 97, the shared production registry, and new guarded migration `097_direct_message_forwarded.dart`.
- Gates: both 1:1 arrays and the reliability discovery script.
- New tests: draft/eligibility, direct transport boundary, retry round trip, conversation-to-picker widget flow, v97 host migration, and real SQLCipher device proof.
- Updated tests: payload, edit propagation, operation-A/B receiver dedup, direct marker rendering, production contact/group coordinator behavior, failed-only picker retry, full migration chain, and the impacted Plan 231 wired transport inventory.
- No attributed changes exist in `go-mknoon/`, `go-relay-server/`, `main.dart`, group payload/model tables, announcement behavior, or private-media policy. Pre-existing/concurrent group and Graphify worktree changes were preserved.

### Evidence ledger

| Contract slice | Exact command | Result / classification | Evidence |
|---|---|---|---|
| First causal RED | `flutter test test/features/conversation/application/build_received_media_forward_test.dart --plain-name 'builds direct owned drafts with a fresh operation token per explicit action'` | exit 1 before production APIs existed; expected causal RED | `/tmp/plan-232-tc01-red.log` |
| Draft and eligibility | `flutter test test/features/conversation/application/build_received_media_forward_test.dart` | passed; final strengthened rerun also passed | `/tmp/plan-232-build-forward-final.log` |
| Conversation/picker UI | `flutter test test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart` | passed; bubble action asserts null current item while viewer remains current-item | `/tmp/plan-232-widget-bubble-all-rerun.log` |
| Production fan-out | `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart` | passed | `/tmp/plan-232-accept-coordinator.log` |
| Picker retry | `flutter test test/features/share/presentation/share_target_picker_wired_test.dart` | passed | `/tmp/plan-232-accept-picker.log` |
| Payload boundary | `flutter test test/features/conversation/domain/models/message_payload_test.dart` | passed | `/tmp/plan-232-accept-payload.log` |
| v97 host migration | `flutter test test/core/database/migrations/097_direct_message_forwarded_test.dart` | passed | `/tmp/plan-232-accept-migration.log` |
| Registry ordering | `flutter test test/core/database/integration/full_migration_chain_test.dart --plain-name 'production registries contain one ordered direct forwarded v97 entry'` | passed | `/tmp/plan-232-accept-chain.log` |
| Retry round trip | `flutter test test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart` | passed; final import-cleanup rerun passed | `/tmp/plan-232-retry-import-cleanup-rerun.log` |
| Transport boundary | `flutter test test/features/conversation/application/direct_media_forward_transport_boundary_test.dart` | passed | `/tmp/plan-232-accept-boundary.log` |
| Edit propagation | `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart --plain-name 'edit preserves forwarded marker and operation dedup token end to end'` | passed | `/tmp/plan-232-accept-edit.log` |
| Card marker | `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart --plain-name 'direct forwarded marker is attribution-free and legacy rows stay unmarked'` | passed serially | `/tmp/plan-232-accept-letter-rerun.log` |
| Screen marker | `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name 'screen marks only the forwarded conversation row'` | passed | `/tmp/plan-232-accept-screen-rerun.log` |
| Localization | `flutter test test/l10n/l10n_integrity_test.dart` | passed | `/tmp/plan-232-accept-l10n-rerun.log` |
| Operation A/B dedup | `flutter test test/features/conversation/integration/two_user_message_exchange_test.dart --plain-name 'same content explicit forwards persist while each operation redelivery key dedups'` | passed | `/tmp/plan-232-preserve-two-user.log` |
| Fresh encryption | `flutter test test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart` | passed | `/tmp/plan-232-preserve-encryption.log` |
| External-share negative | `flutter test test/features/share/integration/share_to_contact_smoke_test.dart` | passed | `/tmp/plan-232-preserve-external-share.log` |
| Impacted Plan 231 boundary | `flutter test test/features/conversation/application/received_media_action_transport_boundary_test.dart --plain-name 'received media egress call sites and wired transport baseline are exact'` | passed after admitting exactly one reviewed picker route | `/tmp/plan-232-preserve-transport-baseline-rerun.log` |
| Curated 1:1 | `./scripts/run_test_gates.sh 1to1` | passed, 1,644 tests | `/tmp/plan-232-gate-1to1-rerun.log` |
| Core host family | `./scripts/run_host_test_gates.sh core-host-all` | passed, 294 files | `/tmp/plan-232-gate-core-host-all-rerun.log` |
| Dual registration | exact five-file array loop plus `./scripts/run_host_test_gates.sh 1to1 --dry-run` | passed; exactly once in both arrays and dry-run | `/tmp/plan-232-host-dry-run.log` |
| Device discovery | `flutter devices --machine`; `adb devices -l`; `xcrun simctl list devices available` | Android physical/emulator and iOS physical/simulators discovered | `/tmp/plan-232-flutter-devices.json`, `/tmp/plan-232-adb-devices.log`, `/tmp/plan-232-simctl-devices.log` |
| Android SQLCipher | `flutter test integration_test/direct_forwarded_marker_sqlcipher_proof_test.dart -d 21071FDF600CSC --plain-name 'encrypted v97 rejects downgrade and wrong password then preserves forwarded owner state'` | passed on physical Pixel 6 | `/tmp/plan-232-device-android.log` |
| iOS SQLCipher | `flutter test integration_test/direct_forwarded_marker_sqlcipher_proof_test.dart -d 674DFFF6-5F38-4235-93F6-AF7FBF86AE65 --plain-name 'encrypted v97 rejects downgrade and wrong password then preserves forwarded owner state'` | passed on iPhone 17 Pro simulator | `/tmp/plan-232-device-ios.log` |
| Discovery isolation | exact `--records-tsv` ignored/1to1/unclassified assertions | passed: one ignored, zero executable records | `/tmp/plan-232-discovery-records.tsv` |
| Full analyzer | `flutter analyze` | exit 1 with 1,629 repo issues; persisted and triaged as pre-existing workspace debt except two Plan-232 diagnostics, both removed/suppressed | `/tmp/plan-232-flutter-analyze.log` |
| New-file analyzer | `dart analyze <all eight new Plan 232 Dart files>` | passed, no issues | `/tmp/plan-232-scoped-new-files-analyze-final.log` |
| Hygiene/scope | `git diff --check`; both Go/relay baseline `cmp` guards | passed | terminal exit 0; baselines `/tmp/plan-232-go-relay-*.before` |
| Reverse impact | `python3 graphify-arch/tdd_context.py affected <final app-owned files> --budget 600` | passed; broad/truncated importer shortlist, source/gates used for verification | `/tmp/plan-232-graph-affected.log` |

### Failure triage and dispositions

- A mistaken broad formatter invocation touched baseline-clean files. Work stopped immediately; the parent mechanically restored 173 outside-scope formatter-only diffs. Remaining Plan 232 files were then manually narrowed to semantic hunks. Pre-existing/concurrent group and Graphify changes were never reverted.
- Early widget failures were bounded-pump and wrong-`TextField` finder defects; production picker launch already occurred. Corrected tests passed.
- The coordinator group test initially used a fake bridge that rejected media commands. Delegating unhandled commands to the base fake fixed the fixture; direct/group owner behavior passed.
- One parallel Flutter run raced a macOS native-asset install before the letter-card test loaded. All affected commands were rerun serially and passed.
- The first curated 1:1 run found the Plan 231 exact source inventory stale for the reviewed picker route. The baseline now permits exactly one `ShareTargetPicker` route and its required `p2pService`/bridge references while retaining zero raw Go/ShareBatch seams; focused and curated reruns passed.
- The first core lane found its legacy hand-driven v1 fixture missing current v97 and its v96-artifact helper still expecting user version 96. The fixture now invokes the actual shared v97 registry entry, expects current version 97, and retains all v96 artifact assertions; the full file and core lane pass.
- Literal full analysis remains nonzero because this repository currently reports 1,629 issues. The only two diagnostics introduced in new Plan 232 files were resolved. The remaining diagnostics on touched existing files are present in HEAD; repo-wide lint cleanup was out of scope.

### QA review points / remaining uncertainty

- `ConversationWired` supports injected `receivedMediaForwardLauncher` and optional `forwardGroup*` dependencies; the production coordinator's real group branch is causally green. Existing outer `ConversationWired` construction sites do not currently pass those optional group dependencies, so QA must decide whether this satisfies the plan's production contact-or-group picker requirement or requires a scoped caller-wiring fix pass.
- The affected Graphify result was truncated at the mandated 600-token budget. Direct importers named in the shortlist (`PendingMessageRetrier`, chat listener, lifecycle/debug callers) were covered by focused, curated 1:1, and core-host gates; no second broad graph query or Executor refresh was run.
- The literal `flutter analyze` exit remains unresolved as a zero-exit gate despite no Plan-232-caused diagnostics in new files. QA must apply the plan's known-failure policy explicitly rather than treating the scoped analyzer as a replacement.

## QA Review

### Reviewer disposition

- Disposition: `blocking_findings`.
- Reviewer: fresh independent QA after the initial Executor pass.
- Production/test edits by QA: none.
- Expensive passing gates were not duplicated. QA inspected their exact logs and reran only the lightweight dual-array/dry-run counts, discovery record inspection, Go/relay baseline comparisons, and `git diff --check`; those checks passed.

### Blocking findings

- **B1 — Blocking correctness / coherent wiring:** the received-media Forward flow cannot deliver to a group from any production `ConversationWired` construction path. `conversation_wired.dart:2147-2152` passes only optional `forwardGroup*` dependencies to `buildShareTargetPickerRoute`, while every production constructor found by `rg -n "ConversationWired\\(" lib` omits them. The picker therefore loads zero groups in production even though the isolated coordinator group test is green. In addition, the two `ConversationWired` sites in `main.dart:3093` and `main.dart:4050` omit `imageProcessor`, so the enablement guard at `conversation_wired.dart:4777-4788` leaves Forward unwired even for contacts on those routes. `conversation_received_media_forward_test.dart` pumps the pure `ConversationScreen` with an injected callback; it does not exercise the real `ConversationWired` launcher or an outer production caller. Required disposition: land the smallest coherent outer-owner wiring for contact plus writable-group dependencies, keep the pure screen callback-bounded, and add a production-wired test that opens the real picker, selects a group, and observes the real group delivery leg. Verification: `flutter test test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart`, `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart --plain-name 'group forward target preserves publish contract and saves group owner'`, then `./scripts/run_test_gates.sh 1to1`.

- **B2 — Blocking required-gate evidence / contract:** the literal required `flutter analyze` command is unresolved. `/tmp/plan-232-flutter-analyze.log` records exit 1 with 1,629 diagnostics. The two diagnostics introduced in new Plan 232 files were subsequently removed/suppressed, `/tmp/plan-232-scoped-new-files-analyze-final.log` is clean, and the remaining diagnostics on touched existing files are outside Plan 232 hunks and already exist in HEAD. That supports "no identified Plan-232 diagnostic," but it does not replace or resolve the literal gate. The preflight explicitly says no known failure is pre-authorized, so the recorded nonzero run cannot be classified `accepted_known_failure` inside this execution contract. Required disposition: obtain an outer contract tightening that explicitly authorizes and defines the repo-wide analyzer baseline (then rerun the literal command and compare it), or make the literal command pass without scope drift. Verification: the exact repository-root command `flutter analyze`; a scoped `dart analyze` command is not sufficient.

- **B3 — Blocking operation-token regression gap:** the implementation structure is safe on inspection—`DefaultShareBatchDeliveryCoordinator._sendToContact` accumulates all processed attachments and calls `sendChatMessage` once per unique contact, so receiver dedup is applied once to a whole message rather than once per attachment, and separate recipients have independent receiver stores. The required causal proof is still absent: TC-232-12 sends text-only payloads, while TC-232-06 uses one source file. No landed test forwards two visual attachments under one operation token, proves both receiver attachments survive, then proves operation A redelivery dedups while operation B with the same source attachments persists. Required disposition: strengthen the named operation-A/B integration (or an equally direct receiver fixture) with two attachments and retained per-operation tokens. Verification: `flutter test test/features/conversation/integration/two_user_message_exchange_test.dart --plain-name 'same content explicit forwards persist while each operation redelivery key dedups'` and `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart --plain-name 'multi-target media forward preprocesses once and encrypts/uploads separately per contact'`.

- **B4 — Blocking edit/retry regression gap:** TC-232-11E's named test checks the sender row and decrypted outbound edit only; it never invokes `handleIncomingChatMessage` and therefore does not prove the receiver existing row retains `dedupKey`/`isForwarded`. TC-232-11 manually seeds one in-memory unacked envelope and calls `retryUnackedMessages`; it does not drive the failed-send or incomplete-upload retry paths changed in `retry_failed_messages_use_case.dart` and `retry_incomplete_uploads_use_case.dart`, reopen a repository, deliver to a receiver, or prove one marked destination row after recovery. Required disposition: add receiver edit/update proof and a failure/reopen/retry fixture that exercises the changed production retry seams while preserving direct owner/bookmark/playback/path state. Verification: `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart --plain-name 'edit preserves forwarded marker and operation dedup token end to end'`, `flutter test test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart`, and the focused changed retry-use-case tests.

- **B5 — Blocking migration/device contract gap:** the production v97 registry, order, guarded migration, default/CHECK, v96 host owner rows/indexes, actual-entry rerun, downgrade refusal, wrong-password failure, and Android/iOS runs are present and green. The named host migration test checks an invalid update but not the required invalid insert and contains no `ConversationMessage.fromMap`/`toMap`/`copyWith` marker proof. The device fixture contains only a direct media row, not the contract's complete-v96 direct/group/unresolved predecessor rows, so the device evidence is narrower than TC-232-09. Required disposition: add the missing insert/model assertions and complete the device predecessor fixture without weakening its actual-entry, cipher, downgrade, wrong-password, and reopen checks. Verification: `flutter test test/core/database/migrations/097_direct_message_forwarded_test.dart`, the exact full-chain registry command, and both pinned device commands already recorded in the Executor ledger.

- **B6 — Blocking direct-boundary regression gap:** TC-232-05's named production-contact test does not include its required external-Share control, and `share_to_contact_smoke_test.dart` never asserts `forwardProvenance == null`, `isForwarded == false`, or an ordinary fresh dedup key. TC-232-06 asserts source file bytes but does not seed or compare the source attachment's stored key/nonce/blob metadata, which the Test Notes require to remain byte-equal. Required disposition: add the real-contact external-share negative and a source-metadata preservation fixture while retaining distinct destination id/key/nonce assertions. Verification: `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart --plain-name 'production contact leg remints identity and persists forward provenance per target'`, `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart --plain-name 'multi-target media forward preprocesses once and encrypts/uploads separately per contact'`, and `flutter test test/features/share/integration/share_to_contact_smoke_test.dart`.

- **B7 — Blocking accessibility/localization regression gap:** TC-232-15's named test only finds the Forward action key and checks `takeException()` for German/Arabic. It does not enable/assert semantics, verify translated action/marker text, exercise the caption/target-count/partial-result strings named by the contract, or render the marker in the 320x568 RTL fixture. Required disposition: strengthen the named widget test to causally assert those localized and semantic surfaces without overflow. Verification: `flutter test test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart --plain-name 'forward flow is localized RTL-safe and semantics-labelled'` and `flutter test test/l10n/l10n_integrity_test.dart`.

- **B8 — Blocking done-criterion evidence:** no mutation-run evidence exists for the explicit done item requiring source-token reuse, retry-remint, contact-leg bypass, marker/edit drop, id/key reuse, CHECK removal, vacuous migration rerun, and transport-boundary mutations to re-red. The initial TC-232-01 compile RED is not a substitute for these representative mutations. Required disposition: run and persist bounded mutation proofs against the named focused tests, restore each mutation, and rerun the affected green slices. Verification: each mutated focused command must exit nonzero for the intended assertion, followed by the corresponding unmutated commands from TC-232-01/04/05/06/08/11/11E/14 passing.

### Non-blocking finding

- **N1 — Concurrent/unattributed worktree artifact:** comparison of `/tmp/plan-232-worktree.before` with the current all-untracked status shows the formatter incident's 173 baseline-clean outside-scope files are no longer dirty. Current-only paths are the attributable Plan 232 set plus unrelated `Test-Flight-Improv/252-review-fixlist.md`; several baseline group-plan/test paths disappeared or changed from untracked to tracked/modified during execution, consistent with concurrent user-owned work. QA did not attribute, edit, or revert these paths. Keep `252-review-fixlist.md` and the concurrent group/Graphify/Test-Flight changes excluded from any Plan 232 commit or verdict.

### Evidence checked and decisions

- All named focused logs, the 1,644-test curated `1to1` rerun, 294-file `core-host-all` rerun, Android physical and iOS simulator SQLCipher logs, registration/dry-run records, and discovery TSV end in pass. Their assertions remain subject to B1 and B3-B8 where the landed fixture is weaker than the contract.
- The Plan 231 transport-inventory update is a legitimate reviewed Plan 232 exception, not a raw transport bypass: it admits exactly one existing picker route plus its required `p2pService`/bridge references, retains zero raw `sendMessageWithReply`, `storeInInbox`, and `ShareBatch` sites, its focused test and curated lane pass, and the Go/relay baseline comparisons remain byte/status clean.
- Viewer-current versus bubble-all selection, incoming/direct-owner fail-closed filtering, direct marker inner-only payload encoding, group destination owner use with no group marker field, and no Go/relay changes are source-supported. The operation-token multi-attachment behavior is structurally sound but remains blocked on the causal regression in B3.
- Lightweight QA reruns/checks: exact five-file dual-array and host dry-run counts were `1/1/1`; the device proof has one `ignored` and zero executable discovery records; `git diff --check` exited 0; both Go/relay baseline `cmp` commands exited 0.

### Exact next Executor scope

1. Fix only B1 and the missing/underpowered tests in B3-B7; do not touch Go/relay, group payload/model tables, announcements, private-media policy, or unrelated concurrent files.
2. Persist and run the B8 bounded mutation evidence, then rerun only the affected focused commands plus the curated `1to1`/`core-host-all` families justified by the final diff.
3. B2 requires outer contract authority or a literal passing analyzer; it must not be replaced by scoped analysis. Return to a fresh QA Reviewer only after that required-gate issue has a valid disposition.

## Fix Pass 1 Evidence

### Executor disposition

- Status: `ready_for_qa`.
- Counter: `fix_passes = 1`.
- Scope: only the independent review's B1-B8 findings. This Executor did not perform the independent QA rerun and does not set the final plan verdict.
- Lasting production edits from this pass are limited to `lib/main.dart`, the 1:1 routes in `first_time_experience_wired.dart`, `feed_wired.dart`, `orbit_wired.dart`, and `posts_wired.dart`, plus `handle_incoming_chat_message_use_case.dart`. Lasting test edits are limited to the received-media widget, two-user operation-token, edit receiver, retry round-trip, v97 host migration, share coordinator, and SQLCipher device proof files.
- No lasting fix-pass edit exists in Go/relay, group payload/model tables, announcements, private-media policy, gate scripts, or core production schema/migration code. Temporary mutations were restored before final evidence.

### B1-B8 disposition

| Finding | Fix-pass disposition | Causal evidence |
|---|---|---|
| B1 production wiring | Resolved for Executor handoff. Both `main.dart` 1:1 routes now provide `imageProcessor` and all five group-forward dependencies. Every other app-owned `ConversationWired` route provides the group dependencies; `PostsWired` now accepts and forwards them. A production-wired widget test opens the actual picker, exposes a writable group, selects it, invokes the actual picker delivery callback, and observes the group upload/publish, message row, and group-owned attachment. | `flutter test test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart --plain-name 'production-wired forward opens picker and delivers to a writable group'` passed; `/tmp/plan-232-fix1-b1-production-wired-rerun2.log`. The full widget file also passed at `/tmp/plan-232-fix1-focus-widget-full.log`. |
| B2 analyzer | Exact non-widening baseline proven. Literal `flutter analyze` at detached HEAD `c88bf7a39` and in the final worktree both exit 1 with 1,627 diagnostics. After retaining analyzer bullet diagnostics, removing line/column coordinates, and LC-sorting as a multiset, `cmp` exits 0 with `new=0` and `resolved=0`. This is not recorded as a zero-exit analyzer pass; it is an exact unchanged repository baseline for QA classification. | HEAD: `/tmp/plan-232-fix1-analyze-head.log` and `.normalized`; final: `/tmp/plan-232-fix1-analyze-current-restored.log` and `.normalized`; deltas: `/tmp/plan-232-fix1-analyze-restored-{new,resolved}.normalized`. |
| B3 operation A/B | Resolved. The named receiver integration sends two visual attachments under operation A and B, persists both attachments for both explicit operations, and dedups A and B redelivery independently. The strengthened test exposed a real receiver-sanitizer defect: its rebuilt payload omitted `isForwarded`; the bounded production fix now carries `payload.isForwarded`. | `flutter test test/features/conversation/integration/two_user_message_exchange_test.dart --plain-name 'same content explicit forwards persist while each operation redelivery key dedups'` passed; `/tmp/plan-232-fix1-b3-operation-ab-green.log`. Multi-target encryption/publish also passed at `/tmp/plan-232-fix1-b6-crypto.log`. |
| B4 edit/retry | Resolved. The edit test now invokes the receiver handler against an existing row and proves marker/dedup survival. The retry fixture drives production incomplete-upload recovery, repository reopen, receiver delivery, a later failed-message retry after another reopen with no reusable envelope, receiver redelivery dedup, exactly one marked destination, and preserved direct owner/bookmark/playback/path/crypto state. | Edit named slice passed at `/tmp/plan-232-fix1-b4-edit.log`; retry round trip passed at `/tmp/plan-232-fix1-b4-retry-roundtrip-rerun2.log`; full changed retry-use-case suites passed at `/tmp/plan-232-fix1-focus-retry-{failed,incomplete}.log`. |
| B5 migration/device | Resolved. The host test now proves invalid INSERT rejection, `ConversationMessage.fromMap`/`toMap`/`copyWith` marker behavior, legacy false, exactly two actual entry runs, and absence of the equal-version vacuous call. The device predecessor now includes direct, group, and unresolved attachment rows and verifies all three after actual v97 migration/reopen while retaining cipher/downgrade/wrong-password proof and direct owner state. | Host migration passed at `/tmp/plan-232-fix1-b5-host-migration-post-contract.log`; registry slice passed at `/tmp/plan-232-fix1-focus-registry.log`; pinned Android `21071FDF600CSC` and iOS simulator `674DFFF6-5F38-4235-93F6-AF7FBF86AE65` passed at `/tmp/plan-232-fix1-device-{android,ios}.log`. |
| B6 boundary/crypto | Resolved. The production contact test now includes an external-OS-share negative with no forward provenance/marker and an ordinary fresh dedup key. The crypto test seeds source attachment key/nonce/blob metadata, proves it remains unchanged, and retains distinct destination id/key/nonce proof. | Named production contact and multi-target tests passed at `/tmp/plan-232-fix1-b6-{contact,crypto}.log`; external-share preservation passed at `/tmp/plan-232-fix1-focus-external-share.log`; media encryption preservation passed at `/tmp/plan-232-fix1-focus-media-encryption.log`. |
| B7 accessibility/localization | Resolved. The compact German/Arabic fixture enables semantics, renders the marker, verifies the translated Forward action, RTL direction, actual picker route, translated caption and target count, exact localized partial-result summary, and no overflow at 320x568. | Named widget slice passed at `/tmp/plan-232-fix1-b7-l10n-widget-green2.log`; full localization suite passed at `/tmp/plan-232-fix1-focus-l10n.log`. |
| B8 mutations | Resolved for Executor evidence. Each of the eight bounded mutations exited 1 for the intended causal assertion; each mutation was restored and every affected slice reran green. | Mutation and restored-green ledger below. |

### Final gate ledger

| Gate | Result | Evidence |
|---|---|---|
| Complete affected focused host set | Passed: full received-media widget, group-owner coordinator slice, v97 registry slice, external-share smoke, 1:1 media encryption, Plan 231 boundary inventory, and both changed retry-use-case files. | `/tmp/plan-232-fix1-focus-{widget-full,group-owner,registry,external-share,media-encryption,plan231-boundary,retry-failed,retry-incomplete}.log` |
| Curated `1to1` | `./scripts/run_test_gates.sh 1to1` passed, 1,645 tests. | `/tmp/plan-232-fix1-gate-1to1.log` |
| SQLCipher Android | Exact pinned device command passed on physical Android `21071FDF600CSC`. | `/tmp/plan-232-fix1-device-android.log` |
| SQLCipher iOS | Exact pinned device command passed on simulator `674DFFF6-5F38-4235-93F6-AF7FBF86AE65`. | `/tmp/plan-232-fix1-device-ios.log` |
| Literal analyzer | Both literal commands exit 1 with 1,627 issues; normalized HEAD/current multisets are byte-identical, `new=0`, `resolved=0`. Classification: `accepted_non_widening_baseline_for_qa_review`, not zero-exit pass. | `/tmp/plan-232-fix1-analyze-head.log`; `/tmp/plan-232-fix1-analyze-current-restored.log`; normalized/delta files beside them |
| Hygiene/scope | `git diff --check` exited 0. Go/relay status and binary-diff comparisons against the preflight baselines both exited 0. | `/tmp/plan-232-fix1-go-relay-{status,diff}.after`; `/tmp/plan-232-go-relay-{status,diff}.before` |
| Reverse impact | One required `python3 graphify-arch/tdd_context.py affected <six final app-owned production files> --budget 600` query passed; its importer shortlist was verified by source inventory and the focused/curated gates. No Executor refresh ran. | `/tmp/plan-232-fix1-graph-affected.log` |

- `core-host-all` was intentionally not duplicated in fix pass 1: this pass made no lasting core production schema/migration/code change, while the initial Executor's core family evidence remains green.
- Registration/dry-run/discovery checks were intentionally not duplicated: this pass did not change a gate or discovery script, while the independent review already confirmed the initial registrations.
- Expensive green gates were not rerun after final comment/format-only hygiene; the final exact analyzer comparison and `git diff --check` cover that non-semantic cleanup.

### Bounded mutation ledger

| Mutation | Expected RED | Restored GREEN |
|---|---|---|
| Source-token reuse (`parent.dedupKey ?? parent.id`) | exit 1; `/tmp/plan-232-fix1-mutation-source-token-reuse.log` | `/tmp/plan-232-fix1-mutation-green-source-token.log` |
| Incomplete-upload retry remints dedup to message id | exit 1; `/tmp/plan-232-fix1-mutation-retry-remint.log` | `/tmp/plan-232-fix1-mutation-green-retry.log` |
| Coordinator bypasses production contact leg | exit 1; `/tmp/plan-232-fix1-mutation-contact-bypass.log` | `/tmp/plan-232-fix1-mutation-green-contact.log` |
| Edit drops the forwarded marker | exit 1; `/tmp/plan-232-fix1-mutation-marker-edit-drop.log` | `/tmp/plan-232-fix1-mutation-green-edit.log` |
| Forward reuses a constant attachment id/key owner | exit 1; `/tmp/plan-232-fix1-mutation-id-key-reuse.log` | `/tmp/plan-232-fix1-mutation-green-id-key.log` |
| v97 `CHECK` constraint removed | exit 1; `/tmp/plan-232-fix1-mutation-check-removal.log` | `/tmp/plan-232-fix1-mutation-green-check-rerun.log` |
| Second actual migration run replaced by equal-version registry guard | exit 1; `/tmp/plan-232-fix1-mutation-vacuous-rerun.log` | `/tmp/plan-232-fix1-mutation-green-check-rerun.log` |
| Direct transport source admits a relay-boundary token | exit 1; `/tmp/plan-232-fix1-mutation-transport-boundary.log` | `/tmp/plan-232-fix1-mutation-green-boundary.log` |

All eight persisted `.exit` files contain `1`. The combined restored command completed with exit 0. No mutation token remains in production source; the relay spelling retained in the boundary test is the assertion's intentional forbidden-token fixture.

### Remaining uncertainty for independent QA

- The repository-wide analyzer is still nonzero, but the literal detached-HEAD comparison proves this work neither adds nor removes any of its 1,627 normalized diagnostics. Independent QA must decide whether that exact non-widening evidence satisfies B2's tightened disposition; the Executor does not relabel it as a zero-exit pass.
- `PostsWired` has no app-owned construction site under `lib/`; its internal 1:1 route is nevertheless now dependency-capable. All app-owned direct `ConversationWired` constructor sites are explicitly wired and source-inventoried.
- No other B1-B8 uncertainty is known. Unrelated Test-Flight, Graphify, `info.plist`, `252-review-fixlist.md`, and concurrent group work remains user-owned and excluded.

## QA Review — Fix Pass 1

### Reviewer disposition

- Disposition: `blocking_findings`.
- Reviewer: fresh independent QA after Executor fix pass 1.
- Production/test edits by QA: none. QA updated only this plan's progress and review documentation.
- Expensive passing gates and device builds were not duplicated. QA inspected the scoped diff, the exact persisted logs, all eight mutation failures/restored greens, and the attributable status. QA reran only `flutter test test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart --plain-name 'forward flow is localized RTL-safe and semantics-labelled'`; it passed.

### Prior B1-B8 status

| Prior finding | QA fix-pass-1 disposition | Evidence and decision |
|---|---|---|
| B1 production wiring | `pass` | Every app-owned `ConversationWired` construction site under `lib/` now supplies `imageProcessor` and the contact/group forwarding dependencies: two in `main.dart`, two in `feed_wired.dart`, and one each in first-time home, Orbit, and the dependency-capable Posts route. The production-wired widget opens the actual picker, exposes/selects a writable group, runs the real coordinator group branch, publishes, persists one group message, and saves one `MediaOwnerLane.group` attachment. Exact log: `/tmp/plan-232-fix1-b1-production-wired-rerun2.log`; the full widget file also passes at `/tmp/plan-232-fix1-focus-widget-full.log`. |
| B2 analyzer | `pass` as `accepted_known_failure` | The literal repository-root `flutter analyze` command ran at detached HEAD `c88bf7a39` and in the restored final worktree; both exit 1 with 1,627 diagnostics. The normalized diagnostic multisets are byte-identical, and both new/resolved delta files are empty. The binding done criterion is explicitly “`flutter analyze` has no new issues,” not “zero analyzer diagnostics”; the preflight's no-preauthorization rule requires persisted triage before classification, which this exact baseline comparison supplies. Evidence: `/tmp/plan-232-fix1-analyze-head.log`, `/tmp/plan-232-fix1-analyze-current-restored.log`, their `.exit`/`.normalized` files, and `/tmp/plan-232-fix1-analyze-restored-{new,resolved}.normalized`. This is accepted pre-existing analyzer debt, not a zero-exit pass or a scoped-analysis substitution. |
| B3 operation A/B | `pass` | The named encrypted-v2 integration now sends image+video attachments under operation A, proves two receiver attachments, dedups a re-minted A delivery, persists operation B with the same content and a new token, proves both B attachments, and dedups B independently. The receiver sanitizer now retains `payload.isForwarded`. Exact log: `/tmp/plan-232-fix1-b3-operation-ab-green.log`. |
| B4 edit/retry | `blocking remainder`; continued as B9 | The receiver edit handler proof is causal and green, and the retry fixture genuinely invokes both production retry use cases. However, its claimed reopen/local-state proof is manual in-memory reseeding rather than a close/reopen of durable state. Details and required disposition are B9 below. |
| B5 migration/device | `pass` | The host fixture proves invalid INSERT and UPDATE rejection, `ConversationMessage.fromMap`/`toMap`/`copyWith` behavior including legacy false, two direct invocations of the actual 097 registry entry, and complete v96 direct/group/unresolved owner rows/indexes. Both pinned SQLCipher runs use the complete predecessor fixture and pass actual 097 rerun, wrong-password rejection, downgrade refusal, and correct reopen. Evidence: `/tmp/plan-232-fix1-b5-host-migration-post-contract.log`, `/tmp/plan-232-fix1-focus-registry.log`, and `/tmp/plan-232-fix1-device-{android,ios}.log`. |
| B6 external/crypto boundary | `pass` | The production contact test leaves `sendToContactFn` null, proves forward provenance/marker/token for two contacts, and then proves an external Share produces `isForwarded == false` with an ordinary fresh id-based dedup key. The crypto fixture preserves the source blob id, key, nonce, scheme, path, bookmark/playback state, and source bytes while destination attachments have distinct ids/keys/nonces. Evidence: `/tmp/plan-232-fix1-b6-{contact,crypto}.log` plus the external-share and media-encryption sentinels. |
| B7 accessibility/localization | `pass` | The German/Arabic 320x568 fixture enables semantics, renders the localized marker and action, checks RTL direction, caption, target count, exact partial-result summary, and no overflow. The persisted exact slice and localization suite pass; QA's same exact slice rerun also passed. Evidence: `/tmp/plan-232-fix1-b7-l10n-widget-green2.log` and `/tmp/plan-232-fix1-focus-l10n.log`. |
| B8 mutations | `pass` | All eight `.exit` artifacts contain `1`; the logs show intended failures for source-token reuse, retry remint, production-contact fallback removal, edit marker drop, attachment-id reuse, CHECK removal, vacuous actual-entry rerun, and a forbidden transport token. Each affected restored slice ends `All tests passed!`; current source retains no mutation token outside the boundary test's intentional forbidden-string fixture. |

### Blocking finding

- **B9 — Blocking TC-232-11 restart/persistence regression gap:** `test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart:60-82` creates fresh `InMemoryMessageRepository`/`InMemoryMediaAttachmentRepository` instances and manually saves the same objects read from the first pair. At `:171-185` it repeats that pattern, explicitly seeds `status: 'failed'`/`wireEnvelope: null`, and manually copies the already-uploaded attachments into another fresh in-memory pair. No repository or database is closed and reopened, no row is rehydrated through production map/DB helpers, and bookmark/playback state is constructor-seeded rather than changed through the owner-aware local-state API. The later assertions therefore prove the production incomplete-upload and failed-send retry functions do not overwrite already-present fields, but they cannot catch marker/token/owner/viewer-state loss across the required restart boundary. The repository already supplies the appropriate real DB owner-aware fixture in `test/shared/fixtures/media_repository_real_db_fixture.dart`; the Test Contract explicitly names a real owner-aware repository and repository reopen for TC-232-11. Required disposition: strengthen only the named retry round-trip fixture so the forwarded message and direct-owned attachment are durably stored, local bookmark/playback state is applied through the repository boundary, the backing store/repository handle is actually closed and reopened before the incomplete/failed retry legs, and the receiver still ends with exactly one marked/tokened direct-owned row. Do not change production code unless that causal test exposes a real defect. Verification: `flutter test test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart`, `flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart`, and `flutter test test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`.

### Non-blocking findings

- No new N2+ finding. Prior N1 remains applicable: unrelated Test-Flight, Graphify, `info.plist`, `252-review-fixlist.md`, and concurrent group changes are user-owned and must remain excluded from the Plan 232 patch/verdict.

### Evidence checked and decisions

- Fix-pass focused logs, the 1,645-test curated `1to1` gate, prior 294-file `core-host-all`, Android/iOS SQLCipher proofs, registration/discovery evidence, and all mutation/restoration logs end in the recorded outcomes. Passing broad gates were not rerun merely to duplicate trustworthy evidence.
- `git diff --check` exits 0. Both current Go/relay status and binary diff compare byte-clean against `/tmp/plan-232-go-relay-{status,diff}.before`.
- The Plan 231 exception remains exact: one `ShareTargetPicker` site, the corresponding bounded `widget.p2pService`/`widget.bridge` count changes, and zero raw `.sendMessageWithReply(`, `.storeInInbox(`, or `ShareBatch` sites in `conversation_wired.dart`. The focused Plan 231 boundary log passes at `/tmp/plan-232-fix1-focus-plan231-boundary.log`.
- The final worktree remains attributable only after excluding the recorded baseline/concurrent changes. QA did not edit or revert the unrelated Test-Flight/Graphify/`info.plist`/252/group paths.

### Exact next Executor scope

1. Fix only B9 in `test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart` and the minimum test fixture support required for a real durable close/reopen. Preserve the already-green edit, retry, migration, device, crypto, localization, and production wiring behavior.
2. Rerun the B9 named integration plus the complete failed-message and incomplete-upload retry test files. If the stronger test exposes a production defect, persist triage before the smallest causal fix and rerun only affected evidence.
3. Do not rerun device builds, `core-host-all`, analyzer baselines, or mutations without a relevant code/evidence change. Do not touch Go/relay, group payload/model tables, announcements, private-media policy, gate scripts, or unrelated concurrent paths. Return to a fresh independent QA Reviewer after the B9 evidence is durable.

## Fix Pass 2 Evidence

### Executor disposition

- Status: `ready_for_qa`.
- Counters: `fix_passes = 2`; `materialization_retries = 1` (the recovery did not increment `fix_passes`).
- Scope: only QA finding B9. This Executor did not perform independent QA and does not set or replace the final plan verdict.
- Production changes in this pass: none. No app-owned production, migration, gate-script, Go/relay, group, announcement, private-media, localization, or Graphify file was edited by this pass.
- Attributable files touched: `test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart`; `test/shared/fixtures/media_repository_real_db_fixture.dart`; this plan's heartbeat/evidence only.

### B9 disposition

- Resolved for Executor handoff. The named integration now creates separate sender and receiver file-backed SQLite databases through the shared production create/upgrade registry and uses real `MessageRepositoryImpl` plus owner-aware `MediaAttachmentRepositoryImpl` objects.
- The sender durably stores one forwarded message and one direct-owned video attachment. It applies local path, bookmark, playback, and pending state only through repository/DB helper APIs, then closes the database and reopens fresh repository objects before `retryIncompleteUploads`.
- After the real incomplete-upload retry, the test transitions the durable message to failed/no-envelope through `MessageRepository.saveMessage`, closes and reopens the backing database a second time, and invokes the real `retryFailedMessage` rebuild path.
- Both reopen generations prove stable operation token, forwarded marker, message id, attachment id/parent identity, direct owner, bookmark, playback position, local path, and uploaded encryption key/nonce. The shared test secure store intentionally survives handle replacement, matching production secure-storage lifetime.
- The receiver uses its own real database repositories. First delivery persists one marked/tokened direct-owned message/attachment; rebuilt-envelope redelivery returns `duplicate`; the final receiver query contains exactly one message and one attachment with the original identities and `MediaOwnerLane.direct`.
- The fixture enhancement is bounded: existing in-memory callers retain the default behavior; only an explicit file-backed fixture can call `reopen()`, and a reopen creates fresh message/media repository objects around a fresh database handle.

### Evidence ledger

All commands ran from `/Users/I560101/Project-Sat/mknoon-2/flutter_app`.

| Command | Result | Classification | Artifact |
|---|---|---|---|
| `flutter test test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart` | Exit 0; 1 test passed. | `passed` | `/tmp/plan-232-fix2-b9-roundtrip-green.log` |
| `flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart` | Exit 0; 32 tests passed. | `passed` | `/tmp/plan-232-fix2-retry-failed.log` |
| `flutter test test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart` | Exit 0; 30 tests passed. | `passed` | `/tmp/plan-232-fix2-retry-incomplete.log` |
| `git diff --check` | Exit 0; no whitespace errors. | `passed` | `/tmp/plan-232-fix2-diff-check.log` |
| `git status --short --untracked-files=all -- go-mknoon go-relay-server \| tee /tmp/plan-232-fix2-go-relay-status.after \| cmp -s - /tmp/plan-232-go-relay-status.before` | Exit 0; status is byte-identical to the preflight baseline. | `passed` | `/tmp/plan-232-fix2-go-relay-status.after` |
| `git diff --binary -- go-mknoon go-relay-server \| tee /tmp/plan-232-fix2-go-relay-diff.after \| cmp -s - /tmp/plan-232-go-relay-diff.before` | Exit 0; binary diff is byte-identical to the preflight baseline. | `passed` | `/tmp/plan-232-fix2-go-relay-diff.after` |
| `dart format test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart test/shared/fixtures/media_repository_real_db_fixture.dart` | Exit 0; only the two explicit files were formatted, never a directory. | `passed` | command output only; no separate log |

- Final scoped status is recorded at `/tmp/plan-232-fix2-scoped-status.log`; it names only this plan, the B9 test, and the shared fixture from this pass's allowed work surface.

### Failure triage and dispositions

| Failure | Persisted evidence | Classification and disposition |
|---|---|---|
| First B9 run rejected playback state for an image attachment. | `/tmp/plan-232-fix2-b9-roundtrip.log` | Fixture-caused: playback is valid only for video. The causal fixture became a video; production was correct and unchanged. |
| Next run expected the first send to have no wire envelope, but the fake transport retained a valid inbox-custody envelope. | `/tmp/plan-232-fix2-b9-roundtrip-rerun.log` | Fixture transition assumption: B9 needs the later failed retry to prove envelope rebuilding. Status and null envelope are now written together through the real message repository before close/reopen; production was unchanged. |
| Next run lost local path because the fake upload result returned the constructor's null path. | `/tmp/plan-232-fix2-b9-roundtrip-rerun2.log` | Fixture-caused after source inspection: production `uploadMedia` initializes `storedPath` from `localFilePath` and returns that path (or its durable relative replacement) on success. The fake now returns its `localFilePath`; no production defect or edit was justified. |

No required failure remains pending triage.

### Skipped evidence, scope guard, and remaining uncertainty

- Device builds, `core-host-all`, analyzer baseline comparison, mutations, curated `1to1`, registrations/discovery, and all other broad/focused suites were intentionally not rerun: fix pass 2 changed only one integration test and its shared real-DB test fixture, and QA's exact next scope authorized only the three recorded Flutter commands plus hygiene/baseline guards.
- Graphify affected/query/refresh was intentionally skipped because no app-owned production code changed; test/fixture-only work does not require graph impact work under the B9 contract.
- Unrelated Test-Flight plans, Graphify output/tooling, `info.plist`, `252-review-fixlist.md`, and concurrent group work remain user-owned and excluded. Go/relay status and binary diff are identical to their preflight baselines.
- No known B9 uncertainty remains for the Executor. Fresh independent QA must still inspect the scoped diff and evidence before the controller records any final verdict.

## QA Review — Fix Pass 2

### Reviewer disposition

- Disposition: `pass`.
- Reviewer: fresh independent QA after Executor fix pass 2.
- Production/test edits by QA: none. QA updated only this plan's progress and review documentation.
- Prior blocker B9 is resolved. No blocking QA finding remains. QA does not set the final plan verdict and did not refresh Graphify.

### B9 disposition

- **B9 — `pass`:** `MediaRepositoryRealDbFixture.create` now accepts a file path, opens SQLite through the shared production create/upgrade registry, and constructs real `MessageRepositoryImpl` and `MediaAttachmentRepositoryImpl` objects over production DB helpers. Its `reopen()` rejects the in-memory mode, closes the current database handle, and opens the same file with fresh message/media repository objects while intentionally retaining only the secure-key store, matching the production storage lifetime.
- The named integration writes the forwarded message and direct-owned video row through those repositories, then changes path, bookmark, playback, and upload status through owner-aware repository methods. It performs a real close/reopen before `retryIncompleteUploads`, proves marker/token/message/attachment/owner/viewer state came back through production row mapping, and invokes the actual incomplete-upload retry with only the upload boundary faked.
- The test then writes the failed/no-envelope transition through `MessageRepository.saveMessage`, performs a second real close/reopen, proves the row and attachment state again, and invokes the actual `retryFailedMessage` rebuild path. After both retry legs it verifies the stable operation token, forwarded marker, message and attachment identities, direct owner, local path, bookmark, playback position, and uploaded key/nonce.
- A separate file-backed receiver repository accepts the first rebuilt delivery, persists one marked/tokened direct-owned message and attachment, returns `duplicate` for the failed-retry redelivery, and still contains exactly one message and one attachment with the original identities. This closes the restart/persistence counterexample that the former in-memory reseeding could not exercise.

### Evidence checked

- Scoped diff: `test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart` and `test/shared/fixtures/media_repository_real_db_fixture.dart`; neither file was present as a preflight dirty path, and fix pass 2 touched no production file.
- Executor focused evidence: `/tmp/plan-232-fix2-b9-roundtrip-green.log` ends `All tests passed!`; `/tmp/plan-232-fix2-retry-failed.log` passes 32 tests; `/tmp/plan-232-fix2-retry-incomplete.log` passes 30 tests. The three earlier failing B9 logs match the persisted triage: invalid image playback, retained first-send envelope, then a fake upload returning a null path.
- Independent narrow verification: `flutter test test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart` exited 0 on the final formatted files; `/tmp/plan-232-qa-fix2-b9-rerun.log`.
- Scope/hygiene: current `git diff --check` exits 0. `/tmp/plan-232-fix2-go-relay-status.after` and `/tmp/plan-232-fix2-go-relay-diff.after` are byte-identical to their empty preflight baselines. `/tmp/plan-232-fix2-scoped-status.log` contains only this plan, the B9 integration, and the shared fixture.
- Graph reverse-impact shortlist was inspected from `/tmp/plan-232-qa-fix2-graph-affected.log`; load-bearing conclusions were verified in the current repositories/helpers and test source. QA did not run the final architecture refresh.

### Non-blocking findings

- No new non-blocking finding. Prior N1 remains: unrelated Test-Flight, Graphify, `info.plist`, `252-review-fixlist.md`, and concurrent group work are user-owned and remain excluded from the Plan 232 change set and verdict.

### Controller handoff

- No further Executor fix pass is required. The controller may proceed with the skill's single final `./graphify-arch/refresh_arch_graph.sh --incremental` for the coherent app-owned production changes from the overall execution, then persist the final `## Execution Result` verdict and evidence ledger.

## Execution Result

### Final verdict

- Verdict: `accepted`.
- Accepted at: 2026-07-10 14:59 CEST.
- Counters: `fix_passes = 2`; `materialization_retries = 1`.
- No blocking finding remains. All done-criteria checkboxes are closed from persisted causal, preservation, gate, device, mutation, scope, and independent-QA evidence.

### Invocation topology

- Controller: primary Codex execution controller.
- Executor: fresh implementation agent, followed by two bounded fix passes. The interrupted second fix pass was resumed once from its persisted triage without incrementing `fix_passes`.
- Independent QA used: yes. A fresh reviewer ran after the initial Executor, after fix pass 1, and after fix pass 2. The final QA disposition is `pass`.
- Local sequential fallback used: no.
- The controller ran the single required final incremental Graphify refresh only after independent QA passed.

### Files changed

- Forward model/application: `lib/core/services/share_intent_model.dart`; `lib/features/conversation/application/build_received_media_forward.dart`; `handle_incoming_chat_message_use_case.dart`; `send_chat_message_use_case.dart`; `retry_failed_messages_use_case.dart`; `retry_incomplete_uploads_use_case.dart`; `ConversationMessage`; `MessagePayload`; `message_repository.dart`; and `share_batch_delivery_coordinator.dart`.
- Direct UI and app wiring: `conversation_screen.dart`; `conversation_wired.dart`; `letter_card.dart`; `message_context_overlay.dart`; `main.dart`; and the 1:1 construction routes in Feed, first-time home, Orbit, and Posts.
- Persistence/localization: DB version 97, the shared production registry, `097_direct_message_forwarded.dart`, English/German/Arabic ARB files, and their generated localizations.
- Gate registration: `scripts/run_test_gates.sh`, `scripts/run_host_test_gates.sh`, and `scripts/check_reliability_simulation_discovery.sh`.
- Final Graphify output: the architecture graph/manifest and TDD overlay were refreshed by `./graphify-arch/refresh_arch_graph.sh --incremental`. Other Graphify/tooling dirt present at preflight remains user-owned.
- Excluded and preserved: all unrelated Test-Flight documents, `info.plist`, concurrent group work, `go-mknoon/`, and `go-relay-server/`. Plan 232 has no attributed Go/relay edit; a later concurrent Plan 252 edit to `go-relay-server/inbox_test.go` is recorded below rather than reverted or claimed here.

### Tests added or updated

- Added causal coverage for forward draft/eligibility, direct transport boundaries, durable retry round trip, conversation-to-picker wiring, DB v97, and the SQLCipher device boundary.
- Strengthened payload, edit, two-operation dedup, marker rendering, production contact/group delivery, failed-only picker retry, production migration-chain, Plan 231 route inventory, and the shared real-DB repository fixture.
- Fix pass 2 replaced the former in-memory restart simulation with two actual file-backed sender close/reopen cycles and a separate real receiver database.

### Final evidence ledger

All commands ran from `/Users/I560101/Project-Sat/mknoon-2/flutter_app`.

| Evidence | Command/result | Classification | Artifact |
|---|---|---|---|
| Causal RED | TC-232-01 exact slice exited 1 before production APIs existed. | `expected_red` | `/tmp/plan-232-tc01-red.log` |
| Focused contract | All named forwarding, payload, migration, edit, marker, dedup, encryption, external-share, picker, and localization slices passed. | `passed` | Executor and Fix Pass 1 ledgers above |
| Curated lane | `./scripts/run_test_gates.sh 1to1` passed 1,645 tests after the final production fixes. | `passed` | `/tmp/plan-232-fix1-gate-1to1.log` |
| Core family | `./scripts/run_host_test_gates.sh core-host-all` passed 294 files after DB v97 integration. | `passed` | `/tmp/plan-232-gate-core-host-all-rerun.log` |
| Device SQLCipher | The exact v97 proof passed on Android `21071FDF600CSC` and iOS simulator `674DFFF6-5F38-4235-93F6-AF7FBF86AE65`. | `passed` | `/tmp/plan-232-fix1-device-{android,ios}.log` |
| Durable retry | B9 passed with real SQLite reopen; retry-failed passed 32 tests; retry-incomplete passed 30 tests. | `passed` | `/tmp/plan-232-fix2-{b9-roundtrip-green,retry-failed,retry-incomplete}.log` |
| Independent final QA | QA independently reran the B9 integration and inspected the durable repository/helper/retry boundaries. | `passed` | `/tmp/plan-232-qa-fix2-b9-rerun.log`; `QA Review — Fix Pass 2` |
| Mutations | All eight required mutations failed causally with exit 1; every restored slice passed. | `passed` | Fix Pass 1 mutation ledger above |
| Analyzer | Literal detached-HEAD and final `flutter analyze` both exit 1 with the same 1,627 normalized diagnostics; `new=0`, `resolved=0`. | `accepted_known_failure`: exact non-widening repository debt, not a zero-exit pass | `/tmp/plan-232-fix1-analyze-{head,current-restored}.log` and normalized/delta artifacts |
| Registration/discovery | New host tests occur exactly once in both 1:1 arrays; host dry-run selects them; SQLCipher proof has one ignored and zero executable records. | `passed` | `/tmp/plan-232-host-dry-run.log`; `/tmp/plan-232-discovery-records.tsv` |
| Hygiene/scope | `git diff --check` passes. Both Go/relay preflight comparisons exited 0 through final QA and again at the 14:59 acceptance cut. A 15:02 current-worktree comparison is nonzero only because concurrent Plan 252 then modified `go-relay-server/inbox_test.go`; its exact named tests match Plan 252 TC-02/TC-03 and are excluded from this verdict. | `passed_at_acceptance`; `late_concurrent_change_excluded` | `/tmp/plan-232-fix2-diff-check.log`; `/tmp/plan-232-go-relay-*.before`; `/tmp/plan-232-fix2-go-relay-*.after`; `/tmp/plan-232-post-acceptance-concurrent-go-{status,attribution,mtimes}.log` |
| Architecture graph | Final incremental refresh processed 40 changed code files and wrote a 45,315-node/70,718-edge graph plus the refreshed TDD overlay. | `passed` | `/tmp/plan-232-final-graph-refresh.log` |

### QA findings and dispositions

- Initial QA findings B1-B8 were resolved in fix pass 1: production group dependency wiring, exact analyzer comparison, two-attachment operation A/B proof, edit/retry fidelity, complete migration/device proof, external-share/crypto boundary, localized accessibility, and eight causal mutations.
- Fix-pass-1 QA accepted B1-B3 and B5-B8, accepted the analyzer only as a proven non-widening baseline, and raised B9 because restart persistence was still simulated with in-memory reseeding.
- Fix pass 2 resolved B9 without a production edit. Final QA verified real file-backed close/reopen, fresh repository objects, production DB mappings/helpers, both retry paths, preserved token/marker/identity/owner/viewer state, and exactly-once receiver persistence.

### Blockers and follow-up

- Blockers remaining: none.
- Non-blocking follow-up: repository-wide analyzer debt remains at the identical 1,627-diagnostic baseline and may be cleaned up independently. It was not widened by Plan 232.
- The unrelated dirty-tree paths recorded in preflight remain outside this verdict and were intentionally preserved.
- Post-acceptance concurrent-state note: `go-relay-server/inbox_test.go` became modified at 15:02:26 CEST, after the clean 14:59 Plan 232 acceptance guard. Its added `TestBuildIntroductionAcceptPushMessage_UsesActionAwareCopyAndStableRouteData` and expanded generic-copy test are literal Plan 252 TC-02/TC-03 owners. The current global guard therefore differs from Plan 232's empty preflight baseline, but this does not reopen Plan 232 because the late change is independently attributable, outside this invocation, and preserved untouched.

### Acceptance rationale

The change is safe to accept because its user-visible and persistence contracts are causally exercised, DB v97 is closed on host and both available device families, the curated and affected core lanes are green, all required mutations re-red, retries survive genuine database reopen, and fresh independent QA found no remaining counterexample. The operation stayed within the plan's Dart/Flutter boundary: Go/relay baselines were byte-identical through the acceptance cut, the later attributable Plan 252 relay test edit is excluded, group marker/payload behavior remains deferred, and no unrelated dirty-tree work is included in this verdict.
