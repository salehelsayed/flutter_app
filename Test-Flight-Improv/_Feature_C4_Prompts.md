# C4-First Prompt
Orchestrate 4 agents to create sepearate C4model files under @Test-Flight-Improv/Group-Chat-Feature/ only for the group message "Discussion" Feature . I want you to create 5 dedicated C4 model files, one per action, each covering all 4 C4 levels in a focused, standalone document



# C4-Second Prompt (On each produced file)
I provided you with that prompt in the previous session: (Orchestrate 4 agents to create sepearate C4model files under @Test-Flight-Improv/Group-Chat-Feature/ only for the group message "Discussion" Feature . I want you to create 5 dedicated C4 model files, one per action, each covering all 4 C4 levels in a focused, standalone document ). Your task is to review Test-Flight-Improv/Group-Chat-Feature/C4-01-Create-Discussion.md  document as QA and make sure that it is accureate and reflect the codebase. this will be the source of truth. orchestrate as many agents as you want and make sure you verify the findings from the agents before you produce the report and don't change the structure


I provided you with that prompt in the previous session: (Orchestrate 4 agents to create sepearate C4model files under @Test-Flight-Improv/Group-Chat-Feature/ only for the group message "Discussion" Feature . I want you to create 5 dedicated C4 model files, one per action, each covering all 4 C4 levels in a focused, standalone document ). Your task is to review Test-Flight-Improv/Group-Chat-Feature/C4-02-Send-Message.md  document as QA and make sure that it is accureate and reflect the codebase. this will be the source of truth. orchestrate as many agents as you want and make sure you verify the findings from the agents you produce the report and don't change the structure

I provided you with that prompt in the previous session: (Orchestrate 4 agents to create sepearate C4model files under @Test-Flight-Improv/Group-Chat-Feature/ only for the group message "Discussion" Feature . I want you to create 5 dedicated C4 model files, one per action, each covering all 4 C4 levels in a focused, standalone document ). Your task is to review Test-Flight-Improv/Group-Chat-Feature/C4-03-Receive-Message.md  document as QA and make sure that it is accureate and reflect the codebase. this will be the source of truth. orchestrate as many agents as you want and make sure you verify the findings from the agents before you produce the report and don't change the structure


I provided you with that prompt in the previous session: (Orchestrate 4 agents to create sepearate C4model files under @Test-Flight-Improv/Group-Chat-Feature/ only for the group message "Discussion" Feature . I want you to create 5 dedicated C4 model files, one per action, each covering all 4 C4 levels in a focused, standalone document ). Your task is to review Test-Flight-Improv/Group-Chat-Feature/C4-04-Invite-And-Join.md document as QA and make sure that it is accureate and reflect the codebase. this will be the source of truth. orchestrate as many agents as you want and make sure you verify the findings from the agents before you produce the report and don't change the structure


I provided you with that prompt in the previous session: (Orchestrate 4 agents to create sepearate C4model files under @Test-Flight-Improv/Group-Chat-Feature/ only for the group message "Discussion" Feature . I want you to create 5 dedicated C4 model files, one per action, each covering all 4 C4 levels in a focused, standalone document ). Your task is to review Test-Flight-Improv/Group-Chat-Feature/C4-05-Recovery-And-Reliability.md document as QA and make sure that it is accureate and reflect the codebase. this will be the source of truth. orchestrate as many agents as you want and make sure you verify the findings from the agents before you produce the report and don't change the structure





# Test-First Prompt
I currently have the @Test-Flight-Improv/Intro-Feature/c1-system-context.md @Test-Flight-Improv/Intro-Feature/c2-container.md @Test-Flight-Improv/Intro-Feature/c3-component.md and @Test-Flight-Improv/Intro-Feature/c4-code.md for the Intro feature. I want to have a documemnt that collects all the tests we currently have in the codebase so I know what do we cover and what not.write a document that shows each test category and what we have for this feature under the @Test-Flight-Improv/Intro-Feature/



# Implementation Prompt
  Use a stronger one that forces continuation and makes early partial stops invalid:

  
  For the matrix decomposition:

Use $test-matrix-row-decomposer on /Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md. Treat it as an implementation-committed gap-closure rollout and refresh the adjacent row-by-row session breakdown.

  For the session pipeline:

Use $implementation-session-pipeline-orchestrator on Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md . Treat it as an implementation-committed gap-closure rollout. Keep strict fresh-child isolation and continuation-controller chaining; do not use degraded local continuation unless strict child execution truly no-progresses.





Use $implementation-session-pipeline-orchestrator on `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`.

Treat this as an implementation-committed gap-closure rollout. Reuse the existing breakdown and continue the full session pipeline until the breakdown reaches a persisted final doc verdict. Do not stop after the first accepted session, the first generated plan, a ledger update, or a “next runnable session” summary.

