# Plan 247 Session 01 — Accept The Private-Route Product And Privacy Contract

Status: accepted
Source: `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-breakdown.md` Session 01
Run mode: documentation-only evidence closure
Migration owner: none

## Problem And Evidence

Plan 247 could not safely expose a cross-lane action while its label, sender authority, copied context, and exceptional-state behavior had no accepted answers. The Wave-1 authority supplied a conservative navigation-only contract: **Message sender**, existing active/unblocked contact only, blank direct composer, minimum local qualification request, and fail-closed stale-state handling.

Current source verifies the inputs named by that contract exist: `GroupMessage` carries `groupId`, `senderPeerId`, `isIncoming`, and media relationships; `GroupModel` distinguishes announcement groups and durable dissolved state; `ContactModel` carries `isArchived` and `isBlocked`; `ContactRepository.getContact` provides a current nullable lookup; and `GroupMessageRepository` exposes both current-message and local-deletion-tombstone reads. Session 01 does not implement or test those seams.

## Scope Contract And Guard

In scope:

- Create `Test-Flight-Improv/247-private-reply-decision.md` with `Status: accepted` and literal D-247-01..04 answers.
- Persist exact EN/DE/AR action, unavailable, and route-failure copy.
- Persist the all-required eligibility matrix, dispatch-time revalidation, blank-composer/minimum-request boundary, and zero-send/no-cross-lane contract.
- Reclassify the source Plan 247 from evidence-gated to implementation-in-progress with Session 02 executable.
- Mark Session 01 accepted and Session 02 executable in the session breakdown.

Out of scope:

- Any production, test, localization resource, generated output, gate script, database, Bridge, Go, relay, or native edit.
- Creating the request/policy types, UI action, opener, or route.
- Running Flutter, Go, device, curated, family, or full-host gates. No executable behavior changed.
- Proceeding to Session 02.

Hard guards:

- Do not claim Plan 247 is feature-complete or user-visible after this session.
- Do not relax announcement publishing, contact authority, media lifecycle/protection, or viewer capability checks.
- Do not turn **Message sender** into Reply, Forward, Report, an introduction flow, or automatic delivery.
- Preserve the pre-existing dirty worktree and edit only the four Plan-247 documentation artifacts owned by this session.

## Accepted Decision Contract

| Decision | Result |
|---|---|
| D-247-01 | **Message sender**; EN `Message sender`, DE `Absender anschreiben`, AR `مراسلة المرسل`; no reply/quote implication. |
| D-247-02 | Current existing contact only, active and unblocked, non-self incoming source, complete opener; no auto-add/introduction/unarchive/unblock. |
| D-247-03 | Existing fully wired 1:1 route with blank composer; local non-serializable request contains only `sourceMessageId` and `senderPeerId`; no source context crosses lanes. |
| D-247-04 | Hide or fail closed for every stale/ineligible row; dismiss stale transient UI and show privacy-minimized unavailable copy; distinguish eligible route-open failure. |

The complete matrix, exact localized copy, invocation ordering, and change-control boundary live in `Test-Flight-Improv/247-private-reply-decision.md` and are authoritative for later sessions.

## Documentation Proof Contract

| Proof | Exact evidence | Required result |
|---|---|---|
| Accepted artifact | non-empty decision file plus exact `Status: accepted` | pass |
| Decision completeness | D-247-01, D-247-02, D-247-03, and D-247-04 each present | pass |
| Decision hygiene | no decision-placeholder vocabulary in the accepted artifact | pass |
| Source synchronization | source status/classification, accepted decision section, first Done Criterion, handoff, and execution progress reflect Session 01 | pass |
| Breakdown synchronization | Session 01 accepted and Session 02 execution-ready; later dependencies unchanged | pass |
| Scope | scoped diff contains documentation only; no production/test file is Session-01-owned | pass |
| Markdown hygiene | scoped tracked diff and explicit whitespace scan are clean | pass |

