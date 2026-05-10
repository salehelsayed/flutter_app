# Group Epoch Key Reliability Test Gaps Session Breakdown

## decomposition artifact

- Artifact path:
  `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`
- Supporting docs:
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
- Decomposition date:
  `2026-05-09`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must refresh against landed code, tests, and current key-repair evidence before execution
  - direct host tests may close repo-owned app-layer and Go-boundary gaps, but true paired-device or live relay evidence must use the explicit device/relay proof profile for that session
  - do not claim closure from sender-side success, fake plaintext delivery, or a single recipient when the source gap requires stale-recipient, conflicting-key, or all-eligible-recipient evidence

## downstream execution path

- Sessions should run, in breakdown order, through:
  1. `$implementation-plan-orchestrator`
  2. `$implementation-execution-qa-orchestrator`
  3. `$implementation-closure-audit-orchestrator`
- Run `GEK-005` only after `GEK-001` through `GEK-004` are accepted, marked stale/already-covered with concrete evidence, or truthfully blocked.
- After `GEK-005`, run the pipeline's final whole-program acceptance/closure pass and persist one final program verdict in this breakdown artifact.
- Allowed final program verdicts for this rollout are `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `still_open`.
- A verdict is not trustworthy while the source spec's reported split-delivery failure is covered only by isolated component evidence and no combined stale-key, durable replay, or user-visible degraded/repaired state proof.

## run-mode snapshot

- Snapshot refreshed:
  `2026-05-09`
- Active mode:
  `standard`
- Degraded local continuation:
  `not allowed by this run prompt`
- Source proposal/matrix/closure doc:
  `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`
- Source status vocabulary:
  the source doc is a spec rather than a row-status matrix. Session statuses use
  `pending`, `accepted`, `accepted_with_explicit_follow_up`,
  `stale/already-covered`, `skipped_due_to_dependency`,
  `prerequisite-blocked`, and `blocked`. Source gaps are resolved only by
  concrete code/test evidence recorded in this breakdown, the source spec,
  `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, and the applicable
  closure/gate docs.
- Overall closure bar:
  accepted eligible group members must not silently miss post-add or
  post-epoch-change group messages. The rollout must prove stale/missing keys,
  delayed key updates, same-epoch conflicts, and delayed membership/config
  propagation either repair into exactly-one visible plaintext or produce an
  explicit pending/unrecoverable state, while preserving no-backfill,
  removed-member exclusion, duplicate suppression, and current gate truth.
- Final verdict policy for this run:
  persist one final program verdict after all runnable sessions resolve:
  `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or
  `still_open`. Use `still_open` if a required app-layer, Go-boundary,
  simulator, or relay proof remains missing without a truthful blocker. Use
  `residual_only` only for a narrow device-lab residual after repo-owned tests
  and docs close the source behavior at host/Go boundaries.

## recommended plan count

- `5`
- The smallest safe split is:
  - `1` unit/app-layer session for stale older key updates and same-epoch conflicting key material
  - `1` combined listener/inbox session for live decrypt failure, pending repair, durable replay, and later key arrival
  - `1` rotation-race session for partial key-update delivery plus immediate post-rotation send
  - `1` membership/config propagation session for newly added senders and recipient eligibility boundaries
  - `1` final acceptance and gate/doc reconciliation session for simulator/real-network profile truth and final verdict
- Session disposition counts at decomposition time:
  - `implementation-ready`: `4`
  - `acceptance-only`: `1`
  - `stale/already-covered`: `0`
  - `blocked`: `0`

## overall closure bar

`Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md` cannot move
below `still_open` until all of the following are true at the same time:

- delayed older key updates cannot regress a recipient from the latest accepted epoch into an unreadable state, and different key material for the same generation cannot silently split recipients without a visible failure or rejection state
- a live `group:decryption_failed` diagnostic plus durable replay plus later key arrival produces one visible repaired message or one explicit unrecoverable placeholder, never a fake delivered plaintext row or a vanished row
- when one recipient misses a key update while another receives it, an immediate new-epoch send is either repaired through key arrival/durable recovery or exposed as pending/unrecoverable for the stale recipient
- delayed membership/config propagation for a newly added sender cannot permanently drop that sender's post-join message; after config catch-up and recovery, eligible recipients see the message exactly once or see a clear degraded state
- invite degradation remains truthful: a member whose invite was not delivered, stored, or accepted is not counted as a confirmed recipient who silently missed later messages
- existing no-backfill, removed-member exclusion, duplicate suppression, and group media/message gates remain green
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/test-gate-definitions.md`, this breakdown, and the source spec agree on what is covered, residual, and fixture-gated

## source of truth

