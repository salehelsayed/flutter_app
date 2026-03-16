# UI-21-POST Orchestration Prompt

Use this prompt as a thin wrapper around `$libp2p-phase-orchestrator` for the
Posts plan.

```text
Use $libp2p-phase-orchestrator for this phase.

Plan path:
- UI-21-POST/3.1-Post-improv-Plan.md

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
- Use the phase-specific skills listed inside UI-21-POST/3.1-Post-improv-Plan.md.
- Keep all orchestration scoped to UI-21-POST/3.1-Post-improv-Plan.md.
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

  ========================================
  Use $libp2p-phase-orchestrator in auto-advance mode.

  Plan path:
  - UI-21-POST/3.1-Post-improv-Plan.md

  Controller mode:
  - auto-advance

  Start phase:
  - Phase 1: Split local creation from delivery execution

  Allowed phase sequence:
  - Phase 1: Split local creation from delivery execution
  - Phase 2: Introduce `PostDeliveryRunner` with serial in-session behavior
  - Phase 3: Make text-only Posts dismiss optimistically
  - Phase 4: Add bounded parallel fanout for text-only Posts
  - Phase 5: Extend optimistic background delivery to media posts
  - Phase 6: Add Posts retry and reconnect recovery
  - Phase 7a: Migrate engagement fanout
  - Phase 7b: Migrate post pin fanout
  - Phase 7c: Migrate pass-along carefully
  - Phase 7d: Migrate presence update fanout

  Stop condition:
  - Stop when a phase is blocked or when Phase 7d is accepted.
  - Do not auto-start Phase 8. It is optional and should run only if I explicitly request it after
  Phase 7d.

  Agent orchestration rules:
  - Spawn a separate implementer/dev agent for each phase.
  - Spawn a separate reviewer/QA agent for each phase.
  - Never let the implementer review its own phase.
  - If review finds blocking gaps, spawn a separate fix agent for that same phase, or a fresh
  implementer-context fix agent, but do not reuse the reviewer as the fixer.
  - After a phase is accepted, discard or close the phase-local implementer, reviewer, and fixer
  agents before advancing.
  - Start the next phase with fresh agents so context does not accumulate across phases.

  Phase control rules:
  - Run one controller session per phase, but auto-advance after acceptance.
  - Treat UI-21-POST/3.1-Post-improv-Plan.md as the authoritative phase contract.
  - For production phases, require strict `RED -> GREEN -> REFACTOR` and capture the exact failing
  tests or commands before production edits.
  - If QA returns `PASS` and the phase is accepted, move to the next phase automatically.
  - If QA returns `NEEDS WORK` or `FAIL`, run the fix loop for that same phase and review again
  before any advancement.
  - Do not widen scope into later phases unless required for compilation.
  - Follow the plan's locked decisions, non-goals, guardrails, success criteria, TDD strategy, and
  definition of done.
  - Record residual risks, explicit deferrals, and next-phase prerequisites before advancing.
  - Rebuild each next phase contract from the plan instead of carrying hidden assumptions forward.

  Posts-specific architecture rules:
  - Keep Posts separate from Group Messages in architecture and code ownership.
  - Do not extract a chat-first shared peer-delivery helper before Posts phases are complete.
  - If a small reusable helper is needed before Phase 8, it must be Posts-owned, transport-scoped,
  and must not change chat semantics.
  - Do not migrate Posts onto the current group-chat transport.
  - Preserve the current Posts wire contract and recipient-set semantics unless the active phase
  explicitly changes them.
  - Keep `sendPost(...)` usable as a synchronous compatibility facade until the plan explicitly
  allows otherwise.
  - Do not introduce chat repository or chat entity writes into the Posts path.
  - Do not change Posts envelope schemas in the early phases.
  - Do not use unbounded fanout concurrency.
  - Do not hide delivery failures by dropping local posts.
  - Keep follow-on Post events fire-and-forget until their specific Phase 7 slice.
  - Limit Phase 6 retry scope to post-create recipient deliveries only.

  Phase-specific execution reminders:
  - Phase 1 must establish the explicit local-create boundary and preserve synchronous
  `sendPost(...)` compatibility.
  - Phase 2 must introduce `PostDeliveryRunner` with serial in-session behavior, incremental
  aggregate status updates, and explicit internal error finalization.
  - Phase 3 must include optimistic composer dismiss, inline `sending` / `partial` / `failed` feed
  UI, disabled follow-on actions while `deliveryStatus == 'sending'`, coalesced `PostsWired` refresh
  behavior, and reconciliation of lingering `sending` posts when the Posts surface opens.
  - Phase 4 must add bounded parallel fanout with lazy envelope building and an injectable
  concurrency limit.
  - Phase 5 must implement the media two-stage optimistic flow and explicit upload-placeholder
  behavior so media-only optimistic posts are never visually blank.
  - Phase 6 must add a Posts-owned retry and reconnect recovery service using the app lifecycle
  wiring pattern used for `PendingMessageRetrier`, without expanding into follow-on event retry.
  - Phase 7a through Phase 7d must migrate only the named follow-on event family for the active
  slice and preserve each slice's current recipient semantics and special-case constraints.

  Commit rule after acceptance, if a commit is requested:
  - feat(posts): implement <accepted phase label>

  Begin with Phase 1 only, then auto-advance according to the rules above.
  =========================================


  Use $libp2p-phase-orchestrator in auto-advance mode.

  Plan path:
  - UI-21-POST/3.2-Post-reliability-and-follow-on-TDD.md

  Controller mode:
  - auto-advance

  Start phase:
  - Phase 1: Reproduce And Lock The Pin-Remove Regression

  Allowed phase sequence:
  - Phase 1: Reproduce And Lock The Pin-Remove Regression
  - Phase 2: Add A Durable Outgoing Follow-On Outbox
  - Phase 3: Put Pin Update And Pin Remove On The Durable Outbox
  - Phase 4: Move Comments, Reactions, And Comment Reactions Onto The New Path
  - Phase 5: Move Repost/Pass-Along Onto The New Path
  - Phase 6: Persist Outgoing Media Upload Recovery State
  - Phase 7: Add A Media Upload Retrier And Handoff To Post-Create Retry

  Stop condition:
  - Stop when a phase is blocked or when Phase 7 is accepted.
  - Do not start any work beyond Phase 7 unless I explicitly request it in a later session.
  - Do not reopen completed 3.1 phases except for the smallest compatibility fix required by the
  active 3.2 phase.

  Agent orchestration rules:
  - Spawn a separate implementer/dev agent for each phase.
  - Spawn a separate reviewer/QA agent for each phase.
  - Never let the implementer review its own phase.
  - If review finds blocking gaps, spawn a separate fix agent for that same phase, or a fresh
  implementer-context fix agent, but do not reuse the reviewer as the fixer.
  - After a phase is accepted, discard or close the phase-local implementer, reviewer, and fixer
  agents before advancing.
  - Start the next phase with fresh agents so context does not accumulate across phases.

  Phase control rules:
  - Run one controller session per phase, but auto-advance after acceptance.
  - Treat UI-21-POST/3.2-Post-reliability-and-follow-on-TDD.md as the authoritative active phase-
  scoped implementation doc.
  - Treat UI-21-POST/3.1-Post-improv-Plan.md as accepted baseline context, not the active phase
  contract.
  - For production phases, require strict `RED -> GREEN -> REFACTOR` and capture the exact failing
  tests or commands before production edits.
  - If QA returns `PASS` and the phase is accepted, move to the next phase automatically.
  - If QA returns `NEEDS WORK` or `FAIL`, run the fix loop for that same phase and review again
  before any advancement.
  - Do not widen scope into later phases unless required for compilation.
  - Follow the 3.2 plan's locked decisions, non-goals, verification matrix, test inventory,
  suggested file touch order, and exit gates.
  - Record residual risks, explicit deferrals, and next-phase prerequisites before advancing.
  - Rebuild each next phase contract from the 3.2 plan instead of carrying hidden assumptions
  forward.

  Posts reliability architecture rules:
  - Do not reuse `PostPendingChildEvent` for outgoing retry.
  - Add one Posts-owned outgoing follow-on outbox with per-event and per-recipient state.
  - Add one Posts-owned outgoing media-upload recovery contract keyed by post and media position.
  - Keep post-create retry separate from follow-on retry, but allow media-recovery completion to
  hand off into the existing post-create delivery runner.
  - Do not extract a cross-feature shared helper in this plan.
  - Include comments, reactions, comment reactions, repost/pass-along, pin update, and pin remove in
  the durable follow-on architecture.
  - Keep nearby presence out of scope for this TDD unless the active phase needs a minimal
  compatibility fix. Presence is not the blocking reliability target in this plan.
  - A sender-side pin remove must not silently report success when recipients have not converged.
  - Follow-on sends must evolve beyond `bool deliveredAny`; the sender path must distinguish fully
  settled, partially settled, and not settled.
  - Optimistic media posts must survive app kill between local creation, media preparation, media
  upload, and recipient fanout.
  - A media post must never become a permanent dead-end skeleton just because the app restarted
  before upload completed.
  - Do not redesign Posts UX in this plan.
  - Do not change chat semantics or extract a cross-feature helper in this plan.

  Phase-specific execution reminders:
  - Phase 1 must reproduce the current pin-remove regression through a real sender -> router ->
  listener -> recipient-state path, make `PostsWired` inspect `RemovePinResult`, and lock one
  temporary sender behavior so failed remove is not silently accepted.
  - Phase 2 must add the durable outgoing follow-on outbox, persist per-event and per-recipient
  sender-side state, and change the follow-on delivery helper to return structured per-recipient and
  aggregate outcomes instead of one boolean.
  - Phase 3 must move `pinPost()`, `editPinnedPost()`, and `removePin()` onto the durable outbox,
  queue before delivery, retry unresolved recipients, and make sender-side result handling explicit
  in `PostsWired`.
  - Phase 4 must move comments, reactions, and comment reactions onto the durable path, persist sender-local state before delivery completes, keep recipient-set resolution semantics unchanged, and preserve comment-expiry refresh
  behavior.
  - Phase 5 must move repost/pass-along onto the durable path while preserving explicit recipient set plus original-author notification, `pickPeople` rejection, one-hop limit checks, and renderable media snapshot validation.
  - Phase 6 must persist restart-safe outgoing media upload recovery state, preserve media order, and stop relying on in-memory `mediaDrafts` for restart recovery.
  - Phase 7 must add a media upload retrier or explicit upload-first stage, wire it beside the current Posts retrier in `lib/main.dart`, make startup and resume catch-up explicit, and hand successful resumed uploads back into the
  existing post-create delivery path.

  Verification reminders:
  - Use the 3.2 plan's per-phase verification matrix as the minimum targeted command set.
  - Before final acceptance of the plan, run the broader regression commands listed in the 3.2 plan's "Broader regression before merge" section.

  Commit rule after acceptance, if a commit is requested:
  - feat(posts): implement <accepted phase label>

  Begin with Phase 1 only, then auto-advance according to the rules above.







   I just added @GoogleService-Info.plist pin












  ==============================================

  Use $libp2p-phase-orchestrator in auto-advance mode.

  Plan path:
  - UI-21-POST/3.3-Pin-improv.md

  Controller mode:
  - auto-advance

  Start phase:
  - Phase 1: Reproduce Serial Pin Latency

  Allowed phase sequence:
  - Phase 1: Reproduce Serial Pin Latency
  - Phase 2: Raise Pin Fanout Concurrency To 25
  - Phase 3: Guard Correctness Under Higher Parallelism

  Stop condition:
  - Stop when a phase is blocked or when Phase 3 is accepted.
  - Do not start any work beyond Phase 3 unless I explicitly request it in a later session.

  Agent orchestration rules:
  - Spawn a separate implementer/dev agent for each phase.
  - Spawn a separate reviewer/QA agent for each phase.
  - Never let the implementer review its own phase.
  - If review finds blocking gaps, spawn a separate fix agent for that same phase, or a fresh
  implementer-context fix agent, but do not reuse the reviewer as the fixer.
  - After a phase is accepted, discard or close the phase-local implementer, reviewer, and fixer
  agents before advancing.
  - Start the next phase with fresh agents so context does not accumulate across phases.

  Phase control rules:
  - Run one controller session per phase, but auto-advance after acceptance.
  - Treat UI-21-POST/3.3-Pin-improv.md as the authoritative active phase-scoped implementation doc.
  - For production phases, require strict `RED -> GREEN -> REFACTOR` and capture the exact failing
  tests or commands before production edits.
  - If QA returns `PASS` and the phase is accepted, move to the next phase automatically.
  - If QA returns `NEEDS WORK` or `FAIL`, run the fix loop for that same phase and review again
  before any advancement.
  - Do not widen scope into later phases unless required for compilation.
  - Follow the 3.3 plan's locked decisions, scope, verification matrix, suggested file touch order,
  risks, and exit gates.
  - Record residual risks, explicit deferrals, and next-phase prerequisites before advancing.
  - Rebuild each next phase contract from the 3.3 plan instead of carrying hidden assumptions
  forward.

  Pin execution rules:
  - Raise the default pin fanout concurrency to 25.
  - Keep the current pin-specific durable outbox architecture intact.
  - Do not change the sender-visible settlement model in this plan.
  - Do not change generic follow-on concurrency in this plan.
  - Do not change stale-event ordering semantics in this plan.
  - Do not widen scope into inbox-settlement semantics or non-pin follow-ons in this plan.

  Phase-specific execution reminders:
  - Phase 1 must reproduce the current serialized pin latency and lock the one-at-a-time behavior
  before changing it.
  - Phase 2 must raise pin follow-on bounded concurrency to 25 for both initial send and retry while
  preserving bounded fanout and outbox persistence semantics.
  - Phase 3 must prove higher parallelism does not break stale remove protection, partial settlement
  handling, queued-for-retry behavior, or real recipient-state convergence.

  Verification reminders:
  - Use the 3.3 plan's per-phase verification matrix as the minimum targeted command set.
  - Before final acceptance of the plan, run the broader regression commands listed in the 3.3
  plan's broader regression section.

  Commit rule after acceptance, if a commit is requested:
  - feat(posts): implement <accepted phase label>

  Begin with Phase 1 only, then auto-advance according to the rules above.


  ======================


  • Use $libp2p-phase-orchestrator in auto-advance mode.

  Plan path:
  - UI-21-POST/3.4-Comment-improv.md

  Controller mode:
  - auto-advance

  Start phase:
  - Phase 1: Reproduce The Receiver Comments Sheet Gap

  Allowed phase sequence:
  - Phase 1: Reproduce The Receiver Comments Sheet Gap
  - Phase 2: Make The Open Comments Sheet Live
  - Phase 3: Raise Post-Create Fanout Concurrency To 25
  - Phase 4: Raise Comment Fanout Concurrency To 25
  - Phase 5: Guard Correctness And UX Regressions

  Stop condition:
  - Stop when a phase is blocked or when Phase 5 is accepted.
  - Do not start any work beyond Phase 5 unless I explicitly request it in a later session.

  Agent orchestration rules:
  - Spawn a separate implementer/dev agent for each phase.
  - Spawn a separate reviewer/QA agent for each phase.
  - Never let the implementer review its own phase.
  - If review finds blocking gaps, spawn a separate fix agent for that same phase, or a fresh implementer-context fix agent, but do not reuse the reviewer as the fixer.
  - After a phase is accepted, discard or close the phase-local implementer, reviewer, and fixer agents before advancing.
  - Start the next phase with fresh agents so context does not accumulate across phases.

  Phase control rules:
  - Run one controller session per phase, but auto-advance after acceptance.
  - Treat UI-21-POST/3.4-Comment-improv.md as the authoritative active phase-scoped implementation doc.
  - For production phases, require strict `RED -> GREEN -> REFACTOR` and capture the exact failing tests or commands before production edits.
  - If QA returns `PASS` and the phase is accepted, move to the next phase automatically.
  - If QA returns `NEEDS WORK` or `FAIL`, run the fix loop for that same phase and review again before any advancement.
  - Do not widen scope into later phases unless required for compilation.
  - Follow the 3.4 plan's locked decisions, non-goals, verification matrix, suggested file touch order, risks, and exit gates.
  - Record residual risks, explicit deferrals, and next-phase prerequisites before advancing.
  - Rebuild each next phase contract from the 3.4 plan instead of carrying hidden assumptions forward.

  Comment execution rules:
  - Fix the receiver comment freshness gap by making the open comments sheet refresh from Posts-owned persisted state, not from a raw transport subscription.
  - Keep `PostCommentListener` as the transport and persistence boundary.
  - Raise post-create bounded fanout concurrency from 4 to 25.
  - Raise comment bounded fanout concurrency from 4 to 25.
  - Do not silently widen reaction, comment-reaction, or pass-along concurrency in this plan unless the active phase requires it and the change is explicitly tested.
  - Do not change whether `deliveryStatus == 'inbox'` counts as settled in this plan.
  - Do not redesign the Comments UI in this plan.

  Phase-specific execution reminders:
  - Phase 1 must reproduce the stale open-comments-sheet behavior and prove the gap is isolated to the open sheet rather than the persisted comment state.
  - Phase 2 must make the open comments sheet live-update from persisted state while preserving optimistic local submit behavior and duplicate protection.
  - Phase 3 must raise post-create bounded concurrency to 25 while preserving delivery-state aggregation and retry behavior.
  - Phase 4 must raise comment bounded concurrency to 25 while keeping comment-specific behavior isolated and preserving sender-local persistence plus expiry refresh.
  - Phase 5 must guard ordering, dedupe, orphan reconciliation, expiry refresh, and open-sheet UX against regressions.

  Verification reminders:
  - Use the 3.4 plan's per-phase verification matrix as the minimum targeted command set.
  - Before final acceptance of the plan, run the broader regression commands listed in the 3.4 plan's broader regression section.

  Commit rule after acceptance, if a commit is requested:
  - feat(posts): implement <accepted phase label>

  Begin with Phase 1 only, then auto-advance according to the rules above.