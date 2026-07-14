# Plan 234 — 1:1 Private Media Lifecycle Session Breakdown

Status: accepted

## Decomposition Progress

- 2026-07-11 — Evidence Collector: Graphify planning query anchored on `MediaAttachment`, `MediaOwnerLane`, `ReceivedMediaActionController`, and `MediaLibraryRepository`; verified the current v99 migration spine, encrypted direct codec, receive/listener ordering, auto-download, notification preview, action/library seams, native platform files, tests, gates, and live device matrix. Next action: map the unresolved evidence ledger to a truthful local-only closure.
- 2026-07-11 — Closure Mapper: resolved D-234-01..08 to the conservative contract below: one private image/video per message; mutually exclusive modes; device-local lifecycle; no relay/Go authority claim; generic notifications; no auto-download or egress; fail-closed unknown policy; route-scoped Android prevention and truthful iOS detection/obscuring. Next action: isolate migration, ingestion, lifecycle, capability, native, and acceptance seams.
- 2026-07-11 — Session Splitter: produced six doc-scoped sessions. Reserved DB v100 exclusively for Plan 234 and recorded Plan 238's sequential v101 reservation; no other Plan-234 session may add a migration. Next action: counterexample review the boundaries, tests, and gate cadence.
- 2026-07-11 — Reviewer: six sessions are the minimum safe split. The initial lifecycle/action bundle was too broad, so atomic reveal/expiry/recovery and cross-surface capability enforcement remain separate. No missing regression family, acceptance pass, or closure owner remains. Next action: arbitrate blockers and accepted differences.
- 2026-07-11 — Arbiter: no structural blocker. The local-only product promise safely removes Go/relay protocol work; unavailable hardware is N/A by project policy; Plan 243 retains actual PiP implementation/proof while Plan 234 supplies a fail-closed eligibility decision. The breakdown is reusable by the downstream session pipeline.

## Recommended Plan Count

Create **6** session plans.

## Decomposition Artifact

- Artifact: `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-breakdown.md`
- Source: `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan.md`
- Detailed planning happens one session at a time.
- Every later session must be refreshed against landed code, the current migration registry, the current named-gate inventories, and the live device matrix before execution.
- Sessions execute strictly in ledger order. A later session must not pre-land production code owned by an earlier session.

## Run Mode Snapshot

- Active mode: `implementation-committed gap-closure`.
- Degraded local continuation: not authorized; fresh planner, execution/QA, closure, and final-acceptance contexts remain mandatory.
- Source proposal / closure doc: `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan.md`.
- Source status vocabulary: `accepted` is now the controlling Plan-234 state;
  older `evidence-gated` and unresolved D-234 wording is historical only.
- Overall closure bar: the `Overall Closure Bar` below, including v100, direct-chat behavior, truthful platform boundaries, curated `1to1`, and synchronized closure docs.
- Final verdict policy: `closed` only after all six sessions are accepted, D-234-01..08 are persisted as resolved, every Plan-234 done criterion is evidenced, and no row-owned gap remains. Otherwise use `still_open`; do not mask an owned gap with follow-up or residual wording.

## Controller Progress

- 2026-07-12 — Session 06 / closure accepted: causal
  criteria `84/84`, final Android-pair artifact `854235…6233`, focused/native/
  device/static evidence green, host inventory `90`, and protected manifests
  byte-identical at `9fa736…8a13` (`2,069,571` bytes; `cmp=0`). Independent QA
  accepted after `fix_passes=2`. The external `1to1` success is user-attested
  without an available count/log and no `run_test_gates.sh` command was rerun
  under the user's explicit direction. No production delta or Session-06
  Graphify refresh is attributable. The separate Closure Reviewer accepted
  with zero findings after the current protected closure pair matched at
  `907c422…36562` (`2,072,461` bytes; `cmp=0`). Plan 234 is closed and Plan 238
  is unblocked at sequential DB v101.
- 2026-07-12 04:58 CEST — Session 03 / bounded post-closure proof repair accepted: repeated Plan-247 aggregate failures concretely reproduced a watchdog/fixture ordering race. A polling candidate was independently rejected; the deterministic optional late-scrub-delay seam preserves every production default. Exact 10/10, download+cleanup 83/83, 1to1 1,963/1,963, groups 1,951/1,951 plus Go, inventory 88, completeness 1,179/1,179, static checks, Graphify affected, and fresh independent QA are green at `post_closure_fix_passes=2`. Exactly one additional post-QA incremental refresh passed. Session 03 remains accepted/closed; Plan 247 Session 04 restarts from a fresh baseline.
- 2026-07-11 — Session 05 / closure accepted: separate read-only Closure Reviewer returned `ACCEPTED` with all 21 criteria reconciled, no unresolved finding, and truthful 21-delta-plus-one-dependency Graphify attribution. Session 05 is closed. Only Plan 247 Session 03 is released; Plan 234 Session 06 is dependency-satisfied but controller-serialized behind Plan 247 Sessions 03-04. Overall Plan 234 remains `still_open`.
- 2026-07-11 21:20 CEST — Session 05 / QA accepted, closure review pending: all final focused/native/device/named/static/scope gates are green; final independent QA accepted B1-B10 after the honest `fix_passes=3`; and exactly one post-QA incremental Graphify refresh passed. The third causally bounded pass is an explicit recorded exception to the original two-pass forecast. Session 05 is not released until a separate Closure Reviewer accepts the synchronized plan/source/breakdown. Sessions 01-04 remain closed; overall Plan 234 remains `still_open`.
- 2026-07-11 17:55 CEST — Session 04 / closure writing complete; Session 05 next: Session 04 is accepted/closed after causal RED/GREEN, initial-QA `B1`, `fix_passes=1`, final QA acceptance, every exact gate, and exactly one post-QA incremental Graphify refresh. Session 05 alone is now runnable; Session 06 remains prerequisite-blocked. Sessions 01-03 remain closed absent concrete regression evidence; overall Plan 234 remains `still_open`.
- 2026-07-11 16:21 CEST — Session 03 / closure complete; Session 04 / plan preparation: Session 03 is accepted/closed with final QA, resolved `B1`, all exact gates, and synchronized source/ledger docs. Ledger sanity passes; Session 04 is the sole runnable session. Next: fresh doc-scoped Session-04 planner; Sessions 01-03 remain closed absent regression evidence.
- 2026-07-11 15:30 CEST — Session 03 / execution resume: reused the existing execution-ready plan, reconciled Sessions 01-02 as accepted, confirmed the prior writer blocker remains resolved, recorded fresh scoped baseline aggregate `f09c1e73e0afeb24aafb88891d20937b84fae0f42018bbe37ba8d6bb157980fa`, and obtained anchored Graphify context. Next: fresh Session-03 Execution+QA from the fully materialized baseline; no degraded local continuation.
- 2026-07-11 — Session 01 / closure complete: typed policy, encrypted-inner codec, direct-parent v100 durability, Android/iOS SQLCipher proof, and the curated 1:1 gate are accepted. Next: prepare Session 02 against landed v100 without reopening Session 01 absent a real regression.
- 2026-07-11 — Session 01 / plan preparation: run mode and v100 ownership locked; waiting for the fresh doc-scoped planner. Next: persist the accepted decisions in the source plan and produce the execution-safe Session-01 plan.

