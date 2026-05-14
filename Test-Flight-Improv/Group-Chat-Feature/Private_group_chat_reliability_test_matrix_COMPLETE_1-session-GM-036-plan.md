# GM-036 Plan: Admin Feedback Distinguishes Local Membership Update From Invite/Key Delivery

Status: accepted/closed

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-12 01:47:22 CEST | Arbiter completed | Reviewer-adjusted plan; final mandatory sections; scoped diff for GM-036 plan file | No structural blockers remain. Tests-only `implementation-ready` is safe with explicit stop/replan if RED proves product code is needed. | Hand off to execution; edit no files except this plan in the planning turn. |
| 2026-05-12 01:46:32 CEST | Reviewer completed | Full draft plan; GM-036 source row steps; direct test target list | Sufficient with adjustment: D's primary forced failure must be transient delivery failure (`needsResend`) and the row's final Send step must be required evidence, not optional. | Patch the draft, then run arbiter classification. |
| 2026-05-12 01:43:29 CEST | Planner completed | Evidence summary, GM-036 row contract, current invite delivery UI/API seams, gate definitions | Drafted tests-only execution plan with exact RED/GREEN target, direct tests, gates, scope guard, stop/replan rules, and closure evidence. | Run strict reviewer pass against the draft before marking execution-ready. |
| 2026-05-12 01:43:29 CEST | Evidence Collector completed | GM-036 source/breakdown rows; `git status --short`; `Test-Flight-Improv/test-gate-definitions.md`; `scripts/run_test_gates.sh`; `lib/features/groups/application/add_group_member_use_case.dart`; `send_group_invite_use_case.dart`; `record_group_invite_delivery_attempts.dart`; `resend_group_invite_use_case.dart`; `remove_group_member_use_case.dart`; `group_message_listener.dart`; `group_key_update_listener.dart`; `group_config_payload.dart`; `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`; invite delivery repository/helper files; `group_info_wired.dart`; `group_member_row.dart`; `group_invite_status_presentation.dart`; owner-hinted Go files; suggested and adjacent tests | Tests-only classification remains valid: product code already separates local membership update from per-recipient invite/key delivery, persists delivery status, shows status/resend UI, and re-add send behavior is covered by adjacent rows. Missing item is exact GM-036 mixed C/D row-named proof. | Draft the narrow execution-safe RED/GREEN plan with direct proofs, gate commands, stop rules, and closure evidence. |
| 2026-05-12 01:40:57 CEST | Evidence Collector started | `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`; `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`; `git status --short` | GM-036 is confirmed as the next unresolved P0, classified `needs_tests_only`/`implementation-ready`; plan file was absent; worktree is dirty in related files and must be treated as shared state. | Inspect relevant code/tests, existing delivery status surfaces, and scoped dirty diffs before drafting. |

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-12 01:53:10 CEST | Executor fallback started | `implementation-execution-qa-orchestrator` skill; this GM-036 plan; `git status --short`; scoped diffs for GM-036 target tests | No spawn-agent tool is available in this environment, so execution is continuing as the requested isolated Executor using the skill's local sequential fallback. Contract extracted: tests-only unless RED proves product code is needed; source matrix and session breakdown closure rows are out of scope. | Add exact GM-036 tests in the three primary targets, then run required selectors and gates. |
| 2026-05-12 01:57:36 CEST | Executor direct selectors | `test/features/groups/presentation/contact_picker_wired_test.dart`; `test/features/groups/presentation/group_info_wired_test.dart`; `test/features/groups/integration/group_membership_smoke_test.dart` | Added three exact GM-036 tests. `contact_picker_wired_test.dart --plain-name GM-036` passed; `group_membership_smoke_test.dart --plain-name GM-036` passed; first parallel `group_info_wired_test.dart --plain-name GM-036` hit Flutter native-asset/lipo contention, then sequential rerun passed. No production gap found. | Run adjacent suggested suites, `./scripts/run_test_gates.sh groups`, and `git diff --check`; then perform local QA review. |
| 2026-05-12 02:00:27 CEST | Executor QA complete | GM-036 tests in the three primary target files; adjacent suites; `./scripts/run_test_gates.sh groups`; `git diff --check` | Adjacent suites passed, `groups` gate passed, and `git diff --check` passed. Local QA found no product gap and no need for optional lower-level `send_group_invite_use_case_test.dart`. No source matrix or session breakdown closure rows were edited. | Final verdict: `tests-only accepted`. |

