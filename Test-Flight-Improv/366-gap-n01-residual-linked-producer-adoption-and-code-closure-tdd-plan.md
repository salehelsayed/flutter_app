# 366 - GAP-N01 Residual Linked Producer Adoption And N01 Closure

Status: post-execution-audit closed / N01 mechanism code complete / live acceptance blocked / admission default-off / not release-eligible
Type: Modification
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` A-18 and OQ-04; GAP-N01 / WP-01 in `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`; final code-closure adopter after Plans 360-365
Classification: implemented and host-verified; `N01_MECHANISM_CODE_COMPLETE` is recorded after the N01-wave `host-all` and combined audit, while `N01_LIVE_ACCEPTANCE_PROVEN` remains blocked pending the existing cumulative Android B1b plus its S2/deployment/rollback receipt
Closure tier: host implementation + N01 wave; optional existing Android pair acceptance

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-14 | Evidence Collector | GAP-N01 coverage; Plans 360-365; direct voice/share/send/edit/delete/private/retry owners; group sender/media/receive/retry/history/UI owners; test-gate inventory | The residual is real but bounded. Current reachable producers can reuse v108/v109/v114/v115 and `group_content_v1`; no new schema, relay action, queue, scheduler, or device harness is justified. One already-registered cumulative Android B1b remains unexecuted. | Draft one canonical contract for the remaining adopters and explicit non-adopters. |
| 2026-08-14 | Planner | This plan and `Test-Flight-Improv/00-INDEX.md` | Keep one final plan organized around one invariant: an initialized linked authority either gets exact per-device custody before egress, or the unsupported action refuses before effects. | Run `$tdd-review`; apply only verified contract corrections. |
| 2026-08-14 | Reviewer | Current Plan-366 draft; Dart/Go group-media scheme; four direct share entries; private v114/v108 Barrier B; mutation DB/retry; group caller/refusal seams; history listener/fallback/unread; all commands and registrations | Verdict was `plan-fixes-required`: one Plan-365 interop false green, one omitted direct-library producer, underspecified private/mutation/history boundaries, three group-forward refusals, and invalid proof paths/names. | Apply every verified correction; add no schema, protocol version, owner, or product surface. |
| 2026-08-14 | Arbiter | Revised canonical contract and reviewer evidence | `ready`: the corrected plan covers every current reachable producer or explicit non-adopter, and the new Go work is one literal validator alignment rather than a new relay design. | Execute from TC-366-00a/01a RED; stop on any hard scope guard. |
| 2026-08-14 | Plans 364/365 closure audit | Their final receipts; B1b runner/dispatcher/contracts; relay rollout contract; live device discovery; WP-01/WP-07 boundary | Plan 364 has no missing product code; Plan 365 has no remaining schema/device-code defect beyond TC-366-00a. Their one cumulative B1b is S2-blocked, and Plan 365's documented command falsely omits the media/voice opt-in. Current valid pair is USB Pixel 6 `21071FDF600CSC` first plus Android emulator `emulator-5554` second. | Consume the existing runner once with the media/voice opt-in after an authorized corrected reader-first relay deployment; restore both admissions off, then record one wave/audit receipt. Add no new harness or extra plan. |

## Problem And Evidence

- Behavior to improve: several shipping direct and group actions still refuse an
  initialized linked-device roster or fall through a singular/legacy owner,
  while group history-gap repair reuses the ordinary replay path that may stage
  notification-display custody. A linked account therefore cannot honestly
  claim GAP-N01 code closure after Plan 365.
- Impact: fresh voice, direct media share/forward, direct media caption EDIT,
  media-parent Delete for Everyone, fresh direct Protected/View-Once media,
  group quote/forward, and repaired group history do not yet share one truthful
  per-device notification-custody disposition.
- Confirmed direct producer gaps:
  - `sendVoiceMessage` hard-codes `canServeLinkedFanout: false` and later calls
    the singular coordinator at
    `lib/features/conversation/application/send_voice_message_use_case.dart:461-557`.
  - `ShareBatchDeliveryCoordinator._preflightDirectMediaAdmissions` does the
    same for external share, received-direct forward, direct-library batch
    forward, and group-to-contact forward at
    `lib/features/share/application/share_batch_delivery_coordinator.dart:410-435`,
    while `_sendFreshDirectMediaWithBlobCustody` uses singular preparation and
    settlement at `:1561-1749`. The distinct direct-library caller is reachable
    through `deliverDirectMediaBatchForwardStrict` at `:990-1115` and
    `lib/features/conversation/presentation/screens/conversation_wired.dart:6887-6950`.
  - the widget refuses media caption EDIT and media-parent DFE at
    `lib/features/conversation/presentation/screens/conversation_wired.dart:2794-2827`
    and `:3565-3601`; the exported use cases still select plural custody only
    for attachment-free/text mutations at
    `lib/features/conversation/application/send_chat_message_use_case.dart:858-866`
    and `lib/features/conversation/application/delete_message_use_case.dart:535-560`.
  - fresh Protected/View-Once image/video is a production-supported matrix at
    `lib/core/media/private_media_policy.dart:362-388`, but the composer refuses
    linked fanout at
    `lib/features/conversation/presentation/screens/conversation_wired.dart:3713-3728`;
    private preparation/retry remains singular at
    `lib/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart:311-485`,
    `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart:886-949`,
    and
    `lib/features/conversation/application/retry_failed_messages_use_case.dart:2294-2373`.
- Confirmed group gaps:
  - the strict sender rejects quote, forward, and private metadata at
    `lib/features/groups/application/send_group_message_use_case.dart:2371-2389`;
    the media owner drops/forces the quote/forward projection at
    `lib/features/groups/application/prepared_group_media_blob_custody_coordinator.dart:245-260`
    and `:546-557`; group share refuses strict forwarding before source work at
    `lib/features/share/application/share_batch_delivery_coordinator.dart:1199-1206`,
    again at dispatch at `:1378-1385`, and in the deep sender at `:2207-2218`.
  - full group media and voice quote callers independently refuse strict
    admission at
    `lib/features/groups/presentation/screens/group_conversation_wired.dart:2714-2761`
    and `:5185-5201`; raw-owner changes alone would leave the feature dead.
  - protected receive and the linked projection terminalize ordinary quote and
    forward metadata at
    `lib/features/groups/application/protected_group_content_receive.dart:500-539`
    and
    `lib/features/groups/presentation/screens/linked_group_conversation_wired.dart:1360-1373`.
  - history-gap repair calls `handleReplayEnvelope` from
    `lib/features/groups/application/drain_group_offline_inbox_use_case.dart:1818-1949`;
    that listener routes through the ordinary replay/display path at
    `lib/features/groups/application/group_message_listener.dart:1452-1470`
    and `:2255-2425`.
  - initialized legacy group-upload retry can still rebuild `allowedPeers` at
    `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart:1193-1229`
    instead of refusing a no-fingerprint/no-manifest generation before network.
- Confirmed Plan-365 interop false green: Dart produces and validates
  `blob_aes_256_gcm_v1` at
  `lib/features/groups/application/protected_group_media_manifest.dart:10,129-160`,
  while the relay accepts only `blob_aes_gcm_v1` at
  `go-relay-server/ack_custody.go:687-701`; the Go fixture repeats that wrong
  literal at `go-relay-server/ack_custody_protocol_test.go:1062-1093`, so its
  current green result cannot prove a real Dart manifest is accepted.
- Confirmed carried acceptance debt, not new product code:
  - Plan 364's only unchecked behavior is the existing cumulative B1b Android
    leg; its blob-free discussion/reaction implementation is otherwise closed.
  - Plan 365's only unchecked acceptance leg is that same B1b extended with one
    deterministic image and voice. Its documented gate command omits
    `MKNOON_B1B_PLAN365_GROUP_MEDIA=true`, although the runner defaults that
    extension off and asserts the media/voice verdicts only when it is true.
  - the cumulative runner already proves Plan-363 bootstrap/reopen, Plan-364
    offline discussion plus reaction ADD/REMOVE, and opt-in Plan-365 image/voice
    before terminal dissolve. Reuse it once; do not create Plan-366 device cases.
  - live execution needs a reader-first relay binary containing TC-366-00a,
    explicit S2 authorization for both custody admissions, and an immediate
    rollback-to-off receipt. These are external acceptance operations, not
    another application implementation slice.
- Existing coverage proves the current negative behavior, not the desired
  adopter: `TC-362-02a` voice/share refusal,
  `TC-362-02e` caption/DFE refusal, and `TC-365-02a` initialized quoted or
  forwarded group-media refusal all pass on this planning baseline.
- Missing coverage: no test currently proves all-target voice/four-share/private
  preparation plus settlement, per-target media-mutation v109 custody,
  quote/forward protected round trip, or a notification-inert history repair.
- Refuted findings:
  - fresh group-private authoring is not a current product surface: the full
    composer hard-codes ordinary policy, and
    `group_conversation_wired_test.dart::P268 group composer source has no private authoring API or mutable policy state`
    pins that fact. Do not invent a private lifecycle adopter here.
  - group post-send caption EDIT and group DFE have no shipping author model/UI;
    only device-local Delete for Me and compatibility receive exist. Do not add
    either action.
  - group avatar is configuration traffic and bypasses user-message
    notification production. Plan 363 already owns its authenticated metadata;
    blob fanout is a different feature.
  - DB v115 already represents per-recipient direct/group blob obligations and
    the signed content envelopes already carry quote/forward fields. A DB v116,
    new relay kind, or new wire protocol is not justified.
- Unresolved findings: none requiring a user choice. Fresh direct
  Protected/View-Once is reachable and notification-worthy, so this plan adopts
  it; the superficially similar group-private surface is receive-only and stays
  explicitly unsupported for initialized linked authoring.
- Affected production owners: direct voice/share/coordinator/send/edit/delete
  and retry files; the existing media/message repository interfaces,
  implementations, SQL helpers and bootstrap delegates needed by plural private
  Barrier B and media mutation; group sender/media/receive/retry/history/listener
  and linked UI files; and the existing relay group-manifest validator. Affected
  tests are the registered files named in the Test Contract. No new test
  harness is planned.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `bca7201d154029f0`; current and anchored on
  the post-Plan-365 working tree.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "Final GAP-N01 residual after Plan 365: sendVoiceMessage initialized linked roster refusal, ShareBatchDeliveryCoordinator external share, ConversationWired media caption EDIT and delete-for-everyone, SendGroupMessageUseCase quote forward private exclusions, notification-producing paths, tests and run_test_gates registrations" --profile tdd --budget 700`.
