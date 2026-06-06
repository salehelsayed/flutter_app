Status: reusable-breakdown

# Group Notification Highlight Double Card Session Breakdown

## Run Mode Snapshot

- Active mode: `standard`
- Degraded local continuation allowed: no
- Source proposal, matrix, or closure doc path: `Test-Flight-Improv/107-group-notification-highlight-double-card.md`
- Source row/status vocabulary: source doc uses test-case ids (`TC-107-*`) and acceptance evidence requirements rather than row-status fields; stable matrices use their own row status vocabulary and are updated only during `04-acceptance-closure` unless earlier sessions add gate classification changes.
- Overall closure bar: one logical incoming group delivery renders as one coherent group message row across live, replay, recovery, reload, reaction update, and notification-anchor entry; notification-targeted rows remain identifiable without adding a second card-like bordered surface; legitimate distinct same-content, same-timestamp stable-id sends remain distinct unless stronger same-logical-delivery evidence exists; interactions and readable dark/light backgrounds remain intact; final evidence explicitly covers `TC-107-R01`, `TC-107-R02`, and `TC-107-R08`.
- Final verdict policy: persist exactly one of `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `still_open` after all runnable sessions are resolved and final program acceptance runs; use `still_open` if any required session remains blocked, any required closure result is missing, or the overall closure bar is not met.

## Controller Progress

- 2026-06-05: Session `04-acceptance-closure` completed and the intended plan now records `Status: accepted_with_explicit_follow_up`. Final direct acceptance filters passed for receive convergence, listener replay notification suppression, signed drain convergence, single-row focus cue, notification-anchor reaction inspection, and `test/integration/group_notification_dedupe_integration_test.dart`. Source/stable docs now record Report 107 evidence and reopen rules. Final program verdict is `accepted_with_explicit_follow_up` only because provider-backed APNs/TestFlight or simulator notification-open visual proof was not run; the repo-owned `TC-107-R01`, `TC-107-R02`, and `TC-107-R08` closure is accepted.
- 2026-06-05: Post-doc session `04-acceptance-closure` sanity passed. `git diff --check` exited `0` with no output after source/stable/session docs were updated. Next action: final response with the accepted-with-explicit-follow-up doc verdict and exact tests/gates.
- 2026-06-05: Session `03-logical-delivery-row-convergence` completed and the intended plan now records `Status: accepted`. The receive handler now converges divergent stable-id deliveries only when they share the proven non-empty `logicalDeliveryId` under the same validated group/sender, enriches the canonical row, emits `GROUP_HANDLE_INCOMING_MSG_DUPLICATE` with `dedupeBy: logicalDeliveryId`, and preserves PGC-007 legitimate distinct stable-id sends. Focused handler/listener/drain/widget/wired tests, `./scripts/run_test_gates.sh groups` (`+321`), and `git diff --check` passed. Session `04-acceptance-closure` is now runnable and owns final source/stable documentation closure. Next action: create/update `Test-Flight-Improv/107-group-notification-highlight-double-card-session-04-acceptance-closure-plan.md`.
- 2026-06-05: Expanded-goal session `02-duplicate-row-identity-evidence` execution completed and the intended plan now records `Status: accepted` plus a proven nullable `logicalDeliveryId` identity contract. Focused persistence, receive/listener/replay, send/retry, full migration-chain, targeted Go bridge/pubsub tests, `./scripts/run_test_gates.sh groups` (`+321`), `./scripts/run_test_gates.sh completeness-check` (`769/769` classified), and `git diff --check` passed. Session `03-logical-delivery-row-convergence` is now runnable, but only against exact `messageId`, current `logicalMediaRetry`, legacy id-less content dedupe, or shared non-empty `logicalDeliveryId`; content-only convergence for stable-id rows remains forbidden. Next action: create/update `Test-Flight-Improv/107-group-notification-highlight-double-card-session-03-logical-delivery-row-convergence-plan.md`.
- 2026-06-05: Session `02-duplicate-row-identity-evidence` refreshed under the expanded goal after the spawned planner no-progressed at `planning-draft`; the bounded local plan fallback rewrote the existing intended plan path to `Status: execution-ready`. The new session-02 execution contract introduces a minimal durable sender-generated `logicalDeliveryId` identity signal for propagation/classification only, preserves PGC-007, forbids content-only convergence, and leaves row convergence to session `03` after tests prove the contract. Next action: spawn a fresh session-02 execution/QA child against `Test-Flight-Improv/107-group-notification-highlight-double-card-session-02-duplicate-row-identity-evidence-plan.md`.
- 2026-06-05: Session `02-duplicate-row-identity-evidence` reassessment/tightening completed after the plan was refreshed to current truth. The session `02` verdict remains `accepted_with_explicit_follow_up`; positive same-logical-delivery identity remains limited to exact raw `messageId`, current `logicalMediaRetry`, and legacy id-less content duplicates; no stronger identity exists for divergent stable-id text rows. Session `03-logical-delivery-row-convergence` remains `prerequisite-blocked`, session `04-acceptance-closure` remains `dependency-blocked`, and source/stable matrix closure was not updated.
- 2026-06-05: Final Program Acceptance completed in Step 11-only mode after ledger sanity against the test-case-id source vocabulary; the durable verdict is recorded in `## Final Program Acceptance / Closure` because session `03-logical-delivery-row-convergence` is `prerequisite-blocked`, session `04-acceptance-closure` is `dependency-blocked`, and the overall closure bar is not met. Only this breakdown artifact was updated; source and stable matrix closure remain owned by blocked session `04`.
- 2026-06-05: Session `02-duplicate-row-identity-evidence` closure completed; ledger now has sessions `01` and `02` as `accepted_with_explicit_follow_up`, session `03` as `prerequisite-blocked`, and session `04` as `dependency-blocked`. No later session is runnable because session `03` lacks a positive divergent stable-id logical-delivery identity contract; next action: spawn the required fresh final program acceptance/closure agent to persist the doc-level verdict.
- 2026-06-05: Session `02-duplicate-row-identity-evidence` execution completed and the intended plan now records `Status: accepted_with_explicit_follow_up` plus a `## Final Execution Verdict`; focused/direct receive-listener tests, `./scripts/run_test_gates.sh groups` with 321 tests, and `git diff --check` passed. The execution verdict establishes positive identity only for exact raw `messageId`, current `logicalMediaRetry`, and legacy id-less duplicates, and records an explicit prerequisite blocker for session `03-logical-delivery-row-convergence` because divergent stable-id text rows still lack stronger same-logical-delivery proof. Next action: fresh closure audit child for session 02.
- 2026-06-05: Session `02-duplicate-row-identity-evidence` planning completed via the allowed artifact-only local fallback after the spawned planner left the intended plan stale at `planning-intake`; `Test-Flight-Improv/107-group-notification-highlight-double-card-session-02-duplicate-row-identity-evidence-plan.md` now records `Status: execution-ready` and reclassifies the evidence-gated state into repo-owned diagnostic/test implementation work. Next action: dirty-worktree snapshot, then fresh execution/QA child for session 02.
- 2026-06-05: Session `02-duplicate-row-identity-evidence` selected as the next runnable session after session `01-notification-focus-cue` closure; dependency check passes because session 02 has no prerequisites and session 03 remains prerequisite-blocked until session 02 establishes a safe logical-delivery identity contract or records an explicit blocker. Next action: create/update the intended session 02 plan artifact and spawn a fresh planning child.
- 2026-06-05: Session `01-notification-focus-cue` execution finished with persisted verdict `accepted_with_explicit_follow_up`; scoped focus cue and tests landed, focused/direct session-owned checks and `./scripts/run_test_gates.sh groups` passed, with one unrelated pre-existing/full-wired send-refresh red test recorded in the session plan. Next action: fresh closure audit child for session 01.