## Closure Progress

- 2026-07-12 — Session 06 / Closure Reviewer: returned `ACCEPTED` with zero
  blocking and zero nonblocking findings. The earlier valid execution pair
  `9fa736…8a13` remains evidence; the current closure pair
  `907c422…36562` is byte-identical at `2,072,461` bytes / `cmp=0`.
  Intermediate closure2/3/4 movement came from unrelated Plan-256/257 writers
  and is neither a Session-06 fix pass nor a regression. The stable Closure
  Audit is persisted; Plan 234 is closed with no residual/blocker/follow-up.
- 2026-07-12 — Session 06 / Closure Writer: synchronized the accepted execution
  evidence, bounded device-local interpretation, gate exception, exact artifact
  and manifest hashes, `fix_passes=2`, DB v100/v101 ownership, and final Plan-234
  verdict across the session plan, source, breakdown, index, and stable closure
  reference. Tentative classification: `accepted-awaiting-closure-review`; no
  Plan-234-owned residual, blocker, or follow-up. Next action: separate read-only
  Closure Reviewer, then only the stable `## Closure Audit` record.
- 2026-07-12 04:58 CEST — Session 03 / post-closure repair QA, refresh, and closure review: independent QA `ACCEPTED` deterministic watchdog/scrub ordering and production-default equivalence with no blocker. Honest `post_closure_fix_passes=2` records the rejected polling candidate and final seam; original historical `fix_passes=1` is unchanged. Exactly one additional post-QA incremental refresh completed at 48,201 nodes / 74,809 edges with overlay 1,272 files / 12,419 tests / 959 targets. A separate read-only Closure Reviewer then accepted all synchronized records with no documentation blocker. No product, schema, transport, native/device, or later-session behavior changed; Session 03 is closed again.
- 2026-07-11 — Session 05 / Closure Reviewer: independently verified the synchronized Session-05 plan, this breakdown, source ledger, current code/tests/gates, native artifacts, graph timestamps, reconstructed metadata attribution, and dependency transition. Verdict `closed` / documentation `accepted`; no blocking or nonblocking finding, residual, follow-up, overclaim, or prior-session regression. All 21 criteria, final counts, honest `fix_passes=3` exception, 21 attributable deltas plus one unchanged preservation dependency, and exactly one refresh reconcile. Only Plan 247 Session 03 is released.
- 2026-07-11 21:22 CEST — Session 05 / Closure Writer: persisted the accepted QA chronology, exact final counts, Graphify reconciliation over 21 attributable production deltas plus the unchanged `media_viewer_item.dart` preservation dependency, one post-QA incremental refresh, reconstructed `info.plist` attribution, and the explicit third-pass exception in the Session-05 plan, this breakdown, and the source execution ledger. Tentative classification: `qa-accepted-awaiting-closure-review`. Session 06 remains controller-blocked; Plan 247 Session 03 is not released until a separate read-only reviewer accepts these synchronized records.
- 2026-07-11 18:01 CEST — Session 04 / Closure Reviewer: independently verified the updated Session-04 plan, breakdown, and source plan against current production/test seams and the persisted execution/QA/gate/refresh evidence. The review corrected two documentation blockers—stale top metadata that still called Session 04 runnable and stale v99/tentative-v100 migration wording—then accepted the synchronized closure. Final verdict: `closed` / documentation `accepted`; no remaining blocking or non-blocking finding, residual, follow-up, overclaim, or dependency error. All 11 criteria, B1 chronology, exact counts, TC-234-06/08/13/14 evidence, exactly-one refresh, and landed v100 / sequential Plan-238 v101 truth reconcile. Session 05 alone is `pending`; Session 06 waits only on Session 05; overall Plan 234 remains `still_open`. Docs updated after review: this final Closure Progress verdict only.
- 2026-07-11 17:55 CEST — Session 04 / Closure Writer complete: set the Session-04 plan to `accepted`, checked all 11 session-owned done criteria, added its stable `closed` Closure Audit, and synchronized this breakdown plus the source execution ledger. The closure records the initial-QA version-1-ordinary `B1`, causal 2-RED/16-GREEN disposition, final focused counts, curated `1to1` 1,901/1,901, host inventory 80, completeness 1,166/1,166, final QA acceptance after `fix_passes=1`, exactly one post-QA Graphify refresh, and no owned code/test newer than refresh. Residuals/blockers/follow-ups: none. Session 05 alone is now `pending`; Session 06 remains prerequisite-blocked; overall Plan 234 remains `still_open`. Next action: a separate Closure Reviewer checks the three synchronized docs for evidence fidelity, overclaim, and dependency correctness without entering Session 05.
- 2026-07-11 17:54 CEST — Session 04 / Completion Auditor: reconciled the accepted `## Execution Result`, final independent-QA disposition, current code/tests/gates, all 11 done criteria, source-plan status, and dependency ledger. Classification: Session 04 `closed`; no residual, blocker, or follow-up. Exact evidence is policy 8, boundary 8, action 4, Forward 3, batch/library 8, SQL/repository 41, download 68, presentation/Forward 13, Shared Media/viewer 12, typed viewer 4, curated `1to1` 1,901/1,901, host inventory 80, completeness 1,166/1,166, green static/scope gates, final QA accepted after `fix_passes=1`, and one post-QA refresh. Overall Plan 234 remains `still_open` for Sessions 05-06. Next action: closure writing only; unblock only Session 05.
- 2026-07-11 16:23 CEST — Session 03 / Closure Reviewer: independently verified the updated Session-03 plan, breakdown, and source/closure plan against the persisted fix/QA/evidence artifacts. Verdict: `closed` / documentation `accepted`; no blocking or non-blocking finding, no residual or follow-up, no overclaim, and no Sessions-01/02 reopening. All 12 session criteria are truthful; `B1`, exact counts, final QA, and the single post-QA refresh match disk. Session 03 is `accepted`; Session 04 alone is `pending`; Sessions 05-06 remain prerequisite-blocked; overall Plan 234 remains `still_open`. Docs updated by review: this final Closure Progress verdict only. Requested GPT-5.5/xhigh controls were unavailable to the spawn API, so the inherited runtime was used and is not acceptance evidence. Next action: return the stable Session-03 closure handoff; any future work starts with Session 04 and reopens Session 03 only on a real lifecycle regression.
- 2026-07-11 16:20 CEST — Session 03 / Closure Reviewer initialization: docs inspected for review are the updated Session-03 plan, breakdown ledger/progress, and source/closure plan; docs updated so far in this phase: this reviewer checkpoint only. Tentative verdict: `closed`. Next action: independently compare the written closure against the reconciled execution artifacts, verify all 12 session criteria without overclaim, confirm Plan 234 remains open, and confirm only Session 04 is unblocked before persisting the final reviewer verdict.
- 2026-07-11 16:19 CEST — Session 03 / Closure Writer complete: set the Session-03 plan to `accepted`, checked all 12 session-owned done criteria, added its stable `closed` Closure Audit, and synchronized this breakdown plus the source execution ledger. The closure records the resolved `B1`, exact green evidence, curated `1to1` 1,875/1,875, host inventory 78, completeness 1,164/1,164, final QA acceptance after `fix_passes=1`, exactly one post-QA Graphify refresh, and no owned source/test newer than the refresh. Residuals/blockers/follow-ups: none. Session 04 alone is now `pending`; Sessions 05-06 remain prerequisite-blocked; overall Plan 234 remains `still_open`. Next action: a separate Closure Reviewer checks the three synchronized docs for evidence fidelity, overclaim, and dependency correctness without entering Session 04.
- 2026-07-11 16:16 CEST — Session 03 / Closure Writer initialization: Completion Auditor reconciled the unchanged on-disk lifecycle SQL/tests and persisted artifacts; docs inspected: Session-03 plan, breakdown, and source/closure plan; docs updated so far: the breakdown's current-session progress records only. Tentative verdict: `closed`. Next action: check all Session-03 done criteria, persist its stable closure record, synchronize the source and breakdown ledgers, and make only Session 04 pending while Sessions 05-06 remain prerequisite-blocked.
- 2026-07-11 16:16 CEST — Session 03 / Completion Auditor: verified the `B1` correction (`MAX(stored, now)` and expiry only at `high_water >= expires_at`) against its causal RED and 14/14 GREEN, scheduler 11/11, download 66/66, restart 2/2, all remaining named direct/sentinel results, curated `1to1` 1,875/1,875, host inventory 78 with all six Session-03 suites, completeness 1,164/1,164, green formatter/analyzer/diff/scope evidence, accepted final QA after `fix_passes=1`, and exactly one post-QA Graphify refresh. No owned code/test file is newer than that refresh. Classification: Session 03 `closed`; no residual, blocker, or follow-up. Overall Plan 234 remains `still_open` for Sessions 04-06. Next action: closure writing only; do not rerun evidence or enter later-session plans.
- 2026-07-11 16:13 CEST — Session 03 / Completion Auditor initialization: inspected the persisted accepted `## Execution Result`, final independent-QA disposition, current Session-03 done criteria, breakdown ledger/dependency contract, and source-plan execution status; updated this current-session checkpoint before long audit/write/review work. Docs inspected: the Session-03 plan, session breakdown, and source/closure plan; docs updated so far: this breakdown checkpoint only. Tentative verdict: `closed`, pending bounded on-disk evidence reconciliation and a separate closure review. Next action: audit only Session-03 attributable artifacts and exact persisted evidence, then synchronize only Session 03 and unblock only Session 04 if the evidence remains truthful.
- 2026-07-11 — Session 02 / Closure Reviewer: verified the stable closure audit against the landed production/test artifacts and persisted execution evidence, including `fix_passes=1`, final curated `1to1` 1,810/1,810, host inventory 72, green analyzer/diff/scope guards, accepted post-fix QA, and exactly one Graphify refresh. Verdict: `closed`; no residual Session-02 item, no whole-Plan-234 acceptance, no Session-03 artifact or scope entry, and no dependency transition beyond Session 03. Session 02 ledger status is `accepted`; Session 03 alone is now `pending`.
- 2026-07-11 — Session 02 / Closure Writer: reconciled the on-disk production/test artifacts with the accepted execution and post-fix QA evidence; changed the Session-02 plan, breakdown ledger, and source execution ledger to the stable accepted state; changed only the satisfied dependency needed to make Session 03 runnable. Tentative verdict: `closed`. Next action: review the closure text for scope overclaim, evidence fidelity, and dependency correctness without entering Session 03.
- 2026-07-11 — Session 02 / Completion Auditor initialization: inspected the persisted accepted Execution Result, checked Done Criteria, QA fix-pass history, final curated `1to1`/host-inventory/analyzer/diff/scope evidence, and the program-level dependency contract; updated this current-session progress record before changing any verdict or ledger state. Tentative verdict: `closed`, pending bounded reconciliation of the on-disk Session-02 artifacts and an independent closure review. Next action: write only Session-02 closure synchronization, then review it for overclaim and dependency correctness before unblocking Session 03.
- 2026-07-11 — Session 01 / Closure Writer: synchronized the accepted execution verdict into the session plan, source execution ledger, and breakdown ledger; changed only dependency state needed to make Session 02 runnable. Tentative verdict: `closed`. Next action: perform the closure overclaim/dependency review.
- 2026-07-11 — Session 01 / Closure Reviewer: verified the accepted execution evidence, v100 ownership, B1/B2 dispositions, Android/iOS SQLCipher proof, curated `1to1` result, and program-level status. Verdict: `closed`; no residual Session-01 item, no premature whole-program acceptance, and no later-session scope was claimed. Session 01 ledger status is `accepted`.
- 2026-07-11 — Session 01 / Completion Auditor initialization: inspected the persisted Session-01 `Final Execution Verdict`, the breakdown closure/ledger contract, and the source plan's still-program-level status; updated this current-session progress record. Tentative verdict: `accepted`, pending bounded on-disk reconciliation of attributable artifacts, exact evidence, and dependency state. Next action: complete the audit, write only Session-01 closure synchronization, then run a separate closure review before unblocking Session 02.