Primary governing docs:

- `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Current repo facts that materially affected decomposition:

- `GroupKeyUpdateListener` already validates direct key updates, persists accepted keys, and invokes pending-key repair.
- `GroupMessageListener` already consumes `group:decryption_failed` diagnostics and can create pending key repair placeholders.
- `drainGroupOfflineInbox` already records pending key repairs for missing replay keys and can repair future-epoch replay after key arrival.
- Existing Go tests prove wrong-key decrypt diagnostics, key-rotation grace behavior, and validator rejection at the node boundary.
- Existing host/app tests prove send-time epoch snapshots, sequential epoch 2 then epoch 3 acceptance, pending receive-side key-update send behavior, and fake-network group onboarding/rejoin evidence.
- GEK-001 now proves the direct key-update listener and Go active-key boundary handle stale older updates without active promotion and reject/ignore same-generation conflicting material without replacing the accepted key. This closes only the direct listener/Go-boundary slice.
- GEK-002 now proves the host app-layer live decrypt diagnostic plus durable replay plus later key-arrival repair journey. Durable replay supersedes the synthetic no-envelope live placeholder, keeps the real replay `messageId` canonical, and repairs to exactly one visible plaintext row after key arrival. The older `PREREQ-GROUP-SYNC-RECEIPTS` fixed-date receipt fixture follow-up was closed during the GEK-005 recovery pass with deterministic retention clock control and full drain owner/broad group reruns.
- GEK-003 now proves the host app-layer partial key-update rotation race: Alice rotates to epoch 2, Bob receives and commits the key while Charlie remains stale, Bob sends immediately on epoch 2, Charlie records a live pending-key state, durable replay supersedes/converges to Bob's real message identity, and later key arrival repairs the message exactly once.
- GEK-004 now proves the host app-layer delayed membership/config replay ordering path: a newly accepted sender's signed durable message can be deferred on `unknown_sender`, retried after delayed `member_added` config catch-up, and delivered exactly once before cursor commit.
- GEK-005 final reconciliation reran on `2026-05-10`; the final program verdict is `residual_only` because all repo-owned host, Go, named-gate, completeness, whitespace, generated-artifact, and configured device/relay checks are green, while the remaining limitation is only the lack of an exact live three-party GEK stale-key/decrypt-repair split-delivery proof.

## session ledger

| Session ID | Source gap ownership | Classification | Intended plan file | Depends on | Current status | Closure result |
| --- | --- | --- | --- | --- | --- | --- |
| `GEK-001` | delayed older key updates; same-epoch conflicting key material | `implementation-ready` | `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-001-plan.md` | none | `accepted` | `closed` |
| `GEK-002` | live decrypt failure plus durable replay plus later key arrival repair | `implementation-ready` | `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-002-plan.md` | `GEK-001` if it changes key-conflict semantics | `accepted` | `closed` |
| `GEK-003` | partial key-update delivery plus immediate post-rotation send around commit boundary | `implementation-ready` | `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-003-plan.md` | `GEK-001`, `GEK-002` if they change repair semantics | `accepted` | `closed` |
| `GEK-004` | delayed membership/config propagation for newly added sender and invite eligibility truth | `implementation-ready` | `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-004-plan.md` | none | `accepted` | `closed` |
| `GEK-005` | final gate, simulator/relay profile, docs, and final verdict | `acceptance-only` | `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-005-plan.md` | `GEK-001`, `GEK-002`, `GEK-003`, `GEK-004` | `accepted` | `residual_only` |

## Closure Progress

- `2026-05-09T19:37:12Z` - GEK-001 closure audit started. Files inspected or targeted: `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-001-plan.md`, this breakdown, `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/test-gate-definitions.md`, `lib/features/groups/application/group_key_update_listener.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, and `go-mknoon/node/pubsub_key_rotation_grace_test.go`. Decision/blocker: audit is limited to GEK-001 and must not claim GEK-002 through GEK-005 closure or write a final program verdict. Next action: write session-scoped evidence into the breakdown/source/stable docs, then run a closure-review pass.
- `2026-05-09T19:39:15Z` - GEK-001 closure writing in progress after user-requested progress refresh. Files touched so far: this breakdown, `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`, and `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`. Decision/blocker: no blocker; ledger now marks only GEK-001 `accepted`/`closed`, later sessions are not claimed by this GEK-001 entry, and no final program verdict has been written. Next action: finish stable doc evidence updates, run closure-review checks, and append the final GEK-001 closure-progress entry.
- `2026-05-09T19:41:25Z` - GEK-001 closure review completed. Files touched by this closure pass: this breakdown, `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, and `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`; `Test-Flight-Improv/test-gate-definitions.md` was inspected but not changed because no named gate membership changed. Commands/results: `git diff --check` passed; review found only the standing final-verdict policy text and no written final program verdict. Decision/blocker: GEK-001 closure docs are accepted, later sessions are not claimed by this GEK-001 entry, and the pipeline must continue without any final program verdict.
- `2026-05-09T20:14:46Z` - GEK-002 closure audit started. Files inspected or targeted: `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-002-plan.md`, this breakdown, `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/test-gate-definitions.md`, `lib/features/groups/application/group_pending_key_repair_service.dart`, and `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Decision/blocker: audit is limited to GEK-002; later sessions must not be claimed by the GEK-002 closure and no final program verdict should be written. Next action: classify the GEK-002 execution evidence, then write only session-scoped closure updates.
- `2026-05-09T20:16:00Z` - GEK-002 completion audit completed and closure writing started. Files inspected or targeted: GEK-002 plan execution progress, landed production/test diff, source spec coverage/gap sections, inventory GEK/repair rows, closure reference residuals, and gate definitions. Decision/blocker: classify GEK-002 as `accepted_with_explicit_follow_up`; the combined live decrypt diagnostic plus durable replay plus later key-arrival repair path is accepted, while the older `PREREQ-GROUP-SYNC-RECEIPTS` fixed-date fixture failure remains a non-blocking follow-up outside GEK-002. Next action: update the ledger and stable docs without claiming GEK-003, GEK-004, GEK-005, or a final program verdict.
- `2026-05-09T20:18:13Z` - GEK-002 closure writing in progress after user-requested progress refresh. Files touched so far: this breakdown, `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, and `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`. Decision/blocker: no blocker; ledger now marks only GEK-002 `accepted_with_explicit_follow_up`, later sessions are not claimed by this GEK-002 entry, and no final program verdict has been written. Next action: finish doc consistency review, decide whether `Test-Flight-Improv/test-gate-definitions.md` needs any GEK-002 change, run diff checks, and append the final GEK-002 closure-review entry.
- `2026-05-09T20:19:15Z` - GEK-002 closure writing completed and closure review started. Files touched: this breakdown, `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, and `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`; `Test-Flight-Improv/test-gate-definitions.md` remains inspection-only because GEK-002 did not change named gate membership. Decision/blocker: no blocker; review is checking for stale GEK-002-open wording, accidental GEK-003/GEK-004/GEK-005 closure claims, and accidental final program verdict text. Next action: run closure-review searches plus `git diff --check`, then append the final GEK-002 review result.
- `2026-05-09T20:20:14Z` - GEK-002 closure review completed. Files touched by this closure pass: this breakdown, `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, and `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`; `Test-Flight-Improv/test-gate-definitions.md` was inspected but not changed by this GEK-002 closure because no named gate membership changed. Commands/results: closure-review search found only standing final-verdict policy text and historical GEK-001 progress notes, not a written final program verdict; `git diff --check` passed; trailing-whitespace search across the touched docs returned no matches. Decision/blocker: GEK-002 closure docs are accepted with explicit follow-up, later sessions are not claimed by this GEK-002 entry, and the pipeline must continue without a final program verdict.
- `2026-05-09T20:56:07Z` - GEK-003 closure audit and writing started. Files inspected or targeted: `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-003-plan.md`, this breakdown, `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/test-gate-definitions.md`, `lib/features/groups/application/group_pending_key_repair_service.dart`, and `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Decision/blocker: classify GEK-003 as `accepted`/`closed` for the deterministic host app-layer partial key-update rotation race only; preserve GEK-002's fixed-date receipt-fixture follow-up; do not claim later GEK-session closure from the GEK-003 entry and write no final program verdict.
- `2026-05-09T21:01:37Z` - GEK-003 closure review completed. Files touched by this closure pass: this breakdown, `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, and `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`; `Test-Flight-Improv/test-gate-definitions.md` was inspected but not changed because GEK-003 did not change named gate membership. Commands/results: `git diff --check` passed; targeted stale-open and overclaim searches found no current GEK-003-open claim and no written final program verdict beyond standing policy/guardrail text; trailing-whitespace search across the touched docs returned no matches. Decision/blocker: GEK-003 closure docs are accepted for GEK-003 only, later-session closure is not claimed by that entry, and no final whole-program verdict has been written.
- `2026-05-09T21:30:24Z` - GEK-004 closure audit started. Files inspected or targeted: `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-004-plan.md`, this breakdown, `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/test-gate-definitions.md`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, and `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Decision/blocker: classify GEK-004 from landed behavior, not plan intent; closure can cover only the host deterministic delayed membership/config durable replay recovery and invite-truth preservation selectors.
- `2026-05-09T21:31:40Z` - GEK-004 closure writing started. Files touched by this closure pass so far: this breakdown, `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, and `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`. Decision/blocker: no named gate membership changed, so `Test-Flight-Improv/test-gate-definitions.md` stays inspection-only; no final whole-program verdict should be written before GEK-005.
- `2026-05-09T21:39:20Z` - GEK-004 closure review completed. Files touched by this closure pass: this breakdown, `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, and `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`; `Test-Flight-Improv/test-gate-definitions.md` was inspected but not changed because GEK-004 did not change named gate membership. Commands/results: `git diff --check` passed; targeted stale-wording and overclaim searches were reviewed, with hits limited to the then-pending GEK-005 ledger/final-verdict policy or intentional unknown-sender guardrail text. Decision/blocker: closure docs are accepted for this session; at that point GEK-005 had not run yet and no final whole-program verdict had been written.
- `2026-05-10T00:10:03+02:00` - GEK-005 execution evidence completed and final reconciliation written. Files touched by this GEK-005 pass: `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-005-plan.md`, this breakdown, `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, and `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`; `Test-Flight-Improv/test-gate-definitions.md` was inspected through `completeness-check` and not changed. Commands/results: all 17 GEK-focused Dart selectors passed; full `group_key_update_listener_test.dart` and `group_message_listener_test.dart` passed; full `drain_group_offline_inbox_use_case_test.dart` failed only the exact preserved `PREREQ-GROUP-SYNC-RECEIPTS` fixed-date fixture cases; broad `flutter test --no-pub test/features/groups` failed two non-receipt `drain_followup_invariants_test.dart` assertions reproduced directly; focused and broad Go passed; `./scripts/run_test_gates.sh groups` passed; `./scripts/run_test_gates.sh completeness-check` passed with `730/730` files classified; `git diff --check` passed; device checks found both named iOS simulators booted and `adb` absent from PATH; configured single-device nightly passed self-contained without CLI peer fixture; paired iOS relay script passed MD-004 primary/sibling proof. Decision/blocker: GEK-005 is blocked by the non-receipt broad host failures, so the final program verdict is `still_open`.
- `2026-05-10T00:17:58+02:00` - GEK-005 QA review completed. Files reviewed: GEK-005 plan, this breakdown, source spec, inventory, closure reference, and `Test-Flight-Improv/test-gate-definitions.md` diff. Commands/results: `git diff --check` passed; targeted final-verdict, stale-wording, overclaim, preserved-follow-up, and blocker searches passed after a bounded stale-wording doc fix. `Test-Flight-Improv/test-gate-definitions.md` still has an unrelated pre-existing invite-status copy diff and was not edited by GEK-005. QA verdict: pass. Final program verdict remains `still_open`.
- `2026-05-09T22:37:28Z` - GEK-005 recovery pass closed the persisted `still_open` blockers. Files touched by this recovery pass: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `test/features/groups/application/drain_followup_invariants_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-005-plan.md`, this breakdown, the source spec, inventory, and closure reference. Commands/results: direct `drain_followup_invariants_test.dart` passed; direct `drain_group_offline_inbox_use_case_test.dart` passed; all 17 GEK-focused selectors passed; full key-update listener, full group-message listener, full drain owner, and broad `flutter test --no-pub test/features/groups` passed; focused and broad Go passed; `groups`, `completeness-check`, and `git diff --check` passed; the single-device real-network nightly passed self-contained and the paired iOS relay script ended `MD-004 proof completed successfully`. Generated tracked artifacts `go-mknoon/bin/testpeer` and `go-mknoon/testdata/interop_vectors.json` were restored after confirming they were generated by the Go/relay evidence runs. Decision/blocker: no repo-owned GEK-005 blocker remains; final program verdict is `residual_only`.

## final program verdict

Final program verdict: `residual_only`.

Reason: GEK-005 completed its recovery and final evidence sweep with no remaining host, Go, named-gate, completeness, whitespace, or generated-artifact blocker. The required broad `flutter test --no-pub test/features/groups` host command now passes, the direct `drain_followup_invariants_test.dart` rerun proves local-delivered receipt re-derivation plus malformed-envelope empty-drop flow logging, and the old `PREREQ-GROUP-SYNC-RECEIPTS` fixed-date receipt fixture follow-up is closed by deterministic retention clock control. Final Report 94 closure is still not overclaimed as `closed` because the available real-network evidence is supporting MD-004 device/relay proof, not an exact live three-party GEK stale-key/decrypt-repair split-delivery proof.

Accepted evidence remains stable for the GEK-owned seams: GEK-001 direct key-update monotonicity/conflict handling, GEK-002 live decrypt diagnostic plus durable replay plus key-arrival repair, GEK-003 partial key-update rotation race repair, and GEK-004 delayed membership/config catch-up all have green focused evidence. The GEK-002 receipt-fixture follow-up is now closed.

Device/relay classification: the required iOS simulator pair was available and the relay env was intentionally configured. The single-device nightly passed only as self-contained device smoke because no CLI peer fixture was present; the paired iOS script passed its MD-004 real-relay primary/sibling proof. These results support device/relay confidence but are not overclaimed as a full live three-party epoch-key split-delivery proof.

Next acceptable closure path: add or run an exact live three-party GEK stale-key/decrypt-repair split-delivery proof without weakening the host/Go acceptance contract, then update this verdict from `residual_only` to `closed` if that proof passes.

## ordered session breakdown

### Session GEK-001

- Title:
  `Key update monotonicity and same-epoch conflict handling`
- Session id:
  `GEK-001`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-001-plan.md`