## Acceptance Checks

```bash
test -s Test-Flight-Improv/247-private-reply-decision.md
rg -x 'Status: accepted' Test-Flight-Improv/247-private-reply-decision.md
for id in D-247-01 D-247-02 D-247-03 D-247-04; do rg -q "$id" Test-Flight-Improv/247-private-reply-decision.md; done
! rg -n 'TBD|TO DECIDE|unresolved|pending approval' Test-Flight-Improv/247-private-reply-decision.md

rg -n '^Status: implementation-in-progress$|^Classification: implementation-ready$' Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan.md
rg -n '^Status: implementation-in-progress$|\| 01 .*\| accepted \||\| 02 .*\| execution-ready \|' Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-breakdown.md
! rg -n 'D-247-[0-9]+.*(TBD|TO DECIDE|unresolved|pending approval)' Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan.md Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-breakdown.md

git diff --check -- Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan.md
rg -n '[[:blank:]]+$' Test-Flight-Improv/247-private-reply-decision.md Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-01-plan.md Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-breakdown.md
git status --short -- Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan.md Test-Flight-Improv/247-private-reply-decision.md Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-01-plan.md Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-breakdown.md
```

The trailing-whitespace `rg` command is expected to return exit 1 with no output. No Flutter or Go command is a Session-01 acceptance gate.

## Evidence And Self-Review

- The architecture graph was current but returned `confidence=broad` for the Plan-247 document anchor; no graph-only relationship was used as proof. Exact model/repository facts were verified in current source before accepting the artifact.
- The initial worktree was already heavily dirty from concurrent Plan-234 and other Wave-1 work. The four scoped Plan-247 documents were the only Session-01 edit targets; no reset, checkout, formatting sweep, commit, or unrelated cleanup was performed.
- Counterexample review confirmed the accepted artifact denies self/outgoing, unknown/archived/blocked, missing/changed/deleted/tombstoned, non-announcement/unavailable membership, text-only/wrong-owner media, missing-opener, and route-failure cases.
- Privacy review confirmed the request allowlist has exactly two local identifiers, no serializer, blank composer, no copied source content, privacy-minimized stale feedback, and zero send/upload/Forward/transport operation.
- Closure review keeps the source at implementation-in-progress. The feature remains absent until Sessions 02–03 implement and verify it; Session 04 owns aggregate acceptance and stable index/audit updates.

## Done Criteria

- [x] The accepted artifact exists and records complete D-247-01..04 answers.
- [x] Exact EN/DE/AR action and failure copy is persisted.
- [x] Eligibility, denial, revalidation, blank-composer, and no-cross-lane boundaries are explicit and mutually consistent.
- [x] The source plan has no stale D-247 decision blocker and points to Session 02.
- [x] The breakdown marks Session 01 accepted and Session 02 execution-ready without advancing Session 03/04.
- [x] No production code or test was edited for Session 01.
- [x] Exact documentation checks and a stale-placeholder/overclaim self-review pass.

## Execution Progress

| Time | Phase | Files / commands | Result | Next |
|---|---|---|---|---|
| 2026-07-11 | evidence collection | Graphify TDD query; current group/contact model and repository anchors; source plan and breakdown | graph context current but broad; load-bearing facts verified in source | persist accepted contract |
| 2026-07-11 | documentation execution | decision artifact, source plan, session plan, breakdown | D-247-01..04 and exact localized/privacy contract synchronized; no code/test edit | run documentation gates and self-review |
| 2026-07-11 | final verdict | exact acceptance checks; scoped hygiene; stale-placeholder and overclaim audit | accepted | stop; Session 02 is the next executable unit |

## Final Execution Verdict

`accepted`

Session 01 is complete as a documentation-only evidence closure. It makes no user-visible feature claim, changes no executable surface, and creates no commit. Session 02 may now implement the minimum request, pure eligibility policy, and dispatch-time revalidation.
