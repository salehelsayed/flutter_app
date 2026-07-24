# 273 - DTR-02 stale analyzer baseline retirement and production suppression ratchet

Status: execution-ready
Type: Modification
Spec: `Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md`
(`DTR-02`)
Classification: implementation-ready
Closure tier: host
Roadmap ID / wave: `DTR-02` / Wave 0 — Safety rails
Date: 2026-07-24

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-24 | Evidence Collector — graph | `graphify-arch/tdd_context.py`; architecture graph | One broad query and one exact refinement found the legacy script and gate array but no complete analyzer-policy proof. The graph is stale only for an unrelated private-media file. | Verify the baseline, suppressions, callers, and registrations in current source. |
| 2026-07-24 | Evidence Collector — baseline | legacy wrapper/tool/TSV/parser test; live analyzer commands | The committed baseline has 1,609 findings while the legacy wrapper, bare strict analysis, and the exact future no-pub/fatal command pass with zero current findings. The allowance is wholly stale and reusable. | Design a strict replacement rather than regenerate an empty baseline. |
| 2026-07-24 | Evidence Collector — suppression census | root and nested-package production Dart; analyzer options; l10n ownership; DTR-05 seam | Four exact production `unused_*` directives exist: three generated localization imports and one hand-owned relay helper. Root analyzer options contain no ignore/exclude bypass; the nested package has no suppression. | Freeze an exact, identity-based inventory and analyzer-options guard. |
| 2026-07-24 | Independent refute pass | active callers; Sims manifest/contracts; both gate runners; external runner compatibility | Deleting only the TSV is broken; the app `baseline` gate is unrelated; a count-only ratchet can swap identities; and Sims `verify-analyzer-delta` is a separate transient comparator. | Make retirement atomic and preserve the unrelated seams. |
| 2026-07-24 | Planner | tier matrix; plan template; roadmap cadence; current dirty tree | This is deterministic host tooling. Exact unit/process tests, `sims-contracts`, the focused required analyzer capability, strict analysis, and diff hygiene are sufficient; no app family or device boundary applies. | Apply the blocking sufficiency check. |
| 2026-07-24 | Independent sufficiency audit | Plan 273; sufficiency checklist; current manifest/tool contracts | Initial verdict `NOT READY`: local analyzer-option includes could bypass the scan; wrapper arguments could weaken policy; the read-only claim ignored implicit pub resolution; DTR-05 preservation was overclaimed; and the Sims row lacked literal assertions/tool requirements. | Patch all five structural blockers once. |
| 2026-07-24 | Sufficiency closer | Test Contract; wrapper/config/source guards; complete Sims row; registrations; exact no-pub command | All five audit blockers are structurally closed and the re-audit verdict is `READY`; the exact future analyzer command passed on the current dirty tree; every behavior has causal/preservation proof and concrete discovery; Wave 0/final own full `host-all`. | Offer optional `$tdd-review`; otherwise execute TC-DTR02-01 first. |
| 2026-07-24 | Formal TDD reviewer — counterexample pass | Plan 273; analyzer 9 public/source contracts; Git enumeration semantics; package topology; Docker callers | Verdict before revision: `plan-fixes-required`. A path-overridden production package escaped discovery; source/config parsing underspecified analyzer semantics; checker exit `2`, deleted-file handling, target ownership, and migrated helper exit propagation lacked causal proof. | Apply only the source-backed deltas and rerun all five review lenses. |
| 2026-07-24 | Formal TDD review closer | Revised Scope/Test Contract/steps/gates; dependency dry-run; independent re-refute | L1-L5 are clear. The ratchet now uses public analyzer results plus fail-closed YAML/include validation, scans every Git-visible package `lib/`, rejects broad/file-wide suppression, proves exact exit propagation, and preserves only required wave/final `host-all`. Final verdict: `ready`; core bet confirmed. | Execute from the assertion-level RED scaffold. |

## Problem And Evidence

- Behavior to improve: repository changes must pass strict static analysis and
  must not introduce, move, or globally hide a production `unused_*`
  diagnostic unless an exact reviewed inventory entry already owns that
  occurrence.
- Impact: the required analyzer capability can currently accept the
  reintroduction of historical debt that happens to match one of 480 stale
  baseline keys, so dead-code work can add or re-hide unused production code
  while the gate remains green.
- Confirmed root cause/current gap:
  - `scripts/check_flutter_analyze_baseline.sh:9-34` selects the committed TSV,
    invokes `flutter analyze --no-fatal-infos --no-fatal-warnings`, and compares
    the result instead of enforcing the SDK's fatal warning/info policy.
  - `tool/analyzer_baseline/analyzer_baseline.dart:301-340` blocks only when a
    current key exceeds its historical count; removed debt is non-blocking.
    A formerly removed exact key can therefore return up to its old count.
  - `tool/analyzer_baseline/flutter_analyze_baseline.tsv:1-5` declares 1,609
    warning/info findings across 480 rows. A current execution of the legacy
    wrapper reported `0` current, `1,609` baseline, `0` errors, and exited `0`.
  - Bare `flutter analyze` and
    `flutter analyze --no-pub --fatal-infos --fatal-warnings` on the current
    dirty working tree each exited `0` with `No issues found!`. This is
    planning evidence, not clean-commit or execution evidence, and must be
    repeated.
  - No production suppression scanner, exact inventory, or analyzer-options
    bypass guard exists.
- Confirmed current production suppression inventory:
  - generated `unused_import` directives at
    `lib/l10n/app_localizations_ar.dart:1`,
    `lib/l10n/app_localizations_de.dart:1`, and
    `lib/l10n/app_localizations_en.dart:1`; `l10n.yaml:1-3` and
    `pubspec.yaml:112-113` own those generated outputs;
  - hand-written `unused_element` at
    `lib/features/conversation/application/send_chat_message_use_case.dart:2029`
    targeting `_tryRelayProbeSend`, with its retention reason at
    `:2025-2028`; roadmap DTR-05 owns its later disposition.
  - `analysis_options.yaml:10-25` contains neither `analyzer.errors` overrides
    nor exclusions. Its effective include chain is
    `package:flutter_lints/flutter.yaml` ->
    `package:lints/recommended.yaml` -> `package:lints/core.yaml`.
    `packages/background_push_crypto/lib/` and the active path override
    `third_party/bonsoir_darwin/lib/` have no `unused_*` directive or
    package-local analyzer-options override.