## Closure Progress

- 2026-06-05: Session `04-acceptance-closure`; closure phase `Closure Writer complete`; docs inspected/updated: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-04-acceptance-closure-plan.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card.md`, `Test-Flight-Improv/52-notification-journey-test-matrix.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`; final verdict: `accepted_with_explicit_follow_up`; tests/gates: final direct acceptance filters passed and earlier required `groups`/`completeness-check` gates remain recorded in session plans; next action: post-doc `git diff --check` and final response.
- 2026-06-05: Session `04-acceptance-closure`; closure phase `Post-doc sanity`; docs inspected/updated: session `04` plan and breakdown; command/result: `git diff --check` -> exit `0` with no output; final verdict unchanged: `accepted_with_explicit_follow_up`; next action: final response.
- 2026-06-05: Session `02-duplicate-row-identity-evidence`; closure phase `Closure Reviewer complete - reassessment`; docs inspected: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-02-duplicate-row-identity-evidence-plan.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`; doc updated: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`; final verdict: `accepted_with_explicit_follow_up`; tests/gates: no new run required because no production or test code changed; next action: return the tightened closure state with session `03` still prerequisite-blocked and session `04` dependency-blocked.
- 2026-06-05: Session `02-duplicate-row-identity-evidence`; closure phase `Closure Writer - reassessment`; docs inspected: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-02-duplicate-row-identity-evidence-plan.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`; doc updated: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`; tentative verdict: `accepted_with_explicit_follow_up`; next action: update the breakdown only, leave source/stable matrix closure unclosed, and keep sessions `03`/`04` blocked.
- 2026-06-05: Session `02-duplicate-row-identity-evidence`; closure phase `Completion Auditor - reassessment`; docs inspected: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-02-duplicate-row-identity-evidence-plan.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`; doc updated: pending breakdown-only write; tentative verdict: `accepted_with_explicit_follow_up`; blocker: no independent canonical logical-delivery id, signed/envelope source identity, or equivalent raw delivery correlation exists for divergent stable-id text rows; content-only convergence remains forbidden and PGC-007 preservation remains mandatory.
- 2026-06-05: Session `02-duplicate-row-identity-evidence`; closure phase `Closure Reviewer complete`; docs inspected/updated so far: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-02-duplicate-row-identity-evidence-plan.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card.md`; final verdict: `accepted_with_explicit_follow_up`; next action: return closure result to the pipeline controller with session `03` still prerequisite-blocked and session `04` dependency-blocked.
- 2026-06-05: Session `02-duplicate-row-identity-evidence`; closure phase `Closure Writer`; docs inspected/updated so far: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-02-duplicate-row-identity-evidence-plan.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card.md`; tentative verdict: `accepted_with_explicit_follow_up`; next action: update session `02` ledger and keep sessions `03`/`04` dependency-blocked without running them.
- 2026-06-05: Session `02-duplicate-row-identity-evidence`; closure phase `Completion Auditor`; docs inspected/updated so far: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-02-duplicate-row-identity-evidence-plan.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card.md`; tentative verdict: `accepted_with_explicit_follow_up`; next action: write the session ledger with the positive exact-id/media-retry/id-less contract and the divergent stable-id blocker for session `03`.
- 2026-06-05: Session `01-notification-focus-cue`; closure phase `Completion Auditor`; docs inspected/updated so far: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-01-notification-focus-cue-plan.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card.md`; tentative verdict: pending evidence verification; next action: verify scoped diff, on-disk final execution verdict, and recorded test/gate evidence before updating the session ledger.
- 2026-06-05: Session `01-notification-focus-cue`; closure phase `Closure Writer`; docs inspected/updated so far: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-01-notification-focus-cue-plan.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card.md`; tentative verdict: `accepted_with_explicit_follow_up`; next action: update only the breakdown session ledger with session 01 closure status and preserve the unrelated send-refresh wired red test as non-blocking follow-up.
- 2026-06-05: Session `01-notification-focus-cue`; closure phase `Closure Reviewer`; docs inspected/updated so far: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-01-notification-focus-cue-plan.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card.md`; tentative verdict: `accepted_with_explicit_follow_up`; next action: review the ledger update against the scoped diff, final execution verdict, and session-04 documentation boundary.
- 2026-06-05: Session `01-notification-focus-cue`; closure phase `Closure Reviewer complete`; docs inspected/updated so far: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-01-notification-focus-cue-plan.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card.md`; final verdict: `accepted_with_explicit_follow_up`; next action: return closure result to the pipeline controller for the next session decision.

## Recommended plan count

4 session plans.

## Decomposition artifact

- Artifact path: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`
- Proposal or source doc path: `Test-Flight-Improv/107-group-notification-highlight-double-card.md`
- Downstream workflow rule: detailed planning happens one session at a time.
- Refresh rule: later sessions must be refreshed against landed code before execution. This matters especially for `03-logical-delivery-row-convergence`, because it must use the logical-delivery identity evidence produced by `02-duplicate-row-identity-evidence` rather than inventing a blanket same-content dedupe rule.