- Anchors: `sendVoiceMessage` ->
  `lib/features/conversation/application/send_voice_message_use_case.dart:49`;
  `ShareBatchDeliveryCoordinator` ->
  `lib/features/share/application/share_batch_delivery_coordinator.dart:287`;
  `ConversationWired` ->
  `lib/features/conversation/presentation/screens/conversation_wired.dart:377`.
- Surfaced proof/gate files:
  `send_voice_message_use_case_test.dart`,
  `share_batch_delivery_coordinator_test.dart`,
  `conversation_wired_test.dart`,
  `send_group_message_use_case_test.dart`,
  `p2p_service_inbox_ack_ordering_test.dart`, and
  `scripts/run_test_gates.sh`.
- Graph gaps requiring source search: private-media policy/retry shape,
  the direct-library producer, all three strict-group-forward refusals,
  history-gap listener/fallback/unread disposition, linked group projection,
  Dart/Go scheme parity, and exact curated registration were source-verified
  after the anchored query and the refined review query.
- Reuse rule: execution and review may reuse these anchors, but must re-read
  current source because the inherited Plan-365 worktree is intentionally
  dirty and may move before execution.

## Scope Contract And Guard

In scope:

- Repair the Plan-365 manifest interop literal: the relay accepts the canonical
  Dart-produced `blob_aes_256_gcm_v1`, its fixture uses that value, and the old
  relay-only alias is rejected. This changes no action, kind, envelope version,
  custody semantics, or deployment state.
- Adopt fresh direct voice and all four file-bearing direct share/forward
  entries into the existing Plan-362 exact-snapshot, encrypt-once,
  per-physical-target v114 blob plus v108 content owner.
- Adopt the existing supported fresh direct Protected image/video and View-Once
  image matrix into that same owner while retaining the incumbent private
  lifecycle lock and pending/completion CAS. There is one attachment, one
  ciphertext, and one canonical private completion, but N independent v114
  rows and N v108 ACK/expiry siblings. A stored/B pending advances only A's
  blob row; final B permits canonical completion and all-target settlement.
  Final-sibling v108 completion alone projects the final parent/cleanup. No v110
  token is fabricated, and the current v110-only transaction is not treated as
  private authority.
- Adopt ordinary direct-media caption EDIT and media-parent DFE (ordinary,
  Protected/View-Once, and disappearing) into the existing Plan-361 v109
  `DirectEventFanoutAuthoring` owner. Mutations never re-upload or re-encrypt
  blobs. Caption routing occurs only after persisted-media qualification. DFE
  stages every target inside the incumbent lifecycle lease before private or
  ordinary cleanup, performs zero cleanup on refusal, releases the lease before
  network, and drains every persisted sibling rather than the singular manual
  retry target.
- Preserve ordinary group `quotedMessageId` for reachable text, media, and voice
  authoring; preserve ordinary forwarded-media `isForwarded` from the verified
  source through Plan-365 preparation, survivor retry, signed receive, and the
  linked projection.
- Give history-gap repair an explicit notification-inert replay disposition:
  canonical timeline persistence remains, while it stages/promotes no display
  custody, performs no alias reconciliation/retry kick/local notification/tone,
  and creates no unread contribution. A duplicate repair preserves the
  canonical `readAt`; ordinary missed offline replay remains unread- and
  notification-eligible exactly once. Listener and no-listener fallback routes
  share this disposition.
- Refuse an initialized group's legacy/no-fingerprint/no-prepared-manifest
  upload retry before source preprocessing, `allowedPeers`, or network. Strict
  persisted survivors still drain before any live authority read; an
  uninitialized legacy group remains byte-equivalent.
- After all cases pass, update the GAP-N01 mechanism checkpoint and index with
  code-closure truth. Record `N01_MECHANISM_CODE_COMPLETE` only after the
  N01-wave `host-all` and combined post-execution audit pass; record
  `N01_LIVE_ACCEPTANCE_PROVEN` only after the cumulative Android B1b and
  rollback receipt also pass. Persistent activation, cohort/quota operations,
  mixed-version retirement, consolidated iOS, A-control compliance, and release
  remain WP-07.

Must preserve:

- Existing ordinary/disappearing direct linked initial fanout and durable
  survivor-first retry -> `TC-362-02a` / `TC-362-02b` sentinels.
- Existing single-primary Protected/View-Once initial and private restart
  lifecycle when the roster is uninitialized -> `TC-354-02b` and the private
  restart sentinel in `retry_incomplete_uploads_use_case_test.dart`.
- Private caption/text EDIT remains unsupported and fail-closed ->
  `send_chat_message_use_case_test.dart::TC-359-04a persisted private target defeats caller policy drift`.
- Unsupported private initial MIME/mode combinations remain all-zero; only the
  matrix in `private_media_policy.dart` is widened to linked targets.
- Plan-364 blob-free group and Plan-365 ordinary group media/voice behavior,
  including strict raw-sender omission refusal and exact survivor recovery.
- The canonical group-media scheme stays `blob_aes_256_gcm_v1`; the obsolete
  relay-only alias remains invalid after the bounded validator repair.
- Group-private receive/view privacy, no fresh private authoring, device-local
  group Delete for Me, and avatar/config behavior.
- Ordinary offline inbox replay still stages exactly one display claim; a
  history-repair duplicate cannot promote/create a claim or alter the canonical
  read state.
- Historical direct/group rows are never backfilled, fingerprinted, or promoted
  into protected custody. Uninitialized legacy send/retry/download behavior is
  unchanged.
- A missing quoted parent renders a bounded fallback; it does not start history
  fetch, generic group runtime, or another notification owner.

Hard `Do not`:

