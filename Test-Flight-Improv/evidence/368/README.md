# Plan 368 Final-Tree N02 Fixed Mailbox-Dirty Wake Closure Receipt

Date: 2026-08-15 (Europe/Berlin)

This is the dependency-wave execution receipt for Plan 368. It records the
final source/test tree after the late independent counterexample audit, the
resulting proof repairs, all reverted semantic mutations, and the one complete
N02-wave `host-all`. No source commit, synthetic commit, tag, deployment,
device run, live migration, capability activation, cleanup, or release was
created or performed.

## Verdict

- `N02_OPAQUE_WAKE_MECHANISM_CODE_COMPLETE = true`
- `N02_COMPLETE = false`
- `N02_LIVE_ACCEPTANCE_PROVEN = false`
- Production clients still do not advertise `opaque_wake_v1`; capability
  admission and the Redis migration remain default-off.
- The default-off relay mechanism and captured provider request contract are
  host-proven. Universal provider privacy, native consumption, A-control PRD
  acceptance, deployment, activation, and release eligibility are not proven.

The exact completion marker is:

```text
N02_OPAQUE_WAKE_MECHANISM_CODE_COMPLETE
```

This marker covers the fixed mailbox-dirty request and provider-facing log
closure at the Plan-367 private route gateway. It does not claim `N02_COMPLETE`,
live acceptance, retirement of the rich mixed-version path, live key
provisioning or migration, device/native presentation, S2/B1b, any A-control,
or release eligibility.

## Dependency provenance

Plan 367 was checksum-validated and revalidated on the final Plan-368 source
before closure:

| Identity | Verified value |
|---|---|
| Receipt | `Test-Flight-Improv/evidence/367/README.md` |
| Receipt SHA-256 | `b0253505ed8bdb2ca3cb352e6179edf85e6290d16503667c5d3949c2e5f61a89` (`shasum -a 256 -c`: `README.md: OK`) |
| Frozen tested tree | `9ec76e3f99e222ba446801f2e5e1281725bdc05b` |
| Porcelain-v2 snapshot SHA-256 | `3473c3919085622bc9b9dabc9780a682789a3371858e641e2aa1648157075ff8` |
| Graphify fingerprint | `76c930dc8afc22a2` |
| Marker | `N02_OPAQUE_HANDLE_FOUNDATION_CODE_COMPLETE = true` |
| Final seven-test revalidation | 7 discovered; 7 top-level PASS; 0 SKIP; run SHA-256 `c8176f3b0c279a9a1f5d6bf62b9ca9b76b6ee9629b7f91dd853733c07c1b82ee` |

The unchanged repository base was
`3865aa9b8b8b000ecaf871a839d1fbdecaa0d86c`. Plan 368 preserved Plan 367's
opaque handle, generation, encrypted resolution, exact compare-revoke, and one
bounded full-reselection contracts.

## Implemented contract

- `opaque_wake_v1` selects a route-only mailbox-dirty send. It remains absent
  from production client registration defaults, so the new path is default-off
  outside deliberately capable fixtures.
- Android uses the fixed `data={v:1,w:1}` request with high priority, 300-second
  TTL, and `mailbox` collapse key. It has no notification, APNs configuration,
  Android notification, or event-derived field.
- iOS uses the fixed alert request with the exact five APNs headers, trusted
  topic `com.mknoon.app`, expiration at the injected time plus 300 seconds,
  `mailbox` collapse ID, localized title/body keys, mutable content, default
  sound, `MESSAGE_WAKE` category, and custom `v=1`. It has no Firebase data,
  Android configuration, thread identifier, plaintext alert text, or
  event-derived field.
- The private route gateway remains the sole provider token/platform resolver
  and the sole token injection point. The opaque handle and all event, route,
  sender, recipient, conversation, group, message, reaction, media,
  ciphertext, deep-link, and analytics values stay out of fixed provider
  requests.
