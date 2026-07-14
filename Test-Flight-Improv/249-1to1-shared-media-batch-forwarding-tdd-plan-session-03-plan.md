# Plan 249 Session 03 — Independent acceptance, mutations, and closure synchronization

Status: accepted
Source: `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan-session-breakdown.md` Session 03
Run mode: acceptance-only
Classification: host-only independent aggregate acceptance
Dependency: Plan 249 Sessions 01 and 02 are accepted and closed; Plan 234 Session 04 remains accepted and closed

## Planning Progress

| Time | Role / phase | Evidence or decision | Next action |
|---|---|---|---|
| 2026-07-11 | Evidence Collector | Read the complete accepted Session-01/02 plans, current Plan-249 source/breakdown, gate definitions, executable arrays, index, closure reference, landed production/tests, and the execution-discovered `ConversationWired` inventory sentinel. | Freeze an acceptance-only combined proof; do not reopen accepted implementation history. |
| 2026-07-11 | Graphify TDD grounding | Compact TDD query anchored `ONE_TO_ONE_TESTS`, `ONE_TO_ONE_HOST_TESTS`, and `ConversationWired` (`confidence=anchored`, fingerprint `267da0ce729dc520`). Graph freshness was stale only because of concurrent `audio_player_widget.dart` work; current source verified all Plan-249 anchors. | Use current source/tests and both arrays as execution truth; no graph refresh belongs to this doc-only session. |
| 2026-07-11 | Acceptance planner | D-249-01..07 require combined causal reruns, nine reversible mutations, registration/static/scope proof, fresh independent QA, durable docs, and a separate closure review. | Obtain independent plan review before executing any gate or mutation. |
| 2026-07-11 | Independent plan reviewer | Reviewed the reproducible 42-path manifest/aggregate, literal forbidden scope, race-safe inverse protocol, nine compilable causal mutations, per-authority registrations, analyzer alignment, sentinel inclusion, obsolete-sentinel exclusion, cadence, and closure ownership through two correction bundles. | `ACCEPTED`; execution may capture a fresh baseline and begin mutations. No gate, mutation, or Graphify refresh ran during review. |

## Execution Preflight And Current Baseline

- Sessions 01 and 02 are immutable accepted evidence. Session 03 plans no production or test implementation and must not recreate their RED history.
- The worktree is shared and intentionally dirty. Never reset, stash, revert, checkout, overwrite, or attribute unrelated work. Concurrent Plan-255/256 and other rollout changes are baseline.
- Historical planning snapshot at `2026-07-11 22:30:20 CEST`: HEAD `84e8ead5d98928d60b1581bdb517b0f307503c35`; this plan was absent; the planner recorded aggregate `8ae6ec3a0c2ebe34a1eb44353988f63d57821df243f92358bc48177c9afa7b54` and a 146-path forbidden status fingerprint `819d01e328998c25d65e39e8fcaf5e870567a3170581e01a58b38c67fdde88af`. Those values are historical path-list evidence only, not the execution comparison baseline.
- Before gates, capture `git status --short`, individual SHA-256/status for all 42 paths, the aggregate, the forbidden list/hash, and a full-analyzer issue fingerprint. Recheck them after every mutation and before QA.

The reproducible ordered 42-path manifest and aggregate algorithm are:

```bash
readonly SESSION_03_PATHS=(
  lib/features/conversation/application/build_direct_media_library_batch_forward.dart
  lib/features/conversation/application/received_media_action_controller.dart
  lib/features/share/application/direct_media_batch_forward_delivery_coordinator.dart
  lib/features/share/application/share_batch_delivery_coordinator.dart
  lib/features/share/presentation/screens/direct_media_batch_forward_picker_screen.dart
  lib/features/share/presentation/screens/direct_media_batch_forward_picker_wired.dart
  lib/features/share/presentation/navigation/direct_media_batch_forward_picker_route.dart
  lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart
  lib/features/conversation/presentation/screens/conversation_wired.dart
  lib/l10n/app_en.arb
  lib/l10n/app_de.arb
  lib/l10n/app_ar.arb
  lib/l10n/app_localizations.dart
  lib/l10n/app_localizations_en.dart
  lib/l10n/app_localizations_de.dart
  lib/l10n/app_localizations_ar.dart
  test/features/conversation/application/build_direct_media_library_batch_forward_test.dart
  test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart
  test/features/share/application/share_batch_delivery_coordinator_test.dart
  test/features/share/presentation/direct_media_batch_forward_picker_wired_test.dart
  test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart
  test/features/conversation/application/direct_media_batch_forward_transport_boundary_test.dart
  test/features/conversation/application/received_media_action_transport_boundary_test.dart
  test/features/conversation/application/private_media_action_eligibility_test.dart
  test/features/conversation/application/direct_private_media_boundary_test.dart
  test/features/conversation/application/received_media_action_controller_test.dart
  test/features/conversation/application/build_received_media_forward_test.dart
  test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart
  test/features/conversation/application/direct_media_library_batch_actions_test.dart
  test/features/conversation/application/direct_media_library_boundary_test.dart
  test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart
  test/features/share/presentation/share_target_picker_wired_test.dart
  test/l10n/l10n_integrity_test.dart
  test/core/l10n/app_localizations_signal_test.dart
  Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan-session-03-plan.md
  Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan.md
  Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan-session-breakdown.md
  Test-Flight-Improv/test-gate-definitions.md
  scripts/run_test_gates.sh
  scripts/run_host_test_gates.sh
  Test-Flight-Improv/00-INDEX.md
  Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md
)

session_03_manifest() {
  local file_path
  for file_path in "${SESSION_03_PATHS[@]}"; do
    test -e "$file_path"
    shasum -a 256 "$file_path"
  done
}

session_03_manifest | shasum -a 256

session_03_forbidden_scope() {
  local line file_path allowed
  git status --porcelain=v1 --untracked-files=all | while IFS= read -r line; do
    file_path="${line:3}"
    allowed=false
    for candidate in "${SESSION_03_PATHS[@]}"; do
      if [[ "$file_path" == "$candidate" ]]; then
        allowed=true
        break
      fi
    done
    if [[ "$allowed" == false ]]; then
      printf '%s\n' "$line"
    fi
  done | LC_ALL=C sort
}

session_03_forbidden_scope
session_03_forbidden_scope | shasum -a 256
```

Capture fresh execution values from these literal functions after this plan is
reviewed. Final mutation restoration compares every mutation-owned file and the
42-path aggregate to that fresh execution baseline. Every forbidden-list delta
is inspected as concurrent shared movement or a blocker; historical
`8ae6...`/`819d...` equality is not required.

## Objective And Acceptance Boundary

Independently accept the complete landed Plan-249 feature only if current evidence proves:

1. `1..10` exact current direct visual sources remain atomic, canonically ordered, independently captioned, and independently tokened.
2. One ordinary recipient-scoped message is attempted per eligible attachment/contact cell, with truthful `sent`/`queued`/`failed` settlement and failed-cell-only retry.
3. Current source and contact revalidation precede file/contact/delivery work; private, terminal, stale, corrupt, wrong-owner, group, and unresolved sources fail closed.
4. The dedicated picker exposes direct contacts only, keeps selection/result truth, and preserves ordinary Plan-232/233/234 and generic-share behavior.
5. No schema/version/registry, wire/codec, Go/relay, group/announcement, native/device, or viewer contract is attributable to Plan 249.

If a mutation survives, a causal gate fails, or QA finds a production/test defect, stop and reopen the owning Session 01 or 02 with concrete regression evidence. Session 03 does not patch production or tests.

## Exact Combined Scope

Production owners, all read-only in this session:

- `lib/features/conversation/application/build_direct_media_library_batch_forward.dart`
- `lib/features/share/application/direct_media_batch_forward_delivery_coordinator.dart`
- `lib/features/share/application/share_batch_delivery_coordinator.dart`
- `lib/features/share/presentation/screens/direct_media_batch_forward_picker_screen.dart`
- `lib/features/share/presentation/screens/direct_media_batch_forward_picker_wired.dart`
- `lib/features/share/presentation/navigation/direct_media_batch_forward_picker_route.dart`
- `lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/l10n/app_en.arb`, `app_de.arb`, `app_ar.arb`
- `lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_de.dart`, `app_localizations_ar.dart`