- Existing coverage:
  - `test/unit/analyzer_baseline_parser_test.dart:7-139` has nine parser and
    comparator tests, but all use inline baseline strings and remain green if
    only the real TSV is deleted.
  - `test/tool/sims/sims_manifest_test.dart:263-289` requires complete major
    rows but does not pin the analyzer command or its assertions.
  - `scripts/test/sims_major_plan_contract_test.sh:91-105` pins required lanes
    and the nested-package analyzer, not the root analyzer command.
  - `tool/sims/verification.dart:498-541` compares caller-supplied before/after
    machine snapshots; it does not read the committed baseline.
- Missing coverage: no test proves strict process invocation, suppression-scan
  scope and parsing, exact identity/staleness, analyzer-options bypass
  rejection, complete legacy retirement, or exact required-capability wiring.
- Confirmed active legacy consumers:
  `tool/sims/critical_features.json:87-102`,
  `docker-ws/run_group_notification_fix_tests.sh:26-31`,
  `docker-ws/run_pending_replay_tests.sh:27-31`, and
  `docker-ws/rerun_analyzer_baseline.sh:1-14`. The installed
  `flutter-full-regression-runner` also calls the repository script at
  `/Users/I560101/.codex/skills/flutter-full-regression-runner/scripts/run_full_regression.sh:177`,
  so a strict compatibility entrypoint is required until that external
  distribution migrates.
- All three Docker helpers currently mask a failing final analyzer leg:
  the two aggregators finish by printing their result file, and the rerun
  helper finishes with `tail`, so each can return `0` after recording failure.
- Refuted findings:
  - “Delete the TSV and keep the rest” is refuted: the legacy CLI reads the
    file at `tool/analyzer_baseline/analyzer_baseline.dart:391-409`, exits `2`
    when it is missing, and strands every caller above while its unit test can
    still pass.
  - “The named app `baseline` gate owns analyzer policy” is refuted by
    `scripts/run_test_gates.sh:8-19,1418-1421`; it is an app smoke-test array
    and never invokes analysis.
  - “A current-count ceiling is a sufficient ratchet” is refuted because one
    allowed occurrence can be moved to another declaration without changing
    the count.
  - “All four suppressions are hand-authored debt” is refuted by the
    `flutter gen-l10n` ownership above. Generated output still needs exact
    reviewed entries; it must not receive a directory-wide exemption.
  - “Sims `verify-analyzer-delta` is the stale baseline” is refuted by its
    two caller-supplied snapshot inputs and lack of any TSV/default path.
- Unresolved findings:
  - The external CI workflow/repository and owner remain absent. This does not
    block the repo-owned required `analyzer.flutter` capability; Release/CI
    owns actual external invocation.
- The installed full-regression skill is not versioned by this repository.
    The legacy repository script path remains only as a zero-argument strict
    delegating shim until the skill distribution owner migrates it; it rejects
    every argument with exit `2` and cannot retain baseline flags, state,
    environment overrides, or comparison behavior.
- Affected implementation, test, and gate files:
  `pubspec.yaml`, `pubspec.lock`,
  `tool/analyzer_guard/**`, `scripts/check_flutter_analyze_strict.sh`,
  `scripts/check_flutter_analyze_baseline.sh`,
  `test/unit/analyzer_suppression_ratchet_test.dart`,
  `scripts/test/flutter_analyze_strict_contract_test.sh`,
  `test/tool/sims/sims_manifest_test.dart`,
  `scripts/test/sims_major_plan_contract_test.sh`,
  `tool/sims/critical_features.json`, the three tracked `docker-ws` callers,
  and the legacy baseline directory/parser test removed by this plan.

## Graph Grounding Snapshot

- Graph fingerprint / freshness:
  `fc333c615c1b3e10`;
  `stale:lib/features/conversation/presentation/screens/direct_private_media_viewer.dart`
  (unrelated to DTR-02).
- Primary query / profile:
  `python3 graphify-arch/tdd_context.py query "DTR-02 retire scripts/check_flutter_analyze_baseline.sh tool/analyzer_baseline and tool/sims/critical_features.json; enforce strict flutter analyze and production unused_* suppression ratchet with analyzer-tool tests and gate registration" --profile tdd --budget 700`
  returned `confidence=broad`.
- One allowed refinement:
  `python3 graphify-arch/tdd_context.py query "scripts/check_flutter_analyze_baseline.sh test/unit/analyzer_baseline_parser_test.dart tool/analyzer_baseline/flutter_analyze.tsv tool/sims/critical_features.json BASELINE_TESTS suppression ratchet" --profile tdd --budget 700`
  returned `confidence=anchored`.
- Anchors:
  `scripts_check_flutter_analyze_baseline_sh__entry` ->
  `scripts/check_flutter_analyze_baseline.sh`;
  `test_unit_analyzer_baseline_parser_test` ->
  `test/unit/analyzer_baseline_parser_test.dart`;
  `scripts_run_test_gates_baseline_tests` ->
  `scripts/run_test_gates.sh`.
- Surfaced proof/gate files: the legacy wrapper, parser test, and
  `scripts/run_test_gates.sh`; deterministic overlay had no direct DTR-02 proof
  candidate.
- Graph gaps requiring source search: the TSV contents, current analyzer
  result, production directives, analyzer-options policy, critical-feature
  command, Docker/external callers, shell-contract discovery, and the separate
  transient delta verifier.
- Reuse rule: these anchors may be handed to review/execution; every conclusion
  still requires current-source or command evidence.

## Scope Contract And Guard

In scope:

