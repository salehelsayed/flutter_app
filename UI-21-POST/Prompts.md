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

  =====

  Use $libp2p-phase-orchestrator in auto-advance mode.

  Plan path:
  - UI-21-POST/3.5-Repost-improv.md

  Controller mode:
  - auto-advance

  Start phase:
  - Phase 1: Reproduce Repost Sender Latency And Receiver Muting

  Allowed phase sequence:
  - Phase 1: Reproduce Repost Sender Latency And Receiver Muting
  - Phase 2: Split Local Repost Persistence From Background Delivery
  - Phase 3: Make Receiver-Targeted Reposts Visibly Surface Existing Posts
  - Phase 4: Raise Repost Fanout Concurrency To 25
  - Phase 5: Guard Repost Correctness, Retry, And Feed Semantics

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
  - Treat UI-21-POST/3.5-Repost-improv.md as the authoritative active phase-scoped implementation doc.
  - For production phases, require strict `RED -> GREEN -> REFACTOR` and capture the exact failing tests or commands before production edits.
  - If QA returns `PASS` and the phase is accepted, move to the next phase automatically.
  - If QA returns `NEEDS WORK` or `FAIL`, run the fix loop for that same phase and review again before any advancement.
  - Do not widen scope into later phases unless required for compilation.
  - Follow the 3.5 plan's locked decisions, non-goals, verification matrix, suggested file touch order, risks, and exit gates.
  - Record residual risks, explicit deferrals, and next-phase prerequisites before advancing.
  - Rebuild each next phase contract from the 3.5 plan instead of carrying hidden assumptions forward.

  Repost execution rules:
  - Move repost/pass-along onto the same delivery/retry stack used by `post_create`.
  - Reuse `PostDeliveryRunner`, `post_recipients`, aggregate delivery status, and `PendingPostDeliveryRetrier` where the runner can be extended safely.
  - Mirror the current local-first Posts pattern:
    - create-local repost step persists the pass and the recipient-delivery state needed by the reused runner path
    - deliver-created repost step performs network fanout afterward through the reused post delivery runner stack
  - Keep one-hop limit, `pickPeople` rejection, explicit-recipient selection, original-author notification, and renderable snapshot validation intact.
  - If the sender tries to select the original author explicitly, filter that author out of the explicit repost audience:
    - the author may still receive the implicit author-notification copy
    - that copy must not count as an explicit repost recipient
  - When a repost arrives for a receiver who already has the original post:
    - do not create a duplicate post row
    - do update persisted surfacing so the pass is visible on the existing card
    - prefer persisted pass attribution plus repost-time resurfacing over a transport-only transient signal
  - When a direct author copy later arrives for a post that already exists locally as a reposted copy:
    - merge by `postId`
    - do not create a duplicate card
    - prefer the direct author relationship for stored sender/origin semantics while preserving any relevant pass history needed for repost surfacing
  - Preserve the existing rule that share counts remain an author-only metric unless the smallest viable implementation absolutely requires revisiting that.
  - Reuse the post-create runner's bounded concurrency of 25 for repost initial send and retry.
  - Do not silently widen comment, reaction, comment-reaction, or pin concurrency in this plan.
  - Do not redefine whether `deliveryStatus == 'inbox'` counts as settled in this plan.
  - Do not widen into repost media/avatar/encryption or repost engagement continuity work from 3.6 unless the active 3.5 phase needs the smallest compatibility fix.
  - Do not widen into repost visual metric/color work from 3.7 unless the active 3.5 phase needs the smallest compatibility fix.

  Phase-specific execution reminders:
  - Phase 1 must reproduce the sender-side blocking repost sheet and the muted receiver-existing- post surfacing gap before changing production code.
  - Phase 2 must split local repost persistence from background delivery so sender UX mirrors the current local-first comment architecture, and the pass sheet closes after local queueing rather than after network settlement.
  - Phase 3 must make receiver-targeted reposts visibly resurface existing posts from durable state without creating duplicate cards, and must keep later direct-copy merge duplicate-free.
  - Phase 4 must raise repost initial-send and retry fanout concurrency to 25 through the reused post-create runner stack while keeping non-repost follow-on defaults unchanged.
  - Phase 5 must prove repost UX changes do not break durable retry, one-hop safety, explicit-recipient plus author-notification behavior, renderable snapshot validation, author-exclusion from explicit selection, or idempotency.

  Verification reminders:
  - Use the 3.5 plan's per-phase verification matrix as the minimum targeted command set.
  - Before final acceptance of the plan, run the broader regression commands listed in the 3.5 plan's broader regression section.

  Commit rule after acceptance, if a commit is requested:
  - feat(posts): implement <accepted phase label>

  Begin with Phase 1 only, then auto-advance according to the rules above.


  ===
  Use $libp2p-phase-orchestrator in auto-advance mode.

  Plan path:
  - UI-21-POST/3.5-Repost-improv.md

  Controller mode:
  - auto-advance

  Start phase:
  - Phase 4: Raise Repost Fanout Concurrency To 25

  Allowed phase sequence:
  - Phase 4: Raise Repost Fanout Concurrency To 25
  - Phase 5: Guard Repost Correctness, Retry, And Feed Semantics

  Stop condition:
  - Stop when a phase is blocked or when Phase 5 is accepted.
  - Do not start any work beyond Phase 5 unless I explicitly request it in a later session.

  Accepted phase context:
  - Phase 1 accepted
  - Phase 2 accepted
  - Phase 3 accepted
  - Resume from Phase 4 only

  Agent orchestration rules:
  - Spawn a separate implementer/dev agent for each phase.
  - Spawn a separate reviewer/QA agent for each phase.
  - Never let the implementer review its own phase.
  - If review finds blocking gaps, spawn a separate fix agent for that same phase, or a fresh implementer-context fix agent, but do not reuse the reviewer as the fixer.
  - After a phase is accepted, discard or close the phase-local implementer, reviewer, and fixer agents before advancing.
  - Start the next phase with fresh agents so context does not accumulate across phases.

  Phase control rules:
  - Run one controller session per phase, but auto-advance after acceptance.
  - Treat UI-21-POST/3.5-Repost-improv.md as the authoritative active phase-scoped implementation doc.
  - Treat the plan's `Required Skills By Phase` section as binding for implementer and reviewer setup.
  - For production phases, require strict `RED -> GREEN -> REFACTOR` and capture the exact failing tests or commands before production edits.
  - If QA returns `PASS` and the phase is accepted, move to the next phase automatically.
  - If QA returns `NEEDS WORK` or `FAIL`, run the fix loop for that same phase and review again before any advancement.
  - Do not widen scope into later phases unless required for compilation.
  - Follow the 3.5 plan's locked decisions, non-goals, verification matrix, suggested file touch order, risks, and exit gates.
  - Record residual risks, explicit deferrals, and next-phase prerequisites before advancing.
  - Rebuild each next phase contract from the 3.5 plan instead of carrying hidden assumptions forward.

  Reviewer fallback rule:
  - If a reviewer/QA agent fails twice to return a usable `PASS` / `NEEDS WORK` / `FAIL` verdict, treat that as a review-orchestration failure, not an implementation failure.
  - In that case, perform a manual controller review in the main session against the active phase contract and issue exactly one verdict: `PASS`, `NEEDS WORK`, or `FAIL`.
  - Do not advance without a verdict.

  Repost execution rules:
  - Move repost/pass-along onto the same delivery/retry stack used by `post_create`.
  - Reuse `PostDeliveryRunner`, `post_recipients`, aggregate delivery status, and
  `PendingPostDeliveryRetrier` where the runner can be extended safely.
  - Reuse the post-create runner's bounded concurrency of 25 for repost initial send and retry.
  - Do not silently widen comment, reaction, comment-reaction, or pin concurrency in this plan.
  - Do not redefine whether `deliveryStatus == 'inbox'` counts as settled in this plan.
  - Do not widen into 3.6 or 3.7 except for the smallest compatibility fix required by the active 3.5 phase.

  Phase-specific execution reminders:
  - Phase 4 must raise repost initial-send and retry fanout concurrency to 25 through the reused post-create runner stack while keeping non-repost follow-on defaults unchanged.
  - Phase 5 must prove repost UX changes do not break durable retry, one-hop safety, explicit-recipient plus author-notification behavior, renderable snapshot validation, author-exclusion from explicit selection, or idempotency.

  Verification reminders:
  - Use the 3.5 plan's per-phase verification matrix as the minimum targeted command set.
  - Before final acceptance of the plan, run the broader regression commands listed in the 3.5 plan's broader regression section.

  Commit rule after acceptance, if a commit is requested:
  - feat(posts): implement <accepted phase label>

  Begin with Phase 4 only, then auto-advance according to the rules above.


===========================================================================



