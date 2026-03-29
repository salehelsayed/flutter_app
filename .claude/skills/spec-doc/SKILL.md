---
name: spec-doc
description: Generate a specification document for a bug, feature improvement, or new feature — problem statement, impact, current state, scope, and test cases only (no solution)
argument-hint: "[description of bug, improvement, or new feature]"
---

# Specification Document Generator

You are writing a specification document for: **$ARGUMENTS**

This skill produces a **problem + test specification only**. Do NOT propose solutions, implementation plans, code changes, or architecture decisions. Another agent will handle the solution.

## Step 1: Understand the Request

Parse **$ARGUMENTS** to determine:

- **Type**: Is this a `bug`, `feature improvement`, or `new feature`?
- **Area**: Which part of the codebase is affected (e.g., media, messaging, groups, encryption, UI, bridge, relay server)?
- **User intent**: What is the user trying to achieve or what problem are they reporting?

If **$ARGUMENTS** is too vague to produce a meaningful spec, ask the user for clarification before proceeding. Do not guess.

## Step 2: Gather Evidence

Launch an Explore agent (subagent_type: `Explore`, thoroughness: `very thorough`).

Task for the Explore agent:

> You are gathering evidence for a specification document about: **$ARGUMENTS**
>
> Search the codebase for ALL relevant:
> 1. Production code paths in `lib/` — find the exact files, constants, classes, and functions involved
> 2. Go code in `go-mknoon/` and `go-relay-server/` if the area touches P2P, relay, bridge, or native code
> 3. Test files in `test/` and `integration_test/` that cover the affected area
> 4. Related docs in `Test-Flight-Improv/`
> 5. Configuration and constants (size limits, retry counts, timeouts, feature flags)
>
> For each file found, note:
> - File path and line numbers for key constants/logic
> - What the current behavior is
> - What constraints or limits exist
> - How the feature is wired (DI chain, listeners, UI widgets)
>
> Also check:
> - How does data flow through the affected area end-to-end (e.g., UI -> use case -> bridge -> Go -> relay)?
> - What related features or systems interact with this area?
> - Are there existing tests that would need updating?
> - Are there known failures or TODOs in this area?
>
> Return a structured evidence report:
> - **affected files**: path, purpose, key constants/logic with line numbers
> - **data flow**: how the feature works end-to-end today
> - **constraints**: current limits, caps, timeouts, and where they are enforced
> - **interactions**: other features/systems that touch this area
> - **existing tests**: what is covered, what is not
> - **known issues**: TODOs, FIXMEs, known failures in test gates

**WAIT for this agent to fully complete before proceeding.**

## Step 3: Write the Specification Document

Using the evidence from Step 2, write the specification document. The document goes in `Test-Flight-Improv/` and follows the numbering convention of existing docs (check `Test-Flight-Improv/00-INDEX.md` for the next available number).

The document MUST contain ALL of the following sections and NONE of the excluded sections.

### Required Sections

#### 1. Title and Type

Format: `# NN - Title`

Below the title, state the type in bold: **Bug**, **Feature Improvement**, or **New Feature**.

#### 2. Problem Statement

Describe what is broken, missing, or insufficient. Be specific:

- What is the current behavior?
- What is wrong with it or what is missing?
- Who is affected (all users, specific platforms, specific use cases)?
- Under what conditions does the problem manifest?

For bugs: include reproduction steps if known.
For improvements: explain why the current behavior is insufficient.
For new features: explain the gap and why it matters.

#### 3. Impact Analysis

Quantify the impact where possible:

- How severe is this? (blocks usage, degrades experience, cosmetic, etc.)
- How often does it occur? (every time, under specific conditions, rare edge case)
- What is the user-visible consequence?
- Are there workarounds?

Use a table if comparing across scenarios (e.g., different file sizes, different device types, different network conditions).

#### 4. Current State

Document exactly what exists today. This is a factual inventory, not a judgment:

- List the exact files, constants, and code paths involved with file paths and line numbers
- Describe the current data flow end-to-end
- List current limits, constraints, and where they are enforced
- List related features and how they interact with this area

Use tables for structured data (e.g., listing constants across multiple files).

#### 5. Scope Clarification

Define what is in scope and what is not:

- Use a table listing each affected area with its status (in scope, out of scope, unchanged)
- Be explicit about boundaries — what should NOT change
- If there are related areas that might seem in scope but are intentionally excluded, call them out and say why

#### 6. Test Cases

This is the most important section. Write comprehensive, meaningful test cases that:

- Cover **boundary values** (exact limit, limit + 1, limit - 1)
- Cover **normal operation** (typical/happy path with realistic data)
- Cover **error paths** (what happens when things fail — network drop, disk full, timeout)
- Cover **recovery paths** (retry, resume, app restart after failure)
- Cover **interactions** between related features (e.g., compression + size limit, quality setting + upload)
- Cover **regression** scenarios (existing behavior that must NOT break)
- Cover **platform differences** if relevant (iOS vs Android)
- Cover **concurrency** where applicable (multiple uploads, multiple users)

Organize test cases into logical groups with clear headers. Each test case must have:

- A unique ID (e.g., TC-XX-01)
- A concrete scenario description — not vague ("test large file") but specific ("attach a 4K video recorded at 60fps for 2 minutes (~800 MB) in a 1:1 conversation")
- An expected outcome — what should happen, stated unambiguously

Test case quality guidelines:
- Every test should be **falsifiable** — it must be possible for the test to fail
- Every test should be **independent** — it should not depend on another test having run first
- Prefer **realistic data** over synthetic edge cases — use file sizes, durations, and scenarios that real users encounter
- Include tests for the **receiver side**, not just the sender
- Include tests for **state transitions** — what happens when the user changes a setting mid-operation, or switches screens, or the app goes to background
- Include tests for **cleanup** — verify no orphaned files, no leaked resources, no stuck states after failures
- Do NOT write implementation-focused tests (e.g., "verify function X is called with parameter Y") — write behavior-focused tests (e.g., "verify the user sees a progress bar during upload")

### Excluded Sections (DO NOT WRITE)

Do NOT include any of the following. These will be handled by another agent:

- Solution or proposed fix
- Implementation plan or steps
- Code changes (before/after)
- Architecture decisions
- File modifications
- Migration strategy
- Technology choices (e.g., which package to use)

If you find yourself writing "change X to Y" or "update file Z", stop — that belongs in the solution, not the spec.

## Step 4: Review the Document

Before presenting the document, self-review:

1. **Completeness**: Does every claim in the Problem Statement have supporting evidence in Current State?
2. **Accuracy**: Do all file paths and line numbers actually exist in the codebase? (Verify with Grep/Read if uncertain.)
3. **Test coverage**: For every behavior described in the Problem Statement and Impact Analysis, is there at least one test case that would detect whether it is fixed?
4. **No solution leakage**: Does the document contain any "should change to", "update to", "use package X", or similar prescriptive language? Remove it.
5. **Actionability**: Could another engineer (or agent) read this document and know exactly what to test, without needing to re-investigate the codebase?

If any check fails, fix the document before presenting it.

## Step 5: Present to User

Write the document to `Test-Flight-Improv/NN-<slug>.md` where NN is the next available number and the slug is a short kebab-case description.

Then present a brief summary to the user:
- Document type (bug / improvement / new feature)
- File path where it was saved
- Number of test case groups and total test cases
- Any areas where evidence was thin and the user may want to provide more context
