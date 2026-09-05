# Plan 403 evidence — relay pending-call slot release (2026-09-05)

| File | What it proves |
|---|---|
| `capacity_refusal_device_evidence_2026-09-05.txt` | the failing call: two ended-but-unacknowledged Pixel calls inside their 40 s lifetime, the third invite refused with `CALL_RECIPIENT_CAPACITY`, and the caller's cleanup loop on `CALL_UNAUTHORIZED` |
| `dart_pending_slot_red_2026-09-05.txt` | RED: 3 failing — the headless session acks nothing on a terminal page (2), cancel throws on `CALL_UNAUTHORIZED` (1); 23 passing |
| `dart_pending_slot_green_2026-09-05.txt` | GREEN: 26/26 across both suites |
| `dart_pending_slot_affected_2026-09-05.txt` | GREEN: 161/161 across the affected suites (composition, signaling service, pre-presentation admission, runtime, production adapters, direct/mailbox convergence, executor, headless entrypoint) |

Device proof: pending the user's "deploy" (see plan §Gates).
