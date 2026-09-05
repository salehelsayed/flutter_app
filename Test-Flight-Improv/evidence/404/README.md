# Plan 404 evidence — Android headless decline reply (2026-09-05)

| File | What it proves |
|---|---|
| `dart_decline_reply_red_2026-09-05.txt` | RED: the four Dart suites fail to compile on the new contract (`mode`, `HeadlessCallAdmissionMode`, `declineReplySender`, `signal`, `HeadlessCallDeclineReplyTransmitter`, coordinator-free `CallSignalingService`), then the direct transport test on `BridgeCallDirectTransport` |
| `dart_decline_reply_green_2026-09-05.txt` | GREEN: 154/154 across entrypoint, headless session, decline reply transmitter, signaling service, bridge direct transport, mailbox client, graph diagnostics, composition, live-call guard, production adapters |
| `dart_decline_reply_handle_red_2026-09-05.txt` / `…_handle_green_…` | device finding (b): the reply must ride the invite's mailbox handle, not the call id; RED compile on the new `callHandle` parameter, GREEN 101/101 |
| `kotlin_foreground_reply_red_2026-09-05.txt` / `…_green_…` | device finding (c): the reply ran at background priority (10 s); it now runs under the call foreground service and releases it when done; RED compile on `releaseDeclineReply`, GREEN worker 14/14 |
| `kotlin_decline_reply_red_2026-09-05.txt` | RED: `compileDebugUnitTestKotlin` fails on `enqueueDeclineReply`, `INPUT_MODE`, `HeadlessCallAdmissionMode`, `mode`, `onDeclineWithoutOwner` |
| `kotlin_decline_reply_green_2026-09-05.txt` | GREEN: `scripts/test/run_call_native_unit_tests.sh` BUILD SUCCESSFUL; call package 129 tests, 0 failures (worker 14 incl. 3 new, lifecycle controller 32 incl. 1 new) |

Device capture that motivated the plan: `docker-ws/deploy-captures/fresh-260905194144/` (Pixel decline at 19:44:14 local, no reject, iPhone cancel at 19:44:19).

Deployed 2026-09-05 18:19Z (`docker-ws/deploy_three_phones_404_result.txt`): iPhones `1.0.0-d5c404b87.d8.flowlog.t260905201506`, Pixel `1.0.0-d5c404b87.d8.t260905201506`, captures `docker-ws/deploy-captures/fresh-260905201908/`. First device run (18:23Z) refuted: the reject reached the iPhone on both legs but was dropped because it rode the call id as its mailbox handle (plan §Device finding (b)); fixed, device proof pending the next deploy.