- Add a pure Dart checker at
  `tool/analyzer_guard/analyzer_suppression_ratchet.dart` and an exact reviewed
  multiset at
  `tool/analyzer_guard/production_unused_suppressions.json`.
- Add direct dev dependencies `analyzer: ^9.0.0` and `yaml: ^3.1.3`, resolve
  them once with an intentional `flutter pub get`, and commit only the required
  `pubspec.yaml`/`pubspec.lock` solver delta. Use public analyzer AST/token,
  URI-conversion, and effective-options APIs. Use `yaml` only to fail-close
  syntax, relevant section shapes, and the applicable scalar/list include
  graph; do not reimplement option merging/glob semantics, import
  `package:analyzer/src/**`, or directly import transitive `glob`.
- Build one NUL-safe Git-visible path set from cached plus non-ignored untracked
  files and subtract Git-reported working-tree deletions. Filter that set to
  Dart files below the root `lib/` and every repo-contained package root
  identified by a Git-visible `pubspec.yaml` with a sibling `lib/`; dependency
  relationship and directory depth are irrelevant. The canonical repository
  contract pins the current three roots: `lib/`,
  `packages/background_push_crypto/lib/`, and
  `third_party/bonsoir_darwin/lib/`. Reject path/symlink escape; treat a file
  that unexpectedly disappears after enumeration as exit `2`. An intentionally
  deleted source is absent, but any retained inventory entry for it remains
  stale policy drift.
- For each analyzed source, consume the applicable analysis session's public
  `ParsedUnitResult` AST/tokens so package language settings apply; invalid
  parse results are exit `2`. Match analyzer-recognized `// ignore:` /
  `// ignore_for_file:` semantics: preceding and same-line directives,
  multiple-slash `/// ignore:`, case-insensitive diagnostic/type names, comma
  lists, whitespace, and explanatory suffixes. Ordinary prose and strings
  remain decoys, but a directive-shaped documentation comment is real.
- Treat any explicit diagnostic whose normalized name begins `unused_` as in
  policy. Reject file-wide `unused_*` and `type=warning` suppressions with zero
  allowance because they cannot own one stable occurrence; the installed
  analyzer classifies all current `unused_*` diagnostics as warnings. Current
  generated `type=lint` directives remain outside this policy. Only a
  single-target line directive can be represented in the reviewed inventory.
- For every enumerated production file, use public
  `AnalysisContextCollection` and `ContextRoot.isAnalyzed`; a production file
  excluded from every applicable context is a zero-allowance violation. For an
  analyzed file, consume its public `ParsedUnitResult.analysisOptions` and
  reject a case-insensitive `unused_*` error processor with null severity
  (`ignore` or `false`). Independently validate every applicable include as
  readable and acyclic, resolving relative URIs from the declaring file and
  `package:` URIs with the public analysis-session URI converter. Cover
  relative and `package:` scalar/list includes, ordered override, nested
  options, and analyzer glob behavior. Resolution, syntax, invalid
  relevant-section/include shape, cycle, or API failure is exit `2`; if the
  pinned public API cannot represent these fixtures, stop and replan instead
  of hand-rolling effective YAML/glob semantics.
- Key every reviewed occurrence by exact repo-relative path, directive kind,
  diagnostic, stable target fingerprint, and count. Require source kind,
  owner/roadmap owner, reason, evidence, and removal condition. Reject unknown,
  duplicate, wildcard/glob, ownerless, relocated, target-swapped, and
  missing/stale entries. Provide `check` only—no generate/update/accept mode.
  The canonical CLI is
  `dart tool/analyzer_guard/analyzer_suppression_ratchet.dart check`; injected
  roots/inventories belong to unit fixtures, not the release command.
- Seed exactly four entries: three generator-owned l10n import identities and
  the DTR-05-owned `_tryRelayProbeSend` identity. Line numbers are diagnostic
  output, never identity.
- Add `scripts/check_flutter_analyze_strict.sh` as the canonical read-only
  gate. It runs the fast suppression check first, then
  `flutter analyze --no-pub --fatal-infos --fatal-warnings`, and propagates
  either failure without producing or updating source-controlled policy or
  evidence files. SDK/package caches are outside the non-mutation claim.
- Both the canonical script and the old compatibility script accept zero
  arguments only and reject any argument with exit `2` before invoking Dart or
  Flutter. The old path is otherwise a minimal delegate to the canonical
  strict gate. Migrate every repo-owned active caller and required manifest row
  to the canonical path; retain the delegate only for the externally
  distributed full-regression caller.
- Delete `tool/analyzer_baseline/**` and
  `test/unit/analyzer_baseline_parser_test.dart` atomically after all live
  registrations/callers are migrated.

Must preserve:

- DTR-02 makes no edit to the DTR-05-owned helper/suppression source; only
  DTR-05 may remove, move, or rewire `_tryRelayProbeSend` ->
  `test/unit/analyzer_suppression_ratchet_test.dart::canonical repository inventory is the three generated l10n identities plus the DTR-05 relay helper`.
- Generated localization files are not hand-edited or blanket-exempted ->
  the same canonical-inventory test, exact target fingerprints, protected
  generated-source diff, and a repository assertion that
  `pubspec.yaml` retains `flutter.generate: true`.
- Nested `packages/background_push_crypto` tests plus `dart analyze` remain in
  the required major plan ->
  `scripts/test/sims_major_plan_contract_test.sh::nested package keeps tests and analyzer`.
- Caller-supplied Sims analyzer-delta comparison remains available and keeps
  fail-on-add/shrink-allowed semantics ->
  `scripts/test/flutter_analyze_strict_contract_test.sh::transient Sims analyzer delta remains independent`.
- Strict analysis remains zero-issue on the execution tree ->
  `flutter analyze --no-pub --fatal-infos --fatal-warnings` GREEN sentinel.

Hard `Do not`:

- Do not regenerate an empty TSV, keep a zero baseline, accept warning/info
  debt, add an allowlist update mode, or introduce a count-only/wildcard
  suppression budget.
