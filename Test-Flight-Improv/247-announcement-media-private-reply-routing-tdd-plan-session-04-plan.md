# Plan 247 Session 04 — Independent Host Acceptance And Closure Synchronization

Status: accepted
Source: `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-breakdown.md` Session 04
Run mode: acceptance-only
Classification: host-only independent aggregate acceptance and documentation closure
Dependency: satisfied — Plan 247 Sessions 01–03 are accepted and closed; Session 03 has accepted post-fix QA, `fix_passes=1`, behavior-fix count `0`, exactly one post-QA incremental Graphify refresh, and an accepted separate Closure Review

## Planning Progress

| Time | Role / phase | Evidence or decision | Next action |
|---|---|---|---|
| 2026-07-12 | Evidence Collector | Read `AGENTS.md`, the Graphify skill, the complete Plan-247 source/breakdown/decision and Session-01/02/03 plans, current gate definitions and executable registrations, `00-INDEX.md`, the announcement audit/closure reference, and current dirty-tree status. | Freeze an acceptance-only contract without reopening accepted Sessions 01–02 or Session 03's recorded RED history. |
| 2026-07-12 | Graphify TDD grounding | The compact TDD query for Plan 247 Session 04 anchored on `FullScreenTypedMediaViewer` with `confidence=anchored`; it surfaced the expected group/direct/shared-viewer owners and focused proof candidates. Graph freshness reported a concurrent stale `lib/main.dart`, so current source, tests, and scripts were verified directly. | Treat the graph as a shortlist. Do not refresh it in this documentation-only session. |
| 2026-07-12 | Dependency audit | Session 03 is `accepted` / `closed`. Fresh post-fix QA accepted with zero blockers at `fix_passes=1` and behavior-fix count `0`. Final evidence is causal `10/10`, Session-02 preservation `6/6`, `groups` `1,951/1,951`, `1to1` `1,963/1,963`, `feature-host-all` `751/751`, and completeness `1,179/1,179`. Exactly one post-QA incremental refresh completed at `48,196` nodes / `74,807` edges with a `1,272`-file, `12,416`-named-test, `959`-production-target overlay; the separate Closure Reviewer accepted with zero blockers. | Dependency satisfied. Preserve Sessions 01–03 and proceed only with Session-04 acceptance and closure synchronization. |
| 2026-07-12 | Acceptance planner | The final session owns fresh combined host evidence, independent behavior/privacy QA, narrow stable-document synchronization, and a separate closure review. It owns no new production behavior, test, RED, mutation campaign, migration, transport, native, or device work. | Recapture the live baseline, then execute every literal gate below. |
| 2026-07-12 | Dependency gate verification | The Session-03 plan has `Status: accepted`, `## Execution Result`, `## Closure Audit`, accepted post-fix QA with `fix_passes=1`, exactly one successful post-QA incremental refresh, and an accepted separate Closure Reviewer. The source ledger records the same counts, while the breakdown marks Session 03 `accepted` and Session 04 `execution-ready`. | `PASSED`; Session 04 is execution-ready. No acceptance gate or closure-document edit was run during this readiness update. |
| 2026-07-12 | Independent Plan Reviewer | Initial review rejected four planning defects: the dependency alternation could pass one row alone, the wrong v100 migration fixture displaced the actual account-migration compatibility repair, registration ownership overclaimed the gate-definition doc, and the full analyzer/Go wording contradicted the scoped contract. All four were corrected without running a gate. | Re-review `ACCEPTED` with zero blockers. Execute the literal contract from a fresh immutable baseline. |

## Dependency Gate

Session 04 must not begin merely because Session 03 implementation or a QA fix
pass appears complete. All of the following must be true in the same current
worktree:

```bash
rg -x 'Status: accepted' \
  Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-03-plan.md
rg -q '^## Execution Result$' \
  Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-03-plan.md
rg -q '^## Closure Audit$' \
  Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-03-plan.md
rg -q 'fix_passes=1' \
  Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-03-plan.md
rg -qi 'independent QA.*accepted|final.*QA.*accepted' \
  Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-03-plan.md
rg -qi 'incremental.*refresh.*completed|refresh_arch_graph.sh --incremental.*(passed|completed)' \
  Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-03-plan.md
rg -qi 'closure reviewer.*accepted|separate closure.*accepted' \
  Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-03-plan.md
rg -q '^\| 03 \|.*accepted' \
  Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-breakdown.md
rg -q '^\| 04 \|.*execution-ready' \
  Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-breakdown.md
```

If wording in the accepted Session-03 result differs, inspect the full sections
rather than weakening the semantic gate. A handoff, green test log, or pending
QA verdict is not accepted closure.

## Objective And Acceptance Boundary

Independently accept Plan 247 only if fresh current-tree evidence proves all of
the following together:

1. Only an eligible incoming non-self, non-system announcement image/video
   owned by the current group parent can expose **Message sender**.
2. The exact selected `(sourceMessageId, senderPeerId)` is freshly resolved at
   dispatch. Current message, tombstone authority, announcement group, exact
   membership, exact group-owned visual relationship, current active/unblocked
   contact, and complete opener all fail closed.
3. Bubble and exact-current typed-viewer actions dismiss their transient UI,
   coalesce while resolution/opener work is pending, and open the freshly
   resolved sender exactly once. Sender drift never retargets another contact.
