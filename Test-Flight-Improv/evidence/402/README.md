# Plan 402 evidence — Android standard call token (2026-09-05)

| File | What it proves |
|---|---|
| `dart_android_call_token_red_2026-09-05.txt` / `…_green_…` | coordinator unit tests: RED on missing types, GREEN 7/7 |
| `dart_android_call_token_wiring_mutation_red_2026-09-05.txt` / `…_wiring_green_…` | composition wiring: mutation RED (graph not calling the coordinator), GREEN |
| `dart_android_call_token_listen_red_2026-09-05.txt` / `…_affected_green_…` | Firebase-less host: RED `[core/no-app]` escaping `start()`, GREEN 86/86 across the affected suites |