## Execution Verdict

Final classification: `tests-only accepted`.

Files changed for GM-036:

- `test/features/groups/presentation/contact_picker_wired_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-036-plan.md`

Exact GM-036 tests added:

- `GM-036 batch invite reports mixed delivery after local re-add`
- `GM-036 mixed invite statuses remain visible after reload`
- `GM-036 send after mixed re-add does not clear failed invite status`

Command evidence:

- `flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name 'GM-036'` passed.
- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name 'GM-036'` initially hit Flutter native-asset/lipo contention when run in parallel with other Flutter commands; sequential rerun passed.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-036'` passed.
- `flutter test test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart` passed.
- `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart` passed.
- `./scripts/run_test_gates.sh groups` passed.
- `git diff --check` passed.

No production code changed. The first RED did not prove missing product behavior, so the execution stayed tests-only.

## real scope

Own exactly GM-036: an admin batch re-adds two members, C and D, local membership/config update succeeds for both, C's invite/key delivery succeeds, D's invite/key delivery fails, and the app/API gives honest per-member feedback before and after a send.

Allowed future execution changes are tests only unless the RED test disproves the current classification:

- Add row-named GM-036 tests that prove mixed per-recipient invite delivery results are surfaced distinctly from local membership updates.
- Prefer direct widget/API tests around `ContactPickerWired`, `ContactPickerInviteResult`, `GroupInfoWired`, and invite delivery attempt persistence because those are the UI/API feedback seams for this row.
- Add or reuse exact GM-036 coverage in the suggested group membership/onboarding suites only where it proves re-add/send context that the widget tests cannot.

Not in scope: GM-032 group dissolve/all-members removal, GK key crypto rows, broad discovery/dial changes, relay storage changes, group-key rotation design, notification routing, closure updates to the source matrix or breakdown, or any production/test refactor outside GM-036 proof.

## closure bar

GM-036 is good enough when row-owned evidence proves all of these:

- C and D are added/re-added locally and appear as current group members only after the local add/config path succeeds.
- The API result does not say "all invited" or "all can receive" when D's invite/key delivery failed.
- The result reports C as delivered or queued and D as `needsResend` for a transient delivery failure, with `lastError: send_failed`.
- The failed member has a persisted `GroupInviteDeliveryAttempt` with `lastError`, so the failure survives navigation/reload.
- Group Info shows honest per-member status and, for `needsResend`, exposes the resend action for D without showing it for C.
- A subsequent group send does not silently clear or overwrite D's failed invite/key delivery status.

## source of truth

- Primary contract: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GM-036.
- Session ordering and classification: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` GM-036 inventory, row-disposition, ordered-session, and detailed-session rows.
- Current code and tests win over stale prose.
- Gate source of truth: `scripts/run_test_gates.sh`; `Test-Flight-Improv/test-gate-definitions.md` explains gate intent, but the script wins on disagreement.

## session classification

`implementation-ready`

Row subtype: `needs_tests_only`.

Rationale: current code already has the required product seams. `ContactPickerWired` separates local add/config publish from `sendGroupInvitesInParallel`, `GroupInviteBatchResult` carries per-recipient success/failure, `recordGroupInviteDeliveryBatch` persists statuses, `GroupInfoWired` loads and displays those statuses, and `resendGroupInvite` repairs `needsResend` members. The missing work is exact GM-036 row-named proof for mixed C/D re-add delivery; no production gap is proven by planning evidence.

## exact problem statement

The risk is a false success claim: after a batch re-add, the app could locally add C and D, successfully deliver C's invite/key, fail D's invite/key, then still tell the admin that every re-added member can receive. That strands D because D is in local membership but lacks the delivered invite/key material needed to participate.

GM-036 must improve confidence that mixed local membership success and invite/key delivery failure stays visible and actionable. Existing behavior for successful invites, missing group key warnings, group config publish rollback, member removal/re-add semantics, and normal group message sending must stay unchanged.

## files and repos to inspect next

Production/UI seams:

- `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/screens/group_info_screen.dart`
- `lib/features/groups/presentation/widgets/group_member_row.dart`
- `lib/features/groups/presentation/group_invite_status_presentation.dart`
- `lib/features/groups/application/send_group_invite_use_case.dart`
- `lib/features/groups/application/record_group_invite_delivery_attempts.dart`
- `lib/features/groups/application/resend_group_invite_use_case.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl.dart`

Owner-hinted Go files are inspect-only unless RED proves a transport-side issue:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`