## Overall closure bar

After all sessions finish, one logical incoming group delivery must render as one coherent group message row across live, replay, recovery, reload, reaction update, and notification-anchor entry. A notification-targeted row must remain identifiable without adding a second card-like bordered surface. Legitimate distinct same-content, same-timestamp stable-id sends remain distinct unless stronger same-logical-delivery evidence exists. Long-press actions, swipe-to-reply, quote previews, reaction inspection, media taps, and normal group entry remain intact. Final evidence must explicitly cover `TC-107-R01`, `TC-107-R02`, and `TC-107-R08`, plus dark and light readable-background visual confidence.

## Source of truth

- Product intent: `Test-Flight-Improv/107-group-notification-highlight-double-card.md`
- Adjacent investigation: `Test-Flight-Improv/Group-Chat-Feature/double-stacked-message-cards-investigation-2026-06-04.md`
- Regression model: `Test-Flight-Improv/14-regression-test-strategy.md`
- Named gates: `Test-Flight-Improv/test-gate-definitions.md`
- Current compact test map: `Test-Flight-Improv/_current-test-map.md`
- Stable notification matrix: `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- Stable group matrix and closure docs: `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- Receive/dedupe files inspected: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/core/bridge/bridge_group_helpers.dart`, `go-mknoon/node/pubsub.go`
- Persistence files inspected: `lib/core/database/migrations/018_group_messages_tables.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- UI files inspected: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/domain/utils/group_message_ordering.dart`, `lib/features/conversation/presentation/widgets/letter_card.dart`, `lib/features/feed/presentation/widgets/swipe_to_quote_bubble.dart`, `lib/main.dart`
- Direct tests inspected or identified: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`