Use $libp2p-phase-orchestrator in auto-advance mode.

  Plan path:
  - UI-21-POST/3.6-Repost-media-improv.md

  Controller mode:
  - auto-advance

  Start phase:
  - Phase 1: Reproduce Repost Fidelity And Security Gaps

  Allowed phase sequence:
  - Phase 1: Reproduce Repost Fidelity And Security Gaps
  - Phase 2: Encrypt Repost Payloads End To End
  - Phase 3: Persist Repost Engagement Participants And Historical Engagement Baselines
  - Phase 4: Make Reposted Media Independently Retrievable And Blob-Encrypted At Rest
  - Phase 5: Make Original-Author Avatars Self-Renderable Inside Encrypted Reposts
  - Phase 6: Guard Retry, Idempotency, Security Compatibility, And Shared-Thread Continuity

  Stop condition:
  - Stop when a phase is blocked or when Phase 6 is accepted.
  - Do not start any work beyond Phase 6 unless I explicitly request it in a later session.

  Accepted phase context:
  - No 3.6 phases are accepted yet.
  - Resume from Phase 1 only.

  Agent orchestration rules:
  - Spawn a separate implementer/dev agent for each phase.
  - Spawn a separate reviewer/QA agent for each phase.
  - Never let the implementer review its own phase.
  - If review finds blocking gaps, spawn a separate fix agent for that same phase, or a fresh implementer-context fix agent, but do not reuse the reviewer as the fixer.
  - After a phase is accepted, discard or close the phase-local implementer, reviewer, and fixer agents before advancing.
  - Start the next phase with fresh agents so context does not accumulate across phases.

  Phase control rules:
  - Run one controller session per phase, but auto-advance after acceptance.
  - Treat UI-21-POST/3.6-Repost-media-improv.md as the authoritative active phase-scoped implementation doc.
  - Treat the plan's `Required Skills By Phase` section as binding for implementer and reviewer setup.
  - Phase 1 is a test-locking phase: reproduce the current repost failures first and do not fix later-phase behavior during Phase 1.
  - For production phases, require strict `RED -> GREEN -> REFACTOR` and capture the exact failing tests or commands before production edits.
  - If QA returns `PASS` and the phase is accepted, move to the next phase automatically.
  - If QA returns `NEEDS WORK` or `FAIL`, run the fix loop for that same phase and review again before any advancement.
  - Do not widen scope into later phases unless required for compilation.
  - Follow the 3.6 plan's locked decisions, non-goals, required skills by phase, verification matrix, suggested file touch order, risks, and exit gates.
  - Record residual risks, explicit deferrals, and next-phase prerequisites before advancing.
  - Rebuild each next phase contract from the 3.6 plan instead of carrying hidden assumptions forward.
  - Treat Phase 6 as a hardening gate: optimize for regression closure, idempotency, retry safety, and compatibility verification rather than feature expansion.

  Reviewer fallback rule:
  - If a reviewer/QA agent fails twice to return a usable `PASS` / `NEEDS WORK` / `FAIL` verdict, treat that as a review-orchestration failure, not an implementation failure.
  - In that case, perform a manual controller review in the main session against the active phase contract and issue exactly one verdict: `PASS`, `NEEDS WORK`, or `FAIL`.
  - Do not advance without a verdict.

  3.6 execution rules:
  - Keep repost delivery on the existing runner/retry stack it already uses today; do not spend Phase 2 re-migrating reposts onto the runner.
  - Reuse `PostDeliveryRunner`, `post_recipients`, aggregate delivery status, and `PendingPostDeliveryRetrier` wherever the runner can be extended safely.
  - Do not reintroduce or route runtime repost send/retry through `post_pass_follow_on_support.dart`; treat it as dead cleanup only.
  - Phase 2 must add per-recipient app-level encryption on the existing runner path, extend `PostPassEnvelope` with v2 inner/encrypted helpers, and thread `Bridge` plus own ML-KEM secret access through repost send and receive.
  - Phase 3 must persist repost engagement participants plus explicit repost-total and hidden-heart baselines; do not rely on `COUNT(post_passes)` alone for fresh recipients.
  - Phase 4 must implement repost-owned media re-encryption with Go-backed file crypto bridge commands for large blobs, persisted attachment crypto metadata, and decrypt-after-download from stored attachment state.
  - Phase 5 must implement original-author avatar snapshot persistence and rendering inside encrypted reposts.
  - Phase 6 must harden retry, idempotency, security compatibility, and broader regression coverage without expanding feature scope.
  - Preserve one-hop limit, `pickPeople` rejection, explicit-recipient plus original-author notification behavior, current direct-then-inbox semantics, and current settlement semantics.
  - Do not widen comment, reaction, comment-reaction, or pin transport encryption beyond the repost-specific continuity required by 3.6.
  - Do not widen into 3.5, 3.7, or unrelated resilience-plan work except for the smallest compatibility fix required by the active 3.6 phase.

  Verification reminders:
  - Use the 3.6 plan's per-phase verification matrix as the minimum targeted command set.
  - Run the new migration/helper regression tests whenever a phase adds schema or helper-backed persistence.
  - Include `integration_test/posts_phase4_fake_test.dart` in regression coverage.
  - When Phase 4 changes real bridge/go commands and a device is available, also run `integration_test/conversation_bridge_test.dart` as the optional device-backed bridge smoke from the 3.6 plan.
  - Before final acceptance of the plan, run the broader regression commands listed in the 3.6 plan's broader regression section.

  Commit rule after acceptance, if a commit is requested:
  - feat(posts): implement <accepted phase label>

  Begin with Phase 1 only, then auto-advance according to the rules above.



  ==========
  
  Use $libp2p-phase-orchestrator.

  Plan path:
  - UI-21-POST/3.6-Repost-media-improv.md

  Controller mode:
  - single-phase

  Active phase:
  - Phase 6: Guard Retry, Idempotency, Security Compatibility, And Shared-Thread Continuity

  Stop condition:
  - Stop when Phase 6 is accepted or blocked.
  - Do not start any work beyond Phase 6 in this session.

  Accepted phase context:
  - Phase 1 accepted
  - Phase 2 accepted
  - Phase 3 accepted
  - Phase 4 accepted
  - Phase 5 accepted
  - Resume from Phase 6 only

  Required skills:
  - flutter-feature-module-implementer
  - flutter-test-orchestrator

  Phase 5 acceptance context to preserve:
  - Phase 5 avatar snapshot is in acceptance shape.
  - The real Phase 5 blocker was fixed in `lib/features/posts/application/handle_incoming_passed_post_use_case.dart` so receive-side avatar persistence now updates both on first insert and when a repost resurfaces an already-stored post.
  - The original envelope/avatar contract gap is closed in `lib/features/posts/domain/models/post_pass_envelope.dart`.
  - Phase 5 coverage is present in:
    - `test/features/posts/phase4/post_pass_envelope_test.dart`
    - `test/features/posts/phase4/pass_post_along_use_case_test.dart`
    - `test/features/posts/phase4/posts_pass_repository_test.dart`
    - `test/features/posts/phase4/post_card_passed_along_test.dart`
    - `test/features/posts/improvement/post_pass_media_avatar_smoke_test.dart`
    - `test/core/database/migrations/039_posts_pass_avatar_snapshots_test.dart`
  - These Phase 5 verification commands were green:
    - `flutter test test/features/posts/phase4/post_pass_envelope_test.dart`
    - `flutter test test/features/posts/phase4/pass_post_along_use_case_test.dart`
    - `flutter test test/features/posts/phase4/handle_incoming_passed_post_use_case_test.dart test/features/posts/phase4/posts_pass_repository_test.dart`
    - `flutter test test/features/posts/phase4/post_card_passed_along_test.dart test/features/posts/phase4/posts_pass_repository_test.dart`
    - `flutter test test/features/posts/improvement/post_pass_media_avatar_smoke_test.dart`
    - `flutter test test/core/database/migrations/039_posts_pass_avatar_snapshots_test.dart`

  Residual Phase 5 follow-up to carry into Phase 6:
  - Post deletion still appears not to clear `post_pass_avatar_snapshots` rows.
  - Treat that as an allowed Phase 6 hardening candidate.
  - If it is reproducible and can be fixed without widening scope, close it in Phase 6.
  - If it is not required to satisfy Phase 6 exit gates, record it clearly as a residual risk or explicit deferral rather than reopening Phase 5.

  Agent orchestration rules:
  - Spawn a separate implementer/dev agent for Phase 6.
  - Spawn a separate reviewer/QA agent for Phase 6.
  - Never let the implementer review its own work.
  - If review finds blocking gaps, spawn a separate fix agent for Phase 6, or a fresh implementer- context fix agent, but do not reuse the reviewer as the fixer.
  - After Phase 6 is accepted or blocked, close the phase-local implementer, reviewer, and fixer agents.

  Phase control rules:
  - Build the Phase 6 contract from `UI-21-POST/3.6-Repost-media-improv.md` only.
  - Treat the plan's `Required Skills By Phase` section as binding.
  - Treat Phase 6 as a hardening gate: optimize for regression closure, retry safety, idempotency,compatibility, and acceptance-quality verification rather than featur expansion.
  - Require strict `RED -> GREEN -> REFACTOR` for any production changes that are still needed.
  - Capture the exact failing tests or commands before production edits.
  - Do not widen into unrelated feature work or later-plan ideas unless a minimal compatibility change is required for compilation or for an explicit Phase 6 exit gate.
  - Follow the 3.6 plan's locked decisions, non-goals, verification matrix, suggested file touch order, risks, and exit gates.
  - Record residual risks, explicit deferrals, and final hardening notes before issuing the acceptance decision.

  Phase 6 execution requirements:
  - Verify that repost retry, idempotency, encrypted repost delivery, encrypted repost media, avatar snapshot persistence, and repost-thread continuity all remain correct together.
  - Verify that repost send/retry stays on the existing `post_create` runner stack and does not regress back onto the dead repost follow-on helper path.
  - Verify that explicit-recipient behavior plus original-author notification still works.
  - Verify that one-hop limit and `pickPeople` rejection remain intact.
  - Verify that repost validation still rejects non-renderable, inaccessible, or unencryptable snapshots before local persistence.
  - Verify that duplicate or retried repost delivery does not create duplicate pass rows, duplicate repost media rows, duplicate ciphertext uploads, duplicated repost participants, duplicated hidden heart-baseline state, duplicated repost-total baseline state, or corrupted avatar snapshot state.
  - Verify that direct `post_create` behavior does not regress.
  - If the `post_pass_avatar_snapshots` deletion leak is reproducible, fix it only as a Phase 6 hardening change and cover it with targeted regression tests.

  Inspect-first files:
  - `lib/features/posts/application/handle_incoming_passed_post_use_case.dart`
  - `lib/features/posts/domain/models/post_pass_envelope.dart`
  - `lib/features/posts/application/post_delivery_runner.dart`
  - `lib/features/posts/application/pending_post_delivery_retrier.dart`
  - `lib/features/posts/application/pass_post_along_use_case.dart`
  - `lib/features/posts/application/attach_post_media_use_case.dart`
  - `lib/features/posts/application/download_post_media_use_case.dart`
  - `lib/features/posts/domain/models/post_media_attachment_model.dart`
  - `lib/features/posts/domain/repositories/post_repository.dart`
  - `lib/features/posts/domain/repositories/post_repository_impl.dart`
  - `lib/core/services/incoming_message_router.dart`
  - `lib/features/posts/presentation/widgets/post_card.dart`
  - `lib/core/database/migrations/039_posts_pass_avatar_snapshots_test.dart`
  - `test/features/posts/phase4/post_pass_envelope_test.dart`
  - `test/features/posts/phase4/pass_post_along_use_case_test.dart`
  - `test/features/posts/phase4/handle_incoming_passed_post_use_case_test.dart`
  - `test/features/posts/phase4/posts_pass_repository_test.dart`
  - `test/features/posts/phase4/post_card_passed_along_test.dart`
  - `test/features/posts/improvement/post_pass_retry_integration_test.dart`
  - `test/features/posts/improvement/post_pass_encrypted_delivery_integration_test.dart`
  - `test/features/posts/improvement/post_pass_encrypted_media_integration_test.dart`
  - `test/features/posts/improvement/post_pass_shared_thread_integration_test.dart`
  - `test/features/posts/improvement/post_pass_engagement_baseline_integration_test.dart`
  - `test/features/posts/improvement/post_pass_media_avatar_smoke_test.dart`
  - `test/features/posts/improvement/post_delivery_runner_parallel_test.dart`
  - `test/core/services/pending_post_delivery_retrier_test.dart`
  - `test/core/services/incoming_message_router_posts_pass_test.dart`

  Verification requirements:
  - Use the 3.6 plan's targeted verification matrix as the minimum required command set for Phase 6.
  - Re-run the highest-value Phase 4 and Phase 5 suites that prove encrypted media, avatar snapshots, retry, and shared-thread continuity together.
  - Run the broader regression commands listed in the 3.6 plan before final acceptance.
  - If any Go-side or bridge-side regressions are suspected, include the corresponding Go and bridge test commands from the plan.
  - Report exact commands run, exact results, exact tests added or updated, and any remaining residual risks or deferrals.

  Reviewer fallback rule:
  - If the reviewer/QA agent fails twice to return a usable `PASS` / `NEEDS WORK` / `FAIL` verdict, treat that as a review-orchestration failure, not an implementation failure.
  - In that case, perform a manual controller review in the main session against the Phase 6 contract and issue exactly one verdict: `PASS`, `NEEDS WORK`, or `FAIL`.
  - Do not accept Phase 6 without a verdict.

  Commit rule after acceptance, if a commit is requested:
  - feat(posts): implement Phase 6: Guard Retry, Idempotency, Security Compatibility, And Shared-Thread Continuity

  Begin with Phase 6 only.



  =============
   Use $libp2p-phase-orchestrator in auto-advance mode.

  Plan path:
  - UI-21-POST/3.7-Repost-visual-improv.md

  Controller mode:
  - auto-advance

  Start phase:
  - Phase 1: Reproduce The Visual And Metric Gap

  Allowed phase sequence:
  - Phase 1: Reproduce The Visual And Metric Gap
  - Phase 2: Add A Durable Repost Visual Metric Contract
  - Phase 3: Surface The New Repost Visual State On Cards
  - Phase 4: Guard Refresh Timing, Idempotency, And Compatibility

  Stop condition:
  - Stop when a phase is blocked or when Phase 4 is accepted.
  - Do not start any work beyond Phase 4 unless I explicitly request it in a later session.

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
  - Treat UI-21-POST/3.7-Repost-visual-improv.md as the authoritative active phase-scoped
  implementation doc.
  - Do not require a separate master plan for this run.
  - For production phases, require strict `RED -> GREEN -> REFACTOR` and capture the exact failing
  tests or commands before production edits.
  - If QA returns `PASS` and the phase is accepted, move to the next phase automatically.
  - If QA returns `NEEDS WORK` or `FAIL`, run the fix loop for that same phase and review again
  before any advancement.
  - Do not widen scope into later phases unless required for compilation.
  - Follow the 3.7 plan's locked decisions, product assumption, non-goals, verification matrix,
  suggested file touch order, residual risks, and exit gates.
  - Record residual risks, explicit deferrals, and next-phase prerequisites before advancing.
  - Rebuild each next phase contract from the 3.7 plan instead of carrying hidden assumptions
  forward.

  Repost visual-metric execution rules:
  - Keep this plan scoped to repost visual state and repost share metrics on the card.
  - Coordinate with 3.6 for carried repost-total baseline transport and persistence, but keep metric
  projection and UI rules in 3.7.
  - Do not overload `shareCount` with a second meaning.
  - Introduce explicit repost-visual metrics in the Posts surface model:
    - `totalSharedToCount`
    - `viewerSharedToCount`
    - `viewerHasPassed`
  - Define `totalSharedToCount` as the carried repost-total baseline plus later locally known repost
  deltas, or the smallest equivalent authoritative projection.
  - Define `viewerSharedToCount` as the sum of `recipient_count` across the current viewer's local
  outgoing repost events for that post.
  - Define `viewerHasPassed` as `viewerSharedToCount > 0`.
  - Add `recipient_count` to repost persistence and repost send/receive contracts where Phase 2
  requires it.
  - Exclude the original-author notification delivery from `recipient_count`.
  - On the reposter's own card, show the viewer-local shared-to count across that viewer's local
  reposts of the post.
  - On the original author's card, show the aggregate shared-to count across repost events known to
  that author.
  - On a passed-along receiver's card, show the aggregate shared-to count when a carried or
  reconstructed total exists, but keep the repost control visually neutral unless the viewer is also
  the author or reposter.
  - Make the repost action visually active only on:
    - the reposter's card when `viewerHasPassed == true`
    - the original author's card when `totalSharedToCount > 0`
  - Keep passive receiver cards visually neutral even when they show an aggregate repost count.
  - Keep the visual change scoped to the repost action itself; do not redesign the whole card.
  - Keep repost counts driven from durable Posts state, not transient widget state.
  - Preserve existing repost durability, one-hop limit, `pickPeople` rejection, and retry semantics.
  - Preserve author-notification privacy by carrying only numeric `recipient_count`, not recipient
  identity lists for metric rendering.
  - Keep compatibility for older rows and envelopes with the smallest safe fallback.
  - Do not widen into repost sender-speed work from 3.5.
  - Do not widen into repost media, avatar, encryption, or heart-baseline work from 3.6 except for
  the smallest compatibility hook needed by the active 3.7 phase.
  - Do not change who can repost, repost fanout concurrency, or the heart metric contract in this
  plan.
  - Do not attempt a globally deduped unique historical recipient count across all repost history in
  this plan.

  Phase-specific execution reminders:
  - Phase 1 must reproduce and lock the current visual and metric gap before changing product
  behavior:
    - repost control stays visually neutral after local repost
    - reposter card shows no repost count
    - author card still uses repost-event count semantics instead of people-shared-to semantics
    - passive receiver cards still hide repost count
  - Phase 2 must add a durable repost visual metric contract:
    - persist `recipient_count`
    - exclude original-author notification from that count
    - persist incoming `recipient_count`
    - persist or project the carried repost-total baseline needed for passed-along receiver cards
    - expose `totalSharedToCount`, `viewerSharedToCount`, and `viewerHasPassed`
    - keep duplicate delivery idempotent
    - keep legacy rows readable with a compatible fallback
  - Phase 3 must surface the new repost visual state on cards:
    - reposter card shows active repost styling plus `viewerSharedToCount`
    - original-author card shows active repost styling plus `totalSharedToCount`
    - passive receiver card shows `totalSharedToCount` neutrally when available
    - narrow-card wrapping must remain stable
  - Phase 4 must guard refresh timing, idempotency, and compatibility:
    - local repost persistence refreshes the reposter card promptly without waiting for full network
  settlement
    - later incoming repost notifications refresh the original author's aggregate count
    - carried baselines on passed-along receiver cards surface promptly and continue from later
  repost deltas
    - retries and duplicate processing do not double-increment the metric
    - compatibility rows created before `recipient_count` still render a stable fallback
    - passed-along banners, share attribution, and feed ordering do not regress

  Verification reminders:
  - Use the 3.7 plan's per-phase verification matrix as the minimum targeted command set.
  - Before final acceptance of the plan, run the broader regression commands listed in the 3.7
  plan's broader regression section.

  Commit rule after acceptance, if a commit is requested:
  - feat(posts): implement <accepted phase label>

  Begin with Phase 1 only, then auto-advance according to the rules above


  ========================================