- Do not add DB v116, a table/index/column, backfill, accepted ledger, target
  hash/refcount, relay/native action or kind, envelope version, scheduler,
  selector, or generic linked runtime. The one relay edit is limited to the
  existing group-manifest scheme validator and its existing tests/contracts.
- Do not add a second direct/group blob coordinator, event outbox, display
  outbox, cleanup owner, retry family, or test harness. Add explicit branches
  to the incumbent owners and existing registered tests.
- Do not implement group-private fresh authoring, group EDIT/DFE, avatar-blob
  reliability, cross-device read clearing, generic history synchronization, or
  notification reconciliation redesign.
- Do not enable admissions or deploy/restart a relay during the implementation
  phase. The cumulative closure phase may do exactly one reader-first deploy and
  B1b only after separate explicit S2 authorization, then must restore both
  admissions off. Do not persist activation, claim iOS evidence, remove legacy
  compatibility, change quota policy, or claim release eligibility.

Deferred / accepted difference:

- Group-private linked authoring -> a future product-approved lifecycle adopter,
  because there is no fresh author surface today. Its legacy/uninitialized
  receive/view behavior remains supported.
- Direct private caption EDIT and unsupported private formats -> remain explicit
  product refusals, not missing custody paths.
- Group post-send mutation and avatar blob fanout -> separate features with no
  current notification-producing author path.
- Persistent activation/cohort/quota UX, mixed-version retirement, consolidated
  iOS and final release evidence -> WP-07. This plan consumes only the existing
  one-run B1b debt so the optional stronger live-acceptance verdict has no
  dangling Plan-363/364/365 checkbox.

Dependencies:

- Current Plan-360 addressing, Plan-361 v108/v109 event fanout, Plan-362
  v114 media fanout, Plan-364 `group_content_v1`, and Plan-365 v115 group media
  owners must remain present. Plan-365's default-off/live-acceptance blocker is
  not a host-code prerequisite.
- Plan-365's current Dart/Go scheme mismatch is a mandatory bounded baseline
  repair in TC-366-00a; group quote/forward work cannot claim GREEN while a
  canonical ordinary manifest is rejected by the relay validator.
- `N01_LIVE_ACCEPTANCE_PROVEN` additionally depends on separately authorized
  external S2:
  deploy a reader-first relay binary containing TC-366-00a, attest shared Redis
  plus media-filesystem readiness, temporarily report both custody-admission
  gauges as `1`, run the existing Android B1b with its Plan-365 extension
  enabled, then restart/restore both gauges to `0`. Without that authority, the
  code plan can complete but N01 remains `LIVE-ACCEPTANCE-BLOCKED`.
- Execution must stop and re-review if fresh direct private fanout cannot reuse
  the existing v114 rows, v108 siblings, and incumbent private lifecycle
  transaction without schema/protocol work; it must not smuggle a migration or
  new owner into this economy plan.

## Test Contract