Combined proof files, all read-only except one-at-a-time temporary mutations of production followed by exact inverse patches:

- Session 01: `build_direct_media_library_batch_forward_test.dart`.
- Session 02 primary: `direct_media_batch_forward_delivery_coordinator_test.dart`, `share_batch_delivery_coordinator_test.dart`, `direct_media_batch_forward_picker_wired_test.dart`, `conversation_shared_media_batch_forward_test.dart`, and `direct_media_batch_forward_transport_boundary_test.dart`.
- Execution-discovered wiring sentinel: `received_media_action_transport_boundary_test.dart`.
- Plan-234: `private_media_action_eligibility_test.dart`, `direct_private_media_boundary_test.dart`, and `received_media_action_controller_test.dart`.
- Plan-232: `build_received_media_forward_test.dart` and `forwarded_media_retry_roundtrip_test.dart`.
- Plan-233: `direct_media_library_batch_actions_test.dart`, `direct_media_library_boundary_test.dart`, and `conversation_shared_media_library_test.dart`.
- Generic picker and l10n: `share_target_picker_wired_test.dart`, `l10n_integrity_test.dart`, and `app_localizations_signal_test.dart`.

The historical Session-01 exact action-absence test named `batch forward stays absent while only draft preflight is landed` is expressly retired as a Session-03 acceptance claim. Exclude that one temporal sentinel; current nullable-action and injected-action behavior is owned by the Session-02 screen suites. Do include the execution-discovered exact received-transport inventory sentinel.

## Reversible Mutation Protocol

Run one representative mutation at a time, using `apply_patch` only:

1. Record the target's exact pre-mutation SHA-256 and `git status --porcelain=v1 -- <target>` output, including its pre-existing dirty state.
2. Apply one minimal mutation, run only its named exact test, and require a causal failure for the intended assertion.
3. Record the intended post-mutation SHA-256. Immediately before inverse patching, re-read the target hash/status and require that they still equal that recorded post-mutation snapshot. If either moved, stop before writing so concurrent same-file work is never overwritten.
4. Apply the exact inverse patch. Never use `git reset`, `git revert`, `git checkout`, stash, a copied clean file, or whole-file replacement.
5. Require the restored SHA-256 and status output to equal the per-mutation snapshot, then rerun the same exact test green.
6. If another process changes the target before restoration, stop; do not overwrite concurrent work. Preserve both hashes and coordinate before continuing.

Required representatives:

| Mutation | Target / minimal fault | Exact test that must turn red, then green |
|---|---|---|
| source-order reversal | Reverse `_compareSourcesNewestFirst` in the Session-01 builder | `sorts reverse tap order and same-parent siblings by the canonical library keyset` |
| same-parent coalescing | In the builder item loop, skip a source when an already-built item has the same `messageId`, thereby dropping a same-parent sibling while remaining compilable | same canonical-order/sibling test |
| edited-caption collapse | In `DirectMediaLibraryBatchForwardItemDraft.copyWith`, assign `this.caption` instead of the supplied `caption` | `dispatch revalidation preserves edited captions and tokens while refreshing paths scope kind and order` |
| token remint | During dispatch revalidation, replace the original operation key with a deterministic `-reminted` value | `dispatch revalidation preserves edited captions and tokens while refreshing paths scope kind and order` |
| private-policy bypass | In `received_media_action_controller.dart`, make the central `privateAvailable` branch continue and make the default qualifier return `eligible` for that same reason; this two-anchor temporary fault remains compilable and authorizes the otherwise denied current row | `qualifies every exact current direct visual source atomically` |
| source-preflight bypass | In `deliverInitial`, assign `canonical = draft` instead of awaiting `_revalidate`; contact/delivery work then starts despite source denial | `source denial precedes contact lookup and every ordinary delivery call` |
| invalid-target exposure proxy | Remove the blocked/archived filters in `_loadContacts`; separately retain the static no-group import/repository audit because no compilable group seam exists | `dedicated picker loads active direct contacts only and edits captions independently` |
| queued/sent replay | Change the `retryFailed` filter from `status == failed` to `status != failed` | `failed-cell retry is sparse and preserves each source caption and token` |
| matrix flattening | In `deliverInitial` pending-map construction, retain only `contactPeerIds.take(1)` for each source | `two canonical sources by two active contacts produce four source-major ordinary cells` |