- Exact scope:
  - prove delayed older key updates cannot roll a recipient back after a newer accepted generation
  - prove two different key materials for the same generation do not silently converge into split-brain group readability without a rejected, ignored, or explicit degraded state
  - adjust only the direct key-update receive path and local key persistence semantics if current behavior permits unsafe same-generation replacement
- Why it is its own session:
  the correctness rule for key update acceptance is independent of inbox replay, live decrypt diagnostics, and multi-user simulator orchestration; it must be pinned before later sessions rely on repair semantics.
- Likely code-entry files:
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/features/groups/application/group_pending_key_repair_service.dart`
  - `lib/features/groups/domain/repositories/group_repository.dart`
  - `lib/core/database/helpers/group_keys_db_helpers.dart`
  - `lib/core/bridge/go_bridge_client.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/group_key_update_listener_test.dart`
  - `test/core/database/helpers/group_keys_db_helpers_test.dart`
  - `test/features/groups/domain/repositories/group_repository_impl_test.dart`
  - `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- Likely named gates:
  - direct Flutter tests
  - `./scripts/run_test_gates.sh groups` if shared group behavior changes
  - `cd go-mknoon && go test ./node -run 'GroupTopicValidator|UpdateGroupKey|KeyRotation|Decryption' -count=1` if Go key state changes
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- Closure audit result:
  `closed` for GEK-001 only.
