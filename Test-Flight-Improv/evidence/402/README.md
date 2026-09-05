# Plan 402 evidence — Android standard call token (2026-09-05)

| File | What it proves |
|---|---|
| `dart_android_call_token_red_2026-09-05.txt` / `…_green_…` | coordinator unit tests: RED on missing types, GREEN 7/7 |
| `dart_android_call_token_wiring_mutation_red_2026-09-05.txt` / `…_wiring_green_…` | composition wiring: mutation RED (graph not calling the coordinator), GREEN |
| `dart_android_call_token_listen_red_2026-09-05.txt` / `…_affected_green_…` | Firebase-less host: RED `[core/no-app]` escaping `start()`, GREEN 86/86 across the affected suites |
| `dart_headless_terminate_red_2026-09-05.txt` / `…_green_…` | second device finding: the terminate's wake rejected the page on the invite row's expiry; RED three `permanentReject`, GREEN 11/11 with per-row binding |
| `kotlin_orphaned_terminal_red_2026-09-05.txt` / `…_green_…` | (c) ended headless call blocked the next presentation: RED two Kotlin tests (`Busy`), GREEN call package |
| `relay_wake_status_mutation_red_2026-09-05.txt` / `relay_wake_receipt_green_2026-09-05.txt` | (d) relay wake outcome on the store receipt, opt-in on the wire |
| `go_wake_receipt_red_2026-09-05.txt` / `…_green_…` | (d) go node + bridge carry the wake outcome |
| `dart_wake_receipt_red_2026-09-05.txt` / `…_green_…` / `dart_wake_receipt_affected_2026-09-05.txt` | (d) Dart client/service/reducer: dispatched wake rings the caller back |
| `host_1to1_batch_wake_receipt_2026-09-05.txt` | closure lane after (b)(c)(d) |