After all mutations, the 42-path aggregate and every production/test hash must match the fresh execution baseline. Mutation evidence is invalid if restoration is inferred only from a passing test.

## Literal Acceptance Gates

Run from the repository root and record exact exit status/counts.

```bash
# Fresh status/hash/scope and registration truth.
git status --short
for suite in \
  test/features/conversation/application/build_direct_media_library_batch_forward_test.dart \
  test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart \
  test/features/share/presentation/direct_media_batch_forward_picker_wired_test.dart \
  test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart \
  test/features/conversation/application/direct_media_batch_forward_transport_boundary_test.dart; do
  for authority in scripts/run_test_gates.sh scripts/run_host_test_gates.sh Test-Flight-Improv/test-gate-definitions.md; do
    rg -qF "$suite" "$authority"
  done
done
for authority in scripts/run_test_gates.sh scripts/run_host_test_gates.sh; do
  rg -qF 'test/features/conversation/application/received_media_action_transport_boundary_test.dart' "$authority"
done
! rg -n "features/groups|GroupRepository|GroupModel|announcement" lib/features/share/presentation/screens/direct_media_batch_forward_picker_screen.dart lib/features/share/presentation/screens/direct_media_batch_forward_picker_wired.dart lib/features/share/presentation/navigation/direct_media_batch_forward_picker_route.dart

# Session 01.
flutter test test/features/conversation/application/build_direct_media_library_batch_forward_test.dart

# Session 02 primary five-file batch.
flutter test test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart test/features/share/application/share_batch_delivery_coordinator_test.dart test/features/share/presentation/direct_media_batch_forward_picker_wired_test.dart test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart test/features/conversation/application/direct_media_batch_forward_transport_boundary_test.dart

# Execution-discovered ConversationWired inventory sentinel.
flutter test test/features/conversation/application/received_media_action_transport_boundary_test.dart --plain-name 'received media egress call sites and wired transport baseline are exact'

# Plan 234 exact-current authority.
flutter test test/features/conversation/application/private_media_action_eligibility_test.dart test/features/conversation/application/direct_private_media_boundary_test.dart test/features/conversation/application/received_media_action_controller_test.dart

# Plan 232 one-source Forward and durable retry.
flutter test test/features/conversation/application/build_received_media_forward_test.dart test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart

# Plan 233 preservation. Exclude only the obsolete Session-01 temporal sentinel.
flutter test test/features/conversation/application/direct_media_library_batch_actions_test.dart test/features/conversation/application/direct_media_library_boundary_test.dart
flutter test test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart --name '^(?!batch forward stays absent while only draft preflight is landed$).*'

# Generic picker and localization preservation.
flutter test test/features/share/presentation/share_target_picker_wired_test.dart
flutter gen-l10n
flutter test test/l10n/l10n_integrity_test.dart test/core/l10n/app_localizations_signal_test.dart

# Proportional named gates. Full host-all remains Wave-1-owned.
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh 1to1 --list
./scripts/run_test_gates.sh completeness-check

# Static and hygiene gates across every attributable Dart owner/proof.
dart format --output=none --set-exit-if-changed lib/features/conversation/application/build_direct_media_library_batch_forward.dart lib/features/share/application/direct_media_batch_forward_delivery_coordinator.dart lib/features/share/application/share_batch_delivery_coordinator.dart lib/features/share/presentation/screens/direct_media_batch_forward_picker_screen.dart lib/features/share/presentation/screens/direct_media_batch_forward_picker_wired.dart lib/features/share/presentation/navigation/direct_media_batch_forward_picker_route.dart lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart lib/features/conversation/presentation/screens/conversation_wired.dart lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_ar.dart test/features/conversation/application/build_direct_media_library_batch_forward_test.dart test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart test/features/share/application/share_batch_delivery_coordinator_test.dart test/features/share/presentation/direct_media_batch_forward_picker_wired_test.dart test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart test/features/conversation/application/direct_media_batch_forward_transport_boundary_test.dart test/features/conversation/application/received_media_action_transport_boundary_test.dart
dart analyze lib/features/conversation/application/build_direct_media_library_batch_forward.dart lib/features/conversation/application/received_media_action_controller.dart lib/features/share/application/direct_media_batch_forward_delivery_coordinator.dart lib/features/share/application/share_batch_delivery_coordinator.dart lib/features/share/presentation/screens/direct_media_batch_forward_picker_screen.dart lib/features/share/presentation/screens/direct_media_batch_forward_picker_wired.dart lib/features/share/presentation/navigation/direct_media_batch_forward_picker_route.dart lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart lib/features/conversation/presentation/screens/conversation_wired.dart lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_ar.dart test/features/conversation/application/build_direct_media_library_batch_forward_test.dart test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart test/features/share/application/share_batch_delivery_coordinator_test.dart test/features/share/presentation/direct_media_batch_forward_picker_wired_test.dart test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart test/features/conversation/application/direct_media_batch_forward_transport_boundary_test.dart test/features/conversation/application/received_media_action_transport_boundary_test.dart
git diff --check
```