## Session ledger

| Session id | Title | Classification | Plan path | Depends on | Current status | Final execution verdict | Closure docs touched | Blocker class | Note |
|---|---|---|---|---|---|---|---|---|---|
| `01-notification-focus-cue` | Replace card-like group notification focus with a polished single-row cue | `implementation-ready` | `Test-Flight-Improv/107-group-notification-highlight-double-card-session-01-notification-focus-cue-plan.md` | none | `accepted_with_explicit_follow_up` | `accepted_with_explicit_follow_up` | `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md` updated; session plan and source doc inspected; stable matrices/source-doc closure rows intentionally untouched for session `04-acceptance-closure` | none | Scoped focus cue landed as a keyed single-row `Stack`/accent rail, focused/direct session-owned coverage and `./scripts/run_test_gates.sh groups` passed, and the unrelated full-wired send-refresh red test remains a non-blocking follow-up. |
| `02-duplicate-row-identity-evidence` | Establish duplicate-row diagnostic evidence and a safe logical-delivery identity contract | `evidence-gated` | `Test-Flight-Improv/107-group-notification-highlight-double-card-session-02-duplicate-row-identity-evidence-plan.md` | none | `accepted` | `accepted` | `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md` updated; session plan updated to accepted; stable matrices/source-doc closure intentionally deferred to session `04-acceptance-closure` | none | Expanded-goal execution introduced and proved a nullable repo-owned `logicalDeliveryId` contract across persistence, live listener, signed offline replay/drain, send/retry, Go bridge/pubsub extras, reload row loading, and notification-anchor row loading. Focused tests, full migration chain, targeted Go tests, `groups`, `completeness-check`, and `git diff --check` passed. Session `03` may now use this shared non-empty identity but still must not collapse stable-id rows by content/timestamp alone. |
| `03-logical-delivery-row-convergence` | Converge proven duplicate logical deliveries without collapsing legitimate stable-id sends | `implementation-ready` | `Test-Flight-Improv/107-group-notification-highlight-double-card-session-03-logical-delivery-row-convergence-plan.md` | `02-duplicate-row-identity-evidence` | `accepted` | `accepted` | `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md` updated; stable matrices/source-doc closure intentionally deferred to session `04-acceptance-closure` | none | Shared non-empty `logicalDeliveryId` now converges divergent stable-id logical deliveries to one canonical row after validation, with quote/media enrichment and duplicate diagnostics. PGC-007 distinct stable-id rows without shared logical identity remain distinct. Focused receive/listener/drain/widget/wired tests, `groups`, and `git diff --check` passed. |
| `04-acceptance-closure` | Validate the full double-card journey and update stable matrices/docs | `acceptance-only` | `Test-Flight-Improv/107-group-notification-highlight-double-card-session-04-acceptance-closure-plan.md` | `01-notification-focus-cue`, `02-duplicate-row-identity-evidence`, `03-logical-delivery-row-convergence` | `accepted_with_explicit_follow_up` | `accepted_with_explicit_follow_up` | Source doc, notification journey matrix, full group matrix, in-scope gap matrix, group reliability closure reference, session plan, and breakdown updated | none | Final direct acceptance filters passed for `TC-107-R01`, `TC-107-R02`, and `TC-107-R08`; source/stable docs record Report 107 evidence and reopen rules. Provider APNs/TestFlight or simulator visual proof remains explicit follow-up. |