- Do not forward or accept caller-supplied analyzer flags through either
  wrapper; `--no-fatal-infos`, `--no-fatal-warnings`, and every other argument
  must fail before analysis starts.
- Do not add, remove, move, or suppress application code to make DTR-02 green.
  A non-clean execution analyzer result belongs to the code that introduced it.
- Do not remove or rewire `_tryRelayProbeSend`, edit generated l10n Dart, relax
  root/package analyzer settings, change the app `BASELINE_TESTS` array, or
  delete/repurpose Sims `verify-analyzer-delta`.
- Do not rewrite historical TDD plans/audits or generated Graphify output to
  remove old baseline wording.
- Do not run a per-plan full `host-all`, app curated lane, feature/core family,
  simulator, device, relay, native, Go, SQLCipher, or migration proof.

Deferred / accepted difference:

- The legacy repository wrapper filename remains a strict no-state delegate
  for zero-argument external full-regression compatibility.
  Release/Codex-skill distribution owns caller migration and later shim
  deletion.
- Repo-external CI invocation remains a Release/CI follow-up; the required Sims
  capability is the repository-owned enforcement surface.
- Historical documents may truthfully describe the retired baseline as past
  behavior. Stale Docker result text is not gate evidence and may be deleted
  only when its owning helper output is migrated.

Dependencies:

- No upstream implementation dependency. DTR-02 is a prerequisite for DTR-03
  and DTR-04 and must be Plan-green before their removals execute.
- DTR-05 owns the only hand-authored allowance and must shrink the inventory in
  the same change that removes or rewires its target.
- DTR-01 and DTR-02 can land in either order but both edit Sims
  registration/contracts. Rebase and edit only the `analyzer.flutter` row;
  preserve any DTR-01 runtime-root capability and contract additions.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-DTR02-01 | The zero-argument canonical gate uses an explicit no-pub fatal analyzer invocation, propagates analyzer failure, and rejects every caller-supplied flag before running tools. | `scripts/test/flutter_analyze_strict_contract_test.sh::strict analyzer invocation argument rejection and exit propagation` | Host process / temporary fake `flutter` and `dart` executables | Assertion RED: the live wrapper accepts environment/config overrides, passes both `--no-fatal-*` flags, and can accept a baseline-matching warning -> exact `flutter analyze --no-pub --fatal-infos --fatal-warnings`, fake nonzero status returned, and `--no-fatal-warnings` yields exit `2` with zero child invocations | Restore either `--no-fatal-*` flag, omit `--no-pub`, forward any argument, or swallow the fake analyzer exit -> TC-DTR02-01 red | `bash scripts/test/flutter_analyze_strict_contract_test.sh`; AUTO (`scripts/test/*_test.sh` in `sims-contracts`) |
