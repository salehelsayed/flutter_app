# UI-21-POST Orchestration Prompt

Use this prompt as a thin wrapper around `$libp2p-phase-orchestrator` for the
Posts plan.

```text
Use $libp2p-phase-orchestrator for this phase.

Plan path:
- UI-21-POST/Plan-Phases.md

Allowed phase targets:
- Phase 0 assumptions lock
- Phase 1: Direct-Friend Posts MVP
- Phase 2: Comments, Reactions, Media, and Expiry
- Phase 3: People Nearby and Privacy
- Phase 4: Pass Along and Extended-Network Delivery
- Phase 5: Pinned Posts and Lifecycle Controls
- Final Hardening Gate

Posts-specific rules:
- Run one controller session per requested phase.
- Do not start the next phase automatically.
- Treat Phase 0 as a non-production contract-lock phase.
- Use the phase-specific skills listed inside UI-21-POST/Plan-Phases.md.
- Keep all orchestration scoped to UI-21-POST/Plan-Phases.md.
- Use these commit message formats after acceptance:
  - Phase 0: docs(posts): lock Phase 0 assumptions
  - Phase 1-5: feat(posts): implement Phase <N> - <phase goal>
  - Final Hardening Gate: test(posts): final hardening gate

Start with the requested phase only.
```



  Resume the chained Posts run.

  Continue Phase 2 only:
  - UI-21-POST/Plan-Phases.md
  - Active phase: Phase 2: Comments, Reactions, Media, and Expiry

  Current state:
  - Phase 1 is accepted and committed as 7f4de99
  - Phase 2 contract is already extracted
  - Slice 1 is the active entry point

  Resume from Phase 2 Slice 1 and continue the chained controller workflow.
  Keep strict RED -> GREEN -> REFACTOR.
  Do not revisit accepted Phase 1 work except for minimal compatibility fixes required by Phase 2.
  Do not enter Phase 3 unless Phase 2 is accepted.

  Stop only if:
  - Phase 2 is accepted and then automatically continue to Phase 3 as the next controller session, or
  - Phase 2 becomes blocked.

  Report:
  - Active slice
  - RED evidence
  - files changed
  - verification run
  - acceptance decision
  - next state

  If you want to be even more forceful because it stalled, prepend this line:

  Your previous controller run stalled after opening Phase 2. Resume from that point; do not restart from Phase 1


  ====


    Continue the chained run on UI-21-POST/Plan-Phases.md.

  Stay in Phase 4 and continue without pausing between the remaining slices:
  - Slice 1: pass contract, original snapshot shape, and trust validation
  - Slice 2: sender pass flow and explicit one-hop rule
  - Slice 3: receiver ingest, local dedupe, and feed rendering
  - Slice 4: original-author share counts and related UI states

  Rules:
  - strict RED -> GREEN -> REFACTOR
  - keep Phase 4 scoped to pass-along only
  - do not reopen accepted Phase 3 work except for minimal compatibility fixes required by Phase 4
  - do not enter Phase 5 unless Phase 4 is accepted
  - stop only if Phase 4 becomes blocked or Phase 4 reaches accepted

  Phase 4 contract reminders:
  - one explicit extra hop only
  - no mutual-friends badge
  - pass payload must stay fully renderable without network reconstruction
  - trust validation must reject sender mismatch and unknown passing-friend cases

  Verification:
  - use slice-scoped verification during implementation
  - rerun the full Phase 4 acceptance matrix before Phase 4 acceptance

  At Phase 4 completion, report:
  - Acceptance decision
  - Gap ledger
  - verification commands run
  - files changed
  - commit hash and commit message

  If Phase 4 is accepted, automatically open the next controller session for Phase 5.

=====================================================================================================================================================================
  Continue the chained run on UI-21-POST/Plan-Phases.md.

  Stay in Phase 5 and continue without pausing between the remaining slices:
  - Slice 1: pin router contract, schema, and persistence
  - Slice 2: sender pin, edit, and remove flows
  - Slice 3: receiver pinned section, dismiss, and restart restore
  - Slice 4: collapsed-header details, active-pins banner, and `Message [name]` action

  Rules:
  - strict RED -> GREEN -> REFACTOR
  - keep Phase 5 scoped to pinned posts and lifecycle controls only
  - do not reopen accepted Phases 1-4 except for minimal compatibility fixes required by Phase 5
  - do not enter Final Hardening Gate unless Phase 5 is accepted
  - stop only if Phase 5 becomes blocked or Phase 5 reaches accepted

  Phase 5 contract reminders:
  - reuse the generic orphan child-event staging path from Phase 2
  - `post_pin_update` and `post_pin_remove` are the only pin transport events in v1
  - receiver dismiss is local-only
  - pinned posts still appear in the normal feed during the initial 24-hour window
  - implement the collapsed header, active-pins compose banner, and `Message [name]` action as part of this phase

  Verification:
  - use slice-scoped verification during implementation
  - rerun the full Phase 5 acceptance matrix before Phase 5 acceptance

  At Phase 5 completion, report:
  - Acceptance decision
  - Gap ledger
  - verification commands run
  - files changed
  - commit hash and commit message

  If Phase 5 is accepted, automatically open the next controller session for Final Hardening Gate.