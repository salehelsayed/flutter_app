# 358 - GAP-N01 Disappearing Direct-Media Initial Inbox/Blob Custody Adoption

Status: IMPLEMENTED / EXECUTION_COMPLETED / POST_EXECUTION_AUDIT_CLOSED / default-off / not release-eligible
Type: Modification
Baseline observed while planning: `66a5940de0d1a0d00f743c97ecca03c22527ca54` (`fix(357): close Plan 356 private delete-for-everyone post-execution defects`)
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` sections 3.1 and 5, A-01/A-03/A-28; `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan.md` D-234-01/D-234-02/D-234-05; gap inventory `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md` GAP-N01 / WP-01 / section 9.2
Classification: bounded default-off adopter of the existing v110/v111/v108 initial-media owners plus the existing receiver-local disappearing lifecycle; no new durable authority
Closure tier: behavioral host tests with current-schema SQLite, real temporary files, secure-key compensation and file-backed reopen; no schema, relay/native, device, iOS, activation, or release boundary

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-11 | Evidence Collector / Planner | Graphify TDD context; private policy/composer; ordinary and private strict blob coordinators; v110/v111/v108 DB owners; sender/retry; strict receive/download; disappearing expiry engine/scheduler; Plan 234 decisions; tests and gates | The adopter is same-schema. Outgoing disappearing must use the token-bearing ordinary-shaped preparation lane without inheriting Protected/View-Once sender-open semantics; incoming disappearing must use the strict-private atomic stage and its receiver-local expiry owner. Blob transport expiry and content disappearance are independent clocks. | Write four causal bundles with existing test paths and a lean gate cadence, then run `$tdd-review`. |
| 2026-08-11 | Test/gate inventory | Host `1to1`, core/feature auto-globs, existing Plan 347/354/355 tests and disappearing lifecycle tests | Existing paths are sufficient. One selector-on concurrency-4 filtered proof, default-define host `1to1`, and one dart-only core sweep cover the intended surfaces. Feature/full/device/Go campaigns are not justified. | Keep every new row in an existing file; add no registration or completeness run. |
| 2026-08-11 | Independent `$tdd-review` | Review-profile Graphify context plus sender/storage/retry, receiver/lifecycle/download, DTR/bootstrap and literal gate audits | Initial verdict was `plan-fixes-required`, core bet confirmed. The plan now closes hydrated-key replay, due-only clock/stream ordering, lifecycle capability, P/VO lineage, selector-on proof-less compatibility, bootstrap `nowMs`, DTR and literal hygiene gaps without another owner, test path or gate family. | Targeted sender, receiver and gate re-reviews all returned READY. |

## Problem And Evidence

- Behavior to improve: a newly authored one-to-one disappearing image/video initial should durably preserve its exact encrypted blob generation and its initial envelope before network egress, and a receiver should atomically commit that initial plus its receiver-local disappearance clock before receipt or presentation.
- User impact: disappearing media currently takes the proof-less generic upload/send and split incoming-save lanes. A crash or race can therefore leave the encrypted event, attachment/key projection, and blob obligation at different durability checkpoints even though Protected/View-Once and ordinary strict media already have reusable owners.
- Confirmed sender gap: `conversation_wired.dart` mints `directMediaCustodyIntentId` only for policy-v0 ordinary media, while `strictBlobSelected` requires that token-bearing durable parent. `send_chat_message_use_case.dart`, `media_attachments_db_helpers.dart`, and both retry validators independently require ordinary policy, so merely selecting the flag cannot adopt disappearing media.
- Confirmed receiver gap: `_parseStrictIncomingMediaProjection` treats only Protected/View-Once as private initials; `dbStageIncomingDirectPrivateMediaBlobCustody` and the strict local-path commit also reject disappearing. The legacy receive path saves the parent and attachment separately.
- Existing reusable authority: physical v110 preparation intent, v111 encrypted-blob rows, v108 ACK-or-expiry envelope custody, the sole strict upload/download owners, the repository-wide private lifecycle lease, receiver-local monotonic expiry columns/engine/scheduler, display-marker outbox, and no-FK v111 expiry/ACK convergence already exist on DB v111.
- Lifetime boundary: the sender-side v111/media expiry is a transport lease and bounds v108 inbox storage. The disappearing deadline starts independently when the recipient durably commits the message (`receivedAt + duration`). A delayed 7-day delivery may therefore leave less than a full 7-day relay-fetch window even though the local card remains scheduled for seven days. D-234-05 explicitly makes no relay-renewal/revocation/recovery promise; Plan 358 must preserve that truth rather than silently clamp the content deadline or add relay work.
- Current authoring matrix: newly selectable private media is exactly one coherent image or video with no text/caption, edit, forward, quote, or second attachment. GIF remains compatibility-decodable but has no new private selector and stays proof-less legacy; audio/file/unknown remain ineligible.
- Existing lifecycle coverage: clock high-water, rollback, resume/cold-start expiry, explicit private download claims, terminal cleanup and strict P/VO staging are already behaviorally covered. This plan adds only the disappearing/strict crossing and the races it creates.
- Expected production surface: `lib/core/media/private_media_policy.dart`, `lib/core/database/helpers/media_attachments_db_helpers.dart`, `lib/core/database/helpers/messages_db_helpers.dart`, `lib/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart`, `lib/features/conversation/presentation/screens/conversation_wired.dart`, `lib/features/conversation/application/send_chat_message_use_case.dart`, `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`, `lib/features/conversation/application/retry_failed_messages_use_case.dart`, `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`, `lib/features/conversation/application/download_media_use_case.dart`, `lib/features/conversation/application/strict_direct_media_blob_download_ack_owner.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository.dart`, `lib/features/conversation/data/repositories/media_attachment_repository_impl.dart`, and `lib/app/bootstrap/production_application_bootstrap.dart`. The exact `nowMs` delegate also updates the incumbent shared real-DB fixture and its existing bootstrap contract test. Stop and re-review before touching any other production file.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: architecture fingerprint `99939b31e3258f0c`; current at planning time.
- Query / profile: `python3 graphify-arch/tdd_context.py query "Plan 358 disappearing direct-media initial inbox blob custody adoption: _isOutgoingPrivateOneMoreLook strictBlobSelected strictPrivateBlobSelected privateMediaInitialProducerMatrixAllows dbStageIncomingDirectMediaBlobCustody dbStageIncomingDirectPrivateMediaBlobCustody privateMediaExpiresAtMs v108 v110 v111 retry incomplete failed download expiry scheduler" --profile tdd --budget 700`.
- Anchors: `_isOutgoingPrivateOneMoreLook` -> `conversation_wired.dart`; `privateMediaExpiresAtMs` -> `conversation_message.dart`; `dbStageIncomingDirectPrivateMediaBlobCustody` -> `media_attachments_db_helpers.dart`.
- Surfaced proof/gate files: `conversation_wired_test.dart`, `media_attachments_db_helpers_test.dart`, `send_chat_message_use_case_test.dart`, retry suites, `handle_incoming_chat_message_use_case_test.dart`, `download_media_use_case_test.dart`, private lifecycle DB/scheduler/restart suites, and host `1to1`.
- Graph gaps requiring source search: exact policy predicates shared by marker-free fresh staging and token-bearing composer staging; source verification showed they must not be widened globally.
- Reuse rule: execution may use these anchors, but every transition and test claim remains subject to current-source verification.

## Scope Contract And Guard

In scope:

- Add one shared duration-aware disappearing-initial producer predicate for exact v1 `disappearing`, duration in `{3600, 86400, 604800}`, and one MIME/mediaType-coherent image or video. Parent-level callers independently require empty text, no edit/forward/quote, and one attachment. Do not widen the P/VO matrix or new-private GIF eligibility.
- When the client selector is enabled and the current composer policy/attachment projection satisfies that predicate, mint the existing deterministic v110 intent on the disappearing parent. Persist the parent and its convention-owned pending attachment through the same already-accepted composer preparation sequence used by ordinary strict media before encryption or network. Do not claim those pre-existing saves are one new transaction.
- Keep disappearing outside `_isOutgoingPrivateOneMoreLook`, the private transfer registry, sender-open/consume CAS, private canonical completion and the no-v110 P/VO generation owner. It adopts the token-bearing `prepareAndUpload` / `reopenAndUpload` path only.
- Widen token-bearing v110/v111/v108 predicates to accept either their unchanged exact ordinary shape or the exact disappearing shape: outgoing, `sending|failed` where the incumbent step permits it, state `available`, allowed non-null duration, and all sender-side receiver-clock/reveal/terminal fields null. Preserve every other parent and attachment invariant.
- Do not globally widen `_isEligibleDirectMediaCustodyParent` or canonical fresh-parent authority. Marker-free external share and authorized internal forward remain ordinary-only. Disappearing is admitted only when the caller proves the existing v110 predecessor (`expectedRow != null`) and the exact prepared parent/attachment projection.
- Publish the complete v111 generation before the first LAN/relay blob callback. Bind its canonical manifest and earliest blob expiry plus the encrypted initial envelope into the existing v108 transaction before chat egress. Keep exact-winner-before-capacity, rollback, node-off, live-ACK hedge retention, ACK-or-expiry acceptance and media-expiry-bounded inbox storage unchanged.
- At exact accepted v108 completion, extend Plan 352's already-proven attachment-lineage stamp to the exact disappearing parent before v108 retirement and v111 cleanup. Require the full disappearing policy/duration/state/null receiver-clock shape and exact complete attachment/v111 projection. Crossed or malformed state returns `stale` before the first write. This is initial-custody provenance, not Delete-for-Everyone adoption; without it, normal cleanup would make this newly strict generation indistinguishable from legacy before Plan 359 can reason about it.
- Extend incomplete and failed retry validation for that same token-bearing disappearing shape. With a complete existing v111 generation, retry must call `reopenAndUpload`, reuse byte-identical ciphertext/key/nonce/hash/commitment, and never call the private P/VO coordinator or legacy upload. Missing/partial/no-v111 and selector-off historical rows are not promoted by this plan; they keep their incumbent legacy/fail-closed result.
- On receive, classify a strict disappearing initial as private only for the same one-image/video matrix and valid duration. Keep zero/multiple, GIF/audio/file, crossed MIME/mediaType, caption/text, edit, forward, quote, partial commitment, invalid duration/version and missing capability fail-closed before key/DB/display/receipt effects.
- Reuse `dbStageIncomingDirectPrivateMediaBlobCustody` for the exact disappearing row. One transaction must commit the incoming parent, one secure-key-backed pending attachment and one `incomingCommitted` v111 row. Require state `available`, positive `receivedAt`, `clockHighWater == receivedAt`, allowed duration, overflow-safe `expiresAt == receivedAt + duration*1000`, and null reveal/terminal fields. The v111 expiry is validated independently and is never copied into the parent deadline.
- An exact active replay preserves the originally committed `receivedAt`, `expiresAt`, and pre-deadline clock high-water byte-for-byte; it cannot reset or extend the lifetime. Compare the original wire mode/duration/immutable identity before `_seedIncomingPrivateMediaLifecycle` may reuse durable lifecycle fields, so canonicalization cannot hide drift. An exact expired/hidden/deleted same-author parent returns the incumbent zero-effect `durablySuperseded` result and one initial receipt; a removed or crossed parent returns refusal with no receipt. Route disappearing strict replays through the transactional private owner instead of relying on the generic duplicate shortcut.
- A selected strict disappearing initial requires both the existing `DirectPrivateMediaLifecycleRepository` and `DirectPrivateMediaCleanupRuntime` before any secure-key or DB stage; capability absence fails closed. Hold the incumbent repository-wide exclusive lifecycle lease from the hydrated replay barrier through the nested atomic stage, durable re-read, deadline decision, marker, publication and ready promotion. On an existing ACTIVE replay, require exactly one hydrated durable attachment and compare its raw key/nonce/scheme and immutable projection to the wire before any secure-key write. Publish only the stage result's hydrated durable attachment, never the caller/wire snapshot. A pre-existing terminal replay keeps Plan 355's reduced durable-parent plus any surviving attachment/commitment proof, because legitimate cleanup may already have removed its key and attachment.
- Inside that lease, compute `effectiveNow = max(sampledNow, durable clock high-water)`. If it is before `expiresAt`, do not call `advancePrivateMediaClock`; stage the marker, publish the available durable row/attachment, then promote ready, so the first available `messageChanges` event is post-marker and also arms the incumbent scheduler. If it is at/after `expiresAt`, call the existing lifecycle advance once, reload and require `expired`, then suppress every presentation effect and emit one receipt. The expiry transaction retires the exact message marker before the existing lifecycle mutation emits the terminal row. Add exact message-kind marker retirement to that transaction; same-message reaction and unrelated rows remain untouched. No new signal, repository method, outcome or `MessageRepositoryImpl` change is authorized.
- Before every strict private download shortcut (ACK-pending local adoption, already-local committed adoption, or blob-expired convergence), advance/reload the disappearing parent through the existing lifecycle repository under its real attachment lifecycle authority and require it still be `available`. A passed deadline returns null, performs no ACK/network/presentation, and lets the incumbent expiry cleanup own files/key/attachment.
- At the final strict local-path/v111 commit, thread the strict owner's existing injected `now()` sample as an explicit `nowMs` argument through the incumbent repository method and atomically call the existing advance-and-qualify disappearing-parent transaction before writing `done` and optional `incomingAckPending`. Do not infer lifecycle authority from a caller-formatted audit timestamp. An expiry winner makes the commit lose, scrubs only attempt-owned plaintext/staging, emits no ACK, and leaves v111 for its independent ACK/expiry convergence. LAN success remains `incomingCommitted`.
- Preserve independent lifetimes across restart: content expiry may remove the private attachment/key while no-FK v111 remains; v111 expiry may make the blob unavailable while the unexpired local parent/card remains. Neither clock changes or resurrects the other.

Must preserve:

- Ordinary v0 strict media remains on its existing v110/v111/v108 predicates and strict upload/download paths.
- Protected/View-Once remains on its no-v110 private generation, canonical completion and sender one-more-look owners.
- Selector-off and proof-less/no-v111 disappearing media remain legacy. `TC-342-03c media private edit delete and existing attempts remain outside new custody` stays green because its disappearing fixture has no strict manifest/provenance.
- Selector-on does not promote a persisted proof-less disappearing parent either: without the exact v110 predecessor and complete v111 generation it keeps the incumbent generic compatibility result and creates no strict/private/v108/v111 authority.
- New GIF drafts remain ineligible for private selection; compatibility-decoded proof-less disappearing GIF remains private/redacted but is never promoted to v110/v111.
- Automatic private download remains refused; only explicit-user download may enter the strict owner. Keep `TC-355-04d production blob drain predicate retains private committed rows without download` green.
- Disappearing expiry remains receiver-local, monotonic and restart-safe; outgoing disappearing never gains a sender timer or reopen action.
- P/VO terminal replay, key compensation, display serialization, ordinary strict download, source-pinned ACK, retry fairness and existing no-v111 compatibility remain unchanged.

Hard `Do not`:

- Do not add DB v112, a table/column/index, new custody kind/outbox/queue/drain/scheduler/lock, new network owner, relay renewal, TTL change, server clock, receipt ledger, cleanup scanner, or backfill.
- Do not widen marker-free external share/internal forward, P/VO producer eligibility, GIF authoring, group/announcement media, private EDIT, disappearing Delete-for-Everyone, historical/no-intent media, linked-device fanout, or activation/cohort behavior.
- Do not change wire fields, physical v108/v110/v111 layout, relay/Go/native/bridge/bindings, migration/SQLCipher, device/iOS harness, notification framework, or app background scheduling.
- Do not add source-string tests as causal evidence, sleeps, a new test file, gate registration, completeness run, per-plan full `host-all`, feature-wide sweep by default, or repeated ad-hoc whole-file runs.

Deferred / accepted difference:

- Disappearing Delete-for-Everyone stays in the separately reviewed Plan 359 scope because it adds mutation/tombstone authority. Plan 358 preserves the exact post-drain lineage it needs but does not select, stage, transmit, receive, or complete a disappearing deletion.
- Private EDIT remains a separate product/authority decision.
- A receiver-local 7-day disappearing deadline may outlive the remaining fixed relay blob lease after delayed delivery. The UI/lifecycle deadline is not a promise that the relay can serve bytes for that entire period; no renewal or server change is added under D-234-05.
- Pre-358/no-v111, selector-off, proof-less GIF and already-drained historical rows are not scanned or promoted.

Dependencies:

- Plans 347/352 provide the token-bearing v110/v111/v108 primitive and exact completion; Plans 354/355 provide strict-private receive/download/presentation behavior; Plan 234 supplies the accepted receiver-clock and relay-truth decisions; Plan 357 is the clean baseline.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-358-01 | Selector-on newly authored disappearing image/video persists deterministic v110, then atomically publishes the exact attachment crypto projection plus complete v111 before first LAN/relay blob network. The token-bearing final stage binds the same manifest/earliest blob expiry and one v108 before chat egress. Exact accepted completion stamps each already-proven attachment commitment before v108 retirement/v111 cleanup, while crossed lineage rolls the whole completion back. Representative 1h/1d/7d and image/video pass; GIF/audio/file, invalid duration, caption/edit/forward/quote, zero/multiple, crossed policy/state/path/hash/key and fresh marker-free authority refuse all-or-zero. Exact winner precedes capacity. P/VO completion remains byte-identical and never receives this disappearing lineage stamp. | `test/features/conversation/presentation/screens/conversation_wired_test.dart::TC-358-01a disappearing initial publishes v110 and v111 before first network`; `test/core/database/helpers/media_attachments_db_helpers_test.dart::TC-358-01b token-bearing disappearing generation and v108 binding are exact`; `test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart::TC-358-01c accepted disappearing custody preserves strict lineage through v111 drain` | selector-on host; real current-schema SQLite for 01b/01c; deterministic coordinator/network barriers; ordered messages/attachments/v108/v111 snapshots and late-transition rollback trigger | HEAD mints no disappearing v110, DB policy predicates refuse the prepared parent, and completion skips lineage for nonordinary policy -> all GREEN with exact order, stamp and rollback | restore ordinary-only intent/predicate, globally widen fresh authority, move network before v111, skip disappearing lineage, stamp P/VO, or accept a crossed duration/state -> named row RED; revert | causal RED/GREEN; existing `1to1` wired/direct-inbox paths plus core AUTO helper; no registration |
| TC-358-02 | The strict disappearing initial owns ACK-or-expiry v108 across node-off/live/inbox paths; live ACK never cancels the hedge. Incomplete and failed retries with existing complete prepared/stored v111 reopen byte-identical ciphertext through `reopenAndUpload`, with zero private-coordinator/legacy upload/re-encryption/key rotation; missing/partial/no-v111 stays legacy/fail-closed and generic unacked still obeys physical v108. Even selector-on, a persisted proof-less disappearing parent takes its unchanged generic compatibility route with zero strict/private/v108/v111 effects. | `test/features/conversation/application/send_chat_message_use_case_test.dart::TC-358-02a disappearing strict initial keeps ACK-or-expiry custody across node live and inbox`; `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart::TC-358-02b disappearing strict restart reopens exact v111 without legacy upload`; `test/features/conversation/application/retry_failed_messages_media_reupload_test.dart::TC-358-02c failed disappearing strict retry reopens exact generation` | selector-on host; physical v108/v111 fixtures; fake network owners with exact call counters; real stored ciphertext identity | HEAD sender refuses disappearing ownership and retry validators refuse the token-bearing parent -> exact v108/reopen assertions RED | reclassify disappearing as private one-more-look, seize a proof-less row, route complete retry to legacy/private upload, cancel v108 on live ACK, or loosen projection -> named row RED; revert | causal RED/GREEN; send is `1to1`; retry files selected once in filtered proof; no registration |
| TC-358-03 | Strict disappearing receive commits the exact receiver-local parent clock, one secure-key-backed pending attachment and incomingCommitted v111 all-or-zero before marker/publication/receipt. Exact pre-deadline replay preserves receivedAt/expiresAt/high-water and requires byte-equal hydrated key/nonce plus policy/descriptor identity; due replay atomically expires and retires the marker before its terminal stream event. Missing lifecycle capability and every drift refuse before key/DB effects. In both actual lifecycle orders, presentation-first publishes only the durable staged attachment after marker then exact expiry terminalizes/cleans, while expiry/terminal-first yields zero presentation and one exact initial receipt. Other/reaction markers survive. | `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart::TC-358-03a disappearing strict receive commits one clock and serializes expiry presentation`; `test/core/database/helpers/messages_db_helpers_private_media_lifecycle_test.dart::TC-358-03b disappearing expiry retires only the exact message marker atomically` | selector-on host; real SQLite/media repository/secure-key fake; actual repository-wide lifecycle lock; competitors started outside inherited Zone; completers, no sleeps; DB failure injection and message-stream order observer | HEAD parser rejects strict disappearing and expiry does not retire a display marker -> both behavioral RED | omit duration/clock equality, trust the wire key/attachment after idempotence, advance every replay before marker, remove lifecycle capability/span, or unhook marker retirement -> named row RED; revert | causal RED/GREEN; both existing host `1to1` paths; no registration |
| TC-358-04 | Every disappearing strict-download shortcut and final commit requalifies the receiver deadline. Before expiry, relay commits `done + incomingAckPending` before source ACK and LAN commits `done` while retaining incomingCommitted. Deadline-first or deadline-during-transfer produces no durable plaintext/ACK, scrubs only attempt-owned staging, retires the exact message marker, and preserves independent v111. File-backed reopen preserves receivedAt/expires/high-water; v111-first and lifecycle-first expiry change only their own authority, and automatic drain remains zero-network. | `test/features/conversation/application/download_media_use_case_test.dart::TC-358-04a disappearing strict download requalifies deadline before shortcuts and final commit`; `test/features/conversation/integration/private_media_restart_replay_test.dart::TC-358-04b disappearing strict custody and local expiry remain independent across reopen` | selector-on host; real current-schema SQLite, temp files, deterministic bridge/ACK, explicit clock, file-backed close/reopen; exact lock-order barriers | HEAD strict local commit refuses disappearing, while local/ACK shortcuts can bypass an unadvanced deadline -> download/reopen matrix RED | skip pre-shortcut advance, skip in-transaction recheck, ACK before commit, derive/clamp parent expiry from v111, or make one expiry delete/reset the other -> named row RED; revert | causal RED/GREEN; both existing host `1to1` paths; no registration |

### Test Notes

- Author all `TC-358-` tests against existing callable seams so the first RED is behavioral; a missing-symbol or source-substring failure is not accepted.
- TC-358-01b must distinguish token-bearing composer staging from marker-free fresh staging. The same exact disappearing row without v110 must refuse, proving external-share/internal-forward authority did not widen.
- TC-358-01c must run exact bound Protected and View-Once controls through accepted completion: v108 retirement and v111 cleanup still converge, but their attachment fingerprints remain null. A broad `policyVersion == 1` lineage patch must fail this row.
- The duration matrix need not duplicate every transport race three times: run one full causal journey at 3600 seconds, one DB/policy row each for 86400 and 604800, and one delayed-receipt assertion proving parent `expiresAt = receivedAt + 604800000` even when that exceeds the remaining v111 lease.
- TC-358-02b/02c must seed physical v111 directly through existing fixture authority before calling current retry APIs; do not let a new Plan-358 helper create its own prerequisite. The strict upload callback must observe byte-identical ciphertext and zero legacy upload.
- TC-358-02a includes selector-on proof-less compatibility: a persisted disappearing parent with no v110/v111 stays on the incumbent generic path and authors no strict/private custody.
- TC-358-03a must assert no secure-key/DB/marker/receipt effect on invalid shapes, missing lifecycle capability, hydrated raw-key/nonce drift or caught DB failure. The active replay uses a later sampled candidate time but must retain the original durable clocks, publish only the hydrated stage-result attachment after marker staging, and never emit an available message-change before that marker. A due replay calls the existing clock advance once, observes `expired`, emits no presentation and owes one receipt.
- TC-358-03/04 race competitors are created outside the current lock owner's Zone and expose attempted/entered/release completers. Final-state-only sequential orders do not prove serialization.
- TC-358-04a includes `incomingAckPending + durable local`, `incomingCommitted + durable local`, and blob-expired/no-local shortcuts after the parent deadline; each must expire/refuse before ACK, return, or network. The final transfer race separately proves the DB commit recheck.
- Extend existing `production_application_bootstrap_phase_contract_test.dart::TC-347-07b production composes one blob custody drain` and `test/shared/fixtures/media_repository_real_db_fixture.dart` only far enough to prove the exact `nowMs` argument crosses the incumbent delegate into the DB callback unchanged. `core-host-all` already executes that contract; add no separate command.
- Existing exact accepted differences are updated narrowly: TC-354-01a's disappearing negative becomes TC-358 positive; TC-355-01a's disappearing local-commit refusal becomes the expiry-aware matrix. P/VO negatives and ordinary positives remain unchanged.

## Implementation Steps

1. Snapshot `git status --short`. Add all four causal bundles in the existing files and run the single combined selector-on RED before production edits. Record the semantic failure for every selected `TC-358-` row.
2. Add/factor the exact disappearing producer-policy predicate in `private_media_policy.dart`. Keep P/VO and new-GIF decisions unchanged.
3. In `conversation_wired.dart`, mint v110 only for selector-on, exact newly authored disappearing image/video and route it to the incumbent token-bearing coordinator. Do not acquire a private transfer lease or change the ordinary composer path.
4. In `media_attachments_db_helpers.dart`, admit the exact disappearing policy only in token-bearing v111/v108 preparation/finalization and strict incoming-private stage/local commit. Keep fresh marker-free authority ordinary-only. Prevalidate every parent/attachment/duration/clock relation before writes and retain existing rollback behavior.
5. In `send_chat_message_use_case.dart`, adopt exact disappearing strict manifest/v108 ownership without widening private one-more-look. Preserve ACK-or-expiry store and live hedge behavior.
6. Extend the exact token-bearing retry predicates in both retry use cases. Existing complete v111 reopens through the ordinary strict coordinator; no-v111/partial/historical rows do not promote.
7. In `handle_incoming_chat_message_use_case.dart`, parse exact strict disappearing initials and require the incumbent message lifecycle plus media cleanup runtime before effects. Under the existing exclusive lifecycle lease, compare any durable hydrated attachment/key to the wire before the nested transactional stage, route duplicate/terminal decisions through that owner, use only its hydrated result, and apply the due-only clock decision before marker/publication/ready. Pre-deadline replay does not call the stream-emitting clock advance; due replay advances to terminal after atomic marker retirement and never presents.
8. In `messages_db_helpers.dart`, retire the exact message-kind display marker inside the transaction that advances a disappearing parent to `expired`; preserve reaction/other rows.
9. In `direct_inbox_custody_outbox_db_helpers.dart`, admit only the exact disappearing successor to Plan 352's existing pre-retirement lineage stamp. Do not broaden text/P/VO/deletion completion semantics.
10. In `download_media_use_case.dart`, the strict owner, repository interface/implementation, production bootstrap delegate and the existing DB commit helper, advance/reload before every strict shortcut and thread the same injected clock sample as explicit `nowMs` for the final in-transaction deadline recheck. Update the incumbent shared real-DB fixture and extend its existing bootstrap wiring contract; add no repository method or clock owner.
11. Re-pin only the existing media-repository placement digest and production-bootstrap layering digest, with adjacent Plan-358 reasons and unchanged assertions. Run the one combined selector-on GREEN/preservation command at concurrency 4, then default-define host `1to1` once, dart-only core once at concurrency 4 (which exercises both DTR contracts), analyzer, changed-Dart format/diff checks and one incremental Graphify refresh. Update Plan 358/index/status/coverage receipts only in the execution session.

Stop/re-review if implementation requires any new schema, relay TTL/renewal, wire field, network owner, scheduler, lock, test path, marker-free fresh disappearing authority, GIF authoring, repository method, native/platform edit, or production file outside the expected surface.

## Risks And Blind Spots

- Silent policy widening -> TC-358-01 pins exact token-bearing vs marker-free authority, duration, media kind, parent lifecycle and no-caption/edit/forward/quote boundaries.
- Crash between preparation stages -> TC-358-01/02 prove v111-before-network, atomic v108 binding, exact reopen and no generic strict promotion from partial/no-v111 state.
- Receiver clock reset on duplicate -> TC-358-03 replays with a later sampled clock and requires the first durable receiver clock/deadline/high-water byte-identically.
- Secure-reference replay alias -> TC-358-03 compares hydrated raw key/nonce before stage, rejects drift without overwriting the secure slot, and publishes the stage result rather than the wire attachment.
- Pre-marker stream leak -> pre-deadline replay never calls the general stream-emitting clock advance; due replay retires the marker transactionally before emitting only the terminal row.
- Two independent expiries conflated -> TC-358-04 exercises both orders across reopen; neither expiry changes the other's timestamp/row authority.
- Deadline bypass through local/ACK shortcuts -> TC-358-04 explicitly covers all shortcut states before the transfer path and the final transactional race.
- Stale display after expiry -> TC-358-03b seeds real ready/not-ready scoped rows and preserves reaction/unrelated markers.
- Secure-key compensated saga -> TC-358-03a covers caught DB failure; process-kill orphan-key behavior remains the inherited Plan-347 accepted residual and is not reframed as SQL atomicity.
- Destructive cleanup -> only incumbent terminal lifecycle authority deletes exact private file/key/attachment/thumbnail; v111 remains no-FK and attempt losers scrub only attempt-owned staging. No new scanner or broad delete is authorized.
- Seven-day promise ambiguity -> Scope and TC-358-01 explicitly preserve receiver-relative UI expiry without promising equivalent relay availability.
- Content-freeze churn -> the repository and bootstrap DTR hashes are the only expected re-pins; both retain adjacent Plan-358 reasons and are exercised by the once-only core family.

## Gate Cadence

- Inner loop: individual plain-name tests as needed while implementing; do not record or repeat every diagnostic run.
- First RED: one selector-on concurrency-4 invocation selecting all `TC-358-` rows across their existing files.
- Final focused proof: one selector-on concurrency-4 Flutter invocation over the same causal paths plus the repository no-auto-download sentinel and only the exact out-of-`1to1` preservation alternatives.
- Curated closure: `./scripts/run_host_test_gates.sh 1to1` once. The gate rejects batch/concurrency flags and currently resolves 120 unique paths; record the live count rather than copying it.
- Family closure: one dart-only `core-host-all --batch-flutter --concurrency 4` because shared core policy/DB helpers change and `media_attachments_db_helpers_test.dart` is not in `1to1`. Fall back to concurrency 2 only after a reproduced resource timeout. Do not run `feature-host-all` unless execution broadens shared feature repository/save/load/publication/bootstrap behavior beyond the named modality predicates.
- Default-off compatibility: the default-define host `1to1` already runs the full relevant sender/receiver/lifecycle suites, including proof-less disappearing and new-GIF exclusion. Do not add a separate selector-off batch.
- Wave closure: do not run full `host-all` for Plan 358. Run it once after the direct-private/disappearing wave (Plan 358 plus the separate disappearing DFE and explicit private-EDIT disposition) and once at final rollout/release closure.
- No dedicated migration/SQLCipher/account-transfer, Go/relay/node/bridge, native/bindings, device/Android/iOS, groups/feed/posts/performance/baseline, non-host `run_test_gates.sh 1to1`, completeness, or repeated whole-file campaign. Incidental Dart contracts included by core are acceptable; no platform harness is launched.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated changes.
git status --short

# One behavioral RED before production edits. Expect non-zero with every
# selected TC-358 row failing for its documented current-policy boundary.
flutter test --concurrency=4 \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/features/conversation/presentation/screens/conversation_wired_test.dart \
  test/core/database/helpers/media_attachments_db_helpers_test.dart \
  test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart \
  test/features/conversation/application/retry_failed_messages_media_reupload_test.dart \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  test/core/database/helpers/messages_db_helpers_private_media_lifecycle_test.dart \
  test/features/conversation/application/download_media_use_case_test.dart \
  test/features/conversation/integration/private_media_restart_replay_test.dart \
  --name 'TC-358-'

# Final selector-on GREEN plus only load-bearing sentinels outside host 1to1.
# Expect every selected name to run and zero failures.
flutter test --concurrency=4 \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/features/conversation/presentation/screens/conversation_wired_test.dart \
  test/core/database/helpers/media_attachments_db_helpers_test.dart \
  test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart \
  test/features/conversation/application/retry_failed_messages_media_reupload_test.dart \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  test/core/database/helpers/messages_db_helpers_private_media_lifecycle_test.dart \
  test/features/conversation/application/download_media_use_case_test.dart \
  test/features/conversation/integration/private_media_restart_replay_test.dart \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  --name 'TC-358-|TC-347-08c absent-v111 partial legacy attempt never promotes to strict|TC-347-03b strict failed retry reopens exact generation without legacy fallback|TC-355-04d production blob drain predicate retains private committed rows without download'

# Once-only curated/default-off compatibility lane; no batch/concurrency args.
./scripts/run_host_test_gates.sh 1to1

# Shared core policy/DB family once; no Android manifest/native tail.
./scripts/run_host_test_gates.sh core-host-all \
  --dart-only --batch-flutter --concurrency 4 --reporter failures-only

# Static/hygiene checks on the final tree.
set -euo pipefail
plan358_base_ref=66a5940de0d1a0d00f743c97ecca03c22527ca54
flutter analyze

plan358_dart_list="$(mktemp)"
trap 'rm -f "$plan358_dart_list"' EXIT
{
  git diff --name-only --diff-filter=ACMR \
    "$plan358_base_ref"...HEAD -- '*.dart'
  git diff --name-only --diff-filter=ACMR -- '*.dart'
  git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
  git ls-files --others --exclude-standard -- '*.dart'
} | sort -u > "$plan358_dart_list"
test ! -s "$plan358_dart_list" || \
  xargs dart format --output=none --set-exit-if-changed < "$plan358_dart_list"
rm -f "$plan358_dart_list"
trap - EXIT

git diff --check "$plan358_base_ref"...HEAD
git diff --check
git diff --cached --check

./graphify-arch/refresh_arch_graph.sh --incremental
git diff --check "$plan358_base_ref"...HEAD
git diff --check
git diff --cached --check
git status --short
```

