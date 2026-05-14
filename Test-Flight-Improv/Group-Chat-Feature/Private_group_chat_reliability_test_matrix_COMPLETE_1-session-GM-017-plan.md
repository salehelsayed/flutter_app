# GM-017 Removed Member Stale Subscription Validator Backstop Plan

Status: accepted by execution QA; closed by closure audit

## Planning Progress

- 2026-05-11 04:25:44 CEST | Role: Arbiter completed | Files inspected since last update: reviewer findings; adjusted mandatory sections; exact gates; scope guard; known-failure interpretation | Decision/blocker: No structural blockers remain. Reviewer adjustments are incorporated, accepted differences are documented, and GM-017 is execution-ready. | Next action: Execute this plan in a later implementation session without editing source matrix or breakdown as part of planning.
- 2026-05-11 04:25:18 CEST | Role: Arbiter started | Files inspected since last update: reviewer findings and adjusted exact tests/gates | Decision/blocker: Arbiter is classifying reviewer findings; no structural blocker identified so far. | Next action: Record final arbiter decision and set final status if safe.
- 2026-05-11 04:24:43 CEST | Role: Reviewer completed | Files inspected since last update: full draft plan; mandatory-section inventory; exact test/gate section | Decision/blocker: Plan is sufficient with adjustments applied. Added explicit targeted analyzer coverage and conditional real-crypto onboarding command; no structural blocker remains for arbiter review. | Next action: Start Arbiter and classify reviewer findings as structural blockers, incremental details, or accepted differences.
- 2026-05-11 04:23:53 CEST | Role: Reviewer started | Files inspected since last update: full draft section inventory | Decision/blocker: Reviewer is checking mandatory-section completeness, command correctness, proof sufficiency, and over-scope risk; no blocker yet. | Next action: Produce sufficiency findings and required adjustments if any.
- 2026-05-11 04:21:46 CEST | Role: Planner completed | Files inspected since last update: evidence notes above | Decision/blocker: Drafted a narrow implementation-ready GM-017 plan with regression-first Go validator proof, Flutter/harness proof expansion, exact gates, and simulator infrastructure recovery guidance; no blocker. | Next action: Start Reviewer and check for missing source of truth, proof commands, scope guard, and stale assumptions.

## Execution Progress

