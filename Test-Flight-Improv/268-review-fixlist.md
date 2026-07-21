# 268 Review — Fix-List (apply against `268-group-media-keep-in-chat-only-tdd-plan.md`)

Applied: 2026-07-21 during Plan 268 execution. Sections §A–§E are now
incorporated into the plan contract; the untouched-tree baseline includes the
full curated groups lane plus the direct TC-268-05 sentinels.

Source: 8-agent `/tdd-review` audit (2 source verifiers, 5 dimension assessors, completeness critic; workflow `wf_6127595b-1f9`) + orchestrator source verification, 2026-07-21. Plan is **ready-with-tightening**; core bet **verified sound** — do not execute until §A–§D land in the plan text. No production-code change is prescribed here; every item is a plan-text edit.

Decisions locked with the user:
- Next action: findings + this written fix-list; the plan file itself is untouched.
- Release-risk: N/A — no one-way change (B-1 clear: no migration, revert is git-level, fresh ordinary rows emit no private wire fields).
- "Done" definition: unchanged from the plan — binary host contract (causal RED→GREEN commands + preservation sentinels), explicitly NOT a claim that the user's original device observation is fixed (plan Handoff already states this).

Gloss: "wired" = the production-wired widget variant (`group_conversation_wired.dart` vs the pure-presentation `group_conversation_screen.dart`); "continuation" = the restored-media resend mechanism that reuses a failed parent's ID/timestamp; GPL-*/APL-* = existing group/announcement private-media sentinel tests.

Verified facts this list relies on (checked against source by the orchestrator):
- Root cause exact: `_attemptAddPendingMedia` appends without resetting `_privateMediaPolicy` (`group_conversation_wired.dart:1255-1266`) while `_removeAttachment` resets it (`:4665-4671`); eligibility one-item gate `group_private_media_policy.dart:57-67`; silent return `:2812-2825`. ✅
- Continuation reuses original parent ID/timestamp (`:2852-2853` via `:1346-1393`) and replaces the failed attachment (`:2979` → `:2404-2417`); projected terminal restore at `:3728` skips `_trackRestoredMediaContinuation`. ✅
- `_trackRestoredMediaContinuation` accepts only a durable row with status `'failed'` (`:1421-1428`); production terminal projection writes `'failed'` in-transaction (`media_attachments_db_helpers.dart:447-459`). ✅
- `GroupMessageRepositoryImpl` implements `GroupUploadRetryProjectionRepository` (`group_message_repository_impl.dart:42`); injectable via widget param (`group_conversation_wired.dart:315`, getter `:2219-2223`). ✅
- Shared pump helpers pass the to-be-removed constructor params from outside every plan-cited edit range: `group_conversation_screen_test.dart:113-117` (decls) + `:164-168` (pass-through); wired `buildWidget` `:1462-1463` + `:1498`. Keep-side `privateMediaAvailability` sits adjacent (`:1464-1465`, `:1499`) and is used by preserved tests (`:4286`, `:4358`, `:4425`). ✅
- `push_decrypt_preview_test.dart` is a `GROUP_TESTS` member (`scripts/run_test_gates.sh:581`), so the notification-redaction Do-not is already gate-guarded. ✅
- Sixth benign policy-ingress site `_resetForGroupChange` (`group_conversation_wired.dart:1175`), widget-sourced, removed by the same step-3 deletion. ✅
- Voice (`:5079-5372`), internal forward (`share_batch_delivery_coordinator.dart:1419-1440`, fail-closed at `group_media_forward_policy.dart:56,117,134-140` and `build_received_media_forward.dart:534-543`), and external share carry no fresh private policy — no missed sibling send path. ✅

## §A — Test-surgery completeness & first runnable checkpoint (blocker 1, B-2 hit)

- **A1.** Amend step 4 to name the two shared pump-helper edits: remove the three authoring params and their pass-throughs from the screen-test helper (`group_conversation_screen_test.dart:113-117`, `:164-168`) and remove `privateMediaPolicy` from the wired `buildWidget` helper (`group_conversation_wired_test.dart:1462-1463`, `:1498`). These sites sit outside every edit range the plan cites; without them neither test file compiles after steps 2–3.
- **A2.** In the same step-4 amendment, explicitly mark `privateMediaAvailability` (`wired_test:1464-1465`, `:1499`) as **kept**: it is production-load-bearing (`group_conversation_wired.dart:393`) and used by preserved legacy tests (`:4286`, `:4358`, `:4425`). It sits directly under the removed param — a wholesale plumbing deletion would over-delete it and break preserved sentinels.
- **A3.** State the checkpoint reality in the Acceptance Gates and step ordering: the first runnable "Causal GREEN" checkpoint is steps 2+3+4 (production removal + obsolete-test retirement/conversion + A1 helper edits) **combined** — no focused command in either composer test file compiles between step 3 and step 4 as currently sequenced. Fold or explicitly sequence the test surgery with the production slice.
- **A4.** Add one sentence to step 4: line ranges (`screen_test:275-507`, `wired_test:3915-4235`, GPL-03A-W `:4259`, GPL-03A-R `:4331`, GPL-03H `:4399`) are HEAD-relative and shift once step 1 appends new tests to the same file — locate targets by test name, treating cited lines as pre-edit anchors.

