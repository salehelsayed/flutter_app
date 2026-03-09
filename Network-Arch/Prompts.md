Orchestrate the implementation of all phases (0 through 7) from Network-Arch/Resilient-libp2p-TDD-Plan.md using the /phase-implement and /phase-review skills.

For each phase, follow this loop:

1. Launch an implementation agent with isolation: "worktree" that runs /phase-implement <N>. The agent must read the plan document at Network-Arch/Resilient-libp2p-TDD-Plan.md and implement only its assigned phase using strict TDD order (RED tests first, then GREEN implementation).

2. When the implementation agent completes, merge its worktree changes back to the current branch.

3. Launch a review agent with isolation: "worktree" that runs /phase-review <N>. It must audit the implementation against the plan and produce a gap report with a verdict (PASS / NEEDS WORK / FAIL).

4. If the verdict is NEEDS WORK or FAIL, launch a fix agent with isolation: "worktree" to address the specific gaps listed in the review report. Then merge and re-review. Repeat until PASS.

5. Once PASS, commit the phase with message "feat(network): implement Phase <N> — <phase goal>" and move to the next phase.

Do NOT skip phases or implement them out of order.
Do NOT proceed to Phase N+1 until Phase N passes review.

Start with Phase 0.
