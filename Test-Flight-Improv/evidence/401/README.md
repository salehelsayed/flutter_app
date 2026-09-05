# Plan 401 evidence — caller-side ringback tone (2026-09-05)

| File | What it proves |
|---|---|
| `dart_ringback_red_2026-09-05.txt` / `dart_ringback_green_2026-09-05.txt` | coordinator (9) + channel port (6): RED on missing types, GREEN 15/15 |
| `kotlin_ringback_red_2026-09-05.txt` / `kotlin_ringback_green_2026-09-05.txt` | `MknoonOutgoingCallRingbackTest` (4) + `MknoonCallNativeBridgeRingbackTest` (2): RED unresolved references, GREEN with the whole call package (122 tests) |
| `swift_ringback_red_2026-09-05.txt` / `swift_ringback_green_2026-09-05.txt` | CallKit controller ×5 + bridge ×1: RED build errors, GREEN lifecycle 52/52 and bridge 12/12 |
| `dart_affected_2026-09-05.txt` | `tdd_context.py affected` set (composition, graph diagnostics, live-call guard + new files): 92/92 |
| `dart_ringback_channel_contract_red_2026-09-05.txt` / `…_green_…` | device finding: the port used an unserved channel; RED on the missing per-platform factories, GREEN 93/93 with the cross-language source census |
| `dart_ringback_handle_red_2026-09-05.txt` / `…_green_…` | second device finding: the port sent the Dart call id, the native bridge only resolves the signaling handle; RED on the missing resolver, GREEN with the resolved handle on the wire |
| `host_1to1_batch_ringback_2026-09-05.txt` | host `1to1` batch with the new gate entries: PASS, 194 paths, 3323 passed / 4 skipped |

Device proof rows are listed in `../401-voice-call-ringback-tone-tdd-plan.md` (user-driven; not yet run).
