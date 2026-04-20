
# Document --> Codebase
I wan t you to run this prompt 3 times in seqwuence using a new agent each time so we don't overwhelm this
  context ( I want you to review the document
  @Test-Flight-Improv/Network-Transport-libp2p-Feature/01-application-layer-map.md  and understand the scope and
  then review the codebase and provide me with missing information) but I want you to be critical to the output and
  compare it to the codebase and the scope of the document before you decide to update the document


# Codebase --> document
I want you to run this prompt 3 times in sequenec using a new agent each time so we dont overwhelm this context, (I want you to review the codebase and check that every in-scope artifact appears in the document @Test-Flight-Improv/Network-Transport-libp2p-Feature/00-transport-dependency-matrix.md  and provide me with missing information) but I want you to be critical to the output and compare it to the codebase and the scope of the document before you decide to update the document


# Factual
I wan t you to run this prompt 3 times in seqwuence using a new agent each time so we don't overwhelm this
  context ( I want you to review the document
  @Test-Flight-Improv/Network-Transport-libp2p-Feature/01-application-layer-map.md  and understand the scope and
  then review the codebase and provide me with line-by-line fact-check, for every factual claim in the document (function name, param type, file path, stream name, ordering), grep/read the code and output CONFIRMED or WRONG.)but I want you to be critical to the output and compare it to the codebase and the scope of the document before you decide to update the document





  Best workflow:

  1. Run Phase 0 on the current codebase and record the baseline.
  2. Run the instrumentation phase next. This becomes your measurement baseline commit.
  3. For Phase 1 to Phase 6, run each phase on its own branch from the instrumentation baseline, not stacked.
  4. After each phase, compare the same benchmark set and decide keep or revert.
  5. Only after that should you create a cumulative branch of accepted phases.

  Use Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md:1 as the source
  of truth.

  Master prompt template

  Use Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md as the source of
  truth.

  Execute Phase <N> only.

  Requirements:
  - Do not implement any later phases.
  - Add the RED tests and any required instrumentation for this phase first.
  - Then implement the smallest code change needed for this phase only.
  - Run the exact benchmark and regression commands required for this phase.
  - Compare results against the saved baseline.
  - Append a concise result report to a markdown file in Test-Flight-Improv/Network-Transport-libp2p-Feature/.
  - Report:
    - files changed
    - tests run
    - benchmark before/after
    - whether this phase meets the promotion rule
    - keep or revert recommendation
  - Stop after reporting. Do not continue to the next phase.

  Prompts to paste one at a time

  Baseline:

  Use Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md as the source of
  truth.

  Execute Phase 0 only: freeze the baseline.

  Requirements:
  - Do not change production code.
  - Re-run the current relay recovery baseline and save the results.
  - Record at minimum:
    - C-Sim relay recovery
    - BR-Sim degraded background resume
    - healthy resume
    - S4 reconnect
    - X1 both-sides restart
  - Create or update a markdown results file under Test-Flight-Improv/Network-Transport-libp2p-Feature/ with the
  exact numbers and commands used.
  - Stop after reporting the baseline.

  Instrumentation first:

  Use Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md as the source of
  truth.

  Execute only the instrumentation-first work from section 8.

  Requirements:
  - Add only additive instrumentation and RED tests needed to attribute relay recovery wins.
  - Do not intentionally change relay recovery behavior yet.
  - Run the relevant host tests and the benchmark subset needed to confirm headline metrics remain within the allowed
  range.
  - Update the experiment results markdown with:
    - new fields/events added
    - tests run
    - baseline before/after
    - whether instrumentation was accepted
  - Stop after reporting.

  Phase 1:

  Use Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md as the source of
  truth.

  Execute Phase 1 only: immediate foreground recovery trigger.

  Requirements:
  - Start from the instrumentation baseline, not from a later experiment.
  - Add the RED tests for Phase 1 first.
  - Implement only the minimum code needed to trigger degraded relay refresh immediately on resume.
  - Run the exact benchmark and regression commands for this phase.
  - Compare against the saved baseline and instrumentation baseline.
  - Update the experiment results markdown with before/after numbers and a keep/revert recommendation.
  - Stop after reporting.

  Phase 2:

  Use Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md as the source of
  truth.

  Execute Phase 2 only: relay-state truth and push-driven recovery completion.

  Requirements:
  - Add the RED tests for Phase 2 first.
  - Implement only the minimum code needed for this phase.
  - Do not include Phase 3 or later work.
  - Run the required benchmarks and regressions.
  - Update the experiment results markdown with before/after numbers and a keep/revert recommendation.
  - Stop after reporting.

  Phase 3:

  Use Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md as the source of
  truth.

  Execute Phase 3 only: in-place relay session refresh instead of host restart.

  Requirements:
  - Add the RED tests for Phase 3 first.
  - Implement only the minimum code needed for in-place refresh.
  - Do not include coalescing or deferred-work changes unless strictly required by the tests for this phase.
  - Run the required benchmarks and regressions, especially C-Sim, S4, X1, and X2.
  - Update the experiment results markdown with before/after numbers and a keep/revert recommendation.
  - Stop after reporting.

  Phase 3a:

  Use Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md as the source of
  truth.

  Execute Phase 3a only: direct reservation after warm dial.

  Requirements:
  - Start from the instrumentation baseline, not from a later experiment.
  - Add the RED tests for Phase 3a first.
  - Implement only the minimum code needed to issue direct reservation after successful warm dial and to complete
  recovery from event-driven circuit-address updates when possible.
  - Do not include Phase 4 or later work.
  - Do not add native lifecycle prewarm, QUIC session-ticket persistence, or proactive TTL refresh in this phase.
  - Add or expose the Phase 3a attribution fields if they are still missing:
    - relayWarmMs
    - reserveRpcMs
    - circuitAddressWaitMs
    - reservationPath
    - reservationWinnerPeer
  - Run the required benchmarks and regressions, especially C-Sim, BR-Sim-2, and M-Sim-3.
  - Update the experiment results markdown with before/after numbers, the winning reservation path, and a keep/revert
  recommendation.
  - Stop after reporting.

  Phase 3b:

  Use Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md as the source of
  truth.

  Execute Phase 3b only: foreground AutoRelay cadence and timeout policy.

  Requirements:
  - Start from the instrumentation baseline, not from a later experiment.
  - Add the RED tests for Phase 3b first.
  - Implement only the minimum code needed to test:
    - lower AutoRelay foreground retry cadence
    - parallel relay warm-up during RefreshRelaySession()
    - a shorter foreground resume relay dial timeout
    - preserving the existing long wait only as fallback safety behavior
  - Start with these experiment values unless direct tests prove they are too flaky:
    - autorelay.WithBackoff(1 * time.Second)
    - autorelay.WithMinInterval(1 * time.Second)
    - foreground resume relay dial timeout = 3 * time.Second
  - If those values are too flaky, relax inside this phase to 2s and/or 4s and record the final values used.
  - Do not include Phase 4 or later work.
  - Do not add native lifecycle prewarm, QUIC session-ticket persistence, or proactive TTL refresh in this phase.
  - Add or expose the Phase 3b attribution fields if they are still missing:
    - relayWarmParallelism
    - foregroundRecoveryPath
    - foregroundRelayDialTimeoutMs
    - autorelayRetryCadenceMs
    - circuitAddressWaitMs
  - Run the required benchmarks and regressions, especially C-Sim, BR-Sim-2, and M-Sim-3.
  - Update the experiment results markdown with before/after numbers, the actual cadence/timeout values used, whether
  foreground success beat background fallback, and a keep/revert recommendation.
  - Stop after reporting.

  Phase 4:

  Use Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md as the source of
  truth.

  Execute Phase 4 only: recovery coalescing and storm prevention.

  Requirements:
  - Add the RED tests for Phase 4 first.
  - Implement only the minimum code needed to coalesce overlapping recovery attempts.
  - Run the required repeated-cycle benchmarks and regressions.
  - Update the experiment results markdown with before/after numbers and a keep/revert recommendation.
  - Stop after reporting.

  Phase 5:

  Use Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md as the source of
  truth.

  Execute Phase 5 only: remove noncritical work from the foreground recovery critical path.

  Requirements:
  - Start from the current accepted Phase 3b branch/baseline, not from the old Phase 0 branch state.
  - Add the RED tests for Phase 5 first.
  - Implement only the minimum deferral needed for this phase.
  - Protect against inbox, registration, and group continuity regressions.
  - Run the required benchmarks and regressions for Phase 5.
  - Update the experiment results markdown with:
    - before/after numbers versus the current accepted Phase 3b baseline
    - before/after numbers versus the frozen Phase 0 baseline
    - whether degraded resume improved on top of Phase 3b
    - whether post-resume correctness stayed green
    - keep or revert recommendation
  - Stop after reporting. Do not continue to any other phase.

  Phase 6 optional:

  Use Test-Flight-Improv/Network-Transport-libp2p-Feature/05-relay-recovery-improvement-tdd-plan.md as the source of
  truth.

  Execute Phase 6 only: optional sendable-before-green experiment.

  Requirements:
  - Treat this as a product-policy experiment, not a default merge candidate.
  - Add the RED tests first.
  - Implement only the minimum code needed to measure resume_to_sendable_ms.
  - Run the required benchmarks and regressions.
  - Update the experiment results markdown with before/after numbers and a keep/revert recommendation.
  - Stop after reporting.

  After all phases, use this final prompt

  Compare all recorded relay-recovery experiments from the results markdown and recommend which phases should be
  kept, reverted, or combined.

  Report only:
  - accepted phases
  - rejected phases
  - measured improvement from each accepted phase
  - safest merge order
  - remaining bottleneck if BR-Sim-2 is still above target

  If you want, I can also create a companion 05-relay-recovery-experiment-results.md template so every phase writes
  results into the same file in a consistent format.


