# Old message notification investigation — 10 September 2026

Implementation and deployment are recorded in
[implementation-and-deployment.md](implementation-and-deployment.md). The
findings below describe the incident before that change.

The strongest supported explanation is an upgrade-history gap in yesterday's
relay notification guard. The guard is deployed and active, but it cannot
recognize an earlier notification that never entered its new admission ledger.
The user confirmed that the old message was originally sent before last night.
Current source reproduces how its first retry after deployment can therefore
receive another notification, while the app correctly rejects the duplicate.

This corrects the operational status in yesterday's `fix.md`: that document's
"local and has not been deployed" statement is now stale.

## Live evidence

All table times are Berlin time (UTC+02:00), 10 September 2026.

| Time | Evidence |
| --- | --- |
| 02:36:21 | Current relay process starts. Startup confirms Redis, durable=true, prefix=relay:. Binary SHA-256 is `47005789a3014a840859863546c689f096394017687077ddaf03430c9ce274ec`. |
| 09:57:27 | Inbox stores from sender prefix `12D3KooWEJwJ5K6rvmE4` to recipient prefix `12D3KooWHyiSmJVcHfQo`; direct admission reports `acquired`, then provider send succeeds on attempt 1. |
| 09:57:41 | Same adjacent sender/recipient store, another `acquired`, another successful provider send on attempt 1. |
| 09:57:55 | User's iPhone app on build 1.0.1+116 reports one incoming message with `committed=true` and three incoming attempts with `reason=duplicate`, `committed=false`. |
| 09:57:56 | User-owned NSE diagnostic reports include two receive/process sequences and two presentation-pending records. These are server receipt times for uploaded events, not precise notification display times. |
| 09:58:01 | All four earlier incoming attempts report acknowledged receipt callbacks. |

The current Flutter run `bfcc66fb-1dc8-4699-93b3-7d4b7c45d179` was matched
inside the relay to the same authenticated owner as yesterday's already-verified
user run. Only boolean match results were exported; owner digests and private
owner maps were not exported. The current other endpoint did not match the
friend from yesterday's separate incident. This investigation does not assume
that yesterday and today involved the same friend.

Across the retained startup-to-investigation journal, the new guard reports
seven acquisitions and no admission failure or duplicate-suppression records.
Two belong to 08:34 Berlin, the rest to the current exchange. Successful
provider sends in the incident window used attempt 1; the second notification
was not evidenced as an internal transient-provider retry.

## Why yesterday's fix misses this case

`go-relay-server/direct_message_dispatch_admission.go:31` constructs an exact
notification identity from authenticated sender, recipient and message event.
Legacy envelopes additionally include canonical ciphertext identity. The ledger
is separate from inbox custody because acknowledgement removes custody and a
later immutable replay receives a new custody ID.

`go-relay-server/group_message_dispatch_admission.go:244` acquires a Redis claim
with `SET NX` and expiry. An absent key means the provider attempt is eligible.
`go-relay-server/server_bootstrap.go:172` wires the direct ledger into production.
There is no historical notification backfill in this startup wiring.

`go-relay-server/inbox.go:512` checks the ledger at the iOS provider boundary.
After successful provider acceptance, the claim remains for seven days. Thus:

1. Old message was notified before this ledger existed; its key is absent.
2. Sender recovery retries the old envelope after the guard is deployed.
3. The first retry acquires a claim and emits another rich alert.
4. Further exact retries within the retained claim's lifetime are suppressed.

Yesterday's existing tests begin by notifying the original message through the
new guard. They prove replay suppression when the original claim exists,
including across service recreation; they do not prove historical migration.

The iOS rich path processes the pushed ciphertext itself, rather than loading
an unrelated older inbox item: `ios/NotificationService/NotificationService.swift:118`
and `NotificationPreviewResolver.swift:714`. An ordinary recognized duplicate
still keeps its trusted text with passive presentation and no sound
(`NotificationService.swift:264`, `NotificationPreviewResolver.swift:369`).
App-level `committed=false` does not cancel an already dispatched rich alert.

## Limits

The journal deliberately has no message-ID-to-provider-event join. Consequently
the two provider sends cannot be individually mapped to the displayed new and
old text. The timing, user-confirmed age, authenticated app duplicate evidence,
and deterministic upgrade scenario strongly support the history gap; they do
not prove the identity of the exact old notification. The current iOS public
diagnostics record presentation handoff, not actual OS display.

The diagnostic run projection is untruncated. Global retained diagnostics have
invalid-record and cumulative client-loss counters, so missing records cannot
prove that a path never ran. No live device reproduction was performed.

## Remaining correction boundary

Zero repeated rich-notification cards requires deciding eligibility before
provider dispatch. The current relay ledger needs exact, authenticated terminal
knowledge for previously received/read message events, including historical
events, or the notification route must defer creation of an OS alert until the
recipient has made that decision. NSE text/sound/passive handling alone cannot
guarantee cancellation of an OS-owned rich notification.

A blanket cutoff for messages older than deployment would also suppress valid
late delivery and is not an appropriate fix. No production code, relay state,
service, app installation, messages, or notifications were changed here.

## Evidence and validation

- `relay-incident.log`: bounded relay incident journal and running binary identity.
- `relay-deployment-and-admission.log`: startup history, durable backend, admission outcomes and counters.
- `diagnostics-owner-linkage.json`: boolean linkage to the previously verified user.
- `diagnostics-receiver-run.json`: current user Flutter run; 174 events, no timeline truncation.
- `receiver-message-summary.json`: compact incoming/outgoing terminal timeline.
- `diagnostics-user-push.json`: schema-validated user-owned push events across processes.
- `current-replay-regressions.log`: existing `^TestDirectNotification` tests pass on `GOTOOLCHAIN=go1.25.0` (13.774 seconds).
- `predeployment_repro_output.txt`: isolated regression intentionally fails for missing historical admission, observing `[old, new, old]`; the retained-history control passes with `[old, new]`. Both suppress a further exact old replay after admission is populated. This uses actual Redis inbox custody/ACK and recreated services, with the exact pre-patch gateway for the historical provider send.
- `predeployment_reproduction.md`: repeatable Go-overlay command and explanation. The intentionally failing reproduction remains outside the production/test tree.

Graphify navigation was verified against current source; no graph output is
treated as runtime proof. Relay branch query `f50b526a5c8745d2`, digest
`fb60f10b764fa63d`; iOS branch query `f9ba29281f8240b4`, digest
`3ba3f9e9493966c9`. Only incident evidence and an isolated reproduction overlay
were created, so app-code impact analysis and graph refresh are not applicable.
