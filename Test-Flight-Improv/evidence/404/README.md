# Plan 404 evidence — Android headless decline reply (2026-09-05)

| File | What it proves |
|---|---|
| `dart_decline_reply_red_2026-09-05.txt` | RED: the four Dart suites fail to compile on the new contract (`mode`, `HeadlessCallAdmissionMode`, `declineReplySender`, `signal`, `HeadlessCallDeclineReplyTransmitter`, coordinator-free `CallSignalingService`), then the direct transport test on `BridgeCallDirectTransport` |
| `dart_decline_reply_green_2026-09-05.txt` | GREEN: 154/154 across entrypoint, headless session, decline reply transmitter, signaling service, bridge direct transport, mailbox client, graph diagnostics, composition, live-call guard, production adapters |
| `dart_decline_reply_handle_red_2026-09-05.txt` / `…_handle_green_…` | device finding (b): the reply must ride the invite's mailbox handle, not the call id; RED compile on the new `callHandle` parameter, GREEN 101/101 |
| `decline_reply_device_proof_2026-09-05.txt` | DEVICE PROOF: two killed-app declines ended the iPhone call 2.5 s / 2.6 s after the tap (9.2 s / 9.6 s before (c2)); Pixel timeline per step |
| `kotlin_foreground_reply_order_red_2026-09-05.txt` / `…_order_green_…` | device finding (c2): cleanup's STOP dropped the reply's START queued behind it; the controller now asks the hook before cleanup and keeps the service, the service re-enters admission after ringing; RED 2 failed of 141, GREEN service 8/8 controller 32/32 |
| `kotlin_foreground_reply_red_2026-09-05.txt` / `…_green_…` | device finding (c): the reply ran at background priority (10 s); it now runs under the call foreground service and releases it when done; RED compile on `releaseDeclineReply`, GREEN worker 14/14 |
| `kotlin_decline_reply_red_2026-09-05.txt` | RED: `compileDebugUnitTestKotlin` fails on `enqueueDeclineReply`, `INPUT_MODE`, `HeadlessCallAdmissionMode`, `mode`, `onDeclineWithoutOwner` |
| `kotlin_decline_reply_green_2026-09-05.txt` | GREEN: `scripts/test/run_call_native_unit_tests.sh` BUILD SUCCESSFUL; call package 129 tests, 0 failures (worker 14 incl. 3 new, lifecycle controller 32 incl. 1 new) |

Device capture that motivated the plan: `docker-ws/deploy-captures/fresh-260905194144/` (Pixel decline at 19:44:14 local, no reject, iPhone cancel at 19:44:19).

Deployed 2026-09-05 18:19Z (`docker-ws/deploy_three_phones_404_result.txt`): iPhones `1.0.0-d5c404b87.d8.flowlog.t260905201506`, Pixel `1.0.0-d5c404b87.d8.t260905201506`, captures `docker-ws/deploy-captures/fresh-260905201908/`. First device run (18:23Z) refuted: the reject reached the iPhone on both legs but was dropped because it rode the call id as its mailbox handle (plan §Device finding (b)); fixed, device proof pending the next deploy. Redeployed 18:35Z (three phones, `fresh-260905203527`) and 18:45Z (Pixel only, `1.0.0-ff3ada35a.d24.t260905204414`, foreground-service reply) and 19:00Z (Pixel only, `1.0.0-9577caeca.d20.t260905205811`, foreground service kept through the reply).