| TC-DTR02-02 | The fast suppression check runs before analysis; checker policy exit `1` and untrustworthy-check exit `2` each propagate exactly and short-circuit Flutter; neither phase changes tracked/source-controlled policy or evidence artifacts. | `scripts/test/flutter_analyze_strict_contract_test.sh::ratchet precedes analysis both statuses are fatal and tracked policy is read only` | Host process / ordered fake command log plus before/after tracked-file digest | Assertion RED: no suppression command exists and the wrapper invokes the comparator after permissive analysis -> separate checker-`1` and checker-`2` runs return that exact status with zero Flutter invocations; checker `0` alone reaches analysis; tracked policy/evidence bytes remain identical | Remove/reorder the ratchet call, let status `2` continue, coerce either status to zero, or write/update an inventory/baseline/log in the tracked fixture set -> TC-DTR02-02 red | `bash scripts/test/flutter_analyze_strict_contract_test.sh`; AUTO (`sims-contracts`) |
| TC-DTR02-03 | NUL-safe discovery covers Git-visible top-level root Dart and every repo-local package `lib/`, tolerates intentional working-tree deletion, and parses analyzer-recognized line/file `unused_*` and broad warning directives without prose/string false positives. | `test/unit/analyzer_suppression_ratchet_test.dart::discovers production unused directives without matching decoys` | Host unit / temporary Git-backed repository and package-config fixture | Assertion RED after compile-only API scaffold: discovery/parser return no policy findings -> exact findings from root, `packages/`, the non-`packages/` path override, and an arbitrary-depth package not referenced by the root; newline-safe paths work; ignored files and unstaged deletions are absent; disappearing files fail untrusted; preceding/trailing, comma/suffix, case-insensitive diagnostic, `/// ignore:`, explicit file-wide unused, and `type=warning` forms are recognized; file-wide unused/broad-warning forms are zero-allowance, while ordinary docs/strings and generated `type=lint` are not findings | Scan only root/`packages/*` or only dependency-referenced packages, use newline-delimited or literal `**/` pathspecs, retain `git ls-files --deleted`, discard all doc comments, miss same-line/uppercase/type syntax, inventory a file-wide suppression, or admit ignored output -> TC-DTR02-03 red | `flutter test test/unit/analyzer_suppression_ratchet_test.dart --plain-name 'discovers production unused directives without matching decoys'`; AUTO (`test/unit` completeness + later `host-all`) |
| TC-DTR02-04 | The ratchet compares an exact occurrence multiset and owner-aware target identity, so new, moved, target-swapped, duplicate, and stale identities fail even when totals and declaration names stay equal. | `test/unit/analyzer_suppression_ratchet_test.dart::rejects unexpected relocated duplicate and stale identities` | Host unit / synthetic source plus JSON inventory | Assertion RED after compile-only API scaffold: comparator accepts mismatches -> each mismatch is a policy violation, same-name declarations under different lexical owners differ, a deleted source with a retained entry is stale, and an exact match is green | Replace path/directive/rule/target comparison with a total or name-only count, omit declaration kind/owner/signature, or ignore missing inventory entries -> TC-DTR02-04 red | `flutter test test/unit/analyzer_suppression_ratchet_test.dart --plain-name 'rejects unexpected relocated duplicate and stale identities'`; AUTO (`test/unit`) |
| TC-DTR02-05 | Inventory entries require stable target/count and review metadata; file-wide entries, globs, wildcards, empty ownership/reason/evidence/removal conditions, and update/generate modes are invalid. | `test/unit/analyzer_suppression_ratchet_test.dart::inventory schema is exact reviewed and shrink only` | Host unit / malformed JSON table | Assertion RED after compile-only API scaffold: invalid inventory is accepted -> invalid or broad entries fail closed with exit `2`; only exact complete single-target records load | Permit a file-wide/wildcard entry, line-only identity, empty owner/removal condition, count other than one, or an accept/update CLI -> TC-DTR02-05 red | `flutter test test/unit/analyzer_suppression_ratchet_test.dart --plain-name 'inventory schema is exact reviewed and shrink only'`; AUTO (`test/unit`) |
| TC-DTR02-06 | Effective analyzer configuration cannot globally hide any `unused_*` diagnostic or exclude an enumerated production source, and an untrustworthy include graph fails closed. | `test/unit/analyzer_suppression_ratchet_test.dart::rejects analyzer option ignore and production exclusion bypasses` | Host unit / root, package-config-backed include, and nested-package YAML fixtures | Assertion RED after compile-only API scaffold: options check reports clean -> direct/relative/package scalar-or-list includes, ordered local override, case-insensitive `unused_field: ignore` and distinct `UNUSED_ELEMENT: false`, nested applicable options, and nontrivial matching excludes become violations; malformed, missing, or cyclic includes return untrusted; unrelated integration `avoid_print` remains out of scope | Inspect one root-relative scalar file, hard-code `unused_field`, hand-roll merge/glob behavior, compare action casing literally, accept `false`, skip nested options, or treat malformed/unresolved includes as empty -> TC-DTR02-06 red | `flutter test test/unit/analyzer_suppression_ratchet_test.dart --plain-name 'rejects analyzer option ignore and production exclusion bypasses'`; AUTO (`test/unit`) |
| TC-DTR02-07 | The canonical repository inventory is exactly three generated l10n import identities plus one DTR-05 relay-helper identity, with no silent generated exemption; all three current production package roots and localization generation ownership stay pinned. | `test/unit/analyzer_suppression_ratchet_test.dart::canonical repository inventory is the three generated l10n identities plus the DTR-05 relay helper`; canonical `check` CLI; protected-source diff guard | Host repository contract / current working-tree sources, package topology, root manifest, and checked-in JSON | Assertion/command RED after compile-only API scaffold: no canonical inventory/check exists -> check exits `0` only for the four exact identities, reports two ownership kinds, scans `lib/`, `packages/background_push_crypto/lib/`, and `third_party/bonsoir_darwin/lib/`, asserts `flutter.generate: true`, and protected generated/helper sources have no DTR-02 diff | Add a fifth directive, drop the path override root, move/edit the relay target, disable localization generation, blanket-skip/edit generated files, or retain an entry after its directive disappears -> TC-DTR02-07 red | `flutter test test/unit/analyzer_suppression_ratchet_test.dart --plain-name 'canonical repository inventory is the three generated l10n identities plus the DTR-05 relay helper'`; `dart tool/analyzer_guard/analyzer_suppression_ratchet.dart check`; protected-source `git diff --exit-code` command in Acceptance Gates; test AUTO (`test/unit`), CLI manually owned by `analyzer.flutter` |
| TC-DTR02-08 | Baseline artifacts retire atomically; active repo callers use the strict gate; the old public path is a zero-argument delegate; migrated Docker helpers return failure when their strict analyzer leg fails. | `scripts/test/flutter_analyze_strict_contract_test.sh::legacy baseline artifacts retire atomically and compatibility is strict` | Host source/process contract / tracked active-root census plus temporary fake repo/tool PATH | Assertion RED: legacy state/callers exist and all three Docker helpers can print failure then return `0` -> artifacts disappear, callers migrate, the sole legacy entrypoint rejects arguments before a child, both aggregators finish nonzero after a failed strict leg, and the rerun helper returns the strict child status after persisting/printing output | Restore TSV/tool/env behavior, point a caller at the comparator, forward an argument, add policy to the shim, or let final `cat`/`tail` mask failure -> TC-DTR02-08 red | `bash scripts/test/flutter_analyze_strict_contract_test.sh`; AUTO (`sims-contracts`) |
| TC-DTR02-09 | Required `analyzer.flutter` is one complete pinned host-process row running the strict+ratchet script with literal assertions and requirement metadata. | `test/tool/sims/sims_manifest_test.dart::analyzer capability runs strict analysis and production unused suppression ratchet`; `scripts/test/sims_major_plan_contract_test.sh::analyzer row pins strict policy command assertions and host requirements` | Host manifest unit + major-plan JSON process contract | Assertion RED: current command is the legacy wrapper, only `analyzer.no_errors` is declared, and only Flutter SDK is named -> exact row keeps `id=analyzer.flutter`, `owner=platform`, `proofBoundary=host.analyzer.repo`, `lane=analyzer`, `modes=[major]`, `families=[infra]`, `required=true`, `command=[./scripts/check_flutter_analyze_strict.sh]`, `buildProfile=host.process`, empty dependencies, read-only `host.cpu`, `targetCapabilities=[host.flutter-sdk,host.bash,host.git]`, `artifactRequired=false`, `active=true`, `declaredBuildException=false`, and assertions `[analyzer.no_errors,analyzer.no_warnings_or_infos,analyzer.production_unused_suppressions_ratcheted]` | Restore the legacy command, alter/drop any pinned field/assertion/requirement metadata, deactivate the row, or omit it from major -> TC-DTR02-09 red | `flutter test test/tool/sims/sims_manifest_test.dart --plain-name 'analyzer capability runs strict analysis and production unused suppression ratchet'`; `bash scripts/test/sims_major_plan_contract_test.sh`; Dart test AUTO (`host-all`), shell AUTO (`sims-contracts`) |
| TC-DTR02-10 | The real repository remains zero-issue under explicit no-pub strict Flutter analysis. | `flutter analyze --no-pub --fatal-infos --fatal-warnings` | GREEN sentinel / live Flutter SDK, resolved package config, and current execution tree | GREEN sentinel: the exact planning command reports `No issues found!` with exit `0` -> execution command reports the same | Reintroduce an unsuppressed unused private declaration -> TC-DTR02-10 red | `flutter analyze --no-pub --fatal-infos --fatal-warnings`; manual required `analyzer.flutter` capability invokes the same argv |
| TC-DTR02-11 | The transient Sims before/after machine-output comparator still fails on added issues and permits shrink; it never becomes the committed baseline. | `scripts/test/flutter_analyze_strict_contract_test.sh::transient Sims analyzer delta remains independent` | GREEN sentinel / temporary machine-format before/after files | GREEN sentinel: `verify-analyzer-delta` has independent two-file semantics -> add fails, shrink passes, and neither path reads the retired TSV | Remove/rename the command, point it at the retired default baseline, or reverse add/shrink semantics -> TC-DTR02-11 red | `bash scripts/test/flutter_analyze_strict_contract_test.sh`; AUTO (`sims-contracts`) |