4. Every production group-conversation owner supplies the accepted complete,
   explicit-null, or pass-through opener. `GroupConversationWired` never
   constructs a partial direct route.
5. The real existing `ConversationWired` route opens blank. Opening, waiting,
   cancelling, and returning create zero direct/group send, upload, Forward,
   Bridge/P2P command, payload, durable history, attachment, source-file, or
   announcement state mutation.
6. The exact EN/DE/AR action, unavailable, and route-failure copy remains
   accessible, RTL-safe, privacy-minimized, and truthful.
7. Announcement readers remain unable to compose or quote-reply while
   reactions remain available. Discussion-group Reply and ordinary direct/group
   behavior remain unchanged.
8. Plan-234 private/unsupported/terminal content remains outside both ordinary
   viewers and publishes no ordinary action, metadata, resume, or Message
   sender capability.
9. The request remains exactly two-field, local, and non-serializable; no
   schema, wire, Go/relay, native/device, or delivery contract is introduced.

Any executable counterexample reopens the owning implementation session. This
acceptance session does not patch production or tests and does not manufacture
a new RED history.

## Source Of Truth

Use these authorities in descending order for meaning:

- `Test-Flight-Improv/247-private-reply-decision.md` — immutable accepted
  D-247-01..04 product/privacy contract and exact copy;
- accepted Session-02 and Session-03 Execution Results, QA verdicts, and Closure
  Audits — implementation and causal evidence;
- `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan.md`
  and its session breakdown — final feature and ledger ownership;
- current production, tests, and exact constructor census — executable truth;
- `scripts/run_test_gates.sh`, `scripts/run_host_test_gates.sh`, and
  `Test-Flight-Improv/test-gate-definitions.md` — registration and gate truth.

Current source wins if a stale historical line names an old count or method.
Sessions 01–03 are reopened only by concrete regression evidence, never by
historical status prose that their accepted closure already superseded.

## Exact Session Scope

### Read-only implementation and proof scope

Session 04 independently reviews but does not edit:

- Session-02 request, policy/resolver, deletion-authority interface, and real
  repository implementation;
- Session-03 group screen/wired, context overlay, typed viewer, all five app
  owners, direct/shared-viewer enum consumers, and EN/DE/AR localization;
- all six Plan-247 headline tests, the exact announcement/read-only sentinels,
  Plan-234 viewer/protection sentinels, and the five execution-discovered
  compatibility fixtures;
- both gate scripts and `test-gate-definitions.md`; and
- accepted Session-01/02/03 plans and the immutable decision artifact.

No temporary fault injection or reversible production mutation belongs here.
Session 03 already owns its mutation evidence. Acceptance is a fresh execution
and counterexample review of the restored final candidate.

### Writable documentation allowlist after QA acceptance

Only these records may change in Session 04:

- this Session-04 plan;
- `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan.md`;
- `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-breakdown.md`;
- `Test-Flight-Improv/00-INDEX.md`;
- `Test-Flight-Improv/13-announcement-use-case-audit.md`; and
- `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`.

`247-private-reply-decision.md` is read-only. Gate definitions and scripts are
also read-only unless the registration audit finds a real omission; an omission
is an executable Session-03 closure defect, not permission to silently edit it
here.

## Fresh Execution Baseline And Dirty-Tree Guard

The repository is shared and intentionally dirty. Never reset, stash, revert,
checkout, overwrite, reformat, or attribute unrelated work. The planning-time
status hash predates the accepted Session-03 closure and is not an execution
baseline. Immediately before Session-04 acceptance execution, capture:

```bash
git status --short
git diff --stat
git diff --check
```

Create an ordered manifest over the following immutable acceptance paths:

```bash
readonly PLAN_247_SESSION_04_IMMUTABLE_PATHS=(
  lib/features/groups/application/announcement_private_reply_request.dart
  lib/features/groups/application/announcement_private_reply_policy.dart
  lib/features/groups/domain/repositories/group_message_repository.dart
  lib/features/groups/domain/repositories/group_message_repository_impl.dart
  lib/features/groups/presentation/screens/group_conversation_screen.dart
  lib/features/groups/presentation/screens/group_conversation_wired.dart
  lib/features/conversation/presentation/widgets/message_context_overlay.dart
  lib/shared/widgets/media/media_viewer_item.dart
  lib/shared/widgets/media/full_screen_typed_media_viewer.dart
  lib/features/conversation/presentation/screens/conversation_screen.dart
  lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart
  lib/features/groups/presentation/screens/group_shared_media_library_screen.dart
  lib/main.dart
  lib/features/feed/presentation/screens/feed_wired.dart
  lib/features/orbit/presentation/screens/orbit_wired.dart
  lib/features/groups/presentation/screens/group_list_wired.dart
  lib/features/groups/presentation/screens/create_group_picker_wired.dart
  lib/l10n/app_en.arb
  lib/l10n/app_de.arb
  lib/l10n/app_ar.arb
  lib/l10n/app_localizations.dart
  lib/l10n/app_localizations_en.dart
  lib/l10n/app_localizations_de.dart
  lib/l10n/app_localizations_ar.dart
  test/features/groups/application/announcement_private_reply_request_test.dart
  test/features/groups/application/announcement_private_reply_policy_test.dart
  test/features/groups/application/announcement_private_reply_transport_boundary_test.dart
  test/features/groups/presentation/announcement_private_reply_routing_test.dart
  test/features/groups/presentation/announcement_private_reply_entry_surface_test.dart
  test/features/groups/integration/announcement_private_reply_no_auto_send_test.dart
  test/features/groups/presentation/group_conversation_screen_test.dart
  test/features/groups/presentation/group_conversation_wired_test.dart
  test/features/conversation/presentation/widgets/message_context_overlay_test.dart
  test/shared/widgets/media/full_screen_typed_media_viewer_test.dart
  test/shared/widgets/media/media_viewer_boundary_test.dart
  test/features/conversation/presentation/screens/conversation_screen_test.dart
  test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart
  test/features/groups/presentation/announcement_media_library_viewer_test.dart
  test/features/groups/application/group_received_media_action_policy_test.dart
  test/features/groups/application/group_received_media_actions_test.dart
  test/features/groups/domain/repositories/group_message_repository_impl_test.dart
  test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart
  test/core/media/private_media_protection_coordinator_test.dart
  test/l10n/l10n_integrity_test.dart
  test/features/account_migration/application/account_migration_post_import_behavior_test.dart
  test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart
  test/features/conversation/presentation/screens/conversation_wired_gif_test.dart
  test/features/conversation/presentation/screens/conversation_wired_offline_send_ux_test.dart
  test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart
  scripts/run_test_gates.sh
  scripts/run_host_test_gates.sh
  Test-Flight-Improv/test-gate-definitions.md
  Test-Flight-Improv/247-private-reply-decision.md
  Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-01-plan.md
  Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-02-plan.md
  Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-03-plan.md
)

plan_247_session_04_manifest() {
  local file_path file_status
  for file_path in "${PLAN_247_SESSION_04_IMMUTABLE_PATHS[@]}"; do
    test -e "$file_path"
    file_status="$(git status --porcelain=v1 -- "$file_path")"
    printf '%s\t' "${file_status:-CLEAN}"
    shasum -a 256 "$file_path"
  done
}

plan_247_session_04_manifest > /tmp/plan-247-session-04-immutable-before.txt
shasum -a 256 /tmp/plan-247-session-04-immutable-before.txt
```

Before QA and again after documentation synchronization, rerun the identical
function and require byte-for-byte equality with the execution baseline:

```bash
plan_247_session_04_manifest > /tmp/plan-247-session-04-immutable-after.txt
cmp -s /tmp/plan-247-session-04-immutable-before.txt \
  /tmp/plan-247-session-04-immutable-after.txt
```

If an immutable path moves concurrently, stop before writing it, capture both
hashes/status values, identify its owner, and restart the affected acceptance
commands from a fresh stable baseline. Do not overwrite the movement or call it
Session-04 work.

## Literal Acceptance Gates

Run every command from the Flutter repository root after the dependency gate
passes. These are fresh Session-04 results; Session-03 counts are historical
comparison evidence, not substitutes.