- 2026-05-11 04:27:53 CEST | Phase: Contract extraction started | Files inspected/touched: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-017-plan.md`, `git status --short`; touched this progress section only | Command: `sed -n '1,260p' ...GM-017-plan.md`, `git status --short` | Decision/blocker: Nested Executor/QA spawn tools are not available in the current toolset, so this isolated execution will use the skill's local sequential fallback and record that explicitly; no contract blocker found yet. | Next action: Finish extracting scope, gates, code-entry files, and exact acceptance criteria before Executor work.
- 2026-05-11 04:29:26 CEST | Phase: Contract extracted / local Executor starting | Files inspected/touched: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_delivery_test.go`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/shared/fakes/group_test_user.dart`, `test/shared/fakes/fake_group_pubsub_network.dart`; touched this progress section only | Command: `rg -n 'GM-017|gm017|validation_rejected|scenario' ...`, targeted `sed` reads, `git diff -- ...` | Decision/blocker: Scope is GM-017 only: add row-owned Go validator proof, GM-017 criteria/runner/harness support, focused Flutter support tests where applicable, exact simulator proof, targeted analyzer, groups/completeness gates, `git diff --check`; do not edit source matrix/session breakdown. Go production change is conditional on the regression failing. | Next action: Add the focused Go regression before any production code changes.
- 2026-05-11 04:30:43 CEST | Phase: Local Executor Go regression added / focused Go proof starting | Files inspected/touched: `go-mknoon/node/pubsub_delivery_test.go`; touched GM-017 plan progress | Command: `gofmt -w go-mknoon/node/pubsub_delivery_test.go`; next `(cd go-mknoon && go test ./node -run '^TestGM017RemovedMemberWithStaleSubscriptionRejectedByRemainingValidators$' -count=1)` | Decision/blocker: Added row-owned test that keeps Charlie joined locally, updates only A/B config without Charlie, requires A/B validation rejection and no stale plaintext, then proves A/B healthy delivery. | Next action: Run the focused Go regression and patch Go production only if it fails for GM-017 behavior.
- 2026-05-11 04:31:23 CEST | Phase: Focused Go proof finished / Dart criteria-harness Executor continuing | Files inspected/touched: `go-mknoon/node/pubsub_delivery_test.go`; touched GM-017 plan progress | Command: `(cd go-mknoon && go test ./node -run '^TestGM017RemovedMemberWithStaleSubscriptionRejectedByRemainingValidators$' -count=1)` | Decision/blocker: Passed (`ok github.com/mknoon/go-mknoon/node 3.235s`); no Go production change needed. | Next action: Add GM-017 scenario support to criteria, criteria tests, runner, and multi-party harness.
- 2026-05-11 04:38:20 CEST | Phase: Local Executor checkpoint during criteria/harness implementation | Files inspected/touched: `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `go-mknoon/node/pubsub_delivery_test.go`; touched GM-017 plan progress | Command: no long-running command active; last completed required proof remains `(cd go-mknoon && go test ./node -run '^TestGM017RemovedMemberWithStaleSubscriptionRejectedByRemainingValidators$' -count=1)` passing | Decision/blocker: GM-017 criteria contract and negative criteria tests are being added, runner now accepts `gm017`, harness now has GM-017 role registration plus draft Alice/Bob/Charlie stale-subscription flow, and a focused Flutter membership test was added to prove removal updates remaining config without invoking stale-member leave. Work is not yet complete or QA-ready; formatting, direct Flutter tests, analyzer, named gates, and exact simulator proof are still pending. | Next action: Finish/format GM-017 harness and criteria changes, then run focused Flutter GM-017 tests before broader required gates.
- 2026-05-11 04:40:56 CEST | Phase: Focused Flutter GM-017 tests finished / Executor validation continuing | Files inspected/touched: `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`; touched GM-017 plan progress | Command/results: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-017'` passed 5 tests; `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-017'` passed 1 test; `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-017'` passed 1 test | Decision/blocker: GM-017 criteria and focused host support proof are green; no blocker. Conditional `integration_test/group_real_crypto_onboarding_test.dart` has not been triggered because execution has not touched real-crypto onboarding or bridge encryption beyond scenario registration/harness proof. | Next action: Run remaining direct Flutter suites, targeted analyzer, exact three-simulator proof, groups/completeness gates, `git diff --check`, then local QA.
- 2026-05-11 04:42:33 CEST | Phase: Direct focused Flutter suites finished / Executor validation continuing | Files inspected/touched: `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`; touched GM-017 plan progress | Command/results: `flutter test test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart` passed 47 tests after `flutter pub get` | Decision/blocker: Required focused Flutter coverage and broader touched direct suites are green. No long-running command is active. Conditional real-crypto onboarding gate remains untriggered because no real-crypto onboarding, bridge encryption, or onboarding harness behavior beyond GM-017 scenario registration was changed. | Next action: Run the remaining onboarding direct suite, then targeted analyzer, exact `--scenario gm017` three-iOS-simulator proof, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, `git diff --check`, and local QA.
- 2026-05-11 04:42:59 CEST | Phase: Remaining direct onboarding suite starting | Files inspected/touched: touched GM-017 plan progress only | Command: `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart` | Decision/blocker: No blocker; this is the remaining direct suite named by the plan. | Next action: Run the command and record exact result before analyzer/simulator gates.
- 2026-05-11 04:43:19 CEST | Phase: Remaining direct onboarding suite finished / targeted analyzer starting | Files inspected/touched: `test/features/groups/integration/group_new_member_onboarding_test.dart`; touched GM-017 plan progress | Command/results: `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart` passed 7 tests | Decision/blocker: Direct Flutter suites named by the plan are green. | Next action: Run targeted analyzer over the Dart files named by the plan, then exact three-simulator GM-017 proof.
- 2026-05-11 04:44:15 CEST | Phase: Targeted analyzer finished / exact simulator proof starting | Files inspected/touched: Dart files named by the plan analyzer command; touched GM-017 plan progress | Command/results: `dart analyze lib/features/groups/application/add_group_member_use_case.dart lib/features/groups/application/remove_group_member_use_case.dart lib/features/groups/application/group_message_listener.dart lib/features/groups/application/group_key_update_listener.dart lib/features/groups/application/group_config_payload.dart lib/features/groups/application/send_group_message_use_case.dart lib/core/bridge/bridge_group_helpers.dart lib/core/bridge/go_bridge_client.dart test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_new_member_onboarding_test.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/shared/fakes/fake_group_pubsub_network.dart test/shared/fakes/group_test_user.dart` exited 0; reported 7 existing info-level `use_null_aware_elements` lints in `bridge_group_helpers.dart`, `group_key_update_listener.dart`, and `send_group_message_use_case.dart`, with no analyzer findings in GM-017-touched criteria/harness/test files | Decision/blocker: Analyzer gate is not blocked; unrelated info-only production style cleanup is deferred to avoid scope creep. | Next action: Run the exact `--scenario gm017` three-iOS-simulator proof using Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
- 2026-05-11 04:49:12 CEST | Phase: Exact three-simulator proof finished / named groups gate starting | Files inspected/touched: `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`; touched GM-017 plan progress | Command/results: `MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm017 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` passed; orchestrator reported `gm017 proof passed: gm017 verdicts valid for alice, bob, charlie`; logs/verdicts at `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm017_dVjLD0`; live log evidence included Alice and Bob `GROUP_VALIDATION_REJECTED` with reason `non_member`, zero stale A/B message count before healthy send, Bob receiving Alice healthy message | Decision/blocker: Required simulator proof is green; no simulator/Xcode repair was needed. | Next action: Run `./scripts/run_test_gates.sh groups`, then completeness-check, `git diff --check`, and local QA.
- 2026-05-11 04:49:59 CEST | Phase: Named groups gate finished / completeness-check starting | Files inspected/touched: group gate suite output; touched GM-017 plan progress | Command/results: `./scripts/run_test_gates.sh groups` passed 122 tests | Decision/blocker: Named group gate is green. | Next action: Run `./scripts/run_test_gates.sh completeness-check`, then `git diff --check` and local QA.
- 2026-05-11 04:50:38 CEST | Phase: Completeness-check finished / diff whitespace gate starting | Files inspected/touched: completeness-check output; touched GM-017 plan progress | Command/results: `./scripts/run_test_gates.sh completeness-check` passed: `Completeness check: 731/731 test files classified. Completeness check PASS.` | Decision/blocker: Completeness gate is green. | Next action: Run `git diff --check`, then local QA.
- 2026-05-11 04:50:53 CEST | Phase: Diff whitespace gate finished / local QA starting | Files inspected/touched: full git diff whitespace check; touched GM-017 plan progress | Command/results: `git diff --check` passed with no output | Decision/blocker: All required Executor tests/gates have completed successfully. Nested QA spawn tools are not available, so local sequential QA fallback is starting in this isolated execution agent. | Next action: Review diff scope, row evidence, plan compliance, dirty worktree preservation, and final acceptance contract.
- 2026-05-11 04:52:10 CEST | Phase: Local QA completed / no fix pass needed / final verdict | Files inspected/touched: GM-017 diff surfaces in `go-mknoon/node/pubsub_delivery_test.go`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `test/features/groups/application/member_removal_integration_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`; simulator verdict summaries in `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm017_dVjLD0`; touched GM-017 plan progress | Command/results: local QA reviewed `rg`/diff snippets for GM-017 ownership and `jq` simulator verdict summaries: Alice/Bob `validationRejectReason=non_member`, `validationRejectCount=1`, `stalePlaintextCount=0`, Alice final members A/B, Bob final members A/B, Charlie final members A/B/C, Alice sent `aliceAfterStaleCharlieReject`, Bob received `aliceAfterStaleCharlieReject`, Charlie sent `charlieStaleAfterRemoval`; all required gates already passed | Decision/blocker: Verdict `accepted`. No fix pass required. Source matrix and session breakdown remain dirty from the pre-existing worktree but were not edited as part of this execution; closure docs remain for the later closure owner. Non-blocking follow-up: unrelated targeted analyzer info lints in pre-existing production files (`use_null_aware_elements`) were intentionally not changed. | Next action: Return final execution verdict.