- Landed behavior:
  - `GroupKeyUpdateListener` now serializes direct key-update processing, verifies signed transition audit before acceptance, and checks existing key state before event-log append, `group:updateKey`, local key replacement, or pending-repair retry.
  - Delayed older key updates after a newer accepted generation may be saved only as non-promoting historical material; they do not call `group:updateKey`, do not change the latest active key, and do not retry pending repairs for the stale epoch.
  - Same-generation duplicate material is idempotent, while same-generation conflicting material is ignored before bridge promotion, event-log append, local replacement, or repair retry.
  - Go `Node.UpdateGroupKey` remains monotonic at the active key boundary and now has focused proof that same-epoch different material and older epochs preserve the current key, previous-key grace state, and grace deadline.
- Closure evidence:
  - focused GEK-001 Flutter red tests failed before the listener fix for the expected stale-older and same-generation conflict reasons
  - focused GEK-001 Flutter green tests passed after the listener fix
  - `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart` passed
  - `cd go-mknoon && go test ./node -run 'TestUpdateGroupKey_(PreservesPreviousKeyAndGraceDeadline|IgnoresSameEpochDifferentMaterial|IgnoresOlderEpochAfterCurrent)' -count=1` passed
  - `./scripts/run_test_gates.sh groups` passed
  - `git diff --check` passed
  - conditional persistence sweep skipped because no persistence helper or repository implementation files changed