```bash
# 1. Accepted decision and exact immutable contract.
test -s Test-Flight-Improv/247-private-reply-decision.md
rg -x 'Status: accepted' Test-Flight-Improv/247-private-reply-decision.md
for id in D-247-01 D-247-02 D-247-03 D-247-04; do
  rg -q "$id" Test-Flight-Improv/247-private-reply-decision.md
done
! rg -n 'TBD|TO DECIDE|unresolved|pending approval' \
  Test-Flight-Improv/247-private-reply-decision.md

# 2. Session-02 fail-closed application boundary.
flutter test \
  test/features/groups/application/announcement_private_reply_request_test.dart \
  test/features/groups/application/announcement_private_reply_policy_test.dart \
  test/features/groups/application/announcement_private_reply_transport_boundary_test.dart

# 3. Session-03 rendered routing, owner census, and real-route no-send proof.
flutter test \
  test/features/groups/presentation/announcement_private_reply_routing_test.dart \
  test/features/groups/presentation/announcement_private_reply_entry_surface_test.dart \
  test/features/groups/integration/announcement_private_reply_no_auto_send_test.dart

# 4. Full group/context/viewer preservation at the changed surfaces.
flutter test \
  test/features/groups/presentation/group_conversation_screen_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart
flutter test \
  test/features/conversation/presentation/widgets/message_context_overlay_test.dart
flutter test \
  test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  test/shared/widgets/media/media_viewer_boundary_test.dart
flutter test \
  test/features/conversation/presentation/screens/conversation_screen_test.dart \
  test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart \
  test/features/groups/presentation/announcement_media_library_viewer_test.dart

# 5. Exact announcement and tombstone preservation sentinels.
flutter test test/features/groups/application/group_received_media_action_policy_test.dart \
  --plain-name 'GMA-13 announcement member and admin get core media capabilities without reply while qa stays empty'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'announcement readers stay read-only for compose but still keep reaction entry'
flutter test test/features/groups/application/group_received_media_actions_test.dart \
  --plain-name 'GMA-04 locally tombstoned parent refuses single Save and Share even when its row survives'
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart \
  --plain-name 'local delete still blocks same-id replay'

# 6. Plan-234 ordinary/private viewer and protection preservation.
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart
flutter test test/core/media/private_media_protection_coordinator_test.dart

# 7. Execution-discovered compatibility fixtures retained by Session 03.
flutter test test/features/account_migration/application/account_migration_post_import_behavior_test.dart
flutter test \
  test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_gif_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_offline_send_ux_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart

# 8. Generated localization parity. Generation must leave immutable hashes unchanged.
flutter gen-l10n
flutter test test/l10n/l10n_integrity_test.dart

# 9. Exact registration and inventory truth.
for suite in \
  announcement_private_reply_request_test.dart \
  announcement_private_reply_policy_test.dart \
  announcement_private_reply_transport_boundary_test.dart \
  announcement_private_reply_routing_test.dart \
  announcement_private_reply_entry_surface_test.dart \
  announcement_private_reply_no_auto_send_test.dart; do
  rg -qF "$suite" scripts/run_test_gates.sh
done
for suite in \
  announcement_private_reply_routing_test.dart \
  announcement_private_reply_entry_surface_test.dart \
  announcement_private_reply_no_auto_send_test.dart; do
  rg -qF "$suite" Test-Flight-Improv/test-gate-definitions.md
done
rg -qF 'test/features/groups/integration/announcement_private_reply_no_auto_send_test.dart' \
  scripts/run_host_test_gates.sh
./scripts/run_host_test_gates.sh 1to1 --list

# 10. Fresh proportional named/family gates.
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh feature-host-all
./scripts/run_test_gates.sh completeness-check

# 11. Scoped formatter/analyzer.
dart format --output=none --set-exit-if-changed \
  lib/features/groups/application/announcement_private_reply_request.dart \
  lib/features/groups/application/announcement_private_reply_policy.dart \
  lib/features/groups/domain/repositories/group_message_repository.dart \
  lib/features/groups/domain/repositories/group_message_repository_impl.dart \
  lib/features/groups/presentation/screens/group_conversation_screen.dart \
  lib/features/groups/presentation/screens/group_conversation_wired.dart \
  lib/features/conversation/presentation/widgets/message_context_overlay.dart \
  lib/shared/widgets/media/media_viewer_item.dart \
  lib/shared/widgets/media/full_screen_typed_media_viewer.dart \
  lib/features/conversation/presentation/screens/conversation_screen.dart \
  lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart \
  lib/features/groups/presentation/screens/group_shared_media_library_screen.dart \
  lib/main.dart \
  lib/features/feed/presentation/screens/feed_wired.dart \
  lib/features/orbit/presentation/screens/orbit_wired.dart \
  lib/features/groups/presentation/screens/group_list_wired.dart \
  lib/features/groups/presentation/screens/create_group_picker_wired.dart \
  lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart \
  lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_ar.dart \
  test/features/groups/application/announcement_private_reply_request_test.dart \
  test/features/groups/application/announcement_private_reply_policy_test.dart \
  test/features/groups/application/announcement_private_reply_transport_boundary_test.dart \
  test/features/groups/presentation/announcement_private_reply_routing_test.dart \
  test/features/groups/presentation/announcement_private_reply_entry_surface_test.dart \
  test/features/groups/integration/announcement_private_reply_no_auto_send_test.dart \
  test/features/account_migration/application/account_migration_post_import_behavior_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_gif_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_offline_send_ux_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart
flutter analyze --no-fatal-infos \
  lib/features/groups/application/announcement_private_reply_request.dart \
  lib/features/groups/application/announcement_private_reply_policy.dart \
  lib/features/groups/domain/repositories/group_message_repository.dart \
  lib/features/groups/domain/repositories/group_message_repository_impl.dart \
  lib/features/groups/presentation/screens/group_conversation_screen.dart \
  lib/features/groups/presentation/screens/group_conversation_wired.dart \
  lib/features/conversation/presentation/widgets/message_context_overlay.dart \
  lib/shared/widgets/media/media_viewer_item.dart \
  lib/shared/widgets/media/full_screen_typed_media_viewer.dart \
  lib/features/conversation/presentation/screens/conversation_screen.dart \
  lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart \
  lib/features/groups/presentation/screens/group_shared_media_library_screen.dart \
  lib/main.dart \
  lib/features/feed/presentation/screens/feed_wired.dart \
  lib/features/orbit/presentation/screens/orbit_wired.dart \
  lib/features/groups/presentation/screens/group_list_wired.dart \
  lib/features/groups/presentation/screens/create_group_picker_wired.dart \
  test/features/groups/application/announcement_private_reply_request_test.dart \
  test/features/groups/application/announcement_private_reply_policy_test.dart \
  test/features/groups/application/announcement_private_reply_transport_boundary_test.dart \
  test/features/groups/presentation/announcement_private_reply_routing_test.dart \
  test/features/groups/presentation/announcement_private_reply_entry_surface_test.dart \
  test/features/groups/integration/announcement_private_reply_no_auto_send_test.dart \
  test/features/account_migration/application/account_migration_post_import_behavior_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_gif_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_offline_send_ux_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart
bash -n scripts/run_test_gates.sh scripts/run_host_test_gates.sh
git diff --check
```

The default scoped analyzer output may also be captured to preserve the exact
accepted info-level baseline, but no warning/error and no new
Plan-247 finding is allowed. `--no-fatal-infos` must exit zero. Any generator,
formatter, or analyzer-driven immutable-file movement is a blocker and routes
back to Session 03; do not keep a generated or formatted fix in Session 04.

Full `host-all` is deliberately absent. It runs once for the completed Wave-1
batch and again at final rollout/release closure, not as a Plan-247 per-session
gate. `core-host-all`, reliability-sim, performance, device/simulator, native,
and Plan-247-specific Go/relay gates are outside this host-only callback/navigation
slice. The mandatory `groups` script still runs its two pre-existing group
forwarding Go sentinels; those are inherited family preservation, not a new
Plan-247 Go proof claim.

