# 300 - Remaining Feature Adapter Placement And DTR-18 Terminal Disposition

Status: Plan-green / implementation-complete / Wave-accepted (2026-07-28)
Type: Modification + retained-debt disposition
Spec: `Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md`
(`DTR-18`)
Authorization: `DTR18-AUTH-02`
Authorization owner: Current authenticated project owner
Classification: implemented-and-verified terminal-increment execution record
Closure tier: host structural + affected repository preservation + manifest
disposition

## Outcome And Scope

This record owns the last six placement identities after the Groups and
Conversation slices: Contact Request, Contacts, Identity, two Introduction
adapters, and the main Posts adapter. It also records the terminal
`DTR18-AUTH-02` disposition for all 165 retained dependency identities.

The integrated 22-adapter batch finished at exactly 165 dependency / zero
placement exceptions. Together with Plan 297's separately closed first
increment, this made DTR-18 terminal. The residual is a terminal disposition,
not a claim that all layering debt was drainable. It does not reopen
`DTR13-AUTH-01` or `DTR17-AUTH-01`, alter the iOS pause boundary, or authorize
behavior, schema, migration, native/Go, wire, crypto, profile, or
release-platform changes.

## Reviewed Relocations

| Old path | Exact destination | Preserved body SHA-256 |
|---|---|---|
| `lib/features/contact_request/domain/repositories/contact_request_repository_impl.dart` | `lib/features/contact_request/data/repositories/contact_request_repository_impl.dart` | `3471670dde3c51e2c8dec5fd6cd84d412d716b99e64f031d3a0f5b48cfb8ab18` |
| `lib/features/contacts/domain/repositories/contact_repository_impl.dart` | `lib/features/contacts/data/repositories/contact_repository_impl.dart` | `b632e4f770f8beeb2e4801a0b469dcc7952a12a19496d479376a297a716eb1e2` |
| `lib/features/identity/domain/repositories/identity_repository_impl.dart` | `lib/features/identity/data/repositories/identity_repository_impl.dart` | `715770a7bb46e7c50ce2c5fb7bd7385ae5e7bb162fe03c1740524cf8e8768e91` |
| `lib/features/introduction/domain/repositories/intro_review_seen_repository_impl.dart` | `lib/features/introduction/data/repositories/intro_review_seen_repository_impl.dart` | `9eb7924630e89ddfa9603c07669026b9a4f7b010c44d0dc3c457b2f9d6681969` |
| `lib/features/introduction/domain/repositories/introduction_repository_impl.dart` | `lib/features/introduction/data/repositories/introduction_repository_impl.dart` | `0b7bdb817d0c3cfcf1b5ba796a603adbb709dabaca7063344706362bea226b53` |
| `lib/features/posts/domain/repositories/post_repository_impl.dart` | `lib/features/posts/data/repositories/post_repository_impl.dart` | `b24eb65551ed124e9c16455c344ed9e8ec3d568074fe7398581241426faee292` |

The preservation contract hashes each body after excluding import/export
lines. This permits required relative-import rewrites but rejects behavior
changes.

## DTR18-AUTH-02 Residual Disposition

The terminal manifest retains exactly 165 dependency identities with identity
SHA-256
`d4f42f151ae18feaf922ad90f172401917a3b7b4ca104d4574e6f9c12a6afb40`.
The canonical full tuple set—rule, source, directive kind, target, owner,
reason, condition, and evidence—has SHA-256
`5f24faf4c5f693d0f19eb18503e5d37c4db4580c6ccbc91806abc75a78dcf132`.
Every retained entry carries the evidence string
`DTR18-AUTH-02 terminal residual disposition dated 2026-07-28.` plus an owner,
reason, and revisit condition.

| Residual family | Identities | Terminal reason / revisit boundary |
|---|---:|---|
| `lib/core/debug/**` | 92 | Retained proof capability under `DTR13-AUTH-01`; revisit only while preserving every authorized profile, entrypoint, command, and proof capability. |
| `lib/core/services/p2p_service_impl.dart` | 8 | Retained transport boundary under `DTR17-AUTH-01`; revisit only with owner-approved facade, Bridge/native/Go, and performance preservation. |
| `lib/core/lifecycle/handle_app_paused.dart` | 8 | Retained iOS lifecycle/background boundary; revisit only with causal iOS lifecycle proof using the availability-bounded device policy. |
| Other source-owned dependency families | 57 | Retained for a future bounded source-family relocation with explicit owner, causal contract, preservation gates, and no substitute exception. |
| **Total** | **165** | Exact identities pinned; zero placement exceptions remain. |

This is a first-class retained-debt close. A future plan may remove an identity
only by satisfying its recorded condition and the trustworthy architecture
guard. It may not silently retarget or replace it.

## TDD Contract And Evidence

| Case | Required result | Evidence / status |
|---|---|---|
| TC-300-01 | All six adapters live only at their exact data paths, retain reviewed bodies, and have no stale package-URI consumer. | `test/unit/dtr18_placement_closure_contract_test.dart`, named remaining-feature case: GREEN. |
| TC-300-02 | Contact request, contact, identity, introduction, and Posts repository behavior remains unchanged. | Thirteen focused repository test files: exit 0, 62 tests passed. Contact-request proof rerun after restoring its preserved body: 12/12 passed. |
| TC-300-03 | All 22 placement rows are gone and all 165 dependency identities are unchanged and explicitly dispositioned. | Named placement/dependency case: GREEN; placement list empty, dependency count 165, identity SHA `d4f42f151ae18feaf922ad90f172401917a3b7b4ca104d4574e6f9c12a6afb40`, and full disposition-tuple SHA `5f24faf4c5f693d0f19eb18503e5d37c4db4580c6ccbc91806abc75a78dcf132`. A temporary mutation of the expected tuple hash re-red this exact case and was removed before the final GREEN. |
| TC-300-04 | Plan 297's first increment and this terminal increment remain simultaneously guarded. | New closure contract +4; combined old/new DTR-18 contracts: exit 0, seven tests passed. |