Run `flutter analyze` once before mutations and once on the restored final candidate. Record exit codes, issue counts, and a sorted issue fingerprint. A nonzero shared baseline is acceptable only if the final fingerprint adds no Plan-249 or Session-03 issue. The scoped analyzer above intentionally covers every attributable Dart owner (including generated l10n) and the seven headline Plan-249 proofs; preservation proofs are executed by their exact test commands rather than relabeled as analyzer inputs. Do not edit unrelated analyzer findings.

Recompute the exact 42-path aggregate. Recompute the full dirty status list after removing only the Plan-249 combined files and authorized closure documents; compare its 146-path/`819d01...` planning snapshot and inspect every delta. Concurrent shared movement may explain a new hash, but no persistent production/test mutation or schema/version/registry, codec/wire, Go/relay, group/announcement, Android/iOS/native, device, or viewer path may be attributed to Session 03.

## Independent QA And Closure Workflow

1. After all restored mutations and literal gates pass, obtain fresh QA from a reviewer independent of the Session-01/02 executors and the Session-03 mutation operator.
2. QA reviews D-249-01..07, complete attributable production/tests, mutation evidence and exact hash restoration, registrations, analyzer comparison, scope attribution, ordinary-message/encryption truth, and all gate output. `fix_passes=0` initially. A production/test finding reopens its owning implementation session; it is not fixed here.
3. Only after QA accepts, update this plan, the source Plan 249, the session breakdown, `00-INDEX.md`, `19-1to1-message-reliability-closure-reference.md`, and `test-gate-definitions.md`. Edit gate arrays only if the registration audit finds a real omission; otherwise preserve them byte-for-byte.
4. Run a separate closure reviewer after documentation synchronization. The reviewer verifies exact counts, accepted differences, queued/persisted retry ownership, no overclaim, all ledger/status/checklist transitions, stable maintenance guidance, and shared-tree attribution.
5. Session 03 is accepted only after that closure review accepts. No Graphify refresh runs: this session is documentation/acceptance-only and all temporary production mutations must be exactly restored.

## Closure-document Contract

- Source Plan 249: set `Status: accepted`, check Session-03/done criteria, append exact aggregate evidence and final verdict `accepted`.
- Breakdown: set overall status accepted/closed, mark Session 03 accepted, preserve D-249-01..07 and accepted differences, and record no remaining blocker.
- `00-INDEX.md`: change Plan 249 from stale `Evidence-gated` to `Accepted` with its direct-only ordinary-send boundary; remove Plan 249 from any stale unresolved-common-semantics sentence without changing Plans 250/251.
- Closure reference: append the Plan-249 maintenance boundary—atomic exact-current direct visual sources, canonical source-major ordinary messages, independent captions/tokens, direct contacts only, truthful matrix, failed-cell-only in-route retry, and existing persisted retry ownership.
- Gate definitions: retain all five Plan-249 suites in both arrays, add Session-03 aggregate/mutation/closure evidence, and keep executable arrays authoritative.
- This plan: set `Status: accepted`, append `## Execution Result` and `## Closure Audit`, including fresh counts, analyzer/scope fingerprints, QA verdict, `fix_passes`, closure-review verdict, and the explicit statement that no Graphify refresh ran.