Use $libp2p-phase-orchestrator in auto-advance mode.

  Plan path:
  - UI-21-POST/3.7-Repost-visual-improv.md

  Controller mode:
  - auto-advance

  Start phase:
  - Phase 1: Reproduce The Visual And Metric Gap

  Allowed phase sequence:
  - Phase 1: Reproduce The Visual And Metric Gap
  - Phase 2: Add A Durable Repost Visual Metric Contract
  - Phase 3: Surface The New Repost Visual State On Cards
  - Phase 4: Guard Refresh Timing, Idempotency, And Compatibility

  Stop condition:
  - Stop on the first blocked phase or when Phase 4 is accepted.
  - Do not start anything beyond Phase 4 unless I explicitly request it later.

  Agent rules:
  - Use fresh isolated agents per phase: one implementer, one reviewer, and a separate fixer only if review finds blocking gaps.
  - Never let the implementer review its own phase.
  - Close phase-local agents before advancing.

  Phase-control rules:
  - Treat UI-21-POST/3.7-Repost-visual-improv.md as the authoritative phase-scoped plan for this run.
  - Do not require a separate master plan.
  - Enforce strict RED -> GREEN -> REFACTOR for every production phase and capture exact failing tests or commands before production edits.
  - Auto-advance only after reviewer verdict PASS and phase acceptance.
  - If review returns NEEDS WORK or FAIL, stay in the same phase, run a fix loop, and review again before any advancement.
  - Rebuild each next phase contract from the 3.7 doc itself.
  - Follow the 3.7 plan’s locked decisions, product assumption, non-goals, verification matrix, suggested file touch order, residual risks, and exit gates.
  - Record residual risks, explicit deferrals, and next-phase prerequisites before advancing.
  - Do not widen into later phases unless required for compilation.

  3.7 execution rules:
  - Keep scope limited to repost visual state and repost share metrics on the card.
  - Coordinate with 3.6 only for the smallest compatibility hook needed for carried repost-total baseline transport/persistence.
  - Do not overload `shareCount`.
  - Implement and use explicit metrics: `totalSharedToCount`, `viewerSharedToCount`,`viewerHasPassed`.
  - Persist `recipient_count` for reposts where Phase 2 requires it.
  - Exclude original-author notification from `recipient_count`.
  - Reposter card: active repost control plus viewer-local shared-to count when `viewerHasPassed == true`.
  - Original-author card: active repost control plus aggregate shared-to count when `totalSharedToCount > 0`.
  - Passed-along receiver card: show aggregate shared-to count neutrally when available; do not impersonate author/reposter ownership.
  - Keep counts driven by durable Posts state, not transient widget state.
  - Preserve repost durability, retry semantics, one-hop limit, `pickPeople` rejection, and author- notification privacy.
  - Keep compatibility for older rows/envelopes with the smallest safe fallback.
  - Do not widen into 3.5 sender-speed work, 3.6 media/avatar/encryption or heart-metric work, repost fanout-concurrency changes, or broader card redesign.

  Phase reminders:
  - Phase 1: prove the current gap only; neutral repost icon, missing reposter count, wrong event- count semantics, and hidden passive-receiver count.
  - Phase 2: add durable metric contract; `recipient_count`, carried aggregate baseline support, idempotent persistence, and compatible fallback for legacy rows.
  - Phase 3: surface correct visual state and count rules on reposter, original-author, and passive receiver cards without layout overflow.
  - Phase 4: guard prompt refresh, carried-baseline continuity, retry/idempotency safety, compatibility rows, passed-along banners, share attribution, and feed ordering.

  Verification:
  - Use the 3.7 per-phase verification matrix as the minimum required command set.
  - Before final acceptance, run the broader regression commands listed in the 3.7 broader regression section.

  Commit rule if a commit is requested:
  - feat(posts): implement <accepted phase label>

  Begin with Phase 1 only, then auto-advance according to these rules.


  =========


   Use $libp2p-phase-orchestrator in auto-advance mode.

  Plan path:
  - UI-21-POST/3.9-Repost-avatar-processAvatar-alignment.md

  Controller mode:
  - auto-advance

  Start phase:
  - The first explicit phase defined in UI-21-POST/3.9-Repost-avatar-processAvatar-alignment.md

  Allowed phase sequence:
  - Derive the ordered phase list directly from UI-21-POST/3.9-Repost-avatar-processAvatar-
  alignment.md.
  - Do not invent, rename, merge, skip, or reorder phases.
  - Use the document’s exact phase labels and titles.

  Stop condition:
  - Stop when a phase is blocked or when the final explicit phase in the 3.9 doc is accepted.
  - Do not start any work beyond the last phase defined in the 3.9 doc unless I explicitly request
  it in a later session.

  Accepted phase context:
  - No 3.9 phases are accepted yet.
  - Resume from the first explicit phase only.

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
  - Treat UI-21-POST/3.9-Repost-avatar-processAvatar-alignment.md as the authoritative active phase-
  scoped implementation doc.
  - Treat the doc’s `Required Skills By Phase` section as binding for implementer and reviewer setup
  when present.
  - If the first phase is a test-locking, contract-only, or non-production phase, do not write
  production code in that phase.
  - For production phases, require strict `RED -> GREEN -> REFACTOR` and capture the exact failing
  tests or commands before production edits.
  - If QA returns `PASS` and the phase is accepted, move to the next phase automatically.
  - If QA returns `NEEDS WORK` or `FAIL`, run the fix loop for that same phase and review again
  before any advancement.
  - Do not widen scope into later phases unless required for compilation.
  - Follow the 3.9 doc’s locked decisions, non-goals, required skills by phase, verification matrix,
  suggested file touch order, risks, internal slices, and exit gates.
  - Record residual risks, explicit deferrals, and next-phase prerequisites before advancing.
  - Rebuild each next phase contract from the 3.9 doc instead of carrying hidden assumptions
  forward.
  - If the final phase is a hardening gate, optimize for regression closure, idempotency,
  compatibility verification, and coverage quality rather than feature expansion.

  Reviewer fallback rule:
  - If a reviewer/QA agent fails twice to return a usable `PASS` / `NEEDS WORK` / `FAIL` verdict,
  treat that as a review-orchestration failure, not an implementation failure.
  - In that case, perform a manual controller review in the main session against the active phase
  contract and issue exactly one verdict: `PASS`, `NEEDS WORK`, or `FAIL`.
  - Do not advance without a verdict.

  3.9 execution rules:
  - Treat UI-21-POST/3.9-Repost-avatar-processAvatar-alignment.md as the sole source of truth for
  processAvatar alignment behavior, scope, sequencing, and acceptance criteria.
  - Preserve all existing repost behavior outside the explicit scope of the active 3.9 phase.
  - Do not widen into 3.5, 3.6, 3.7, 3.8, unrelated repost work, or unrelated resilience-plan work
  except for the smallest compatibility fix required by the active 3.9 phase.
  - Do not bundle unrelated encryption, media, retry, schema, transport, or UI work unless the
  active 3.9 phase explicitly requires it.
  - If the 3.9 doc defines ownership, rendering, persistence, caching, source-precedence,
  processAvatar, or avatar-fidelity rules, follow those rules exactly.
  - If the 3.9 doc defines phase-specific invariants or regressions to preserve, treat them as
  mandatory.

  Verification reminders:
  - Use the 3.9 doc’s per-phase verification matrix as the minimum targeted command set.
  - Run any migration/helper regression tests whenever a phase adds schema or helper-backed
  persistence.
  - Run any avatar-rendering, repost, or UI regression tests the 3.9 doc marks as required.
  - Before final acceptance of the plan, run the broader regression commands listed in the 3.9 doc’s
  broader regression section.

  Commit rule after acceptance, if a commit is requested:
  - feat(posts): implement <accepted phase label>

  Begin with the first explicit phase only, then auto-advance according to the rules above.

  ===================

  Use $libp2p-phase-orchestrator in auto-advance mode.

  Plan path:
  - UI-21-POST/3.9-Repost-avatar-processAvatar-alignment.md

  Controller mode:
  - auto-advance

  Start phase:
  - Phase 1: Reproduce The Client-Side Avatar Contract Drift

  Allowed phase sequence:
  - Phase 1: Reproduce The Client-Side Avatar Contract Drift
  - Phase 2: Canonicalize Local Contact Avatar Storage Through processAvatar()
  - Phase 3: Align Repost Sender With The Canonical Avatar Contract
  - Phase 4: Guard Legacy Files, Diagnostics, And Receiver Compatibility

  Stop condition:
  - Stop when a phase is blocked or when Phase 4 is accepted.
  - Do not start any work beyond Phase 4 unless I explicitly request it in a later session.

  Accepted phase context:
  - No 3.9 phases are accepted yet.
  - Resume from Phase 1 only.

  Dependency context:
  - UI-21-POST/3.6-Repost-media-improv.md
  - UI-21-POST/3.8-Repost-author-fidelity-and-thread-continuity.md
  - Use these only as dependency/background context.
  - Do not widen scope beyond what UI-21-POST/3.9-Repost-avatar-processAvatar-alignment.md explicitly requires.

  Agent orchestration rules:
  - Spawn a separate implementer/dev agent for each phase.
  - Spawn a separate reviewer/QA agent for each phase.
  - Never let the implementer review its own phase.
  - If review finds blocking gaps, spawn a separate fix agent for that same phase, or a fresh
  implementer-context fix agent, but do not reuse the reviewer as the fixer.
  - After a phase is accepted, discard or close the phase-local implementer, reviewer, and fixer agents before advancing.
  - Start the next phase with fresh agents so context does not accumulate across phases.

  Phase control rules:
  - Run one controller session per phase, but auto-advance after acceptance.
  - Treat UI-21-POST/3.9-Repost-avatar-processAvatar-alignment.md as the authoritative active phase- scoped implementation doc.
  - Treat the 3.9 doc’s `Suggested File Touch Order`, `Verification Matrix`, `Locked Decisions`,
  `Non-Goals`, `Residual Risks To Track`, and `Exit Gate` sections as binding controller guidance.
  - Treat any `Required Skills By Phase` section in the 3.9 doc as binding for implementer and reviewer setup if present.
  - Phase 1 is a test-locking phase: reproduce the current avatar-contract drift first and do not fix later-phase behavior during Phase 1.
  - For production phases, require strict `RED -> GREEN -> REFACTOR` and capture the exact failing tests or commands before production edits.
  - If QA returns `PASS` and the phase is accepted, move to the next phase automatically.
  - If QA returns `NEEDS WORK` or `FAIL`, run the fix loop for that same phase and review again before any advancement.
  - Do not widen scope into later phases unless required for compilation.
  - Record residual risks, explicit deferrals, and next-phase prerequisites before advancing.
  - Rebuild each next phase contract from the 3.9 doc instead of carrying hidden assumptions forward.
  - Treat Phase 4 as the final compatibility and diagnostics hardening gate rather than a feature- expansion phase.

  Reviewer fallback rule:
  - If a reviewer/QA agent fails twice to return a usable `PASS` / `NEEDS WORK` / `FAIL` verdict, treat that as a review-orchestration failure, not an implementation failure.
  - In that case, perform a manual controller review in the main session against the active phase contract and issue exactly one verdict: `PASS`, `NEEDS WORK`, or `FAIL`.
  - Do not advance without a verdict.

  3.9 execution rules:
  - `ImageProcessor.processAvatar(...)` is the canonical client-side avatar processing contract for repost avatar snapshots.
  - Preserve that contract exactly:
    - `512x512`
    - quality `80`
    - EXIF stripped
  - Do not use raw local avatar bytes as the repost transport contract.
  - Do not use the pre-processed raw file size as the primary inclusion gate.
  - Newly downloaded contact avatars must be normalized client-side through the same
  `processAvatar()` contract before becoming the canonical local avatar file.
  - Repost sender must still protect legacy or previously downloaded oversized avatar files by preparing a processed avatar snapshot at send time or through a shared normalization helper.
  - Keep `original_author_avatar_base64` as the repost payload field unless tests prove an envelope
  change is necessary.
  - Keep avatar persistence and hydrate behavior inside Posts-owned state.
  - Add explicit FLOW diagnostics for:
    - local avatar path resolution
    - avatar processing start
    - avatar processing success
    - avatar processing failure
    - avatar snapshot include/omit result
  - Preserve one-hop repost depth, retry semantics, and current repost media behavior.
  - Do not widen into:
    - repost-thread trust/fanout fixes from 3.8
    - repost visual-state work from 3.7
    - generic avatar redesign or `UserAvatar` styling changes
    - relay avatar schema changes
    - a broad media-pipeline rewrite outside avatar normalization
    - new friends-of-friends contact behavior
  - Phase 2 must canonicalize local contact avatar storage through `processAvatar()`.
  - Phase 3 must align repost sender with the canonical avatar contract and explicitly cover legacy oversized local avatar files already present on disk.
  - Phase 4 must harden legacy-file handling, diagnostics, receiver compatibility, safe fallback behavior, and temp-file cleanup without expanding scope.
  - Keep processing logic in application/helper code, not `Wired` UI code, except for the smallest dependency-wiring change required by the active phase.

  Verification reminders:
  - Use the 3.9 doc’s per-phase verification matrix as the minimum targeted command set.

  Phase 1 minimum:
  - `flutter test test/features/settings/application/download_profile_picture_use_case_test.dart`
  - `flutter test test/features/posts/phase4/pass_post_along_use_case_test.dart`
  - `flutter test test/features/posts/improvement/post_pass_media_avatar_smoke_test.dart`

  Phase 2 minimum:
  - `flutter test test/features/settings/application/download_profile_picture_use_case_test.dart`
  - `flutter test test/features/settings/application/profile_update_listener_test.dart`
  - `flutter test test/features/settings/integration/profile_picture_flow_test.dart`

  Phase 3 minimum:
  - `flutter test test/features/posts/phase4/pass_post_along_use_case_test.dart`
  - `flutter test test/features/posts/phase4/handle_incoming_passed_post_use_case_test.dart`
  - `flutter test test/features/posts/improvement/post_pass_media_avatar_smoke_test.dart`

  Phase 4 minimum:
  - `flutter test test/features/posts/phase4/pass_post_along_use_case_test.dart`
  - `flutter test test/features/posts/phase4/handle_incoming_passed_post_use_case_test.dart`
  - `flutter test test/features/posts/improvement/post_pass_media_avatar_smoke_test.dart`

  Broader regression before final acceptance:
  - `flutter test test/core/media/image_processor_test.dart`
  - `flutter test test/features/settings/application/upload_profile_picture_use_case_test.dart`
  - `flutter test test/features/settings`
  - `flutter test test/features/posts/phase4`
  - `flutter test test/features/posts/improvement`

  Commit rule after acceptance, if a commit is requested:
  - feat(posts): implement <accepted phase label>

  Begin with Phase 1 only, then auto-advance according to the rules above.


  ====


