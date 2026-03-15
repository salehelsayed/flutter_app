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