## Failure And Flake Interpretation

- Every first failure is `pending_triage`. Record the command, failing test,
  first useful output, current path hashes, and relevant dirty ownership before
  any rerun.
- An exact-name rerun may classify a timing-sensitive failure, but it does not
  replace the required fresh complete suite or named/family gate. The complete
  command must subsequently pass from the same stable candidate.
- A compile error, causal assertion failure, surviving privacy bypass, missing
  registration, changed immutable hash, analyzer warning/error, or generator
  delta is blocking.
- If a production/test defect is attributable to Plan 247, stop Session 04 and
  reopen Session 03 with a causal counterexample, bounded fix pass, affected
  focused/family reruns, fresh independent QA, one new post-QA incremental
  refresh for that new coherent code state, and closure. Then restart Session
  04 from a fresh baseline.
- If an unrelated concurrent owner moves a shared file, do not classify it as
  Plan 247 and do not overwrite it. Wait for a stable handoff, recapture the
  immutable manifest, and rerun every affected command.

## Independent QA Contract

After every literal gate passes and immutable hashes match, obtain a fresh
read-only QA verdict from a reviewer independent of the Session-03 executor,
its QA-fix operator, and the Session-04 gate operator. QA must inspect current
source and test behavior, not merely accept persisted counts.

QA must explicitly audit:

- D-247-01..04 and exact EN/DE/AR copy;
- render-time plus dispatch-time fresh authority, selection-time sender
  retention, exact current viewer item, and corrupt-owner fail-closed behavior;
- dismissal order, one wired cross-surface latch, and separate unavailable vs
  opener-failure feedback;
- all five production opener owners and absence of partial direct construction;
- the real routed blank composer and zero direct/group delivery, upload,
  Forward, Bridge/P2P, persistence, or source mutation before/during/after
  cancellation;
- announcement read-only/reaction preservation, discussion Reply preservation,
  and Plan-234 private/terminal viewer denial;
- all registrations, literal gates, analyzer result, immutable manifest, and
  shared dirty-tree attribution; and
- absence of schema/version, payload/serializer, transport, native/device, Go,
  relay, actual PiP, or cross-plan scope.

Session-04 executable `fix_passes` is fixed at `0`. A behavior/test correction
cannot be made here; it reopens Session 03 as described above. QA acceptance
authorizes documentation synchronization but is not final closure by itself.

## Closure-Document Contract

After independent QA accepts, update only the documentation allowlist:

- **Source Plan 247:** set `Status: accepted`; add exact fresh Session-04
  commands/counts, QA verdict, `fix_passes=0`, accepted differences, and final
  boundary; check all applicable done criteria.
- **Session breakdown:** set overall status accepted/closed; mark Session 03
  accepted from its own closure and Session 04 accepted; preserve the four-part
  decomposition and full-host-all Wave-1 ownership.
- **Session-04 plan:** append `## Execution Result` and `## Closure Audit` with
  baseline/final immutable hashes, exact counts, analyzer/scope evidence, QA
  and separate closure-review verdicts, and the explicit no-refresh statement.
- **`00-INDEX.md`:** change only Plan 247's stale `Evidence-gated` row to
  `Accepted`. Describe explicit **Message sender** as fresh fail-closed,
  callback-only navigation to an existing active sender contact's blank 1:1
  composer, with no copied context, announcement write, or automatic send.
  Remove only the stale Wave-0 sentence claiming Plan 247 lacks an approved
  routing policy; preserve every other plan's status and residual.
- **Announcement use-case audit:** add a narrowly titled
  `Explicit Message Sender Navigation` subsection. It must classify the action
  as reader-initiated cross-lane navigation, not an announcement send, Reply,
  Forward, contact-introduction, or transport capability; name the fresh
  resolver, current-item/owner checks, blank composer, zero-send proof, and
  preservation of read-only compose plus reactions.
- **Announcement closure reference:** add a narrowly titled
  `Explicit Message Sender Is Outside Announcement Delivery` subsection. It
  must record that Plan 247 changes no announcement writer authorization,
  delivery/retry/status, Go/relay, or native/device closure claim and that
  regressions reopen Plan 247 only for its local eligibility/navigation/no-send
  boundary.
- **Decision artifact, gate scripts, gate definitions, and accepted prior
  session plans:** keep byte/status identical.

Do not create a new announcement matrix and do not rewrite unrelated historical
closure prose.

## Literal Documentation Gates

Run after the candidate documentation synchronization and before the separate
closure review:

```bash
rg -x 'Status: accepted' \
  Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan.md
rg -x 'Status: accepted' \
  Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-breakdown.md
rg -q '^## Execution Result$' \
  Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-04-plan.md
rg -q '^## Closure Audit$' \
  Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-04-plan.md
rg -n '^\| \[247-announcement-media-private-reply-routing-tdd-plan.md\].*\| Accepted \|' \
  Test-Flight-Improv/00-INDEX.md
! rg -n 'Plan 247 lacks approved private-reply routing policy' \
  Test-Flight-Improv/00-INDEX.md
rg -q '^## Explicit Message Sender Navigation$' \
  Test-Flight-Improv/13-announcement-use-case-audit.md
rg -q '^### Explicit Message Sender Is Outside Announcement Delivery$' \
  Test-Flight-Improv/21-announcement-reliability-closure-reference.md
rg -qF 'reader-initiated cross-lane navigation' \
  Test-Flight-Improv/13-announcement-use-case-audit.md
rg -qF 'blank composer' \
  Test-Flight-Improv/13-announcement-use-case-audit.md
rg -qi 'zero.*send' \
  Test-Flight-Improv/13-announcement-use-case-audit.md
rg -qF 'read-only compose' \
  Test-Flight-Improv/13-announcement-use-case-audit.md
rg -qF 'reactions' \
  Test-Flight-Improv/13-announcement-use-case-audit.md
rg -qF 'changes no announcement writer authorization' \
  Test-Flight-Improv/21-announcement-reliability-closure-reference.md
rg -qF 'delivery/retry/status' \
  Test-Flight-Improv/21-announcement-reliability-closure-reference.md
rg -qF 'Go/relay' \
  Test-Flight-Improv/21-announcement-reliability-closure-reference.md
git diff --check
```

## Separate Closure Review

After documentation gates pass, obtain a separate read-only Closure Reviewer.
The reviewer must reconcile:

1. Session-03 accepted closure and its one post-QA incremental refresh;
2. every fresh Session-04 focused/family/static result and any flake triage;
3. exact immutable before/after equality and the six-file documentation
   allowlist;
4. accepted D-247 semantics and no overclaim about unknown contacts, copied
   context, sending, transport, device, or announcement reliability;
5. source, breakdown, index, audit, closure reference, and Session-04 status;
6. unchanged decision, tests, production, scripts, and gate definitions; and
7. retained Wave-1 ownership of full `host-all`, availability-bounded device
   proof, and final rollout Graphify refresh.

At most two documentation-only correction passes are allowed. Each uses
`apply_patch`, reruns the literal documentation gates and immutable comparison,
and obtains another closure-review verdict. A behavior/test correction is not a
documentation pass and must reopen Session 03.

Session 04 becomes accepted only after the separate Closure Reviewer says
`ACCEPTED` with zero blockers and the verdict is persisted in this file.

## Graphify Cadence

The anchored compact Graphify query already supplied planning context. Session
03 owns the single post-QA incremental refresh for its coherent app-code
change. Session 04 changes documentation only, so it runs no `affected`,
incremental, or full refresh. The final Wave-1 rollout retains its own final
Graphify refresh after all remaining plans and aggregate proof close.

## Strict Non-Goals

- No production or test implementation, new RED, mutation campaign, or
  Session-03 history rewrite.
- No migration, schema, DB version/v101, SQL/helper, Plan-238, or persisted
  route/draft field.
- No group/announcement send, Reply, reaction, reporting, Forward, media
  download/egress, actual PiP, or contact-introduction behavior change.
- No Bridge/P2P, Go, relay, payload/wire, notification, native/platform, or
  device/simulator work or proof.
- No Plan-234, Plan-249, Plan-247 Session-03, or excluded-plan implementation.
- No full `host-all`, `core-host-all`, reliability-sim, performance, device,
  native, or additional Plan-247-specific Go/relay gate. The existing `groups`
  family's two Go sentinels remain part of that mandatory script.
- No Graphify refresh.

## Done Criteria

- [x] Session 03 is accepted and closed with fresh final QA, `fix_passes=1`,
  exactly one post-QA incremental refresh, and a separate accepted closure
  review.
- [x] A fresh stable immutable manifest is captured and matches after all gates
  and documentation work.
- [x] Session-02 focused boundary and Session-03 routing/owner/no-send suites
  pass from the current candidate.
- [x] Full changed-surface, announcement/tombstone, Plan-234 protection,
  compatibility, and l10n sentinels pass.
- [x] Registrations, host inventory, `groups`, `1to1`, justified
  `feature-host-all`, and completeness all pass freshly.
- [x] Formatter, scoped analyzer, script syntax, and diff hygiene
  pass under the exact accepted info-level interpretation.
- [x] Fresh independent QA accepts with executable `fix_passes=0`.
- [x] Source, breakdown, index, audit, closure reference, and this plan agree on
  accepted Plan 247 and its callback-only blank-composer/no-send boundary.
- [x] Decision, production, tests, scripts, gate definitions, and accepted prior
  session plans remain byte/status identical to execution start.
- [x] Separate closure review accepts after no more than two documentation-only
  correction passes.
- [x] No Session-04 Graphify refresh runs; full `host-all`, device proof, and
  final refresh remain Wave-1-owned.

## Plan-Review Self-Audit

Verdict: **sufficient and execution-ready as an acceptance-only contract**.

- Dependency is structural and executable: current Session 03 is not mistaken
  for accepted closure merely because its fix-pass tests are green.
- Scope is minimal: zero code/test/mutation ownership, six writable closure
  records, immutable decision/gates, and an exact dirty-tree hash guard.
- Behavior coverage is complete across Session 02 policy, Session 03 bubble and
  exact-current viewer routing, five owners, real blank route, localization,
  announcement preservation, and Plan-234 private-viewer protection.
- Fresh gates are proportional and literal: focused suites, `groups`, `1to1`,
  justified `feature-host-all`, host inventory, completeness, scoped analyzer,
  formatter, syntax, and diff. Full `host-all` remains Wave-1-owned.
