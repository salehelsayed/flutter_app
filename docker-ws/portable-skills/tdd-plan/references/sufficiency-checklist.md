# Definition Of Sufficient

Read this during the final planning step. Any `No` leaves the plan
`planning-draft` or `evidence-gated` until the structural gap is fixed or
explicitly owned.

## Core Conditions

1. **Behavior totality:** every requested behavior or invariant maps to a named
   automated test or a justified proof at the right boundary.
2. **Causal proof:** every behavior change states its honest baseline, expected
   GREEN result, and meaningful counterfactual/mutation. Preservation-only
   rows are labeled `GREEN sentinel`.
3. **Executable gates:** commands or justified proof procedures are literal,
   scoped to the correct working directory/environment, state semantic
   outcomes, and explain how every new automated proof is discovered by a real
   gate.
4. **Boundary realism:** claims that depend on production-equivalent engine,
   provider, process/runtime, platform, device, hardware, compatibility, or
   external-system semantics close on that boundary; lower-level substitutes
   may supplement but cannot replace it.

## Yes/No Gates

- [ ] Applicable repository instructions were read and the Project Convention
      Snapshot records current runners, selectors, discovery, gates, fixtures,
      repository root/revision/state, resolved plan path, and unresolved
      conventions.
- [ ] When Graphify was authorized and used, it followed the destination
      repository's policy and commands. Otherwise the snapshot says why it did
      not run and names the targeted-source fallback. Neither state treats
      graph output as proof.
- [ ] Every behavior and declared invariant appears in the Test Contract or is
      explicitly accepted out of scope with an owner.
- [ ] Every row names an exact `file/target::test`, scenario, build consumer, or
      observable manual proof rather than a broad test category.
- [ ] Every row labels the baseline honestly as causal RED, intentional
      compile-time gap, GREEN sentinel, boundary-only proof, or stale
      verification.
- [ ] Every causal baseline can fail for the documented mechanism. Negative
      assertions cannot pass merely because of an unrelated error.
- [ ] Stale/already-covered and acceptance-only plans use exact verification
      evidence and do not invent a RED, cause, edit, or mutation obligation.
- [ ] Every distinct behavior-changing contract names a meaningful
      counterfactual/mutation and the test expected to re-red; planning does not
      claim the run result. Stale, acceptance-only, and justified boundary-only
      rows may use `N/A - <source-backed reason>`.
- [ ] Every GREEN sentinel names a meaningful counterfactual or explains why a
      causal row fully guards the same preservation obligation.
- [ ] Shared-result paths use a discriminator when the wrong sibling path could
      otherwise satisfy the assertion.
- [ ] Preservation sentinels cover adjacent behavior plausibly exposed by the
      implementation; unrelated sentinels are not added for ceremony.
- [ ] Persistence, schema, file/API/wire-format, or artifact migrations use the
      real technology and supported prior-state fixtures, with applicable
      before/after, idempotency, restart, atomicity, rollback/recovery, and
      compatibility direction checks.
- [ ] Process/runtime, native/OS, browser, external provider, device/hardware,
      distributed, authentication/authorization/trust, security-provider, and
      cross-version claims have named production-equivalent proof and exact
      setup when those boundaries are material.
- [ ] Manual proof states why automation is infeasible or disproportionate
      under repository policy, plus exact setup/actions, observable evidence,
      success/failure interpretation, and owner.
- [ ] Quantitative goals define a comparable baseline, metric, sample method,
      variance controls, decision threshold, and registered regression gate.
      Ordinary binary behavior is not forced into an arbitrary number.
- [ ] Commands are copy-pasteable and manual procedures independently
      reproducible. They include working directory/package/environment scope
      when relevant and state selection, discovery, exit status, observable
      evidence, and zero relevant failures or new issues. Counts appear only
      when the gate contract fixes them.
- [ ] Gate strategy is proportionate and follows repository policy: focused
      causality plus preservation and affected-suite proof, with broader suites
      run or assigned to their real owner/cadence.
- [ ] Discovery/registration is concrete for every new proof and verified
      against excludes, tags, manifests, suite lists, build targets, CI path
      filters/matrices, or scenario registries as applicable.
- [ ] Evidence uses `confirmed`, `refuted`, and `unresolved` honestly; weak
      evidence is never mislabeled refuted or confirmed.
- [ ] Repository state is planned before execution when version-controlled;
      expected baseline failures, pre-existing failures, environment
      limitations, and scope drift have distinct interpretations.
- [ ] Scope Contract And Guard names in-scope work, preservation obligations,
      hard `Do not` limits, deferred owners, and accepted differences.
- [ ] The plan does not claim unrun RED, GREEN, mutation, benchmark, or
      environment evidence. Any separately authorized planning-time run is
      labeled preliminary and does not satisfy the execution contract.
- [ ] Reviewer findings, execution results, and conditional profiles appear
      only when the corresponding phase or trigger exists.

## Blind-Spot Sweep

For each recurring class, add a Test Contract row or record a justified `N/A`:

- [ ] **Lifecycle / derived-state durability:** derived state is reconstructed
      correctly on remount, reopen, restart, replay, restore, or re-entry when
      applicable.
- [ ] **Bypassing callers / sibling consistency:** wrappers and plausible raw
      operations or alternate entrypoints inherit the change, or deliberate
      asymmetry is test-locked.
- [ ] **Destructive effects / atomicity / concurrency:** delete, cleanup,
      cancel, swap, retry, duplicate, ordering, partial failure, and concurrent
      behavior assert both changes and preservation where triggered.
- [ ] **Invariant re-verification:** reset, self-heal, retry, resume, rollback,
      release, or re-entry re-checks invariants invalidated by the transition.
- [ ] **Compatibility / fallback:** prior versions, alternate configurations,
      and the highest-risk fallback are verified when promised.

## Test Contract Gate

Every row has non-empty values for:

- named test or proof;
- level and fixture;
- honest baseline-to-GREEN state;
- counterfactual/mutation or justified equivalent;
- literal command or justified proof procedure plus discovery/registration
  when applicable.

A missing behavior row is a coverage hole. A baseline that cannot fail for the
stated reason is theater. A test that enters no gate is invisible. A lower-level
substitute cannot prove semantics that exist only at a real boundary.
