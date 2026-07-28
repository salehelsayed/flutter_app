# 300 - Remaining Feature Adapter Placement And DTR-18 Terminal Disposition

Status: Implementation applied / focused proof green / closure gates pending
Type: Modification + retained-debt disposition
Spec: `Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md`
(`DTR-18`)
Authorization: `DTR18-AUTH-02`
Authorization owner: Current authenticated project owner
Classification: terminal-increment execution record
Closure tier: host structural + affected repository preservation + manifest
disposition

## Outcome And Scope

This record owns the last six placement identities after the Groups and
Conversation slices: Contact Request, Contacts, Identity, two Introduction
adapters, and the main Posts adapter. It also records the terminal
`DTR18-AUTH-02` disposition for all 165 retained dependency identities.

The integrated 22-adapter batch must finish at exactly 165 dependency / zero
placement exceptions. This is a terminal disposition, not a claim that all
layering debt was drainable. It does not reopen `DTR13-AUTH-01` or
`DTR17-AUTH-01`, alter the iOS pause boundary, or authorize behavior, schema,
migration, native/Go, wire, crypto, profile, or release-platform changes.

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
| TC-300-03 | All 22 placement rows are gone and all 165 dependency identities are unchanged and explicitly dispositioned. | Named placement/dependency case: GREEN; placement list empty, dependency count 165, exact identity hash and residual metadata asserted. |
| TC-300-04 | Plan 297's first increment and this terminal increment remain simultaneously guarded. | New closure contract +4; combined old/new DTR-18 contracts: exit 0, seven tests passed. |

The causal contract initially exited 1 for the intended remaining-family state:
old-path consumers still existed and the manifest still contained 22
placement rows. After the integrated relocations, import rewrites, and terminal
metadata update, all four closure cases passed. No compile failure or metadata
weakening was accepted as causal RED.

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
- Do not claim DTR-18 terminal or Wave 4C accepted before the pending integrated
  gates pass.

## Acceptance And Pending Closure

- [x] Six exact source/destination pairs and body hashes are recorded.
- [x] Thirteen focused repository files pass 62 tests.
- [x] Contact-request preservation rerun passes 12/12 after body restoration.
- [x] All 22 path/body/no-stale-consumer assertions pass in the four-test
      closure contract.
- [x] Combined old/new DTR-18 contracts pass seven tests.
- [x] Manifest contract pins 165 dependency identities, zero placements,
      exact identity SHA, and terminal metadata.
- [ ] Affected curated lanes and justified core/feature family sweeps are
      green.
- [ ] Architecture lane proves trustworthy 165 / 0 with zero new or stale
      issue.
- [ ] Runtime-root and completeness gates are green.
- [ ] Repository-wide `flutter analyze` and `git diff --check` are clean.
- [ ] Incremental Graphify refresh and affected query are recorded.
- [ ] Wave 4C aggregate `host-all` is green.
- [ ] Wave 4C `performance-host` is green where the integrated batch justifies
      it.
- [ ] Roadmap/index/authorization receipt and stable evidence are finalized.

The full `host-all` run is intentionally deferred to the single Wave 4C
aggregate after Plans 298-300 are otherwise green. The final release closure
will run it again under the program cadence.

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
