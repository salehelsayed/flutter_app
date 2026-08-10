# 355 - GAP-N01 Protected + View-Once Custody Post-Execution Closure

Status: **REVIEWED / EXECUTION-READY / DEFAULT-OFF REPAIR PLAN / DO NOT CLAIM PLAN-354 OR GAP-N01 CLOSURE UNTIL GREEN** (2026-08-10)
Type: Bug / modification
Baseline observed while planning: `6f66a80984be582a25f2d48650674847798a2088` (`docs: mark Plan 354 complete`)
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` rule 3 (durable ACK-or-expiry custody), rule 9 (lifecycle recheck before presentation), A-03 and A-28; gap inventory `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md` GAP-N01 / WP-01 / section 9.2
Classification: bounded post-execution repair of Plan 354's existing Protected/View-Once initial adopter; no new modality or durable authority
Closure tier: behavioral host tests with real SQLite/files plus affected curated/core/feature families; no schema, relay, native, mobile, iOS, activation, or release claim

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-10 | Post-execution auditors | Plan 354 receipts and all 21 named tests; private explicit download; strict local-path commit; private terminal replay; display marker/publication; thumbnail; bootstrap drain policy | Plan 354's final source-order tests are green, but the production route still has executable defects. The latest append-only STATUS entry correctly records `POST_EXECUTION_REVIEW_INCOMPLETE`. | Repair the existing adopter before starting disappearing media or another N01 modality. |
| 2026-08-10 | Planner | `StrictDirectMediaBlobDownloadAckOwner`; direct-private download claim; v111 commit; handler duplicate and strict branches; notification-display owner; message publication; private producer matrix; current gate ownership | One no-schema repair plan is coherent because every defect belongs to the same Plan-354 private-initial owner. Four behavioral bundles are sufficient; no new outbox, scheduler, lock, or transport is justified. | Write exact RED/GREEN contracts and invoke `$tdd-review`. |
| 2026-08-10 | Independent reviewers | Download/storage/path/recovery; receiver replay/lifecycle/presentation; literal tests/gates/risk | Core bet confirmed. Required bounded amendments closed stale-row commit, strict-to-legacy escape, ACK-before-local-durability, reversible LAN staging, exact terminal identity, active duplicate/delete ordering, exact marker retirement, notification eligibility, lock scope, and non-vacuous commands. Final targeted verdicts: READY / READY / READY. | Record the reviewed contract; no implementation in this planning session. |
| 2026-08-10 | Arbiter | Amended four-bundle contract, four mutation re-reds, preservation set, host-only cadence, stop conditions | Plan 355 is sufficient and execution-ready. It reuses existing v111/private lifecycle/display owners and adds no durable architecture. | Append the exact readiness marker and hand off to a separate implementation session. |

## Problem And Evidence

- Behavior to repair: a selector-on Protected/View-Once initial can be staged and received, but its explicit strict download cannot complete the durable local-path plus source-pinned v111 transition. Terminal replay and terminal-after-stage races can also enter generic duplicate/display behavior or publish stale private media.
- User impact: a user can explicitly download valid protected media, incur network/decrypt work, and still lose the canonical promotion because the final DB CAS necessarily refuses. A consumed/hidden/deleted/expired private item can also cause a stale display retry, marker, thumbnail, or message publication instead of monotonic zero-effect supersession.
- Why Plan 354's green receipt missed it: TC-354-04c/04d/05a and related rows mostly inspect source ordering. They prove tokens are present in files, not that the real DB state after the private claim can commit or that the production handler reaches the dedicated terminal disposition. TC-354-05d copies the bootstrap predicate instead of invoking production policy.
- Confirmed download counterexample: `downloadMedia` changes the durable attachment to `downloading`, then passes the stale pre-claim attachment to `StrictDirectMediaBlobDownloadAckOwner`. That owner calls `commitIncomingDirectMediaBlobLocalPath`, whose DB helper still accepts only policy-v0 `ordinary` parents and exact-compares the stale attachment row. A protected or View-Once strict download therefore cannot commit `done` or `incomingAckPending`.
- Confirmed path/recovery counterexample: private preflight authorizes canonical plus `.private.enc`/`.private.enc.dec`, but LAN can still use un-authorized `$canonical.enc`, decrypt to `$canonical.enc.dec`, and trust an arbitrary bridge-returned path. On an ordinary error return, the process token is released while the durable row can remain `downloading`; private cleanup does not own every dynamic sibling.
- Confirmed replay counterexample: generic existing-message duplicate handling runs before the strict-private terminal owner. A retained terminal attachment may promote display and return generic `duplicate`; a consumed row without its attachment refuses with no receipt. The private DB terminal branch is therefore not reliably reachable from production.
- Confirmed presentation counterexample: after one post-stage terminal re-read, thumbnail write, display-marker stage, publication, and later marker promotion occur outside one lifecycle decision. Hide/consume/expiry/contact deletion can win between those steps. Publication suppresses only deleted/hidden state, not all exact private terminal states, and some supersession results are mapped back to `duplicate`, which tells the listener to retry global display work.
- Confirmed identity counterexample: `privateMediaAttachmentKindForMediaIdentity` uses MIME OR `mediaType`; crossed pairs such as `video/mp4` plus `mediaType=image` can be admitted. Terminal survivor comparison also omits custody kind, contract, and transport MIME from the public immutable commitment.
- Existing owners to reuse: the direct-private transfer registry and `MediaAttachmentLifecycleLock`; `StrictDirectMediaBlobDownloadAckOwner`; the physical v111 row; the existing incoming local-path transaction; the private lifecycle/cleanup owner; direct notification display outbox; and the dedicated `durablySuperseded` handler/listener disposition. No new durable authority is required.
- Expected production surface: existing Dart files only: `private_media_policy.dart`, `media_attachments_db_helpers.dart`, `messages_db_helpers.dart`, `media_attachment_repository.dart` and implementation only as needed to expose/reuse the incumbent lifecycle authority, `download_media_use_case.dart`, `strict_direct_media_blob_download_ack_owner.dart`, `direct_private_media_lifecycle.dart` only to distinguish retry-source preservation from terminal cleanup, `handle_incoming_chat_message_use_case.dart`, `message_repository.dart`/implementation, direct display-outbox helper only if its existing parent guard must become private-terminal-aware, and production bootstrap only for one testable policy predicate. Stop for re-review if a migration, new owner/table/queue/journal/scheduler/lock/network caller, wire change, relay/native edit, or scanner is proposed.

## Graph Grounding Snapshot

- Query/profile: `python3 graphify-arch/tdd_context.py query "StrictDirectMediaBlobDownloadAckOwner dbCommitIncomingDirectMediaBlobLocalPath dbCommitDirectPrivateMediaDownloadIfEligible handleIncomingChatMessage durablySuperseded stageNotificationDisplayCustody privateMediaState" --profile tdd --budget 700`.
- Graph fingerprint/freshness: current architecture fingerprint `d29d7e05e4e65fc1` at planning baseline.
- Primary anchors: `StrictDirectMediaBlobDownloadAckOwner`, `handleIncomingChatMessage`, `dbCommitIncomingDirectMediaBlobLocalPath`, `dbCommitDirectPrivateMediaDownloadIfEligible`, `IncomingDirectPrivateMediaBlobCustodyRepository`, and `MediaAttachmentLifecycleLock`.
- Direct proof candidates: existing DB-helper, download-use-case, handler, listener, private cleanup/restart, thumbnail, repository, bootstrap, and notification-display tests. All proposed causal additions extend existing paths; no new test path or registration is expected.
- Graph gaps verified directly in source: ordinary-only final commit; stale pre-claim expected attachment; early generic duplicate; post-stage unlocked effects; incomplete private terminal publication predicate; MIME/mediaType OR classification; copied bootstrap predicate.

## Scope Contract And Guard

In scope:

- Preserve Plan 354's exact producer set: v1 Protected with one image or video and v1 View Once with one image. Disappearing, GIF, View-Once video, audio/voice, file, multiple attachments, captions/edits/forwards, groups, and malformed policy remain excluded.
- Before the private DB download claim, perform a read-only path preflight using the existing private path guard. Authorize the canonical path, legacy LAN `$canonical.enc`, deterministic `$canonical.private.enc`, and deterministic `$canonical.private.enc.dec` without creating directories or files. An unsafe initial path causes zero network and zero durable mutation. Repeat the exact check inside the strict owner immediately before source/decrypt work; post-claim path drift causes zero network/file work and only the bounded exact failure-CAS transition.
- Before any generic proof-less download fallback, classify the persisted private lane. A fingerprinted strict-private parent with missing, crossed, expired, or unsupported v111 state fails closed or converges through the exact v111 expiry/terminal owner; it never calls the legacy P2P media helper. Only a pre-354 private parent with no strict fingerprint and no v111 retains the current legacy explicit-download path.
- After `beginDirectPrivateMediaDownloadWithinLock` changes the exact row to `downloading`, reload/hydrate the current attachment under the same exact-attachment lifecycle lease. Require the same message, lane, immutable descriptor, key/nonce/hash/fingerprint, and exact `downloading` state; return the qualified row plus current transfer token, release that exact-ID lease, and only then enter the strict owner's existing repository-wide custody lifecycle section. Pass that current row—not the UI/pre-claim snapshot—to the strict owner. Do not attempt an exact-ID-to-exclusive lock upgrade. A failed requalification releases the exact claim through the existing private failure/recovery CAS and retains v111.
- Generalize the existing `dbCommitIncomingDirectMediaBlobLocalPath` transaction instead of adding a capability: retain its unchanged ordinary-v0/pending behavior, and additionally accept an incoming v1 Protected/View-Once available parent plus the exact claimed `downloading` row. Disappearing stays refused. The same transaction commits canonical path + `done` and, for a relay source, `incomingCommitted -> incomingAckPending`; source-less LAN remains `incomingCommitted`. Any attachment or v111 failure rolls both halves back. Source-pinned ACK remains strictly after that commit.
- Pin the state matrix before transfer: `incomingCommitted` plus an exact claimable row may download; `incomingCommitted` plus exact canonical `done` locally adopts without ACK; `incomingAckPending` plus exact canonical `done` retries only the source-pinned ACK; `incomingAckPending` plus missing/retryable/downloading local state does not ACK, claim, download, or delete v111; exact expiry uses the existing expiry transition; a terminal winner uses existing private cleanup while v111 converges independently. No row in these strict states may fall through to legacy transport.
- In private mode, normalize both relay and LAN ciphertext into the existing deterministic private pair. Verify and **copy** the legacy LAN candidate (or use an equivalently reversible staging operation) only after path authorization; preserve the original byte-identical LAN source through every retryable nonterminal noncommitted return and process crash. Delete it only after the atomic local-path/v111 commit succeeds or exact terminal-cleanup authority wins. Require the bridge's returned decrypted path to equal the authorized deterministic `.private.enc.dec` path before stat, delete, rename, or promotion. Ordinary Plan-347 candidate behavior remains byte-identical.
- Every noncommitted return/throw after a successful claim must classify its owner outcome explicitly. Pre-network drift, network/proof/decrypt/output refusal, and commit loss use the exact private failure/recovery CAS to make `downloading` retryable, scrub only attempt-owned canonical/private siblings, retain v111, and preserve the verified legacy LAN `$canonical.enc` retry source. Narrow the existing interrupted-download artifact expansion accordingly for this strict incoming retry case; terminal private cleanup must still delete that legacy source. Exact expiry may terminalize the attachment and retire v111; a private terminal winner may remove the attachment while v111 remains independently ACK/expiry-governed. Process crash recovery continues through the existing interrupted-download reconciliation; prove it with file-backed reopen rather than adding cleanup machinery.
- Route only a selected strict-private terminal replay around generic duplicate handling. Active available/opening/viewing exact replay retains its current path. Build the wire-derived fresh candidate for DB qualification instead of seeding a terminal candidate; the DB remains the sole authority that verifies the durable same-author/private-policy terminal parent and optional surviving v111 commitment.
- In the private DB stage, classify the exact private terminal winner before the generic tombstone branch. Map a selected private author tombstone to the dedicated `durablySuperseded` result; retain the generic deletion result for non-private/legacy cases. A physically absent parent with surviving v111 remains refused/retryable and emits no receipt.
- Compare a terminal survivor's complete immutable public commitment: attachment/message identity, direction/state family, custody kind, custody contract, content hash, ciphertext size, transport MIME, and expiry. Continue excluding ACK-source and retry metadata. For the reduced no-v111 case, require equality of every surviving immutable wire parent field: message ID, sender/contact, timestamp, dedup key, forwarded flag, quote, the empty-caption initial producer shape, policy version/mode, and null private duration; an author tombstone additionally requires `deleted_by_peer_id == senderPeerId`. If an attachment still survives, compare its exact immutable descriptor and fingerprint too. Once both attachment and v111 are gone, blob-byte identity is inherently unprovable; accept only that explicitly reduced parent equivalence and add no schema/backfill.
- Serialize the selected strict-private existing-row decision through stage, terminal re-read, protected thumbnail, marker stage, repository publication, and ready promotion with the incumbent repository-wide exclusive `DirectPrivateMediaCleanupRuntime.directPrivateMediaLifecycleLock.synchronizedAll` lease. Nested private repository acquisition must be reentrant; never acquire the exclusive lease while holding an exact-ID lease, and no detached work may escape it. Network, contact metadata, receipt transport, or other unbounded work stays outside. Whichever existing lifecycle owner wins first decides: terminal-first produces durable zero-effect supersession; receive-first completes publication, after which terminal state retires its presentation authority.
- Make private publication and the production canonical-keep, replacement, and display-projection policies suppress every exact terminal state, including consumed/expired, without emitting or showing a message. A publication-time private supersession returns the dedicated terminal result, never generic `duplicate`; the listener therefore never invokes global display retry. Reuse/add one exact message-kind display-marker retirement seam keyed by peer plus message event identity inside the incumbent terminal/stage transaction. It must retire both `not_ready` and `ready` message markers while preserving same-message reaction and other-message rows.
- Preserve the Protected inline thumbnail as best effort only. It may be written after atomic custody while holding the existing lifecycle authority; a terminal-first winner produces none, and receive-first cleanup removes it. Do not promote thumbnail state into durable authority.
- Make MIME and `mediaType` classification coherent at the shared existing predicate. MIME-derived kind must agree with the persisted media type, preserving the intentional `image/gif` + `media_type=image` classification as GIF so it remains refused.
- Replace the copied TC-354 bootstrap predicate proof with one behavioral invocation of the exact production policy. At most extract one tiny pure predicate adjacent to the existing drain callback; both production and test must call it. This row is GREEN-only after that behavior-preserving extraction; the TC-355-04 causal RED comes from terminal marker/publication and MIME identity behavior. Do not introduce a policy class, drain framework, or new file solely for testing.
- Keep every selector/admission default-off. This plan repairs code/evidence only; it does not activate private custody, expand mixed-version support, or claim release eligibility.

Out of scope / hard do not:

- No disappearing-media adoption, private EDIT/delete-event custody, groups/announcements, historical promotion, linked-device fanout, notification outcome ledger, activation/cohort/rollback work, aggregate quota/UX, or release closure.
- No DB v112, table/column/index, v110 expansion, new v108/v111 kind, new queue/outbox/drain/scheduler/lock, cleanup journal/scanner, second strict upload/download owner, protocol/native/bridge change, bindings, or platform harness.
- No broad refactor of generic message duplicate handling, notification display, media policy, or download architecture. Every change must be guarded by an exact strict-private predicate and preserve ordinary/legacy behavior.
- Do not accept source-string/order tests as the causal proof for this repair. The causal Plan-355 rows must execute the real production owner with real SQLite/files and deterministic barriers. TC-355-04d (shared production drain predicate) and TC-355-04e (bootstrap notification wiring) are explicit GREEN-only preservation/wiring sentinels after the production behavior is established by 04a/04b/04c/04f; neither counts as a first RED or mutation proof.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-355-01 | Exact private explicit download succeeds end to end without legacy escape. Protected image/video and View-Once image claim `downloading`, reload the exact current row, verify/decrypt through authorized deterministic paths, atomically commit canonical `done` plus relay `incomingAckPending`, then ACK; LAN commits `done` but stays `incomingCommitted`. The strict state table distinguishes committed, ACK-pending, expiry, terminal, crossed, and pre-354 legacy rows; an ACK-pending row without exact local `done` never ACKs or loses v111. | `media_attachments_db_helpers_test.dart::TC-355-01a private strict local path and v111 ACK state commit atomically`; `download_media_use_case_test.dart::TC-355-01b explicit private strict download commits before ACK and never falls through` | real SQLite + real temp files + fake bridge/proof/ACK; parameterized policy/mode/state | HEAD private claim succeeds but ordinary-only/stale final CAS returns false; wrong strict states fall through or can ACK before local durability -> exact private current-row commit and closed decision table | restore ordinary-only predicate, pass pre-claim row, or allow strict-to-legacy/early ACK -> RED; revert | focused; helper AUTO core, download host `1to1` + AUTO feature |
| TC-355-02 | Private path, failed-claim, and crash recovery are bounded. Unsafe canonical/LAN/private/decrypt symlinks refuse before claim/network; LAN is copied/reversibly normalized into the deterministic private pair while its source survives until commit; arbitrary bridge-returned decrypt path refuses without touching its target. Pre-network drift, network/proof/decrypt/output failure, and commit loss release `downloading`, scrub only attempt-owned bytes, retain v111 and preserve LAN source; exact expiry/terminal outcomes follow their existing owners. File-backed restart reconciles the exact siblings and leaves sibling/source files untouched. | `download_media_use_case_test.dart::TC-355-02a private strict path guard and deterministic staging preserve retry authority`; `private_media_restart_replay_test.dart::TC-355-02b interrupted private strict download reopens without residue or v111 loss` | guarded temp tree + unsafe symlink + file-backed SQLite reopen | HEAD omits the LAN path, trusts bridge return, moves through dynamic paths, and can leave `downloading`/residue -> one enumerable reversible recovery path | bypass exact decrypted-path check, destroy LAN source before commit, or omit failure CAS -> RED; revert | focused; download/restart host `1to1` or AUTO feature |
| TC-355-03 | Terminal replay reaches the private DB owner before generic duplicate logic. Consumed/expired/hidden/author-deleted exact parents with matching committed/ACK-pending survivor or exact reduced no-v111 parent equivalence return `durablySuperseded`, exactly one receipt, zero key/attachment/marker/promotion/stream/notification/global retry. Crossed immutable parent fields, deletion author, non-null duration, attachment descriptor, full commitment, or a physically absent parent refuse with zero receipt; an active duplicate racing author deletion is decided by the final transactional reread. | `media_attachments_db_helpers_test.dart::TC-355-03a private terminal replay compares complete surviving authority`; `handle_incoming_chat_message_use_case_test.dart::TC-355-03b strict private terminal replay bypasses generic duplicate and removed parent emits no receipt`; `chat_message_listener_test.dart::TC-355-03c production terminal outcomes never retry display` | real SQLite + handler/listener fakes + exact receipt/display counters + barrier | HEAD generic duplicate intercepts terminal rows and maps some supersession back to duplicate -> dedicated reachable terminal route | map either private terminal result to duplicate/global retry or trust pre-read active state -> RED; revert | focused; helper AUTO core, handler/listener host `1to1` + AUTO feature |
| TC-355-04 | Post-stage presentation and policy remain monotonic. The incumbent repository-wide exclusive lifecycle authority serializes the selected private decision/stage/re-read/thumbnail/message-marker/publication/ready sequence against hide/consume/expiry/contact-delete in both lock orders. Real SQLite `not_ready` and `ready` message markers are retired by the **actual** terminal-first private stage branch and receive-first View-Once consume/private-hide transactions while same-message reactions and other-message rows survive; production canonical keep/replacement/display projection cannot show terminal private media. Consumed/expired publication suppresses; crossed MIME/mediaType refuses; valid producer shapes remain. After a tiny behavior-preserving extraction, the actual production drain predicate retains private `incomingCommitted` without network. | `receive_protected_photo_thumbnail_test.dart::TC-355-04a private terminal and strict presentation converge under one lifecycle authority`; `107_direct_notification_durability_test.dart::TC-355-04b private terminal owners retire only the exact message display marker`; `message_repository_impl_test.dart::TC-355-04c private terminal publication emits no message`; `media_attachment_repository_impl_test.dart::TC-355-04d production blob drain predicate retains private committed rows without download`; `production_application_bootstrap_phase_contract_test.dart::TC-355-04e production notification policies exclude terminal private media`; `private_media_policy_test.dart::TC-355-04f private media identity requires coherent MIME and mediaType` | completer barriers, real SQLite markers through production DB owners, temp thumbnail, repository stream counter, production predicate and wiring, pure policy table | HEAD releases lifecycle authority before effects, leaves terminal markers/policies eligible, publication misses consumed/expired, identity uses OR, and policy proof is copied -> one existing-owner sequence plus exact predicates | unhook marker retirement from a terminal owner, remove lifecycle span, or re-admit terminal presentation -> RED; revert; TC-355-04d/04e are GREEN-only after extraction/wiring | focused; existing AUTO core/feature paths, no new registration |
| PRES-355-A | Ordinary strict download, Plan-351 tombstone/display convergence, Plan-354 atomic private stage/key compensation, valid producer shapes, selector-off/proof-less legacy behavior, ordinary duplicate display retry, private expiry loss, strict network ownership, and no-auto bootstrap wiring remain unchanged. | exact sentinels under Acceptance Gates | existing fixtures | GREEN -> GREEN | any widened generic/private behavior -> sentinel/shell RED | exact commands only; do not rerun whole files |

Test notes:

- TC-355-01a must install a trigger that aborts the v111 update after the attachment write and assert both rows roll back. The relay success observation must see `done` plus `incomingAckPending` before the first ACK callback. The LAN success observation must see `done` plus unchanged `incomingCommitted` and no ACK.
- TC-355-01b must inspect the bridge callback's DB row and prove it is the reloaded `downloading` projection, not the pre-claim UI object. It must separately pin `incomingAckPending + done/local` ACK retry and `incomingAckPending + missing/retryable/downloading` retention with zero ACK/network. A fingerprinted strict row in every nonlegacy state must show zero generic helper calls; only the exact no-fingerprint/no-v111 historical row may retain legacy behavior.
- TC-355-02 uses completers and filesystem barriers, never sleeps. The arbitrary decrypt-path case supplies a same-size regular file outside the authorized root and proves it is neither deleted nor renamed. A post-normalization CAS-loss/reopen case must preserve the byte-identical LAN source, remove attempt-owned private/canonical candidates, leave `downloading` recoverably failed, retain v111, and make zero relay calls; a paired exact terminal-cleanup case must still remove the legacy LAN source.
- TC-355-03a must exercise `incomingCommitted` and `incomingAckPending` survivors with identical public commitment but different ACK/retry metadata, the reduced no-v111 immutable-parent matrix, deletion-author/duration crossings, and a surviving exact-attachment descriptor crossing. TC-355-03b must force terminal-with-survivor, terminal-without-v111, and consumed-without-attachment routes through the production handler. A source scan or direct DB-helper call alone is insufficient. It must also force parent removal after a successful stage result and before receipt, proving no receipt without durable author/policy authority, plus active-pre-read then author-delete before final reread.
- TC-355-04a must force both lock orders and include the later generic ready-promotion site; merely checking one pre-marker re-read is insufficient. No async work started under the exclusive lifecycle lease may be detached. TC-355-04b must use separate real-SQLite fixtures for the unique `not_ready` and `ready` event keys, seed same-message reaction plus unrelated-message rows, and reach retirement only through (a) the real private-stage terminal-first branch and (b) the real View-Once consume/private-hide receive-first transitions. Calling the marker-delete helper directly is not proof.
- TC-355-04d is intentionally GREEN-only after the tiny production-predicate extraction; it must invoke the same callable predicate/callback production bootstrap uses rather than copy its body. TC-355-04e is likewise GREEN-only as the wiring/canonical-policy sentinel and must cover canonical keep, replacement, and display projection. Removing the production call that attaches exact marker retirement to private stage/consume/hide must re-red TC-355-04a/04b; a direct helper-only test is never sufficient.
- Required mutation re-reds: (1) restore ordinary-only or stale-row final commit; (2) map terminal replay/publication back to generic duplicate; (3) unhook exact message-marker retirement from the private stage/consume/hide terminal transactions; (4) remove the exclusive lifecycle serialization/final requalification. Each must turn its named behavioral test red and be reverted. Do not create a separate mutation framework.

## Implementation Steps

1. Confirm a clean baseline at `6f66a8098`, retain the append-only Plan-354 post-execution-incomplete marker, and record the first behavioral RED for TC-355-01 through TC-355-04. The REDs must fail on the demonstrated behavior, not on a missing symbol or source string.
2. Tighten `privateMediaAttachmentKindForMediaIdentity` to coherent MIME/mediaType classification with the GIF exception. Extend private terminal matching to the complete surviving public commitment and reduced immutable-parent/attachment equivalence, including deletion author and null-duration guards. Add no schema or new validator.
3. Generalize the existing incoming local-path transaction for the exact private claimed row while preserving ordinary behavior. Prove attachment/v111 atomicity, relay versus LAN state, idempotence, and rollback before changing the application flow. Pin the strict committed/ACK-pending/expiry/terminal/legacy decision table so no fingerprinted private row can enter generic download.
4. In `downloadMedia`, perform read-only path preflight before claim; claim and reload/requalify under the incumbent exact-ID lease; return the exact `downloading` row/token and release that lease before invoking the strict owner's existing exclusive lifecycle section. Route every transient noncommitted outcome through the failure/recovery CAS. In the strict owner, reversibly copy private LAN work into the deterministic authorized pair, reject any other decrypt result path, and delete the legacy source only after durable commit. Narrow existing interrupted-download recovery to preserve that legacy retry source for a recoverable strict incoming transfer while keeping terminal cleanup destructive.
5. Route strict-private terminal replay ahead of generic duplicate handling, build the fresh wire-derived candidate, classify exact private terminal state before generic tombstone fallback, and map every selected private supersession to the dedicated handler/listener result. A final transactional reread decides an active-duplicate/deletion race; a removed parent fails closed with no receipt.
6. Reuse the incumbent repository-wide exclusive private lifecycle lease across the selected existing-row decision, private stage, terminal re-read, guarded thumbnail, exact message-marker stage/retirement, repository publication, and marker ready promotion. Broaden private publication and all production notification eligibility paths to every exact terminal state. Keep network/contact/receipt outside, forbid exact-ID-to-exclusive upgrade, and preserve ordinary duplicate behavior.
7. Replace the copied no-auto-download predicate test with a call through the exact production policy. Extract at most one small pure predicate in an existing file if necessary; do not add a framework or production file. Treat the new predicate test as GREEN-only; obtain the fourth causal RED from terminal presentation/identity behavior.
8. Run the four mutation re-reds, the focused `TC-355-` batch, exact preservation sentinels, affected gates, analyzer/format/diff, and one incremental Graphify refresh. Update Plan 354/index/coverage honestly as superseded by the implemented Plan-355 repair only after GREEN; do not activate or claim GAP-N01 closure.

## Risk And Reversibility

| Risk | Detection | Reversible response |
|---|---|---|
| Private commit accidentally widens ordinary/disappearing acceptance | TC-355-01 matrix + TC-347-06b + selector-off sentinels | Revert exact policy branch; no schema/data rollback |
| Exclusive lifecycle span deadlocks through nested repository acquisition or detached callback | TC-355-04 completer barriers and bounded focused timeout | Stop for re-review. Do not shorten the span unless an equivalent terminal requalification plus exact marker-retirement proof is added; do not invent another lock |
| Terminal replay still enters generic duplicate or sends receipt after parent removal | TC-355-03 production handler/listener journeys | Revert narrow routing change; v111 remains durable/default-off |
| Path normalization deletes or renames unrelated files, or consumes the only LAN retry source before commit | TC-355-02 unsafe-symlink/arbitrary-path/source-and-sibling inventory | Revert private normalization; no persisted schema change |
| Pure production policy extraction becomes a framework | Diff review and TC-355-04d | Inline one shared function in an existing owner; reject class/file hierarchy |
| Mixed-version behavior changes while selector is off | exact proof-less/selector-off sentinels | Revert adopter-only branch; admissions remain off |

Rollback requires no migration or external rollout: all selectors/admissions remain default-off and DB stays v111. Runtime deletion is deliberately limited to failed-attempt-owned staging bytes, the legacy LAN source only after durable commit or exact terminal-cleanup authority, exact terminal **message** display markers, and the incumbent terminal owner's already-authorized canonical/private/LAN/thumbnail/key cleanup. Those successful/terminal deletions are valid and need not be restored after a code rollback. Reverting Plan 355 otherwise restores the audited Plan-354 behavior without data conversion.

## Gate Cadence

- Inner loop: one exact `--plain-name` command for the active TC-355 row only.
- Final focused proof: one `--plain-name 'TC-355-'` batch over existing changed test paths; do not rerun whole files afterward.
- Preservation: exact named sentinels only, plus the strict media custody source-owner shell.
- Curated regression: host-only `1to1` once. Do not use the non-host wrapper because it adds unchanged Go/relay tails.
- Families: dart-only `core-host-all` at concurrency 2 because shared core policy/DB/display helpers change; serial dart-only `feature-host-all` because handler/repository/download/bootstrap surfaces change.
- No completeness check unless implementation creates or moves a test path; this plan expects none.
- Hygiene: one full analyzer, exact changed-Dart format check, `git diff --check`, then one incremental Graphify refresh after coherent changes.
- Wave/final only: no full `host-all` here.

## Acceptance Gates

Expected first REDs:

```bash
flutter test --concurrency=1 \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/core/database/helpers/media_attachments_db_helpers_test.dart \
  test/features/conversation/application/download_media_use_case_test.dart \
  --plain-name 'TC-355-01'