If fresh-child continuation no-progresses again, explicitly enter degraded local continuation mode and keep processing the remaining sessions locally under the same row-owned closure bar. Persist progress after each session and continue until every session is resolved as `accepted`, `stale/already- covered`, `evidence-gated`, or `prerequisite-blocked`, and the breakdown records the final program/doc verdict.

Do not weaken acceptance: no row-owned session may finish `accepted` while its source row remains `Open`, `Partial`, or `Contract-undefined`. Update the source matrix to `Closed`, `Covered`, or `Unsupported` only with concrete evidence. Keep unsupported, repo-external, and prerequisite-blocked rows explicit rather than inventing feature work or silently skipping them.




Prompt 1: refresh the same breakdown so the
  remaining rows become real in-scope work

Use $test-matrix-row-decomposer on `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`.

Refresh the existing adjacent breakdown at:
  `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`

Treat this as an implementation-committed gap-closure rollout. The remaining unresolved rows are now in scope for implementation.

Rows that must now be reconsidered as active in-scope work:

  Evidence-gated:
  - `CB-006`
  - `CB-007`
  - `RC-009`
  - `RC-010`
  - `MD-004`
  - `SV-010`
  - `UX-009`
  - `SV-011`

  Prerequisite-blocked:
  - `RY-013`
  - `RY-014`
  - `RY-015`
  - `RY-016`
  - `SV-004`
  - `SV-005`
  - `SV-006`
  - `SV-007`
  - `SV-012`

Do not leave repo-owned missing prerequisites as vague blockers. Where several rows share one missing repo-owned capability or harness, create explicit shared prerequisite sessions plus the row-owned dependent sessions. In particular, create executable prerequisite work for:
  1. encrypted, membership-aware group offline replay across Flutter, `go-mknoon/node`, and `go-relay-server`
  2. tamper / replay / wrong-key / wrong-nonce / key-rotation proof harnesses
  3. dispatcher overflow observability and proof

Keep exact row traceability. Keep only truly repo-external or device-lab-only proof rows as evidence-gated or blocked. Rewrite the same `*-session-breakdown.md` artifact so it is ready for `$implementation-session-pipeline-orchestrator`.

  Prompt 2: after Prompt 1 finishes, run the pipeline
  on that refreshed breakdown

Use $implementation-session-pipeline-orchestrator on `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`.

Treat this as an implementation-committed gap-closure rollout. Execute the refreshed breakdown to a persisted final verdict. Do not stop after partial progress. If fresh-child continuation no-progresses again, explicitly enter degraded local continuation mode and keep going



--

Use $implementation-session-pipeline-orchestrator on `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`.

Continue from the current persisted ledger. Do not stop just because `PREREQ-GROUP-OFFLINE-REPLAY` is blocked. Keep processing later independent runnable sessions, starting with `PREREQ-GROUP-PROOF-HARNESS`, then continue in ledger order.

Stay in implementation-committed gap-closure mode. If fresh-child continuation no-progresses again, remain in degraded local continuation mode and keep going. Only stop when no later independent runnable sessions remain or a real blocker prevents further safe progress.









Use $implementation-session-pipeline-orchestrator on
  `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`.

Treat this as an implementation-committed gap- closure rollout, and finish all remaining repo-owned work in this same breakdown, including the current blockers.

Before doing anything else:
  1. run the required ledger sanity check
  2. reconcile any inconsistency between the controller summary and the session ledger
  3. continue from the true next runnable session

Do not stop just because `PREREQ-GROUP-OFFLINE-REPLAY` is currently marked blocked.

For this run, `PREREQ-GROUP-OFFLINE-REPLAY` and `PREREQ-GROUP-DISPATCHER-OVERFLOW` are both in scope. The goal is to implement the blocker work, then continue through all dependent row-owned sessions.

Requirements:
- work on `PREREQ-GROUP-OFFLINE-REPLAY` across Flutter, `go-mknoon/node`, and `go-relay-server`
- work on `PREREQ-GROUP-DISPATCHER-OVERFLOW`
- then continue with dependent rows `RY-013`, `RY-014`, `RY-015`, `RY-016`, `RC-010`, and `SV-012`
- keep using this same `*-session-breakdown.md` artifact as the source of truth

If `PREREQ-GROUP-OFFLINE-REPLAY` is blocked only because the current session contract is too broad, do not leave it as a broad blocked seam. Tighten it into the smallest safe executable contract, and if needed split it inside the same breakdown artifact into smaller prerequisite sessions with doc-scoped plan files, then continue execution.

If fresh-child continuation no-progresses again, explicitly remain in degraded local continuation mode and keep going.

  Do not stop after partial progress, one accepted prerequisite, or a “next runnable session” summary.
  Stop only when:
  - the breakdown reaches a persisted final verdict, or
  - a true external blocker remains after exhausting all repo-owned implementation and replanning options