## Overall Closure Bar

Plan 234 is closed only when a direct-chat sender can deliberately send one eligible encrypted image/video as Protected, View Once, or Disappearing; the receiver durably stores the policy before preview/download decisions; private bytes stay app-owned and manually downloaded; notifications disclose only `Private media`; every export, Forward, bookmark, Shared Media, and PiP path fails closed; view-once and expiry transitions survive retry/restart without resurrection; Android and iOS behavior matches truthful platform copy; ordinary/legacy direct media remains unchanged; v100 passes complete-chain SQLCipher proof; the curated `1to1` gate is green; and the source plan, index, gate docs, and 1:1 closure reference record an accepted verdict.

This closure deliberately promises **device-local privacy state**, not account-wide consumption, relay revocation, screenshot-proof iOS behavior, or revocation of a copy captured outside the app.

## Source Of Truth

The split is governed by:

- Product intent and original obligations: `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan.md`.
- Regression cadence: `Test-Flight-Improv/14-regression-test-strategy.md:8-29`, `:57-70`, and `:106-132`.
- Named-gate and availability policy: `Test-Flight-Improv/test-gate-definitions.md:1-18`, `:121-131`, and `:180-220`; executable arrays in `scripts/run_test_gates.sh:21-205` and `scripts/run_host_test_gates.sh:14-120` win on disagreement.
- Stable closure reference: `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`.
- Migration truth: `lib/core/database/app_database_version.dart:1-13`, `lib/core/database/production_migration_registry.dart:218-221`, `:328-331`, and `test/core/database/migrations/099_group_messages_is_forwarded_test.dart:96-337`.
- Direct encrypted policy carrier: `lib/features/conversation/domain/models/message_payload.dart:15-42`, `:160-244`; send construction at `lib/features/conversation/application/send_chat_message_use_case.dart:397-494`.
- Direct durable parent/owner truth: `lib/features/conversation/domain/models/conversation_message.dart:7-155`; `lib/core/media/media_owner_lane.dart:1-58`; attachment-local state at `lib/features/conversation/domain/models/media_attachment.dart:19-104`, `:142-278`.
- Receive ordering and replay seams: `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart:304-364`, `:495-597`, `:757-813`.
- Notification and automatic-download seams: `lib/features/conversation/application/chat_message_listener.dart:190-275`, `:574-665`; `lib/features/push/application/show_notification_use_case.dart:17-40`; `lib/features/push/application/push_decrypt_preview.dart:46-100`, `:179-207`.
- Existing fail-closed action/viewer/library seams: `lib/features/conversation/application/received_media_action_controller.dart:16-89`, `:197-287`; `lib/features/conversation/domain/repositories/media_attachment_repository.dart:145-241`; `lib/shared/widgets/media/media_viewer_item.dart:25-171`; `lib/shared/widgets/media/full_screen_typed_media_viewer.dart:22-188`.
- Native baseline: current Android/iOS trees contain received-media egress but no `FLAG_SECURE`, capture observer, app-switcher privacy cover, or PiP owner. This was verified by targeted search under `android/app/src`, `ios/Runner`, `lib`, `test`, and `integration_test` on 2026-07-11.