Use the existing registered test owners. Every named case is added before its
production edit; current negative sentinels are replaced only where the desired
behavior intentionally changes.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-366-00a | A canonical Dart `group_media_manifest_v1` uses `blob_aes_256_gcm_v1`; the existing Go validator accepts that exact value and rejects the obsolete relay-only alias. All other manifest/kind/hash/recipient checks remain unchanged. | `upload_media_use_case_test.dart::TC-366-00a Dart group manifest scheme matches the relay validator`; `ack_custody_protocol_test.go::TestRelayNotificationClosure_GroupMediaBlobCustody/Dart_AES-256-GCM_scheme`; `relay_media_custody_contract_test.sh::TC-366-00a canonical group-media scheme parity` | Host Dart manifest fixture, real Go validator, existing rollout source contract | Current Dart output is rejected while the Go fixture's wrong alias passes -> update the existing validator/fixture/contract so only the production literal passes. | Restore `blob_aes_gcm_v1` in the validator or fixture -> the Go subtest/source contract red. | Exact Go and shell commands below; existing relay group-media family remains registered under the curated gates. |
| TC-366-01a | Fresh voice plus external share, received-direct forward, direct-library batch forward, and group-to-contact forward resolve one pre-effect contact snapshot. Initialized A/B encrypts each attachment once, stages all v114 rows before upload and all v108 siblings before settlement; fileless share and uninitialized legacy remain unchanged. A stored/B pending restart uses persisted rows with no source, roster read, remint, or re-encryption. An admitted voice lacking the exact plural capability and an external-share contact that drifts after preflight both refuse before any singular/legacy effect. | `send_voice_message_use_case_test.dart::TC-366-01a fresh voice stages exact linked targets before upload and settlement`; `send_voice_message_use_case_test.dart::TC-366-01a linked voice admission without plural custody refuses before legacy upload`; `conversation_wired_test.dart::TC-366-01a voice widget carries one admitted snapshot without a second roster read`; `share_batch_delivery_coordinator_test.dart::TC-366-01a four direct media entries share one artifact across exact linked targets`; `share_batch_delivery_coordinator_test.dart::TC-366-01a external linked admission refuses contact drift before legacy effects`; `conversation_wired_test.dart::TC-366-01a direct-library batch caller reaches the strict fanout entry`; `retry_incomplete_uploads_use_case_test.dart::TC-366-01a voice and four-share survivors reopen without source or roster`; `retry_failed_messages_use_case_test.dart::TC-366-01a failed voice and four-share drain persisted v114 before reconstruction` | Host fakes plus real temp files/artifact crypto; A/B, one-target, zero-target, fileless, direct-library caller, capability mismatch, post-preflight contact drift, and restart rows | Current voice/share admission says `canServeLinkedFanout: false` and strict delivery calls singular preparation -> all five initialized producers succeed only after the one exact admission snapshot is threaded into the existing fanout owner and settlement; an admitted operation cannot demote to singular/legacy after the snapshot. | Restore voice to `canServeLinkedFanout: false`, route the direct-library entry around preflight, call singular preparation, accept mismatched plural capability, re-read roster after preprocessing, or demote post-preflight drift to legacy -> its independent sentinel red. | Focused direct command below; existing paths are registered or run exactly; no new path. |
| TC-366-01b | Supported fresh direct Protected/View-Once initials publish one shared ciphertext and N exact v114 rows under the incumbent private lifecycle lock, then bind N v108 siblings through an explicit private Barrier-B branch with no v110 token. One attachment pending/completion CAS runs only after all blob targets are stored; per-target ACK retires only that sibling and final-sibling completion alone projects final parent/cleanup. Both retry families reopen persisted rows without source/roster. Uninitialized private, unsupported shapes, private EDIT, and linked receive privacy stay unchanged. | `media_attachment_repository_impl_test.dart::TC-366-01b private fanout atomically publishes N v114 rows without a v110 token`; `messages_db_helpers_test.dart::TC-366-01b private Barrier B binds N v114 rows to N v108 siblings atomically`; `message_repository_impl_test.dart::TC-366-01b message repository forwards plural private Barrier B without singular collapse`; `send_chat_message_use_case_test.dart::TC-366-01b protected and view-once settle exact per-target siblings with final-only projection`; `conversation_wired_test.dart::TC-366-01b supported private initials fan out while unsupported shapes refuse before effects`; `retry_incomplete_uploads_use_case_test.dart::TC-366-01b incomplete private fanout reopens byte-identically without roster`; `retry_failed_messages_use_case_test.dart::TC-366-01b failed private fanout drains persisted targets without singular assumptions`; `handle_incoming_chat_message_use_case_test.dart::TC-366-01b linked protected receive keeps physical transport and logical contact authority`; `production_application_bootstrap_phase_contract_test.dart::TC-366-01b production composes the plural private generation and Barrier-B delegates` | Host real-SQLite repository/SQL helpers, temp crypto, composition and receiver fakes; Protected image/video, View-Once image, A/B survivor, uninitialized and invalid-shape controls | Current composer refuses every linked private initial; generation, Barrier B, repository forwarding, sender settlement and both retries require exactly one row -> widen those existing owners for the exact private batch while crossed matrices remain zero-effect. | Reject private in generation/Barrier B, collapse the repository delegate to one row, accept a v110 token, project completion after A only, retain `rows.length == 1`, or omit bootstrap wiring -> the corresponding storage/sender/retry/composition sentinel red. | Focused direct command; shared core paths run exactly and remain registered for later wave `host-all`; no schema or new test path. |
| TC-366-02a | Ordinary media/voice caption EDIT first classifies the durable parent/attachments, then resolves one event-fanout snapshot, stages one exact v109 event per physical target before transport, and preserves every blob/attachment byte and generation. It works when media authoring is off but event fanout is on; an attachmentless caller snapshot cannot bypass persisted classification. | `send_chat_message_use_case_test.dart::TC-366-02a persisted media caption edit stages per-target v109 without touching blobs`; `conversation_wired_test.dart::TC-366-02a initialized media caption edit dispatches once and preserves draft on custody refusal`; `retry_failed_messages_use_case_test.dart::TC-366-02a failed media caption edit drains only persisted v109 siblings` | Host real repository/transport fakes; hydrated and forged attachmentless snapshots, selector split, A accepted/B pending | Current early fanout predicate excludes caller attachments before durable classification and the widget refuses initialized media -> defer routing until the existing media-caption qualifier succeeds, then delegate to `DirectEventFanoutAuthoring`. | Route before durable qualification, restore `!hasAttachments`, stage singular v109, or mutate any attachment/blob field -> sender/UI/retry sentinel red. | Focused direct command; files already in `ONE_TO_ONE_TESTS`. |
| TC-366-02b | Media-parent DFE for ordinary, Protected/View-Once, and disappearing parents uses an explicit lifecycle-safe DB qualification, then stages every physical target's v109 tombstone inside the incumbent lease before cleanup. Refusal performs zero cleanup; the lease releases before network; blob upload is zero. Global plural drain (not singular manual target reconstruction) retires A while retaining B and drains attachmentless B after restart. | `direct_reaction_inbox_custody_outbox_db_helpers_test.dart::TC-366-02b media DFE atomically qualifies ordinary private and disappearing parents for N v109 siblings`; `delete_message_use_case_test.dart::TC-366-02b media DFE stages all targets inside the lifecycle lease before cleanup`; `conversation_wired_test.dart::TC-366-02b initialized media DFE dispatches plural custody once`; `retry_failed_messages_use_case_test.dart::TC-366-02b attachmentless B drains from persisted v109 after A settles`; `private_media_cleanup_race_test.dart::TC-366-02b private DFE fanout stages or performs zero cleanup under the lease` | Host real DB plus deterministic lease/race/network hooks; policy matrix, A/B survivor, attachmentless post-cleanup row | Current application delegates only the text lane, DB fanout accepts only ordinary policy, and manual retry targets `message.contactPeerId` -> widen the incumbent DB/use-case branch and use the existing plural drain. | Restore ordinary-text-only qualification, release lease before stage, cleanup on refusal, or use singular manual retry -> DB/deletion/race/retry sentinel red. | Focused direct command; all existing paths are registered or run exactly. |
| TC-366-03a | Ordinary group quote metadata round-trips for text, image/video/audio, and voice through one signed `group_content_v1` event and exact per-device custody. Full composer media and voice callers reach the owner. Missing quoted parents render a local fallback without history/network lookup; malformed/private quote shapes still terminalize. | `send_group_message_use_case_test.dart::TC-366-03a strict ordinary quote preserves typed metadata for text media and voice`; `p2p_service_inbox_ack_ordering_test.dart::TC-366-03a quoted protected content commits before exact ACK`; `group_conversation_wired_test.dart::TC-366-03a text and media quote callers reach strict authoring`; `group_conversation_wired_test.dart::TC-366-03a voice quote caller reaches the prepared media owner`; `group_conversation_wired_test.dart::TC-366-03a linked quote renders a missing-parent fallback without fetch` | Host signed-envelope fakes plus DB-backed receiver; blob-free/media/voice, caller wiring, malformed and missing-parent rows | Current raw sender/media owner/receive/linked UI reject or omit the field, while media and voice callers refuse independently -> exact ordinary quotes commit/display through shipping callers. | Drop `quotedMessageId` in preparation/retry, restore either caller refusal, restore raw-sender rejection, or require parent lookup -> the corresponding owner/UI sentinel red. | Focused group command; group paths are registered; shared P2P proof runs exactly. |
| TC-366-03b | Verified ordinary received-group image/video forward to an initialized group passes all-strict pre-source admission, dispatch, and deep sender gates; retains operation identity and `isForwarded` through Plan-365 preparation, per-target manifest/content custody, survivor retry, protected receive, notification persistence, and linked rendering; never uses `allowedPeers`. Private/unverified source refuses before preprocessing. | `share_batch_delivery_coordinator_test.dart::TC-366-03b all-strict group forward reaches source verification and preparation`; `share_batch_delivery_coordinator_test.dart::TC-366-03b admitted strict group forward preserves provenance through dispatch`; `retry_incomplete_group_uploads_use_case_test.dart::TC-366-03b forwarded strict survivor preserves marker without source or authority read`; `p2p_service_inbox_ack_ordering_test.dart::TC-366-03b forwarded protected media commits marker before ACK`; `group_conversation_wired_test.dart::TC-366-03b linked projection presents ordinary forwarded media` | Host immutable-source/temp-file fakes plus protected receiver DB; all-strict target, A/B survivor and denied-source controls | Current pre-source helper, dispatch, and deep sender each refuse strict forward; coordinator later forces `isForwarded: false`; receive/UI reject it -> every existing gate admits only the verified ordinary forward and preserves the marker. | Independently restore `allowStrictFreshGroupMedia: false`, dispatch refusal, deep provenance refusal, forced-false staging, or `allowedPeers` fallback -> the named share/retry/receive sentinel red. | Focused group plus exact P2P command; existing paths are registered in `GROUP_TESTS`/`ONE_TO_ONE_TESTS`. |
| TC-366-04a | History-gap repair uses one explicit delivery source on both listener and fallback routes; persists authenticated canonical messages as locally read, creates/promotes no display custody, performs no alias reconciliation/display retry/compatibility notification/tone, and preserves canonical `readAt` on duplicate. A buffered reaction still applies, persists, emits to UI, and clears its buffer, but remains notification-inert. Ordinary missed replay remains unread- and display-eligible exactly once. | `drain_group_offline_inbox_use_case_test.dart::TC-366-04a listener and fallback history repair are locally read and notification inert`; `group_message_listener_test.dart::TC-366-04a history repair gates display alias retry and compatibility presentation`; `group_notification_display_outbox_wiring_test.dart::TC-366-04a history repair cannot stage or reconcile a display claim`; `group_notification_display_outbox_wiring_test.dart::TC-366-04a history repair flushes pending reaction notification-inert` | Host repository/listener/display/reaction fakes with persisted read-state assertions; fresh/duplicate repair, buffered reaction, unrelated ready-display, and ordinary replay controls | Current repair uses ordinary `replay`; listener stages/reconciles/retries/presents, new rows have null `readAt`, and pending-reaction flush independently stages/presents/retries -> an exact `historyRepair` disposition gates every display effect while preserving message/reaction persistence and local read state. | Route either branch as ordinary replay, pass display callbacks, reconcile/retry, present, leave a fresh repair unread, or let buffered-reaction flush stage/notify/retry -> history/listener/wiring sentinel red. | Focused group command; all four existing paths are already in `GROUP_TESTS`. |
| TC-366-04b | No-intent boundary: complete strict direct/group survivors drain before any authority read; initialized legacy/no-fingerprint group upload refuses before preprocessing, `allowedPeers`, or network; no direct/group historical row is promoted/backfilled; uninitialized legacy remains byte-equivalent. Explicit non-adopters remain absent/refused. | `retry_incomplete_group_uploads_use_case_test.dart::TC-366-04b strict survivors precede authority and initialized no-fingerprint retry refuses before network`; `115_group_media_blob_custody_test.dart::TC-366-04b migration remains no-backfill for historical attachment fingerprints`; `group_conversation_wired_test.dart::P268 group composer source has no private authoring API or mutable policy state`; `send_chat_message_use_case_test.dart::TC-359-04a persisted private target defeats caller policy drift` | Host retry/network counters plus v114-to-v115 migration fixture and source contract | Strict survivors already precede the live branch, but legacy group retry still computes `allowedPeers`; migration already preserves null fingerprints -> add only the post-survivor initialized refusal and retain no-backfill/non-adopter controls. | Move admission before strict-survivor lookup, allow one initialized legacy network call, or stamp a historical fingerprint -> retry/migration sentinel red. | Focused group/preservation commands; paths are registered in `GROUP_TESTS`, `ONE_TO_ONE_TESTS`, or migration inventory. |