- Direct, direct-reaction, group-reaction, and group adapters share one route
  selector and one stale-reselection policy. Opaque selection wins over rich;
  empty handles, unknown platforms, and non-stale errors fail closed. One
  explicit stale result may reselect opaque or terminate, and never downgrades
  an originally opaque attempt to rich. A stale rich attempt may upgrade to
  opaque.
- Mixed-case and surrounding-whitespace variants of known Android/iOS route
  platform values canonicalize to their fixed request; empty and unknown
  values send nothing.
- Provider permanent errors compare-revoke only the immutable handle and
  generation that failed. Generic errors do not switch opaque sends to rich.
  Strict size fallback remains confined to legacy rich requests.
- Legacy incapable routes preserve existing rich projection, eligibility,
  authorization, store-before-push ordering, duplicate suppression, counters,
  retry, and strict fallback behavior.
- Provider-owned `[PUSH]`, `[REDIS][PUSH]`, and touched
  `[GROUP_REACTION_WAKE]` logs use fixed event names, finite coarse outcomes,
  reasons, and attempt counts. They omit private identifiers, payloads, tokens,
  handles, raw provider bodies, and raw error strings. Unrelated logging remains
  GAP-N10 work.
- The incumbent full-relay script is registered once as the last synthetic
  `host-all` row, alongside the exactly-once Plan-367 tagged process row. No
  service, package, queue, scheduler, worker, protocol action, or mobile
  consumer was introduced.

## TDD evidence

The initial Android test captured the real Firebase Admin SDK request at the
incumbent rich boundary. It failed because the request still serialized
`sender_id`, `message_id`, `kem`, `ciphertext`, `nonce`, `type`, and
`envelope_version` and omitted the required fixed TTL and collapse key. That
semantic RED preceded the production implementation.

A late independent proof audit found that the first green draft did not yet pin
the exact producer census, all real-store zero controls, every stale transition,
typed Firebase permanent errors, every promised runtime log path, or platform
canonicalization. A provisional `host-all` was stopped at row 83 and was not
counted. The tests were repaired, the focused and preservation bundles were
rerun, and only the later complete final-tree wave run is authoritative.

The final exact test-contract results were:

| Proof | Final result | Final-session SHA-256 |
|---|---|---|
| Focused discovery | Exactly 5 named Plan-368 tests discovered | `9f8f6c790334c3e4b76540f6c364f5fa739ca3afbdba4148926c229718de0e1d` |
| Focused execution | 5 top-level PASS; 0 SKIP | `c53b8a16a2b623fc33f79e199d5420311a90fb009e5d2ff9471d8e28e3f4906b` |
| Provider-shape matrix inside the focused run | 22 shared source-eligible producer fixtures on Android and the same 22 on iOS; 44 real Firebase SDK HTTP captures matched the platform-fixed allow-lists exactly; real-store zero controls emitted no request | covered by the focused execution hash above |
| Preservation discovery | Exactly 15 named sentinels discovered | `850e88deccdc99f7556efa4d69471f6352c6a3f605a235399605a865af9b2fd6` |
| Preservation execution | 15 top-level PASS; 0 SKIP | `0e56c1418d4a00fca8ead4b057b119493c3fdaba83a868970f5cef4a3bac3863` |

The source-eligible producer census covers direct ordinary envelopes, direct
reactions, ordinary group fanout, and group reactions. Eligible ordinary group
fixtures traverse the real `GroupInboxStore`; direct and group reaction
controls traverse their real eligibility/deduplication seams. Ordinary group
deletion/system cases retain the notification behavior current production
source actually admits instead of being mislabeled as zero-wake. The fixed
shape assertions therefore prove convergence without manufacturing producer
behavior at the adapter boundary.

### Serial semantic mutations

Each family was applied alone, required to red its owner, reverted, and
followed by owner green before the next mutation. Raw mutation logs were not
retained, so this receipt deliberately records no invented per-mutation hash.

