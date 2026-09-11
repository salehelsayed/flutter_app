# Old message notification investigation — 9 September 2026

The evidence strongly supports an old message being presented again. The user
confirmed that “that's cool” was sent on 8 September at 21:02 Berlin time, while
the notification was reported on 9 September around 21:30. The remaining unknown
is whether an app retry, delayed push delivery, or iOS notification replay caused
this particular presentation. No message identifier connects the displayed text
to an individual retained push record.

All times below are Berlin time (UTC+02:00).

| Time | Observed evidence |
| --- | --- |
| 8 Sep 21:02 | User confirms original message. Relay stores from the user's peer to the friend's peer at 21:02:05 and 21:02:15; provider success records occur at 21:02:06 and 21:02:15. Logs do not contain text or a message-ID join. |
| 9 Sep 21:02:52 | User's iPhone reconnects. |
| 9 Sep 21:03:07–08 | Relay stores items from user to friend. Three provider successes occur at 21:03:08, with other recipients active in the same second, so individual push attribution is unavailable. |
| 9 Sep 21:03:09–21:31:06 | No recorded provider-accepted push send on this relay. This does not exclude later delivery/display of an earlier push. |
| 9 Sep 21:28:30 | Another user-to-friend inbox item is stored during fanout to contacts, without a recorded push success. A stored inbox item can be control traffic; it does not prove a newly authored chat message. |
| 9 Sep 21:30:18.894 | Friend's iPhone launches build 1.0.1+114. |
| 9 Sep 21:30:19 | Friend connects with seven pending relay inbox items. Her app handles two incoming attempts as duplicates, without a new chat-message commit; receipt callbacks subsequently succeed. |
| 9 Sep 21:30:19–24 | Five other incoming attempts finish with `authority_rejected` and `committed:false`. An unhandled error is also reported at 21:30:19.180. These events cannot be individually matched to the displayed phrase. |

## Peer attribution

The friend's resolved ID is
`12D3KooWG4g99ezcntWcHddJYzTotX8nzLeMNyPZe45ha2S7EMoP`.
The initial supplied prefix contained an extra `4`.

Run `92967673-12f8-41fa-aff7-5b836b90bd72` was matched on the relay to the
friend's authenticated collector partition. Run
`78613d35-9d9c-49c0-baaa-19ed7a22e337` was matched to the user's supplied peer.
Only boolean match results were exported; private owner maps, digests, secrets,
and raw collector records were not exported. Endpoint aliases differ between
operator exports and must not be used as stable identities.

## Source findings

- `ios/NotificationService/NotificationService.swift:258` applies a trusted
  ordinary preview to rich-push duplicates. `NotificationPreviewResolver.swift:375`
  preserves their text while making them silent/passive. Direct chat is included.
- `NotificationPreviewResolver.swift:708` resolves direct preview text from the
  pushed ciphertext with sender/message-ID checks, without a message-age check.
  Notification presentation does not establish that a new chat row was committed.
- `ios/RunnerTests/NotificationPreviewResolverTests.swift:7` asserts that trusted
  duplicate text is retained. `IosNotificationRecoveryTests.swift:1676` represents
  already-read replay as a duplicate with zero badge.
- The fixed-mailbox terminal-duplicate path differs:
  `IosLocalNotificationFinalEffect.swift:724` sanitizes to generic text. Therefore
  rich-push duplicate behavior must not be generalized to every delivery path.
- `handle_incoming_chat_message_use_case.dart:222` maps several distinct results
  to `authority_rejected`: unknown sender, ID/sender mismatch, missing original
  edit, and strict media refusal. This diagnostic label cannot identify a single
  security failure or explain the notification by itself.
- `startup_router.dart:1871` emits `route_pushed` for ordinary startup navigation;
  it is not evidence of a notification tap.

These are current-source findings, not an exact reconstruction of build 114.
The live relay reports a modified source tree at revision `d8b919c5`; its binary
does not match the two local relay artifacts compared. No relay restart or
journal-suppression record was found around the incident. The active process
started at 00:44:01 UTC on 9 September.

## Limits and next causal check

The old text plus owner-linked duplicate processing explains the reported
“notification, but nothing new in chat” shape. It does not establish which
duplicate or rejected attempt caused it. In particular, today's 21:03 push
records cannot be proved to be a retransmission of yesterday's phrase.

The friend's retained native run contains no notification receive/presentation/
tap event. The user's bounded run projection through 21:31 contains no message
events, but a cumulative dropped-event count is nonzero, and not every retry
path is proven covered. Therefore absence of outgoing diagnostics is not proof
that no background replay occurred.

The next corrective investigation should correlate a stable notification event
with original message identity and read/terminal state across sender retry,
relay push, extension presentation, and app ingestion. Verify that an already
read message cannot reappear as a new notification, while preserving delivery
recovery for messages that were never received. No speculative production fix
was applied during this read-only investigation.

## Evidence files

- `relay-yesterday-1858-1906UTC.log`: original-send window.
- `relay-1903-window.log`: today's store/provider timing.
- `relay-peers-1830-2015UTC.log`: today's peer activity.
- `relay-push-1830-2015UTC.log`: today's provider outcomes.
- `diagnostics-peer-linkage.json`: boolean authenticated-owner linkage.
- `diagnostics-ios-run-1930.json`: friend's startup/message attempts, untruncated.
- `diagnostics-friend-native-1930.json`: friend's native events, untruncated.
- `diagnostics-user-run-through-1931.json`: bounded sender run, untruncated.
- `diagnostics-user-run.json`: longer sender export; its timeline is truncated.
- `diagnostics-duplicate-trace.json`: one duplicate's full retained diagnostic trace.
- `relay-push-semantics-audit.md`: relay source, deployed-binary checks, and focused test results.

No services, app code, devices, messages, or notifications were changed. Source
assertions were inspected. Four existing focused relay tests passed, covering
control/key-exchange push suppression, transient retries, and iOS duplicate-store
suppression. No device reproduction was performed.