====
• Committed and pushed pre-phase1 on Test-Flight-Improv.

  Current baseline:

  - Branch: Test-Flight-Improv
  - Commit: 2647e9fa541026588179d94763983e6648df37bd
  - Remote: origin/Test-Flight-Improv
  - Worktree: clean


==> Rollback Prompt:
Return this repo to the pre-experiment baseline, regardless of which later phase or experiment branch was
  implemented.

  Baseline source of truth:
  - branch: Test-Flight-Improv
  - commit: 70beff450980157ef95a7a6aa089b2c79daf1556
  - commit message: clarify section8 verdict

  Requirements:
  - This must work after any later phase or experiment work, including but not limited to Phase 1, Phase 2, Phase
  3, Phase 3a, Phase 4, or Phase 5.
  - If I am on any experiment branch, switch me away from it safely.
  - If there are uncommitted changes anywhere in the current worktree, show me exactly what would be lost before
  doing anything destructive.
  - Restore the repo to the baseline commit `70beff450980157ef95a7a6aa089b2c79daf1556`.
  - Prefer switching back to `Test-Flight-Improv` if it still points to that baseline.
  - If `Test-Flight-Improv` has moved since that snapshot, create a recovery branch from the baseline commit
  instead of rewriting shared history.
    - Use branch name: `pre-phase-baseline-recovery`
  - Do not keep any later phase changes.
  - After restoring, report:
    - final branch
    - final commit SHA
    - whether it exactly matches the baseline commit
    - git status
  - Stop after reporting.
