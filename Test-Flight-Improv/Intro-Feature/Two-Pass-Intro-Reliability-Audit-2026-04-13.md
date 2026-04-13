# Two-Pass Intro Reliability Audit

Date: 2026-04-13

## Goal

Review the Intro feature against the current client and relay code, compare its evidence quality to the stronger Group Chat audit style, run two sequential review-agent passes, and keep only the findings that still make sense after critical validation. The bar here is reliability, not overengineering.

## What Was Checked

- First agent pass: broad Intro reliability and coverage audit against current code/tests.
- Second agent pass: adversarial re-audit to challenge pass one and look for overstatements.
- Local validation against the repo after both passes.
- Current gate run: `./scripts/run_test_gates.sh intro` passed on 2026-04-13.

## Final Verdict

The Intro feature is not missing core coverage. The reported split-brain symptom
where one side keeps showing `Waiting for X to accept` is already covered and
should stay closed unless new contradictory evidence appears.

The three narrow follow-ups identified by this audit were all closed on
2026-04-13:

1. Avatar eventual settlement now has intro-owned later recovery proof.
2. Relay-side action-distinct intro dedupe now has direct Go-side regression
   coverage.
3. Intro persistence now has direct migration and helper-query hardening tests
   at the SQL seam.

No remaining item from this audit needs to stay open on current repo evidence.

## Accepted Findings

### 1. Avatar eventual settlement gap was closed on 2026-04-13

Classification: `closed with code and tests`

What landed:

- [handle_mutual_acceptance_use_case.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/introduction/application/handle_mutual_acceptance_use_case.dart:71) creates the contact first, then starts avatar download as fire-and-forget work.
- The repo now also has intro-owned later settlement through
  [expire_old_introductions_use_case.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/introduction/application/expire_old_introductions_use_case.dart:1),
  so Feed/Orbit-triggered intro recovery can retry avatar settlement for an
  already-created mutual-acceptance contact that still lacks an avatar.
- Direct proof now exists in:
  - [create_connection_on_mutual_acceptance_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart:1)
  - [expire_old_introductions_use_case_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/introduction/application/expire_old_introductions_use_case_test.dart:1)
- `flutter test --no-pub test/features/introduction/application`,
  `./scripts/run_test_gates.sh intro`, and
  `./scripts/run_test_gates.sh baseline` were rerun green.

Practical call:

- Keep this closed unless new evidence shows intro-owned later settlement is
  still insufficient.
- Do not widen this into a generic global avatar subsystem without new product
  requirements.

### 2. Relay-side action-distinct dedupe proof landed on 2026-04-13

Classification: `closed with direct regression proof`

What landed:

- The client already does the right thing. [introduction_outbound_delivery.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/introduction/application/introduction_outbound_delivery.dart:24) builds action-scoped envelope IDs, and [introduction_outbound_delivery_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/introduction/application/introduction_outbound_delivery_test.dart:96) proves `send` and `accept` on the same intro get distinct transport IDs.
- The payload layer also encodes that contract in [introduction_payload.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/introduction/domain/models/introduction_payload.dart:208).
- The relay gap is now closed by direct Go regressions in
  [inbox_dedup_test.go](/Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server/inbox_dedup_test.go:1)
  proving that two different intro actions for the same `introductionId` both
  survive dedupe when they carry distinct action-scoped top-level
  `messageId` values.
- The targeted relay dedupe rerun and the full `go-relay-server` test suite
  both passed on 2026-04-13.

Why this matters:

- If relay-side intro dedupe ever regressed back toward plain `introductionId` semantics, the exact class of lost-accept / stale-waiting failures users complain about could reappear.

### 3. Direct intro migration/helper coverage gap was closed on 2026-04-13

Classification: `closed with persistence hardening tests`

What landed:

- There is real coverage already:
  - [full_migration_chain_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/core/database/integration/full_migration_chain_test.dart:806) proves a migrated schema can persist introductions and deferred responses.
  - [introduction_repository_impl_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/introduction/domain/repositories/introduction_repository_impl_test.dart:6) proves delete-time cleanup of staged responses and outbox rows.
  - [046_pending_introduction_responses_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/core/database/migrations/046_pending_introduction_responses_test.dart:1) exists as a dedicated intro migration test.
- The direct intro-specific DB surface is now covered by:
  - [intro_migrations_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/core/database/migrations/intro_migrations_test.dart:1)
  - [intro_db_helpers_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/core/database/helpers/intro_db_helpers_test.dart:1)
- Those new suites directly verify:
  - intro migration `019`
  - key-column migrations `022` and `023`
  - the `already_connected` table rebuild in `025`
  - intro outbox migration `047`
  - pending intro visibility and badge-count truth
  - deferred-response replay ordering
  - retryable intro outbox selection
- `flutter test --no-pub test/core/database` was rerun green after the new
  suites landed.

Practical call:

- Keep this closed unless future schema changes add new intro DB seams without
  direct proof.
- This hardening improves persistence confidence without reopening the feature
  or adding new runtime behavior.

## Rejected Or Down-Ranked Findings

### 1. The split-brain `Waiting for X to accept` symptom is not an open coverage gap

Classification: `already covered / not a real gap`

Why it stays closed:

- [introduction_multi_node_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/introduction/integration/introduction_multi_node_test.dart:1057) covers split-brain mutual acceptance healing after reconnect.
- [intro_row_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/introduction/presentation/widgets/intro_row_test.dart:143) covers the waiting label itself.
- [orbit_wired_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/orbit/presentation/screens/orbit_wired_test.dart:1556) covers startup repair for stale persisted mutual-acceptance rows.

### 2. Missing top-level `integration_test/` Intro journey is only a shape gap

Classification: `missing test gap`, but down-ranked

Why I am not treating it as a real reliability hole:

- There is no intro-specific top-level `integration_test/` file in the current tree.
- But stronger proof already exists in host-side and simulator-backed surfaces:
  - [introduction_multi_node_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/introduction/integration/introduction_multi_node_test.dart:1057)
  - [intro_wiring_smoke_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/introduction/integration/intro_wiring_smoke_test.dart:510)
  - repo-local simulator flows referenced in the Intro docs and smoke harnesses

Practical call:

- Do not spend time creating a top-level `integration_test/` file just for symmetry if the existing proof remains green and trusted.

### 3. Sender-local persistence, silent intro recovery, and intro push routing should stay closed

Classification: `already covered / not a real gap`

Closed evidence:

- Sender-local persistence:
  - [send_introduction_use_case.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/introduction/application/send_introduction_use_case.dart:168)
  - [send_introduction_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/introduction/application/send_introduction_test.dart:305)
- Silent intro recovery / contact-request crossover:
  - [recover_intro_contact_request_use_case_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/contact_request/application/recover_intro_contact_request_use_case_test.dart:86)
  - [contact_request_listener_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/contact_request/application/contact_request_listener_test.dart:884)
- Intro push routing and fallback:
  - [introduction_listener_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/introduction/application/introduction_listener_test.dart:216)
  - [background_push_notification_fallback_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/push/application/background_push_notification_fallback_test.dart:213)
  - [intro_notification_orbit_route_test.dart](/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/push/application/intro_notification_orbit_route_test.dart:78)

## Recommended Next Step

No follow-up from this audit is currently required.

Reopen only if:

1. New contradictory evidence appears against the now-closed avatar, relay, or
   intro persistence seams.
