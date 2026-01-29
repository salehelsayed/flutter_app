# Milestone Orchestration Prompt (XS naming locked, MVP that runs)

Use this prompt when asking a **scrum master / project engineer agent** to **create or revise** milestone orchestration documentation for this repo.

This prompt is designed to prevent the failures observed in M1 (stub/demo outputs, missing bridge runtime, missing JS bundling, manual-only QA) by forcing explicit glue/build/verification tasks and by locking the XS task naming scheme.

---

## Prompt (copy/paste)

```text
You are creating OR revising a milestone orchestration for an EXISTING Flutter + JavaScript (core_lib_js) application with a local SQLite database.

Your output MUST be a set of orchestration docs + XS task files that coding agents can execute to produce a WORKING MVP.

================================================================================
0) HARD CONSTRAINTS (NON‑NEGOTIABLE)
================================================================================

### 0.1 Naming is LOCKED (NO RENAMES, NO RESTRUCTURE)
You MUST follow the existing orchestration structure and XS task naming convention.

- Do NOT rename or move any existing orchestration files.
- Do NOT change task file naming conventions.
- Do NOT renumber existing tasks.
- You may create NEW files ONLY if required for a working MVP and ONLY if they do not already exist.

Task file naming convention (REQUIRED):
- DB_XS_01.md, DB_XS_02.md, ...
- JS_XS_01.md, JS_XS_02.md, ...
- FL_XS_01.md, FL_XS_02.md, ...
- QA_XS_01.md, QA_XS_02.md, ...

Rules for adding NEW tasks:
- If you must add a task, append the next number within that prefix.
- Keep two-digit numbering with leading zero (e.g., 04, 16).
- NEVER renumber existing tasks to “make space”.

### 0.2 Output must be runnable (no stubs / placeholders)
A milestone is DONE only when ALL are true:
1) An end-to-end automated smoke test runs from a clean checkout and prints PASS.
2) The smoke test exercises the same runtime path as production (no simulated bridge, no mocked integrations).
3) The feature produces real data (not demo/test/placeholder) and passes domain validations.
4) All dependencies and build/config steps are explicit (exact package names + versions + exact commands + exact file paths).

If the above cannot be satisfied, you MUST NOT add stub implementations “to make it compile”.
Instead, you must add the missing glue/build/integration tasks needed to make it real.

### 0.3 MVP scope (keep it simple)
- Implement ONE vertical slice (happy path) end-to-end first.
- Only minimal error handling required to prevent crashes/corrupt data.
- No extra architecture, refactors, abstractions, analytics, telemetry, or optional polish unless required for the slice to run.
- Prefer boring, well-supported libraries and the smallest number of moving parts.

================================================================================
1) INPUTS YOU WILL RECEIVE
================================================================================

You will be given some or all of:
- Feature requirements for the milestone
- C4_MODEL.md (baseline architecture + components + file paths)
- A milestone orchestration folder (if this is a revision use case)
- Existing repository structure/codebase context

You MUST treat C4_MODEL.md and the repo codebase as ground truth for what already exists.

================================================================================
2) CHOOSE MODE: REVISION vs CREATION
================================================================================

### Mode A — REVISION (Use case 1)
If the user provides an existing milestone orchestration folder:
- You are revising it (NOT generating from scratch).
- You MUST produce DIFF output only (see Section 8.1).
- You MUST NOT rename/move/delete existing files.
- You may mark tasks as “SKIP/DEPRECATED” inside the file if no longer needed,
  and remove them from execution-order.md, but you must NOT delete the file.

### Mode B — CREATION (Use case 2)
If the user does NOT provide an orchestration folder:
- You are creating a new orchestration folder from scratch,
  but it MUST match the existing M1 structure and XS task naming (Section 3).
- You MUST output full file contents (see Section 8.2).

================================================================================
3) REQUIRED ORCHESTRATION STRUCTURE (LOCKED)
================================================================================

Your orchestration output directory MUST be:

[milestone]-orchestration/
├── README.md
├── GLOBAL_CONTEXT.md
├── execution-order.md
├── file-structure.md
├── verification-checklist.md
└── tasks/
    ├── DB_XS_01.md
    ├── JS_XS_01.md
    ├── FL_XS_01.md
    ├── QA_XS_01.md
    └── ... (more XS tasks as required)

Do NOT introduce alternate folder names, alternate doc names, or different task prefixes.

================================================================================
4) REQUIRED STEP 0 — ARCHITECTURE BASELINE + DELTA (MANDATORY)
================================================================================

You are NOT designing from scratch.

You MUST include these sections at the TOP of GLOBAL_CONTEXT.md:

### 4.1 Baseline Inventory (from C4_MODEL.md + repo)
List, concretely:
- Existing containers and boundaries (Flutter↔JS via WebView channel, Flutter↔DB via sqflite, etc.)
- Existing key components/modules relevant to the feature (include file paths)
- Existing build pipeline and runtime glue already present (if any)
- Existing smoke tests / verification entry points (if any)

### 4.2 Boundary Map (baseline + milestone impact)
List every boundary the milestone touches. For each boundary, state:
- How the request crosses the boundary (protocol, serialization format, entry points)
- What must be verified as a handshake (ping/version) BEFORE feature logic

### 4.3 Delta Plan (delta-only)
Create a small table:
- Change Type: REUSE / MODIFY / ADD
- Component or file path
- Why needed (MVP justification)
- How verified (runnable command or check)

Rules:
- Prefer REUSE, then MODIFY, only ADD when unavoidable.
- If you ADD something, justify why baseline cannot satisfy the requirement.
- Do NOT introduce new architecture patterns or alternate bridges/runtimes unless required for MVP.

================================================================================
5) LESSONS LEARNED (FROM THE ORCHESTRATION GAPS) — ENFORCE THESE
================================================================================

Your orchestration MUST explicitly avoid these known failure modes:

### 5.1 The “Bridge Gap” (interface without runtime)
If Flutter calls JS:
- It is NOT enough to define a Dart interface + TS handlers.
- You MUST include an XS task that implements the real runtime bridge (e.g., WebView-based)
  and a handshake verification that proves Flutter can call JS and get a real response.

### 5.2 The “Bundling Gap” (TS exists but never runs in app)
If JS is written in TS/ESM and must run in WebView:
- You MUST include an XS task that defines the build/bundle pipeline (deps + scripts + polyfills),
  producing a JS bundle placed into the Flutter assets path.

### 5.3 The “Fake Output” gap (verification checks shape only)
Verification must include REALNESS checks:
- Example: mnemonic must validate (BIP39 checksum, word count)
- Example: peerId format checks
- Example: deterministic restore: generate → restore → same peerId

### 5.4 Manual QA is not enough
You may include QA_XS manual test scripts, BUT you MUST ALSO include
at least one automated runnable smoke test task (QA_XS_*).
The smoke test is the milestone gate.

================================================================================
6) MICRO-TASK “OVERLAY” RULE (CHAINED CONNECTION BETWEEN TASKS)
================================================================================

When splitting work into XS tasks, each task must clearly connect to the previous ones.

For EVERY XS task, you MUST explicitly define:
- What upstream task outputs it consumes (files created, schemas, message formats, build artifacts)
- The exact input/output shapes it expects/produces
- Which downstream tasks will consume its outputs

Examples:
- If saving identity to DB: define schema/table first (DB_XS), then helpers (DB_XS),
  then repository mapping (FL_XS), then use case (FL_XS), then UI wiring (FL_XS),
  then automated smoke test (QA_XS).
- If JS creates identity: define IdentityJson type first (JS_XS), then generate/restore funcs (JS_XS),
  then bridge handlers/router (JS_XS), then bundling/build (JS_XS), then Flutter runtime bridge (FL_XS),
  then Flutter bridge client helper calls (FL_XS), then use case (FL_XS), etc.

The goal: tasks are independently executable, but never ambiguous about how the system connects end-to-end.

================================================================================
7) TASK FILE TEMPLATE (MUST MATCH XS STYLE)
================================================================================

Every tasks/<ID>.md MUST follow this structure (do NOT invent a new format):

------------------------------------------------------------
# Task Prompt: <ID> - <Title>

## Instructions for AI Agent
You are implementing a specific task for a Flutter/JS application.
Follow the task specification exactly. Output complete, working code/docs that can be directly used.

---

## Global Context
```text
Milestone: <Mx – Name>

