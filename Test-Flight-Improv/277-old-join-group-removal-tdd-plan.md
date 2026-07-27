# 277 - Old Direct `joinGroup` Removal

Status: Plan-green
Type: Modification
Spec: free-text DTR-10 owner decision — remove the test-only direct join island because live invite materialization and startup/recovery rejoin flows replace it
Classification: implementation-complete
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-26 | Evidence Collector | `join_group_use_case.dart`, its direct suite, runtime-root manifest, group gate, live invite/rejoin/bridge seams | Confirmed one declaration and seven calls, all confined to the legacy source and its SUT-only suite; no production caller or export was found | Verify the independent live replacements |
| 2026-07-26 | Baseline Verifier | direct join suite; bridge helper, accepted-invite, and rejoin selectors | All selected current-HEAD tests passed; the old suite is healthy but isolated, while the live full-config paths have independent green coverage | Build removal and preservation contracts |
| 2026-07-26 | Planner | roadmap `DTR08-COMP-004`, current native/Go join chain, TDD tier/template references | Explicit owner decision authorizes only removal of the old direct Dart island; full-config/native/Go behavior stays protected | Emit an execution-ready host plan |
| 2026-07-26 | Sufficiency Check | TDD sufficiency checklist and this plan | All declared behaviors have a causal absence contract or named preservation proof; no schema, device, relay, or live wire change is planned | Ready for optional independent review, then execution |
| 2026-07-26 | `$tdd-review` counterexample audit | review-profile Graphify query; complete owned-Dart caller/import census; `SelfRemovedGroupShellRepository` API/implementation/fakes/tests; live invite/rejoin selectors; gate/runtime-root/C4 records | Core bet confirmed, but source-only deletion would leave the six-token, direct-join-only `commitFreshDirectJoin` capability and its SUT-only repository test behind; the import census also omitted `test`, `scripts`, and root Dart files | Expand the same bounded retirement to that orphaned capability, make the final causal contract scan all owned Dart roots, and preserve the live duplicate-retry coordinator sentinel |

## Authorization Receipt

- Receipt: `DTR10-AUTH-01`.
- Authority/date: current authenticated project owner, 2026-07-26.
- Authorized action: remove the old direct `joinGroup` implementation because
  supported admission plus startup/recovery replace it.
- Included cleanup: its dedicated SUT-only suite, its direct-join-only
  `commitFreshDirectJoin` repository declaration/implementation/fake fragments
  and dedicated repository test block, runtime-root/gate records, and
  present-tense architecture claims that would otherwise advertise the deleted
  island.
- Guard: this receipt does not authorize a new admission surface or any change
  to live invite/re-entry, rejoin, full-config, native, Go, shared repository
  persistence, keys, schema, or migration behavior.

## Problem And Evidence

- Behavior to improve: remove the misleading, test-only direct `joinGroup`
  entry point instead of maintaining a second group-admission implementation
  that production never calls.
- Impact: keeping a second join implementation and seven SUT-only calls makes
  dead behavior look production-supported and can diverge from the durable
  invite/re-entry and lifecycle-rejoin paths that users actually exercise.
- Confirmed current gap: `joinGroup` is declared at
  `lib/features/groups/application/join_group_use_case.dart:13-93`; a
  fail-closed current-source census finds its only calls at
  `test/features/groups/application/join_group_use_case_test.dart:80-257`.
  No other owned Dart source imports/exports the file or references the exact
  symbol, and `pubspec.yaml:5` sets `publish_to: none`, so there is no supported
  package-consumer surface.
- Review-confirmed residue: the use case's
  `SelfRemovedGroupShellRepository.commitFreshDirectJoin` dependency has six
  exact owned-Dart tokens: the use-case call, interface declaration,
  production implementation, in-memory fake, one test-only fake stub, and one
  direct repository test call. No live invite/re-entry or rejoin path uses it.
  Removing only the two originally named files would therefore leave a second,
  test-only direct-join capability behind.
- Confirmed replacement mechanisms:
  - accepted invite re-entry supplies the full config, key, and epoch to
    `callGroupJoinWithConfig` at
    `accept_pending_group_invite_use_case.dart:691-708`;
  - incoming invite materialization persists the group, roster, and key, then
    performs the full-config native join at
    `handle_incoming_group_invite_use_case.dart:1081-1125`;
  - startup/resume recovery reconstructs the full config from stored members
    and current key at `rejoin_group_topics_use_case.dart:90-105,208-219`;
  - the retained bridge command contains exactly `groupId`, `groupConfig`,
    `groupKey`, and `keyEpoch` at
    `bridge_group_helpers.dart:105-147`, and maps to `groupJoinTopic` at
    `go_bridge_client.dart:173-176`.