## Closure Audit

Closure verdict: `closed` / accepted for GM-017. Accepted execution proves a removed Charlie with stale local group/topic/key state cannot publish an accepted post-removal message to Alice/Bob: A/B reject Charlie as `non_member`, emit validation rejection proof, store zero stale Charlie plaintext, and keep healthy remaining-member delivery.

What is now closed:

- Source matrix row GM-017 is `Covered`.
- GM-017 landed as a Go validator regression plus criteria, runner, harness, and focused Flutter support. Product Go/Dart code did not require behavior changes.
- Row-owned proof files are `go-mknoon/node/pubsub_delivery_test.go`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `test/features/groups/application/member_removal_integration_test.dart`, and `test/features/groups/integration/group_membership_smoke_test.dart`.

Accepted simulator proof:

- Exact simulator-only `--scenario gm017` proof passed on Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
- Verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm017_dVjLD0/gmp_1778467478117_gm017_orchestrator_verdict.json` records `scenario: gm017`, `ok: true`, and `gm017 verdicts valid for alice, bob, charlie`.
- Role/criteria proof shows Alice and Bob each have `validationRejected: true`, `validationRejectCount: 1`, `validationRejectReason: non_member`, `stalePlaintextCount: 0`, and final member lists excluding Charlie. Charlie has `groupPresentAfterRemoval: true`, `keyPresentAfterRemoval: true`, `memberListStillIncludesCharlie: true`, `staleSubscriptionPresent: true`, `sentStaleMarker: true`, `leaveRequested: false`, and `leaveResponseOk: false`. Bob received Alice's healthy post-rejection message once.

Maintenance gates passed:

- `(cd go-mknoon && go test ./node -run '^TestGM017RemovedMemberWithStaleSubscriptionRejectedByRemainingValidators$' -count=1)`.
- Focused GM-017 criteria, member-removal, and membership selectors.
- Direct `member_removal_integration_test.dart` plus `group_membership_smoke_test.dart` passed 47 tests after `flutter pub get`; `group_new_member_onboarding_test.dart` passed 7 tests.
- Targeted analyzer exited 0 with only unrelated info-level `use_null_aware_elements` lints in pre-existing production files.
- Exact three-iOS-simulator `gm017`, `./scripts/run_test_gates.sh groups` (`122` tests), `./scripts/run_test_gates.sh completeness-check` (`731/731`), and `git diff --check`.

Residual-only items:

- Unrelated targeted analyzer info-level `use_null_aware_elements` lints remain in pre-existing production files. They are not a GM-017 product residual.

Still-open items: GM-018 and later removed-member/durable-recipient/re-add rows remain open; no final program verdict is written from this GM-017 closure.

Accepted differences:

- Execution used the execution skill's local sequential fallback because nested Executor/QA child tools were unavailable. This is accepted execution mode, not a product residual.
- Conditional `integration_test/group_real_crypto_onboarding_test.dart` was not run because GM-017 did not touch real-crypto onboarding, bridge encryption, or onboarding harness behavior beyond scenario proof wiring.
- No simulator/Xcode build-state blocker occurred for GM-017. Future simulator/Xcode build-state failures should be treated as repair/rerun infrastructure, not a GM-017 row blocker.
- Checkpoint policy was skipped because dirty overlapping aggregate rollout artifacts and existing dirty product/test edits make a clean scoped checkpoint unsafe.

Reopen GM-017 only on a real regression against removed-member stale publish rejection, validation rejection diagnostics, zero accepted stale plaintext on Alice/Bob, or healthy remaining-member delivery after rejection.

## Evidence Collector Notes

- Pre-execution source matrix line 123 kept GM-017 Open: Charlie did not call `LeaveGroupTopic`; A/B update config without C; C publishes with old key; A/B must reject as `non_member` or bad epoch and log `validation_rejected`. The Closure Audit above supersedes this planning-time status.
- Breakdown line 1063 classifies GM-017 as `needs_code_and_tests` / `implementation-ready`, with likely ownership in Flutter membership config propagation and Go pubsub validator paths.
- GM-016 is closed only for the normal removed-member leave/unsubscribe path. Its proof explicitly leaves GM-017 stale-publish validation open.
- `go-mknoon/node/pubsub.go` current validator flow parses the v3 envelope, checks group match and transport binding, reads `groupConfigs[groupId]`, rejects absent sender as `non_member`, rejects missing key as `missing_key`, and rejects signature/epoch mismatch as `bad_signature_or_epoch`; `logPubSubValidationReject` emits `group:validation_rejected`.
- `UpdateGroupConfig` stores a cloned group config snapshot. `remove_group_member_use_case.dart` removes the member locally, builds a config from remaining members, and calls `group:updateConfig`. `group_message_listener.dart` applies remote `member_removed` snapshots to remaining members and calls config sync; self-removal calls `leaveGroup`, which is GM-016 behavior and must not be relied on for GM-017.
- Existing Go tests cover adjacent but not row-owned proof: GL-011 proves nodeB rejects C after `UpdateGroupConfig` removes C; key-rotation tests prove removed previous-epoch sender rejects in pure validation. GM-017 still needs A/B remaining-peer proof and diagnostic evidence for stale C.
- Existing fake Flutter integration network fans out to subscribers without Go validator semantics, and `GroupTestUser.removeMember` unsubscribes the removed peer. A GM-017 host test must deliberately preserve or restore Charlie's stale subscription, or use a bridge/diagnostic seam, rather than reusing the normal GM-016 remove helper unmodified.
- Multi-party simulator harness currently supports GM-001 through GM-016. GM-017 will need scenario, criteria, runner usage, and harness role branches added before exact simulator proof can run.
- `test-gate-definitions.md` makes `./scripts/run_test_gates.sh groups` authoritative for group behavior changes, and classifies the multi-party device orchestrator and criteria test as optional/manual direct proof rather than a frozen named gate.

## real scope

GM-017 owns exactly the validator backstop for a removed Charlie that still has local group topic/key state because Charlie did not call `LeaveGroupTopic`. A/B must have current local group config without Charlie, Charlie must publish using the stale old membership/key state, and A/B must reject that publish through their validators as `non_member` or `bad_signature_or_epoch`, emit `group:validation_rejected` diagnostics, and not persist/render Charlie's post-removal plaintext.

The implementation may add or adjust production code only where regression-first tests prove the backstop is missing. Expected likely code surfaces are Go pubsub validation/config/key handling and Flutter membership config propagation or harness/criteria support. It must not change normal self-removal cleanup, group re-add behavior, durable recipient-list policy, relay inbox replay policy, UI copy, or unrelated group lifecycle rows.

## closure bar

GM-017 is good enough when:

- A focused real-validator regression proves two remaining peers, Alice and Bob, reject stale Charlie's post-removal publish after A/B install config without Charlie, while Charlie remains joined locally.
- The rejection path emits `group:validation_rejected` on A/B with reason `non_member` or `bad_signature_or_epoch`.
- No A/B message repository, bridge receive callback, or simulator verdict records accepted Charlie plaintext for the stale post-removal publish.
- A/B still deliver at least one healthy post-rejection message between remaining members so the fix does not break normal remaining-member delivery.
- Exact three-iOS-simulator GM-017 proof passes on simulators only, preferably Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.

## source of truth

Authoritative contract:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GM-017 defined the expected behavior before execution; the Closure Audit above records the row's accepted `Covered` state.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` row GM-017 defines implementation-ready ownership, likely files, and direct commands.
- Current code and tests win over stale prose if details conflict.
- `Test-Flight-Improv/test-gate-definitions.md` wins for named gate membership.