### Test Notes

- TC-DTR02-01/02 use PATH-injected fakes and a temporary command log. They must
  not invoke the real analyzer. The fake analyzer returns success only for the
  old permissive flags during RED, making the obsolete acceptance mechanism
  causal rather than a filename/source-text proxy. Their non-mutation digest
  covers tracked/source-controlled policy and evidence artifacts; ephemeral
  SDK/package caches are not claimed byte-stable. TC-DTR02-02 runs checker
  statuses `1` and `2` separately and requires zero Flutter calls in both.
- TC-DTR02-03/04 bind a standalone directive only to one eligible AST target on
  the immediately following physical line and a trailing directive only to one
  eligible target on that same physical line, matching analyzer line
  application. A declaration fingerprint contains declaration kind,
  lexical-owner chain, identifier, and normalized header/signature; an import
  contains URI, prefix, and normalized combinators. Targetless, ambiguous, and
  file-wide `unused_*` suppressions cannot enter inventory. Line numbers may
  appear in diagnostics but never satisfy identity.
- TC-DTR02-06 uses `yaml` only to prove the applicable include graph is
  well-formed, readable, and acyclic. Public analyzer contexts own effective
  merge, severity, nested-options, and exclusion matching semantics. The test
  must exercise those public APIs rather than a production-only fake parser.
- TC-DTR02-08 scans executable/config/test roots, not historical plans,
  generated graphs, or archived result prose. The compatibility shim is the
  only permitted active old path and must contain no policy of its own. Its
  process fixture runs the real helper scripts in a disposable fake repository;
  source-text assertions alone do not prove their final exit statuses.
- `host.bash` and `host.git` are pinned Sims requirement metadata, not generic
  preflight enforcement. TC-DTR02-01/02/08 and the real strict capability are
  the causal proof that Bash, Git, and Flutter behavior actually ran.

## Implementation Steps

1. Snapshot `git status --short` and record unrelated work. Run
   `flutter analyze --no-pub --fatal-infos --fatal-warnings` before edits.
   Stop if it is nonzero: assign the issue to its owning change; do not revive,
   regenerate, or expand a baseline.
2. Add direct dev dependencies `analyzer: ^9.0.0` and `yaml: ^3.1.3`, then
   intentionally run `flutter pub get` once. Verify the lock resolves analyzer
   9.0.0 under the current SDK, `flutter.generate: true` remains intact, and no
   generated/app source changed. Every later analyzer command remains
   `--no-pub`.
3. Add `scripts/test/flutter_analyze_strict_contract_test.sh`,
   `test/unit/analyzer_suppression_ratchet_test.dart`, the exact new
   `sims_manifest_test.dart` case, and the analyzer-row assertions in
   `sims_major_plan_contract_test.sh`. Add only the minimum compile-only checker
   API scaffold needed to run the unit file, with unimplemented/untrusted
   results and no policy behavior. Run every new named unit behavior plus
   TC-DTR02-01/02/08/09 and record assertion RED for its stated mechanism;
   a missing-import or compile failure does not satisfy the behavior RED.
4. Implement the injected pure checker and `check` CLI under
   `tool/analyzer_guard/` in named RED -> GREEN -> mutation-re-RED microcycles:
   Git/package discovery and comment parsing (TC-DTR02-03), owner-aware
   fingerprints/comparison (TC-DTR02-04), schema (TC-DTR02-05), then effective
   options plus fail-closed include validation (TC-DTR02-06). Keep each
   component independently testable and use the real public analyzer APIs in
   the fixtures; dispose every `AnalysisContextCollection` in `finally`. Exit
   `0` for an exact trustworthy inventory, `1` for policy drift, and `2` for
   usage/config/parse/Git/I/O failure. The release invocation is exactly
   `dart tool/analyzer_guard/analyzer_suppression_ratchet.dart check`.
5. Add `production_unused_suppressions.json` with the four exact records and no
   wildcard, generated-directory exemption, line-number identity, or
   update/generate command. Stop if current source produces any fifth identity
   or cannot bind an entry to a stable target.
6. Add `scripts/check_flutter_analyze_strict.sh`: resolve repository root, run
   the ratchet first, then run
   `flutter analyze --no-pub --fatal-infos --fatal-warnings`, and preserve all
   exit statuses without writing source-controlled evidence/baseline files.
   Require a resolved package config; missing dependencies are an environment
   precondition failure, not permission for an implicit `pub get`.
7. Replace `scripts/check_flutter_analyze_baseline.sh` with the minimal
   zero-argument strict delegate; both scripts reject every argument with exit
   `2` before child execution. Update the three `docker-ws` helpers'
   commands/labels and remove their baseline-log environment behavior;
   preserve their unrelated focused test commands and result aggregation.
   After printing/persisting results, both aggregators must exit nonzero when
   `overall=FAILED`; the analyzer-only rerun must capture and return the strict
   child's exact status rather than the final `tail` status.
