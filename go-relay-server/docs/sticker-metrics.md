# Anonymous sticker counter contract

Owner decision: Option A, anonymous counts (2026-11-08, Kayan task
`m-6b87664e`). Exact integer totals and nonce retention were selected in
`m-b96f0cb3`; this supersedes the proposed HLL send estimates.

## Design in ten lines

1. Only accepted per-sticker/per-pack daily integer sums are measured; these are client-reported sends, not independently verified deliveries.
2. The app batches a completed UTC day once, with a fresh random UUIDv4 nonce for that batch, never a device/account identifier.
3. Batches survive local restart, retry after failure no more than hourly, and expire after three UTC dates; each day is capped at 1,000 sends.
4. The existing Share app diagnostics switch controls collection/upload; off clears pending local batches, and no diagnostics default is changed.
5. The separate `sticker_usage_v1` libp2p action has only `day`, `nonce`, and `counts`; it does not enter the relay app-diagnostics store.
6. Redis atomically increments totals and records the random nonce for 72 hours, so a lost response/retry does not double count.
7. Daily aggregate hashes expire at UTC day start plus 28 days; the Redis authority survives relay-process restart using the existing Redis persistence policy.
8. No peer/device/IP/report body is stored with totals/nonces; salted abuse-budget tokens exist only in bounded hourly relay RAM, with no exported labels.
9. Admission requires known catalog/reserved IDs, at most 32 KiB/1,000 counts, eight attempts per authenticated actor/hour and 600 globally/hour; hostile claims/Sybil identities are not verified usage.
10. Operators with existing Redis/Prometheus access can read totals; no public read API or phones count exists, and old relays/native builds fail silently on the app side.

## Wire and persistence

```json
{"action":"sticker_usage_v1","day":"2026-11-08","nonce":"7b719404-d2bb-4d98-b3b6-b7be5d8186f1","counts":{"orbit_crew.planet.hello":3}}
```

The native bridge command is `sticker_usage_v1` / `stickerUsageV1`, exported by
Go as `StickerUsageV1`. It sends to the first configured relay only: an ambiguous
write is retried there rather than failed over to another counting authority.
Normal builds must regenerate the Go mobile bindings before compiling the added
Android/iOS dispatch arms. Source tests do not certify an old generated framework.

Only the previous three completed UTC dates are accepted. Unknown/duplicate JSON
fields, unknown sticker IDs, invalid/nonpositive counts and out-of-window dates
are refused. The catalog uses the existing closed enum, whose manifest-equality
test covers `assets/stickers/packs.json`, including `custom` and `unknown`.
Pack IDs are the prefix before the first dot (`custom`/`unknown` stay separate).

With the normal Redis prefix `relay:`, keys are:

- `relay:sticker:day:YYYY-MM-DD`: integer hash fields `total`, `p:PACK`, `s:STICKER`.
- `relay:sticker:nonce:UUID`: value `1`, expires 72 hours after first acceptance; no timestamp, peer, IP, counts or body accompanies it.

Both keys are updated by one Lua operation after type/numeric preflight. A
storage failure is retryable. Redis is the authoritative aggregate snapshot:
there is deliberately no independently committed file counter that could diverge
from nonce admission. Durability across a Redis-server loss follows the existing
Redis persistence/backup configuration, as with relay custody; no stronger Redis
fsync claim is made. Redis Cluster is not supported by the existing client.

Enable only with `RELAY_BACKEND=redis` and
`MKNOON_RELAY_STICKER_METRICS_ENABLED=true`. Other configurations answer
`supported:false`. Failure does not change message/media/call operations.
Disabling stops ingestion/readout; existing keys expire at their original TTLs.
Opting out cannot subtract reports already accepted or recall an in-flight send.

## Mission Control / Kayan-2 readout

All are Prometheus gauges on the existing protected/operator `/metrics` surface:

| Family | Labels | Meaning |
| --- | --- | --- |
| `relay_sticker_sends_daily` | `day` | Exact sum of accepted reports for that UTC date. |
| `relay_sticker_pack_sends_daily` | `day`, `pack` | Exact pack sum for that date. |
| `relay_sticker_sends_by_id_daily` | `day`, `pack`, `sticker` | Exact sticker sum for that date. |
| `relay_sticker_metrics_storage_ready` | none | `1` when Redis aggregate read succeeds, otherwise `0`; count families are omitted on failure. |

Do not apply `rate()`/`increase()` to these gauges. Read the last sample for each
date, or sum selected retained dates. Dates are absolute `YYYY-MM-DD` UTC and
reports normally appear the following day; today is incomplete. A missing
family with no ready collector is unavailable, not zero. Even available totals
exclude opted-out users, old builds, excess capped sends and expired/lost local
reports. Local writes are coalesced for one second; abrupt termination can lose
the newest unpersisted observations. Totals are not a count of all users.

Adapt the three usage/pack/sticker views from these families. Drop the fourth
"phones that sent a sticker" chart's data: no phone estimate/identity sketch is
collected. Multiple relays sharing one Redis namespace expose identical totals;
scrape one authority or deduplicate them, never add replica gauges together.
Relays with separate Redis authorities have separate populations; changing an
app's preferred authority during a pending batch can count that batch twice.
Keep that operational migration separate from ordinary retry guarantees.