## Resolved Decision Ledger

These decisions replace the source draft's D-234-01..08 execution block. The first downstream planner must copy them into the refreshed source plan before authoring RED tests.

| Decision | Accepted contract | Consequence |
|---|---|---|
| D-234-01 modes and eligibility | Version 1 has four mutually exclusive modes: `ordinary`, `protected`, `view_once`, and `disappearing`. A private mode is allowed only on a new ordinary send containing exactly one image/GIF or video, no audio/file, no second attachment, no non-empty caption/text, no edit, and no Forward-derived payload. `protected`, `view_once`, and `disappearing` are all egress-protected. Disappearing offers only `1 hour`, `1 day`, or `7 days`. | No combination matrix, hidden modifier, mixed batch, stale composer selection, or private re-forward exists. Ordinary remains the missing-policy default. |
| D-234-02 clock | A disappearing duration starts when the recipient durably commits the message on that device. The receiver persists `receivedAt`, `expiresAt`, and a clock high-water mark. `now >= expiresAt` expires with no grace. A forward wall-clock jump may expire early; a backward jump never resurrects or extends because evaluation uses `max(now, persistedHighWater)`. Resume/cold-start sweeps are idempotent. | Copy says `Expires on this device … after delivery`; it does not imply sender-synchronized or account time. Protected and View Once have no timer. |
| D-234-03 consume and convergence | Consumption is device/install-local. View Once uses a durable `available -> opening -> viewing -> consumed` state machine. A CAS to `opening` occurs before byte exposure; only that in-process lease may revert to `available` after a proven pre-first-frame decode failure. First rendered frame records `viewing/revealedAt`; route exit, backgrounding, capture handling, or explicit close terminalizes and cleans up. Restart with `opening` or `viewing` terminalizes fail closed. Duplicate/retry can never downgrade or reopen a terminal row. No consume receipt is sent. | Two installed devices may each view once. Product copy must say this. No account-wide or globally-single-use claim is made. |
| D-234-04 platform truth | While any private route is visible, Android applies route-scoped `FLAG_SECURE` and removes it on every exit/error; this prevents standard screenshot/screen-recording/recents capture while active. iOS does not claim screenshot prevention: it observes capture/screenshot signals, covers app-switcher snapshots, pauses/covers private bytes during active capture, and warns/dismisses truthfully. All private modes are PiP-ineligible. No platform claim covers photographing another screen. | Android prevention and iOS detection/obscuring are tested separately. Plan 243 owns actual native PiP implementation and cross-platform PiP proof; Plan 234 owns only the mandatory denial input. |
| D-234-05 relay and copies | No Go/libp2p/relay change. Private downloads use the existing encrypted media transport and existing post-commit relay delete behavior. The app never promises relay revocation, sender revocation, cross-device consumption, or recovery after uninstall. Local terminal state blocks re-download. Copies made with another device/camera or before this feature cannot be revoked. | TC-234-12's relay-authoritative branch is N/A. The two-Android proof demonstrates the narrower send/receive and device-local truth, not a server consume authority. |
| D-234-06 notifications | Foreground local and decrypted push previews use the literal localized meaning `Private media`; sender/conversation identity may remain. Caption, thumbnail, media kind, mode, duration, expiry, keys, paths, and state never enter notification text/payload/diagnostics. Policy is committed before preview and download decisions. | Ordinary previews stay caption/type based. A private message never races through ordinary preview. |
| D-234-07 codec and legacy | Private policy is a versioned `privateMedia` object carried only in the encrypted v2 inner JSON: version, mode, and duration when disappearing. It is never emitted in the clear v2 envelope, v1 plaintext writer, owner lane, relay metadata, or logs. Missing object means ordinary. Unknown version/mode, invalid duration, malformed combination, or private policy on an ineligible media shape persists as local `unsupported`, stays redacted, cannot download/open/export/forward/bookmark/PiP, and remains deletable. Unknown additive fields inside a known valid v1 object are ignored. | Legacy inbound v1 remains ordinary. New private send requires the existing encrypted-v2 path. Fail-closed unsupported content prompts update/delete instead of silently becoming ordinary. |
| D-234-08 actions and cleanup | Private media is absent from Shared Media and bookmarks. Save to Photos/Files, external Share, internal Forward, bookmark, batch actions, and PiP are always denied from viewer, bubble, library, notification/deep-link, and direct-call seams. Auto-download is always off; explicit in-app download is allowed only before terminal state and stays in canonical app storage. Info exposes only truthful generic mode/expiry state; Reply may quote only `Private media`, never caption/thumbnail. Delete-for-me remains allowed. On consumed/expired/delete, app-owned bytes, staged parts, key material, bookmark/resume state, and local path are removed while a minimal parent/state tombstone remains for idempotency. Sender delete/block semantics stay existing best effort and do not claim remote revocation. | A stale viewer path or caller boolean never grants access. Central current-row qualification plus SQL/library exclusion are both required. |

## Migration Ownership And Sequential Merge Contract

- Current landed spine: **v100**.
- Plan 234 exclusively owns landed **v100**, named `100_direct_private_media_lifecycle`.
- Plan 238 is reserved **v101** and must rebase on landed v100; the two migrations merge sequentially, never concurrently.
- Plans 242 and 243 receive no competing migration reservation here.
- v100 extends `messages`, because the private policy applies to exactly one direct attachment and the parent is durably saved before listener notification/download decisions. It does not add private columns to shared `media_attachments`, does not reclassify `owner_lane`, and does not touch `group_messages`.
- The accepted v100 contract locks constrained columns for policy version, mode, optional duration, lifecycle state, receive/expiry/reveal/terminal timestamps, and persisted clock high-water, plus an expiry-sweep index. Legacy rows default atomically to version `0`, mode `ordinary`, state `none`, and null timestamps/duration. No legacy content backfill guesses privacy.
- The frozen landed column contract is: `private_media_policy_version`, `private_media_mode`, `private_media_duration_seconds`, `private_media_state`, `private_media_received_at_ms`, `private_media_expires_at_ms`, `private_media_revealed_at_ms`, `private_media_terminal_at_ms`, and `private_media_clock_high_water_ms`, with the accepted exact SQLite types, defaults, CHECK values, and `idx_messages_private_media_expiry` proven by Session 01.
- Session 01 accepted both production create/upgrade registries, `currentIdentityDatabaseVersion == 100`, complete v99 predecessor preservation, fresh v100 creation, real 99->100 upgrade, actual-entry rerun, wrong-password rejection, downgrade rejection, and correct reopen. The Plan-238 v101 work must preserve every v100 value/index byte-for-byte.