## Execution Interpretation And Done Criteria

- Expected RED: all named TC-358 rows fail behaviorally because current code refuses disappearing strict preparation/receive/local commit or omits expiry marker retirement; no missing symbol/source-string failure counts.
- Green sentinel: default-off/proof-less disappearing, new GIF exclusion, ordinary strict, P/VO strict and no-v111 legacy behavior remain green through host `1to1`; selector-on proof-less compatibility is inside TC-358-02a, while the exact out-of-lane retry and no-auto-download sentinels run once in the filtered command.
- Representative mutation re-reds: four independent mutations are required and reverted: remove disappearing v110/token-bearing policy admission; route complete v111 retry to legacy/private upload or cancel v108 on live ACK; reset/bypass the durable receiver clock or marker retirement; bypass pre-shortcut/final download expiry requalification.
- Pre-existing dirty tree / known failure: execution starts only from an explicitly accepted clean or documented checkpoint; none known at planning baseline.
- Environment blocker: none. Host SQLite/temp-file evidence is the intended closure tier; no unavailable device can block this plan.
- Scope drift: any schema/relay/native/new owner/scheduler/lock/test-path/GIF-authoring/fresh-marker-free expansion stops execution for re-review.

- [x] Every behavior has a named causal test or exact preservation proof.
- [x] One combined behavioral RED, final combined GREEN, and four mutation re-reds are recorded.
- [x] v111 commits before blob network and v108 commits before chat egress.
- [x] Receiver clock starts once, survives replay/reopen, and expires without stale display.
- [x] Pre-deadline replay preserves all receiver clock columns, compares hydrated key material under the lifecycle lease, and emits no available stream event before marker staging; due replay emits only the terminal row after marker retirement.
- [x] Strict download checks expiry before every shortcut and again at final commit.
- [x] Transport expiry and receiver-local disappearance remain independent in both orders.
- [x] Selector-off/proof-less/GIF legacy, ordinary and P/VO behavior stay unchanged.
- [x] Host `1to1` and only the justified dart-only core family pass once.
- [x] No new test path/registration/completeness or unauthorized family/device gate is added.
- [x] Analyzer, changed-Dart format, staged/unstaged/baseline diff hygiene and incremental Graphify are clean.
- [x] The bootstrap delegate and shared real-DB fixture forward the exact `nowMs`; only the two reviewed DTR-18 digests are re-pinned with adjacent reasons and unchanged assertions.
- [x] Scope Contract And Guard is respected; no activation, GAP-N01 closure or release claim is made.

