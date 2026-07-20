# Proof-Level Selection And Test Registration

Read this during planning Steps 1 and 2. Map these generic properties onto the
destination repository's real level names, directories, runners, and gates.

## Behavior To Obligation Mapping

| Input element | Obligation | Plan location |
|---|---|---|
| Observable problem or requested behavior | Bug: causal baseline failure. New behavior: assertion, contract, or intentional compile-time gap showing the confirmed absence. | Test Contract at the lowest causal level |
| Impact and preservation | Regression for the affected behavior; add a GREEN sentinel only for adjacent behavior plausibly exposed by the change. | Test Contract |
| Current mechanism | Exercise the cited seam; add a discriminator when sibling paths return the same broad result. | Test Contract or a focused test note |
| Scope and constraints | In scope, preserve, hard `Do not`, deferred owner, and accepted differences. | Scope Contract And Guard |
| Enumerated cases or invariants | One named test or justified proof per behavior. | Test Contract |

One behavior needs multiple rows only when they prove distinct obligations, for
example a deterministic policy decision plus a production-equivalent provider
or runtime boundary.

## Selection Matrix

Use the repository's actual terminology in the finished plan.

| Behavior or claim | Typical lowest causal proof | Escalate fixture or level when |
|---|---|---|
| Pure logic, validation, transformation, state machine | Unit or property test | A runtime/library implementation detail is itself part of the claim |
| Parsing, serialization, schema, or protocol shape | Unit, golden, property, or contract test | Interoperability with another implementation/version is claimed |
| UI/component render and interaction | Repository's component/UI harness | Browser engine, native accessibility, layout/runtime, or OS behavior is claimed |
| Module/service collaboration inside one process | Component or integration test | Real collaborator semantics, transactionality, timing, or lifecycle matter |
| Persistence, cache, query, constraint, or durability | Repository/integration test | Use the production-equivalent engine when its locking, durability, constraints, recovery, or query semantics are the behavior |
| Data/schema/file/API migration | Migration or compatibility integration test | Start from supported prior-state snapshots; use the actual engine, codec, or service; prove idempotency and rollback/recovery where relevant |
| External API, queue, storage, or wire adapter | Contract/integration test with controlled substitute | Use a sandbox, container, recorded contract, or real provider when provider/wire/TLS semantics are claimed |
| Lifecycle, process, worker, scheduler, concurrency, cancellation | Integration or system test | Real process restart, scheduling, isolation, ordering, or runtime behavior is part of the claim |
| Native/plugin/OS/browser/device/hardware boundary | System or boundary proof | Use the relevant supported runtime, sandbox, emulator, device, browser, or hardware fixture |
| Multi-instance or distributed behavior | Multi-instance integration/system test | Use real transport/coordinator/service semantics when convergence or failure behavior depends on them |
| Security, authorization, identity, or cryptographic behavior | Unit vectors/properties plus seam tests | Use the actual provider, key store, policy engine, or interoperability boundary when that behavior is claimed |
| Build, package, generated code, or consumer compatibility | Compile/build/consumer fixture | Exercise each supported toolchain, artifact type, or downstream consumer path claimed |
| Performance, memory, throughput, or resource use | Benchmark or performance test | Use representative data/configuration and a comparable environment; threshold is repository- or user-owned |
| Cross-version/platform/configuration compatibility | Compatibility matrix | Exercise both divergent paths and every required direction or round trip |

## Selection Rules

- Choose the lowest proof level that can fail for the real causal reason.
- Add a faster seam test only when it proves a real decision contract; do not
  add proxy rows to satisfy a level count.
- Add a production-equivalent boundary row whenever the acceptance claim
  depends on semantics a fake cannot reproduce.
- Do not over-escalate: a fake-network policy test is not a real-network test,
  but it may be the correct closure when no network behavior is claimed.
- Label adjacent preservation coverage `GREEN sentinel`. It need not fail on
  HEAD, but its counterfactual must still guard the preservation obligation.
- Compile-time RED is valid only when a deliberately missing symbol/type is the
  confirmed gap. Ordinary implementation errors are not a planned compile RED.
- Manual proof is a last resort. State why automation is infeasible or
  disproportionate under repository policy, exact setup and actions,
  observable evidence, success/failure interpretation, and owner.
- Follow the destination's environment-availability policy. An unavailable
  optional target is not silently promoted to a required blocker, and a
  required production boundary is not silently waived.

## Migration And Compatibility Rules

When a behavior changes stored data, schema, file format, API shape, wire
contract, or generated artifact, name the supported starting states and prove
the applicable directions:

- old state -> new implementation;
- new state -> restarted/reopened new implementation;
- repeated upgrade or replay idempotency;
- old/new coexistence or round trip when compatibility is promised;
- rollback, recovery, backup, or explicit one-way release strategy;
- partial failure, atomicity, and concurrent access when plausible.

Use the real technology and its inspection mechanisms. Do not assume a
relational database, version pragma, sidecar layout, or rollback model.

## Discovery And Registration

Every new proof names how a real gate finds it.

| Mechanism | Required plan entry | How to verify |
|---|---|---|
| Runner auto-discovery | Exact directory/name/tag rule plus relevant excludes | Run a list/collect command or focused suite and confirm selection |
| Manifest, suite list, or build target | Exact file/key/target to edit | List or execute the target and confirm the test is included |
| Tag/group/filter | Exact tag and gate filter | Run collection/listing with the filter and confirm selection |
| CI workflow or matrix | Exact job/workflow/matrix entry and path rules | Inspect rendered/listed configuration or run the local equivalent |
| Dispatcher/scenario registry | Exact case, route, or registry entry | Use list/dry-run/discovery and confirm the scenario appears |
| Manual closure | Exact owner, environment, actions, evidence capture, and retention location | Independent reproduction of the written steps |

Never write `AUTO` from convention alone. Verify excludes, tags, sharding, path
filters, and CI configuration do not make the new test invisible. Registration
in a broad suite proves discovery, not that the plan's causal gate has run.
