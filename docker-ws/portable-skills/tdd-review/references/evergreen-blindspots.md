# Evergreen Blind-Spot Sweep

Read this during review Steps 2 and 4. Consider every class internally. Report
each hit with evidence and a concrete plan delta, then summarize the remaining
classes as clear/N/A. Emit a full ten-row table only when the user requests a
thorough report or fix-list.

## B-1 - One-Way Or Irreversible Change

Trigger: stored data, schema, file/API/wire format, artifact, identity, key,
external resource, or release behavior that an earlier version cannot safely
read or undo.

Check downgrade/rollback behavior, read-old/write-new staging, coexistence,
kill switch, backup/recovery, staged release, and whether affected data or
identity is replaceable. An explicit one-way decision belongs to the user or
release owner and needs compatible tests and operational constraints.

## B-2 - Bypassing Callers Or Entry Points

Trigger: every plan that changes a shared operation or policy.

Search both the wrapper and direct/raw operation. Include plausible API, UI,
CLI, worker, queue, scheduler, startup, callback, background, generated,
plugin, native, alternate-configuration, and secondary-process entrypoints.
Do not enumerate unrelated adjacent features.

## B-3 - False Or Stale Evidence

Trigger: every plan.

Verify load-bearing symbols and lines, current behavior, test existence,
registration, and stale/already-covered claims. A graph hit or historical plan
is not current proof. Spot-check supporting citations and expand only when a
contradiction becomes material.

## B-4 - Vacuous Goal, Test, Counterfactual, Or Gate

Trigger: every Test Contract.

Try a no-op, unconditional success, wrong handler/event/entity/configuration,
partial update, stale cache, unrelated failure, skipped scenario, or inert
mutation. Confirm the command selects the intended proof and the assertion
measures the actual behavior.

For quantitative work, require a comparable baseline, sample method, variance
controls, and a decision threshold. For ordinary behavior, prefer a binary
semantic assertion over an arbitrary number. An aggregate suite cannot replace
focused causality.

## B-5 - Atomicity, Concurrency, Ordering, And Destructive Effects

Trigger: migrations, swaps, cleanup/delete, retries, deduplication, shared
mutable state, asynchronous work, cancellation, or re-entry.

Check failure before/during/after commit, partial state, duplicate work,
concurrent invocation, ordering, idempotency, crash/restart recovery, and
exactly what is changed, removed, retained, or externally leaked.

## B-6 - Durable Marker, Cache, Or Derived-State Survival

Trigger: flags, markers, caches, derived UI/state, checkpoints, or "already
done" decisions.

Check marker/data lifecycle and backup domain, reconstruction after restart or
replay, reinstall/restore/configuration behavior, invalidation, and the full
marker-by-data-exists decision table. A same-process reopen may be fooled by
cached state.

## B-7 - Highest-Risk Bet And Fallback

Trigger: every plan with a non-trivial technical mechanism or fallback.

Verify call ordering, constraints, version, and failure behavior using current
repository/dependency source and primary documentation when needed. Confirm the
fallback is reachable before the failure point, preserves the same invariants,
and does not violate the constraint that breaks the primary mechanism.

## B-8 - Underpowered Real Boundary

Trigger: persistence-engine, provider/wire, process/runtime, platform/browser,
native/OS, device/hardware, distributed-system, authentication,
authorization, tenant isolation, secret handling, security-provider,
cross-version, or external-service claims.

Confirm the production-critical leg is named and closed on a realistic
standing proof. Fakes may prove decisions and error mapping but cannot prove
the real boundary's semantics. Pin relevant versions, identities,
configurations, fixtures, targets, setup, registration, and evidence capture.
Respect repository availability policy without silently waiving a required
claim.

## B-9 - Untested Preservation Or Accepted Difference

Trigger: every `must preserve`, hard de-scope, "unaffected", or accepted
difference claim.

Require a named sentinel when adjacent behavior is plausibly exposed. Require
an owner or test-locked rationale for accepted differences. Do not demand
unrelated preservation tests for ceremony.

## B-10 - Platform, Version, Configuration, Or Protocol Parity In Prose

Trigger: compatibility or parity claims across divergent implementations,
versions, platforms, browsers, providers, configurations, processes, or
protocols.

Require literal commands and fixtures for each material divergent path, plus
both directions or round trips when compatibility is promised. One target,
configuration, or implementation cannot prove another unless current source
shows the paths are identical below the tested seam.