## Handoff

- First causal RED command: the single ten-file selector-on `--name 'TC-358-'` invocation above.
- Final proof command: the single eleven-file selector-on filtered invocation above; verify every selected name, including the no-auto-download sentinel, and do not rerun it ad hoc.
- Manual registration: none; every test extends an existing path.
- Migration: none; DB remains v111 and physical v108/v110/v111 stay byte-compatible.
- Boundary closure: host-only current-schema SQLite, secure-key compensation, real temp files and file-backed reopen.
- Runtime defaults: existing client selector and relay admissions remain default-off.
- Deferred: disappearing DFE and private EDIT disposition (reviewed Plan 359 handoff), direct-private/disappearing wave full `host-all`, activation/cohort/device/iOS/release closure.
- Unresolved evidence: none for Plan 358's bounded code adopter; relay availability for the full receiver-relative duration is explicitly not promised.

## Reviewer Findings

Initial verdict: **plan-fixes-required; core bet confirmed**.

Required fixes were applied:

- Outgoing strict custody remains token-bearing and prepared-only. TC-358-01c now proves exact disappearing lineage through v108 completion/v111 drain while exact Protected/View-Once controls still retire custody without receiving a fingerprint; TC-358-02a proves selector-on proof-less disappearing remains generic legacy.
- Active disappearing replay now requires the incumbent lifecycle capabilities, compares hydrated raw key/nonce and immutable attachment identity under the existing exclusive lease, and publishes only the stage result's durable attachment. Terminal replay retains Plan 355's reduced proof after legitimate attachment/key cleanup.
- Pre-deadline replay leaves all three receiver clock columns unchanged and emits no available stream before marker staging. A due replay alone calls the existing clock advance; its transaction retires the exact marker before the existing lifecycle stream emits the terminal row.
- The final strict download uses one explicit sampled `nowMs` through owner, repository interface/implementation, production bootstrap delegate and DB. The existing real-DB fixture and TC-347-07b wiring assertion cover that exact forwarding.
- Only the media-repository placement digest and production-bootstrap layering digest may be re-pinned, with adjacent Plan-358 reasons and unchanged DTR assertions.
- The final proof adds the one out-of-lane no-auto-download sentinel, while the first RED remains ten causal files. Fixed-baseline, trap, post-Graphify diff checks and `failures-only` core reporting are literal and failure-safe.

