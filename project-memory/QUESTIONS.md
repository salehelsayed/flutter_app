# Project-Memory Seed Questions (v1)

Purpose: the questions-first step of the project-memory design. These 30
questions are drawn from REAL repository history — each one was, at some
point, re-derived from scratch, answered wrongly from stale context, or
required a raw sweep of the plan corpus. The ontology below is derived from
them, not invented upfront. They double as the A/B evaluation set: score
`Claude + repo search` vs `Claude + memory recall` on correctness/staleness,
tool calls, documents opened, tokens, and time.

Gold answers reflect state as of 2026-08-17 (branch `protected-view`).
Answers marked (verify) should be re-confirmed from the cited source at
extraction time. Provenance shorthand: `TFI` = Test-Flight-Improv.

## A. Plan status & supersession
The single biggest staleness risk: treating a planning artifact as landed
work, or landed work as still open.

1. Is plan 377 (fresh-group strict-authority send lockout) executed or
   planning-only? — CLOSED at device tier in `65f816276` (2026-08-17):
   bricked group healed live, fresh-group first send OK. [TFI/377, memory]
2. What is the status of plans 263–267 (group-exit reliability)? — 263–266
   EXECUTED and accepted 2026-07-20/21 (263: 1bb3c1c95; 264: f0a5d2777);
   267 Wave 0 only, production `not-ready`. Root cause (B3 retained shell)
   confirmed. [plan Status headers; GOLD CORRECTED 08-17 — memory was stale]
3. Is plan 302 (remove one-more-look budget for protected media) executed?
   — EXECUTED: implemented-verified, host-green 2026-07-29; engine/SQL
   stayed zero-diff. [TFI/302 Status; GOLD CORRECTED 08-17]
4. Is plan 303 (view-once minimal presentation) landed? — COMPLETED
   2026-07-30 (8b6154bf7/277c5596e); info-unreachable for view-once images
   is shipped accepted behavior. [TFI/303 Status; GOLD CORRECTED 08-17]
5. What happened to plan 259's private-media copy edits? — COMMITTED
   2026-07-19 (checkpoint 2be07626e, ancestor of HEAD); gates/QA still
   unproven (empty execution table). [TFI/259 + git; GOLD CORRECTED 08-17]
6. Which plan closed the state-guard campaign-red problem, and what was the
   root cause? — plan 317 CLOSED; tar member-ORDER after dir re-creation
   (canonical digest fix). [memory: state-guard-verify-order-instability]
7. What superseded the "host-all is not runnable from the container"
   limitation? — SUPERSEDED: Go installed + node reporter pinned; it aborts
   before Go tails on a red Flutter batch. [memory: host-all-not-runnable]
8. Is `test/unit` still invisible to per-plan gates? — SUPERSEDED:
   core-host-all globs `test/unit/**` now; curated lanes remain blind.
   [memory: test-unit-invisible-to-per-plan-gates]

## B. Refuted findings (do NOT re-introduce)
Highest-value category: each of these was expensively refuted and keeps
being re-derived as a "fix" or "bug".

9. Is "write a genesis authority proof at plain creation" a valid fix for
   the fresh-group send lockout? — REFUTED twice: with both selectors
   compiled off, a settled proof flips the refusal to
   `strict_group_content_not_qualified` — same false-removal UI. [TFI/377]
10. Is the multi-device group-push divergence (transportPeerId vs
    accountPeerId) a real bug? — No; structurally impossible in shipped
    builds; repeatedly re-derived from the message-vs-reaction recipient
    asymmetry. [memory: transport-peer-id-equals-account-peer-id]
11. Was the group self-reaction empty nomination (`[]`) a defect? — No;
    H1/H3 refuted, it is by design. The real defects were author-missing
    permanent empty wake, Go silent false-'stored', zero relay
    observability. [memory: group-reaction wake findings, plan 315]
12. Did skia cache churn cause the state-guard campaign reds? — REFUTED
    (as was the exclusion fix); see Q6. [memory]
13. Is narrowing the disappearing-message application predicate to match
    the storage predicate safe? — No; DELIBERATE asymmetry — narrowing
    leaks the private secure key (proven by reverse mutation). [memory]
14. Was the "pending contact requests invisible in E2E builds" behavior the
    171 bug? — No; E2E/sims builds suppress incoming-request UI by design;
    the invisibility is a product gap, not the bug. [memory]

## C. Constraints, flags & rationale
15. Why do post-344 clients require
    `DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED=true`? — Without it every
    offline send silently dies (metric-only signal); flipped 2026-08-16.
    [memory: custody-admission-flag]
16. Which linked-device features are compiled out of shipped builds, and
    what does that make unreachable? — `kDirectLinkedDevicesEnabled` /
    `kMultiDeviceSyncEnabled` off; QR device-link (the only
    authority-writing entry point) is unreachable. [TFI/377]
