# Plan 404 evidence — Android headless decline reply (2026-09-05)

| File | What it proves |
|---|---|
| `dart_decline_reply_red_2026-09-05.txt` | RED: the four Dart suites fail to compile on the new contract (`mode`, `HeadlessCallAdmissionMode`, `declineReplySender`, `signal`, `HeadlessCallDeclineReplyTransmitter`, coordinator-free `CallSignalingService`), then the direct transport test on `BridgeCallDirectTransport` |
| `dart_decline_reply_green_2026-09-05.txt` | GREEN: 154/154 across entrypoint, headless session, decline reply transmitter, signaling service, bridge direct transport, mailbox client, graph diagnostics, composition, live-call guard, production adapters |
| `kotlin_decline_reply_red_2026-09-05.txt` | RED: `compileDebugUnitTestKotlin` fails on `enqueueDeclineReply`, `INPUT_MODE`, `HeadlessCallAdmissionMode`, `mode`, `onDeclineWithoutOwner` |
| `kotlin_decline_reply_green_2026-09-05.txt` | GREEN: `scripts/test/run_call_native_unit_tests.sh` BUILD SUCCESSFUL; call package 129 tests, 0 failures (worker 14 incl. 3 new, lifecycle controller 32 incl. 1 new) |

Device capture that motivated the plan: `docker-ws/deploy-captures/fresh-260905194144/` (Pixel decline at 19:44:14 local, no reject, iPhone cancel at 19:44:19).

Device proof: pending the user's "deploy" (see plan §Gates).