flutter test --concurrency=1 \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/features/conversation/application/download_media_use_case_test.dart \
  test/features/conversation/integration/private_media_restart_replay_test.dart \
  --plain-name 'TC-355-02'

flutter test --concurrency=1 \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/core/database/helpers/media_attachments_db_helpers_test.dart \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  test/features/conversation/application/chat_message_listener_test.dart \
  --plain-name 'TC-355-03'

flutter test --concurrency=1 \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/core/database/migrations/107_direct_notification_durability_test.dart \
  test/features/conversation/domain/models/private_media_policy_test.dart \
  test/features/conversation/application/receive_protected_photo_thumbnail_test.dart \
  test/features/conversation/domain/repositories/message_repository_impl_test.dart \
  --plain-name 'TC-355-04'
```

`TC-355-04d` and TC-355-04e are deliberately absent from the first-RED command. Add 04d only after the tiny production predicate has been extracted and prove it invokes that same callable predicate; run 04e only as the later wiring/canonical-policy sentinel. The other TC-355-04 rows supply the causal RED for the bundle.

Focused GREEN after all changes:

```bash
flutter test --concurrency=1 \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/features/conversation/domain/models/private_media_policy_test.dart \
  test/core/database/helpers/media_attachments_db_helpers_test.dart \
  test/features/conversation/application/download_media_use_case_test.dart \
  test/features/conversation/integration/private_media_restart_replay_test.dart \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  test/features/conversation/application/chat_message_listener_test.dart \
  test/features/conversation/application/receive_protected_photo_thumbnail_test.dart \
  test/features/conversation/domain/repositories/message_repository_impl_test.dart \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  test/core/database/migrations/107_direct_notification_durability_test.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  --plain-name 'TC-355-'