| Mutation family | Required RED observed after mutation |
|---|---|
| Opaque precedence / second lookup / unknown platform | Route-selection owner rejected precedence loss, duplicate selection, unsupported-platform admission, or stale downgrade |
| Android event leak or wrong fixed shape | Real SDK Android capture rejected an extra event field or missing/wrong allow-list field |
| iOS event leak or wrong fixed shape | Real SDK APNs-through-Firebase capture rejected a thread/event field or wrong topic/expiration/allow-list field |
| Generic opaque failure falls back to rich | Failure owner observed the forbidden rich send |
| Unconditional permanent-error revoke | Typed Firebase permanent-error interleaving observed deletion of the refreshed generation |
| Provider-log canary | Runtime log owner found the private canary in a provider-owned record |

No `PLAN368 MUTATION` marker remained in final source.

## Final gates

| Gate | Final result |
|---|---|
| `bash scripts/run_test_gates.sh groups` | exit 0; Flutter `+4199: All tests passed!`; registered Go bridge, node, and relay tails passed; log SHA-256 `84966e1f76ebd0f781ff634ecdf9bfeb38b7956a7c9cd93f975910beb6ac7222` |
| `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go vet ./...)` | exit 0; no output |
| All `go-relay-server/*.go` through `gofmt -l` | no output |
| `git diff --check` | exit 0; no output |
| `bash -n` for the changed host scripts | exit 0 |
| `bash scripts/test/host_test_gate_batch_contract_test.sh` | `PASS: batched host test gate contract`; 10 synthetic rows / 11 Go calls; log SHA-256 `02bd1fce20bfdc96f6eb19133b590015169d7e0dc978db1a1555ae897be0bf50` |
| `./scripts/run_host_test_gates.sh host-all` | exactly 1,357 / 1,357 rows PASS; 0 skipped and 0 failed rows; log SHA-256 `b0132cb137865dd2b5de50207aeaf243894590054c7f9daa1679e4850f2f6da3` |

In the authoritative wave run, rows 1-1,347 were Flutter rows and rows
1,348-1,356 were incumbent/Plan-367 Go rows. The tagged Plan-367 process test
ran exactly once at row 1,356. The unfiltered full relay ran exactly once at row
1,357 and passed in 21.785 seconds. The earlier stopped row-83 provisional run
was a pre-acceptance diagnostic and is not counted as the N02-wave gate.

No phone was required for this Go relay/provider-contract slice. Device/native
consumption belongs to later work packages and no unavailable device is treated
as a closure blocker here.

## Current-source audit

The combined post-execution Plan-367/368 audit used production source only
(`!*_test.go`) and found:

| Guard | Count |
|---|---:|
| `LookupToken` references | 0 |
| `.LookupRoute(` call sites | 1 |
| `.ResolveRoute(` call sites | 1 |
| `selectPushRoute` call sites | 7 |
| `sendSelectedPushThroughGateway` definition plus callers | 5 |
| `sendPushRouteThroughGateway` definition plus callers | 3 |
| Provider-token injection sites | 1 |
| `mailboxDirty` call sites | 1 |
| `recipientSupportsCapability` references | 0 |
| Owned provider log sites | 35 |
| Production client advertisements of `opaque_wake_v1` | 0 |
| `PLAN368 MUTATION` markers | 0 |

The seven selector calls are the four public adapter entry points, two
store-owned reaction snapshot sites, and the shared stale reselect. The five
selected-send occurrences are one definition and four adapter calls; the three
private-gateway occurrences are its definition plus the rich and fixed
callers. The sole lookup, resolver, and token injection remain at their intended
private boundaries. The 35 provider-owned log sites use only the audited coarse
vocabulary.

An independent final audit also re-read opaque/rich precedence, empty handles,
known and unknown platforms, stale transitions, fixed builders, typed provider
errors, exact generation revoke, strict rich fallback, producer eligibility,
default-off advertisement, and the host-gate registrations. It found no
remaining mechanism or host-proof defect.