8. Update only the `analyzer.flutter` manifest row. Pin its complete existing
   row plus command, exact assertion IDs
   `analyzer.no_errors`, `analyzer.no_warnings_or_infos`, and
   `analyzer.production_unused_suppressions_ratcheted`, and target
   capabilities `host.flutter-sdk`, `host.bash`, and `host.git` in both typed
   and process contracts. Preserve the nested-package analyzer, DTR-01
   additions, and all other capability rows byte-for-behavior.
9. Delete `tool/analyzer_baseline/analyzer_baseline.dart`,
   `tool/analyzer_baseline/flutter_analyze_baseline.tsv`, and
   `test/unit/analyzer_baseline_parser_test.dart` together. Do not edit
   historical documents, generated Graphify files, or the separate Sims
   analyzer-delta implementation.
10. Run focused GREEN/mutation cycles, exact discovery, full
   `sims-contracts`, the focused required analyzer capability, completeness,
   strict analysis, and diff hygiene. Do not run an app family or per-plan full
   `host-all`.
11. Update this plan's Execution Progress and the roadmap row only after all
    per-plan gates pass; Wave 0 still owns aggregate `host-all`.

## Rollback Contract

- Keep DTR-02 as one coherent implementation commit/range. If the new checker
  or strict capability must be withdrawn, resolve that exact commit/range and
  use `git revert <DTR-02-commit>` (or revert the resolved commits newest first)
  so the wrapper, manifest, caller wiring, tool, inventory, tests, and deleted
  baseline artifacts return to one internally consistent prior state.
- Never roll back only the JSON inventory, only the manifest command, or only
  one wrapper: each partial state either strands callers or silently removes a
  proof leg.
- After an emergency revert, run
  `flutter pub get`,
  `flutter test test/unit/analyzer_baseline_parser_test.dart`,
  `./scripts/check_flutter_analyze_baseline.sh`,
  `dart tool/sims/sims.dart major --list --only analyzer.flutter`, and
  `git diff --check`. Restore the roadmap row to `Planned`, block DTR-03/DTR-04,
  and open a forward-fix before claiming Wave 0 closure; the historical
  allowance is not an acceptable long-term green state.

## Risks And Blind Spots

- Analyzer output/defaults can change across SDK upgrades -> the wrapper pins
  `--no-pub`, both positive fatal flags, and TC-DTR02-01 observes exact
  argv/status; analyzer 9 is a direct, lock-pinned tool dependency and public
  API compilation is covered by the unit file.
- A contributor can keep the same suppression count while moving it -> exact
  owner-aware target fingerprints and stale-entry checks in TC-DTR02-04/07.
- Generated code can be over-exempted for convenience -> no glob or automatic
  generated allowance; the three current identities are exact TC-DTR02-07
  records.
- Analyzer-recognized source/config forms can bypass a literal scan ->
  TC-DTR02-03 covers broad warning and comment-token forms; TC-DTR02-06 uses
  effective analyzer options and fail-closed include validation.
- A path-overridden or newly nested package can escape root-only scanning ->
  TC-DTR02-03 derives repo-contained package `lib` roots and TC-DTR02-07 pins
  the current root, `packages/`, and `third_party/` topology.
- Git's cached view retains an unstaged deletion -> TC-DTR02-03 subtracts
  Git-reported deletions NUL-safely, while TC-DTR02-04 still rejects a retained
  stale inventory record and unexpected post-enumeration disappearance fails
  untrusted.
- Atomic deletion can strand a manual/external caller -> TC-DTR02-08 inventories
  repo callers and preserves a zero-argument behaviorless strict compatibility
  delegate; its process fixture also prevents final `cat`/`tail` from masking a
  failed migrated analyzer leg.
- Lifecycle / derived-state durability:
  N/A — the gate derives no persisted or in-memory application state; every run
  rescans the working tree and config.
- Sibling-surface consistency:
  TC-DTR02-03/06 applies one policy to root and nested-package production
  surfaces; test/integration suppressions are deliberately outside the
  production contract.
- Destructive-action side effects:
  TC-DTR02-08 proves removal of the old files and preservation/migration of
  callers; Git makes the deleted tooling recoverable.
- Invariant re-verification under new transitions:
  TC-DTR02-04/07 re-check unexpected and stale identities on every run; no
  cached “previously clean” result authorizes a later suppression.

## Gate Cadence

- Per-plan closure: focused analyzer-guard unit/process tests; exact typed and
  shell manifest contracts; full affected `sims-contracts`; focused execution
  of required `analyzer.flutter`; completeness; explicit no-pub strict
  analysis; diff hygiene. The named app `baseline` gate and app family sweeps
  are not affected.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all --continue-on-failure` once after
  Wave 0 (`DTR-01`, `DTR-02`, and `DTR-08`) is integrated/terminal, and once
  again at final rollout/release closure.
- Shared tests outside feature/core globs:
  `flutter test test/unit/analyzer_suppression_ratchet_test.dart`,
  `flutter test test/tool/sims/sims_manifest_test.dart --plain-name 'analyzer capability runs strict analysis and production unused suppression ratchet'`,
  `bash scripts/test/flutter_analyze_strict_contract_test.sh`, and
  `bash scripts/test/sims_major_plan_contract_test.sh`.

## Acceptance Gates

```bash
# Snapshot before execution; record all unrelated modified/untracked paths.
git status --short

# Current prerequisite sentinel; require an already-resolved package config.
# Expect exit 0 and "No issues found!". A nonzero result blocks DTR-02 and must
# not be baselined or suppressed here.
flutter analyze --no-pub --fatal-infos --fatal-warnings

# After declaring analyzer/yaml direct dev dependencies: the one intentional
# resolution step. Inspect pubspec/lock and require no generated/app source diff.
flutter pub get
git diff --check -- pubspec.yaml pubspec.lock

# After adding tests plus the compile-only checker API scaffold: causal
# assertion REDs for permissive invocation, both absent ratchet status paths,
# legacy callers, and masked Docker-helper status.
bash scripts/test/flutter_analyze_strict_contract_test.sh