Use $libp2p-phase-orchestrator in auto-advance mode.

  Goal:
  - Implement the full BiDi text rendering fix end-to-end so mixed Arabic + English text renders correctly in display widgets and compose inputs, and safe BiDi markers are preserved through send/receive flows.

  Plan path:
  - UI-TestFlight-1/bidi-text-fix-tdd-plan.md

  Controller mode:
  - auto-advance

  Start phase:
  - Phase 1: Text Direction Detection Utility

  Allowed phase sequence:
  - Phase 1: Text Direction Detection Utility
  - Phase 2: Update Text Sanitizer — Preserve Helpful BiDi Markers
  - Phase 3: Add `textDirection` to LinkableText Widget
  - Phase 4: Wire Direction Detection into Display Widgets
  - Phase 5: Auto-Detect Direction on Compose Input Fields
  - Phase 6: Symmetric Sanitization — Send + Group Paths

  Stop condition:
  - Stop on the first blocked phase or when Phase 6 is accepted.
  - Do not stop for intermediate approval between phases.
  - Do not start anything beyond Phase 6 unless I explicitly request it later.

  Agent rules:
  - Use fresh isolated agents per phase: one implementer, one reviewer, and a separate fixer only if review finds blocking gaps.
  - Never let the implementer review its own phase.
  - Close phase-local agents before advancing.

  Phase-control rules:
  - Treat UI-TestFlight-1/bidi-text-fix-tdd-plan.md as the authoritative phase-scoped plan for this run.
  - Do not require a separate master plan.
  - Enforce strict RED -> GREEN -> REFACTOR for every production phase and capture exact failing tests or commands before production edits.
  - Auto-advance only after reviewer verdict PASS and phase acceptance.
  - If review returns NEEDS WORK or FAIL, stay in the same phase, run a fix loop, and review again before any advancement.
  - Rebuild each next phase contract from the bidi plan itself.
  - Follow the bidi plan’s phase goals, file scopes, test files, implementation notes, summary table, and run commands.
  - Record residual risks, explicit deferrals, and next-phase prerequisites before advancing.
  - Do not widen into later phases unless required for compilation.
  - If the plan labels a test file as “new” but that file already exists in the repo, extend the existing file instead of creating a duplicate suite.

  BiDi execution rules:
  - Keep scope limited to fixing mixed Arabic/English rendering, BiDi marker preservation, widget `textDirection` wiring, compose-field direction detection, and symmetric sanitization on send/receive paths.
  - Implement and use `detectTextDirection()` with the first-strong-character heuristic described in the plan.
  - Preserve safe/helpful markers: `LRM` (U+200E), `RLM` (U+200F), `ALM` (U+061C), `LRI` (U+2066), `RLI` (U+2067), `FSI` (U+2068), `PDI` (U+2069), and `ZWJ` (U+200D).
  - Continue stripping only the dangerous/invisible characters called out by the plan, including zero-width space, ZWNJ, legacy bidi embedding/override characters, and BOM.
  - Keep `LinkableText` backward-compatible when `textDirection` is null.
  - In display widgets, detect direction from the actual message body or quoted text as specified by the plan.
  - In compose widgets, update `TextField.textDirection` dynamically from controller text as the user types.
  - In send/receive flows, sanitize text once at the top of each flow and reuse the sanitized value consistently for save, dedupe, publish, inbox-store, and wire payload generation.
  - Do not introduce unrelated UI redesigns, localization refactors, or chat-pipeline changes outside the plan.

  Phase reminders:
  - Phase 1: add the direction-detection utility and its tests.
  - Phase 2: update sanitizer behavior to preserve helpful BiDi markers, including ALM, and update existing sanitizer tests.
  - Phase 3: add optional `textDirection` support to `LinkableText` and verify backward compatibility.
  - Phase 4: wire direction detection into `LetterCard`, `MessageBubble`, and `QuotePreviewBar`, including quote-bar text.
  - Phase 5: wire live input direction into `ComposeArea`, `InlineReplyInput`, and `ExpandedComposeInput`.
  - Phase 6: add symmetric sanitization to chat send, group send, and group receive, with tests that verify saved data plus wire/publish/inbox/dedupe behavior.

  Scope guardrails:
  - Keep production edits limited to the files named in the plan unless a minimal compatibility change is required for compilation.
  - Keep test edits limited to the plan’s listed suites unless a minimal helper update is required to make those tests compile.
  - Do not add new architecture, new persistence formats, or unrelated cleanup.

  Verification:
  - Use the phase-specific run commands in the plan as the minimum required command set for each phase.
  - Before final acceptance, run a final regression sweep across all touched suites:
    - flutter test test/core/utils/text_direction_utils_test.dart
    - flutter test test/core/utils/text_sanitizer_test.dart
    - flutter test test/shared/widgets/linkable_text_test.dart
    - flutter test test/features/conversation/presentation/widgets/letter_card_test.dart
    - flutter test test/features/feed/presentation/widgets/message_bubble_test.dart
    - flutter test test/features/feed/presentation/widgets/quote_preview_bar_test.dart
    - flutter test test/features/conversation/presentation/widgets/compose_area_test.dart
    - flutter test test/features/feed/presentation/widgets/inline_reply_input_test.dart
    - flutter test test/features/feed/presentation/widgets/expanded_compose_input_test.dart
    - flutter test test/features/conversation/application/send_chat_message_use_case_test.dart
    - flutter test test/features/groups/application/send_group_message_use_case_test.dart
    - flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart

  Commit rule if a commit is requested:
  - fix(chat): implement <accepted phase label>

  Assume the plan is approved and ready.
  Begin with Phase 1 only, then auto-advance through Phase 6 according to these rules without pausing for intermediate approval unless a phase is genuinely blocked.