- Boundary proof is host-causal: no device, native, migration, payload, or
  Plan-247-specific Go/relay leg is invented for callback-only local navigation;
  the inherited `groups` Go sentinels remain honest family preservation.
- Failure handling cannot hide implementation work: any executable defect
  reopens Session 03 with causal proof, fresh QA, refresh, and closure before
  Session 04 restarts.
- Documentation ownership is exact and maintenance-safe: index, audit, and
  closure reference record the feature without changing announcement write or
  reliability semantics.
- QA and closure are independent phases: behavior/privacy QA precedes docs; a
  separate reviewer accepts the synchronized durable record.
- Graphify cadence is correct: planning query used, no docs-only refresh, final
  Wave-1 refresh retained.

No structural planning or dependency blocker remains. Incremental command
counts and analyzer info fingerprints are execution evidence and must be
recorded from the then-current stable tree rather than copied from Session 03.

## Execution Progress

| Time | Phase | Evidence | Result / next |
|---|---|---|---|
| 2026-07-12 | planning | Full source/breakdown/decision and Session-01/02/03 review; current scripts/gate definitions; stable announcement docs; anchored compact Graphify query; live status check | Plan authored only. No test, analyzer, gate, mutation, production/test edit, documentation closure edit, or Graphify refresh ran. Session 04 initially remained prerequisite-blocked on Session-03 QA/refresh/closure. |
| 2026-07-12 | dependency release | Session-03 accepted Execution Result and Closure Audit; post-fix QA accepted at `fix_passes=1` / behavior-fix count `0`; causal `10/10`, Session-02 `6/6`, groups `1,951/1,951`, 1to1 `1,963/1,963`, feature-host-all `751/751`, completeness `1,179/1,179`; exactly one post-QA incremental refresh; accepted separate Closure Reviewer; synchronized source/breakdown ledgers | Dependency gate `PASSED`. Session 04 changed from `prerequisite-blocked` to `execution-ready`. No acceptance gate, production/test edit, closure-document synchronization, or Graphify refresh ran during this readiness update. |
| 2026-07-12 | independent plan review | Complete S04 contract, exact scripts/docs/fixtures, analyzer scope, family cadence, immutable guard, QA/docs/closure ownership, and Graphify exclusions | Initial review rejected four concrete contract defects; corrected plan re-review `ACCEPTED` with zero blockers. No acceptance gate or refresh ran during review. |
| 2026-07-12 | execution preflight correction | Dependency checks, status/stat/diff hygiene, and first immutable-manifest invocation | Dependency and diff checks passed, but the manifest function failed before writing a baseline because zsh reserves `path` for command lookup and `status` as read-only. Renamed only those plan-local variables to `file_path` / `file_status`. No test, analyzer, family gate, production/test edit, closure-document synchronization, or Graphify refresh ran; recapture the baseline from scratch. |
| 2026-07-12 | superseded acceptance attempts | Immutable baseline `aa2229d36393347ec770b35362836f058e2864830329856636bb6bc35dcd388b`; complete focused/preservation/named evidence through fresh groups `1,951`, 1to1 `1,963`, and download `68`; four feature-host attempts | Attempt 1 stopped at command 141 on transient `pub.dev` DNS and its exact file passed 3/3. Attempt 2 stopped at command 89 on the known late-scrub assertion; one exact rerun failed, the next passed, and a complete download rerun passed 68/68. Attempt 3 passed command 89 but stopped at command 121 on transient DNS; its exact file passed 30/30. Attempt 4 again stopped at command 89. Repeated causal failure made the old flaky classification untenable and concretely reopened the owning Plan-234 Session-03 proof seam. No partial feature-host attempt is acceptance evidence. |
| 2026-07-12 | upstream Plan-234 Session-03 proof repair | Deterministic optional late-scrub test seam; exact `10/10`; download+cleanup `83/83`; 1to1 `1,963`; groups `1,951` plus Go; inventory `88`; completeness `1,179`; clean static checks; Graphify affected; fresh independent QA and separate closure review | A probability-based polling candidate was independently rejected. Final repair preserves production defaults and was accepted at `post_closure_fix_passes=2`, followed by exactly one additional post-QA incremental Graphify refresh. Plan-234 Session 03 remains accepted/closed. The former Session-04 immutable baseline is intentionally invalid and cannot be compared or credited; restart Session 04 from a fresh baseline with executable `fix_passes=0`. |
| 2026-07-12 | fresh focused and named acceptance | Decision checks; Session-02 `6/6`; Session-03 `10/10`; group screen/wired `266/266`; overlay `15/15`; typed viewer/boundary `8/8`; conversation/shared/announcement viewers `81/81`; GMA-13, reader, tombstone, and local-delete sentinels; Plan-234 viewer `16/16`; protection `9/9`; account migration `3/3`; wired compatibility `34/34`; l10n `2/2`; groups `1,951/1,951` plus both inherited Go sentinels | All focused/preservation evidence passed. No Plan-247 production or behavioral correction was required; Session-04 executable `fix_passes=0`. |
| 2026-07-12 | feature-host completion under shared-tree movement | Original 751-file inventory covered through supported `--start-at` resumes after one SQLite checksum transfer failure and one DNS failure. Two aggregate-only failures—the group voice pre-persist 10-second timeout and push one-time initialization call history—passed exact-name reruns `1/1`. Three concurrently added feature suites shifted the inventory to 754; a 22-suite current-state delta passed `282/282`, then current items `684..754` passed and emitted the final scope success marker. | Independent QA accepted this honest segmented evidence as `754/754`; it is not represented as one uninterrupted run. No completed file was replayed merely to conceal infrastructure or aggregate-only failures. |
| 2026-07-12 | current named/static acceptance | Current `./scripts/run_test_gates.sh 1to1` after Plan-256 registration passed `1,977/1,977`; host inventory `89`; completeness `1,185/1,185`; registrations, script syntax, and `git diff --check` passed. Scoped analyzer exited zero with 13 info-only findings: the eight accepted Session-03 findings plus five initializing-formal infos byte-for-byte present in HEAD; zero warning/error and no Plan-247 finding. | Current gate-definition movement affected only `1to1`, so `groups` was not duplicated. Static and scope evidence accepted. |
| 2026-07-12 | bounded Session-03 formatting repair | The first no-write formatter found four retained compatibility fixtures. Temp-copy review proved formatting-only line wrapping/indentation; repository formatting changed only those four tests; their combined batch passed `34/34`; the literal 32-file formatter rerun passed `0 changed`. | Fresh independent repair QA `ACCEPTED` with zero blockers. Historical Session-03 `fix_passes=1` stays unchanged; separate `post_closure_fix_passes=1`, post-closure behavior-fix count `0`. No Graphify query/refresh is attributable because symbols, names, registrations, and behavior are unchanged. |
| 2026-07-12 | final immutable and independent QA | Post-repair v4 before/after manifest matched at `23bc0470903a17861ff43067765e8fb0ee275fc14442cd127df904a1ab382a0b`, `cmp=0`. After the owning Session-03 repair amendment, the final Session-04 reconciliation baseline is v5 `804e40579d0ca86898bae247a96ac04c771b2f048980f089e38cce4a6f032d2b`. Independent behavior/privacy QA inspected current source/tests and returned `ACCEPTED` with zero blockers. | Synchronize only the closure-document allowlist, rerun literal documentation gates and v5 equality, then obtain a separate Closure Reviewer. No Session-04 Graphify refresh. |
| 2026-07-12 | closure-document candidate | Source, breakdown, Session-04 plan, index, announcement audit, and closure reference synchronized; the owning Session-03 plan contains the separate formatting-repair amendment. Literal documentation gates and `git diff --check` passed. Two documentation-only correction passes placed required `zero-send`, `blank composer`, and `changes no announcement writer authorization` phrases on single searchable lines. Final v5 before/after manifest remained `804e40579d0ca86898bae247a96ac04c771b2f048980f089e38cce4a6f032d2b`, `cmp=0`. | Candidate is ready for the separate read-only Closure Reviewer; correction-pass budget is exhausted but no blocker remains. |