# The complete unit file must compile and each named unimplemented behavior must
# report its intended assertion RED; a missing API/import is not causal proof.
flutter test test/unit/analyzer_suppression_ratchet_test.dart

# After adding the exact manifest assertions only: expect assertion RED because
# analyzer.flutter still names the legacy command and one assertion.
flutter test test/tool/sims/sims_manifest_test.dart \
  --plain-name 'analyzer capability runs strict analysis and production unused suppression ratchet'

# Focused GREEN; each command exits 0 with zero failed assertions.
flutter test test/unit/analyzer_suppression_ratchet_test.dart
bash scripts/test/flutter_analyze_strict_contract_test.sh
flutter test test/tool/sims/sims_manifest_test.dart \
  --plain-name 'analyzer capability runs strict analysis and production unused suppression ratchet'
bash scripts/test/sims_major_plan_contract_test.sh

# Canonical suppression check; expect exit 0 and exactly the four reviewed
# identities, with no unexpected, stale, or analyzer-options bypass.
dart tool/analyzer_guard/analyzer_suppression_ratchet.dart check

# Protected-source guard; expect exit 0 and no DTR-02 edits to the DTR-05
# helper, generated l10n outputs, l10n config, or root analyzer policy. The
# canonical repository test separately pins pubspec `flutter.generate: true`
# while permitting only the required analyzer/yaml dev-dependency change.
git diff --exit-code -- \
  lib/features/conversation/application/send_chat_message_use_case.dart \
  lib/l10n/app_localizations.dart \
  lib/l10n/app_localizations_ar.dart \
  lib/l10n/app_localizations_de.dart \
  lib/l10n/app_localizations_en.dart \
  l10n.yaml \
  analysis_options.yaml

# Registration discovery only; expect the new shell contract and exact
# analyzer.flutter strict command to be listed. These list runs are not passing
# execution evidence.
./scripts/run_test_gates.sh sims-contracts --list
./scripts/run_test_gates.sh sims major --list --only analyzer.flutter

# Affected shell-contract lane; expect every registered contract to exit 0.
./scripts/run_test_gates.sh sims-contracts

# Test-file classification; expect all files classified and exit 0.
./scripts/run_test_gates.sh completeness-check

# Required repository analyzer capability; expect only analyzer.flutter to run,
# the four-entry suppression inventory to match, strict analysis to report zero
# issues, and the capability to pass.
./scripts/run_test_gates.sh sims major --only analyzer.flutter

# Independent strict/hygiene closure; expect exit 0, zero analyzer issues, and
# no whitespace errors. No implicit pub resolution is permitted.
flutter analyze --no-pub --fatal-infos --fatal-warnings
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED:
  - `flutter_analyze_strict_contract_test.sh` rejects the old permissive argv,
    checker-status handling, live baseline artifacts, stale caller wiring, and
    Docker helpers that mask failure;
  - after a compile-only checker scaffold, every new unit behavior fails its
    intended assertion rather than merely failing to compile;
  - the typed manifest assertion fails on the legacy command/claims.
- Green sentinel: explicit no-pub/fatal `flutter analyze` remains zero-issue,
  and the transient Sims analyzer-delta add/shrink contract remains unchanged.
- Pre-existing dirty tree / known failure: planning began with unrelated
  private-media implementation/tests, `info.plist`, Docker evidence, dirty
  Graphify outputs, the modified index, and untracked Plans 271/272/roadmap.
  Preserve them. No analyzer failure was known; the current dirty working tree
  analyzed clean.
- Environment blocker: none observed. This is host-only and uses Bash, Git,
  the installed Flutter/Dart SDK, one explicit dependency resolution after the
  declared dev-dependency change, and temporary local fixtures; every
  subsequent gate is `--no-pub`, and missing resolution blocks execution rather
  than authorizing another implicit `pub get`. No simulator/device/relay is
  required.
- Scope drift: any production app edit, analyzer/lint relaxation, fifth
  accepted production suppression, DTR-05 helper change, external CI rollout,
  app family requirement, or non-clean prerequisite analyzer result blocks
  completion and requires reassignment/replanning.

- [ ] Every behavior row has its named causal or preservation evidence.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are
      recorded with the documented failure reason.
- [ ] Exact four-entry production inventory across all three package roots,
      analyzer-semantic source/config bypass checks, and fail-closed include
      validation pass; legacy artifacts/callers are retired or strictly
      delegated, and migrated helpers propagate failure.
- [ ] Unit, process, typed manifest, `sims-contracts`, focused capability,
      completeness, strict analyzer, and diff-hygiene gates pass.
- [ ] Harness registration is selected by both list commands and then executed;
      Wave 0/final, not this plan, own full `host-all`.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command:
  `bash scripts/test/flutter_analyze_strict_contract_test.sh` after adding the
  tests and compile-only checker API scaffold; it must fail on permissive
  no-fatal baseline acceptance, absent checker status handling, stale callers,
  and masked Docker-helper failure.
- Preservation commands:
  `flutter analyze --no-pub --fatal-infos --fatal-warnings` and the protected
  source `git diff --exit-code` command in Acceptance Gates.
- Manual registration:
  update required `tool/sims/critical_features.json` capability
  `analyzer.flutter` to the canonical strict script; literal assertions are
  `analyzer.no_errors`, `analyzer.no_warnings_or_infos`, and
  `analyzer.production_unused_suppressions_ratcheted`, with target
  capabilities `host.flutter-sdk`, `host.bash`, and `host.git`.
  The Dart unit test is AUTO under later `host-all` and completeness; the shell
  contract is AUTO under `sims-contracts`.
- Migration: none.
- Boundary closure: host-only; no SQLCipher, crypto, OS callback, relay,
  simulator, device, native, Go, or app behavior boundary.
- Unresolved evidence: external CI and installed-skill caller ownership remain
  outside the repository; the strict compatibility shim prevents either from
  weakening or breaking this plan.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plan | contract extraction |