(Include ONLY the minimum shared context needed to complete this task:
- relevant schemas
- relevant request/response contracts
- relevant type shapes
- relevant file paths)
```

---

## Task Definition
```
[TASK <ID> – <Title>]

Owner: <DB | JS | Flutter | QA>

Goal:
  <One paragraph maximum>

Prerequisites:
  - Requires: <UPSTREAM_TASK_ID> complete and VERIFIED
  - Requires output: <artifact path> exists / <command> ran successfully

What to implement:
  - <bullet list with exact file paths and exact symbols/functions>
  - <include HOW the task connects to upstream outputs>

Inputs:
  - <types/shapes/constraints>
Outputs:
  - <types/shapes/constraints>
  - <include EXACT output format that downstream tasks will consume>

Flow_events:
  - <start/success/error events with example details>
  (If not applicable, say “None”.)

Constraints:
  - <keep short; include “NO stubs/placeholder” when relevant>
  - <state what NOT to do>

Deliverable:
  - <exact file paths created/modified>
```

---

## Output Requirements
1) File path(s): <exact>
2) Output type: <Dart code | TypeScript code | Markdown doc>
3) If code: output the COMPLETE file content unless the task explicitly says “partial”.
4) Include runnable verification steps if applicable.

---

## Begin Implementation
Output the complete implementation now.

------------------------------------------------------------

================================================================================
8) REQUIRED VERIFICATION (QUALITY + RUNNABLE)
================================================================================

### 8.0 Per-task verification is mandatory
Every XS task MUST include “Verification” details either in Output Requirements or Task Definition.
Verification must be runnable where applicable, not just “file exists”.

### 8.1 Automated smoke test (MANDATORY)
You MUST include at least one QA_XS_* task that creates an automated smoke test entrypoint:
- File: lib/smoke_test_<feature>.dart (or similar)
- Run: flutter run -t lib/smoke_test_<feature>.dart
- Must exercise the real runtime boundary (Flutter↔JS and/or Flutter↔DB).
- Must validate output SHAPE + REALNESS.
- Must fail loudly (exit non-zero / throw) if stub/demo/placeholder detected.

Smoke test must include stub detection:
- Fail if output contains: “demo”, “placeholder”, “fake”, “TODO”, “simulate”, “stub”.

### 8.2 End-to-end integration verification task (REQUIRED when crossing boundaries)
If the milestone crosses Flutter↔JS:
- Include a task that verifies handshake (e.g., core.ping → pong) over the REAL runtime
  BEFORE identity logic is considered done.

================================================================================
9) REQUIRED CONTENT FOR execution-order.md, file-structure.md, verification-checklist.md
================================================================================

### execution-order.md
- Provide phases and explicit dependencies.
- Dependencies must reference OUTPUT artifacts, not just “task completed”.

### file-structure.md
- Map every XS task to the exact code/doc file(s) it modifies/creates.
- If a file is “partial” across multiple tasks, explicitly explain merge order.

### verification-checklist.md
- Include checks per task:
  - signature/shape checks
  - realness checks (domain validation)
  - boundary checks (bridge handshake, JS bundle exists in assets, DB persistence)
- Include the final smoke test run command and PASS criteria.

================================================================================
10) OUTPUT FORMAT REQUIREMENTS (STRICT)
================================================================================

### 10.1 If Mode A (REVISION): Output DIFF ONLY
Return ONLY:
1) Change Summary (files changed + files added)
2) Unified diffs for each changed/added file:
   - Modified file:
     --- a/<path>
     +++ b/<path>
   - New file:
     --- /dev/null
     +++ b/<path>

DO NOT output a regenerated folder.
DO NOT output renamed paths.
DO NOT delete files (mark SKIP/DEPRECATED instead).

### 10.2 If Mode B (CREATION): Output FULL FILES
Output the complete set of files with exact paths, like:
- FILE: [milestone]-orchestration/README.md
  <full content>
- FILE: [milestone]-orchestration/GLOBAL_CONTEXT.md
  <full content>
...
- FILE: [milestone]-orchestration/tasks/FL_XS_01.md
  <full content>

================================================================================
11) FINAL CHECKLIST (GATE)
================================================================================

Before you finalize:
- [ ] XS naming preserved; no renames; no renumbering
- [ ] Baseline Inventory + Delta Plan included in GLOBAL_CONTEXT.md
- [ ] Every boundary has explicit glue/build/verification tasks (no “bridge gap”)
- [ ] JS bundling/build is explicit if JS must run in WebView (no “bundling gap”)
- [ ] Automated smoke test exists and validates REAL output (no “fake output” gap)
- [ ] execution-order/file-structure/verification-checklist updated consistently

Deliver the orchestration docs accordingly.
```