- Accepted differences:
  Dart may keep non-conflicting historical older key material for replay while Go keeps the latest active key; this is accepted and is not a split-brain state as long as older material cannot promote or replace accepted same-generation material.
- Residual scope:
  GEK-002, GEK-003, and GEK-004 are recorded separately as `closed`.
  This GEK-001 closure does not itself claim decrypt-repair convergence, partial-recipient rotation-race recovery, delayed membership/config propagation, or final simulator/relay profile acceptance. GEK-005 records the final program verdict separately as `residual_only`.

### Session GEK-002

- Title:
  `Decrypt-failure placeholder to durable replay repair journey`
- Session id:
  `GEK-002`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-002-plan.md`
- Exact scope:
  - combine live `group:decryption_failed` handling, pending key repair placeholder creation, durable inbox replay, later key arrival, and final message visibility into one user-visible regression
  - assert no fake plaintext row is delivered on the failed live path
  - assert durable replay plus key arrival repairs the same message exactly once or records an explicit unrecoverable state
- Why it is its own session:
  this is the core silent-disappearance symptom and spans listener diagnostics plus inbox repair; it should land before broader rotation-race and simulator/gate acceptance work.
- Likely code-entry files:
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/application/group_pending_key_repair_service.dart`
  - `lib/features/groups/domain/models/group_pending_key_repair.dart`
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  - `go-mknoon/node/pubsub_decryption_failure_test.go`
- Likely direct tests/regressions:
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/domain/repositories/group_pending_key_repair_repository_impl_test.dart`
  - `test/features/groups/presentation/group_conversation_screen_test.dart`
  - `go-mknoon/node/pubsub_decryption_failure_test.go`
- Likely named gates:
  - direct Flutter tests
  - `./scripts/run_test_gates.sh groups` if listener or inbox behavior changes
  - `cd go-mknoon && go test ./node -run 'DecryptionFailed|KeyRotation|Group' -count=1` if Go diagnostics change
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- Dependency on earlier sessions:
  `GEK-001` only if it changes the same key-acceptance semantics used by repair.
- Closure audit result:
  `accepted_with_explicit_follow_up` for GEK-002 at original closure time; GEK-005 recovery later closed the explicit receipt-fixture follow-up.
- Landed behavior:
  - `queueMissingGroupReplayKeyRepairFromEnvelope` now supersedes matching pending no-envelope live diagnostic repairs for the same group, sender/transport peer, and key epoch when a durable replay repair becomes canonical.
  - Supersession deletes the synthetic live placeholder row, finalizes the live repair, and emits `GROUP_LIVE_DECRYPTION_REPAIR_SUPERSEDED`; the durable replay's real `messageId` remains the one pending/repaired visible row.
  - Live diagnostic-only failures still create the existing safe pending placeholder and repair request. GEK-002 only changes the convergence path when durable replay later arrives.
  - No Go diagnostics, relay APIs, persistence schema, membership policy, invite eligibility, or broad UI behavior changed.
- Closure evidence:
  - focused GEK-002 regression failed red first for the expected synthetic live placeholder/durable replay convergence issue
  - `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK002 live decrypt failure plus durable replay repairs one visible message after key arrival'` passed after the app-layer repair-service change
  - required focused prerequisite selectors 2 through 6 passed
  - `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart` passed
  - `./scripts/run_test_gates.sh groups` passed
  - `git diff --check` passed