===============================


  Use $libp2p-phase-orchestrator in auto-advance mode. If that skill is unavailable, follow the same controller workflow manually.

  Goal
  - Implement the full BiDi text rendering fix end-to-end so mixed Arabic + English text renders correctly in display widgets and compose inputs, and safe BiDi markers are preserved through send/receive flows.

  Plan Path
  - UI-TestFlight-1/bidi-text-fix-tdd-plan.md

  Controller Mode
  - auto-advance

  Start Phase
  - Phase 1: Text Direction Detection Utility

  Allowed Phase Sequence
  1. Phase 1: Text Direction Detection Utility
  2. Phase 2: Update Text Sanitizer — Preserve Helpful BiDi Markers
  3. Phase 3: Add `textDirection` to LinkableText Widget
  4. Phase 4: Wire Direction Detection into Display Widgets
  5. Phase 5: Auto-Detect Direction on Compose Input Fields
  6. Phase 6: Symmetric Sanitization — Send + Group Paths

  Stop Condition
  - Stop on the first blocked phase or when Phase 6 is accepted.
  - Do not stop for intermediate approval between phases.
  - Do not start anything beyond Phase 6 unless I explicitly request it later.

  Agent Rules
  - Use fresh isolated agents per phase: one implementer, one reviewer, and a separate fixer only if review finds blocking gaps.
  - Never let the implementer review its own phase.
  - Close all phase-local agents before advancing.

  Phase-Control Rules
  - Treat `UI-TestFlight-1/bidi-text-fix-tdd-plan.md` as the authoritative phase-scoped plan for this run.
  - Do not require a separate master plan.
  - Rebuild each phase contract from the BiDi plan itself.
  - Enforce strict `RED -> GREEN -> REFACTOR` for every production phase and capture the exact failing tests or commands before production edits.
  - Auto-advance only after reviewer verdict `PASS` and phase acceptance.
  - If review returns `NEEDS WORK` or `FAIL`, stay in the same phase, run a fix loop, and review again before any advancement.
  - Follow the BiDi plan’s phase goals, file scopes, test files, implementation notes, summary table, and run commands.
  - Record residual risks, explicit deferrals, and next-phase prerequisites before advancing.
  - Do not widen into later phases unless required for compilation.
  - If the plan labels a test file as `new` but that file already exists in the repo, extend the existing file instead of creating a duplicate suite.

  BiDi Execution Rules
  - Keep scope limited to fixing mixed Arabic/English rendering, BiDi marker preservation, widget `textDirection` wiring, compose-field direction detection, and symmetric sanitization on send/receive paths.
  - Implement and use `detectTextDirection()` with the first-strong-character heuristic described in the plan.
  - Preserve these safe/helpful markers:
    - `LRM` (`U+200E`)
    - `RLM` (`U+200F`)
    - `ALM` (`U+061C`)
    - `LRI` (`U+2066`)
    - `RLI` (`U+2067`)
    - `FSI` (`U+2068`)
    - `PDI` (`U+2069`)
    - `ZWJ` (`U+200D`)
  - Continue stripping only the dangerous/invisible characters called out by the plan, including zero- width space, ZWNJ, legacy bidi embedding/override characters, and BOM.
  - Keep `LinkableText` backward-compatible when `textDirection` is null.
  - In display widgets, detect direction from the actual message body or quoted text as specified by the plan.
  - In compose widgets, update `TextField.textDirection` dynamically from controller text as the user types.
  - In send/receive flows, sanitize text once at the top of each flow and reuse the sanitized value consistently for save, dedupe, publish, inbox-store, and wire payload generation.
  - Do not introduce unrelated UI redesigns, localization refactors, or chat-pipeline changes outside the plan.

  Phase Reminders
  - Phase 1: add the direction-detection utility and its tests.
  - Phase 2: update sanitizer behavior to preserve helpful BiDi markers, including ALM, and update existing sanitizer tests.
  - Phase 3: add optional `textDirection` support to `LinkableText` and verify backward compatibility.
  - Phase 4: wire direction detection into `LetterCard`, `MessageBubble`, and `QuotePreviewBar`, including quote-bar text.
  - Phase 5: wire live input direction into `ComposeArea`, `InlineReplyInput`, and `ExpandedComposeInput`.
  - Phase 6: add symmetric sanitization to chat send, group send, and group receive, with tests that verify saved data plus wire/publish/inbox/dedupe behavior.

  Scope Guardrails
  - Keep production edits limited to the files named in the plan unless a minimal compatibility change is required for compilation.
  - Keep test edits limited to the plan’s listed suites unless a minimal helper update is required to make those tests compile.
  - Do not add new architecture, new persistence formats, or unrelated cleanup.

  Verification
  - Use the phase-specific run commands in the plan as the minimum required command set for each phase.
  - Before final acceptance, run this final regression sweep across all touched suites:
    - `flutter test test/core/utils/text_direction_utils_test.dart`
    - `flutter test test/core/utils/text_sanitizer_test.dart`
    - `flutter test test/shared/widgets/linkable_text_test.dart`
    - `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart`
    - `flutter test test/features/feed/presentation/widgets/message_bubble_test.dart`
    - `flutter test test/features/feed/presentation/widgets/quote_preview_bar_test.dart`
    - `flutter test test/features/conversation/presentation/widgets/compose_area_test.dart`
    - `flutter test test/features/feed/presentation/widgets/inline_reply_input_test.dart`
    - `flutter test test/features/feed/presentation/widgets/expanded_compose_input_test.dart`
    - `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart`
    - `flutter test test/features/groups/application/send_group_message_use_case_test.dart`
    - `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart`

  Commit Rule
  - If a commit is requested, use: `fix(chat): implement <accepted phase label>`

  Assumptions
  - Assume the plan is approved and ready.
  - Begin with Phase 1 only, then auto-advance through Phase 6 according to these rules without pausing for intermediate approval unless a phase is genuinely blocked.