Targeted sender/storage, receiver/lifecycle and gate/economy re-reviews all returned **READY**, with no remaining required delta.

## Arbiter Decision

**READY / EXECUTION_READY. Core bet confirmed.** Plan 358 is one coherent initial-media adopter: outgoing disappearing reuses the exact token-bearing v110/v111/v108 owners, incoming disappearing reuses the strict-private atomic stage/download and receiver-local lifecycle, and their transport/content clocks remain independent. The post-drain lineage stamp is retained because this transaction is the last point at which the generation is provable; it adds no deletion behavior.

The test disposition is intentionally lean: ten named causal tests in four bundles, one concurrency-4 RED, one concurrency-4 final proof with three exact out-of-lane sentinels, one sequential curated `1to1`, and one dart-only 404-path core batch at concurrency 4. No feature/full/device/Go/completeness campaign is authorized. No schema, relay, native, new owner, scheduler, lock, repository method, activation, GAP-N01 closure or release claim is added.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-11 | Causal RED | The ten plan test paths | One selector-on concurrency-4 `--name 'TC-358-'` invocation | `+1 -10`: every named row failed behaviorally (HEAD mints no disappearing v110, DB predicates refuse the prepared parent, completion skips nonordinary lineage, the receiver refuses the strict disappearing initial and its local commit, retry validators refuse the token-bearing parent, and expiry retires no display marker). The single pass is the added TC-358-03b Protected/View-Once control, which asserts unchanged incumbent behavior. | No missing-symbol or source-substring failure was accepted. | production edits |
| 2026-08-11 | Implementation | 13 of the 14 expected production files plus the shared real-DB fixture and the TC-347-07b wiring contract; `retry_failed_messages_use_case.dart` inherited the widened shared validator and required no production edit | Per-bundle GREEN after each step | Policy predicate, token-bearing v110/v111/v108 admission, exact-lineage stamp, composer/sender/retry adoption, strict disappearing receive under one lease, expiry marker retirement, download requalification and the explicit `nowMs` thread | No file outside the expected surface was touched. No schema, wire, relay, native, new owner/scheduler/lock/repository method. | combined proof |
| 2026-08-11 | Combined GREEN | The eleven-file filtered proof | One selector-on concurrency-4 invocation | `+14` and zero failures: ten named TC-358 rows, the TC-358-03b P/VO control, and the three out-of-lane sentinels `TC-347-08c`, `TC-347-03b`, `TC-355-04d` | Every selected name ran. | curated closure |
| 2026-08-11 | Curated closure | `1to1` and dart-only `core-host-all` | `./scripts/run_host_test_gates.sh 1to1`; `./scripts/run_host_test_gates.sh core-host-all --dart-only --batch-flutter --concurrency 4 --reporter failures-only` | `1to1` PASS at **120/120 paths** (live count measured, final path `#120`); `core-host-all` PASS at **404 test paths / 3,237 tests**. Both ran concurrently. | One recorded correction was required first (below). | mutations + hygiene |
| 2026-08-11 | Recorded correction | `handle_incoming_chat_message_use_case_test.dart` | Default-define `1to1` surfaced `TC-354-04c` | That incumbent Plan-354 contract pinned the exact pre-358 spelling of the strict-private capability gate and the textual position of the durable-supersession branch relative to marker staging. Plan 358 adds the lifecycle-owner and cleanup-runtime requirements to that same fail-closed gate and moves the atomic stage INSIDE the exclusive lease that already owned the marker/publication/promotion. Both original properties are retained and restated against the real structure, and the assertion now additionally requires the two new capabilities. | Property preserved and strengthened; only the literal spelling and textual order moved. | mutations |
| 2026-08-11 | Mutation re-reds | Four independent production mutations, each reverted | Each named row re-run under its mutation | M1 ordinary-only token-bearing admission -> TC-358-01b RED; M2 disappearing removed from the shared token-bearing retry predicate -> TC-358-02b and TC-358-02c RED; M3 expiry marker retirement unhooked -> TC-358-03b RED; M4 pre-shortcut deadline requalification bypassed -> TC-358-04a RED. All four reverted and the combined `+14` proof re-confirmed on the restored tree. | 4/4 required mutations executed and reverted. | hygiene |
| 2026-08-11 | Static/hygiene/graph | Final tree | `flutter analyze`; changed-Dart `dart format`; three `git diff --check`; incremental Graphify | Analyzer: **No issues found**. Format: 28 changed Dart paths, clean. Baseline/unstaged/staged diff checks clean before and after Graphify. Incremental Graphify: 28 changed code files / 3,123 unchanged / 0 deleted, closing at **71,012 nodes / 104,353 edges**; TDD overlay 1,563 files / 15,323 named tests / 1,199 production targets. Two reviewed DTR-18 digests re-pinned with adjacent Plan-358 reasons and unchanged assertions (media-repository placement `027226d2…`, production-bootstrap layering `1d7df44e…`). | No feature/full/device/Go/completeness campaign was run, per the authorized cadence. | closed |

