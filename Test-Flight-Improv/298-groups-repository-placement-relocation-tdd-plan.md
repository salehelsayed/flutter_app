# 298 - Groups Repository Adapter Placement Closure

Status: Implementation applied / focused proof green / closure gates pending
Type: Modification
Spec: `Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md`
(`DTR-18`)
Classification: terminal-increment execution record
Closure tier: host structural + Groups repository preservation

## Outcome And Scope

This record owns the Groups slice of DTR-18's terminal placement increment:
move all 13 concrete repository adapters from
`lib/features/groups/domain/repositories/` to
`lib/features/groups/data/repositories/`, update their consumers, and leave no
old-path shim. It owns 13 of the 22 placement identities present after Plan
297. The integrated terminal batch, not an independently captured intermediate
manifest, is required to move the canonical architecture inventory from
165 dependency / 22 placement exceptions to 165 / 0.

No repository behavior, API, schema, migration, queue ordering, retry policy,
wire/native/Go code, or dependency exception is in scope.

## Reviewed Relocations

The common source prefix is
`lib/features/groups/domain/repositories/`; the destination replaces `domain`
with `data`. The body hashes exclude import/export lines so that necessary
relative-import rewrites do not weaken preservation proof.

| Adapter | Preserved body SHA-256 |
|---|---|
| `group_exit_diagnostic_repository_impl.dart` | `50640490daad1ed8aa3e45ab2248d89e5f9f224883c4d6540e8cf7e0ef6607e7` |
| `group_exit_intent_repository_impl.dart` | `fb0f6344390d71bc3206144c9c9a008e8374c2b86f0ec60497db6dfc1694b988` |
| `group_history_gap_repair_repository_impl.dart` | `5991b2a9cad4ff1e5ea4d1695e0623ea8c8cc63c4bc65c9fc9bf4f72bea1e893` |
| `group_invite_delivery_attempt_repository_impl.dart` | `42850e9af2a99bd1617c1f943c448c11db4bd83252a113203863d55f3a7fc27c` |
| `group_message_repository_impl.dart` | `414791b5c32e3a32000db687cf012cfc4a973821319c686896103d824ca0461c` |
| `group_pending_broadcast_repository_impl.dart` | `2a61d288bd4719986886a96a54521329f5311bbb5db7f58fb2c0f167d1c12783` |
| `group_pending_key_distribution_repository_impl.dart` | `040432e247dd6dd2ea631e9b159554e487c5c344b3aef7fe852793cb0c1a578a` |
| `group_pending_key_repair_repository_impl.dart` | `9e11d726d2984dade495d2fde435371ea30b62f3b2d99b25565fa8c6db8d38e1` |
| `group_pending_membership_message_repository_impl.dart` | `35b0cc141b05c185a47130de53dac188a35239c4ff48c55692a7394e70432f38` |
| `group_pending_reaction_repository_impl.dart` | `35cd4ccd56b45cdb6d556df7a300b42008d9587e9c803480b6b0214e4b40c537` |
| `group_reaction_replay_outbox_repository_impl.dart` | `29aadb44b199d5f01c2cf7879933fe746bf648b40280d3aeb0ea1774d65ead1d` |
| `group_repository_impl.dart` | `c32d07debab99919a94c9df5e098b7bd12e53190d42325defc1dbf70778bd877` |
| `pending_group_invite_repository_impl.dart` | `04eb0b4d54864c308f92689289c24f29587ce2312fdb559f0e4ef9a8ff45fa04` |

## TDD Contract And Evidence

| Case | Required result | Evidence / status |
|---|---|---|
| TC-298-01 | Every reviewed adapter exists only at its exact data-layer destination, retains its reviewed body hash, and has no stale package-URI consumer. | `test/unit/dtr18_placement_closure_contract_test.dart`, named Groups case: GREEN as part of the four-test closure contract. |
| TC-298-02 | Groups persistence, outbox, replay, pending-message, invite, and repair behavior remain unchanged. | Nine focused Groups repository proof files: exit 0, 150 tests passed. |
| TC-298-03 | No compatibility shim or duplicate implementation remains below the old domain prefix. | TC-298-01 exact old-path absence and live-consumer scan: GREEN. |
| TC-298-04 | The full placement family closes without changing any of the 165 dependency identities. | Combined old/new DTR-18 contracts: exit 0, seven tests passed. Canonical architecture lane: pending. |

The causal contract was added before the integrated relocation batch. Its
initial command exited 1 for the intended state: the old Groups paths were
still present. After all 22 reviewed moves and import rewrites, the same
contract passed all four cases. No compile failure was accepted as causal RED.

## Guardrails

- Preserve constructors, method bodies, SQL, mapping, retry/error behavior,
  streams, and disposal semantics.
- Rewrite imports only as required by the path move.
- Do not leave an export, barrel, proxy, part, or compatibility file at an old
  path.
- Do not add, retarget, or remove a dependency exception.
- Do not absorb Conversation or the six remaining feature adapters into this
  record; Plans 299 and 300 own those proof families.
- Do not claim Wave 4C acceptance from focused proof.

## Acceptance And Pending Closure

- [x] Thirteen exact source/destination pairs are recorded.
- [x] Body-preservation hashes and no-old-path assertions are green.
- [x] Nine focused repository proof files pass 150 tests.
- [x] The all-placement contract passes four tests; the combined DTR-18
      contracts pass seven.
- [ ] Affected curated Groups lane is green on the integrated tree.
- [ ] Justified affected family sweep is green.
- [ ] Architecture lane proves trustworthy 165 / 0 with zero new or stale
      issue.
- [ ] Runtime-root and completeness gates are green.
- [ ] Repository-wide `flutter analyze` and `git diff --check` are clean.
- [ ] Incremental Graphify refresh and affected query are recorded.
- [ ] Wave 4C aggregate `host-all` and justified `performance-host` are green.

Full `host-all` is a Wave 4C batch gate, not a Plan 298 per-plan gate.
Unavailable device/version bands are N/A under project policy; this
path-and-host preservation slice makes no new mobile OS or relay claim.

## Execution Progress

| Date | Phase | Result | Next |
|---|---|---|---|
| 2026-07-28 | Causal RED | Closure contract exited 1 at the intended Groups old-path assertion. | Apply exact relocations and consumer rewrites. |
| 2026-07-28 | Implementation | Thirteen adapters moved to `data/repositories`; old paths removed; no shim added. | Run structural and repository preservation proof. |
| 2026-07-28 | Focused GREEN | Groups closure case green; nine repository proof files passed 150 tests; integrated closure contract +4 and combined DTR-18 contracts +7. | Complete affected policy/family gates, then the Wave 4C aggregate. |