======================

  Use $libp2p-phase-orchestrator in auto-advance mode. If that skill is unavailable, follow the same controller workflow manually with fresh isolated implementer/reviewer/fixer agents per section.

  Important
  - The authoritative plan for this run is `UI-TestFlight-1/message-delivery-reliability-tdd-plan.md`.
  - Treat that document, including its audit notes, addenda,stale-test updates, smoke matrices, and prerequisite notes, as authoritative for scope and sequencing.
  - Do not use any other TestFlight or UI plan as the source of truth for this run.

  Goal
  - Implement the full message-delivery reliability plan end- to-end so the original send-then-lock failure is actually fixed:
    Alice sends a message, Alice’s phone locks or backgrounds, the message is not lost, Bob receives it, and Bob gets the correct notification/deep-link behavior.
  - Cover the full plan, not just the narrow 1:1 sender path. That includes the specified relay, notification, lifecycle, retry, media/voice recovery, and integration-test work defined by the plan.

  Phase Granularity
  - Treat each top-level `Section` in `UI-TestFlight-1/message- delivery-reliability-tdd-plan.md` as one controller phase.
  - Treat the section’s internal `Part` / `Step` / addendum items as internal slices that must be completed within the same section before advancing.
  - Do not stop mid-section for approval unless the section is genuinely blocked.

  Controller Mode
  - `auto-advance`

  Start Phase
  - `Section 4: Direct-First Send with Early wireEnvelope Persistence`

  Allowed Phase Sequence
  1. `Section 4: Direct-First Send with Early wireEnvelope Persistence`
  2. `Section 5: FCM and Notification Fixes`
  3. `Section 1: Stuck-Sending Message Recovery`
  4. `Section 2: App Lifecycle Pause Handler`
  5. `Section 3: iOS Background Task Assertion`
  6. `Section 6: Test Infrastructure and Integration`

  Stop Condition
  - Stop on the first blocked section or when Section 6 is accepted.
  - Do not stop for intermediate approval between sections.
  - Do not start anything beyond Section 6 unless I explicitly request it later.

  Agent Rules
  - Use fresh isolated agents per section: one implementer, one
  reviewer, and a separate fixer only if review finds blocking gaps.
  - Never let the implementer review its own section.
  - Close all section-local agents before advancing.
  - Do not run overlapping implementers on the same edit surface.

  Section-Control Rules
  - Build a fresh phase contract from the plan at the start of each section.
  - Internal parts/steps remain inside the current section; do not confuse them with phase advancement.
  - Enforce strict `RED -> GREEN -> REFACTOR` for every production section.
  - Capture the exact failing tests, compile failures, or commands before any production edits.
  - Auto-advance only after reviewer verdict `PASS` and explicit section acceptance.
  - If review returns `NEEDS WORK` or `FAIL`, stay in the same section, run a fix loop, and review again before advancing.
  - Record residual risks, explicit deferrals, stale-test updates applied, and next-section prerequisites before advancing.
  - Do not widen into later sections unless a minimal compatibility change is required for compilation.
  - If the plan says a test file is `new` but it already exists in the repo, extend the existing file instead of creating a duplicate suite.
  - If the plan’s audit notes say a referenced file or interface does not exist, verify the repo state first, then implement the prerequisite exactly as needed for the section.

  Global Execution Rules
  - Follow the plan’s recommended implementation order above, not numeric section order.
  - Respect the plan’s dependency graph:
    - Section 4 improves the post-serialization window but is not sufficient alone.
    - Section 1 creates recovery infrastructure that Section 2 depends on.
    - Section 3 protects the full send pipeline from the presentation layer only.
    - Section 6 comes after the fix sections and proves the actual bug is fixed.
  - Review against the plan contract, not generic completeness.
  - Keep scope inside the plan’s named files and explicit prerequisite helpers unless a minimal compile fix is required.
  - Do not introduce unrelated architecture changes, protocol changes, persistence redesigns, or UI rewrites.

  Section-Specific Rules

  Section 4 — Direct-First Send with Early wireEnvelope Persistence
  - Complete the full section, including Step 4.5 and the Section 4 Addendum.
  - Persist media attachment metadata at optimistic write time in `conversation_wired.dart`.
  - Persist `wireEnvelope` immediately after serialization and before the transport race in `send_chat_message_use_case.dart`.
  - Preserve inbox as fallback behavior; do not introduce unconditional optimistic inbox store.
  - Implement the relay/client idempotency contract required by
  Step 4.5:
    - relay-side inbox dedup by `messageId`
    - client-side retry guard when transport is already `inbox`
  - Preserve the invariant that direct ACK’d sends do not trigger phantom inbox/push behavior.
  - Account for duplicate-push risk explicitly; do not hand-wave it away.

  Section 5 — FCM and Notification Fixes
  - Complete the full section, including Bug A, Bug B, Bug C, and Bug D / media-notification-body work.
  - Bug A:
    - fix `sender_id` vs `from` routing in `notification_route_target.dart`
    - keep legacy fallback only where the plan allows
    - do not add redundant server aliases if the plan says the client fix is sufficient
  - Bug B:
    - add the missing top-level `Notification` struct for group push in `go-relay-server/inbox.go`
    - keep this scoped to the plan’s group-push parity hardening
  - Bug C:
    - implement the deployment/config/test requirements around Redis-backed push-token durability exactly as the plan specifies
    - treat production Redis requirement as in-scope, not optional commentary
  - Bug D:
    - implement media hydration and notification body generation so image/video/audio-only notifications show the correct body
    - update stale tests identified by the plan
  - Keep the distinction clear:
    - some fixes are required for 1:1 sufficiency
    - Bug B is group-specific and should stay narrowly scoped
    - but still implement the full section because this run is for the full plan

  Section 1 — Stuck-Sending Message Recovery
  - Complete the entire section, including Parts A, B, C, D, F, and G, plus the later gap-closure items called out inside Parts F/G.
  - Keep Section 1 scoped to 1:1 text/media/voice reliability; group sends remain out of scope for this section as the plan states.
  - Implement the stuck-sending recovery path end-to-end:
    - DB helpers for stuck `sending` rows
    - repository methods and interfaces
    - `recoverStuckSendingMessages()` use case
    - `PendingMessageRetrier` support for `sending` rows and cold-start initial sweep
    - resume-triggered retry callbacks with strict step ordering and fault isolation
    - media-aware replay safety for `retryFailedMessages`
    - null safety in `retryUnackedMessages`
    - incomplete-upload re-upload flow
    - pre-upload media/voice persistence and durable storage handling
  - Respect the plan’s ordering contracts for resume and retrier flows.
  - Do not quietly stop after Part D; Parts F and G are part of the same section acceptance.

  Section 2 — App Lifecycle Pause Handler
  - Complete the full section, including all Step 2.x work and acceptance checks.
  - `handleAppPaused()` must be local DB only. No network calls in the pause handler.
  - Add paused/hidden lifecycle handling in the real `_MyAppState` flow in `main.dart`, not a fake harness-only path.
  - Use conditional status transition semantics so completed messages are not overwritten back to `failed`.
  - Carry the repository/message-stream/UI-refresh contract through to the conversation screen so `failed` status actually becomes visible.
  - Preserve idempotency and race safety exactly as the plan requires.
  - Respect the plan’s state-specific guidance: do not widen to `inactive` if the plan excludes it.

  Section 3 — iOS Background Task Assertion
  - Complete the full section, including Swift XCTest, Dart bridge contract tests, presentation-layer wiring, Android no- op parity, and helper refactor.
  - Enforce the canonical owner rule:
    - `bg:begin` / `bg:end` live only in presentation-layer wired widgets
    - never in use cases or domain/application-layer send
  functions
  - Cover all four presentation-layer 1:1 send call sites the
  plan names:
    - `_onSend`
    - `_onVoiceRecordingStopped` local WiFi branch
    - `_onVoiceRecordingStopped` relay branch
    - `_onInlineSend` in feed
  - Start the background task before upload/transfer/send, and release it in `finally`.
  - Confirm `sendVoiceMessage` and `sendChatMessage` do not own background-task calls.
  - Use the iOS and Android bridge changes exactly as the plan specifies.

  Section 6 — Test Infrastructure and Integration
  - Complete the entire section last: Part A shared infrastructure, Part B integration tests, Part C smoke checklist, Part D execution order/CI concerns.
  - Use the existing `TestUser` + `FakeP2PNetwork` harness patterns from the repo.
  - Do not replace them with isolated dead-stream fakes for the cross-cutting integration tests.
  - Use mutable lifecycle closures for pause/resume simulation where the plan says to.
  - Create/extend only the shared fakes/helpers/fixtures the plan names.
  - Respect the plan’s testing discipline:
    - fake isolation per test
    - no shared bridge/service instances across tests
    - avoid `fake_async` except where the plan allows it
    - keep XCTest separate on macOS CI
  - The primary acceptance target is the real send-then-lock scenario plus the other cross-cutting regressions and notification flows.

  Scope Guardrails
  - Keep production edits limited to the plan’s named Dart, Go, Swift, Kotlin, and test files unless a minimal compatibility change is required for compilation.
  - Keep test edits limited to the plan’s named suites plus the stale-test updates the plan explicitly calls out.
  - Do not bundle unrelated cleanups.
  - Do not redesign transport architecture.
  - Do not move background-task ownership into application/ domain use cases.
  - Do not add unconditional inbox sends.
  - Do not expand Section 1 into group-message durability beyond what the plan explicitly allows.
  - Do not ignore the plan’s stale-test-update notes; apply them when the green-phase behavior changes those expectations.

  Verification Rules
  - Use the plan’s phase-specific run commands as the minimum required command set for each section.
  - Before accepting each section, run that section’s targeted Dart/Go/Swift tests and record exact results.
  - Before final acceptance, run the full regression required by the plan across the touched areas, including:
    - targeted `flutter test` runs for all new/updated section suites
    - `flutter test`
    - `flutter test test/unit/`
    - `flutter test test/integration/ --timeout 60s`
    - `flutter test test/core/resilience/ --timeout 120s`
    - `flutter test test/core/services/ pending_message_retrier_test.dart`
    - `flutter test test/core/lifecycle/ handle_app_paused_test.dart`
    - `flutter test test/features/push/`
    - targeted `go test` runs for the relay server files/ packages touched by Sections 4 and 5
    - `xcodebuild test -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 16'` for the iOS background-task tests
  - If any verification cannot be run, report the exact blocker and do not silently accept the section.

  Manual QA / Smoke Expectations
  - Use the smoke scenarios/checklists in Sections 1, 3, 5, and 6 as required evidence, not optional notes.
  - Record which smoke scenarios were executed versus deferred.
  - If a smoke scenario cannot be executed in this environment, record it as an explicit residual risk/deferral.

  Acceptance Rules
  - Accept a section only if:
    - all required behavior for that section is implemented
    - required red tests were captured before production edits
    - required targeted tests/commands are green, or any non- green item is explicitly understood and accepted
    - the reviewer reports `PASS`
    - scope stayed inside the section boundary
    - residual risks, deferrals, and next-section prerequisites are written down
  - In auto-advance mode, advance only if the current section is accepted and the next section is inside the allowed sequence.

  Commit Rule
  - If a commit is requested, use: `fix(chat): implement <accepted section label>`

  Assumptions
  - Assume the plan is approved and ready.
  - Begin with Section 4 only, then auto-advance through the allowed sequence without pausing for intermediate approval unless a section is genuinely blocked

  ================