Test seams:

- `test/features/groups/presentation/contact_picker_wired_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/presentation/group_info_screen_test.dart`
- `test/features/groups/application/send_group_invite_use_case_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `integration_test/group_real_crypto_onboarding_test.dart`

## existing tests covering this area

- `send_group_invite_use_case_test.dart` already proves `sendGroupInvitesInParallel` preserves per-recipient outcomes when one invite fails.
- `contact_picker_wired_test.dart` already proves a single failed invite can still add the member locally and return a warning message instead of a clean invite success.
- `group_info_screen_test.dart` already proves status labels and resend action visibility for `queued`, `needsResend`, and `cannotSend`.
- `group_info_wired_test.dart` already proves persisted invite statuses load into Group Info and resend can update a `needsResend` member.
- Invite delivery repository tests already prove persisted statuses round-trip.
- Member removal and membership smoke suites already cover adjacent remove/re-add and post-readd send behavior, including GM-033/GM-035 style reliability edges.

Missing: no exact `GM-036` selector proves a batch re-add with C success and D failure, the completion API warning, persisted C/D statuses, Group Info visibility, and status preservation after send.

## regression/tests to add first

RED target:

- Add `GM-036` row-named test coverage before any product change.
- The core test should simulate C success and D failure in one batch, assert the local membership update succeeds for both, and assert the returned result/status UI distinguishes C from D.
- If this test passes immediately, record it as tests-only green-on-arrival and do not patch production. If it fails, only then re-evaluate the tests-only classification.

Primary tests to add:

- `test/features/groups/presentation/contact_picker_wired_test.dart`
  - Add `GM-036 batch invite reports mixed delivery after local re-add`.
  - Use two selected contacts, e.g. Charlie succeeds and Dave fails via a deterministic test bridge/P2P hook that throws or fails only for Dave's invite delivery after local add remains valid.
  - Assert `membersAdded == 2`, `invitesSent == 1`, `hasWarnings == true`, completion copy says members were added but includes only D in invite issues, and does not use the clean "2 members invited" success path.
  - Assert both members are in `groupRepo`, C has `sent` or `queued`, D has `needsResend` with `lastError: send_failed`, and D is not `unknown`.
- `test/features/groups/presentation/group_info_wired_test.dart`
  - Add `GM-036 mixed invite statuses remain visible after reload/send`.
  - Seed C and D as current members with persisted invite attempts, send or simulate a normal group action if needed, load `GroupInfoWired`, and assert C's status is successful/queued while D shows failed status and the resend button appears only for `needsResend`.
- `test/features/groups/integration/group_membership_smoke_test.dart`
  - Add `GM-036 send after mixed re-add does not clear failed invite status`.
  - Seed or drive the same mixed C/D re-add state, perform the row's final Send step, then assert D's invite delivery attempt remains `needsResend`/`send_failed` and C remains successful/queued. The send proof must not mark D as joined, sent, or unknown.

Optional direct support if the primary tests need lower-level proof:

- `test/features/groups/application/send_group_invite_use_case_test.dart` can add an exact `GM-036` selector around `GroupInviteBatchResult.describeFailures`.

## step-by-step implementation plan

1. Re-run `git status --short` and inspect `git diff -- <file>` before touching any dirty file. Preserve all pre-existing edits.
2. Add a small test-only fake if needed:
   - Prefer a private test bridge that fails `message.encrypt` only for D's ML-KEM key, leaving C's path successful.
   - If using P2P failure instead, make it peer-specific in the test only; do not change production `P2PService`.
3. Add the primary `ContactPickerWired` GM-036 test. Construct the widget manually if the existing helper does not accept `inviteDeliveryAttemptRepo`; do not change production code for helper convenience.
4. Run the new selector. If it passes immediately, continue as tests-only. If it fails because production claims clean success, does not persist D's status, or cannot distinguish recipients, stop and replan as code-and-tests.
5. Add the `GroupInfoWired` GM-036 test proving persisted mixed statuses are shown after reload and D is actionable.
6. Add the required GM-036 Send-step proof in `group_membership_smoke_test.dart` or an equally direct group send test. The proof must show a normal send after mixed re-add feedback does not silently promote or clear D's failed invite/key delivery status.
7. Add optional lower-level GM-036 proof only if the first three tests do not isolate the failure cause clearly.
8. Run direct selectors, adjacent suggested suites, `groups` gate, and hygiene commands listed below.
9. Do not update source matrix, breakdown, closure ledger, or adjacent plans in this execution session; closure evidence belongs to a later closure/audit pass.

## risks and edge cases

- Per-recipient failure must be deterministic. A global fake P2P failure would fail both C and D and would not prove mixed delivery.
- `Future.wait` preserves result order by input order, but assertions should match by `peerId`, not list position.
- D's primary GM-036 failure should be `needsResend`/`send_failed`, because the row requires a stranded-but-repairable failed member rather than a permanently unpreparable invite. `cannotSend` remains adjacent status vocabulary, not the main GM-036 proof.
- "Missing group key" is not the right primary GM-036 proof because it skips all invite sends and does not create mixed C/D outcomes.
- A later `member_joined` event can legitimately mark an invite `joined`; GM-036 should not break that behavior.
- Removal/re-add timestamps and stale joined attempts must not make a failed D appear joined.
- The dirty worktree already has broad group changes; failures outside GM-036-touched tests must be classified before fixing.

## exact tests and gates to run

Direct RED/GREEN selectors:

```bash
flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name 'GM-036'
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name 'GM-036'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-036'
```

If an exact lower-level selector is added:

```bash
flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart --plain-name 'GM-036'
```

Suggested adjacent suites:

```bash
flutter test test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart
flutter test test/features/groups/integration/group_new_member_onboarding_test.dart
```

Named gate and hygiene:

```bash
./scripts/run_test_gates.sh groups
git diff --check
```

Conditional commands:

```bash
./scripts/run_test_gates.sh completeness-check
```

Run `completeness-check` only if execution adds a new test file or edits gate/test inventory docs. Run `integration_test/group_real_crypto_onboarding_test.dart` only if execution changes real crypto onboarding/invite payload behavior or needs nightly-style evidence; record the actual `FLUTTER_DEVICE_ID` if used.

No Go command is required for tests-only GM-036. If a RED points at Go publish/inbox behavior, stop and replan before touching Go code.

## known-failure interpretation

- There is no planning-time known GM-036 failure because the exact test does not exist yet.
- Existing broad dirty-tree failures must not be attributed to GM-036 unless they reproduce in a GM-036-touched selector or the `groups` gate failure points at the exact invite delivery/status path changed by execution.
- If `groups` fails in an unrelated file or from an existing dirty edit, record the failing file/test and current dirty context; do not fix it under GM-036 without a causal link.
- If a direct selector is green-on-arrival after adding the test, that is acceptable for `needs_tests_only`; closure should state that the implementation was proof-only.

## done criteria

- The plan's future executor changes only tests/test helpers unless a stop/replan rule explicitly fires.
- Exact GM-036 tests prove mixed C/D delivery feedback after local re-add.
- C and D local membership state is asserted separately from invite/key delivery status.
- D's failure is persisted and visible/actionable after reload; D is not silently `unknown`.
- A send after the mixed result does not erase D's failed status.
- Direct selectors, adjacent suggested suites, `groups` gate, and `git diff --check` pass or have explicitly classified non-GM-036 failures.
- Closure evidence records exact command outputs, touched files, and whether tests were green-on-arrival or exposed a product gap.

## scope guard

Do not solve GM-032, GK rows, general key rotation, group dissolve, discovery filters, real relay proof, or push/notification behavior.

Do not:

- Change production code just to make tests easier.
- Rewrite invite delivery status vocabulary.
- Mark failed D as joined/sent/queued without a real send result or join event.
- Clear `lastError` except through the existing resend/join success paths.
- Reformat unrelated dirty files.
- Update the source matrix or session breakdown from this planning/execution plan.

Overengineering would be adding a new delivery-state subsystem when the current `GroupInviteDeliveryAttempt` model already has the required statuses.

## accepted differences / intentionally out of scope

- GM-036 closes through host/widget/API evidence unless execution changes real onboarding/invite payload behavior. The source row marks 3-party E2E as recommended, not required.
- `cannotSend` remains valid adjacent status vocabulary for secure-material failures, but the primary GM-036 proof intentionally uses `needsResend`/`send_failed` so the failed member is visibly repairable rather than silently stranded.
- Go `pubsub.go` and `group_inbox.go` remain inspect-only because GM-036 is about admin feedback for invite/key delivery, not group message recipient filtering.
- Closure/audit updates are deferred to the appropriate closure worker after execution evidence exists.

## dependency impact

GM-036 was the next unresolved P0 row when this plan was written; it is now accepted/closed. Accepted GM-036 evidence lets later GK rows proceed without carrying an open question about invite/key delivery feedback after re-add. If tests-only classification is disproved, later rows should not assume mixed re-add invite delivery is honest until a new code-and-tests plan closes the product gap.

## stop/replan conditions

- Replan as `needs_code_and_tests` if the exact GM-036 test shows the app returns a clean all-invited success despite D failure.
- Replan if D's failed attempt is not persisted, reloads as `unknown`, or cannot be made actionable through existing status/resend UI.
- Replan if local add/config success cannot be separated from invite/key delivery failure without production changes.
- Replan if the "Send" step clears or masks D's failed invite/key status.
- Stop if the only way to create mixed C/D failure is to alter production fake/service APIs outside tests.
- Stop if Go changes appear necessary; create a new code plan rather than smuggling Go work into this tests-only session.

## closure evidence requirements

The execution/closure record must include:

- Exact files touched.
- Exact GM-036 test names added.
- Direct selector outputs for every added GM-036 selector.
- Adjacent suggested suite outputs.
- `./scripts/run_test_gates.sh groups` result.
- `git diff --check` result.
- If any gate fails, the failing file/test and whether it is GM-036-caused.
- A final classification statement: `tests-only accepted` if no product code changed, or `replanned` if RED proved a product gap.

## reviewer findings

- Sufficiency: sufficient with the adjustment above.
- Missing files/tests/gates before the adjustment: the draft treated the final Send step as optional and allowed `cannotSend` as the primary D failure. That was too weak for a row about failed members not being silently stranded.
- Stale assumptions: none found after evidence review; the tests-only classification is still valid because existing product seams already support per-recipient statuses.
- Overengineering: none. The plan now uses row-named tests and existing status models rather than adding a new delivery subsystem.
- Decomposition: narrow enough for implementation. The executor can add three exact GM-036 proofs, stop on RED, and avoid adjacent GM/GK rows.
- Minimum needed: exact mixed C/D ContactPicker/API proof, exact Group Info reload/actionability proof, exact Send-step status-preservation proof, adjacent suggested suites, `groups`, and `git diff --check`.

## arbiter decision

- Structural blockers: none.
- Incremental details intentionally deferred: exact private fake class names and Dave/Charlie fixture names can be chosen during implementation; they must stay test-only and deterministic.
- Accepted differences: closure can be host/widget/API based because GM-036's 3-party E2E column is Recommended, not Required, and no real transport/product gap is proven at planning time.
- Final decision: execution-ready tests-only plan. Reclassify only if the required GM-036 RED proves product behavior is missing.