- Explicit follow-up:
  - The original GEK-002 closure left older `PREREQ-GROUP-SYNC-RECEIPTS` receipt tests as a fixed-date fixture follow-up. GEK-005 recovery closed that follow-up with deterministic retention clock control in the drain tests and reran the full drain owner plus broad group host suites successfully.
- Accepted differences:
  - Live diagnostics remain less message-specific than durable replay because they intentionally avoid sensitive replay payload details.
  - Host-side app-layer proof is accepted for GEK-002's state-machine gap; GEK-005 final reconciliation is recorded above as `residual_only`.
- Residual scope:
  GEK-003 and GEK-004 are recorded separately as `closed`.
  This GEK-002 closure does not itself claim partial-recipient rotation-race recovery, delayed membership/config propagation, invite eligibility truth, or final simulator/relay profile acceptance. GEK-005 records the final program verdict separately as `residual_only`.

### Session GEK-003

- Title:
  `Partial key-update rotation race and immediate send recovery`
- Session id:
  `GEK-003`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-003-plan.md`
- Exact scope:
  - prove that when one eligible recipient misses a key update and another receives it, a new-epoch message sent around the rotation commit boundary does not silently disappear for the stale recipient
  - assert the stale recipient either repairs through later key arrival plus replay or retains an explicit pending/unrecoverable state
  - preserve sender-side epoch snapshotting and avoid weakening removed-member exclusion
- Why it is its own session:
  this is the source inventory's remaining combined race gap and needs different setup from the smaller listener/inbox repair proof.
- Likely code-entry files:
  - `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `test/shared/fakes/group_test_user.dart`
  - `test/shared/fakes/fake_group_pubsub_network.dart`
  - `integration_test/group_multi_device_real_harness.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `integration_test/group_multi_device_real_harness.dart` or a focused companion when device proof is available
- Likely named gates:
  - direct Flutter tests
  - `./scripts/run_test_gates.sh groups`
  - `FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relay1,relay2,...> ./scripts/run_test_gates.sh group-real-network-nightly` when the plan requires live paired proof
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- Dependency on earlier sessions:
  `GEK-001` and `GEK-002` if either changes the repaired-message or key-conflict contract.
- Closure audit result:
  `closed` for GEK-003 only.
- Landed behavior:
  - `queueMissingGroupReplayKeyRepairFromEnvelope` now derives the durable replay repair sender from the signed replay envelope's account sender (`senderPeerId`) and the transport identity from `senderTransportPeerId` before falling back to the relay `from` value.
  - Durable replay repairs created from a relay envelope whose `from` is a device transport id now still match the live diagnostic account sender identity, so stale-recipient repair can supersede/converge correctly after partial key-update delivery.
  - The focused GEK-003 regression proves Alice rotates to epoch 2, Bob receives and commits the key while Charlie remains on epoch 1, Bob sends immediately on epoch 2, Alice/current-key replay succeeds, Charlie records a live pending-key state, durable replay becomes canonical under Bob's real message id, later Charlie key arrival repairs to exactly one delivered plaintext row, and duplicate retry/replay does not create a second row.
  - No Go diagnostics, receipt semantics, membership/config propagation, invite eligibility policy, per-recipient ACKs, or final live relay/device acceptance behavior changed.
- Closure evidence:
  - `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK003 partial key-update delivery plus immediate post-rotation send repairs stale recipient after later key arrival'` passed.
  - Focused safety selectors passed for pending key-update sends, delayed older key updates, same-generation conflicts, send epoch binding, and the GEK-002 live diagnostic plus durable replay convergence contract.
  - `./scripts/run_test_gates.sh groups` passed (`103` tests).
  - `git diff --check` passed.
  - Conditional `./scripts/run_test_gates.sh completeness-check` was skipped because no `_test.dart` file was added, removed, or renamed.
  - QA verdict was `pass` with no blocking issues, no non-blocking follow-ups, and no fix loop.