## Device And Relay Proof Profile

- Re-resolve `flutter devices --machine`, `adb devices`, and `xcrun simctl list devices available` at execution. Never let Flutter select implicitly.
- Current bounded Android pair: physical `21071FDF600CSC` plus emulator `emulator-5554`. Use this pair for the fully automated non-platform-specific private send/receive/retry/restart lifecycle journey. It proves device-local behavior, not account-wide consumption.
- Current reproducible iOS target: booted simulator `674DFFF6-5F38-4235-93F6-AF7FBF86AE65`. Use it for iOS SQLCipher and route/capture/background integration proof; an available physical iPhone may add confidence but is not mandatory when the simulator proves the selected iOS boundary.
- Android v100 SQLCipher and secure-window proof uses explicit `21071FDF600CSC`; a second exact run may use `emulator-5554` when the session plan needs emulator automation.
- iOS screenshot prevention is not a selected claim. XCTest/native seams and simulator lifecycle/capture injection prove detection, cover, restoration, and copy; unavailable capture hardware/version legs are `N/A (target unavailable by project policy)`.
- Relay-authoritative consume/revocation is N/A by accepted product policy. No Go or relay server edits/tests are required beyond a status/diff scope guard proving none landed.

## Session Ledger

| Session | Title | Classification | Run mode | Intended plan file | Depends on | Current status | Execution verdict | Closure note |
|---|---|---|---|---|---|---|---|---|
| 01 | Typed policy, encrypted codec, and v100 durability | implementation-ready | implementation | `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-01-plan.md` | none | accepted | accepted | Session plan, source execution ledger, and this breakdown synchronized; no blocker or follow-up. |
| 02 | Compose, send/receive ordering, redacted previews, and private download entry | implementation-ready | implementation | `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-02-plan.md` | 01 | accepted | accepted | Original host slice remains accepted. A later concrete iOS NSE private-preview leak was repaired additively around Plan-256 work: causal compile RED, exact GREEN 1/1, full resolver 30/30, Dart preview preservation 55/55, independent QA accepted at `post_closure_fix_passes=1`, Graphify affected, and exactly one additional post-QA incremental refresh; no residual Session-02 item. |
| 03 | Atomic reveal, expiry, cleanup, and restart convergence | implementation-ready | implementation | `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-03-plan.md` | 01, 02 | accepted | accepted | Original host lifecycle closure remains accepted after `B1` and historical `fix_passes=1`. A later concrete timeout-proof race was repaired without changing production defaults: exact 10/10, download+cleanup 83/83, 1to1 1,963/1,963, groups 1,951/1,951 plus Go, host 88, completeness 1,179/1,179, independent QA accepted at `post_closure_fix_passes=2`, and exactly one additional post-QA incremental refresh passed. No residual, blocker, or follow-up. |
| 04 | Central action, library, egress, Forward, bookmark, and PiP eligibility | implementation-ready | implementation | `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-04-plan.md` | 01, 03 | accepted | accepted | Host-only central capability slice accepted: initial-QA version-1-ordinary `B1` resolved by causal RED/GREEN; all focused commands green including download 68/68; curated `1to1` 1,901/1,901; host inventory 80; completeness 1,166/1,166; static/scope guards green; final QA accepted after `fix_passes=1`; exactly one post-QA Graphify refresh; no owned code/test newer than refresh; no residual, blocker, or follow-up. |
| 05 | Private-route UX and native Android/iOS protection truth | implementation-ready | implementation + device proof | `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-05-plan.md` | 02, 03, 04 | accepted | accepted | Dedicated private route/native protection slice accepted: final focused/native/device/named/static/scope evidence green; final QA accepted after honest `fix_passes=3`; exactly one post-QA refresh; separate closure review accepted all 21 criteria. The third pass is a recorded bounded exception. No blocker, residual, or follow-up. |
| 06 | Cross-session acceptance, device evidence, and closure synchronization | acceptance-only | acceptance/closure | `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-06-plan.md` | 01-05 | accepted | accepted | Criteria 84/84; focused/native/device/static evidence green; host inventory 90; final artifact `854235…6233`; execution manifests `9fa736…8a13` and current closure manifests `907c422…36562` each match byte-for-byte; QA accepted after `fix_passes=2`; separate Closure Review accepted with zero findings. External `1to1` success is user-attested without an available count/log and was not rerun here. No production delta or Session-06 Graphify refresh; no residual, blocker, or follow-up. |

## Final Plan Verdict

All six Plan-234 sessions are accepted. The program is closed for the bounded
device/install-local direct private-media contract with DB v100; it has no
Plan-234-owned residual, blocker, or hidden follow-up. The final Android pair
is app-layer device-local evidence, not live relay transport, account-wide
consume, remote revocation, actual PiP, or two rendered protected sessions.

Plan 238 retains sequential DB v101. Full `host-all`, availability-bounded
final device proof, final documentation synchronization, and one final
Graphify refresh remain final included-Wave-1 work after Plan 238. Plans 242,
243, 248, 254, 241, and 253 are excluded and are not closure dependencies.

## Run Mode Contract

- `implementation`: production, causal tests, registration, and the session's docs may change. Snapshot the dirty tree first; preserve unrelated edits. RED-first is required for owned behavior. Run only focused tests, exact preservation sentinels, and the affected curated gate/family allowed below.
- `implementation + device proof`: same as implementation, plus explicit bounded native/device commands. A device failure may trigger a bounded production fix only when it proves an owned regression; record the command and target ID.
- `acceptance/closure`: default to tests, harnesses, source-plan/closure/index/gate docs, and verdict evidence. Production edits are forbidden unless a causal acceptance regression reopens the owning prior session; then return through a bounded implementation/QA pass instead of patching silently.
- Full `host-all` is forbidden per session and at Plan-234-only closure. Under
  the current exclusions it runs once at final included-Wave-1 closure after
  Plan 238, not after Plan 242.

## Ordered Session Breakdown

### Session 01 — Typed policy, encrypted codec, and v100 durability

- Session ID: `01`
- Classification: `implementation-ready`
- Intended plan: `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-01-plan.md`
- Exact scope:
  - Refresh the source plan with the resolved decisions before RED.
  - Add a shared typed/versioned private-media policy and lifecycle-state vocabulary reusable by Plans 238/242 without importing direct presentation code.
  - Carry `privateMedia` only through `MessagePayload.toInnerJson` / `fromDecryptedJson`; preserve v1 and missing-policy ordinary behavior; make malformed/unknown policy typed unsupported.
  - Extend `ConversationMessage`, mapping/copy semantics, DB helpers/repository, v100 migration, both registries, and version constant with the constrained direct parent fields above.
  - Preserve same-ID group attachments, v96 owner/library state, v97 direct Forward marker, v98 deletion journal, v99 group Forward marker, and every earlier artifact.
