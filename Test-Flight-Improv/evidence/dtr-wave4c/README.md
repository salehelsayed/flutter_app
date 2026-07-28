# DTR Wave 4C acceptance evidence

Date: 2026-07-28

Scope: DTR-16 / Plan 296, DTR-17 / Plan 295, and DTR-18 / Plans
297–300

Wave verdict: **Wave-accepted** on 2026-07-28

## Terminal outcome

Plan 297 remains DTR-18's closed first increment. It moved application-resume
orchestration to the app layer and two Posts adapters to data, taking the
trustworthy architecture inventory from 182 dependency / 24 placement
exceptions to 165 / 22.

Plans 298–300 then moved the remaining 22 concrete repository implementations
from feature `domain/repositories/` to `data/repositories/`, with no old-path
shim. Their reviewed implementation bodies are unchanged apart from
import/export lines. The terminal inventory is:

- 165 dependency exceptions, the same exact identities present after Plan 297;
- zero placement exceptions;
- zero architecture-guard issues.

The overall DTR-18 reduction is therefore 17 dependency exceptions and all 24
placement exceptions. DTR-18 is terminal under `DTR18-AUTH-01` and
`DTR18-AUTH-02`.

`DTR18-AUTH-02` dispositions, rather than silently deletes, the 165 dependency
residual:

| Residual family | Identities | Disposition |
|---|---:|---|
| `lib/core/debug/**` | 92 | Retained proof capability under `DTR13-AUTH-01` |
| `lib/core/services/p2p_service_impl.dart` | 8 | Retained transport boundary under `DTR17-AUTH-01` |
| `lib/core/lifecycle/handle_app_paused.dart` | 8 | Retained iOS lifecycle/background boundary |
| Other source-owned families | 57 | Retained for separately bounded source-family work |
| **Total** | **165** | Every row has an owner, reason, revisit condition, and authorization evidence |

The exact dependency-identity SHA-256 is
`d4f42f151ae18feaf922ad90f172401917a3b7b4ca104d4574e6f9c12a6afb40`.
The canonical full tuple set—rule, source, directive kind, target, owner,
reason, condition, and evidence—has SHA-256
`5f24faf4c5f693d0f19eb18503e5d37c4db4580c6ccbc91806abc75a78dcf132`.

## Plan-level proof

The causal placement contract first exited 1 on the intended old-path and
22-row manifest conditions. It then passed all four cases after the integrated
relocation. No compile failure was accepted as causal RED. A mutation of the
expected full disposition-tuple hash re-established RED at the intended
assertion; restoring the reviewed hash returned that case to green.

The accepted focused and preservation receipts were:

| Proof family | Result |
|---|---|
| DTR-18 closure contract | 4 passed |
| Plan 297 plus terminal DTR-18 contracts | 7 passed |
| Groups repository preservation | 150 passed across 9 files |
| Conversation message/reaction preservation | 40 passed |
| Conversation media repository preservation | 49 passed |
| Remaining feature repository preservation | 62 passed across 13 files; Contact Request rerun 12/12 |
| `1to1` | 2,464 Flutter tests plus relay Go tail passed |
| `groups` | 3,265 Flutter tests plus all Go/relay tails passed |
| `intro` | 300 passed |
| `posts` | 7 host tests and 2 device tests passed on USB Pixel 6 target `21071FDF600CSC` |
| `feature-host-all` | 8,441 passed, 1 declared skip across 811 paths |
| `core-host-all` | 2,847 passed across 367 Flutter paths; Android renderer contract passed |

Policy and structural closure also passed:

- `architecture-boundaries`: 6/6; exact mode; 1,039 sources; trustworthy
  165 dependency / 0 placement inventory; zero issues;
- `runtime-roots`: 20/20; trustworthy, no drift;
- `completeness-check`: 1,359/1,359 test files classified;
- repository-wide `flutter analyze`: zero issues;
- `git diff --check`: clean;
- C4 file, component, code, and infrastructure views record the current
  destinations and contain no old implementation path.

Graphify received the required incremental refresh. The resulting query
exposed source-less orphan import nodes for old paths, so a complete rebuild
was performed rather than retaining misleading topology. The final graph has
63,016 nodes and 96,398 edges; its TDD overlay covers 1,460 files, 14,221 named
tests, and 1,094 production targets. The final focused query was current and
anchored with fingerprint `c148591f22c0989a`; it anchors only the new
`data/repositories` implementations, and an exact old-implementation URI/path
scan of the graph is empty.