- Accepted differences:
  - Host deterministic app-layer proof is accepted for GEK-003's partial-recipient rotation/send/repair state machine; GEK-005 final reconciliation is recorded above as `residual_only`.
  - The identity fix intentionally treats the signed replay account sender as canonical while retaining the replay transport identity for bridge replay/decrypt expectations.
  - Existing group `sent` status remains receipt-less and GEK-003 does not add per-recipient acknowledgement semantics.
- Residual scope:
  GEK-004 is recorded separately as `closed`.
  This GEK-003 closure does not claim delayed membership/config propagation, invite eligibility truth, final simulator/relay profile acceptance, or a final whole-program verdict. GEK-005 records the final program verdict separately as `residual_only`, and the old GEK-002 `PREREQ-GROUP-SYNC-RECEIPTS` fixed-date receipt fixture follow-up is closed.

### Session GEK-004

- Title:
  `Delayed membership/config propagation and invite eligibility truth`
- Session id:
  `GEK-004`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-004-plan.md`
- Exact scope:
  - prove a newly added accepted sender whose membership/config update arrives late does not have post-join messages permanently dropped
  - prove config catch-up plus durable recovery produces exactly-one visibility or an explicit unrecoverable state
  - preserve creator-side invite degradation truth so undelivered or unaccepted invitees are not treated as confirmed silent-miss recipients
- Why it is its own session:
  membership/config propagation has different owner files and policy boundaries from epoch-key repair, even though both can produce the same user-visible disappearance symptom.
- Likely code-entry files:
  - `lib/features/groups/application/create_group_with_members_use_case.dart`
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/send_group_invite_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/presentation/group_invite_status_presentation.dart`
  - `test/shared/fakes/fake_group_pubsub_network.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/create_group_with_members_use_case_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/send_group_invite_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/integration/invite_round_trip_test.dart`
- Likely named gates:
  - direct Flutter tests
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh completeness-check` if a new test file is added
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- Closure audit result:
  `closed` for GEK-004 only.
- Landed behavior:
  - Added the focused regression `GEK004 delayed membership config catch-up recovers newly accepted sender durable message exactly once` in the existing drain owner test file.
  - The initial GEK-004 selector failed red before production edits because signed durable replay for the newly accepted sender was rejected as `unknown_sender` and aborted the drain before the delayed `member_added` config replay could make the sender locally known.
  - `drainGroupOfflineInbox` now defers signed durable group-message replays rejected as `unknown_sender` within the page, processes membership/config/system replays, and retries the deferred messages before cursor commit.
  - Unresolved unknown senders still reject before cursor advancement, and live unknown-sender handling remains fail-closed.
  - No invite eligibility semantics, per-recipient acknowledgements, Go/native bridge behavior, final simulator/relay behavior, or broad group membership policy changed.
- Closure evidence:
  - `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK004 delayed membership config catch-up recovers newly accepted sender durable message exactly once'` passed after the drain fix and passed again in QA.
  - All required GEK-001, GEK-002, GEK-003, membership/config, and invite-truth focused selectors from the GEK-004 plan passed.
  - QA reran the GEK-002 and GEK-003 drain selectors because GEK-004 changed the drain seam; both passed.
  - `./scripts/run_test_gates.sh groups` passed.
  - `git diff --check` passed, including after the final GEK-004 plan update.
  - Conditional `./scripts/run_test_gates.sh completeness-check` was skipped because no `_test.dart` file was added, removed, or renamed.