## Strict Non-goals

- No production/test implementation, new RED, schema/migration/v101, wire/codec, Go/relay, group/announcement, native/device, viewer, actual PiP, Plan-234/247/238 work, or excluded-plan work.
- No full `host-all`, `core-host-all`, `feature-host-all`, performance family, device, SQLCipher, native, Go, or relay gate. Wave 1 owns aggregate `host-all` and availability-bounded device proof.
- No incremental or full Graphify refresh. A read-only compact query is sufficient for this acceptance-only session.

## Done Criteria

- [x] Fresh execution baseline, 42-path aggregate, forbidden scope, and analyzer fingerprint are recorded.
- [x] Every literal focused command and the exact received-transport sentinel pass; the obsolete Session-01 temporal sentinel is excluded.
- [x] All nine representative mutations fail causally, restore by inverse `apply_patch` to exact pre-mutation hashes/status, and rerun green.
- [x] Curated `1to1`, host list, completeness, registration, l10n, formatter, scoped/full analyzer comparison, diff, and scope checks pass.
- [x] No persistent production/test or forbidden boundary change is attributable to Session 03.
- [x] Fresh independent QA accepts with no unresolved finding.
- [x] Source, breakdown, index, closure reference, and gate definitions agree on accepted Plan 249 and its maintenance boundary.
- [x] Separate closure review accepts the synchronized record.
- [x] No Graphify refresh runs, and Plan 249 is finally `accepted`/closed.

## Execution Progress

| Time | Phase | Evidence | Result / next |
|---|---|---|---|
| 2026-07-11 22:30 CEST | planning baseline | HEAD/status; 42-path aggregate `8ae6ec3...`; forbidden status list 146 paths / `819d01e3...`; Session-03 plan absent; anchored compact Graphify query | Shared dirty tree preserved. Plan authored only; no gate, analyzer, mutation, production/test edit, or Graphify refresh ran. Await independent plan review. |
| 2026-07-11 | independent plan review | Reproducible 42-path manifest/algorithm, literal forbidden scope, race-safe inverse protocol, concrete compilable mutations, per-authority registrations, analyzer alignment, cadence, and closure ownership | `ACCEPTED` after two correction bundles; execution-ready with no plan-time gate or refresh. |
| 2026-07-11 | fresh execution baseline | Complete status, first 42-path aggregate `b57dae187a309af2f20483728fa4cd58fb326d30819519ad82588b75c92c056b`, forbidden `147` / `48c8fd5355ae6578f821126a9ec8e024f5411957b42761c5a0e3fa5b4b2dc659`, and full analyzer | Full analyzer baseline exit `1`, `1,626` shared issues, fingerprint `3f65200c1c42d256cd246afbcb978a00f9357d346147115e9372d28e3afe66e1`. Mutation targets individually captured. |
| 2026-07-11 | mutation pass | Nine one-at-a-time compilable faults: order reversal, sibling coalescing, caption collapse, token remint, private bypass, source-preflight bypass, invalid-target exposure, settled-cell replay, and matrix flattening | Each exact test RED exit `1`; each pre-inverse post-hash/status race check passed; each inverse `apply_patch` restored exact SHA/status; each reran GREEN `1/1`. No persistent edit. |
| 2026-07-11 | literal focused and proportional gates | Session-01 builder; Session-02 primary; received inventory; Plan-234/232/233; generic picker; l10n; registrations/static audit; curated/inventory/completeness; format/analyze/diff | Focused `7/7`, `45/45`, `1/1`, `19/19`, `3/3`, `12/12` (obsolete temporal sentinel alone excluded), `16/16`, `3/3`; curated `1,962/1,962`; host `87`; completeness `1,174/1,174`; formatter 20/0; scoped analyzer clean; full analyzer exact parity `1,626` / `3f6520...`; diff/syntax/scope clean. |
| 2026-07-11 | initial independent QA | Complete code/tests/mutations/gates/scope review | Product behavior `ACCEPTABLE`, but closure evidence `REJECTED`: the first baseline retained only an aggregate and concurrent index/generated-l10n movement prevented per-file proof. No production finding; `fix_passes=0`. |
| 2026-07-11 | corrective evidence audit | Captured all 42 current SHA/status pairs, authoritative aggregate `7554c14da99ffac504ce3200c32afc96b708387bef027eace16d3e7df74098b2`, then repeated all nine RED/inverse/GREEN cycles under the same race protocol. | Final count `42`; aggregate exactly `7554c14d...`; status mismatches `0`; status-vector fingerprint `f89cdc17310f744af6dc842d7e4ef414fc5bfacf3488cc905e6c170d8a9af99a`; forbidden unchanged `147` / `48c8fd...`. Existing broad evidence remains byte-applicable. |
| 2026-07-11 | fresh final QA | Corrective 42-file baseline, repeated mutation evidence, restored candidate, prior literal gates/analyzer parity, and no-refresh boundary | `ACCEPTED`; no findings, `fix_passes=0`. No production/test drift and no Graphify refresh. Proceed to documentation synchronization and separate closure review. |

