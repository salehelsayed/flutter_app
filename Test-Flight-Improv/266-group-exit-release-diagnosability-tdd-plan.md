# 266 - Group-Exit Failures Must Be Diagnosable In Release Builds (Modification)

Status: planned (v1 authored 2026-07-20; awaiting $tdd-review audit; NOT executed)
Type: modification (diagnosability + bridge-down handling)
Closure tier: unit + widget proof; one release-build on-device verification that the
cause code is user-visible and the diagnostic row is persisted
Boundary triggers: Flutter-only; no relay, bridge, native-handler, or wire-format
production change (the Go `NOT_INITIALIZED` path is consumed, not modified)
Spec: free-text intent — 2026-07-20 debugging session cost: the field failure
("Failed to leave group") carried ZERO information in the release build; diagnosing it
required building and installing a debug binary on the affected phone. Every exit
failure must carry a short cause code in the UI and persist a diagnostic record
readable later.
Grounding: anchors verified at HEAD ad073dd39.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-20 | Planner | flow_event_emitter.dart, main.dart (FDC override), leave use case result type, orbit_wired.dart / group_info_wired.dart / group_list_wired.dart failure sites, go-mknoon/bridge/bridge.go GroupLeaveTopic | Cause taxonomy drafted from existing `cause` threading | Run $tdd-review 266, execute RED-first |

## Source Of Truth
- Spec / intent: inline above
- Gate definitions: scripts/run_test_gates.sh + scripts/run_host_test_gates.sh
- Numbering / index: Test-Flight-Improv/00-INDEX.md

## Session Classification
planning-only (no implementation in this session)

## Exact Problem Statement
1. Release builds log nothing: `flowEventLoggingEnabled = kDebugMode`
   (lib/core/utils/flow_event_emitter.dart:6, gate at :251), overridable only at
   compile time via `FDC_FLOW_LOG` (lib/main.dart:332-342). Field failures are
   invisible.
2. Every exit failure collapses to one string: `group_info_leave_failed` shown for
   `preworkFailed` AND `nativeLeaveFailed` (orbit_wired.dart:3025-3031;
   group_info_wired.dart:471-488 additionally has the full `result.cause` in hand and
   drops it into a release-silent flow event; group_list_wired.dart:857-876 same).
3. A dead Go node (`NOT_INITIALIZED`, go-mknoon/bridge/bridge.go:1977-1980) surfaces
   as the same generic leave failure instead of an "engine not running" state, and no
   recovery is attempted.

## Fix Outline (execution session implements)
1. Cause taxonomy: map the already-threaded `LeaveGroupAndDeleteLocalHistoryResult.cause`
   (use case :26-40) to short stable codes — e.g. EX01 pending-role-sync, EX02
   not-a-member (plan 263), EX03 sign-failed, EX04 envelope-failed (plan 265), EX05
   bridge-not-initialized, EX06 native-leave-rejected, EX07 native-uncertain, EX08
   cleanup-incomplete. Codes are appended to the existing snackbar copy
   ("Failed to leave group (EX05)") — one l10n template, codes not translated.
2. Persisted exit-failure diagnostic: a small bounded store (ring of the last N exit
   failures: ts, groupId prefix, status, code, sanitized cause string — reuse
   `sanitizeFlowEventDetails`, flow_event_emitter.dart:236-248) written on every
   non-left result regardless of build mode, readable from the existing
   settings/diagnostics surface (execution session locates the exact screen).
3. Bridge-down handling: when `cause` is a `BridgeCommandException` with
   `NOT_INITIALIZED`, show engine-down copy instead of the generic string; attempt one
   node re-init + single `group:leave` retry before surfacing (retry is safe:
   `LeaveGroupTopic` is idempotent, go-mknoon/node/pubsub.go:203-215).
4. Optional (decide in execution): a user-facing "enable verbose logs" toggle flipping
   `flowEventLoggingEnabled` at runtime — the variable is already mutable; the FDC
   harness at main.dart:332-342 is precedent. Scope-check log volume/PII with the
   existing sanitizer before adopting.

## RED-First Test Plan
- Unit: each failure status/cause maps to its stable code; unknown causes map to a
  catch-all code, never crash.
- Unit: diagnostic store writes on every non-left result, honors its bound, survives
  reload; sanitizer applied (no key material in stored strings — sensitive-key
  redaction already exists in flow_event_emitter.dart:160-234).
- Widget: snackbar carries the code for preworkFailed vs nativeLeaveFailed vs
  uncertain; NOT_INITIALIZED renders engine-down copy and triggers exactly one retry.
- Preservation: successful-leave UX unchanged; existing snackbar tests updated for the
  template, not duplicated.

## Sibling Open-Sites
- The same collapse-to-one-string pattern exists for other group admin failures
  (role change, dissolve, invite). This plan lands the mechanism; extending the
  taxonomy to those flows is follow-up scope recorded here deliberately.

## Gates
- GROUP_TESTS: ./scripts/run_test_gates.sh groups
- AUTO_FEATURE_HOST: ./scripts/run_host_test_gates.sh feature-host-all
  --batch-flutter --concurrency 4 --reporter failures-only
- Explicit grep-gate registration for new tests; flutter analyze clean.

## Risks / Open Questions
- Codes in user-visible copy: confirm tone with the product copy conventions (keep
  codes small and parenthesized; copy stays reassuring).
- The diagnostic store must not become a second unbounded log — hard bound + sanitizer
  are non-negotiable acceptance criteria.