GM-016 is source evidence only for the separate normal leave/unsubscribe path. It must not be treated as closing GM-017.

## session classification

`implementation-ready`

Do not downgrade to docs-only, evidence-only, or stale/already-covered while the source row remains Open. If regression-first tests show production behavior already rejects correctly, execution still remains implementation-ready because GM-017 needs row-owned tests, criteria, runner, and simulator proof before closure.

## exact problem statement

When Charlie is removed from a private group but keeps stale topic/key state, Charlie can still attempt a live pubsub publish under the old membership epoch. The missing GM-017 proof is that Alice and Bob, after applying current config without Charlie, reject that stale publish at the validator boundary, log a validation rejection diagnostic, and do not render or persist Charlie's stale plaintext.

User-visible behavior that must improve: removed members cannot continue sending accepted group messages to remaining members just because their local app failed to leave the topic.

Behavior that must stay unchanged: normal `member_removed` self-removal still calls `leaveGroup`/`LeaveGroupTopic`; remaining Alice/Bob messaging still works; allowed pre-removal cutoff behavior from GM-013 stays intact; re-add behavior from GM-014 stays intact.

## files and repos to inspect next

Production and bridge files:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/core/bridge/go_bridge_client.dart`

Tests, harness, criteria, and gates:

- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `go-mknoon/node/pubsub_test.go`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/shared/fakes/group_test_user.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/group_real_crypto_onboarding_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`