The causal contract initially exited 1 for the intended remaining-family state:
old-path consumers still existed and the manifest still contained 22
placement rows. After the integrated relocations, import rewrites, and terminal
metadata update, all four closure cases passed. No compile failure or metadata
weakening was accepted as causal RED.

The temporary expected-hash mutation then re-red the exact
placement/dependency case; restoring the reviewed expected hash returned the
closure contract to 4/4 and the combined Plan 297 plus terminal DTR-18
contracts to 7/7.

## Guardrails

- Preserve every adapter constructor, query, mapping, stream, callback,
  persistence, error, and disposal behavior.
- Remove old production paths completely; no export, barrel, part, proxy, or
  compatibility shim.
- Keep the exact 165 dependency identity set unchanged while adding only the
  terminal owner/reason/condition evidence.
- Do not reopen the debug or P2P preservation receipts.
- Do not move the pause or P2P implementations in this increment.
- Do not resolve the separate Product + Release supported-platform decision;
  opening that Wave 5 prerequisite is documentation-only and separately owned.
- Do not claim DTR-18 terminal or Wave 4C accepted from focused proof alone.
  The final claims below rely on the accepted integrated and wave gates.

## Acceptance And Closure

- [x] Six exact source/destination pairs and body hashes are recorded.
- [x] Thirteen focused repository files pass 62 tests.
- [x] Contact-request preservation rerun passes 12/12 after body restoration.
- [x] All 22 path/body/no-stale-consumer assertions pass in the four-test
      closure contract.
- [x] Combined old/new DTR-18 contracts pass seven tests.
- [x] Manifest contract pins 165 dependency identities, zero placements,
      exact identity and full tuple SHAs, and terminal metadata; its exact
      tuple-hash mutation re-red and final restoration are recorded.
- [x] Affected curated lanes are green: `1to1` passes 2,464 Flutter tests plus
      relay Go; Groups passes 3,265 Flutter tests plus Go tails; Introduction
      passes 300 tests; Posts passes seven host tests and two device assertions
      on physical Pixel `21071FDF600CSC`.
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
      seconds.
- [x] The following Wave 4C aggregate `host-all` passes 12,845 tests with one
      declared skip across 1,269 Flutter paths plus all eight Go tails in 785
      seconds, exit 0.
- [x] Roadmap/index/authorization receipts and
      [stable evidence](evidence/dtr-wave4c/README.md) are finalized.

The full `host-all` ran once as the Wave 4C aggregate after Plans 298-300 were
otherwise green; the justified `performance-host` replay immediately preceded
it on the accepted tree. Final release-closure `host-all` and
`performance-host` remain later obligations. The Wave 5 supported-platform
Product + Release decision remains separate and open.

## Rollback

Rollback is family-atomic: restore each old source path and its original
imports together with exactly its reviewed placement row. Do not leave dual
implementations or a shim. Reverting `DTR18-AUTH-02` metadata without restoring
the previous reviewed metadata is not a valid partial rollback. No data,
schema, wire, or native rollback is required because those surfaces did not
change.

## Execution Progress

| Date | Phase | Result | Next |
|---|---|---|---|
| 2026-07-28 | Causal RED | Closure contract exited 1 at stale remaining-family consumers and the 22-row placement manifest. | Apply exact relocations and manifest disposition. |
| 2026-07-28 | Implementation | Six adapters moved to data; old paths removed; all placement rows removed; dependency identities retained with `DTR18-AUTH-02` metadata. | Run focused preservation and structural proof. |
| 2026-07-28 | Focused GREEN | Thirteen files/+62; contact-request rerun 12/12; closure contract +4; combined DTR-18 contracts +7. | Complete policy/family gates, final documentation, and the Wave 4C aggregate. |
| 2026-07-28 | Manifest mutation proof | A temporary mutation of the expected full disposition-tuple hash re-red the exact tuple-hash case; restoration returned the closure contract to 4/4 and combined DTR-18 contracts to 7/7. | Run integrated curated, family, policy, analyzer, and graph gates. |
| 2026-07-28 | Plan-green closure | `1to1` 2,464 pass plus relay Go; Groups 3,265 pass plus Go tails; Introduction 300 pass; physical-Pixel Posts host 7/device 2; feature 811 paths / 8,441 pass / 1 skip; core 367 paths / 2,847 pass plus renderer; architecture 165/0/0; runtime roots 20/20; completeness 1,359/1,359; analyzer and diff clean; Graphify current at `c148591f22c0989a`. | All Plans 298-300 and DTR-18 terminal obligations are green; run the separate Wave 4C aggregate. |
| 2026-07-28 | Wave 4C acceptance | `performance-host` 21 paths / 106 pass in 17 seconds, then `host-all` 1,269 Flutter paths / 12,845 pass / 1 skip plus eight Go tails in 785 seconds; exit 0; stable evidence archived. | Complete; final release closure remains later and the Wave 5 platform decision remains open. |