## Execution Result

`accepted`

- The authoritative 42-file audit baseline and final candidate are byte/status identical: aggregate `7554c14d...`, zero status mismatches, status fingerprint `f89cdc...`. Forbidden scope stayed exactly `147` paths / `48c8fd...`.
- All nine representative mutations repeated causal RED exit `1`, passed the pre-inverse race check, restored via exact inverse `apply_patch`, and reran GREEN `1/1`. No production or test mutation persists.
- Final focused evidence passed: Session 01 `7/7`; Session 02 primary `45/45`; inventory `1/1`; Plan 234 `19/19`; Plan 232 `3/3`; Plan 233 `12/12` with only the obsolete temporal action-absence test excluded; generic picker `16/16`; l10n `3/3`.
- Proportional gates passed: curated `1to1` `1,962/1,962`, host inventory `87`, completeness `1,174/1,174`, all five Plan-249 suites present in both arrays plus the definition doc, received inventory present in both arrays, static no-group audit, formatter 20/0, scoped analyzer clean, full analyzer exact parity at `1,626` / `3f6520...`, and clean syntax/diff checks.
- Fresh final QA accepted with `fix_passes=0`. Session 03 made no persistent production/test, schema, wire, Go/relay, group/announcement, native/device, viewer, or PiP change.
- No Graphify refresh ran. Session 02's post-code refresh remains the final Plan-249 architecture refresh; this session is acceptance/documentation-only.
- Plan 249 is accepted and closed. Plans 250/251 remain separate group/announcement owners.

## Closure Audit

- **Contract:** D-249-01..07 are accepted as direct-only composition over ordinary Plan-232 sends: atomic exact-current source qualification, canonical source-major cells, independent captions/tokens, active direct contacts, truthful outcomes, and failed-cell-only in-route retry.
- **Preservation:** Plans 232/233/234, generic picker behavior, persisted ordinary retry ownership, external share, and direct Shared Media actions remain green.
- **Evidence:** the corrective complete baseline resolves the initial aggregate-only QA rejection without fabricating historical hashes; final content and status equality is exact.
- **Scope:** no full `host-all`, device, SQLCipher, native, Go, relay, or Graphify-refresh claim is made. Wave 1 retains aggregate host/device obligations.
- **Maintenance:** reopen only for concrete regression in atomic source qualification, direct target filtering, source-major matrix truth, per-source caption/token identity, strict ordinary delivery, failed-only retry, picker/action wiring, or registration drift.
- **Separate Closure Reviewer:** `ACCEPTED` with no correction pass. The reviewer verified the authoritative 42-file equality, repeated mutation evidence, exact gates/analyzer parity, maintenance and retry wording, accepted/closed status across all six durable authorities, Plans 250/251 separation, unchanged executable arrays, and absence of host-all/device/schema/wire/Graphify-refresh overclaim. Live forbidden scope became `148` only because concurrent untracked Plan 257 appeared after the authoritative snapshot; excluding that unrelated path reproduces exact `147` / `48c8fd...`. Plan-255/256 index content remains preserved.