### Test Notes

- TC-366-00a changes the Go fixture to the Dart literal before the validator,
  records the causal rejection, then changes only the validator literal. The
  old alias is a negative row, so accepting both strings is not GREEN.
- TC-366-01a/01b count snapshot reads, encryptions, artifact paths, blob calls,
  v108 stages, and per-recipient envelopes independently. An A/B assertion alone
  is insufficient if both rows accidentally carry A's key or manifest.
- TC-366-01b uses only the already-supported product matrix. Crossed
  MIME/media-type, Protected GIF/audio/file, and unsupported View-Once shapes
  must fail before crypto, file copy, DB mutation, or network. A stored/B
  pending leaves the canonical private parent pending; after B stores, the one
  completion CAS and N-sibling Barrier B are replay-safe.
- TC-366-02b proves the all-target DB stage and cleanup share the incumbent
  lifecycle lease, then proves the lease is released before network. Its
  attachmentless restart must drain B from the persisted event sibling rather
  than `message.contactPeerId`.
- TC-366-03a proves the protected receiver accepts typed metadata; it does not
  weaken malformed-field rejection or launch history synchronization for a
  missing quoted parent.
- TC-366-04a distinguishes `historyRepair` from ordinary `replay` by display
  rows, presentation calls, tones, alias reconciliation, and durable `readAt`,
  not by log text. Both listener and direct fallback are causal rows.
- Focused cardinality is contractual: direct is 8 + 9 + 3 + 5 = 25 named
  TC-366-01/02 tests; group/history is 1 + 5 + 5 + 4 + 2 = 17 named Dart
  TC-366-00/03/04 tests. Existing preservation IDs are outside those regexes.

## Implementation Steps

1. Snapshot `git status --short` and the current Graphify fingerprint. Preserve
   every inherited Plan-364/365 change. Add all TC-366 causal tests to the
   existing registered owners before production edits; run the first exact RED
   and record the semantic failure rather than accepting a no-test-selected
   result.
2. Interop repair: change the existing Go group-media fixture and rollout source
   contract to the Dart canonical scheme, record the validator RED, then align
   only `ack_custody.go` and retain a negative old-alias row. Do not change an
   action, kind, schema, envelope, or deployment flag.
3. Direct producer bundle:
   - thread the one pre-effect `DirectMediaFanoutAdmission` snapshot through
     voice and all four share/forward entries, including the direct-library
     batch caller;
   - use `PreparedDirectMediaBlobCustodyCoordinator.prepareAndUploadFreshFanout`
     (or its explicit private branch on the same class) and pass the resulting
     `DirectLinkedMediaFanoutContext` to final settlement;
   - widen the incumbent private repository interface/implementation, v114
     generation helper, private Barrier-B SQL helper, send settlement, bootstrap
     delegate, and both retries for exactly one private attachment x N physical
     targets under the existing lifecycle lock; keep the null-v110 shape
     mutually exclusive from ordinary/disappearing token-bearing authority;
   - stage N target rows atomically, upload/store each independently, run one
     canonical private completion only after the complete target set is stored,
     bind N v108 siblings, and retain final-sibling-only projection;
   - reopen complete/partial private v114 survivors before source/roster work.
   Stop-if: this requires a DB migration, new durable owner, new envelope kind,
   or changes private receive semantics; re-plan instead of widening scope.
4. Direct mutation bundle: defer caption route resolution until the existing DB
   qualifier proves the persisted media parent, then delegate to
   `DirectEventFanoutAuthoring`. Extend that owner's current DB qualification for
   the exact ordinary/private/disappearing DFE shapes. Keep plural stage and
   cleanup inside the incumbent lifecycle lease, perform zero cleanup on stage
   refusal, release before network, and send manual retry to the existing global
   plural v109 drain. Leave blob rows/artifacts immutable for EDIT.
   Stop-if: any branch cannot preserve the incumbent private lifecycle lease or
   needs a second cleanup owner.
5. Group metadata bundle: remove and test both full-composer quote refusals, then
   preserve `quotedMessageId` through raw sender, prepared owner, retry, receive,
   and linked fallback. For forward, remove and independently test the
   pre-source, dispatch, and deep-sender refusals; preserve operation identity
   and `isForwarded` through preparation/retry/receive/UI. Keep private/malformed
   checks. No Go change beyond Step 2 is permitted because these metadata fields
   already live inside the signed envelope.
6. History/no-intent bundle: pass an explicit `historyRepair` disposition through
   both listener and fallback. Gate stage/promote, alias reconciliation, display
   retry kicks, compatibility presentation and tone; persist a fresh repaired
   row locally read and preserve a duplicate's canonical `readAt`. Leave ordinary
   replay unchanged. In upload retry, inspect complete strict survivors first,
   then refuse initialized no-fingerprint authority before source,
   `allowedPeers`, or network. Add no backfill.
7. Run representative mutations one at a time, confirm the named case re-reds,
   revert immediately, and rerun that exact case green. A mutation that stays
   green is a test defect and blocks the curated lanes.
8. Run focused bundles, exact Go/shell proof, preservation sentinels, serial curated `1to1` and
   `groups`, completeness, analyzer/format/diff checks, then one incremental
   Graphify refresh. Update the coverage checkpoint/index only after those pass.

## Risks And Blind Spots

- Cross-language false green -> TC-366-00a uses the canonical Dart literal in
  the real Go validator test and a source contract; the old alias is negative.
- Snapshot TOCTOU or double resolution -> TC-366-01a counts exactly one
  pre-effect read and requires transaction requalification, with persisted
  survivors exempt from live reads.
- Private lifecycle drift -> TC-366-01b retains the existing private
  lock/pending/completion/deadline authority, real-SQLite plural Barrier B,
  bootstrap wiring and final-sibling projection; unsupported shapes remain
  zero-effect.
- Lifecycle / derived-state durability -> TC-366-01a/01b/03b reconstruct A/B
  survivors from persisted rows and exact bytes; no source or roster is needed.
- Sibling-surface consistency -> voice widget/use case, four share entries,
  direct-library caller, exported mutation use cases, full group media/voice
  callers, raw sender, receiver, and linked projection have named assertions.
- Destructive-action side effects -> TC-366-02b requires all-target v109 custody
  inside the lifecycle lease before cleanup, zero cleanup on refusal, release
  before network, and persisted-B retry without parent resurrection.
- Notification regression from history -> TC-366-04a has both an inert repair
  on listener/fallback and an unread/display-eligible ordinary replay control,
  including duplicate alias/read-state behavior.
- Quote-parent lookup expansion -> TC-366-03a requires a local fallback and zero
  history/network calls when the parent is absent.
- Invariant re-verification under new transitions -> every fresh snapshot is
  re-read inside the incumbent all-target transaction; retry authority comes
  only from complete v114/v115 rows; crossed target/key/manifest/policy state
  refuses all-zero.
- Dirty inherited baseline -> execution records the exact pre-existing status
  and must not attribute unrelated Plan-364/365 edits or failures to Plan 366.

## Gate Cadence

- Per-plan closure: two focused TC-366 bundles, exact preservation sentinels,
  exact group-media Go package/rollout-contract proof, representative mutation
  re-reds, serial curated `1to1`, serial curated `groups`, completeness,
  analyzer, format/diff, and Graphify freshness.
- No migration, native binding, simulator, device, relay deployment,
  performance, `core-host-all`, or `feature-host-all` leg is justified. DB
  remains v115 and no action/wire shape changes. One existing Go relay package
  family is mandatory solely to align its validator with the Dart literal; all
  other owners are exercised by exact tests plus both affected curated lanes.
- The per-plan implementation gate remains host-only. The stronger cumulative
  live-acceptance receipt reuses exactly one existing B1b after the corrected
  relay is separately deployed and S2-authorized; it is not a second Plan-366
  test campaign or a reason to add device code.