- Accepted differences:
  - Host deterministic app-layer proof is accepted for GEK-004's delayed membership/config replay ordering gap; GEK-005 final reconciliation is recorded above as `residual_only`.
  - Invite eligibility truth is preserved by existing invite/status safety selectors rather than by new invite semantics in this session.
  - Existing group `sent` status remains receipt-less, and GEK-004 does not add per-recipient acknowledgement semantics.
- Residual scope:
  GEK-005 records the final source-spec verdict separately as `residual_only`. The old GEK-002 explicit follow-up for `PREREQ-GROUP-SYNC-RECEIPTS` fixed-date receipt fixtures is closed. This GEK-004 closure does not claim exact live three-party GEK split-delivery closure by itself.

### Session GEK-005

- Title:
  `Final epoch-key reliability acceptance, gate classification, and verdict`
- Session id:
  `GEK-005`
- Session classification:
  `acceptance-only`
- Intended plan file:
  `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-005-plan.md`
- Exact scope:
  - reconcile source spec gaps against landed `GEK-001` through `GEK-004` evidence
  - classify any new direct tests in `test-gate-definitions.md` and inventory docs
  - run the required direct suites, named gates, and device/relay proof profile or record the exact external fixture blocker
  - write the source spec and breakdown final state without overstating simulator or real-network evidence
- Why it is its own session:
  final acceptance depends on the accumulated evidence and should not be bundled into any individual implementation slice.
- Likely code-entry files:
  - none expected unless gate scripts require classification updates
  - `scripts/run_test_gates.sh` only if a new recurring gate member is intentionally added
- Likely direct tests/regressions:
  - direct suites added or changed by `GEK-001` through `GEK-004`
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh completeness-check`
  - `cd go-mknoon && go test ./...`
  - `flutter test --no-pub test/features/groups`
  - `FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relay1,relay2,...> ./scripts/run_test_gates.sh group-real-network-nightly` if live proof is required and devices/relays are available
- Likely named gates:
  - `groups`
  - `completeness-check`
  - `group-real-network-nightly` as fixture-gated supporting evidence when available
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`
  - `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-breakdown.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Dependency on earlier sessions:
  all prior runnable sessions.
- Device/Relay Proof Profile:
  - Profile type:
    `paired-device` or `three-party/device-lab` when live proof is required;
    host-only direct suites are sufficient only for repository-owned acceptance
    evidence and do not replace paired-device proof if the final closure claim
    says "live" or "three-party".
  - Live availability checks:
    `flutter devices --machine`; for iOS proof also run
    `xcrun simctl list devices available`; for Android paired proof also run
    `adb devices`.
  - Default configured iOS pair:
    `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` and
    `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
  - Default relay env:
    `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`
  - Closure evidence requirement:
    a single `FLUTTER_DEVICE_ID` run supports host/device regression confidence
    but does not by itself close a three-party or live paired-device claim.
    If required devices or relays are unavailable, record an
    `external-fixture-blocked` residual instead of overclaiming closure.
- Execution result:
  GEK-005 ran on `2026-05-10` and is `accepted`; the final program verdict is
  `residual_only`. Focused GEK selectors, full owner/broad host suites,
  focused/broad Go, named gates, completeness, hygiene, generated-artifact
  cleanup, and configured iOS relay evidence passed. The remaining limitation is
  only the absence of an exact live three-party GEK stale-key/decrypt-repair
  split-delivery proof.

## why this is not fewer sessions

- Same-epoch key conflict handling must be isolated because it can change core key acceptance semantics used by every later repair path.
- Decrypt-failure repair spans listener diagnostics, pending placeholder state, durable replay, and later key arrival; bundling it with rotation races would obscure whether the basic repair contract works.
- Partial key-update delivery around a rotation commit boundary requires different setup and acceptance criteria from a single stale-key replay repair.
- Membership/config propagation is a policy and eligibility problem, not just a cryptographic key problem; it needs invite-status and accepted-recipient truth to remain intact.
- Final gate/doc acceptance must run after the implementation sessions so it can truthfully classify host, Go, simulator, and relay evidence without prematurely closing live/device-lab residuals.
