# Five Counterexample Lenses

Read this during review Step 2. Apply all five lenses during synthesis; do not
assign one worker per lens.

For each lens, use one state:

- `clear`: no required plan delta;
- `tighten`: a concrete correction is required before execution, but the core
  direction remains viable;
- `block`: the core contract, boundary, or release decision is unsafe or
  unresolved;
- `N/A`: the lens genuinely does not apply, with a one-line reason.

Do not emit numeric scores unless the user explicitly requests them. Each
material finding names the plan section or Test Contract row, current evidence,
counterexample/consequence, and smallest sufficient correction.

## L1 - Evidence Truth And Classification

Question: is the plan solving a real, current problem for the stated reason?

Check:

- Bug plans have a source-confirmed cause; feature plans have a confirmed
  current gap; stale/already-covered plans have current source and test proof.
- `confirmed`, `refuted`, and `unresolved` are used honestly.
- Cited symbols/lines operate on the claimed object, identity, scope, and
  lifecycle.
- Graph output is treated as navigation and verified in current source.
- The highest-risk mechanism and fallback survive repository evidence and,
  when necessary, authoritative version-matched dependency/platform docs.
- Quantitative baselines are current and comparable when the goal is
  quantitative.

Counterexamples:

- The current revision/working tree already implements the requested behavior.
- A cited line is adjacent to, but does not perform, the claimed operation.
- A build/config/environment artifact is mistaken for a code defect.
- A fallback runs after the failure point or under the same invalid constraint
  as the primary mechanism.

## L2 - Test Contract Causality

Question: can the plan go green with the wrong implementation?

Check every behavior row for:

- an honest causal RED, intentional compile-time gap, `GREEN sentinel`,
  boundary-only proof, or source-backed stale disposition;
- a GREEN assertion on an observable behavior, state, artifact, contract, or
  effect rather than only a mock call, type, flag, or broad success result;
- a meaningful counterfactual/mutation for each causal implementation or
  preservation contract; stale, acceptance-only, and justified boundary-only
  rows may use `N/A - <source-backed reason>`;
- an event/result/identity discriminator when sibling flows look alike;
- a specific negative assertion that cannot pass because of an unrelated
  exception, missing fixture, wrong path, timeout, or skipped action;
- setup that reaches the production seam rather than only a test double.

Try the smallest wrong implementation:

- no-op or unconditional success;
- early return or wrong handler/route/event;
- wrong user/entity/tenant/configuration;
- partial state update or stale-cache result;
- unrelated failure satisfying a negative assertion;
- inert mutation that leaves the test green.

## L3 - Bypass Sites And Scope Safety

Question: can another real entrypoint bypass the planned seam or violate its
scope assumptions?

Check plausible:

- shared wrappers and direct/raw operations;
- API, UI, CLI, job, queue, scheduler, startup, callback, and background paths;
- generated, plugin, native, alternate-configuration, or secondary-process
  entrypoints;
- sibling operations that do not inherit through the shared seam;
- hard `Do not` limits, stop-if conditions, preservation sentinels, accepted
  differences, and deferred owners.

Enumerate plausible bypasses tied to the changed operation, not every adjacent
feature. A focused single-seam plan may remain one slice unless another site
creates an independent behavioral or rollback risk.

## L4 - Execution, Discovery, And Gate Integrity

Question: can an executor run the contract literally and know whether it
passed?

Check:

- static command definitions exist, use the correct working directory/package,
  and would select the named test, target, scenario, or consumer;
- auto-discovery claims account for excludes, tags, sharding, path filters, and
  CI configuration;
- manifests, suite lists, build targets, jobs/matrices, and scenario registries
  are named exactly when required;
- semantic outcomes state intended discovery/selection, exit status, and zero
  relevant failures or new issues;
- skips, expected failures, retries, dirty-tree state, known failures, and
  environment exclusions cannot hide absent causal proof;
- focused and preservation proof is not replaced by aggregate-suite theater;
  broad-suite cadence follows repository policy;
- numeric thresholds, samples, and percentiles exist only for genuinely
  quantitative goals and have a comparable baseline.

Do not demand brittle test counts unless the repository gate contract itself
fixes the count.

## L5 - Boundary, Reversibility, And State Transitions

Question: does closure exercise the real risk and leave a safe failure path?

Check when triggered:

- production-equivalent datastore/provider/codec/runtime/platform/browser/
  device/hardware/external-service semantics;
- migration and compatibility directions, supported starting states,
  coexistence, idempotency, restart, rollback, recovery, and old/new behavior;
- partial failure, atomicity, retries, duplicate work, ordering, concurrency,
  cancellation, and crash/re-entry recovery;
- destructive effects and exact preservation across records, files, artifacts,
  related state, or external resources;
- durable marker/cache/derived-state lifecycle alignment across restart,
  reinstall, restore, replay, or configuration changes;
- target/fixture versions, identities, configuration, setup, registration, and
  evidence capture;
- genuinely user-owned product, compatibility, release-risk, or quantitative
  decisions.

Lower-level fakes may prove policy but cannot prove semantics that exist only
at the boundary being claimed. Manual proof needs an automation infeasibility
or disproportionality rationale under repository policy and independently
reproducible steps.
