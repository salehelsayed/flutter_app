# Tier Selection & Harness Registration (read in Steps 1, 2)

## A. Spec → test-obligation mapping

Walk the spec (or grounded free-text intent) top-down. Each section emits an obligation:

| Spec section | Obligation it generates | Lands at |
|---|---|---|
| **Problem Statement** (what's broken, who, when) | One RED test per symptom, failing on HEAD *for the stated reason*. The symptom narrative IS the RED expectation. | Lowest deterministic tier that stubs the broken seam |
| **Impact** (severity/frequency) | A preserved-green sentinel for adjacent behavior the fix must not break + a regression test reproducing the quantified failure | Fix tier + named-gate preservation |
| **Current State** (file:line, data flow) | A test that exercises *that exact seam* — when two paths return the same result, assert a distinct observable discriminator | Integration / real-fixture tier |
| **Scope** (in/out) | Becomes `Scope Guard` + `Accepted Differences` (no test; names the owning follow-up) | planning artifact |
| **Test Cases** (IDs) | The RED Test Catalog: per ID → tier → file → RED reason → GREEN assertion → mutation that re-reds | per-case via the matrix below |

One spec case routinely produces **three** rows: a **unit/fast floor** (mandatory), an **integration middle**, and a **real-environment proof** (closure gate for OS-boundary / cross-process / external-system specs).

## B. Tier-selection decision matrix

Pick by the behavior's *properties*, not convenience. "Required" = the plan is insufficient without it. Map the generic tiers below onto this project's actual layout (recorded in `docs/tdd/HARNESS.md`).

| Behavior property | Required tier | Fake OK or real fixture? | Harness-registration consequence |
|---|---|---|---|
| **Pure logic / domain / serialization** (use-case, model, encoding, comparator) | unit | in-memory fakes/stubs suffice | usually **AUTO (runner glob)** |
| **Persistence + state transitions** (data survives, status transitions durable) | integration with a **real persistence engine** (real DB file / in-memory instance of the real engine — durability is the point, not a fake) | real engine | AUTO or add to the integration suite/gate |
| **Schema/data migration** (constraints, idempotency, data preservation) | migration test against the **real engine — fakes forbidden**: schema introspection before/after, row preservation, run-twice idempotency | real engine mandatory | number it (`migration v##`) in the plan; register in the migration/integration gate |
| **UI / component render + interaction** | the project's component/widget/DOM test tier | fakes for services; beware async teardown races on shared global resources | AUTO (glob) |
| **Multi-component flow inside one process** (A→B convergence, ordering) | integration with faked transport/network boundary | fakes + real migrations in setup | AUTO or suite list |
| **Cryptography / handshake / protocol convergence** | E2E with the **real implementation** — a fake cannot prove convergence | real implementation required | register in the E2E runner/gate |
| **External service contract** (real API, queue, storage) | E2E against a real or containerized instance | real/containerized; no hand-rolled fake | register in the E2E job (often not auto-discovered) |
| **OS-boundary / cross-process / cross-machine** (push/notification callbacks, deep links, background tasks, multi-device convergence) | **real-environment proof** (device/emulator/multi-process harness) | real environment on all parties | register the scenario in the proof runner. **This is the closure gate, not optional**, for OS-boundary specs |
| **Multi-instance with faked network, no real protocol** | integration — do **not** misfile it in the E2E tier (that tier's harness expects the real stack) | fakes | AUTO/suite list |

**Rule of thumb:** drop to the **lowest** tier that can still *fail for the real reason*; climb a tier only when the lower tier physically cannot exercise the boundary (OS callback, real crypto convergence, cross-process, real external service, real persistence engine).

## C. Fake vs real fixture

- **Fake** (in-memory repositories, stub services, fake transport): use for pure logic, wiring, and UI. Fast, deterministic, auto-discovered.
- **Real persistence fixture**: mandatory whenever *persistence/durability/migration* is the behavior under test — a fake cannot prove a column constraint, that a status survives restart, or that a migration is idempotent. Bring the relevant migrations into test setup.
- **Real protocol / external system (E2E or environment proof)**: mandatory for crypto/protocol convergence, real service contracts, OS boundaries, and cross-process/cross-machine convergence. A fake here proves nothing about the actual boundary.

## D. Harness registration — what to do so the test runs in a gate

Fill this table with the project's real mechanisms during the Step 0.5 harness bootstrap; the generic shape is:

| Tier | Action | Verify it runs |
|---|---|---|
| unit / component (auto-discovered) | **nothing** — place it where the runner's glob finds it | run the suite; confirm the new test appears in the output/count |
| curated suite / named gate | **manually add the path** to the suite list / gate script / CI job — the glob will NOT add it | run the named gate; confirm presence |
| integration | auto-run or suite list, per project convention | run the integration gate; confirm presence |
| E2E scenario | register the scenario wherever the E2E runner enumerates its cases (config, tag, scenario switch, job matrix) | run the E2E runner's list/dry-run mode; the new scenario MUST appear |
| real-environment proof | register in the proof runner's scenario list; the runner only RUNS registered scenarios, it never discovers them | dry-run/list the proof runner; confirm the scenario index |

**Runners run; they don't register.** If a new scenario does NOT appear in the runner's listing, the bug is in your registration wiring, not the test.