## existing tests covering this area

- `go-mknoon/node/pubsub_delivery_test.go::TestGL011UpdateGroupConfigReplacesMembershipDuringActiveSubscription` proves one remaining Go node rejects C as `non_member` after `UpdateGroupConfig` removes C and emits validation rejection evidence.
- `go-mknoon/node/pubsub_key_rotation_grace_test.go::TestGroupTopicValidator_RejectsRemovedSenderPreviousEpochDuringGrace` proves the pure validator rejects a removed sender even during previous-key grace.
- `go-mknoon/node/pubsub_test.go::TestGroupTopicValidator_RejectsRemovedMemberAfterConfigUpdate` proves the pure validator changes from accept to `reject:non_member` after config membership removal.
- `test/features/groups/integration/group_membership_smoke_test.dart` contains GM-013/GM-016 adjacent membership removal behavior, but GM-016 intentionally exercises Charlie leaving and unsubscribing, not stale publish.
- `lib/core/bridge/go_bridge_client.dart` and `test/core/bridge/go_bridge_client_test.dart` prove Go `group:validation_rejected` diagnostics reach Flutter flow diagnostics without invoking group message callbacks.
- `test/integration/group_multi_party_device_criteria_test.dart` currently has GM-016 criteria. It does not yet recognize or enforce GM-017 proof fields.

Missing coverage:

- No row-owned GM-017 test proves stale Charlie remains locally subscribed while A/B reject his post-removal publish.
- No exact `--scenario gm017` simulator proof exists.
- No criteria check currently requires A/B validation rejection counts and no A/B accepted Charlie plaintext for GM-017.

## regression/tests to add first

Add the direct regression before production changes:

1. Add a Go real-validator test, preferably in `go-mknoon/node/pubsub_delivery_test.go`, named along the lines of `TestGM017RemovedMemberWithStaleSubscriptionRejectedByRemainingValidators`.
2. Test shape: start Alice/Bob/Charlie local nodes; join all three to the same group with config/key epoch 1; prove Charlie can send before removal; update Alice and Bob to config without Charlie while leaving Charlie's local group/topic/key state untouched; have Charlie publish with the old key; assert Alice and Bob each emit `group:validation_rejected` with reason `non_member` or `bad_signature_or_epoch`; assert no stale marker is received by A/B; assert Alice/Bob still accept a remaining-member message after the rejection.
3. If that Go regression fails, fix only the proven validator/config/key seam. Candidate fixes are limited to config snapshot installation, member/device lookup, validation rejection emission, or stale key-epoch rejection. Do not broaden into relay inbox or recipient filtering.
4. Add or update Flutter host proof in `group_membership_smoke_test.dart` only if it can model the intended seam without pretending the fake network is a Go validator. If the fake network cannot faithfully model validator rejection, keep the host test focused on scenario setup/criteria-adjacent app state and rely on Go plus simulator proof for validator behavior.
5. Add `GM-017` criteria tests before or with harness changes so missing A/B rejection fields, missing Charlie stale-subscription evidence, or any accepted stale Charlie plaintext fail locally.

## step-by-step implementation plan

1. Add the focused Go GM-017 regression and run it. Stop production Go changes if it passes unchanged; keep the test as row-owned evidence.
2. If the Go regression fails, patch only `go-mknoon/node/pubsub.go` or directly adjacent helper code so A/B validators read the current cloned config/key and reject stale Charlie with diagnostics. Re-run the focused Go test after each minimal fix.
3. Inspect the Flutter membership removal/config propagation path only for GM-017-relevant gaps: A/B config without Charlie must be installable without requiring Charlie to process a self-removal event. Avoid changing normal `member_removed` self-removal.
4. Add `gm017` scenario support to the multi-party criteria and runner:
   - `integration_test/scripts/group_multi_party_device_criteria.dart`: add GM-017 requirement for Alice/Bob/Charlie and expected proof fields.
   - `test/integration/group_multi_party_device_criteria_test.dart`: add positive and negative GM-017 cases that fail on missing A/B rejection proof, Charlie not stale, accepted stale plaintext, wrong scenario/roles, or no healthy A/B post-rejection delivery.
   - `integration_test/scripts/run_group_multi_party_device_real.dart`: accept `--scenario gm017`, include usage text, and run only GM-017 for the direct scenario.
   - `integration_test/group_multi_party_device_real_harness.dart`: add Alice/Bob/Charlie GM-017 branches.
5. Harness shape for GM-017:
   - Create a three-member private group and wait for Alice/Bob/Charlie to join.
   - Install current membership config without Charlie on Alice and Bob only, using direct config/update helpers or a row-specific harness helper; do not send Charlie a self-removal path and do not call `leaveGroup` on Charlie.
   - Verify Charlie still has local group state, local key state, and no `GROUP_FL_BRIDGE_LEAVE_REQUEST`.
   - Have Charlie publish a post-removal marker with stale key/config.
   - Capture Alice and Bob flow diagnostics and message repositories.
   - Require A/B `GROUP_VALIDATION_REJECTED`/`group:validation_rejected` evidence with reason `non_member` or `bad_signature_or_epoch`.
   - Require zero accepted/persisted/rendered Charlie stale marker on Alice and Bob.
   - Send a healthy Alice/Bob post-rejection proof message and require receipt to avoid breaking remaining-member delivery.
6. Run direct tests and named gates. If simulator proof fails from unsupported scenario or missing criteria, treat that as implementation work. If it fails from simulator/Xcode/Flutter build state, apply the infrastructure recovery steps in `known-failure interpretation` and rerun the exact command.
7. Stop after GM-017 proof is green. Do not edit source matrix or breakdown during implementation unless a later closure/audit session explicitly owns those docs.

## risks and edge cases