| Graph artifact | SHA-256 |
|---|---|
| `graphify-arch/graphify-out/graph.json` | `8b9bc76e5865d1b7d1a3c70056337afdeca4fbf936998cab9a5763a553ddb16a` |
| `graphify-arch/graphify-out/manifest.json` | `4d1cceed44a39cc3e21f89b30c2af943f11f114e93426539d7f89b5a7082e47e` |
| `graphify-arch/tdd-overlay.json` | `ab01b69ebc7e14c4c6bff7e01d32de87d1b946da45197a78f56c073338702511` |

## Wave aggregate

The exact accepted commands, in order, were:

```bash
./scripts/run_host_test_gates.sh performance-host --batch-flutter --concurrency 4 --continue-on-failure --reporter failures-only
./scripts/run_host_test_gates.sh host-all --batch-flutter --concurrency 4 --continue-on-failure --reporter failures-only
```

`performance-host` exited 0 in 17 seconds:

- 21 exact Flutter paths;
- 106 tests passed, zero skipped, zero failed;
- final scope-completion marker present.

The full `host-all` aggregate exited 0 in 785 seconds:

- 1,277 planned items: 1,269 exact Flutter paths and eight serial Go tails;
- 12,845 Flutter tests passed, one declared test skipped, zero failed;
- all eight Go tails passed;
- final `PASS: host tests completed for scope: host-all`.

The accepted original logs and deterministic `gzip -n` archives are:

| Artifact | Path | Size (bytes) | SHA-256 |
|---|---|---:|---|
| Original `host-all` log | `build/wave4c-logs/wave4c-host-all-accepted.log` | 15,789,221 | `6f0cb1c15b28209aa7744e6c273cd9b4ff29083b5cb677e807a827dcec06a286` |
| Deterministic `host-all` archive | `Test-Flight-Improv/evidence/dtr-wave4c/wave4c-host-all-accepted.log.gz` | 1,229,282 | `09ec61bc113a850fe053eb55c85032bbba7f08f06069a5ad7911fce84412d55b` |
| Original `performance-host` log | `build/wave4c-logs/wave4c-performance-host-accepted.log` | 70,097 | `ff45b29f9e1a3a2d0fd1fe2734a4330e373922b7bf30657581f690320b6d1856` |
| Deterministic `performance-host` archive | `Test-Flight-Improv/evidence/dtr-wave4c/wave4c-performance-host-accepted.log.gz` | 8,063 | `cf0c00445e8a22ae2192bdaf74a706543b0ac11bce8aebaa42be4179881cefe2` |

Decompressing each archive reproduces its original-log SHA-256 exactly.

## Tested state and workspace disclosure

Both aggregate commands ran in the shared dirty workspace against one frozen
implementation state. An alternate index captured tracked files plus
untracked, nonignored files without replacing the shared index:

| Identity | Value |
|---|---|
| Base and unchanged `HEAD` | `765be74523b25ce592ff200ff435653b35c66b4d` |
| `HEAD` tree and shared-index tree | `bea5eec367ed57617ad2a4f8ce8a7c549797b57e` |
| Frozen tested tree | `8b4052ea418a537d1a9af145da44dd20d367fb7b` |
| Porcelain-v2 workspace snapshot SHA-256 | `24d8dd61e243f3203c5fd024fcffad9074c880a29f4117ea06a5a0d34ea818ee` |
| Shared-index byte SHA-256 | `b0b42576e93d4c4cc66de885866fabb84cc40361ef4eb5f0852561227d16eba9` |

The tested tree and porcelain snapshot matched before `performance-host`,
between the two aggregate commands, and after `host-all`. Because 25 earlier
relocations appear as tracked deletions plus untracked destinations in this
workspace, `core-host-all`, `runtime-roots`, and the Wave aggregate temporarily
staged only those exact source/destination pairs in the real index. Each run
restored the original shared index; the byte SHA above matched before and after
the accepted aggregate.

No commit, synthetic commit, or tag was created. The evidence archives and
final closure-document updates postdate the aggregate and are intentionally
not files in the frozen tested tree. No production or test source changed
after the aggregate.

## Closure

DTR-16, DTR-17, and DTR-18 are Plan-green and Wave-accepted. Wave 4C is the
last implementation wave in this rollout.

DEP-01's preceding-wave gate is now green, but Wave 5 planning remains blocked
on the already-open Product + Release decision defining supported platform and
CI targets. This receipt does not resolve that decision. Final release-closure
`host-all` and justified `performance-host` also remain separate later
obligations.
