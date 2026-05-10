# GM-007 Execution Plan - Remove C, Send During Absence, Then Re-add C

Status: closed

## Planning Progress

- 2026-05-10 16:00 CEST - Evidence Collector completed. Files inspected since last update: source matrix rows GM-006/GM-007/GM-008, breakdown ordered rows GM-005 through GM-007, GM-006 plan/closure evidence, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, and `integration_test/scripts/run_group_multi_party_device_real.dart`. Decision/blocker: GM-007 remains `Open`; GM-006 proves immediate re-add/current epoch, but GM-007 still lacks row-owned history-boundary proof for allowed M0, excluded M1..M3, and allowed M4 after rejoin. Next action: implement GM-007 proof support without changing source matrix/breakdown closure status.
- 2026-05-10 16:00 CEST - Planner completed. Decision/blocker: GM-007 is implementation-ready because the product seams and GM-006 harness pattern exist, but exact host, criteria, runner, and device harness coverage are missing. Next action: add row-owned regression and extend only the accepted GM multi-party harness files.
- 2026-05-10 16:00 CEST - Reviewer completed. Decision/blocker: plan is sufficient as-is if it makes Charlie's visibility boundary explicit and treats product changes as conditional on a failing proof. Next action: arbiter pass.
- 2026-05-10 16:00 CEST - Arbiter completed. Decision/blocker: no structural blockers; optional `--scenario all` expansion remains out of scope. Next action: execute GM-007 only.

## real scope

Own exactly source row `GM-007`: Charlie is a valid member for M0, is removed before M1..M3, and is re-added before M4.

In scope:
- Add a row-owned GM-007 host/app proof that Charlie receives only the allowed pre-removal message M0 and the post-rejoin message M4, while Bob continues receiving M1..M3 during Charlie's absence.
- Extend the accepted GM multi-party proof files for `gm007` only:
  - `integration_test/scripts/run_group_multi_party_device_real.dart`
  - `integration_test/group_multi_party_device_real_harness.dart`
  - `integration_test/scripts/group_multi_party_device_criteria.dart`
  - `test/integration/group_multi_party_device_criteria_test.dart`
- Fix the smallest product or harness seam only if GM-007 proof shows a real behavior gap: Charlie sees removed-window messages, misses allowed M0 or M4, re-enters with stale epoch/config, or remaining members lose delivery.

Out of scope:
- App restart during re-add, duplicate remove/re-add events, stale out-of-order membership events, role changes, media, notifications, and long history retention policy outside M0/M1..M3/M4.
- Changing GM-001 through GM-006 accepted criteria or closure facts.
- Expanding `--scenario all`.
- Committing changes.

## closure bar

GM-007 is good enough only after row-specific evidence proves:
- Alice/Bob/Charlie start as current members with a shared initial key/config.
- Alice sends pre-removal M0 while Charlie is still a member, and Bob/Charlie receive it.
- Alice removes Charlie and rotates/distributes the current key/config to Alice/Bob only.
- Alice sends removed-window M1, M2, and M3; Bob receives all three exactly once, and Charlie stores/decrypts none of them.
- Alice re-adds Charlie under the current rejoin epoch/config.
- Alice sends post-rejoin M4; Bob and Charlie receive it exactly once under the current config/device binding.
- Alice, Bob, and Charlie converge on the final A/B/C member list and key epoch.
- Exact relay/device proof passes with `--scenario gm007` and writes an orchestrator verdict JSON where `scenario: gm007`, `ok: true`, and per-role verdicts validate Alice, Bob, and Charlie.
- Direct tests, named gates, and hygiene checks in this plan pass.

Do not weaken GM-007 into "Charlie can send after re-add"; the row's closing contract is the history boundary: M0 yes, M1..M3 no, M4 yes.

## source of truth

Authoritative inputs:
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GM-007`.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` row `GM-007`.
- Accepted GM-006 closure evidence as the nearest remove/re-add precedent.
- Current Flutter app code and accepted GM harness files.
- `Test-Flight-Improv/test-gate-definitions.md` for named gate behavior.

Conflict rule:
- Current code/tests beat stale prose.
- The GM-007 matrix row defines the contract unless exact repo proof shows it is already covered; current evidence does not.
- The accepted relay env is mandatory for device proof.

## session classification

`implementation-ready`

Rationale: the breakdown classifies GM-007 as `needs_repo_evidence` / `evidence-gated`, but exact planning found missing row-owned host proof, criteria support, runner support, and real-device harness support. These proof surfaces are repo-owned implementation work. Product changes are conditional on a failing GM-007 proof.

## exact problem statement

GM-007 remains `Open`. GM-006 proves immediate re-add with current epoch, but it does not prove the longer visibility boundary where Charlie has allowed pre-removal history, then must be excluded from a removed-window sequence, then must receive post-rejoin content.

