# TOM-004 - Group Transport-Census Evidence Boundary Plan

Status: accepted

## Planning Progress

- 2026-05-29 21:17:17 CEST - Evidence/planning/reviewer/arbiter completed locally under the batch fallback. Files inspected: `Test-Flight-Improv/99-transport-observability-and-metrics-session-breakdown.md`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/core/bridge/bridge_group_helpers.dart`, and focused group send tests. Decision/blocker: current group send evidence proves aggregate live fanout and durable inbox custody, but it does not expose a trustworthy direct/relay/wifi transport-family label. Next action: add accepted-boundary regression evidence without adding a speculative production metrics hook.

## real scope

Close the group diagnostics boundary for the current architecture. Add only evidence that current group flow events expose aggregate fanout safely. Do not wire group send/drain/listener paths into direct, relay, wifi, inbox, or unknown transport buckets unless an existing terminal signal proves that transport family.

## closure bar

TOM-004 is closed when:
- The group send stack has been inspected for current safe transport-family signals.
- Current group diagnostics evidence is recorded as aggregate fanout/custody rather than direct/relay/wifi transport family.
- A focused group regression proves flow-event diagnostics expose fanout evidence without message text, message-derived previews, peer IDs, or transport identity labels.
- No production `TransportMetrics` hook is added from speculative group fields such as `transportPeerId`.

## source of truth

- Active session contract: TOM-004 in `Test-Flight-Improv/99-transport-observability-and-metrics-session-breakdown.md`.
- `lib/features/groups/application/send_group_message_use_case.dart` owns terminal group send behavior and flow-event fanout evidence.
- `lib/core/bridge/bridge_group_helpers.dart` owns current bridge result shape for group publish/reliable send helpers.
- `test/features/groups/application/send_group_message_use_case_test.dart` owns focused group send regression evidence.

## session classification

`evidence-gated`

The safe implementation decision depends on current code evidence. The session is accepted by proving the boundary and avoiding invented transport labels.

## exact problem statement

The source doc found no explicit group-message `TransportMetrics` census surface. The group stack contains `transportPeerId` identity fields and publish/inbox evidence, but those fields do not prove whether delivery used direct, relay, wifi, inbox fallback, or unknown transport family. Counting them in the shared transport mix would make diagnostics less trustworthy.

## files and repos to inspect next

- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`

## step-by-step implementation plan

1. Inspect group send, drain, listener, and bridge helper result shapes for an existing terminal direct/relay/wifi/inbox label.
2. If no safe transport-family signal exists, avoid production `TransportMetrics` wiring from identity or fanout fields.
3. Add a focused group send test proving flow-event diagnostics carry aggregate fanout/custody evidence only.
4. Run the focused group test by name.
5. Record the accepted difference for TOM-005 closure.

## exact tests and gates to run

```bash
flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "group send diagnostics expose fanout evidence without transport identity labels"
```

Final hygiene:

```bash
git diff --check
```

## accepted differences / intentionally out of scope

- No group production hook increments direct, relay, wifi, inbox, or unknown `TransportMetrics` buckets from `transportPeerId`, `topicPeers`, or inbox custody fields.
- No group routing, bridge protocol, relay privacy, or analytics exporter changes are included.
- A future group transport-family census requires a real terminal signal from the native/bridge layer or an explicit product/protocol change.

## Execution Verdict

Verdict: accepted.

Landed TOM-004 evidence:
- Added `group send diagnostics expose fanout evidence without transport identity labels` to `test/features/groups/application/send_group_message_use_case_test.dart`.
- The test proves group send flow events expose `topicPeers`, `expectedRecipientCount`, `liveFanoutState`, `inboxStored`, `inboxPending`, and `recipientReceiptClaimed`.
- The test rejects message text, message-derived previews, transport identity keys, sender peer IDs, and recipient peer IDs from the captured diagnostics payload.
- No production `TransportMetrics` group hook was added because current group fields do not prove direct/relay/wifi transport family.

Tests/gates:
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "group send diagnostics expose fanout evidence without transport identity labels"` passed.

Residuals: future group transport-family census remains intentionally out of scope until a trustworthy bridge/native signal exists.