## Final Program Acceptance / Closure

- Persisted final program verdict: `accepted_with_explicit_follow_up`
- Ledger sanity: source doc uses test-case ids (`TC-107-*`) and acceptance evidence requirements, not row-status fields. Stable source/matrix/reliability docs were updated by session `04-acceptance-closure`.
- Current status: session `01` is `accepted_with_explicit_follow_up`; sessions `02` and `03` are `accepted`; session `04` is `accepted_with_explicit_follow_up`; no runnable session remains blocked.
- Closed source test cases: `TC-107-R01` is accepted for shared non-empty `logicalDeliveryId` convergence across receive/listener/replay/drain and reload/anchor-preserving persistence; `TC-107-R02` is accepted for single-row notification focus without a second card-like wrapper; `TC-107-R08` is accepted as preserved because PGC-007 stable-id rows without shared logical identity remain distinct.
- Explicit follow-up: provider-backed APNs/TestFlight or simulator notification-open visual proof was not run. No provider/device route/focus regression is known; this remains a confidence follow-up, not a repo-owned blocker.
- Docs updated in this pass: `Test-Flight-Improv/107-group-notification-highlight-double-card.md`, `Test-Flight-Improv/52-notification-journey-test-matrix.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card-session-04-acceptance-closure-plan.md`, and this breakdown.
- Accepted tests/gates: session `01` recorded focused highlight/wired checks, full group conversation screen suite, `./scripts/run_test_gates.sh groups` (`+321`), and `git diff --check`; session `02` recorded focused persistence/receive/listener/replay/send/retry/migration tests, targeted Go bridge/pubsub tests, full migration chain, `./scripts/run_test_gates.sh groups` (`+321`), `./scripts/run_test_gates.sh completeness-check` (`769/769`), and `git diff --check`; session `03` recorded focused receive/listener/drain/widget/wired convergence tests, `./scripts/run_test_gates.sh groups` (`+321`), and `git diff --check`; session `04` recorded the final direct acceptance filters and `test/integration/group_notification_dedupe_integration_test.dart`.

## Ordered session breakdown

### 1. Replace card-like group notification focus with a polished single-row cue

- Session id: `01-notification-focus-cue`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-01-notification-focus-cue-plan.md`
- Exact scope: Change the group notification-anchor focus treatment so a targeted message is identifiable without wrapping the normal `LetterCard` in another full rounded bordered card. Preserve one-target-only highlighting, scroll/anchor behavior, long-press context actions, reaction chip inspection, quote previews, swipe-to-reply resting state, media inspectability, and normal entry with no `highlightedMessageId`.
- Why it is its own session: This is a deterministic presentation seam with existing route-anchor tests. It can be fixed and verified independently from the unresolved duplicate-row identity question.
- Likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/widgets/letter_card.dart` only if the shared card needs a tiny focus affordance hook, `lib/main.dart` only if anchor state threading changes.
- Likely direct tests/regressions: `test/features/groups/presentation/group_conversation_wired_test.dart` for notification-anchor target, one-target-only behavior, long-press actions, and reaction inspection; `test/features/groups/presentation/group_conversation_screen_test.dart` for highlighted incoming/outgoing text, quoted, media, reaction-bearing, dark/readable and light/readable backgrounds, and no-highlight normal entry. Existing `grp-highlight-*` assertions should be tightened so they prove a non-card-like focus cue rather than just the wrapper key.
- Likely named gates: focused widget tests first; `./scripts/run_test_gates.sh groups` because the group conversation surface changes; `./scripts/run_test_gates.sh baseline` if notification route/open wiring is touched; `./scripts/run_test_gates.sh completeness-check` if new test files are added.
- Matrix/closure docs to update when done: defer stable matrix and closure doc updates to `04-acceptance-closure`; update `Test-Flight-Improv/test-gate-definitions.md` immediately only if new test files require classification.
- Dependency on earlier sessions: none.

### 2. Establish duplicate-row diagnostic evidence and a safe logical-delivery identity contract