- Why its own session: codec compatibility and a shared production migration are the highest-blast foundation and require complete-chain/SQLCipher evidence before UI or lifecycle state writes exist.
- Likely production entry files:
  - `lib/core/media/private_media_policy.dart` (new shared domain file)
  - `lib/features/conversation/domain/models/message_payload.dart`
  - `lib/features/conversation/domain/models/conversation_message.dart`
  - `lib/core/database/migrations/100_direct_private_media_lifecycle.dart` (new)
  - `lib/core/database/app_database_version.dart`
  - `lib/core/database/production_migration_registry.dart`
  - direct message DB helpers/repository implementations and `lib/main.dart` opener wiring only where the registry/version requires it
- Likely direct tests:
  - `test/features/conversation/domain/models/private_media_policy_test.dart`
  - existing `test/features/conversation/domain/models/message_payload_test.dart`
  - new `test/core/database/migrations/100_direct_private_media_lifecycle_test.dart`
  - existing `test/core/database/integration/full_migration_chain_test.dart`
  - new `integration_test/direct_private_media_lifecycle_sqlcipher_proof_test.dart`
- Likely gates:
  - focused tests above;
  - exact Android/iOS SQLCipher commands with discovered IDs;
  - `./scripts/run_test_gates.sh 1to1` after GREEN;
  - no `core-host-all`, `feature-host-all`, or full `host-all` for this session.
- Docs/registrations: add dedicated host files to both 1:1 arrays; classify the SQLCipher file as one exact 1:1 device record in `test-gate-definitions.md`/the owning device planner; update the source plan's migration and decision sections.
- Dependency: none. It must land before Plan 238 allocates v101.

### Session 02 — Compose, send/receive ordering, redacted previews, and private download entry

- Session ID: `02`
- Classification: `implementation-ready`
- Intended plan: `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-02-plan.md`
- Exact scope:
  - Add the one-item image/video private-mode composer with duration presets and stale-selection reset; reject invalid combinations before upload/encryption/persistence.
  - Thread typed policy through encrypted direct send/retry without outer-envelope or diagnostic leakage.
  - On receive, validate and durably commit the private parent state before notification, download, or UI emission; duplicate/retry preserves the stricter/terminal durable state.
  - Redact foreground/local and decrypted push previews to `Private media`.
  - Disable auto-download for private/unsupported rows; expose only explicit app-local download before terminal state.