## Graph grounding

The final incremental refresh ran after the settled source/test proof repair. A
fresh compact review query was current and anchored.

| Graph fact | Final value |
|---|---|
| Freshness / confidence | `current` / `anchored` |
| Fingerprint | `27ea9a664ebf98d9` |
| Nodes / edges | 75,606 / 110,505 |
| TDD overlay | 1,575 files / 15,658 named tests / 1,241 production targets |
| `graphify-arch/graphify-out/graph.json` SHA-256 | `e88b91497ad79a456f47d5e772b9086b9e4b76cd01b66c4b577ee3e8efb79876` |
| `graphify-arch/graphify-out/manifest.json` SHA-256 | `28a41854a3a7ab789d0ffb9d1f8c94fc1db704f5b4f4ea6cdfec39c598c7d209` |
| `graphify-arch/tdd-overlay.json` SHA-256 | `40e472253c6806895359a6b664e5d1f97de7b795685253009c68ca15723b6087` |

The affected-surface review identified the expected relay adapters, route
gateway, producer stores, provider-error/log tests, and incumbent notification,
dedupe, reaction, retry, and projection sentinels. The exact preservation
bundle, curated group lane, full relay tail, and complete wave gate cover those
reverse dependencies.

## Frozen tested state

The shared worktree was intentionally dirty. An alternate Git index captured
all tracked files plus every untracked, nonignored file without replacing or
writing the shared index.

| Identity | Value |
|---|---|
| Capture time | `2026-08-15T15:09:40+0200` |
| Branch | `protected-view` |
| Base and unchanged `HEAD` | `3865aa9b8b8b000ecaf871a839d1fbdecaa0d86c` |
| `HEAD` tree | `a0a945780c196f16d852906607ed85a103770e59` |
| Frozen tested tree | `924e8f64ebc7c9dca2de83890ecad144fefbdaf2` |
| Porcelain-v2 workspace snapshot SHA-256 | `d15109f11a37cda022fd90e44526d5bf15b03091578d3dd3ccf71738d5676428` |
| Porcelain-v2 records | 244 |
| Shared-index entries SHA-256 | `f5e25c72126c695528f43f407191869d53ec6109bd87b2d9be182001ec1a8a4f` |
| Shared-index entries | 6,348 |
| Shared-index byte SHA-256 | `cfa02381018fbb5d3da0f1c137c278bb07d7f1d2bfe7bda0a863105143d87226` |
| Alternate-index entries SHA-256 | `75cfe72dafed2c8dc9e0605a751c27fa727d0f4a38efbefa8c6762cf20aaf4a2` |
| Alternate-index entries | 6,388 |
| Alternate-index byte SHA-256 | `f2eaee703c83587ee97388c0aa86773fea7099f8f6304cb9901642b035460e15` |
| Toolchain | `go version go1.25.0 darwin/arm64` |

The product source, tests, scripts, and refreshed Graphify artifacts in that
tree are the state on which the final gates and audit are based. This README,
its sibling checksum, the plan's checked acceptance/progress edits, and the
status/index/coverage closure edits necessarily postdate and are intentionally
absent from the self-describing frozen tested tree. Product and test source did
not change after the freeze.

## Handoff

WP-04 iOS and WP-05 Android own native consumption proof without capability
advertisement. WP-06/WP-07 alone may admit `opaque_wake_v1` after encrypted
route availability, rollback prerequisites, and mixed-version observation;
they also own live key provisioning and Redis migration, rich-path retirement,
deployment, device acceptance, cleanup, rollback, and release closure. GAP-N10
retains unrelated runtime-log scope.

This receipt authorizes none of those actions. It establishes only the
default-off fixed mailbox-dirty relay mechanism, captured fixed provider
request shapes, provider-owned log sanitation, combined source audit, and host
wave proof recorded above.
