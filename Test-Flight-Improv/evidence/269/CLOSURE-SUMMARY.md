# Plan 269 Closure Summary

Date: 2026-07-23
Disposition: **implementation complete with one explicit physical-iOS proof
exception**

Plan 269 now closes the confirmed sender persistence, transport ACL,
receiver-recovery, lifecycle, native ownership, and automated Android proof
defects. TC-269-19 passes on the final frozen source. TC-269-20 does not pass:
its single user-authorized physical-iOS run reached cold recovery but never
published the required final UI effect, so the user directed execution to
bypass it and continue. This is an accepted proof exception, not a TC-269-20
PASS or N/A.

## Implemented behavior

- Sender completion normalizes only local nullable retry counters, preserves
  creation time, thumbnail hash, and both retry counters across completion,
  retains exact CAS authority, and bounds failed persistence instead of
  uploading forever.
- Group upload callers derive ACLs from active transport identities. An
  explicitly empty group ACL fails before file copies, saves, cleanup, bridge
  work, or avatar access; direct-message null ACL behavior remains separate.
- Receiver download failure is one deletion-aware atomic transition. Candidate
  paging cannot starve eligible rows behind denied pages, and one
  policy-aware coordinator owns listener, route, resume, readiness, and
  periodic recovery.
- Duplicate handling distinguishes successful stable enrichment from
  identical, guard-refused, and content-only exits, so transfer and UI effects
  occur only for committed message IDs.
- iOS native critical-task ownership has deterministic end, refusal, throw,
  expiry, and late-end behavior. The Android and iOS harnesses use prepared
  artifacts and explicit device assignments, and the Android proof exercises
  real process death and reopened production SQLCipher role databases.
- A final broad-gate regression now guards route disposal while the async
  native background-task begin is pending; a stopped voice recording cannot
  update an already disposed composer.

No migration was added. The database remains at user version 104. The group
receiver lane intentionally sends no relay delete acknowledgement; that
invariant remains owned by TC-269-11.

## Final verification

| Boundary | Result | Sanitized result or log SHA-256 |
|---|---|---|
| TC20-oriented focused host suite | PASS, 23/23 | outcome recorded in the plan |
| Curated `groups` gate | PASS, 3,305 Flutter tests plus bridge/node/relay gates | `21740c6c7df4482dd987947377b6e2ca135eadbadac6736316578f06ee7d5999` |
| `feature-host-all` | PASS, 824 paths; 8,555 passed, 1 skipped, 0 failed | `28f91e1cf75a8fa51eec70d81a16b1d07d5f5ec1ce3639b0601065c9746ab367` |
| `core-host-all` | PASS, 350 exact Dart paths plus renderer contract | `3f25568c53163bd2f11b4e0881de1d15a590031c63dcff4610332e6a023446df` |
| Pinned Android transport lane | PASS, 6 invocations / 21 Flutter tests | `ef9b74ba029b2ae6e704f5a78931a4d24b9752abc97873ddfeccffbad7d0b3ce` |
| Swift critical-task suite | PASS, 7/7 | exact `GoBridgeCriticalTaskTests` run |
| Relay Go sentinel suite | PASS, 3/3 | upload/download, unauthorized-peer, and compatibility tests |
| `flutter analyze` | PASS, no issues | `b49a04ab5155a601be13cf512dda56bc0c68ec5a8c78fa074842fc235c0193d4` |
| `git diff --check` and plan/evidence whitespace check | PASS | no errors |
| Graphify incremental refresh | PASS, 49 changed code files; 62,537 nodes / 94,456 edges | graph `9003a507f595e0418ecaa60a291ce74fedf7a6e920834e9c767159f457204710` |

The project cadence deliberately does not run full `host-all` for each plan;
the justified `feature-host-all`, `core-host-all`, curated groups, transport,
native, and relay families above are the Plan 269 closure gates.

## Device proofs

### TC-269-19 — PASS on final source

The registered `groups.media_send_reliability` capability reused one prepared
Android artifact with zero child builds and passed strict v1 validation.

- Source digest:
  `2ff0aa860c0427ac10f62245191096b35c4a64e34f761a9e5c3c816f40ddcb53`
- Prepared artifact:
  `335399705700dbfd59dfdbd2816552351b1aab1522609180743fa543c7dcca8f`
- Validated proof:
  `0d7e43159d3057d55c6e4428ab0068196b5c4078b2f9c854bcb7cd573be8d904`

JPEG, MP4, and voice each uploaded and published once. Downloads settled at
2/1/1 attempts and rendered once each; the second explicit upload and download
passes performed zero work. Sender and receiver account IDs differed from
their active transport IDs, and both production SQLCipher databases reopened
at v104.

The earlier v15 direct and registered PASS artifacts remain as historical
proof. The final registered proof was rebuilt and rerun because the later
composer-disposal production fix changed source custody.

### TC-269-20 — FAIL, then bypassed

The one allowed final physical-iOS run passed Phase A and the Phase B durable
claim, native ownership, and host termination boundaries. Its fresh receiver
process started recovery but did not publish the required final group-media UI
effect. XCUITest failed that final assertion after 4 minutes 21 seconds. No
validated final TC-269-20 artifact exists, no credential was supplied to the
optional post-failure diagnostic collector, and no further TC-269-20 run is
authorized.

The iPhone remaining on the Home Screen was expected after Phase B and
cleanup; it was not evidence that the test was still running. The complete
scenario and investigation record is in `TC20-EXECUTION-NOTES.md`.

## Evidence and scope

Only sanitized JSON, hashes, and the bounded execution notes are retained in
this directory. Raw device logs, `.xcresult` bundles, database paths, device or
peer identities, relay addresses, tokens, keys, and environment files were
not archived.

The pre-existing dirty `00-INDEX.md`, `269-review-fixlist.md`,
`docker-ws/run_fresh_three_phones.sh`,
`docker-ws/run_fresh_three_phones_result.txt`, and root `info.plist` were
preserved and were not modified for closure.