- Session id: `02-duplicate-row-identity-evidence`
- Session classification: `evidence-gated`
- Intended plan file: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-02-duplicate-row-identity-evidence-plan.md`
- Exact scope: Produce regression-first evidence that distinguishes two persisted rows from one highlighted row, then define the minimum safe identity evidence for "same logical delivery under divergent ids." Required diagnostics include local row ids, group id, sender id, text, timestamp, created-at, incoming flag, reaction target id when present, `GROUP_HANDLE_INCOMING_MSG_SUCCESS` count, `GROUP_HANDLE_INCOMING_MSG_DUPLICATE` `dedupeBy` values, and raw live/replay `messageId` values when available. Preserve PGC-007 and legacy id-less content dedupe as explicit negative controls.
- Why it is its own session: The source doc and investigation both reject blanket content-based dedupe for stable-id messages. Before any data fix, the repo needs a stronger same-logical-delivery rule or a recorded blocker explaining why the duplicate-row path cannot be safely implemented yet.
- Likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/core/bridge/bridge_group_helpers.dart`, `go-mknoon/node/pubsub.go` if raw id propagation needs diagnostic proof.
- Likely direct tests/regressions: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` for PGC-007 preservation, legacy id-less duplicate suppression, divergent-id negative/positive identity cases, and diagnostic flow events; `test/features/groups/application/group_message_listener_test.dart` for live/replay source classification and id-less queue behavior if used as evidence; `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` for replay payload id extraction; `test/features/groups/integration/group_resume_recovery_test.dart` only if a fake-network live/replay convergence harness is needed.
- Likely named gates: focused application tests first; `./scripts/run_test_gates.sh groups` if group receive/listener behavior or test harnesses change; Go targeted tests if native id propagation is touched; `./scripts/run_test_gates.sh completeness-check` if new test files are added.
- Matrix/closure docs to update when done: defer final matrix closure to `04-acceptance-closure`; record only immediate gate classification changes in `Test-Flight-Improv/test-gate-definitions.md` if new files are introduced.
- Dependency on earlier sessions: none.

### 3. Converge proven duplicate logical deliveries without collapsing legitimate stable-id sends

- Session id: `03-logical-delivery-row-convergence`
- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-03-logical-delivery-row-convergence-plan.md`
- Exact scope: Implement the duplicate-row fix only after `02-duplicate-row-identity-evidence` lands a safe logical-delivery contract. The implementation must converge one logical incoming delivery to one persisted/user-visible row across live, replay, recovery, reload, timeline ordering, and reaction update. It must preserve PGC-007 distinct stable-id sends, legacy id-less duplicate suppression, media retry canonicalization, id-based dedupe, sender/self-delivery behavior, local deletion boundaries, and reaction coherence. Id-less race hardening belongs here only if session `02` proves it is part of the accepted identity or defense-in-depth contract.
- Why it is its own session: This is the core receive/persistence correctness seam. It should not be bundled with evidence collection because the safe identity rule is the high-risk unknown, and it should not be bundled with notification-focus UI because it needs different direct tests and named gates.
- Likely code-entry files: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, optional migration files under `lib/core/database/migrations/` only if downstream planning chooses a DB defense that is compatible with PGC-007.
- Likely direct tests/regressions: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` for logical duplicate convergence and PGC-007 preservation; `test/features/groups/application/group_message_listener_test.dart` for live/replay convergence and notification non-duplication; `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` for replay/reload convergence; `test/features/groups/integration/group_resume_recovery_test.dart` for live/replay/recovery user-visible convergence; `test/features/groups/presentation/group_conversation_wired_test.dart` or `group_conversation_screen_test.dart` for duplicate-looking rows with reaction state on one source id rendering as one coherent row after data convergence.
- Likely named gates: focused receive/persistence suites first; `./scripts/run_test_gates.sh groups`; direct notification dedupe suites if listener notification behavior changes; `./scripts/run_test_gates.sh baseline` after stable group behavior lands; `./scripts/run_test_gates.sh completeness-check` if new files are added. Run SQLite migration tests if a migration is added.
- Matrix/closure docs to update when done: defer durable docs to `04-acceptance-closure`; update gate definitions immediately only for new file classification.
- Dependency on earlier sessions: depends on `02-duplicate-row-identity-evidence`.

### 4. Validate the full double-card journey and update stable matrices/docs

- Session id: `04-acceptance-closure`
- Session classification: `acceptance-only`
- Intended plan file: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-04-acceptance-closure-plan.md`
- Exact scope: Validate that both reported double-card categories are closed together: notification-anchor focus no longer resembles a second card, and proven duplicate logical deliveries no longer survive as two visible/persisted rows. Include dark and light readable backgrounds, targeted incoming/outgoing text, targeted quote, targeted media, targeted reaction-bearing row, duplicate-looking incoming text with reaction state attached to one source id, normal entry without highlight, live/replay/recovery convergence, reload, and notification-open route behavior. Update stable matrices and closure docs with final evidence and any explicit residuals.
- Why it is its own session: This session validates multiple earlier seams together and owns documentation closure. It should not run before sessions `01` and `03`, because otherwise it would either duplicate direct tests or produce predictable failures.
- Likely code-entry files: primarily test harnesses and docs. Candidate files include `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/integration/group_notification_dedupe_integration_test.dart`, `integration_test/notification_open_ui_smoke_test.dart`, notification-open simulator scripts if used, and the stable docs named below.
- Likely direct tests/regressions: final focused widget/application/integration bundle for `TC-107-R01`, `TC-107-R02`, and `TC-107-R08`; direct reaction inspection and long-press preservation; direct or simulator notification-open proof; visual/screenshot or widget-level evidence across dark and light readable backgrounds.
- Likely named gates: `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh baseline` if notification route/open wiring or shared startup behavior changed, `./scripts/run_test_gates.sh completeness-check`, direct notification suites from `_current-test-map.md`, and optional/nightly simulator commands only when the acceptance plan chooses device-backed notification proof.
- Matrix/closure docs to update when done: `Test-Flight-Improv/52-notification-journey-test-matrix.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/_current-test-map.md` if new direct coverage should be discoverable, `Test-Flight-Improv/test-gate-definitions.md` if gate classification changes, and the source doc if closure evidence is recorded there by the downstream closure workflow.
- Dependency on earlier sessions: depends on `01-notification-focus-cue`, `02-duplicate-row-identity-evidence`, and `03-logical-delivery-row-convergence`.