```

Exact preservation sentinels:

```bash
flutter test test/features/conversation/application/download_media_use_case_test.dart \
  --plain-name 'TC-347-06b strict download commits before same-source ACK'
flutter test test/core/database/migrations/107_direct_notification_durability_test.dart \
  --plain-name 'TC-351-04 tombstone and direct message display marker cannot coexist'
flutter test test/core/database/helpers/media_attachments_db_helpers_test.dart \
  --plain-name 'TC-354-04a private strict receive is all-or-none'
flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  --plain-name 'TC-354-04b private strict receive key CAS is exact'
flutter test test/features/conversation/application/chat_message_listener_test.dart \
  --plain-name 'TC-354-04e terminal private supersession never retries message display'
flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  --plain-name 'TC-354-01c protected and view-once publish blob custody before first network'
flutter test test/features/conversation/application/download_media_use_case_test.dart \
  --plain-name 'explicit available private parent reaches canonical durable storage'
flutter test test/features/conversation/application/download_media_use_case_test.dart \
  --plain-name 'private download losing to expiry cannot commit or retain promoted bytes'
flutter test --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  --plain-name 'TC-347-06a strict blob commitment publishes only after atomic stage and legacy remains compatible'
flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  --plain-name 'private receive durably saves policy and available state before attachment work'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'failed private upload restores the exact selected policy'
bash scripts/test/relay_media_custody_contract_test.sh
```

Affected regression/hygiene:

```bash
./scripts/run_host_test_gates.sh 1to1
./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 2 --dart-only
./scripts/run_host_test_gates.sh feature-host-all --batch-flutter --concurrency 1 --dart-only
flutter analyze
changed_dart_files="$(git diff --name-only --diff-filter=ACMR -- '*.dart')"
test -z "$changed_dart_files" || dart format --output=none --set-exit-if-changed $changed_dart_files
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
```

Explicitly NOT RUN per plan:

- `./scripts/run_test_gates.sh 1to1`, full `host-all`, completeness without a path/registration change, whole-file duplicate runs after focused GREEN, groups/feed/posts/performance/baseline gates.
- Go relay/node/bridge/process suites, gomobile bindings, migration/account-transfer/SQLCipher/device campaigns, Android/iOS harnesses, production deployment, admission activation, or mixed-version rollout.

## Done Criteria

- [ ] Real private explicit relay/LAN download commits canonical `done` and the correct v111 state atomically before ACK; ACK-pending without durable local bytes retains custody, fingerprinted strict rows never use legacy transport, and expiry/terminal outcomes remain owned by their existing transitions. -> TC-355-01.
- [ ] Private path authorization, reversible deterministic staging, arbitrary decrypt-path refusal, failure CAS, and crash recovery preserve the only LAN retry source and leave no unowned attempt bytes or stuck `downloading` row. -> TC-355-02.
- [ ] Every exact terminal replay reaches the dedicated private owner, compares complete surviving authority and reduced no-v111 parent identity, emits only the authorized receipt, and never triggers generic display retry; removed/crossed parent remains unacknowledged. -> TC-355-03.
- [ ] Stage/presentation and private terminal lifecycle converge under the incumbent repository-wide exclusive lease with no stale message marker/thumbnail/stream/canonical notification candidate; reaction/other-message markers survive, media identity is coherent, and the production no-auto policy is behaviorally proved. -> TC-355-04.
- [ ] Four representative mutation re-reds are recorded and reverted; focused/preservation/curated/core/feature/analyzer/format/diff/Graphify receipts are current.
- [ ] Plan 354 and its index/coverage claims are reconciled as post-review-incomplete until this plan executes; after execution they may say superseded/closed by Plan 355, never erase the historical receipts.
- [ ] No schema, new durable owner, modality expansion, activation, device/iOS, per-plan full host-all, GAP-N01 closure, or release claim is made.

## Handoff

- First causal REDs: the four exact commands above on baseline `6f66a8098`.
- Manual registration: none; every test extends an existing AUTO/curated path. Run completeness only if that assumption changes.
- Migration: none; DB remains v111 and physical v108/v111 layouts remain byte-compatible.
- Rollout: all existing client/relay admissions remain default-off.
- Boundary closure: host Dart + real SQLite/filesystem only.
- Deferred next N01 work: after Plan 355 executes and a post-execution audit passes, reassess disappearing direct media versus private mutation custody. Do not plan those while this owner is incorrect.
- Implementation session must update this plan, `Test-Flight-Improv/00-INDEX.md`, the GAP-N01 coverage document, and append `- Plan 355 — EXECUTION_COMPLETED` only after every required receipt passes.

## Reviewer Findings

Fresh `$tdd-review` independently audited download/storage, receiver/presentation, and literal gate/economy boundaries. All reviewers confirmed the core bet: repair the existing Plan-354 Protected/View-Once initial adopter in one bounded plan over physical v111, the existing strict download owner, private transfer claim, repository-wide lifecycle lease, terminal parent, and direct display outbox. No schema, new queue/owner/lock/network path, protocol/native work, or device campaign is needed.

The first pass returned `PLAN-FIXES-REQUIRED`. It found executable counterexamples hidden by Plan 354's source-order tests: stale post-claim local-path CAS; strict rows falling into legacy transport; ACK-pending custody retirement without exact local bytes; destructive LAN normalization/recovery; terminal replay intercepted by generic duplicate; removed-parent receipt; post-stage thumbnail/marker/publication races; terminal notification eligibility and marker retention; weak no-v111 identity; crossed MIME/media type; and a copied rather than invoked production drain predicate. It also found a missing test path and first-RED/wiring sentinel ambiguity.

The amended plan closes each issue with existing-owner behavior and causal tests. Retryable failures preserve the LAN source while exact terminal cleanup remains destructive; the strict state table cannot fall through; the final private DB commit consumes the reloaded `downloading` row; terminal replay compares all surviving authority; the selected receive sequence holds the incumbent exclusive lifecycle lease; actual stage/consume/hide owners retire only exact message markers; production keep/replacement/display paths reject terminal private media; and GREEN-only production-policy/wiring sentinels are not misrepresented as RED proof. All literal paths/names and gate flags resolve. Final targeted verdicts are **READY** from all three reviewers, with no remaining required delta.

## Arbiter Decision

**READY / EXECUTION_READY. Core bet confirmed.** Plan 355 is the smallest coherent next action because it repairs demonstrated Plan-354 closure defects without adopting a new modality. Four behavioral bundles and four representative mutation re-reds are sufficient. The exact focused/preservation/host `1to1`/affected dart-only core+feature cadence is proportional; completeness, non-host Go tails, full `host-all`, device/iOS, migration/SQLCipher, relay/native/bindings, performance, activation, and release work must not be added absent an implementation-driven scope change.

Disposition: execute in a separate session from clean baseline `6f66a8098`. Stop and re-review if implementation requires a schema change, new durable authority, second strict network owner, new lock, scanner/journal, broad notification framework, or platform work. Plan 354 remains post-execution-review incomplete until every Plan-355 receipt passes.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-10 | planning | Plan 355 draft | `$tdd-plan` source/Graphify/test/gate reconnaissance | Four behavior bundles over existing owners; no schema/new infrastructure | independent review pending | run `$tdd-review`; do not implement |
| 2026-08-10 | review | Plan 355, current source, literal test/gate paths | three independent `$tdd-review` passes plus targeted re-reviews: READY | All required download, terminal, lifecycle, notification, identity, recovery, and gate deltas incorporated; no overengineering blocker | none | execute separately; append completion only after all receipts pass |