- Confirmed live admission semantics:
  - accepted invites validate signed full-config/key material and persist the
    complete roster, self role, and epoch before the full-config native join;
  - malformed/repairable material is refused or rolled back, while a transient
    native join failure intentionally keeps the materialized group and enrolls
    the bounded rejoin retrier instead of reproducing the old fresh-direct
    rollback;
  - retained/deleted self-removal authority is re-entered only with a newer
    signed membership generation. The dormant helper's simpler “fresh-only”
    guard is not a supported substitute for that live policy.
- Existing coverage: the planning baseline passed the complete seven-test
  legacy suite plus:
  `bridge_group_helpers_test.dart::sends group:join with groupId, groupConfig,
  groupKey, keyEpoch`,
  `accept_pending_group_invite_use_case_test.dart::accepts pending invite,
  persists group, and drains inbox`, and
  `rejoin_group_topics_use_case_test.dart::calls callGroupJoinWithConfig for
  each active group`.
- Missing coverage: no current test asserts that this separately authorized
  legacy source, its SUT-only suite, its runtime-root declaration, and its
  curated-gate entry are all absent. Current C4 files also still advertise the
  old source/symbol as live. TC-JOIN-01 adds the causal removal/current-doc
  contract.
- Refuted findings:
  - “Removing this file removes `group:join`” is refuted: live invite and
    rejoin callers independently reach `callGroupJoinWithConfig`, the Dart
    command mapping, native handlers, and Go `GroupJoinTopic`.
  - “Startup/recovery alone replaces new-group acceptance” is refuted:
    invite materialization owns admission; startup/recovery owns rejoining
    already-persisted groups. Both replacement families are preserved.
- Unresolved findings: N/A for this bounded leaf removal. A future open-join or
  link-token product entry point would require a new TDD plan and cannot revive
  this API without current-source and trust-policy design.
- Affected production, test, gate, and bookkeeping files:
  `lib/features/groups/application/join_group_use_case.dart`,
  `test/features/groups/application/join_group_use_case_test.dart`,
  `test/features/groups/application/old_join_group_removal_contract_test.dart`
  (new), `lib/features/groups/domain/repositories/group_repository.dart`,
  `lib/features/groups/domain/repositories/group_repository_impl.dart`,
  `test/shared/fakes/in_memory_group_repository.dart`,
  `test/features/groups/application/delete_self_removed_group_shell_use_case_test.dart`,
  `test/features/groups/domain/repositories/group_repository_impl_test.dart`,
  `tool/runtime_roots/runtime_roots.json`,
  `scripts/run_test_gates.sh`, `C4/file-structure.md`, `C4/code.md`,
  `C4/components.md`, the DTR roadmap, and `00-INDEX.md`.

## Graph Grounding Snapshot