- Do not run full `host-all` for this individual plan. Because this is the final
  GAP-N01 code adopter, the GAP-N01 dependency-wave owner runs
  `./scripts/run_host_test_gates.sh host-all` once after Plan 366's per-plan
  acceptance and any B1b-exposed correction, then records it in the N01
  mechanism-closure receipt. WP-07 runs it once again at final rollout/release
  closure.
- Shared tests outside feature/core globs:
  `test/features/conversation/application/private_media_cleanup_race_test.dart`,
  `test/core/services/p2p_service_inbox_ack_ordering_test.dart`,
  `test/core/database/helpers/messages_db_helpers_test.dart`, and
  `test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart`
  are run in the focused bundles; registration under a later full `host-all`
  does not make that sweep a per-plan gate.

## Acceptance Gates

```bash
# Snapshot before execution; record inherited Plan-364/365 changes.
git status --short
plan366_gate_dir="$(mktemp -d /tmp/plan366-gates.XXXXXX)"
command -v jq >/dev/null

# First causal RED: after changing only the Go fixture/source contract to the
# Dart canonical scheme, expect non-zero because the validator rejects it.
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . \
  -run '^TestRelayNotificationClosure_GroupMediaBlobCustody$' -count=1 -v)

# Direct causal RED after adding the test and before direct production edits.
# Expect non-zero because initialized voice still refuses singular fanout.
# Zero selected tests is a harness failure, not RED.
flutter test test/features/conversation/application/send_voice_message_use_case_test.dart \
  --plain-name 'TC-366-01a fresh voice stages exact linked targets before upload and settlement'

# Focused direct GREEN. Expect exactly 25 TC-366-01/02 tests, zero failures/skips.
flutter test \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart \
  test/core/database/helpers/messages_db_helpers_test.dart \
  test/features/conversation/application/send_voice_message_use_case_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/application/delete_message_use_case_test.dart \
  test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart \
  test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  test/features/conversation/domain/repositories/message_repository_impl_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart \
  test/features/share/application/share_batch_delivery_coordinator_test.dart \
  test/features/conversation/application/private_media_cleanup_race_test.dart \
  --name 'TC-366-0[12]' --concurrency=4 \
  --file-reporter "json:$plan366_gate_dir/direct.json"
test "$(jq -s '[.[] | select(.type == "testStart" and (.test.name | test("TC-366-0[12]")))] | length' "$plan366_gate_dir/direct.json")" -eq 25
test "$(jq -s '[.[] | select(.type == "testDone" and .skipped == true)] | length' "$plan366_gate_dir/direct.json")" -eq 0

# Focused group/history GREEN. Expect exactly 17 TC-366-00/03/04 tests,
# including the shared P2P/display owners, with zero failures/skips.
flutter test \
  test/features/conversation/application/upload_media_use_case_test.dart \
  test/features/groups/application/send_group_message_use_case_test.dart \
  test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart \
  test/features/groups/application/drain_group_offline_inbox_use_case_test.dart \
  test/features/groups/application/group_message_listener_test.dart \
  test/features/groups/application/group_notification_display_outbox_wiring_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart \
  test/features/share/application/share_batch_delivery_coordinator_test.dart \
  test/core/services/p2p_service_inbox_ack_ordering_test.dart \
  test/core/database/migrations/115_group_media_blob_custody_test.dart \
  --name 'TC-366-0[034]' --concurrency=4 \
  --file-reporter "json:$plan366_gate_dir/group.json"
test "$(jq -s '[.[] | select(.type == "testStart" and (.test.name | test("TC-366-0[034]")))] | length' "$plan366_gate_dir/group.json")" -eq 17
test "$(jq -s '[.[] | select(.type == "testDone" and .skipped == true)] | length' "$plan366_gate_dir/group.json")" -eq 0

# Exact interop GREEN and affected Go package family. Expect PASS; the old
# `blob_aes_gcm_v1` negative row must be selected in the focused test.
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . \
  -run '^TestRelayNotificationClosure_GroupMediaBlobCustody$' -count=1 -v)
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . -count=1)
bash scripts/test/relay_media_custody_contract_test.sh

# Exact preservation sentinels. Expect one selected and exit 0 for each.
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'TC-354-02b private initial keeps ACK-or-expiry custody across node live and completion races'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'TC-359-04a persisted private target defeats caller policy drift before EDIT effects'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'P268 group composer source has no private authoring API or mutable policy state'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'TC-362-02a composer routes a fresh strict generation through the all-target owner'
flutter test test/features/conversation/application/upload_media_use_case_test.dart \
  --plain-name 'TC-365-02a strict group upload stores exact recipient custody without allowedPeers'

# Existing registered inventories; run serially.
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check

# Hygiene. Expect no new analyzer issue, no format drift, no whitespace error.
flutter analyze
dart format --output=none --set-exit-if-changed \
  lib/app/bootstrap/production_application_bootstrap.dart \
  lib/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers.dart \
  lib/core/database/helpers/media_attachments_db_helpers.dart \
  lib/core/database/helpers/messages_db_helpers.dart \
  lib/features/conversation/application/send_voice_message_use_case.dart \
  lib/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart \
  lib/features/conversation/application/direct_event_fanout_coordinator.dart \
  lib/features/conversation/application/send_chat_message_use_case.dart \
  lib/features/conversation/application/delete_message_use_case.dart \
  lib/features/conversation/application/retry_incomplete_uploads_use_case.dart \
  lib/features/conversation/application/retry_failed_messages_use_case.dart \
  lib/features/conversation/data/repositories/media_attachment_repository_impl.dart \
  lib/features/conversation/data/repositories/message_repository_impl.dart \
  lib/features/conversation/domain/repositories/media_attachment_repository.dart \
  lib/features/conversation/domain/repositories/message_repository.dart \
  lib/features/conversation/presentation/screens/conversation_wired.dart \
  lib/features/share/application/share_batch_delivery_coordinator.dart \
  lib/features/groups/application/handle_incoming_group_message_use_case.dart \
  lib/features/groups/application/send_group_message_use_case.dart \
  lib/features/groups/application/prepared_group_media_blob_custody_coordinator.dart \
  lib/features/groups/application/protected_group_content_receive.dart \
  lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart \
  lib/features/groups/application/drain_group_offline_inbox_use_case.dart \
  lib/features/groups/application/group_message_listener.dart \
  lib/features/groups/presentation/screens/group_conversation_wired.dart \
  lib/features/groups/presentation/screens/linked_group_conversation_wired.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  test/core/database/migrations/115_group_media_blob_custody_test.dart \
  test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart \
  test/core/database/helpers/messages_db_helpers_test.dart \
  test/core/services/p2p_service_inbox_ack_ordering_test.dart \
  test/features/conversation/application/delete_message_use_case_test.dart \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  test/features/conversation/application/private_media_cleanup_race_test.dart \
  test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/application/send_voice_message_use_case_test.dart \
  test/features/conversation/application/upload_media_use_case_test.dart \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  test/features/conversation/domain/repositories/message_repository_impl_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart \
  test/features/groups/application/drain_group_offline_inbox_use_case_test.dart \
  test/features/groups/application/group_message_listener_test.dart \
  test/features/groups/application/group_notification_display_outbox_wiring_test.dart \
  test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart \
  test/features/groups/application/send_group_message_use_case_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart \
  test/features/share/application/share_batch_delivery_coordinator_test.dart
test -z "$(gofmt -l \
  go-relay-server/ack_custody.go \
  go-relay-server/ack_custody_protocol_test.go)"
git diff --check

# Refresh once after the coherent app-owned change, then require an anchored query.
./graphify-arch/refresh_arch_graph.sh --incremental
python3 graphify-arch/tdd_context.py query \
  "Plan 366 final GAP-N01 direct voice share private media mutation group quote forward history repair custody" \
  --profile review --budget 800 --ensure-fresh
```

Representative mutation log required before the curated lanes:

1. restore the relay validator's obsolete encryption-scheme literal;
2. restore voice `canServeLinkedFanout: false`;
3. route the direct-library batch entry around fanout preparation;
4. reject the private branch in generation or Barrier B;
5. choose caption fanout from the caller snapshot before DB qualification;
6. restore ordinary-text-only DFE qualification or cleanup before plural stage;
7. drop group `quotedMessageId` at one prepared/caller seam;
8. restore strict-group-forward pre-source `allowStrictFreshGroupMedia: false`;
9. restore the strict-group-forward dispatch refusal;
10. restore the deep strict-forward provenance refusal/forced-false marker;
11. route either history-repair branch as ordinary `replay` or leave it unread;
12. permit one initialized no-fingerprint retry network call.

Run one mutation at a time, record the exact failing named case, revert it, and
rerun the same case green. Do not carry mutation edits into a lane gate.

## N01 Closure States And Cumulative Gates

Keep the delivery structure to this one plan and distinguish three verdicts:

1. `N01_MECHANISM_CODE_COMPLETE` unlocks N02 under the adopted roadmap. It
   requires Plan-366 per-plan acceptance, one final current-source audit across
   Plans 364-366, and one N01-wave `host-all`. Admissions remain default-off.
2. `N01_LIVE_ACCEPTANCE_PROVEN` additionally consumes the single outstanding
   Plans-363/364/365 B1b on the existing Android pair. It is S2-gated and is not
   permission for persistent admission or general activation.
3. `N01_PRD_ACCEPTED` / release closure remains WP-07 because cohort operations,
   quota UX, mixed-version retirement, consolidated iOS, telemetry, and the
   cross-gap outcome/presentation controls do not belong in this adopter.

No new device harness, scenario, registration, or per-modality campaign is
allowed. The one media-enabled B1b always runs the base bootstrap/reopen,
offline blob-free discussion, reaction ADD/REMOVE, and dissolve assertions,
then adds one deterministic image and voice plus strict blob download/ACK. It
therefore closes the carried Plan-364 and Plan-365 device checkboxes in one run.
Plan-365's accepted Android SQLCipher proof is not repeated because Plan 366
adds no schema or native boundary.

Before the live command, a separately authorized operations receipt must name:

- explicit S2 authorization and the corrected reader-first relay binary digest;
- exact relay multiaddresses, shared Redis URL/prefix and restart/restore proof;
- media-filesystem single-writer ownership/capacity/reconstructed gauges;
- `relay_inbox_custody_admission_enabled = 1` and
  `relay_media_custody_admission_enabled = 1` on every target front-end.

The runner never changes relay admission. If any precondition is missing, do
not run it and retain `LIVE-ACCEPTANCE-BLOCKED`; do not substitute a local fake
or silently call a base-only B1b pass sufficient.

```bash
# Re-resolve immediately before execution. Current valid discovery on
# 2026-08-14 is USB Pixel 6 first and Android emulator second.
flutter devices --machine
adb devices -l
plan366_physical_android_id='21071FDF600CSC'
plan366_emulator_android_id='emulator-5554'
test "$(adb -s "$plan366_physical_android_id" get-state)" = 'device'
test "$(adb -s "$plan366_emulator_android_id" get-state)" = 'device'

# Existing runner/opt-in preservation. This is not a new Plan-366 harness.
flutter test test/integration/invite_reliability_runner_contract_test.dart \
  --plain-name 'TC-365-04a B1b registers group media and voice before terminal dissolve'

plan366_s2_relay_addresses='<PLAN366_FIXED_S2_RELAY_MULTIADDRS>'
case "$plan366_s2_relay_addresses" in *'<'*|*'>'*) exit 1 ;; esac

# Registration/dry-run. The media flag must also be present on the live run;
# the Plan-365 command without it proves only the base Plan-363/364 path.
MKNOON_B1B_PLAN365_GROUP_MEDIA=true \
MKNOON_RELAY_ADDRESSES="$plan366_s2_relay_addresses" \
RELIABILITY_MULTI_DEVICE_IDS="$plan366_physical_android_id,$plan366_emulator_android_id" \
  ./scripts/run_test_gates.sh reliability-sim group --list \
  --only integration_test/scripts/run_b1b_sibling_device_convergence.dart

# Run only after the external S2 receipt above is attached.
MKNOON_B1B_PLAN365_GROUP_MEDIA=true \
MKNOON_RELAY_ADDRESSES="$plan366_s2_relay_addresses" \
RELIABILITY_MULTI_DEVICE_IDS="$plan366_physical_android_id,$plan366_emulator_android_id" \
  ./scripts/run_test_gates.sh reliability-sim group \
  --only integration_test/scripts/run_b1b_sibling_device_convergence.dart
```

The live log must state `plan365GroupMedia=true`, both role exits `0`, all base
verdict fields, and every conditional Plan-365 media/voice verdict field. After
the run—even on failure—operations must restore both admissions off and record
both gauges as `0`; already accepted rows remain drainable. Never roll back to
an old binary that cannot drain protected state.

If B1b exposes a product defect, make only the smallest causal correction,
rerun its affected focused/curated gates and this one B1b, then run the N01 wave
gate exactly once on the final tree:

```bash
./scripts/run_host_test_gates.sh host-all
git status --short
git diff --check
python3 graphify-arch/tdd_context.py query \
  "Plans 364 365 366 final GAP-N01 mechanism closure and residual bypass audit" \
  --profile review --budget 800 --ensure-fresh
```

The combined audit records the final HEAD, inherited dirty baseline, complete
Plan-366 path set, Graphify fingerprint, B1b verdict/rollback provenance when
authorized, and `host-all` outcome. It supersedes separate Plan-364 and
Plan-365 audit-plan work; do not create another implementation plan merely to
manufacture a clean SHA.

## Execution Interpretation And Done Criteria

- Expected REDs: TC-366-00a first proves that the real Go validator rejects the
  Dart-produced `blob_aes_256_gcm_v1`; TC-366-01a then reaches the current
  `VOICE_SEND_MEDIA_FANOUT_SINGULAR_REFUSED` branch and observes zero plural
  coordinator/settlement work.
- Green sentinels: the existing Go validator accepts only the canonical Dart
  scheme, and initialized A/B voice stages exact per-target blob/content
  obligations once. Uninitialized and existing ordinary/disappearing controls
  remain unchanged.
- Pre-existing dirty tree / known failure: Plan 366 is authored over the dirty
  post-Plan-365 worktree. The executor records that baseline and does not claim
  a clean implementation SHA unless one later exists.
- Environment blocker: none for per-plan host implementation. The currently
  available USB Android/emulator pair makes cumulative B1b `BLOCKED (S2
  authorization and corrected relay deployment)`, not N/A. This blocks only
  `N01_LIVE_ACCEPTANCE_PROVEN`, not `N01_MECHANISM_CODE_COMPLETE`.
- Scope drift: anything beyond the bounded existing Go validator-literal repair,
  or any migration, new protocol/backend/owner, group-private authoring, generic
  history sync, broad runtime, or activation change, blocks completion and
  requires re-review. The separately authorized reader-first deployment,
  temporary S2 admissions and mandatory rollback are acceptance operations,
  not permission to widen product implementation.

- [x] Every behavior has a named non-vacuous test or justified preservation proof.
- [x] The Dart/Go canonical scheme RED/GREEN proves the obsolete alias is rejected.
- [x] Causal REDs, focused GREEN, and twelve representative mutation re-reds are recorded.
- [x] Exact-snapshot direct voice, four-share, and supported private fanout plus roster-independent survivor retry pass.
- [x] Private generation, Barrier B, bootstrap wiring, per-target settlement, and final-sibling-only projection pass without v110 or schema work.
- [x] Direct caption EDIT/DFE use existing per-target v109 custody before transport/cleanup.
- [x] Ordinary group quote/forward round-trip through existing signed content/media owners.
- [x] Listener and fallback history repair are locally read and display/notification-inert; ordinary missed-message replay remains unread and eligible once.
- [x] Initialized no-intent group retry is zero-network; historical rows remain unpromoted.
- [x] Existing private/group non-adopter and legacy preservation sentinels pass.
- [x] Curated `1to1`, `groups`, and completeness pass with semantic outcomes.
- [x] No migration, native/device code, new harness, or new deployment mechanism is added; the exact existing Go validator family is recorded.
- [x] `flutter analyze` has no new issues; format and `git diff --check` are clean.
- [x] Scope Contract And Guard is respected; Graphify is refreshed once and anchored.
- [x] One combined current-source audit across Plans 364-366 and the final N01-wave `host-all` pass; coverage/index may then record `N01_MECHANISM_CODE_COMPLETE`.
- [ ] If the stronger no-dangling live verdict is requested, the one media-enabled cumulative B1b passes on USB Android first plus Android emulator second, and both S2 admissions are attested `0` after rollback.
- [x] Coverage/index distinguish mechanism code completion, live acceptance, and WP-07 PRD/release work without upgrading one into another.