## Why this is not fewer sessions

The repeatable notification-focus artifact and the duplicate-persisted-row path have different owners, tests, and closure bars. The focus issue is a presentation problem around `highlightedMessageId`; the data issue is receive/persistence correctness with a known PGC-007 preservation risk. Collapsing the evidence-gated identity work into the data fix would invite a blanket same-content dedupe implementation before the repo proves a safe same-logical-delivery rule. Collapsing final acceptance into either implementation session would hide cross-seam failures such as reaction state coherence, reload behavior, or dark/light visual regressions.

## Why this is not more sessions

The source doc lists many test cases, but most are variants inside the same four seams. Incoming/outgoing text, quote, media, reaction, long-press, and swipe-to-reply are presentation variants for `01` and acceptance variants for `04`, not separate plans. Live, replay, recovery, reload, and reaction update are data-convergence test cases for `03`, not separate architectural layers unless `02` discovers a new root cause that requires a later split. DB defense-in-depth, id-less queue hardening, and diagnostic flow events should stay in the data/evidence sessions unless planning proves they have independent blast radius.

## Regression and gate contract

`Test-Flight-Improv/14-regression-test-strategy.md` applies because this is a production bug-shaped report: add focused permanent regressions first, then run change-based gates for touched group, notification, and persistence seams. `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` are the named-gate source of truth.

- `01-notification-focus-cue`: run focused group conversation widget/wired tests first; run `./scripts/run_test_gates.sh groups`; run `baseline` only if notification route/open or app-root wiring changes; run `completeness-check` if new files are added.
- `02-duplicate-row-identity-evidence`: run focused receive/listener/replay diagnostics and preservation tests; run `./scripts/run_test_gates.sh groups` if receive/listener harnesses change; run targeted Go tests only if native raw id propagation changes; run `completeness-check` if new files are added.
- `03-logical-delivery-row-convergence`: run focused receive/persistence/replay/reaction-convergence tests, then `./scripts/run_test_gates.sh groups`; run direct group notification dedupe tests if listener notification behavior changes; run `baseline` after stable group behavior if shared startup/route behavior was touched; run migration tests if DB schema changes.
- `04-acceptance-closure`: run the final direct widget/application/integration bundle, `groups`, `completeness-check`, and any direct notification/simulator commands selected by the acceptance plan. Record unrelated red tests honestly rather than hiding them.

## Matrix update contract

Reuse existing stable docs; do not create a new matrix doc for this report.