====================

Use $libp2p-phase-orchestrator in auto-advance mode. If unavailable, follow the same controller workflow manually with fresh isolated implementer/reviewer/fixer agents per section.

  Authoritative plan
  - `UI-TestFlight-1/message-delivery-reliability-tdd-plan.md`

  Goal
  - Implement the full message-delivery reliability plan end-to-end so the real bug is fixed: sender sends, sender locks/ backgrounds immediately, message is not lost, recipient receives it, and notification/deep-link behavior is correct.
  - Implement the whole plan, not just the narrow 1:1 sender path.

  Phase model
  - Treat each top-level `Section` in the plan as one controller phase.
  - Treat each section’s internal `Part` / `Step` / addendum items as internal slices that must be completed before that section is accepted.
  - Do not stop mid-section for approval unless genuinely blocked.

  Controller mode
  - `auto-advance`

  Start phase
  - `Section 4: Direct-First Send with Early wireEnvelope Persistence`

  Allowed phase sequence
  1. `Section 4: Direct-First Send with Early wireEnvelope Persistence`
  2. `Section 5: FCM and Notification Fixes`
  3. `Section 1: Stuck-Sending Message Recovery`
  4. `Section 2: App Lifecycle Pause Handler`
  5. `Section 3: iOS Background Task Assertion`
  6. `Section 6: Test Infrastructure and Integration`

  Stop condition
  - Stop on the first blocked section or when Section 6 is accepted.
  - Do not pause for intermediate approval between sections.
  - Do not start anything beyond Section 6 unless I explicitly request it later.

  Agent rules
  - Use fresh isolated agents per section: one implementer, one reviewer, and a separate fixer only if review finds blocking


  =====================