## Execution Outcome

**EXECUTION_COMPLETED / DEFAULT-OFF / NOT RELEASE-ELIGIBLE.**

Every Done Criteria item is satisfied:

- Ten named causal tests plus three exact out-of-lane preservation proofs, all in existing paths; no new test file, registration or completeness run was added.
- One combined behavioral RED (`+1 -10`), one combined GREEN (`+14`), and four mutation re-reds executed and reverted.
- v111 commits before the first LAN/relay blob callback and v108 commits before chat egress (TC-358-01a observes the durable v110 token and the complete `outgoing_prepared` generation inside the first strict upload callback).
- The receiver clock starts once, survives replay and file-backed reopen, and expires without stale display.
- Pre-deadline replay preserves all three receiver clock columns and compares hydrated key material under the lease; a due replay emits only the terminal row after marker retirement.
- Strict download checks expiry before every shortcut and again at the final in-transaction commit.
- Transport expiry and receiver-local disappearance remain independent in both orders across a real reopen.
- Selector-off, proof-less, GIF-legacy, ordinary and P/VO behavior are unchanged (default-define host `1to1` 120/120; selector-on proof-less compatibility is inside TC-358-02a).
- Host `1to1` and only the justified dart-only core family ran, once each.
- Analyzer, changed-Dart format, all three diff-hygiene checks and one incremental Graphify refresh are clean on the same final tree.
- The bootstrap delegate and the shared real-DB fixture forward the exact `nowMs`; only the two reviewed DTR-18 digests were re-pinned.
- No activation, GAP-N01 closure or release claim is made.