## Execution Result

Verdict: `accepted` / `closed`.

- D-247-01..04 are implemented as a callback-only **Message sender** action with exact English `Message sender`, German `Absender anschreiben`, and Arabic `مراسلة المرسل` copy. Eligibility and dispatch both reload current authority, preserve the selected sender, require the exact current group-owned visual item, and fail closed for stale, corrupt, protected, missing, self, unknown, archived, or blocked rows.
- Transient UI dismisses before navigation or feedback, one wired latch coalesces concurrent taps, and unavailable versus opener-failure feedback remains distinct. The five production owners are exactly three complete openers, one explicit null, and one pass-through; no partial direct route exists.
- The real route opens an existing fully wired blank `ConversationWired` and sends, uploads, forwards, persists, or publishes nothing. Direct/group send, upload, Forward, P2P/Bridge, histories, source files, announcement read-only state, and reactions remain unchanged; discussion Reply and Plan-234 private/terminal viewer denial are preserved.
- Final executable evidence is groups `1,951/1,951` plus inherited Go sentinels, current 1to1 `1,977/1,977`, feature-host `754/754` by supported segmented resume plus delta `282/282`, completeness `1,185/1,185`, host inventory `89`, formatting-repair files `34/34`, formatter `32/0`, analyzer exit zero with 13 accepted infos and no warning/error, registrations/syntax/diff clean, and independent QA `ACCEPTED` at Session-04 `fix_passes=0`.
- No migration/schema/v101, payload/serializer, group or announcement write, Go/relay production, native/device, actual PiP, Session-05/06, or excluded-plan work is claimed. Full `host-all`, availability-bounded device proof, and the final Graphify refresh remain Wave-1-owned.

## Closure Audit

- Current classification: `closed`.
- Behavior/privacy QA: `ACCEPTED` with zero blockers; Session-04 executable `fix_passes=0`.
- Separate Session-03 formatting repair QA: `ACCEPTED`; `post_closure_fix_passes=1`, post-closure behavior-fix count `0`; no additional Graphify refresh.
- Immutable authority: final v5 before/after manifests both equal `804e40579d0ca86898bae247a96ac04c771b2f048980f089e38cce4a6f032d2b`; `cmp=0` after documentation synchronization.
- Documentation correction passes used: `2`, both phrase-wrap-only and within the allowed limit.
- Separate read-only Closure Reviewer verdict: `ACCEPTED` with zero blockers. It reconciled the retained logs, current immutable files, QA accounting, callback-only/no-send boundary, synchronized ledgers, and Wave-1 residual ownership. Session 04 and Plan 247 are closed.
