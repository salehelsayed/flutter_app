# group system publish durable replay session breakdown

## Run-mode snapshot

- Active mode: standard
- Degraded local continuation: not explicitly allowed
- Source proposal/matrix doc: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-matrix.md`
- Source bug: direct group system publishes can bypass the durable replay retry contract used by normal group sends.
- Source status vocabulary: `Planned`, `Accepted`, `Blocked`, `Closed`.
- Overall closure bar for this one-session rollout: one small Dart helper exists, one representative direct system-message publish path that owns a local timeline row uses it, and failed replay storage leaves retryable `inboxRetryPayload` state on that timeline row. Remaining direct callers stay explicit follow-up inventory unless a later acceptance pass reopens them.
- Final verdict policy: `closed` when GSPR-001 is accepted with focused Flutter tests plus scoped format/analyze evidence.

## Recommended plan count

1

## Session ledger

| Session | Status | Plan path | Owner files | Required gates |
| --- | --- | --- | --- | --- |
| GSPR-001 | accepted_with_explicit_follow_up | `Test-Flight-Improv/Group-Chat-Feature/group-system-publish-durable-replay-session-GSPR-001-plan.md` | `lib/features/groups/application/group_system_publish_use_case.dart`; representative caller `lib/features/groups/application/dissolve_group_use_case.dart`; focused tests under `test/features/groups/application/` | RED/GREEN helper/caller selectors passed; focused helper/dissolve files passed; required retry selectors passed; scoped `dart analyze` passed; scoped `dart format --set-exit-if-changed` passed; `git diff --check` passed |

## Closure Progress

- 2026-05-23 21:29:58 CEST - Completion Auditor simulated locally per `implementation-closure-audit-orchestrator`. Evidence inspected: GSPR-001 plan final verdict, current breakdown ledger, `git status --short`, landed helper file, `dissolveGroup(...)` diff, helper/caller tests, and `rg` direct publish inventory. Classification: `accepted_with_explicit_follow_up`.
- 2026-05-23 21:29:58 CEST - Closure Writer updated only this breakdown artifact. GSPR-001 is accepted for the session closure bar because `publishGroupSystemMessage(...)` landed, `dissolveGroup(...)` is migrated as the representative direct system-publish caller, and parent-confirmed focused tests plus scoped format/analyze/whitespace checks passed.
- 2026-05-23 21:29:58 CEST - Closure Reviewer checked the wording against the landed scope. This closure does not claim every direct system-publish site is migrated and does not convert the final program verdict; parent final acceptance remains pending.
- 2026-05-23 21:32:31 CEST - Final program acceptance pass inspected the breakdown ledger and GSPR-001 final execution verdict. All sessions are resolved; final program verdict is `accepted_with_explicit_follow_up` because the closure bar is met and the remaining direct system-publish callers are explicit non-blocking follow-up inventory.

Closed for GSPR-001:

- Direct system publish helper exists and uses the existing low-level group publish plus signed offline replay retry payload flow.
- Failed replay storage for a supplied local timeline row now leaves retryable `inboxStored: false` / `inboxRetryPayload` state.
- `dissolveGroup(...)` is migrated and proved as the representative caller that persists the helper-returned timeline row.
- Existing normal `sendGroupMessage(...)`, Go `GroupPublish`, relay protocol, schema, migrations, and broad retry architecture remain out of scope and unchanged for this session.

Residual-only / explicit follow-up:

- Other direct system publish callers remain inventory-only follow-up for a later session: `accept_pending_group_invite_use_case.dart`, `broadcast_voluntary_leave_use_case.dart`, `create_group_with_members_use_case.dart`, and `rotate_and_distribute_group_key_use_case.dart`.
- Optional broad confidence gate `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` failed with broad existing/unrelated group integration failures (`+288 -13`) outside this host-only closure bar. Reopen only if a focused GSPR helper/caller/retry proof regresses or if final acceptance determines the broad failures are newly caused by this session.

Still-open blockers for this session: none.

## Ordered session breakdown

### GSPR-001 - Durable replay helper for direct system publishes

Classification: accepted_with_explicit_follow_up

Dependency state: satisfied.

Scope:

- Add a small Dart application-layer helper for group system messages that:
  - publishes via existing `callGroupPublish`;
  - builds/stores the existing signed group offline replay envelope for recipient peers;
  - when a timeline `GroupMessage` and `GroupMessageRepository` are supplied, records `inboxStored`/`inboxRetryPayload` so `retryFailedGroupInboxStores` can retry failed replay storage.
- Migrate representative direct system-message publish paths that already own a timeline row and recipient list to use the helper.
- Keep normal `sendGroupMessage` unchanged.
- Keep Go `GroupPublish` unchanged.

Out of scope:

- Do not add a new outbox table, cursor protocol, relay endpoint, or Go inbox-store coupling.
- Do not change normal user-message send semantics.
- Do not refactor all group UI flows beyond the direct system-publish call sites needed by this session.
- Do not edit broad matrix docs owned by the parallel gap-closure session.

## Downstream execution path

1. `GSPR-001` reusable TDD plan exists at the plan path and is `execution-complete`.
2. Execution completed for the helper, representative caller, and focused tests.
3. Current-session closure completed in this artifact as `accepted_with_explicit_follow_up`.
4. Final program acceptance is persisted below as `accepted_with_explicit_follow_up`.

## Final program verdict

accepted_with_explicit_follow_up

Final acceptance note: the one-session rollout is resolved. Reopen only if focused GSPR helper/caller/retry proof regresses, if one of the inventoried direct system-publish callers is promoted from explicit follow-up into scope, or if the broad `groups` gate failures are later proven to be caused by this session.