- Graph fingerprint / freshness:
  `0c2b989ba6d96ada`; `freshness=current`.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "Remove obsolete GroupRepositoryImpl.joinGroup entry point after verifying production invitation startup recovery and full group configuration joins preserve native and Go behavior" --profile tdd --budget 700`
  returned `confidence=broad`; the single allowed refinement
  `python3 graphify-arch/tdd_context.py query "GroupRepositoryImpl joinGroup JoinGroupUseCase join_group_test.dart" --profile tdd --budget 700`
  returned `confidence=anchored`.
- Independent review query / profile:
  `python3 graphify-arch/tdd_context.py query "counterexample audit joinGroup join_group_use_case.dart supported caller export invite admission rejoin full-config callGroupJoinWithConfig native Go GroupJoinTopic" --profile review --budget 800`
  returned `confidence=anchored` with the same current fingerprint.
- Anchors:
  `GroupRepositoryImpl` ->
  `lib/features/groups/domain/repositories/group_repository_impl.dart:33`;
  `joinGroup` ->
  `lib/features/groups/application/join_group_use_case.dart:13`.
- Surfaced proof/gate files:
  `group_repository_impl_test.dart`,
  `join_group_use_case_test.dart`, `scripts/run_test_gates.sh`.
- Graph gaps requiring source search: exact whole-repository caller/import
  census; current invite, startup/rejoin, MethodChannel, native, and Go
  replacement paths.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Delete
  `lib/features/groups/application/join_group_use_case.dart` and its dedicated
  `test/features/groups/application/join_group_use_case_test.dart`.
- Remove only the now-orphaned `commitFreshDirectJoin` declaration,
  implementation, two fake/stub overrides, and its dedicated
  `group_repository_impl_test.dart` test block. No table, DB helper, secure-key
  operation, accepted re-entry method, or shared coordinator changes.
- Remove only the matching runtime-root declaration and the deleted suite's
  explicit `GROUP_TESTS` entry.
- Add the causal source/removal contract, then update the current DTR decision,
  compatibility row, index entry, and present-tense C4 source/API claims to
  record this exact disposition. Historical `UI-19-Groups/TDD_PLAN_*` records
  stay historical.

Must preserve:

- Live invite admission and post-removal re-entry ->
  `accepts pending invite, persists group, and drains inbox` and the full
  accepted-invite suite.
- Live incoming invite materialization ->
  `calls group:join bridge command with groupId, groupConfig, groupKey,
  keyEpoch`, `persists all members from groupConfig, not just sender`, and
  `persists correct myRole as member (not admin)`.
- Live invalid-material, transient-failure, and re-entry policy ->
  `returns invalidPayload for missing groupKey`,
  `returns invalidPayload for missing groupConfig`,
  `E: a group:join timeout keeps the group and enrolls it in the rejoin
  retrier`, and
  `deleted-shell re-entry enforces retained removal freshness floor`.
- The retained accepted-reentry repository coordinator ->
  `duplicate retry holds the per-group coordinator through native join`.
- Startup/resume topic recovery ->
  `calls callGroupJoinWithConfig for each active group` and
  `builds correct groupConfig from stored members`.
- Full-config Dart/MethodChannel contract ->
  the exact bridge-helper and `BB-007` client selectors in TC-JOIN-04.
- Native/generated/Go validation, idempotence, and newer key-generation refresh
  -> protected-path no-diff, binding verification, and the exact Go selectors
  in TC-JOIN-05.

Hard `Do not`:

- Do not edit `callGroupJoinWithConfig`, `group:join`, `groupJoinTopic`,
  Android/iOS/macOS handlers, generated bindings, Go `GroupJoinTopic`, group
  config/wire schemas, keys, key epochs, database rows, or migrations.
- Do not alter any retained `SelfRemovedGroupShellRepository` method or shared
  group-mutation coordinator; only the exact orphaned direct-join method and
  its dedicated test/fake fragments are removable.
- Do not redirect production callers to a new wrapper.
- Do not delete invite, rejoin, native, Go, or preservation tests merely
  because they once also covered the old helper.
- Do not rewrite historical completed plans or execution receipts; update only
  current C4/roadmap bookkeeping that claims the removed leaf exists.

Deferred / accepted difference:

- A future user-facing open/link join surface -> owner Groups + Product, via a
  separately authorized TDD plan, because this removal is not authority to
  design a new admission policy.
- The old helper's fresh-only validation and flow events disappear with its
  unreachable code. Production invite/re-entry and rejoin paths keep their own
  stronger, independently tested authority contracts; those SUT-only assertions
  are not migrated as if the old entry point remained supported.
- The old helper performed native join before committing local rows, so a
  transient native error left nothing persisted. Live invite admission
  intentionally keeps a valid materialized group and bounded rejoin state for a
  transient failure, while malformed material is refused/rolled back. Preserve
  the live retry behavior; do not resurrect the obsolete rollback contract.

Dependencies:

- `DTR10-AUTH-01`: the user's 2026-07-26 instruction is the explicit
  Groups-owner authorization for this exact leaf/test removal. Execution must
  preserve that receipt label in the roadmap as the join-specific DTR-10
  disposition before deletion.
- DTR-03 already retired only the deprecated topic-name wrapper and preserved
  this decision for DTR-10; its live full-config preservation floor remains in
  force.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-JOIN-01 | The old direct-join source, SUT-only suite, direct-join-only repository capability/test/fake fragments, runtime-root declaration, curated gate entry, and present-tense C4 source/API claims are absent, while named live replacement files and the accepted-reentry coordinator remain. | `test/features/groups/application/old_join_group_removal_contract_test.dart::DTR10-JOIN-01 old direct join island and bookkeeping are absent` | Host source/API/current-doc contract / real repository tree and fail-closed owned-Dart enumeration | Scaffolded causal RED: HEAD contains the old files, six `commitFreshDirectJoin` tokens, manifest/gate/current-C4 records -> GREEN after exact island deletion/bookkeeping correction. | Restore either file, either retired identifier, a manifest/gate/current-C4 claim, or remove a retained live anchor -> TC-JOIN-01 red. | `flutter test --no-pub test/features/groups/application/old_join_group_removal_contract_test.dart --plain-name 'DTR10-JOIN-01 old direct join island and bookkeeping are absent'`; AUTO (`test/features/**`) for `feature-host-all`. |
| TC-JOIN-02 | No supported owned-source caller, tear-off, import, export, entrypoint, or downstream direct-join repository token remains outside the enumerated legacy island before deletion; both exact identifiers and the retired import are absent afterward. | `DTR10-JOIN-CALLER-01` fail-closed census in Acceptance Gates | Host source evidence / all owned Dart roots plus root Dart files | HEAD evidence: one `joinGroup` declaration and seven calls in the two removal files; six enumerated `commitFreshDirectJoin` tokens; zero other exact identifier/import/export tokens -> GREEN final census: zero retired identifiers/file imports. | Add a tear-off/export in `test`, `scripts`, or a root Dart file, or leave one repository/fake token -> census and TC-JOIN-01 fail. | Literal fail-closed `rg`/count commands below; MANUAL source registration, followed by TC-JOIN-01 and `runtime-roots`. |
| TC-JOIN-03 | Live invite admission/re-entry and lifecycle rejoin retain full group config, complete roster/self role/key material/current epochs, malformed-material refusal, transient native retry enrollment, retained-removal-floor authority, and retained per-group native-retry serialization. | `accept_pending_group_invite_use_case_test.dart::accepts pending invite, persists group, and drains inbox`; `handle_incoming_group_invite_use_case_test.dart::{calls group:join bridge command with groupId, groupConfig, groupKey, keyEpoch, persists correct myRole as member (not admin), persists all members from groupConfig, not just sender, returns invalidPayload for missing groupKey, returns invalidPayload for missing groupConfig, E: a group:join timeout keeps the group and enrolls it in the rejoin retrier, deleted-shell re-entry enforces retained removal freshness floor}`; `rejoin_group_topics_use_case_test.dart::{calls callGroupJoinWithConfig for each active group, builds correct groupConfig from stored members}`; `group_repository_impl_test.dart::duplicate retry holds the per-group coordinator through native join` | Application/repository host / real SQLite repository and bridge fakes | GREEN sentinels on HEAD -> same live assertions remain green after direct-island deletion. The transient-error sentinel deliberately preserves materialized state, unlike the retired helper. | Remove a live join call/required field/roster/key/epoch, accept malformed input, roll back valid state on transient failure, omit retry enrollment, bypass removal-floor freshness, or release the coordinator during native retry -> corresponding selector red. | Exact commands below; all files are explicitly in `GROUP_TESTS` and AUTO feature-host. |
| TC-JOIN-04 | The retained Dart helper and MethodChannel map still send the exact full-config command. | `test/core/bridge/bridge_group_helpers_test.dart::sends group:join with groupId, groupConfig, groupKey, keyEpoch`; `test/core/bridge/go_bridge_client_test.dart::BB-007 callGroupJoinWithConfig forwards exact full config payload to groupJoinTopic` | Core host / fake Bridge and fake MethodChannel | GREEN sentinels on HEAD -> exact command/method and four fields remain green. | Drop/change `groupKey` or `keyEpoch`, add `topicName`, or remap the method -> selector red. | Two exact direct commands below; AUTO core registration. They are run directly because full `core-host-all` is not justified for a feature-leaf deletion. |
| TC-JOIN-05 | Native/generated/Go join behavior remains byte-for-byte unchanged and still rejects legacy/invalid material while preserving valid, idempotent, and newer-epoch joins. | protected-path `git diff HEAD --quiet`; `scripts/verify_gomobile_bindings.sh all`; `go-mknoon/bridge/bridge_test.go::{TestGroupJoinTopic_BB006RejectsLegacyTopicNameOnlyPayload, TestGroupJoinTopic_RejectsInvalidKeyState, TestSV009GroupJoinAndUpdateConfigRejectMalformedMemberKeys, TestGroupJoinTopic_RejectsIncompleteActiveMemberKeyMaterial, TestGroupJoinTopic_RejectsMalformedActiveDeviceTransportPeerId, TestGroupJoinTopic_BB007RoundTripsFullConfigAndAcceptsPublish, TestGroupJoinTopic_AlreadyJoinedIsIdempotent, TestGroupJoinTopic_BB008AlreadyJoinedRefreshesNewerKeyAndConfig}` | Source integrity + generated binding verifier + real Go unit boundary | GREEN on HEAD -> protected sources stay unchanged and all exact Go behaviors remain green after Dart leaf deletion. | Edit a protected mapping/handler, remove a generated export, accept invalid material, or regress valid/idempotent/newer-epoch handling -> no-diff, verifier, or Go selector red. | Literal protected-path, verifier, and Go commands below; MANUAL exact registration. |
| TC-JOIN-06 | Runtime-root and test-gate inventories describe the final tree; the new causal test is discoverable and the deleted suite is not selected. | `test/unit/runtime_root_inventory_test.dart::repository manifest accounts for current non-main sources and keeps known candidates advisory`; `feature-host-all --list` discovery | Tool/unit host + real Git-visible tree | Causal inventory RED after manifest/gate expectations change while files remain -> GREEN: no drift, new contract auto-discovered, deleted test absent from gate script. | Restore the removed manifest/gate row or omit the new contract from discovery -> inventory/discovery proof red. | Isolated-index `./scripts/run_test_gates.sh runtime-roots`; `./scripts/run_host_test_gates.sh feature-host-all --list`; `./scripts/run_test_gates.sh groups`. |

### Test Notes

- TC-JOIN-01 constructs the retired filename and camel-case symbol from split
  fragments so the contract itself never becomes a false caller. It fails
  closed if an owned root cannot be enumerated/read. It scans only current C4
  claims; historical `UI-19-Groups/TDD_PLAN_*` evidence is excluded.
- TC-JOIN-02 is a pre-edit stop condition, not deletion authorization by itself.
  The recorded owner decision supplies authorization; any extra caller or export
  requires replanning.
- TC-JOIN-05 is preservation proof, not a claim that this leaf deletion changes
  native/Go behavior. A device test would be non-causal because every live
  boundary file is protected from change.

## Implementation Steps

1. Snapshot `git rev-parse HEAD`, `git status --short`, and the real index.
   Require every removal-fragment file and all TC-JOIN-03/04/05 preservation
   paths to be clean against the selected execution baseline; otherwise stop
   rather than absorb unrelated changes.
2. Run and record `DTR10-JOIN-CALLER-01`. Stop on any count other than one
   `joinGroup` declaration, seven dedicated-test calls, the six enumerated
   `commitFreshDirectJoin` tokens, and zero other owned-source exact
   references/imports/exports.
3. Add TC-JOIN-01 first without using the exact retired camel-case identifier
   literally; run its causal RED and record that it fails only because the
   authorized artifacts still exist.
4. Delete the old source and dedicated suite. Remove the exact orphaned
   `commitFreshDirectJoin` interface/implementation/fake/stub fragments and its
   one dedicated repository test block. Remove only the source's
   `runtime_roots.json` declaration and the deleted suite's `GROUP_TESTS`
   entry. Do not edit live bridge, invite, rejoin, native, generated, Go,
   shared persistence, or key code.
5. Update current DTR-10 decision/compatibility/index bookkeeping and the three
   current C4 files with the explicit owner disposition, exact removed scope,
   intentional live transient-retry semantics, and preserved full-config
   boundary. Do not rewrite historical receipts.
6. Run TC-JOIN-01 GREEN, final negative census, runtime-root/discovery proof,
   named preservation selectors, real Go selectors, `groups`, and the justified
   `feature-host-all` sweep.
7. Run strict analysis, completeness, incremental Graphify refresh, and diff
   hygiene. Stop-if any replacement/native/Go path changed or a preservation
   selector fails.

## Risks And Blind Spots

- A hidden caller would turn deletion into an API break -> fail-closed
  TC-JOIN-02 whole-owned-source census before editing.
- Source-only deletion would leave a misleading downstream admission
  capability -> TC-JOIN-01/02 require zero `commitFreshDirectJoin` tokens while
  TC-JOIN-03 preserves the live accepted-reentry coordinator.
- Full-config behavior was partly asserted by the deleted suite -> TC-JOIN-03
  through TC-JOIN-05 retain independent live-path, mapping, and Go proofs.
- Runtime manifest or curated gate could retain a ghost path -> TC-JOIN-01/06.
- Lifecycle / derived-state durability: preserved by the live accepted-invite
  and startup/rejoin selectors; no state transition is added.
- Sibling-surface consistency: invite materialization and lifecycle rejoin are
  intentionally different surfaces with named sentinels in TC-JOIN-03.
- Destructive-action side effects: deletion is restricted to two whole files,
  five exact dead method/test/fake fragments, and exact bookkeeping rows;
  focused repository preservation plus protected-path no-diff guard all live
  join, persistence, key, and native behavior.
- Invariant re-verification under new transitions: N/A — no new transition is
  introduced.

## Gate Cadence

- Per-plan closure: causal source contract, exact caller/final census, live
  invite/rejoin and bridge/Go sentinels, isolated `runtime-roots`, `groups`, and
  the justified `feature-host-all` sweep because an app-owned feature source and
  curated group test are removed.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the DTR-10/Wave-3
  dependency batch is complete, and once at final DTR rollout/release closure.
- Shared tests outside feature/core globs: the Go bridge selectors and
  `runtime-roots` are run by their exact commands below.

## Acceptance Gates

Run from the repository root. Every non-RED command must exit `0` with zero
failed tests or new issues.

```bash
# Snapshot before execution; preserve unrelated work
git rev-parse HEAD
git status --short
git diff --cached --name-status

# Pre-edit DTR10-JOIN-CALLER-01; expect exact isolated shape
test "$(rg -o '\bjoinGroup\b' \
  lib/features/groups/application/join_group_use_case.dart | wc -l | tr -d ' ')" -eq 1
test "$(rg -o '\bjoinGroup\b' \
  test/features/groups/application/join_group_use_case_test.dart | wc -l | tr -d ' ')" -eq 7
for candidate_file in \
  lib/features/groups/application/join_group_use_case.dart \
  lib/features/groups/domain/repositories/group_repository.dart \
  lib/features/groups/domain/repositories/group_repository_impl.dart \
  test/shared/fakes/in_memory_group_repository.dart \
  test/features/groups/application/delete_self_removed_group_shell_use_case_test.dart \
  test/features/groups/domain/repositories/group_repository_impl_test.dart; do
  test "$(rg -o '\bcommitFreshDirectJoin\b' "$candidate_file" |
    wc -l | tr -d ' ')" -eq 1
done
test "$(rg -o --glob '*.dart' '\bcommitFreshDirectJoin\b' \
  lib test integration_test test_driver tool packages scripts ./*.dart |
  wc -l | tr -d ' ')" -eq 6
if rg -n \
  --glob '*.dart' \
  --glob '!lib/features/groups/application/join_group_use_case.dart' \
  --glob '!test/features/groups/application/join_group_use_case_test.dart' \
  '\bjoinGroup\b' \
  lib test integration_test test_driver tool packages scripts ./*.dart; then
  exit 1
else
  DTR10_JOIN_RG_STATUS=$?
  test "$DTR10_JOIN_RG_STATUS" -eq 1
fi
if rg -n \
  --glob '*.dart' \
  --glob '!test/features/groups/application/join_group_use_case_test.dart' \
  'join_group_use_case\.dart' \
  lib test integration_test test_driver tool packages scripts ./*.dart; then
  exit 1
else
  DTR10_JOIN_IMPORT_STATUS=$?
  test "$DTR10_JOIN_IMPORT_STATUS" -eq 1
fi

# Causal RED after scaffolding TC-JOIN-01, before deletion:
# expect non-zero only because the authorized source/test/records remain
flutter test --no-pub \
  test/features/groups/application/old_join_group_removal_contract_test.dart \
  --plain-name 'DTR10-JOIN-01 old direct join island and bookkeeping are absent'

# Focused GREEN after exact deletion/bookkeeping update
flutter test --no-pub \
  test/features/groups/application/old_join_group_removal_contract_test.dart
test ! -e lib/features/groups/application/join_group_use_case.dart
test ! -e test/features/groups/application/join_group_use_case_test.dart
if rg -n --glob '*.dart' \
  '\bjoinGroup\b|\bcommitFreshDirectJoin\b|join_group_use_case\.dart' \
  lib test integration_test test_driver tool packages scripts ./*.dart; then
  exit 1
else
  DTR10_JOIN_FINAL_STATUS=$?
  test "$DTR10_JOIN_FINAL_STATUS" -eq 1
fi
if rg -nF 'test/features/groups/application/join_group_use_case_test.dart' \
  scripts/run_test_gates.sh; then
  exit 1
else
  DTR10_JOIN_GATE_STATUS=$?
  test "$DTR10_JOIN_GATE_STATUS" -eq 1
fi

# Live invitation/rejoin preservation
flutter test --no-pub \
  test/features/groups/application/accept_pending_group_invite_use_case_test.dart \
  --plain-name 'accepts pending invite, persists group, and drains inbox'
flutter test --no-pub \
  test/features/groups/application/handle_incoming_group_invite_use_case_test.dart \
  --plain-name \
  'calls group:join bridge command with groupId, groupConfig, groupKey, keyEpoch'
# Admission-totality sentinels named in TC-JOIN-03.
flutter test --no-pub \
  test/features/groups/application/handle_incoming_group_invite_use_case_test.dart
flutter test --no-pub \
  test/features/groups/application/rejoin_group_topics_use_case_test.dart \
  --plain-name 'calls callGroupJoinWithConfig for each active group'
flutter test --no-pub \
  test/features/groups/application/rejoin_group_topics_use_case_test.dart \
  --plain-name 'builds correct groupConfig from stored members'
flutter test --no-pub \
  test/features/groups/domain/repositories/group_repository_impl_test.dart \
  --plain-name \
  'duplicate retry holds the per-group coordinator through native join'

# Exact Dart helper and MethodChannel preservation
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart \
  --plain-name \
  'sends group:join with groupId, groupConfig, groupKey, keyEpoch'
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart \
  --plain-name \
  'BB-007 callGroupJoinWithConfig forwards exact full config payload to groupJoinTopic'

# Native/generated/Go preservation; protected files must remain unchanged
git diff HEAD --quiet -- \
  lib/core/bridge/bridge_group_helpers.dart \
  lib/core/bridge/go_bridge_client.dart \
  lib/features/groups/application/accept_pending_group_invite_use_case.dart \
  lib/features/groups/application/handle_incoming_group_invite_use_case.dart \
  lib/features/groups/application/rejoin_group_topics_use_case.dart \
  android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt \
  ios/Runner/GoBridge.swift \
  macos/Runner/MainFlutterWindow.swift \
  go-mknoon/bridge/bridge.go \
  go-mknoon/node/pubsub.go
./scripts/verify_gomobile_bindings.sh all
(
  cd go-mknoon
  GOTOOLCHAIN=go1.25.0 go test ./bridge \
    -run '^(TestGroupJoinTopic_BB006RejectsLegacyTopicNameOnlyPayload|TestGroupJoinTopic_RejectsInvalidKeyState|TestSV009GroupJoinAndUpdateConfigRejectMalformedMemberKeys|TestGroupJoinTopic_RejectsIncompleteActiveMemberKeyMaterial|TestGroupJoinTopic_RejectsMalformedActiveDeviceTransportPeerId|TestGroupJoinTopic_BB007RoundTripsFullConfigAndAcceptsPublish|TestGroupJoinTopic_AlreadyJoinedIsIdempotent|TestGroupJoinTopic_BB008AlreadyJoinedRefreshesNewerKeyAndConfig)$' \
    -count=1
)

# Real final-tree runtime-root gate without touching the user's real index
DTR10_JOIN_INDEX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dtr10-join-index.XXXXXX")"
trap 'rm -rf -- "${DTR10_JOIN_INDEX_DIR:?}"' EXIT
GIT_INDEX_FILE="$DTR10_JOIN_INDEX_DIR/index" git read-tree HEAD
GIT_INDEX_FILE="$DTR10_JOIN_INDEX_DIR/index" git add -A -- \
  lib/features/groups/application/join_group_use_case.dart \
  lib/features/groups/domain/repositories/group_repository.dart \
  lib/features/groups/domain/repositories/group_repository_impl.dart \
  test/features/groups/application/join_group_use_case_test.dart \
  test/features/groups/application/old_join_group_removal_contract_test.dart \
  test/features/groups/application/delete_self_removed_group_shell_use_case_test.dart \
  test/features/groups/domain/repositories/group_repository_impl_test.dart \
  test/shared/fakes/in_memory_group_repository.dart \
  tool/runtime_roots/runtime_roots.json \
  scripts/run_test_gates.sh
GIT_INDEX_FILE="$DTR10_JOIN_INDEX_DIR/index" \
  ./scripts/run_test_gates.sh runtime-roots

# Discovery, affected curated lane, and justified feature sweep
./scripts/run_host_test_gates.sh feature-host-all --list |
  rg -nF \
  'test/features/groups/application/old_join_group_removal_contract_test.dart'
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all \
  --continue-on-failure \
  --batch-flutter \
  --concurrency 1 \
  --reporter failures-only

# Hygiene and graph refresh
./scripts/check_flutter_analyze_strict.sh
./scripts/run_test_gates.sh completeness-check
./graphify-arch/refresh_arch_graph.sh --incremental
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-JOIN-01 exits non-zero only because the authorized old
  source/test/manifest/gate artifacts still exist.
- Green sentinels: TC-JOIN-03 through TC-JOIN-05 preserve live invite, rejoin,
  bridge, native, generated, Go, key, and epoch behavior.
- Pre-existing dirty tree / known failure: snapshot and preserve it; any
  overlapping dirty removal/protected path is scope drift requiring a new
  baseline.
- Environment blocker: none; host Dart and real Go unit tools are sufficient.
- Scope drift: any live caller, native/Go/mapping diff, schema/key change, or
  preservation failure blocks completion.

- [x] Every behavior has a named test or justified proof.
- [x] Causal RED, focused GREEN, and representative restore/tear-off mutation
      re-red are recorded.
- [x] Preservation and named gates pass with semantic outcomes.
- [x] AUTO registration and deleted curated-entry removal are verified.
- [x] `flutter analyze` strict wrapper has no new issues; `git diff --check` is
      clean.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command:
  `flutter test --no-pub test/features/groups/application/old_join_group_removal_contract_test.dart --plain-name 'DTR10-JOIN-01 old direct join island and bookkeeping are absent'`.
- Preservation command:
  `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'accepts pending invite, persists group, and drains inbox'`.
- Manual registration: remove the deleted suite from `GROUP_TESTS`; the new
  contract is AUTO feature-host. The source census, runtime-roots isolated
  index, native no-diff, binding verifier, and Go selectors are manual exact
  proofs.
- Migration: none.
- Boundary closure: host-only plus real Go unit preservation; no production
  wire/native/crypto change and no causal simulator/device obligation.
- Unresolved evidence: none for bounded deletion. A new open/link admission
  feature requires separate authorization and planning.

## Reviewer Findings

- Verdict: `ready` after the bounded review fix below; core bet confirmed and
  disposition `execute`.
- Counterexample census confirmed exactly one declaration and seven
  dedicated-suite calls, with no other owned Dart caller/import/export; package
  publication is disabled.
- Required fix applied to this plan: source-only deletion would leave the raw
  six-token `commitFreshDirectJoin` seam as a public production orphan. Its
  declaration, implementation, two fake/stub overrides, and sole dedicated
  repository test block now retire atomically with the use case, while
  `rollbackFreshAcceptedMaterialization` remains because accepted-invite
  admission calls it.
- Required fix applied to this plan: the fail-closed census and causal contract
  now include `test`, `scripts`, and root Dart files and distinguish both
  retired identifiers, so a tear-off/export or raw repository residue cannot
  pass through an omitted owned-source root.
- Material fix: expanded live-admission proof to cover complete roster/self
  role, malformed material, intentional transient rejoin enrollment, and
  retained-removal-floor authority, plus the live duplicate-retry coordinator.
  The old native-before-persist rollback is explicitly not preserved.
- Material fix: added present-tense C4 cleanup to the causal contract while
  excluding historical `UI-19-Groups` plans.
- Five lenses after revision: evidence truth, Test Contract causality,
  bypass/scope safety, gate integrity, and reversibility are clear. Blind-spot
  hits B-2/B-3/B-4/B-5/B-9 are closed by the revised census, zero-token
  contract, exact fragment scope, and live coordinator sentinel; B-1/B-6/B-8/
  B-10 are N/A and B-7 is clear. No status, closure-tier, device profile, or
  gate-cadence change is required.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-26 | review and baseline | Plan 277; old direct source/suite; repository interface/implementation/fakes/test; live invite/rejoin/bridge seams | `$tdd-review` verdict `ready` after one bounded scope fix; legacy suite `+7`; causal contract RED only on the still-present authorized source | One declaration, seven SUT-only calls, six direct-only repository tokens, and zero other owned caller/import/export; review identified `commitFreshDirectJoin` as the only orphan that source-only deletion would leave | Core bet confirmed; no user or environment blocker | Retire the exact direct-join island |
| 2026-07-26 | causal implementation | Two deleted files; five repository/fake/test fragments; runtime-root/gate/C4/current-roadmap records; new removal contract | TC-JOIN-01 GREEN; temporary `commitFreshDirectJoin` mutation fixture re-red, then GREEN after fixture removal; final census exited 0 | 594 retired lines: two whole files plus 124 direct-only seam/test/fake lines; zero retired identifier/import/gate residue; protected live invite/rejoin/native/Go paths unchanged | Scope contract held | Run preservation and closure gates |
| 2026-07-26 | preservation and closure | TC-JOIN-03 through TC-JOIN-06 surfaces; groups and feature host families; analysis; Graphify | All named Dart selectors GREEN; bindings verifier and eight Go join tests GREEN; isolated `runtime-roots` 16/16; `groups` Flutter `+3297` plus Go gates; `feature-host-all` `+8543 ~1` across 821 paths; strict analysis no issues; completeness 1354/1354; `git diff --check` clean | Live full-config invite/rejoin, accepted-reentry coordination, keys/epochs, MethodChannel/native/Go behavior preserved; new contract auto-discovered; architecture graph refreshed once at current fingerprint `b04644b8f017826a` | `Plan-green`; no DTR-10 Plan 277 blocker | Keep Plan 278 and later DTR-10 dispositions separate |