## §B — TC-268-09 fixture fidelity (blocker 2)

- **B1.** Add to TC-268-09's Test Notes: the injected fake `GroupUploadRetryProjectionRepository` must itself persist parent status `'failed'` into the fake message repo when reporting a terminal failure (mirroring production `dbProjectGroupUploadFailure` → `media_attachments_db_helpers.dart:447-459`). Why: `_trackRestoredMediaContinuation`'s acceptance gate (`wired.dart:1421-1428`) rejects any row not durably `'failed'` — a naive fake makes a **correct** production fix fail GREEN spuriously.
- **B2.** Add: the TC-268-09 fixture must inject `mediaAttachmentRepo` + `mediaFileManager` (the attachment-replacement path needs both), and the injection pattern to copy lives inside GPL-03A-W (`wired_test:4282-4286`) — **copy it out before step 4 retires that test**, or the referenced example disappears mid-execution.

## §C — Mutation-evidence attribution (blocker 3)

- **C1.** Split TC-268-02's mutation cell (plan line 189). After GREEN the selector is deleted, so TC-268-02's conditional discriminator can never commit Protected again — a state-only "reintroduce mutable composer policy" mutant is killed **only** by TC-268-01's source contract, not by TC-268-02. Reword: "pass a nonordinary policy at the optimistic/final send boundary → TC-268-02 red (wire-key oracle); reintroduce selector/authoring prop/mutable state/snapshot policy → TC-268-01 source contract red." Why: the done checklist requires *recorded* mutation re-red; as written the executor records a kill that never happened or falsely concludes the harness is broken.
- **C2.** Replace "representative mutation re-red" in the done checklist with a minimal mandatory set: one mutation per causal row (selector restore; mutable-policy reintroduction; projected-restore private policy / omitted continuation) **plus** the TC-268-03 CAS deletion (`wired.dart:2523-2548`), each with its expected red test named.

## §D — Baselines & RED semantics (blocker 4)

- **D1.** Insert a pre-edit baseline block in the Acceptance Gates immediately after the `git status --short` snapshot: run all TC-268-03..08 focused commands (or `./scripts/run_test_gates.sh groups`) once on the untouched tree, record results in Execution Progress, **stop-if** any named sentinel is not green. Why: only 2 of 20 asserted-GREEN sentinels were actually probed during planning; a pre-existing red discovered post-edit is unattributable.
- **D2.** Add to Execution Interpretation: a causal RED counts only if the recorded failure output shows the pre-committed mechanism for that test (e.g. TC-268-02 must show zero upload/publish calls after the silent return); "no tests match", load errors, or compile errors do not count as RED.
- **D3.** (nit) Record `flutter analyze` output during the step-1 snapshot so "no new issues" is checked against captured evidence, not inference.

## §E — Specs & cleanup (nits, apply opportunistically)

- **E1.** Extend TC-268-01's source contract with rename-resistant forbidden slices: any import of `lib/shared/widgets/private_media_policy_picker_sheet.dart` in the group screen and any `showPrivateMediaPolicyPickerSheet`/`PrivateMediaSummaryChip` reference — the current key-named negative assertions are satisfiable by a renamed reintroduction.
- **E2.** Name `lib/features/push/application/push_decrypt_preview.dart:725` in the Do-not list as the sole out-of-layer nonordinary-policy construction (receive-side redaction, untouchable), and note it is guarded by `push_decrypt_preview_test.dart` in `GROUP_TESTS` (`run_test_gates.sh:581`) — protects against an over-eager repo-wide symbol sweep.
- **E3.** Pin the source-contract mechanics in Test Notes: the literal forbidden identifiers (including the exact `_GroupComposerSnapshot` policy field name, read from source before authoring RED — declared at `wired.dart:7955`) and the slice mechanism, with `message.privateMediaPolicy`/receive-side reads explicitly allowed.
- **E4.** TC-268-02/03 wire oracle: the wired fake bridge captures reliable + publish; either pin the exact replay-capture seam or apply TC-268-06's honest rule (unavailable map types are N/A for that fixture, not inferred).
- **E5.** Add the sixth ingress `_resetForGroupChange` (`wired.dart:1175`) to the ingress enumeration (same step-3 removal covers it; source contract catches residue).
- **E6.** Cite fix: `toWireExtras()` is `group_private_media_policy.dart:269-277` (plan says `:266-276`, the doc comment).

## Priority order to apply

1. **§A** — without it the plan's own GREEN gates are unrunnable as sequenced and the adjacent keep-param can be over-deleted (breaks preserved sentinels).
2. **§B** — prevents a correct fix from failing TC-268-09 and losing the fixture example mid-execution.
3. **§C + §D1/D2** — makes the recorded causal/mutation evidence truthful and the baseline attributable.
4. **§E** — hardening and citation cleanup.
