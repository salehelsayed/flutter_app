# Plan 403 evidence — relay pending-call slot release (2026-09-05)

| File | What it proves |
|---|---|
| `capacity_refusal_device_evidence_2026-09-05.txt` | the failing call: two ended-but-unacknowledged Pixel calls inside their 40 s lifetime, the third invite refused with `CALL_RECIPIENT_CAPACITY`, and the caller's cleanup loop on `CALL_UNAUTHORIZED` |
| `dart_pending_slot_red_2026-09-05.txt` | RED: 3 failing — the headless session acks nothing on a terminal page (2), cancel throws on `CALL_UNAUTHORIZED` (1); 23 passing |
| `dart_pending_slot_green_2026-09-05.txt` | GREEN: 26/26 across both suites |
| `dart_pending_slot_affected_2026-09-05.txt` | GREEN: 161/161 across the affected suites (composition, signaling service, pre-presentation admission, runtime, production adapters, direct/mailbox convergence, executor, headless entrypoint) |

Deployed 2026-09-05 17:42Z (`docker-ws/deploy_three_phones_403_result.txt`): iPhones `1.0.0-4d87486a2.d7.flowlog.t260905193900`, Pixel `1.0.0-4d87486a2.d7.t260905193900`, captures `docker-ws/deploy-captures/fresh-260905194144/`. Device proof: pending (see plan §Gates).
