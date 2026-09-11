Go diagnostics implementation and validation, 2026-09-08

This document records the initial implementation gate. Subsequent live QA found and repaired aggregate trace capacity and added native admission diagnostics; the later candidate provenance and validation are recorded in the nested `call-observability-implementation/relay-quota-repair-*` and `relay-admission-schema-*` documents. The initial artifact hashes and limits below are historical, not the latest deployment declaration.

Implemented authenticated opt-in diagnostic control, durable event collection, and advisory v2 wrapping around the unchanged strict v1 call/TURN requests. The bridge accepts outer `cause`; the shared fixture tests its conversion to event `reason`. Call paths consult cached capability support. An explicit old-relay rejection invalidates the cache and permits one legacy retry; TURN keeps that retry inside its existing attempt deadline.

Consent defaults off. Monotonic authenticated consent epochs survive server restart. Disable purges associated records. Clear advances the epoch and purges records/bindings while preserving the enabled flag; stale uploads, wrapped requests, and queued server work cannot repopulate cleared data. Invalid schema/foreign-trace uploads receive terminal rejection IDs; transient storage/quota failure leaves IDs unacknowledged for retry.

Private last-authority links now retain their author digest so disable/clear can erase the originating owner's links durably. Startup migration drops diagnostic-only links from older metadata that lack that provenance. This does not modify call authority in Redis.

Desired push consent is separate from effective push-parser capability. Successful authenticated legacy call-token registration disables the effective capability without changing consent or its epoch; an earlier in-flight configure cannot restore it. A fresh same-epoch configure can restore capability, and a relay restart requires fresh configuration. The relay cannot detect a binary rollback before a subsequent registration, so the operator runbook requires acknowledged diagnostic opt-out before installing an older native app. Never-opted-in legacy peers retain the original push payload.

The protected file store is independent of Redis mailbox expiration. It retains data for14 days by relay receipt, with a64MiB record quota,5MiB owner quota,256 events/64KiB per trace and separate bounded terminal summaries. Authorization/route metadata uses an in-memory lock separate from disk work; queued persistence cannot block the business request. Events accept only the shared allowlisted schema, canonical UUIDv4 identifiers and bounded build values. Private bindings, handles, peer identities, credentials, tokens, addresses, encrypted envelopes and raw errors are absent from operator output.

Relay phase evidence distinguishes mailbox commit, actual APNs/FCM provider invocation/result, wake failure, and response-write failure. Endpoint lookup joins the latest endpoint operation separately from wake-grant/token changes. `values.authorityKind` identifies the authority object; typed `cause` becomes the event reason. Every relay event carries the reviewed build source digest. TURN evidence stops at request/mint/write; coturn allocation/media remains a separate boundary.

Validation passed:

| Check | Evidence |
| --- | --- |
| Relay diagnostics |18 focused tests, including auth/consent/restart, quotas/summary retention, schema/privacy, blocked disk independence, Store+provider failure, response-write failure, delayed epochs, transient retry, pair/handle binding, shared Dart cause fixtures, private-authority erasure/migration and legacy push capability races |
| Node/bridge diagnostics |8 focused tests, including negotiated wrapping, exact v1 preservation, old-relay fallback, delayed configure response, TURN cache/deadline behavior and shared fixtures |
| Relay race preservation | Diagnostics/metrics batch passed19.046s; later erasure regression batch passed44.706s and capability regression batch passed5.324s. The final full suite also includes the bounded registry guard added after the capability race run. |
| Final relay full suite | `GOTOOLCHAIN=go1.25.0 go test ./... -count=1` passed34.830s |
| Node/bridge diagnostics race and TURN cancellation | focused final run passed24.999s /24.002s |
| Final node/bridge call and TURN preservation | `go test ./node ./bridge -run 'Call\|TurnCredentials' -count=1` passed9.632s /11.546s |
| Full go-mknoon suite before final cause/cache compatibility corrections | all packages passed; final corrections were subsequently covered by the focused race and full call/TURN preservation checks above |
| Operator | `python3 docker-ws/call_diagnostics_test.py` passed6 tests including privacy projection, endpoint completeness, all rate categories/minimum sample thresholds, normal-decline exclusion and related authority-operation joins |
| Generated bindings | Both existing ensure scripts passed using Go1.25; Android and iOS/NSE artifacts regenerated after final wire correction |
| Change hygiene | Scoped `git diff --check` passed; Graphify affected checks cover the owned source batch |

Final artifacts and exact source/input hashes are in `call-diagnostics-relay-build.json` and `call-diagnostics-bindings-build.json`. The final Linux candidate is `/tmp/beta-call-review-20260908/relay-call-diagnostics-linux-amd64-final`, SHA256 `df4412361360f4707723ac26e9bbf9dc92023595e53c8a35102dd09301ad72ae`; its event build is `8f1df9c50ce0d6db7c11c36858b45af9ebaeb3d6821b956c6018a22f0d310cb2`. No source input was edited after that build. The final erasure and capability fixes are server-only and leave mobile binding hashes unchanged. This subagent did not deploy or operate phones during this implementation batch.

Operator implementation is `docker-ws/call_diagnostics.py`; deployment/API notes are `docker-ws/call_diagnostics_protocol.md`. The overview reports preflight rejection, classified technical setup failure, answered-without-media, drops after media, registration withdrawals by origin, provider/credential failure, telemetry loss, and cleanup failure. Rates expose numerators, denominators and a minimum5-observation threshold. Declines, cancellations, busy and no-answer terminals are excluded from the technical failure denominator. Trace lookup shows first relay-received failure, missing stage reports, related registration operations and separate caller/callee terminal/media completeness.

Proof limits remain explicit. A direct leg can succeed while mailbox Store fails; shared relay participant binding requires successful Store, so those endpoints can retain separate/provisional traces. Consent-disabled, old-peer, unavailable-sink, expired and bounded-quota records can be incomplete. A single endpoint's media claim is not promoted to a both-endpoint success. ACK, push submission and TURN issuance do not prove audio. Relay-receipt ordering of delayed device uploads does not establish global causal order. These limits appear in operator projections and must remain in release notes.
