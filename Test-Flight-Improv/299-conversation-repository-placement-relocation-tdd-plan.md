# 299 - Conversation Repository Adapter Placement Closure

Status: Plan-green / implementation-complete / Wave-accepted (2026-07-28)
Type: Modification
Spec: `Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md`
(`DTR-18`)
Authorization: `DTR18-AUTH-02`
Authorization owner: Current authenticated project owner
Classification: implemented-and-verified terminal-increment execution record
Closure tier: host structural + Conversation repository preservation

## Outcome And Scope

This record owns the Conversation slice of DTR-18's terminal placement
increment. It relocated the three concrete Conversation adapters from
`lib/features/conversation/domain/repositories/` to
`lib/features/conversation/data/repositories/`, updated their consumers, and
left no old-path shim. It owns three of the 22 placement identities present
after Plan 297.

The integrated terminal batch, rather than an independently captured
three-row manifest checkpoint, is responsible for the canonical 165 dependency
/ 22 placement to 165 / 0 transition. No behavior, repository contract,
schema, migration, message state transition, upload policy, reaction policy,
wire/native/Go code, or dependency exception is in scope.

Plan 297 remains DTR-18's separately closed first increment. Plan 299 is one
of the three later placement slices that made DTR-18 terminal.

## Reviewed Relocations

| Old path | Exact destination | Preserved body SHA-256 |
|---|---|---|
| `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart` | `lib/features/conversation/data/repositories/media_attachment_repository_impl.dart` | `25c2edae75c47de771504dea387c838f518e269341566cf8d32c64aa9bd53d3c` |
| `lib/features/conversation/domain/repositories/message_repository_impl.dart` | `lib/features/conversation/data/repositories/message_repository_impl.dart` | `768329771535ccde97a31a1ad6bc63e4f7b627d8b867f6d5a8e48b51d02cae5c` |
| `lib/features/conversation/domain/repositories/reaction_repository_impl.dart` | `lib/features/conversation/data/repositories/reaction_repository_impl.dart` | `13b077a7e38eba342c0931b63b2787fd94cfb6710674198f8b83fd178a122c14` |

The hashes exclude import/export lines. This permits only the relative-import
changes forced by the new directory while continuing to reject any repository
body drift.

## TDD Contract And Evidence

| Case | Required result | Evidence / status |
|---|---|---|
| TC-299-01 | All three implementations live only at the exact data-layer paths, retain their reviewed bodies, and have no stale package-URI consumer. | `test/unit/dtr18_placement_closure_contract_test.dart`, named Conversation case: GREEN as part of the four-test closure contract. |
| TC-299-02 | Message and reaction persistence behavior remains unchanged. | Focused message/reaction repository suites: exit 0, 40 tests passed. |
| TC-299-03 | Relocated Conversation sources and their rewritten consumers remain analyzer-clean. | Targeted analysis and repository-wide `flutter analyze`: exit 0, zero issues. |
| TC-299-04 | Media descriptor/upload behavior remains covered after the global fixture import rewrite. | The resolved fixture rewrite was followed by the exact media repository preservation rerun: 49/49 passed. |
| TC-299-05 | The complete placement batch reaches zero without changing the exact retained dependency floor. | Integrated closure contract +4 and combined old/new DTR-18 contracts +7: GREEN. The canonical architecture lane passed 6/6 at 165 dependency / 0 placement / 0 issues. |

The pre-move causal command exited 1 at the intended Conversation condition:
stale old-path imports remained. After the relocations and integrated consumer
rewrite, all four closure-contract cases and all seven combined DTR-18
contract tests passed. No compilation failure was counted as causal RED.

## Guardrails

- Preserve repository constructors, SQL and row mapping, stream behavior,
  message state transitions, upload-pending logic, reaction persistence, and
  disposal.
- Change implementation and consumer imports only as required by relocation.
- Do not rename domain interfaces or move tests merely to mirror production
  paths.
- Do not leave an export, barrel, part, proxy, or duplicate implementation
  under an old domain path.
- Do not add, retarget, or remove a dependency exception.
- Keep Groups and the six remaining feature-adapter families under Plans 298
  and 300.

## Acceptance And Closure

- [x] Three exact source/destination pairs and body hashes are recorded.
- [x] Exact path, body, and stale-consumer structural contract is green.
- [x] Message/reaction focused suites pass 40 tests.
- [x] Targeted analyzer is clean.
- [x] The all-placement contract passes four tests; combined DTR-18 contracts
      pass seven.
- [x] Media descriptor/upload repository preservation passes 49/49 after the
      resolved fixture rewrite.
- [x] The affected `1to1` lane passes 2,464 Flutter tests plus its relay Go
      tail.
- [x] Integrated `feature-host-all` passes 8,441 tests with one declared skip
      across 811 paths; `core-host-all` passes 2,847 tests across 367 paths
      plus the Android renderer contract.
- [x] The architecture lane is trustworthy at 165 dependencies, zero
      placements, and zero issues.
- [x] Runtime roots pass 20/20 with trustworthy/no-drift output; completeness
      passes 1,359/1,359.
- [x] Repository-wide `flutter analyze` reports zero issues and
      `git diff --check` is clean.
- [x] Graphify was refreshed incrementally, then rebuilt to remove source-less
      old-path orphans; the final current graph fingerprint is
      `c148591f22c0989a`, with 63,016 nodes / 96,398 edges and no old
      implementation URI.
- [x] Wave 4C `performance-host` passes 106 tests across 21 paths in 17
      seconds; the following full `host-all` passes 12,845 tests with one
      declared skip across 1,269 Flutter paths plus all eight Go tails in 785
      seconds, exit 0.
- [x] Stable acceptance evidence is archived in
      [evidence/dtr-wave4c/README.md](evidence/dtr-wave4c/README.md).

Full `host-all` accepted Wave 4C only after every DTR-18 terminal slice was
green.
This path-only slice makes no new device, relay, native, or OS behavior claim.
Final release-closure `host-all` and `performance-host` remain later
obligations. The Wave 5 supported-platform Product + Release decision remains
separate and open.

## Execution Progress

| Date | Phase | Result | Next |
|---|---|---|---|
| 2026-07-28 | Causal RED | Closure contract exited 1 for stale Conversation old-path imports. | Apply exact moves and consumer rewrites. |
| 2026-07-28 | Implementation | Three adapters moved to exact data destinations; old paths removed; no shim added. | Run structural and behavior preservation proof. |
| 2026-07-28 | Focused GREEN | Conversation structural case green; message/reaction suites passed 40 tests; media preservation passed 49/49; targeted analyzer clean; integrated contract +4 and combined DTR-18 contracts +7. | Complete integrated gates. |
| 2026-07-28 | Plan-green closure | `1to1` 2,464 pass plus relay Go; feature 811 paths / 8,441 pass / 1 skip; core 367 paths / 2,847 pass plus renderer; architecture 165/0/0; runtime roots 20/20; completeness 1,359/1,359; analyzer and diff clean; Graphify current at `c148591f22c0989a`. | Every Plan 299 obligation is green; run the separate Wave 4C aggregate. |
| 2026-07-28 | Wave 4C acceptance | `performance-host` 21 paths / 106 pass in 17 seconds, then `host-all` 1,269 Flutter paths / 12,845 pass / 1 skip plus eight Go tails in 785 seconds; exit 0; stable evidence archived. | Complete; final release closure remains later. |