Plan-366 per-plan completion is not by itself the dependency-wave receipt. The
GAP-N01 wave owner then runs one full `host-all`; a failure causally tied to
Plans 360-366 reopens the responsible plan before N02 begins. No additional
implementation plan is created for the audit, wave, or cumulative B1b receipt.

## Handoff

- First causal RED command: change only the existing Go fixture/source contract
  to `blob_aes_256_gcm_v1`, then run
  `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . -run '^TestRelayNotificationClosure_GroupMediaBlobCustody$' -count=1 -v)`.
- Second causal RED command:
  `flutter test test/features/conversation/application/send_voice_message_use_case_test.dart --plain-name 'TC-366-01a fresh voice stages exact linked targets before upload and settlement'`.
- Preservation commands: the five exact sentinels plus curated `1to1`, `groups`,
  and completeness commands above.
- Manual registration: none. All test cases extend existing registered paths or
  are exact commands already named above. The cumulative B1b reuses its existing
  registered runner with `MKNOON_B1B_PLAN365_GROUP_MEDIA=true`; no harness or
  inventory edit is needed.
- Migration: none; DB stays v115 and historical rows remain null/unpromoted.
- Boundary closure: product implementation is host-only plus one existing Go
  validator family. The cumulative acceptance phase uses one existing Android
  B1b and a separately authorized reader-first deployment; it adds no relay
  action/protocol, OS/native boundary, SQLCipher schema, or delivery structure.
- Wave handoff: after per-plan acceptance and any B1b-exposed repair, run one
  GAP-N01 dependency-wave `./scripts/run_host_test_gates.sh host-all`; WP-07 owns
  the later persistent rollout and final-release run.
- Unresolved evidence: S2/deployment authority is not granted by this artifact.
  Without it, mechanism code closure may pass while the stronger live verdict
  remains blocked. Revalidate current source if inherited Plan-365 APIs move.

## Reviewer Findings

Review verdict after correction: `ready`.

Independent review initially returned `plan-fixes-required` / `not-ready`. It
found a real Dart/Go scheme false green, a fourth direct-library producer, the
three distinct group-forward refusal seams, and underspecified private Barrier
B, media-DFE retry/lifecycle, history fallback, and unread-state contracts. It
also found stale proof paths and names. The revised contract incorporates each
verified finding without adding a schema, protocol, durable owner, or product
surface. Final factual and boundary re-reviews both returned `ready` after the
repository-adapter sentinel and machine-enforced test-count/skip checks landed.
A later audit of the completed Plan-364/365 receipts found one more acceptance
false green: Plan 365's documented B1b command never enables its media/voice
extension. The corrected cumulative command and its rollback boundary are now
explicit, with no new harness.

- L1 behavior: every current reachable notification producer is now either a
  named adopter or an explicit, evidence-backed non-adopter.
- L2 architecture: v108/v109/v114/v115 and the incumbent private,
  `group_content_v1`, display, and retry owners remain the only authorities.
- L3 TDD causality: the cross-language false green is exposed first; every
  producer/lifecycle branch has a named RED, control, and exact fixture.
- L4 regressions: 25 direct and 17 group/history named tests, twelve mutation
  re-reds, exact preservation sentinels, and both affected curated lanes bound
  the change.
- L5 economy: group-private authoring, group mutations, avatar fanout, generic
  history sync, persistent activation, and extra device work remain out of
  scope. One existing cumulative B1b replaces separate 364/365 campaigns.

Evergreen blind spots are explicitly covered: no migration/backfill; callers
and both retry families are named; real SQLite/temp-crypto/Go boundaries are
used where fakes would hide state; test counts and mutations prevent vacuity;
DFE cleanup ordering, persisted fingerprints, and cross-language scheme parity
have causal assertions. Per-plan device proof remains unnecessary, while the
available physical-Android/emulator B1b is isolated as an S2-gated cumulative
acceptance receipt. No iOS or persistent-rollout claim is made.

## Arbiter Decision

`ready`; the optional cumulative live receipt is S2-gated. Plan 366 is the
single final GAP-N01 implementation slice. Its per-plan gates remain
proportional; the same artifact then records one combined audit and N01-wave
`host-all` for `N01_MECHANISM_CODE_COMPLETE`, and may consume the one existing
Android B1b for `N01_LIVE_ACCEPTANCE_PROVEN` after explicit S2. WP-07 retains persistent
activation, cohort/quota operations, mixed-version retirement, iOS, A-control
acceptance, and release closure.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-14 | planning/review and carried-receipt audit complete | plan and index only | anchored Graphify, independent reviews, live Android discovery, Plans-364/365 receipt and B1b command audit | corrected implementation contract is ready; cumulative live mode is now non-vacuous | dirty baseline recorded; stronger live verdict awaits explicit corrected-relay S2 | begin TC-366-00a fixture-only RED |
| 2026-08-15 | implementation, per-plan closure, combined audit and N01-wave closure complete | existing direct/group custody owners, relay validator, bounded tests and closure records | direct TC-366 `25/25`; group/history `17/17`; canonical relay family and rollout contract PASS; five preservation sentinels; 12/12 mutations RED then restored GREEN; curated `1to1` 3,205 pass / 10 declared skips plus tails; curated `groups` 4,199 pass plus tails; completeness 1,445/1,445; default serial `host-all` 1,355/1,355; final analyzer clean in 108.8s; 184 Dart and 13 Go files format-clean; diff check clean; anchored/current Graphify `19e306d1432ccbf1` (75,335 / 109,759; 15,646 named tests) | every reachable Plan-366 producer either uses exact persisted per-device custody or refuses before effects; no v116, new protocol, queue, scheduler, selector, native/device code or activation was added | `N01_MECHANISM_CODE_COMPLETE`; no S2/deployment/admission/B1b/rollback operation was authorized, so `N01_LIVE_ACCEPTANCE_PROVEN` remains blocked and WP-07 retains activation/PRD/release closure | hand off to N02/WP-07 without another N01 adopter plan |

Wave-gate correction note: the first serial runs exposed stale bootstrap/API
fingerprints, v115 migration fixtures, new admission-read counters, protected
authority reconciliation fixtures, and shared integration-test assumptions.
Those repairs were test-contract/fixture corrections except for localizing 16
already-shipping linked-device UI literals across English, German and Arabic;
the localization sentinel was not allowlisted. No production custody bypass was
introduced. The authoritative `host-all` receipt was then run from command 1 on
the settled tree and passed all 1,355 commands. A subsequent current-source
counterexample audit found three real fail-open edges: linked voice could admit
without the exact plural owner and fall to singular upload, external share
could demote an immutable linked admission to legacy after contact/key drift,
and history repair could notify through buffered-reaction flush. Each received
a causal RED/GREEN and preservation control; focused direct expanded to 25 and
group/history to 17, both curated lanes re-passed, and the earlier wave receipt
was superseded by a fresh command-1 `host-all` on the final frozen tree. That
authoritative final run passed all 1,355 commands before the current Graphify
refresh and closure-record update.

Durable dependency receipt: `Test-Flight-Improv/evidence/366/README.md`
(`README.md` SHA-256
`5c3843a5f4059652b83a58e57909ab8bcf3a99c78ba5587a5efd6ccdfda5753b`).
It binds the final logs to frozen dirty-tree ID
`0765646f6c60140424e5320552d38ed0e5a2fce8`, records honest MID-to-POST
machine equality plus launch-to-MID executor attestation, and supersedes the
earlier unbound summaries for successor dependency purposes. It changes no
live/S2/admission/B1b/release disposition.