- Why its own session: it closes the privacy leak window at ingestion and gives a complete sender-to-durable-receiver slice; lifecycle deletion and native capture are separate failure domains.
- Likely production entry files:
  - `lib/features/conversation/application/send_chat_message_use_case.dart`
  - retry use cases that replay the persisted encrypted envelope
  - `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
  - `lib/features/conversation/application/chat_message_listener.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/push/application/push_decrypt_preview.dart`
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`, `conversation_screen.dart`, composer/attachment widgets, and l10n files
- Likely direct tests:
  - `test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart`
  - `test/features/conversation/application/send_chat_message_use_case_test.dart`
  - `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
  - `test/features/conversation/application/chat_message_listener_private_media_test.dart`
  - `test/core/notifications/private_media_preview_policy_test.dart` or the current feature/push equivalent
  - existing push preview/show-notification and encrypted media round-trip sentinels
- Likely gates:
  - focused tests and `test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart`;
  - `./scripts/run_test_gates.sh 1to1`;
  - no broad host family/full host gate.
- Docs/registrations: add new direct host/cross-feature notification files to both 1:1 arrays; keep feature-local files auto-discovered as well; update source Test Contract rows TC-234-01/02/04/05/10/13.
- Dependency: Session 01.

### Session 03 — Atomic reveal, expiry, cleanup, and restart convergence

- Session ID: `03`
- Classification: `implementation-ready`
- Intended plan: `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-03-plan.md`
- Exact scope:
  - Add a shared, lane-adapted lifecycle engine and a direct typed repository with CAS transitions for View Once and expiry.
  - Implement the `opening` lease, first-frame reveal callback, route/background terminalization, pre-frame decode rollback, restart recovery, persisted clock high-water, resume/cold-start sweep, and exactly-once app-owned cleanup.
  - Cleanup removes only the exact direct-owned attachment artifacts/key/local-state and retains the minimal terminal parent/state. Same-ID group/unresolved siblings survive.
  - Coordinate download commit, reveal, expiry, eviction, delete, and cleanup with the existing attachment lifecycle lock/conditional state seams so a loser cannot resurrect bytes/path.
- Why its own session: this is the destructive transactional core. It needs crash/interleaving regressions distinct from send/notification and from surface capability rendering.
- Likely production entry files:
  - `lib/core/media/private_media_lifecycle_engine.dart` (new reusable engine)
  - direct adapter/repository and DB helper files under conversation/database
  - `lib/core/media/media_attachment_lifecycle_lock.dart`
  - `lib/core/media/media_storage_manager.dart`
  - direct download/delete helpers and `lib/core/lifecycle/handle_app_resumed.dart`
  - minimal cold-start wiring in `lib/main.dart`
- Likely direct tests:
  - `test/features/conversation/application/consume_private_media_use_case_test.dart`
  - `test/features/conversation/application/private_media_expiry_scheduler_test.dart`
  - `test/features/conversation/integration/private_media_restart_replay_test.dart`
  - direct cleanup/download-vs-expiry race tests with real temp files
  - exact resume/cold-start wiring tests under `test/core/lifecycle/`
- Likely gates:
  - focused lifecycle/race/wiring tests;
  - existing download retry, eviction/redownload, delete, and owner-collision sentinels;
  - `./scripts/run_test_gates.sh 1to1`;
  - exact core lifecycle tests instead of `core-host-all`; no full host gate.
- Docs/registrations: explicitly register new integration/core lifecycle files in both 1:1 arrays and classify any device-bound lifecycle journey; update TC-234-07/08/09.
- Dependencies: Sessions 01 and 02.

### Session 04 — Central action, library, egress, Forward, bookmark, and PiP eligibility

- Session ID: `04`
- Classification: `implementation-ready`
- Intended plan: `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-04-plan.md`
- Exact scope:
  - Replace HEAD's ordinary-only direct qualifier with current durable parent-state qualification and one shared capability decision consumed by viewer, bubble, Save/Files/Share, Forward, bookmark, Shared Media query/batch, explicit download, reply/info, and future PiP.
  - Enforce private exclusion in repository/SQL scope as well as UI; stale paths, current-item snapshots, same-ID group rows, and unresolved rows never grant eligibility.
  - Allow only generic Reply/Info and Delete-for-me; terminal/unsupported rows cannot expose bytes or re-download.
  - Publish a typed `canEnterPictureInPicture == false` result for every private/unsupported/terminal state without implementing PiP.
- Why its own session: current plans 227-233 deliberately expose policy seams in several independently callable surfaces. Central enforcement plus bypass tests is independently verifiable and must not be hidden inside cleanup/native work.
- Likely production entry files:
  - `lib/features/conversation/application/received_media_action_controller.dart`
  - `lib/features/conversation/application/build_received_media_forward.dart`
  - `lib/features/conversation/application/direct_media_library_controller.dart`
  - batch action/delete files and media repository implementation/query helpers
  - `lib/features/conversation/presentation/screens/conversation_screen.dart`, `conversation_wired.dart`, `direct_shared_media_library_screen.dart`
  - `lib/shared/widgets/media/media_viewer_item.dart` and typed viewer adapters only as needed for the central decision
- Likely direct tests:
  - `test/features/conversation/application/private_media_action_eligibility_test.dart`
  - existing received-media controller/transport-boundary tests
  - existing direct Forward tests
  - existing direct Shared Media library/batch/boundary tests
  - shared typed viewer availability/action tests
- Likely gates:
  - focused matrix and existing plan-231/232/233 preservation suites;
  - `./scripts/run_test_gates.sh 1to1`;
  - no feature/full host sweep.
- Docs/registrations: pin the central/boundary file in both 1:1 arrays; update TC-234-06/08/13/14 and note Plan 243's dependency on this typed decision.
- Dependencies: Sessions 01 and 03.

### Session 05 — Private-route UX and native Android/iOS protection truth

- Session ID: `05`
- Classification: `implementation-ready`
- Intended plan: `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-05-plan.md`
- Exact scope:
  - Render honest unopened/opening/viewing/consumed/expired/unsupported states, generic quote/info copy, duration copy, update/delete guidance, and capture-limit disclosure.
  - Add one route-scoped Dart/native protection coordinator with completion-safe enter/exit and lifecycle restoration.
  - Android: set/clear `FLAG_SECURE` only while a private route owns it; handle nested/late/dispose calls safely.
  - iOS: add capture observation, app-switcher privacy cover, active-capture pause/cover/dismiss signaling, and restore ordinary routes; never claim screenshot prevention.
  - Wire first-frame and route-exit callbacks to Session 03; consume/expire cleanup remains application-owned, never native-owned.
- Why its own session: native platform behavior has its own Android JUnit, iOS XCTest, app lifecycle, project-registration, and device evidence. Mixing it into domain transitions would make failure ownership ambiguous.
- Likely production entry files:
  - new Dart protection coordinator/channel under `lib/core/media/` or shared media presentation
  - `lib/shared/widgets/media/full_screen_typed_media_viewer.dart` and direct route adapter
  - `android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt` plus a bounded new native coordinator
  - `ios/Runner/AppDelegate.swift` plus a bounded new native coordinator and `ios/Runner.xcodeproj/project.pbxproj`
  - l10n ARBs/generated output
- Likely direct tests:
  - direct private viewer/route widget tests
  - Dart method-channel/lifecycle tests
  - new `android/app/src/test/kotlin/com/mknoon/app/PrivateMediaProtectionNativeTest.kt`
  - new `ios/RunnerTests/PrivateMediaProtectionCoordinatorTests.swift`
  - `integration_test/direct_private_media_platform_protection_proof_test.dart`
- Likely gates:
  - focused Dart/widget tests;
  - targeted Android Gradle unit command;
  - targeted iOS XCTest command;
  - explicit physical Android + iOS simulator integration commands;
  - `./scripts/run_test_gates.sh 1to1` after focused/native GREEN;
  - no full host gate.
- Docs/registrations: exact device record and native command in source plan/gate docs; update TC-234-11 and platform limitation copy.
- Dependencies: Sessions 02, 03, and 04.

### Session 06 — Cross-session acceptance, device evidence, and closure synchronization

- Session ID: `06`
- Classification: `acceptance-only`
- Intended plan: `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-06-plan.md`
- Exact scope:
  - Independently audit the resolved policy/action/state table, migration reservation, scope diff, registrations, diagnostics redaction, and ordinary-media preservation.
  - Run all Plan-234 focused suites, representative mutation checks, v99->v100 SQLCipher proof, Android/iOS protection proof, and the fully automated physical-Android + Android-emulator sender/recipient journey.
  - The Android pair must prove encrypted private send, policy-before-preview, generic notification, no auto-download, explicit app-local download, one View Once reveal, terminal cleanup/restart non-resurrection, disappearing expiry, protected repeat viewing, and ordinary media preservation. It must also prove that one device's local terminal state is not described as a remote/account consume receipt.
  - Run the complete curated `1to1` gate, targeted analysis, `git diff --check`, gate completeness, and Go/relay no-scope diff guard.
  - Update source status/checklist/final verdict, `00-INDEX`, the stable 1:1 closure reference, gate definitions/arrays, and this ledger.
- Why its own session: device/SQLCipher/native evidence validates all earlier slices and closure docs together; it must be independent of the implementers and must not disappear into the last native change.
- Likely tests/evidence:
  - every new Plan-234 test;
  - ordinary encrypted media, retry, eviction, egress, Forward, Shared Media, viewer, notification, and delete sentinels;
  - `integration_test/direct_private_media_lifecycle_sqlcipher_proof_test.dart` on explicit Android/iOS targets;
  - `integration_test/direct_private_media_platform_protection_proof_test.dart` on explicit Android/iOS targets;
  - a fully automated two-Android lifecycle runner using `21071FDF600CSC` + `emulator-5554` after live re-resolution.
- Likely gates:
  - `./scripts/run_test_gates.sh 1to1`;
  - `./scripts/run_host_test_gates.sh 1to1 --list` and registration comparison;
  - `./scripts/run_test_gates.sh completeness-check`;
  - targeted `dart analyze`/`flutter analyze` for changed surfaces and `git diff --check`;
  - no Plan-234-only full `host-all`; defer to final included-Wave-1 closure
    after Plan 238.
- Matrix/closure docs: `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan.md`, `Test-Flight-Improv/00-INDEX.md`, `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`, `Test-Flight-Improv/test-gate-definitions.md`, gate scripts, and this breakdown ledger.
- Dependencies: Sessions 01-05.

## Why This Is Not Fewer Sessions

- v100/codec compatibility can corrupt every profile and therefore cannot share an acceptance boundary with UI/native work.
- Ingestion ordering/redaction is a pre-notification privacy boundary; reveal/expiry is a destructive crash-recovery boundary. One vertical mega-session would make a green notification test say nothing about cleanup resurrection.
- Lifecycle transitions and capability enforcement have different counterexamples: a correct cleanup engine can still be bypassed through Forward/library/native egress, while perfect button hiding can still leave bytes after restart.
- Android/iOS native protection has different build/test machinery and truthful guarantees from Dart domain work.
- Final device/SQLCipher/closure evidence spans all slices and needs an independent acceptance owner.

## Why This Is Not More Sessions

- Composer selection, encrypted send, receive persistence, notification redaction, and auto-download denial form one observable ingress contract and use the same policy fixture; splitting each would create misleading half-states.
- View-once, disappearing expiry, cleanup, and restart recovery share one CAS/state machine and one destructive race family.
- Save/Share/Forward/bookmark/library/PiP are consumers of one current-row capability decision; separate per-action sessions would encourage duplicated policy.
- Android and iOS remain in one native session because they implement one route ownership contract and must ship with shared truthful copy, while their direct tests stay platform-specific.
- Documentation-only closure is one acceptance session, not a separate plan per file.

## Regression And Gate Contract

- Follow the regression strategy's focused causal-test-first model. Each implementation session starts with the smallest named RED that proves its owned failure and retains exact GREEN sentinels for ordinary media.
- Every new feature-local direct test is auto-discovered by feature broad gates but must also be explicitly evaluated for the curated 1:1 arrays. New core lifecycle, migration, cross-feature notification, integration, and device tests require explicit classification in `test-gate-definitions.md` and `completeness-check`.
- Per session: focused causal tests + exact preservation sentinels + `./scripts/run_test_gates.sh 1to1`. Use targeted native/SQLCipher commands only in owning sessions. Do not add `host-all` as a per-session gate.
- A broad family sweep is not justified by default here: run exact changed core/feature files and the curated 1:1 gate. If a downstream planner proves an app-wide production surface beyond these named seams changed, it may add the single affected `core-host-all` or `feature-host-all` sweep with a written justification; never both reflexively.
- Full `host-all` runs once at final included-Wave-1 closure after Plan 238.
  Excluded Plans 242/243 are not dependencies of this rollout.
- Required ordinary preservation includes encrypted v2 send/receive, retry/dedup, download/eviction, received-media Save/Share, Forward, Shared Media/bookmark/batch, viewer playback/resume, notification preview, and Delete-for-me.
- Representative mutations must include: missing policy made private, unknown mode treated ordinary, policy emitted outside inner JSON, notify/download before commit, duplicate resetting terminal state, non-CAS reveal, clock rollback extending expiry, cleanup deleting same-ID group sibling, stale viewer path granting egress, private row appearing in Shared Media, Android secure flag left global, and iOS copy claiming prevention.

## Matrix Update Contract

- Do not create a new broad matrix. Session 06 extends the stable `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` with the accepted private-media maintenance contract and reopen triggers.
- Session 06 updates the source plan's decision ledger, execution evidence, done checklist, and final verdict; updates `Test-Flight-Improv/00-INDEX.md` from evidence-gated to the actual accepted/blocked outcome; and synchronizes `test-gate-definitions.md` plus both executable 1:1 arrays.
- This breakdown's Session Ledger becomes the program ledger: each downstream closure pass records the landed plan verdict/evidence and changes the corresponding status to `completed` only after the intended plan's closure audit is persisted.
- Plan 238's session planning must read landed v100 and preserve it while taking
  v101. Plans 242/243 remain excluded from this rollout; their future ownership
  statements do not create a current execution or closure dependency.

## Downstream Execution Path

For each session in order:

1. Refresh the doc-scoped intended plan through `$implementation-plan-orchestrator` against landed code and live devices.
2. Execute the accepted plan through `$implementation-execution-qa-orchestrator` with RED/GREEN evidence and bounded independent QA.
3. Close the session through `$implementation-closure-audit-orchestrator`, update this ledger on disk, then refresh the next session.

No later session is planned once and treated as immutable; every prerequisite landing can change symbols, tests, and exact commands.

## Reviewer Verdict

- Recommended count: **sufficient; neither too coarse nor too fragmented**.
- Merge candidates: none. Merging Sessions 03/04 or 05/06 would erase independent verification value.
- Required splits: none after retaining lifecycle and action enforcement as separate sessions.
- Missing tests/gates: none structurally. Exact test names/commands must be frozen by each downstream planner after checking landed code; device records and cross-feature/core files require explicit registration.
- Meaningful end state: yes. Session 01 gives durable typed policy; 02 gives private delivery/redaction; 03 gives terminal lifecycle; 04 closes bypasses; 05 gives truthful platform behavior; 06 gives accepted program evidence.
- Matrix responsibility: assigned only to Session 06.
- Minimum safe set: six sessions.

## Arbiter Result

- Structural blockers: none.
- Mergeable sessions: none.
- Required splits: none.
- Accepted differences: the local-only and platform-truth limitations below.
- Stop rule satisfied after one reviewer/arbiter pass; no replanning loop is needed before Session 01 planning.

## Structural Blockers Remaining

None. The repo supports a conservative device-local implementation without an external moderation, legal, relay-authority, or unavailable-hardware decision.

## Accepted Differences Intentionally Left Unchanged

- View Once is once per installed device, not account-wide. No consumption receipt or relay single-use API is added.
- Existing relay storage/deletion semantics remain; no sender revocation guarantee exists.
- iOS screenshots cannot be prevented by this product contract; detection/obscuring/warning is the honest boundary.
- No software can prevent photographing a screen with another camera.
- Private items are excluded from Shared Media rather than represented by protected thumbnails.
- Sender source files and already external copies cannot be revoked.
- Plan 234 supplies fail-closed PiP eligibility only; Plan 243 owns native PiP implementation and Android/iOS PiP acceptance.
- Group and announcement lifecycle remain Plans 238 and 242 and may reuse shared typed policy/engine without importing direct storage/UI.

## Exact Docs And Files Used As Evidence

- `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/00-INDEX.md`
- `scripts/run_test_gates.sh`
- `scripts/run_host_test_gates.sh`
- `lib/core/database/app_database_version.dart`
- `lib/core/database/production_migration_registry.dart`
- `lib/core/database/migrations/096_media_library_state.dart`
- `lib/core/database/migrations/099_group_messages_is_forwarded.dart`
- `test/core/database/migrations/096_media_library_state_test.dart`
- `test/core/database/migrations/099_group_messages_is_forwarded_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`
- `lib/core/media/media_owner_lane.dart`
- `lib/core/media/media_attachment_lifecycle_lock.dart`
- `lib/core/media/media_storage_manager.dart`
- `lib/features/conversation/domain/models/conversation_message.dart`
- `lib/features/conversation/domain/models/media_attachment.dart`
- `lib/features/conversation/domain/models/message_payload.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/application/received_media_action_controller.dart`
- `lib/features/conversation/application/direct_media_library_controller.dart`
- `lib/features/conversation/application/direct_media_library_batch_actions.dart`
- `lib/features/conversation/application/build_received_media_forward.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart`
- `lib/features/push/application/show_notification_use_case.dart`
- `lib/features/push/application/push_decrypt_preview.dart`
- `lib/shared/widgets/media/media_viewer_item.dart`
- `lib/shared/widgets/media/full_screen_typed_media_viewer.dart`
- existing direct action, library, codec, send/receive, download, notification, viewer, migration, and SQLCipher tests surfaced by the Graphify shortlist and targeted file search
- `android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt`, `android/app/src/test/kotlin/com/mknoon/app/ReceivedMediaEgressNativeTest.kt`
- `ios/Runner/AppDelegate.swift`, `ios/Runner/ReceivedMediaEgressCoordinator.swift`, `ios/RunnerTests/ReceivedMediaEgressCoordinatorTests.swift`, and `ios/Runner.xcodeproj/project.pbxproj`

## Why The Decomposition Is Safe For Downstream Planning And Execution

The feature no longer depends on undefined privacy claims: each former evidence decision has one conservative, testable answer; the relay boundary is explicitly out; platform limitations are truthful; v100/v101 ownership is collision-free and sequential; destructive lifecycle and bypass enforcement have separate regression families; the live device policy is bounded and reproducible; ordinary behavior and cross-lane ownership are explicit sentinels; and acceptance/closure responsibility cannot disappear into implementation. Every session has a doc-scoped plan path and a mandatory plan -> execution/QA -> closure chain.