What must improve or be proven:
- Charlie retains/accesses only the content allowed by its membership windows: M0 before removal and M4 after rejoin.
- Charlie cannot decrypt or persist M1..M3 sent while removed.
- Bob continues receiving M1..M3 during Charlie's absence and M4 after Charlie rejoins.
- All roles converge on the current member list and key epoch after re-add.

What must stay unchanged:
- Accepted GM-001 through GM-006 proof semantics.
- Current removal fail-closed behavior and current re-add epoch behavior.
- Existing signed system-message validation, key-rotation validation, and send validation.

## files and repos to inspect next

Production/app seams:
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`

Harness/tests:
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`

Go fallback only if a failing proof points below Flutter/app replay or PubSub validation:
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`

## existing tests covering this area

Already useful but not enough:
- GM-004 covers online removal and removed-member non-access.
- GM-005 covers stale offline removal and removed-window exclusion while offline.
- GM-006 covers immediate remove/re-add and post-readd current-epoch messaging.
- `group_membership_smoke_test.dart::removed member can be re-added with current state and resumes send/receive` covers generic re-add behavior.

Missing:
- A GM-007-named host/app regression for M0 allowed, M1..M3 excluded, M4 allowed after rejoin.
- GM-007 criteria that reject false positive role verdicts.
- `--scenario gm007` runner/harness support.
- Exact relay/device proof for GM-007.

## regression/tests to add first

Add tests before product fixes:
- Add a focused host regression in `test/features/groups/integration/group_membership_smoke_test.dart`, named:
  - `GM-007 preserves allowed pre-removal and post-readd messages while excluding removed-window messages`
- Extend `test/integration/group_multi_party_device_criteria_test.dart` for GM-007:
  - accepts complete Alice/Bob/Charlie verdicts;
  - rejects Charlie missing pre-removal M0;
  - rejects Charlie receiving any removed-window M1..M3 plaintext;
  - rejects Charlie missing post-rejoin M4;
  - rejects Bob missing any M1..M3 or M4;
  - rejects incomplete final member/key convergence proof.

Product code changes should begin only after the row-owned proof fails for product behavior rather than missing proof support.

## step-by-step implementation plan

1. Reconfirm current dirty worktree and do not revert unrelated changes.
2. Add the GM-007 host regression:
   - Start Alice/Bob/Charlie as members at epoch 1.
   - Alice sends M0 before removal; Bob and Charlie receive it.
   - Alice removes Charlie and rotates to epoch 2 for Alice/Bob only.
   - Alice sends M1, M2, and M3 while Charlie is removed; Bob receives all three, Charlie receives none.
   - Alice re-adds Charlie with current epoch 2.
   - Alice sends M4 after rejoin; Bob and Charlie receive it.
   - Assert Charlie's texts include M0 and M4 but not M1..M3, and all roles converge on A/B/C plus epoch 2.
3. Add GM-007 criteria support:
   - Add `_gm007Requirement` with roles `alice`, `bob`, `charlie`.
   - Include `gm007` in supported-scenario errors.
   - Expected messages: M0 to Bob/Charlie; M1..M3 to Bob only; M4 to Bob/Charlie.
   - Add `_validateGm007HistoryBoundaryProof` requiring Alice removal/readd/final epoch, Bob removed-window and post-readd receipts, and Charlie pre-removal/post-readd receipts with zero removed-window plaintext.
4. Add GM-007 positive and negative criteria tests.
5. Extend `run_group_multi_party_device_real.dart` to accept direct `--scenario gm007`; keep `--scenario all` unchanged.
6. Extend `group_multi_party_device_real_harness.dart`:
   - Add `gm007` roles Alice/Bob/Charlie.
   - Reuse GM-006 helper shape but split proof messages into M0, M1..M3, and M4.
   - Charlie should count removed-window plaintext before and after readd.
7. Run direct tests and fix only GM-007-owned failures.
8. Run fresh device discovery:
   - `flutter devices --machine`
   - `xcrun simctl list devices available`
9. Run exact GM-007 relay/device proof with accepted relay env:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g \
dart run integration_test/scripts/run_group_multi_party_device_real.dart \
  --scenario gm007 \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

10. Run named gates and hygiene, then stop for closure.

## risks and edge cases

- GM-007 can accidentally collapse into GM-006 if M1..M3 are not distinct and asserted individually.
- Charlie must be active for M0 and removed for the entire M1..M3 window.
- Re-add must install current config/key before M4.
- Bob must not lose delivery during Charlie's absence.
- Existing dirty files may affect broad gates; isolate failures before attributing them to GM-007.

## exact tests and gates to run

Direct tests after adding GM-007 support:

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-007 preserves allowed pre-removal and post-readd messages while excluding removed-window messages'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart
dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart
```

Fresh device discovery before exact proof:

```bash
flutter devices --machine
xcrun simctl list devices available
```

Device proof:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm007 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Named gates and hygiene:

```bash
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

If docs remain untracked, run no-index whitespace checks on the touched markdown files before final handoff.

## known-failure interpretation

Known unrelated context:
- The worktree already contains many modified and untracked files from earlier rollout sessions.
- GM-001 through GM-006 are covered; reopening them is out of scope unless a real regression appears in their accepted proof.
- `--scenario all` currently omits later GM rows; direct `--scenario gm007` is the required proof and `all` expansion is not a GM-007 blocker.

Do not hide a GM-007 regression behind "known failure" if Charlie receives M1..M3, misses M0/M4, rejoins with stale epoch/config, or Bob loses removed-window delivery.

## done criteria

- GM-007 host regression exists and passes.
- GM-007 criteria tests exist and pass, including negative history-boundary cases.
- `--scenario gm007` runner/harness support exists and reuses the accepted GM multi-party device harness surface.
- Fresh device discovery was run immediately before exact proof.
- Exact relay/device proof passes with accepted relay env and writes an `ok: true` GM-007 orchestrator verdict plus Alice/Bob/Charlie role verdicts.
- Direct tests, named gates, and hygiene checks pass.
- Source matrix and breakdown are not marked `Covered` during implementation.
- No unrelated dirty files are reverted or overwritten.

## scope guard

Do not:
- Convert GM-007 into a general message-history or retention rewrite.
- Change product expectations so Charlie can see removed-window messages.
- Treat GM-006 as complete closure evidence for GM-007.
- Add a second orchestration system.
- Expand `--scenario all` as a required closure condition.
- Revert or clean unrelated dirty/untracked files.

Overengineering signs:
- New generic membership simulator framework.
- New persistence abstraction just for this row.
- Broad Go PubSub rewrites before GM-007 failing proof points there.

## accepted differences / intentionally out of scope

- GM-006 is precedent for current-epoch rejoin, but GM-007 needs separate M0/M1..M3/M4 history-boundary proof.
- `--scenario all` not including GM-007 is acceptable for this session.
- Host fake-network proof and exact device proof are both required; one is not a substitute for the other.

## dependency impact

Later removal/re-add rows can reuse the GM-007 history-boundary proof shape:
- GM-008 adds app restart to the re-add window.
- GM-019 depends on recipient inclusion only after re-add.
- GK-023 depends on re-added members not decrypting removed-window backlog.

If GM-007 exposes a product gap, pause later removal/re-add/history rows until the narrow GM-007 fix and proof are accepted.

## Reviewer Findings

Verdict: sufficient as-is.

- Missing files, tests, regressions, or gates: none structural. The plan names the GM-007 host proof, criteria tests, runner/harness files, fresh device discovery, exact relay proof, groups gate, completeness-check, and diff hygiene.
- Stale or incorrect assumptions: none found. GM-006 is treated only as precedent, not closure evidence.
- Overengineering: none required. The plan extends the accepted GM harness.
- Decomposition: sufficient. Product changes are conditional and limited to the seam shown by failing GM-007 evidence.

## Arbiter Decision

- Structural blockers: none.
- Incremental details: optional `--scenario all` expansion remains deferred.
- Accepted differences: GM-006 closes immediate re-add only; GM-007 requires separate M0/M1..M3/M4 proof.
- Stop rule: no structural blocker was found, so this plan is execution-ready for GM-007 only.

## Execution Progress

- 2026-05-10 16:25 CEST - Implemented GM-007 host, criteria, runner, and device harness proof support. Files changed: `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, and `integration_test/group_multi_party_device_real_harness.dart`. Product code changed: no.
- 2026-05-10 16:25 CEST - Direct verification passed:
  - `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-007 preserves allowed pre-removal and post-readd messages while excluding removed-window messages'`
  - `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` (`41` tests)
  - `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart`
- 2026-05-10 16:25 CEST - Device discovery passed. `flutter devices` found the target simulators Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and Dana `1B098DFF-6294-407A-A209-BBF360893485`; `xcrun simctl list devices available` also showed those iOS simulators booted.
- 2026-05-10 16:25 CEST - Exact relay/device proof passed:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm007 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Verdict: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm007_Yp12M1/gmp_1778422910998_gm007_orchestrator_verdict.json` records `scenario: gm007`, `ok: true`, and `gm007 verdicts valid for alice, bob, charlie`.

- 2026-05-10 16:26 CEST - Supporting gates passed:
  - `./scripts/run_test_gates.sh groups` (`+111`)
  - `./scripts/run_test_gates.sh completeness-check` (`731/731 test files classified`)
  - `git diff --check`

## Closure Verdict

GM-007 is closed/covered. The row-owned proof verifies the intended history boundary: Charlie receives M0 before removal and M4 after re-add, stores zero M1..M3 removed-window plaintext, rejoins at the current epoch, and Bob keeps delivery for M0, M1, M2, M3, and M4. No production behavior change was required; the missing work was proof infrastructure and row-owned regression coverage.

GM-007 should reopen only on a real regression against pre-removal visibility, removed-window exclusion, post-readd delivery, current-epoch rejoin, or remaining-member delivery continuity. GM-008 and later rows remain unresolved.
