# 299 - Conversation Repository Adapter Placement Closure

Status: Implementation applied / partial focused proof green / closure gates pending
Type: Modification
Spec: `Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md`
(`DTR-18`)
Classification: terminal-increment execution record
Closure tier: host structural + Conversation repository preservation

## Outcome And Scope

This record owns the Conversation slice of DTR-18's terminal placement
increment. It relocates the three concrete Conversation adapters from
`lib/features/conversation/domain/repositories/` to
`lib/features/conversation/data/repositories/`, updates their consumers, and
forbids old-path shims. It owns three of the 22 placement identities present
after Plan 297.

The integrated terminal batch, rather than an independently captured
three-row manifest checkpoint, is responsible for the canonical 165 dependency
/ 22 placement to 165 / 0 transition. No behavior, repository contract,
schema, migration, message state transition, upload policy, reaction policy,
wire/native/Go code, or dependency exception is in scope.

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
| TC-299-03 | Relocated Conversation sources and their rewritten consumers remain analyzer-clean. | Targeted analyzer: exit 0, no issues. Repository-wide analyzer remains pending. |
| TC-299-04 | Media descriptor/upload behavior remains covered after the global fixture import rewrite. | The stale fixture dependency is resolved. Exact media descriptor/upload suite rerun: pending; it must not be inferred from TC-299-02. |
| TC-299-05 | The complete placement batch reaches zero without changing the exact retained dependency floor. | Integrated closure contract +4 and combined old/new DTR-18 contracts +7: GREEN. Canonical architecture lane: pending. |

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

## Acceptance And Pending Closure

- [x] Three exact source/destination pairs and body hashes are recorded.
- [x] Exact path, body, and stale-consumer structural contract is green.
- [x] Message/reaction focused suites pass 40 tests.
- [x] Targeted analyzer is clean.
- [x] The all-placement contract passes four tests; combined DTR-18 contracts
      pass seven.
- [ ] Media descriptor/upload repository preservation suites rerun green after
      the resolved fixture rewrite.
- [ ] Affected curated Conversation/one-to-one lane is green.
- [ ] Justified affected feature-family sweep is green.
- [ ] Architecture lane proves trustworthy 165 / 0 and zero issues.
- [ ] Runtime-root and completeness gates are green.
- [ ] Repository-wide `flutter analyze` and `git diff --check` are clean.
- [ ] Incremental Graphify refresh and affected query are recorded.
- [ ] Wave 4C aggregate `host-all` and justified `performance-host` are green.

Full `host-all` belongs to Wave 4C after every DTR-18 terminal slice is green.
This path-only slice makes no new device, relay, native, or OS behavior claim.

## Execution Progress

| Date | Phase | Result | Next |
|---|---|---|---|
| 2026-07-28 | Causal RED | Closure contract exited 1 for stale Conversation old-path imports. | Apply exact moves and consumer rewrites. |
| 2026-07-28 | Implementation | Three adapters moved to exact data destinations; old paths removed; no shim added. | Run structural and behavior preservation proof. |
| 2026-07-28 | Focused GREEN | Conversation structural case green; message/reaction suites passed 40 tests; targeted analyzer clean; integrated contract +4 and combined DTR-18 contracts +7. | Rerun media descriptor/upload proof, then complete integrated gates. |