- Charlie must remain stale intentionally; accidentally delivering the normal `member_removed` self-removal path to Charlie collapses the scenario back into GM-016.
- Fake host network delivery is not equivalent to Go validator rejection. Do not claim fake-network rejection as validator proof.
- A/B may reject Charlie before signature verification as `non_member`; this is acceptable. If the config still includes Charlie but key epoch changed, `bad_signature_or_epoch` is also acceptable.
- Go diagnostics hash group/sender/transport identifiers and do not include raw peer IDs. Criteria should check reasons/counts and no accepted plaintext, not raw IDs from the diagnostic payload.
- Charlie's normal send path may attempt relay inbox storage. Durable recipient and offline replay consequences are GM-020/GI-018 scope; GM-017 must not silently expand into relay recipient filtering.
- Remaining Alice/Bob delivery after the rejection must stay green to avoid closing GM-017 by breaking the group.
- Existing dirty worktree changes may overlap likely files. Execution must read current file contents before editing and preserve unrelated changes.

## exact tests and gates to run

Focused Go proof:

```bash
(cd go-mknoon && go test ./node -run '^TestGM017RemovedMemberWithStaleSubscriptionRejectedByRemainingValidators$' -count=1)
```

If Go validator production code changes:

```bash
(cd go-mknoon && go test -race ./node -run '^TestGM017RemovedMemberWithStaleSubscriptionRejectedByRemainingValidators$|GroupTopicValidator|UpdateGroupConfig' -count=1)
(cd go-mknoon && go test ./node -run 'GroupTopicValidator|UpdateGroupConfig|PublishGroupMessage|ValidationReject|GL011|GM017' -count=1)
```

Direct Flutter tests from the breakdown plus GM-017 selectors:

```bash
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-017'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-017'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GM-017'
flutter test test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart
flutter test test/features/groups/integration/group_new_member_onboarding_test.dart
```

Conditional direct test if GM-017 execution touches real-crypto onboarding, bridge encryption, or onboarding harness behavior beyond criteria/runner scenario registration:

```bash
flutter test integration_test/group_real_crypto_onboarding_test.dart
```

Named and hygiene gates:

```bash
dart analyze lib/features/groups/application/add_group_member_use_case.dart lib/features/groups/application/remove_group_member_use_case.dart lib/features/groups/application/group_message_listener.dart lib/features/groups/application/group_key_update_listener.dart lib/features/groups/application/group_config_payload.dart lib/features/groups/application/send_group_message_use_case.dart lib/core/bridge/bridge_group_helpers.dart lib/core/bridge/go_bridge_client.dart test/features/groups/application/member_removal_integration_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_new_member_onboarding_test.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart test/shared/fakes/fake_group_pubsub_network.dart test/shared/fakes/group_test_user.dart
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Device/relay proof:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm017 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

If touched files broaden beyond the listed surfaces, add the smallest adjacent direct tests needed for those files before running broad gates.

## Device/Relay Proof Profile

- Device type: simulators only; do not require real external devices.
- Preferred exact simulator IDs:
  - Alice: `38FECA55-03C1-4907-BD9D-8E64BF8E3469`
  - Bob: `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`
  - Charlie: `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`
- Relay env: use the exact `MKNOON_RELAY_ADDRESSES` value from `group_multi_party_device_criteria.dart`.
- Required proof fields should include: Charlie stale group present, Charlie key present, Charlie did not request/complete leave, Charlie sent stale marker, Alice rejection count/reason, Bob rejection count/reason, Alice stale plaintext count zero, Bob stale plaintext count zero, Alice/Bob healthy post-rejection delivery true, and scenario `gm017`.

## known-failure interpretation

- `--scenario gm017` being unsupported is expected before implementation and must be fixed in this session before closure.
- A failure where A/B accept or persist Charlie's stale marker is a GM-017 regression, not an infrastructure failure.
- A failure where A/B reject Charlie but no diagnostic is emitted is still a GM-017 gap because the source row requires `validation_rejected`.
- Pre-existing unrelated warnings or dirty files must not be reclassified as GM-017 failures unless touched code introduces them.
- Simulator/Xcode/Flutter build-state problems are fixable infrastructure during execution, not terminal row blockers. Refresh device inventory, boot the exact simulators, uninstall the app and extensions from those simulators, clear Runner/Pods DerivedData and `build/ios` if build state is stale, run `flutter pub get` or `flutter clean` only if needed, then rerun the exact commands above.

## done criteria

- GM-017 plan remains `execution-ready` after review/arbiter.
- Row-owned Go validator regression exists and passes.
- GM-017 criteria tests exist and pass, including negative cases for missing rejection/no-stale-state/accepted plaintext.
- GM-017 simulator harness scenario exists and exact three-simulator proof passes on simulator IDs above or documents equivalent available simulator IDs after inventory refresh.
- Breakdown direct Flutter commands pass.
- Targeted analyzer over touched Dart files, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` pass.
- No source matrix or breakdown updates are made during this planning session.