Update the source matrix, test inventory, plans, and breakdown only with concrete code/test evidence.


# Local Testing
Use $implementation-session-pipeline-orchestrator on `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`.   Keep the main thread thin. Spawn fresh child agents for each row/session, and use multiple child agents in parallel when sessions are independent and have disjoint ownership.

Run all repo tests plus all available group/recovery/relay integration/E2E tests against the local `go-relay-server`, and execute the remaining simulator proof for `MD-004` and the local-relay /simulator exploratory proof for `UX-009`.

Do not stop on the first failure. Keep going until everything is green. If any issue appears, fix whatever is necessary in the codebase, tests, plans, or matrix-aligned proof so the full local-relay test and simulator run becomes green.

Stop only when:
  1. all repo-owned tests and available E2E/simulator proof are green, or
  2. a true non-repo blocker remains after exhausting repo-owned fixes.
If green, update the matrix, inventory, and breakdown with the final evidence and close any rows now proven.






================
# Update go-relay-server on EC2 then run 
================

Use $implementation-session-pipeline-orchestrator on
  `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`.

Keep the main thread thin. Spawn fresh child agents for each row/session or failing area, and use multiple child agents in parallel when work is independent and ownership is disjoint. 

With the newly deployed `go-relay-server` on EC2, rerun every test and verification lane we have in this repo against the deployed relay: the full Flutter test suite, full `go-mknoon` test suite, full `go-relay-server` test suite, and all repo-owned group/recovery/relay integration, simulator,smoke, soak, and E2E runs

Do not stop on the first failure. Keep spawning/fixing through child agents until everything is green. If anything fails, fix whatever is necessary in code, tests, plans, or matrix-aligned proof, and update deployed-relay evidence only when the full deployed run is green.

Stop only when:
  1. all repo-owned tests and available E2E/deployed-relay proof are green, or
  2. a true non-repo blocker remains after exhausting repo-owned fixes.

If green, update the matrix, inventory, and breakdown with the final deployed-relay evidence. Reopen rows only if the deployed run exposes a real regression.




=======
  Use $implementation-execution-qa-orchestrator to execute the plan at Test-Flight-Improv/Intro-Feature/intro-split-brain-silent-repair-fix-plan.md.

  Treat that markdown file as the execution contract. Do not replan from scratch.

  Scope:
  - keep the fix on the receiver-side `pending + own side accepted -> mutualAccepted` intro repair seam
  - do not widen into `alreadyConnected`, intro-only harness work, smoke work, or protocol redesign
  - do not reuse `resolve_unknown_inbox_sender_use_case.dart` verbatim
  - keep the heavy intro-repair logic in a focused helper/use case
  - keep intro refresh ownership on `IntroductionListener`, with `main.dart` only used for wiring if needed

  Land the seam coherently in one pass across:
  - lib/features/contact_request/application/handle_incoming_message_use_case.dart
  - lib/features/contact_request/application/contact_request_listener.dart
  - lib/features/contact_request/application/recover_intro_contact_request_use_case.dart
  - lib/features/introduction/application/introduction_listener.dart
  - lib/features/introduction/application/handle_mutual_acceptance_use_case.dart
  - lib/features/contact_request/application/resolve_contact_request_notification_target_use_case.dart
  - lib/features/orbit/presentation/screens/orbit_wired.dart
  - lib/features/feed/presentation/screens/feed_wired.dart
  - any directly required tests

  Add the RED tests named in the plan first, then implement the fix.

  Required direct tests:
  - test/features/contact_request/application/handle_incoming_message_use_case_test.dart
  - test/features/contact_request/application/contact_request_listener_test.dart
  - test/features/contact_request/application/recover_intro_contact_request_use_case_test.dart
  - test/features/contact_request/application/resolve_contact_request_notification_target_use_case_test.dart
  - test/features/contact_request/integration/contact_request_flow_test.dart
  - test/features/orbit/presentation/screens/orbit_wired_test.dart
  - test/features/feed/presentation/screens/feed_wired_test.dart

  Required named gate:
  - ./scripts/run_test_gates.sh intro

  Only run these if touched:
  - test/integration/contact_request_notification_dedupe_integration_test.dart
  - test/features/introduction/application/resolve_unknown_inbox_sender_use_case_test.dart
  - cd go-relay-server && go test ./...  (only if Go code changes)

  At the end, report:
  - changed files
  - tests/gates run
  - QA findings and whether a fix loop was needed
  - whether the plan’s done criteria were met


  ===
Run $implementation-doc-rollout-orchestrator on /Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Intro-Feature/intro-introducer-status-feedback.md and carry it through decomposition plus full session-pipeline completion until the doc reaches a persisted final verdict.