17. Why is the private-media failure copy reassuring and sender-attributed
    rather than technical? — recorded tone decision; offline text UX
    deliberately unchanged. [memory: private-media-copy-tone]
18. Why must `avoid_print`/`file_names` analyzer suppressions stay, and why
    is `dart fix --apply` forbidden? — suppressed by design; `--apply`
    breaks final-field constructors. [memory: analyzer-clean-policy]
19. Why does the relay ACL govern delete-ack, and what does a wrong ACL
    leak? — wrong ACL leaks blobs to TTL; Android bg delete task is a
    no-op (critical-task work is iOS-provable only). [memory]
20. Which relay version is live and which is burned? — v1.8.0 live
    (2026-08-16 notification/custody wave deploy); v1.7.0 burned (rolled-
    back plan-309 binary). PRODUCTION box only, no staging relay.
    [main.go const + TFI/376 + 00-INDEX; GOLD CORRECTED 08-17]

## D. Proof & evidence requirements
21. What proof is required before claiming a phone deploy succeeded? —
    stamped `versionName 1.0.0-<sha>[.dN].t<stamp>` + the deploy script's
    post-install verify; unread FAILED lines mean the phone kept the old
    build. [memory: phone-build-provenance-guard]
22. Why did plan 377 require a device-tier closure that host tests cannot
    substitute? — the production resolver composition (bootstrap closure
    ~:8327) is unexported; only the device build exercises it. [TFI/377]
23. What is the pinned device pair for group/Android device proofs? —
    physical Pixel 6 `21071FDF600CSC` + emulator `emulator-5554`. [TFI/377]
24. What must never be run against a stamped release install on a phone? —
    `flutter test -d <phone>`: the debug install uninstalls the stamped
    build, the state guard fail-closes and discards evidence. [memory]
25. Which host-all failures are pre-existing baggage rather than
    regressions? — 13 perf reds + 9 `test/integration` reds predate the
    receipt plans; the 6 concurrency-only reds are FIXED (`f1165a010`).
    [memory: host-all reds]

## E. Deferred items & ownership
26. Who owns the linked-surface silent-drop
    (`linked_group_conversation_wired` collapses results to bool)? —
    linked-device UX follow-up; unreachable in shipped builds (flags off).
    [TFI/377 Deferred]
27. What was deferred from plan 377's remove-reaction lane, and to which
    wave? — strict-lane-only `notMember` sites `:171/:255/:285/:310` →
    multi-device wave. [TFI/377]
28. Where is the persisted terminal-failure-reason gap tracked? — future
    plan; plan 376's typed-refusal C2/C4 is the template; needs a schema
    change (`group_message.dart` has no reason column). [TFI/377 Deferred]
29. Which standing program owns the next aggregate `host-all` run? — the
    36x–37x notification wave; per-plan gates must not run one. [TFI/377]

## F. Process policies (institutional landmines)
30. Why must `/workspace` never be stashed, and what is the alternative? —
    concurrent sessions edit the live checkout; use `git worktree` for HEAD
    comparisons. [memory: workspace-live-checkout-no-stash]

Reserve set (swap in if any gold answer above churns): why lane runs forbid
tree mutation mid-run; the `--plain-name` substring trap; why host-run
scripts must be bash-3.2-safe; why `GROUP_TESTS` registration needs grep
gates; why DTR-18 digests must be re-pinned rather than weakened.

## Derived ontology (from the questions above, nothing more)

ENTITY TYPES (8):
  PLAN         (Q1-8, 22, 26-29)   — has status, closure tier, commit
  FINDING      (Q9-14)             — refuted/confirmed claims w/ rationale
  CONSTRAINT   (Q15-16, 19-20)     — flags, env vars, ACLs, compiled-out
  DECISION     (Q13, 17-18)        — recorded rationale, tone/policy
  PROOF        (Q21-25)            — evidence requirements, device pins
  GAP          (Q25, 28)           — open items with owners
  POLICY       (Q24, 30, reserve)  — process rules / landmines
  GATE         (Q8, 25, 29)        — lanes, sweeps, frozen digests

RELATION TYPES (10):
  supersedes, refutes, addresses, depends_on, constrained_by,
  verified_by, deferred_to, owned_by, part_of, governs

STATUS VOCABULARY:
  proposed | execution-ready | executed | closed | superseded |
  refuted | deferred | open | accepted-difference

REQUIRED FIELDS ON EVERY FACT:
  status, source_doc, source_commit, date

## Notes for extraction
- Categories A, E and much of D parse DETERMINISTICALLY from plan headers
  (`Status:`), `## Reviewer Findings`, `Deferred / accepted difference`
  (owner lines), and Device/Relay Proof sections — no LLM needed.
- Category B maps to the plans' "Refuted findings (do NOT re-introduce)"
  sections — also deterministic.
- Categories C and F live partly in Claude's session memory
  (`/claude-home/.claude/projects/-workspace/memory/`), which is
  account-scoped; migrating those facts into project-memory is what makes
  them visible to subagents, workflows, and Codex.