## Reviewer Findings

- Is the plan sufficient as-is, sufficient with adjustments, or insufficient? Sufficient with adjustments applied in this reviewer pass.
- What files, tests, regressions, or gates are missing? The draft needed explicit targeted analyzer coverage and an exact conditional `integration_test/group_real_crypto_onboarding_test.dart` command because the breakdown named it as likely coverage. Both are now recorded.
- What assumptions are stale or incorrect? None found. The plan correctly treats GM-016 as separate leave/unsubscribe evidence and keeps GM-017 implementation-ready.
- What is overengineered? No product architecture expansion found. The plan's harness work is necessary because exact three-party proof is required.
- Is the work decomposed enough to minimize hallucination during implementation? Yes. It starts with one Go validator regression, then only minimal production fixes if that fails, then harness/criteria proof.
- What is the minimum needed to make the plan sufficient? Keep the regression-first Go proof, GM-017 criteria/runner/harness support, exact simulator proof, targeted analyzer, groups/completeness gates, and explicit scope guard.

## scope guard

Do not implement GM-018, GM-019, GM-020, GM-021, GM-022, GK-022, GA-003, or GI-018 while executing GM-017. Do not redesign group membership, key rotation, relay inbox storage, recipient selection, offline replay cutoff, or re-add invitation semantics. Do not add a new authorization framework or new transport abstraction. Do not make fake-network tests pretend to prove real Go validator behavior. Do not broaden `--scenario all`.

## accepted differences / intentionally out of scope

- GM-016 remains separate: it proves removed-member leave/unsubscribe when Charlie receives and processes removal.
- GM-017 accepts either `non_member` or `bad_signature_or_epoch` because the validator may reject at current membership lookup before key verification.
- Durable relay recipient exclusion after removal is GM-020/GI-018, even if Charlie's stale send path attempts inbox storage.
- Diagnostic payloads may contain hashes instead of raw IDs by design.
- Exact simulator proof may use equivalent booted iOS simulators only if the preferred GM-016 IDs are unavailable after inventory refresh; the final execution evidence must list the actual IDs.

## dependency impact

Closing GM-017 unblocks later confidence for GM-018 remaining-member delivery under stale rejection pressure, GM-020 recipient exclusion, GA-003 removed-member old-config/key authorization evidence, and GK-022/GI-018 post-removal decrypt/replay privacy rows. If GM-017 reveals the validator cannot distinguish current membership from stale local state, skip later stale-publish closure claims until the validator/config update fix and exact simulator proof are green.

## Arbiter Decision

- Structural blockers: none.
- Incremental details: keep the conditional `integration_test/group_real_crypto_onboarding_test.dart` command conditional unless execution touches real-crypto onboarding or bridge encryption paths. Keep exact simulator IDs preferred, but allow equivalent simulator IDs only after inventory refresh proves the preferred set unavailable.
- Accepted differences: GM-017 may close with `non_member` or `bad_signature_or_epoch`; fake-network host tests are support evidence, not validator proof; durable inbox recipient filtering remains out of scope.
- Stop rule: no structural blocker remains, so planning stops here.

## Final verdict

`execution-ready` for GM-017 only.

## Final plan

Execute the plan sections above as written: add the row-owned real-validator regression first, make only minimal code fixes if it fails, add GM-017 criteria/runner/harness support for exact three-simulator proof, then run the direct tests, targeted analyzer, named gates, simulator proof, and diff hygiene.

## Structural blockers remaining

None.

## Incremental details intentionally deferred

- Do not run `integration_test/group_real_crypto_onboarding_test.dart` unless GM-017 execution touches real-crypto onboarding, bridge encryption, or onboarding harness behavior beyond scenario registration.
- Do not expand `--scenario all`; direct `--scenario gm017` is the required proof.

## Accepted differences intentionally left unchanged

- GM-016 leave/unsubscribe evidence remains separate and does not close stale-publish validation.
- GM-017 does not own durable recipient-list filtering, relay inbox replay cutoff, or post-removal decrypt privacy.
- Go diagnostic payloads may stay hashed/redacted.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `go-mknoon/node/pubsub_test.go`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/core/bridge/go_bridge_client.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/shared/fakes/group_test_user.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`

## Why the plan is safe or unsafe to implement now

Safe to implement now. The plan is bounded to GM-017, starts with a regression that exercises the real Go validator seam, separates GM-016 normal leave/unsubscribe from stale malicious publish, includes exact proof and gate commands, and records simulator infrastructure recovery steps without treating build-state problems as terminal row blockers.