# QA

    Use $libp2p-phase-orchestrator in auto-advance mode. If that
  skill is unavailable, follow the same controller workflow
  manually with fresh isolated reviewer/verifier/fixer agents
  per section.

  Authoritative plan
  - `UI-TestFlight-1/message-delivery-reliability-tdd-plan.md`

  Goal
  - QA and harden the already-implemented message-delivery
  reliability work against the plan above.
  - Assume the implementation already exists in the repo. This
  run is not a greenfield implementation run.
  - Prove whether the plan is sufficiently implemented end-to-
  end, identify any gaps or regressions, and fix only the
  blocking gaps needed for acceptance.
  - The acceptance bar is the real user outcome: sender sends,
  sender locks/backgrounds immediately, message is not lost,
  recipient receives it, and notification/deep-link behavior is
  correct.

  Mode
  - Treat each top-level `Section` in the plan as one
  hardening/QA phase.
  - Treat each section’s internal `Part` / `Step` / addendum
  items as internal acceptance slices inside that section.
  - Use review-before-acceptance for every section.
  - Use minimal targeted fixes only when needed to close
  blocking gaps.

  Controller mode
  - `auto-advance`

  Start phase
  - `Section 4: Direct-First Send with Early wireEnvelope
  Persistence`

  Allowed phase sequence
  1. `Section 4: Direct-First Send with Early wireEnvelope
  Persistence`
  2. `Section 5: FCM and Notification Fixes`
  3. `Section 1: Stuck-Sending Message Recovery`
  4. `Section 2: App Lifecycle Pause Handler`
  5. `Section 3: iOS Background Task Assertion`
  6. `Section 6: Test Infrastructure and Integration`

  Stop condition
  - Stop on the first blocked section or when Section 6 is
  accepted.
  - Do not pause for intermediate approval between sections.
  - Do not start anything beyond Section 6 unless I explicitly
  request it later.

  Agent rules
  - Use fresh isolated agents per section: one reviewer/
  auditor, one verifier, and a separate fixer only if review
  finds blocking gaps.
  - Never let the fixer review its own fixes.
  - Close all section-local agents before advancing.
  - Do not run overlapping fixers on the same files.

  Section-control rules
  - Rebuild the section contract from `UI-TestFlight-1/message-
  delivery-reliability-tdd-plan.md` at the start of each
  section.
  - Treat the plan, including audit notes, stale-test notes,
  addenda, smoke matrices, and prerequisites, as authoritative.
  - Start each section by inspecting the current
  implementation, touched files, existing tests, and current
  repo state before deciding whether anything needs to change.
  - Audit against the exact plan contract, not generic
  completeness.
  - Do not assume the implementation is sufficient just because
  the code compiles or broad tests pass.
  - If the current section is already sufficiently implemented
  and verified, do not edit code; accept it with evidence.
  - If review returns `NEEDS WORK` or `FAIL`, run a minimal fix
  loop scoped only to the blocking gaps, rerun targeted
  verification, and review again before advancing.
  - Do not widen into later sections unless a minimal
  compatibility change is required for compilation.
  - Record residual risks, explicit deferrals, stale-test
  updates applied or still missing, and next-section
  prerequisites before advancing.

  Per-section QA workflow
  1. Build the expected contract from the plan.
  2. Inspect the actual implementation and compare expected vs
  actual behavior/file scope/tests.
  3. Run the section’s required verification commands from the
  plan.
  4. Produce findings first, ordered by severity, with file/
  line references where possible.
  5. Decide one verdict only: `PASS`, `NEEDS WORK`, or `FAIL`.
  6. If needed, apply only minimal fixes for blocking gaps.
  7. Rerun targeted verification and re-review.
  8. Accept only if behavior, tests, scope, and evidence all
  meet the section contract.

  Required evidence for every section
  - Expected files and behaviors from the plan
  - Actual files touched / relevant current implementation
  - Missing items from the plan, if any
  - Unexpected scope leakage, if any
  - Tests already present vs missing tests vs stale tests that
  required updates
  - Exact commands run and whether they passed
  - Whether any smoke scenarios were executed or deferred
  - Residual risks and explicit deferrals
  - Clear acceptance or blocked decision

  Section-specific QA requirements

  Section 4
  - Verify the full section, including Step 4.5 and the Section
  4 Addendum.
  - Confirm media attachment metadata is persisted at
  optimistic write time in `conversation_wired.dart`.
  - Confirm `wireEnvelope` is persisted immediately after
  serialization and before discover/dial/send.
  - Confirm inbox remains fallback behavior only; no
  unconditional optimistic inbox store was introduced.
  - Confirm Step 4.5 idempotency protections exist:
    - relay-side inbox dedup by `messageId`
    - client-side retry guard when transport is already `inbox`
  - Confirm the implementation does not create phantom pushes
  or duplicate user-visible delivery on successful direct ACK
  paths.

  Section 5
  - Verify the full section, including Bug A, Bug B, Bug C, and the media-notification-body work.
  - Confirm `sender_id` routing is fixed in `notification_route_target.dart`.
  - Confirm group push now includes the top-level `Notification` struct in `go-relay-server/inbox.go`.
  - Confirm Redis-backed token durability requirements and tests/docs/config changes from the plan are present where required.
  - Confirm media hydration and notification body generation are implemented so image/video/audio-only notifications show correct bodies.
  - Confirm the stale tests named by the plan were updated if the new behavior changed their assumptions.

  Section 1
  - Verify the entire section, including Parts A, B, C, D, F, and G, plus the later gap-closure work inside F/G.
  - Do not accept the section if only Parts A-D landed; Parts F/G are required for full section acceptance.
  - Confirm stuck `sending` recovery exists end-to-end:
    - DB helpers
    - repository/interface changes
    - recovery use case
    - retrier support for `sending` rows and initial sweep on cold start
    - resume-triggered retry callbacks with the plan’s required ordering and fault isolation
    - media-aware replay safety in `retryFailedMessages`
    - null guard in `retryUnackedMessages`
    - incomplete upload re-upload flow
    - pre-upload media/voice persistence and durable storage handling
  - Keep Section 1 scoped to 1:1 text/media/voice as the plan states.

  Section 2
  - Verify the full section, including all Step 2.x work and acceptance checks.
  - Confirm `handleAppPaused()` is local DB only. No network calls.
  - Confirm paused/hidden lifecycle handling was added in real `_MyAppState` flow in `main.dart`.
  - Confirm conditional transition semantics prevent overwriting already-completed messages back to `failed`.
  - Confirm the repository/message-stream/UI-refresh chain is closed so `failed` status becomes visible in the conversation UI.

  Section 3
  - Verify the full section, including Swift XCTest, Dart bridge contract tests, presentation-layer wiring, Android no-op parity, and helper refactor.
  - Enforce the canonical owner rule:
    - `bg:begin` / `bg:end` live only in presentation-layer wired widgets
    - never in use cases or domain/application layer
  - Confirm all four named 1:1 send call sites are covered:
    - `_onSend`
    - `_onVoiceRecordingStopped` local WiFi branch
    - `_onVoiceRecordingStopped` relay branch
    - `_onInlineSend` in feed
  - Confirm background protection starts before upload/transfer/send and ends in `finally`.
  - Confirm `sendVoiceMessage` and `sendChatMessage` do not own background-task calls.

  Section 6
  - Verify the entire section last: Part A shared infrastructure, Part B integration tests, Part C smoke checklist, Part D execution order/CI concerns.
  - Confirm the implementation uses the repo’s existing `TestUser` + `FakeP2PNetwork` harness patterns for cross- cutting integration tests.
  - Confirm lifecycle simulation helpers, fake extensions, and fixtures required by the plan exist and are used appropriately.
  - Confirm the cross-cutting integration coverage actually proves the real bug is fixed, not just isolated unit behavior.
  - Confirm CI/test execution notes are reflected where the plan expects them.

  Scope guardrails
  - Keep edits limited to the plan’s named Dart, Go, Swift, Kotlin, and test files unless a minimal compatibility change is required for compilation.
  - Keep test edits limited to the plan’s named suites plus the stale-test updates explicitly called out by the plan.
  - Do not bundle unrelated cleanups or refactors.
  - Do not redesign transport architecture.
  - Do not move background-task ownership into application/ domain use cases.
  - Do not add unconditional inbox sends.
  - Do not expand Section 1 into group-message durability beyond what the plan explicitly allows.

  Verification rules
  - Use the plan’s section-specific run commands as the minimum required command set for each section.
  - Before accepting each section, run that section’s targeted verification and record exact results.
  - Before final acceptance, run the broad regression required by the plan across the touched areas, including:
    - `flutter test`
    - `flutter test test/unit/`
    - `flutter test test/integration/ --timeout 60s`
    - `flutter test test/core/resilience/ --timeout 120s`
    - `flutter test test/core/services/pending_message_retrier_test.dart`
    - `flutter test test/core/lifecycle/handle_app_paused_test.dart`
    - `flutter test test/features/push/`
    - targeted `go test` runs for touched relay-server files/ packages
    - `xcodebuild test -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 16'`
  - If any required verification cannot be run, report the exact blocker and do not silently accept the section.

  Smoke / manual QA rules
  - Use the smoke scenarios/checklists in Sections 1, 3, 5, and 6 as required evidence.
  - Record which smoke scenarios were executed versus deferred.
  - If a smoke scenario cannot be executed in this environment, record it as an explicit residual risk/deferral rather than silently ignoring it.

  Acceptance rules
  - Accept a section only if:
    - required behavior is present
    - required tests and verification are green, or any non- green item is explicitly understood and accepted
    - reviewer verdict is `PASS`
    - scope stayed inside the section boundary
    - residual risks, deferrals, and next-section prerequisites are written down
  - In auto-advance mode, advance only if the current section is accepted and the next section is inside the allowed sequence.

  Output format
  - Keep the orchestration output compact and structured with:
    - `Mode`
    - `Plan path`
    - `Active phase`
    - `Allowed phase sequence`
    - `Entry gates`
    - `Phase contract`
    - `Implementation audit`
    - `Reviewer prompt`
    - `Fix prompt` when needed
    - `Gap ledger`
    - `Acceptance decision`
    - `Next state`
    - `Next phase trigger`
  - Findings must come first, ordered by severity.
  - If no blocking findings exist for a section, say that explicitly and still list residual risks/testing gaps if any remain.

  Commit rule
  - If a commit is requested and code changes were needed, use: `fix(chat): harden <accepted section label>`

  Assumptions
  - Assume the plan has already been implemented.
  - Begin with Section 4 only, then auto-advance through the allowed sequence without pausing for intermediate approval unless a section is genuinely blocked.




  =================================


  Use `$libp2p-phase-orchestrator` in `auto-advance` mode. If unavailable, follow the same controller
  workflow manually with fresh isolated implementer/reviewer/fixer agents per phase and parallel
  implementers only for disjoint within-phase slices.

  Authoritative plan
  - `docs/qa/BIDI_FEED_ORBIT_TDD_PLAN.md`

  Goal
  - Implement the full BiDi cross-surface plan end-to-end so mixed Arabic/English user content is
  rendered, entered, previewed, and persisted correctly across Feed, Orbit, 1:1 chat, groups,
  announcements, posts, comments, share previews, intro/contact-request surfaces, and notification
  passthrough.
  - Fix the real bugs, not just isolated widgets: sender/receiver parity, open/collapsed parity,
  timestamp/footer layout, optimistic/send parity, and sanitization policy must all be correct.
  - Implement the whole plan, not just the original Feed and Orbit regressions.

  Phase model
  - Treat each top-level `Phase` in the plan as one controller phase.
  - Treat each phase’s internal bullets, tests, policy decisions, and addendum items as internal slices
  that must be completed before that phase is accepted.
  - Do not stop mid-phase for approval unless genuinely blocked.

  Controller mode
  - `auto-advance`

  Start phase
  - `Phase 0: Create stable BiDi-specific test surfaces`

  Allowed phase sequence
  1. `Phase 0: Create stable BiDi-specific test surfaces`
  2. `Phase 1: Lock collapsed Feed direction behavior`
  3. `Phase 2: Lock Orbit direction behavior`
  4. `Phase 3: Replace the fragile expanded Feed timestamp layout`
  5. `Phase 4: Prove open/collapsed parity on Feed`
  6. `Phase 5: Cover group and announcement summary previews`
  7. `Phase 6: Cover posts main text input/render`
  8. `Phase 7: Cover post comments and sanitization parity`
  9. `Phase 8: Cover 1:1 send-side sanitization and optimistic parity`
  10. `Phase 9: Cover share preview and share-boundary policy`
  11. `Phase 10: Cover intro/contact-request renderers and notification passthrough`
  12. `Phase 11: Align helper and sanitization policy across domains`

  Stop condition
  - Stop on the first blocked phase or when `Phase 11` is accepted.
  - Do not pause for intermediate approval between phases.
  - Do not start anything beyond `Phase 11` unless I explicitly request it later.

  Agent orchestration rules
  - Use fresh isolated agents per phase.
  - Phase progression must stay sequential. Do not work on multiple phases at once.
  - Inside a phase, parallelize only when slices have disjoint edit zones.
  - Before coding each phase, explicitly decide whether that phase should use one implementer or
  multiple parallel implementers, and justify the choice from file ownership.
  - If parallel implementers are used, give each agent explicit ownership of a non-overlapping file set.
  - Use one reviewer agent for the whole phase after integration.
  - Use a separate fixer agent only if the review finds blocking gaps.
  - Close or discard all phase agents before advancing to the next phase.
  - Review may use additional read-only explorers in parallel for disjoint audit areas, but the final
  verdict must be a single phase-level `PASS`, `NEEDS WORK`, or `FAIL`.
  - Do not orchestrate overlapping implementers on the same widget, helper, or test file.

  Parallelism guidance
  - Likely parallelizable when file ownership stays disjoint: `Phase 0`, `Phase 5`, `Phase 6`, `Phase
  7`, `Phase 8`, and `Phase 10`.
  - Likely better as single-implementer phases because edits converge tightly: `Phase 3`, `Phase 4`, and
  `Phase 11`.
  - Do not force parallelism if the current phase depends on a shared helper refactor or the same test
  fixture.

  Implementation requirements
  - Follow strict `RED -> GREEN -> REFACTOR` for every production phase.
  - Record the exact failing tests or commands observed before production edits.
  - Implement only the current phase, plus the minimum compatibility changes required to compile.
  - Add or update only the tests required by the current phase.
  - Use the plan’s dedicated BiDi test files as the main entry point instead of the known noisy baseline
  in `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`.
  - Preserve the plan’s explicit policy decision points, especially share-boundary sanitization and
  cross-domain helper usage.
  - Do not rely on ambient text direction for user content unless the current phase explicitly proves
  that exception is intentional.

  Acceptance rules
  - Accept a phase only if the required behavior is implemented, the required tests are green, the
  reviewer returns `PASS`, and there is no later-phase scope leakage.
  - If the reviewer returns `NEEDS WORK` or `FAIL`, run a focused fixer agent only on the reviewer’s
  blocking gap ledger, then re-review before advancing.

  Deliverables per accepted phase
  - Acceptance note
  - Files changed
  - Tests added or updated
  - RED evidence
  - GREEN verification
  - Residual risks or deferrals
  - Next-phase trigger