Accepted differences carried forward unchanged: disappearing Delete-for-Everyone and private EDIT remain outside Plan 358 and are handed to the separately reviewed Plan 359 scope; a receiver-local 7-day deadline may outlive the remaining fixed relay blob lease after delayed delivery, and no renewal or server change is added under D-234-05; pre-358, no-v111, selector-off, proof-less GIF and already-drained historical rows are neither scanned nor promoted.

One further accepted difference is new: an ACTIVE strict-private replay whose durable attachment has already left the fresh `pending` projection (the user downloaded it) adopts that durable projection instead of re-running the insert-shaped stage, and a durable v111 survivor in any state other than `incoming_committed`, or with a disagreeing public commitment, fails closed with no receipt. This is strictly narrower than the pre-358 generic duplicate shortcut it replaces for this modality, and it exists only for disappearing media, which has no shipped production behavior to regress.

## Post-Execution Audit

**POST_EXECUTION_AUDIT_CLOSED at `4e24d7451c30d2a6f6f609dfcc3b0880d2ac70f6`.** A clean-tree source, test, receipt and change-surface review found no executable defect and did not repeat the already-current expensive gates. The final architecture graph is current at fingerprint `88c2f3f763067ef2`; the exact disappearing post-v108 fingerprint remains durable after v111 drain, while proof-less/no-v111 rows remain distinguishable. The Plan 357 baseline-to-closure change set contains the reviewed 13 production files and 15 test/fixture paths, all within the authorized surface, and all recorded diff hygiene remains clean. Plan 359 may use this exact commit as its accepted baseline; this audit makes no activation, GAP-N01 or release claim.