- `Test-Flight-Improv/52-notification-journey-test-matrix.md`: update group notification-open and replay/materialization rows if final evidence changes GMN/route-anchor confidence.
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`: update exactly-once display, duplicate-path dedupe, replay protection, notification deep-link, and related UX rows with final evidence.
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`: update only if this report changes a row that is tracked as in-scope closure or residual status.
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`: record final group discussion duplicate-row/focus closure evidence if accepted.
- `Test-Flight-Improv/_current-test-map.md`: add a compact discoverability note only if new permanent direct tests land outside existing rows.
- `Test-Flight-Improv/test-gate-definitions.md`: update only for new test-file classification or gate membership changes.
- Closure responsibility belongs to `04-acceptance-closure`.

## Downstream execution path

| Session id | Next downstream path |
|---|---|
| `01-notification-focus-cue` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| `02-duplicate-row-identity-evidence` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| `03-logical-delivery-row-convergence` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` after `02-duplicate-row-identity-evidence` resolves the prerequisite |
| `04-acceptance-closure` | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |

## Structural blockers remaining

None. The original session `03-logical-delivery-row-convergence` prerequisite was resolved when session `02` proved the shared non-empty `logicalDeliveryId` identity contract; session `03` and session `04` then completed under that contract. Content-only convergence for stable-id rows remains forbidden.

## Manual follow-up closure - 2026-06-05

- Final program verdict remains `accepted_with_explicit_follow_up`: the deterministic repo-owned closure is green, while a fresh provider-backed APNs/TestFlight visual pass remains complementary confidence evidence.
- Follow-up regression closed: the APNs-open path now records the remote group target as a recent announcement before inbox drain, preventing the second local notification for the same logical group message.
- Follow-up routing closed: tapping the same active group notification no longer pushes another `GroupConversationWired` route on top of the current group conversation.
- Preview parity closed at the deterministic seams: encrypted group replay payloads include `groupName`, iOS Notification Service Extension and Dart decrypt preview use it as the group notification title, and relay-visible payloads still omit plaintext preview fields.
- Required follow-up evidence passed: focused notification/push/group tests (`+25`, `+3`, `+3`, `+4`), iOS `NotificationPreviewResolverTests` via `build-for-testing` and `test-without-building` on existing iPhone 17 `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, `./scripts/run_test_gates.sh groups` (`+321`), and `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh baseline` (host `+100`, loading-states integration `+7`, posts integration `+1`).
- Non-result recorded: the first unpinned `./scripts/run_test_gates.sh baseline` invocation passed host tests but exited at device selection because multiple devices were connected and no `FLUTTER_DEVICE_ID` was specified; the pinned rerun passed.

## Accepted differences intentionally left unchanged

- Exact visual language for the notification focus cue is a downstream design/implementation choice, as long as it avoids a second card-like surface and preserves readability/interactions.
- The exact divergent-id trigger is not assumed from static analysis. Session `02` must prove or block the safe identity rule before session `03` changes row convergence.
- No blanket collapse of same-content, same-timestamp stable-id rows is authorized by this decomposition.
- No broad redesign of group cards, feed cards, background themes, notification payload contracts, or group transport is included.
- Provider-backed APNs/TestFlight proof is complementary unless the downstream acceptance plan explicitly scopes it; repo-owned direct, smoke, integration, and optional simulator evidence are the required closure layer.

## Exact docs/files used as evidence

- `Test-Flight-Improv/107-group-notification-highlight-double-card.md`
- `Test-Flight-Improv/Group-Chat-Feature/double-stacked-message-cards-investigation-2026-06-04.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/_current-test-map.md`
- `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `go-mknoon/node/pubsub.go`
- `lib/core/database/migrations/018_group_messages_tables.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/domain/utils/group_message_ordering.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/feed/presentation/widgets/swipe_to_quote_bubble.dart`
- `lib/main.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/integration/group_notification_dedupe_integration_test.dart`

## Why the decomposition is safe to send into downstream planning/execution

Each session has a doc-scoped, non-colliding intended plan path and ends in a meaningful verified state. The split follows current code boundaries instead of the screenshot narrative alone: deterministic notification focus, duplicate-row evidence/identity, receive/persistence convergence, and final acceptance/closure are independently testable while preserving the required ordering. The data fix cannot run before the identity evidence session, so downstream planning is protected from the main overreach risk called out by the source doc: collapsing legitimate PGC-007 stable-id messages with a broad content-only rule.
