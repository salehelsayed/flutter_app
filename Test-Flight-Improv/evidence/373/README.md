# Plan 373 Final-Tree iOS NSE Opaque-Wake Adapter Receipt

Date: 2026-08-16 (Europe/Berlin)

This receipt binds the default-off Plan 373 iOS Notification Service Extension
(NSE) adapter transaction to its tested source tree. It records host, native,
available-simulator, preservation, hygiene and final-review evidence. It does
not claim physical-iPhone or live APNs evidence, capability activation, rich
compatibility retirement, full GAP-N07/PRD acceptance, deployment or release
eligibility.

## Verdict

**POST-EXECUTION AUDIT CLOSED / N07 IOS NSE OPAQUE-WAKE ADAPTER CODE COMPLETE /
HOST+NATIVE+AVAILABLE-SIMULATOR VERIFIED / DEFAULT-OFF / PHYSICAL-IOS EVIDENCE
DEFERRED / NOT LIVE-ACCEPTED / NOT RELEASE-ELIGIBLE**

N07_IOS_NSE_OPAQUE_WAKE_ADAPTER_CODE_COMPLETE_IOS_EVIDENCE_DEFERRED

The final audit found no release-blocking defect inside the bounded Plan 373
slice. The implementation remains inert unless the existing paired opaque-wake
admission is enabled and the exact platform consumer is qualified.

## Dependency provenance

The Plan 372 checksum-bound receipt was revalidated before RED. Dependency
labels below are deliberately distinct from the parser-owned Plan 373 frozen
identity rows later in this receipt.

| Dependency identity | Accepted value |
|---|---|
| Plan-372 receipt SHA-256 | `9da08053f6a6034b002376ccc348834ca2576b0761e77be72386e5ec1dec4a62` |
| Plan-372 receipt/implementation commit | `650f8cbe68dfed52a5c66fc53da35915bca53f02` |
| Plan-372 receipt tree | `9d4b46d37a205ea7da1a858dcde8c6f365b29917` |
| Plan-372 base | `434d31d16efc506b3a57b1cdec4ebb2f15fcf66a` |
| Plan-372 frozen tree | `71ab5f0ddcfa5e682f50f1bc36ebb891567b78b2` |
| Plan-372 workspace snapshot | `45e68aab0c0a79750102ccbccd1e010f663dea20a50ea5221cffa1e9278357ed` |
| Plan-372 graph identity | `8c428eb87b960e70` |
| Plan-372 archived snapshot SHA-256 | `e6311ee51cefca9a66201478ab07b0bc1ae1b5a4ff833cc6903117f2a08f027c` |

The checksum, committed artifact bytes, base ancestry, frozen tree object,
archived workspace snapshot and graph identity all validated. DB remains v116.
The production tree still has one `local_notification_ledger_v1.json` owner
under `NotificationConversationIds/.coordination.lock`, the exact
`RELAY_VERIFIED_UNACKED` to `SQL_READY` phase-preserving handoff, and paired
opaque-wake/outcome admission defaulting to false. Plan 372's aggregate
N03-N06 `host-all` was not repeated.

## Implemented contract

### Physical transport projection and readiness

- One versioned shared-Keychain `nse_inbox_transport_v1` projection carries the
  exact returned-peer-qualified physical Ed25519 transport key, logical account,
  binding and effective ordered relay list. The writer removes exact duplicate
  relays while strict readback rejects non-canonical bytes.
- Primary and active-linked roles select their exact physical transport; a
  linked installation never falls back to the logical-account key. Projection
  retirement/readback occurs before logout, account migration/switch, identity
  rotation and linked-role/credential mutation; failed refresh stays absent.
- `OpaqueWakePlatformConsumerReadiness` has exactly one app-owned definition.
  iOS supplies the qualified reader; missing/Android/default-off readers return
  false and perform no registration or unrelated live-service work.
- The active-linked iOS path uses the incumbent
  `PushRegistrationCoordinator.ensureStarted` as its sole registration owner.
  A transient Firebase/foundation failure leaves startup re-armable and push
  listeners gated until a genuinely successful start.

### Current direct and group authority

- Direct device trust and current protected-group sender authority retire and
  verify shared projection absence before any authority-changing SQL mutation.
  A retirement failure aborts the authoritative mutation.
- After commit, projection publication is rebuilt only from committed current
  authority and exact shared-store readback. A publish/readback failure leaves
  authority absent and therefore preserves generic fallback.
- Replacement, removal, backfill and purge paths preserve the same fail-closed
  order. Non-authority group housekeeping does not acquire a new Keychain
  dependency.

### Stateless retrieval and native final effect

- One bounded Go one-shot export derives and authenticates the physical peer,
  uses the configured relay order under one total deadline, performs protected-
  first same-peer legacy fallback, returns at most one page, closes its host and
  never starts singleton listeners/services or acknowledges relay custody.
- The fixed iOS grammar is distinct from rich compatibility. Operational,
  incomplete, timeout, contention and unsupported outcomes preserve the exact
  original generic notification once; authenticated terminal policy remains a
  separate passive result.
- Direct messages/reactions and fetchable protected-group content require exact
  transport/logical/signing/recipient/hash/signature/correlation authority.
  Unsupported/control/plaintext/future rows and legacy group-only rows remain
  generic. Media/voice uses descriptor-only preview and performs no blob fetch.
- `IosLocalNotificationFinalEffect.swift` is the one narrow Swift adopter of
  Plan 372's logical ledger, lock, stable-ID and sidecars. It admits only exact
  matching `RELAY_VERIFIED_UNACKED` custody with owner `IOS_NSE`. It cannot
  initialize/rebind/suspend the store, open SQL/v116, upgrade custody, settle or
  ACK. Bounded lock contention remains generic.
- Main app and NSE share the same revision/content-generation/effect authority;
  relay custody remains pending until main-app persistence and acknowledgement.

### Recovery lease and rollback

- The incumbent recovery boundary carries one bounded mailbox-alert lease.
  Every page in the owning serialized drain generation replays in a scoped
  silent context; unrelated live direct/group callbacks retain normal modality.
- Partial/crash/background continuation retains only the captured generation
  context. An authoritative later null lease clears stale process state. The
  lease is consumed only after verified `hasMore == false`; ambiguous consume
  reply clears local state so a later native begin can re-arm if necessary.
- Default-off, missing reader, unqualified identity/binding, failed projection
  and rollback all omit paired capability advertisement and leave the generic
  path intact.

## TDD chronology and causal evidence

| Stage | Result | Retained evidence |
|---|---|---|
| TC-373-00 dependency/default-off preflight | PASS against committed Plan 372 receipt and source/API sentinels | Receipt identities above; DB v116 and admission false |
| First TC-373-01 RED | 1 selected RUN / 1 semantic FAIL; peer isolation could not use the global singleton | SHA-256 `4682f127b4db4ee50c5fd74ee69cb7155708047c484ff54f53c28fb5ee15729e` |
| Final Go focused | 4/4 roots, zero skips | `go-focused.log` SHA-256 `27ce611f800a0ee9975d111df0428f54e1b9bc520442f7df1fba37eeccee75e9` |
| Final Go race | Same 4/4 roots under `-race`, zero skips | `go-focused-race.log` SHA-256 `045dcc2f6976e02f9d2a9e28d485594bdaf813726f83209a92a6cc0b649a34ff` |
| Final Go preservation | 4/4 exact incumbent roots, zero skips | `go-preservation.log` SHA-256 `8532d27300824248d5813c27eea48e23a664bd0a2ef6fc80170d6bff34b28cc0` |
| Selected Dart Plan-373 cases | 5/5, zero skips, on the final fixture | Terminal attestation; no retained post-regeneration artifact |
| Final-fixture TC-373-07 | 1/1, zero skips | Terminal attestation; no retained post-regeneration artifact |
| Broader Dart owner/preservation bundle | 175/175 | Retained JSON SHA-256 `3c78bb148fd85348d3df5d2c38355d9b96eb590cafc08819924e8233a36eab51`; this artifact predates final fixture regeneration and is not the final-fixture proof |
| Native Swift final | 16/16, zero skips, simulator `DBE8C32E-9F19-4593-860A-B41113791D79` | Summary SHA-256 `04a601819338c17271b49a3bc33c31a80e1d19077c9fad8c50b26c05321cecd1`; method JSON SHA-256 `ce8989ac21b8b89e3e61f16000d2ebdec801e1daa50f095686fc253e1207ae12` |
| Fixture classification | 31 unique rows: 14 accepted / 6 rejected / 11 invalid | Fixture SHA-256 `1b4687a81ac55505d50e511f055b3bfdb61bda0dee1d8687c7a9ca25aa79d508`; census SHA-256 `fae78cf5fc5091b6f291ae9cd45656c596c2077cf7884d935799a09e716940c5` |

The exact five Dart cases were TC-373-02, TC-373-02b, TC-373-02c,
TC-373-04b and TC-373-07. Their final-fixture result is reported honestly as a
terminal attestation: the retained exact-five JSON SHA-256
`ebd680d5e5ce44ba5c21d3488aa4b6be509f3293a2489114019a43fbbd5067b3`
and the 175/175 artifact both predate the final group-reaction fixture repair
and are not used as its hash-bound proof.

### Native authority mutations

Each mutation selected
`testTC37305AuthenticatedCandidatesShareOneFinalEffectOwner` exactly once,
failed its named semantic boundary with zero skips, and was reverted before the
final 16/16 run.

| Mutation | RED evidence |
|---|---|
| Redirect to sibling logical ledger/lock | SHA-256 `92e5f3219b542748d6dfe974c5e9ebdaa93e911b6d0f7e326bca6b676aa401cc` |
| Admit SQL/settled custody authority | SHA-256 `870d3b5648c9feef1ff1bea4a36b1ceeaa324ad391e355e73a2c125f9e5500e9` |
| Treat bounded `flock` contention as authority | SHA-256 `ba4d878931583210ce0c955ea49775f2a40f1285e9190b7c0464797b67ad89a3` |
| Byte-restored source | SHA-256 `036e44d3122c7ddb4b5693508b66f18e30df34fac0eceb85bf8167f40e0e45b5` |
| Restored selected method | 1/1; log SHA-256 `6d7518357b2002421237852d2cddb9312c6728ad31301e7a9a54b736f288fa38` |

## Final gates

| Gate | Final result / evidence |
|---|---|
| Registered native owner | Exactly one host item; absent from dart-only; runner SHA-256 `a485503b38a6e2a642e0377394c27f9c1900e341010ea63a033e16289be67b7c` |
| Native command | Exit 0; evidence directory `/tmp/plan373-native.u7sW4p` |
| Fixture membership | PASS; SHA-256 `a6afc98ec5f618d28b5d64ffb0da5a7c44d0047acf52e33ff10a27d0b5f0a36e` |
| Generated binding contract | PASS; SHA-256 `df15bc808432c11c096e999d0314899348a6165cb7e1b54f15bf0765c7f8e71c` |
| Binding input/stamp | Exact digest `83680b73348c4806044adb6da9af1071a93143cd3d4a93a57790140332c6a9d9` |
| Generated framework | SHA-256 `caa00d8877353533aa2826964447d9be41f646c00bdfd7cc4bcac6909bad56da` |
| Runner simulator build | PASS; SHA-256 `0b50db7bc720847709917ce8250b9d82cc20c07397faa97df046f676c36aa679` |
| Embedded NSE symbols | PASS; SHA-256 `75c5eaad251eaa61849a0c0ad632ed039251c96269657a243e7ab549fea83a7d` |
| Embedded NSE entitlements | PASS; SHA-256 `c740f5d22e92ed62f73e427d76b2eedf46f9a17ba7c0bdd608bb27bc8376b3b1` |
| Privacy manifests | PASS; SHA-256 `3c77f0418290aa5d27f2838e86328f3094b4241c69c7f79f939392d054c3a963` |
| Xcode residue | Five intentional `.xcresult` bundles in the isolated evidence directory; zero `DerivedData` residue |
| Curated `1to1` | 3,334 pass / 10 declared skips plus all non-Flutter tails; terminal attestation |
| Curated `groups` | 4,339 pass plus 278 hidden / 0 fail / 0 skip; SHA-256 `a9df65ae3da7cae6a60866451f2b13b0e79319bf1714a7e34561c226635a96cf` |
| Full analyzer | No issues in 122.4 seconds |
| Formatting | 34 Dart files, zero changes; 5 Go files `gofmt` clean |
| Syntax/metadata/diff | 2 shell files `bash -n`, 3 plist files `plutil`, and scoped diff check all PASS |
| Broad sweep policy | No per-plan `host-all`, `core-host-all`, `feature-host-all`, Android or physical-device campaign |

## Current-source audit

The final audit accepted exactly 56 implementation paths: 14 added, 42
modified and none deleted. By ownership they are 26 `lib`, 5 Go, 12 iOS, 9
test, 2 script and 2 Graphify paths; by file type they are 34 Dart, 5 Go, 11
Swift, 2 shell, 1 pbxproj and 3 JSON paths.

- DB is still v116; there is no SQL/relay schema migration, second inbox,
  ledger, lock, queue, worker, scheduler or Flutter-engine NSE owner.
- There is exactly one production `OpaqueWakePlatformConsumerReadiness` class,
  one stateless NSE bridge/node API family, one
  `IosLocalNotificationFinalEffect.swift` adapter, and one registered native
  host item.
- The Plan 372 logical basename, coordination lock, stable-ID registry and
  phase/custody vocabulary remain the sole authority. The NSE neither ACKs nor
  settles relay custody.
- The paired fixed-wake admission remains default false. Android remains
  unready and Plan 374/375 product scope is untouched by this transaction.
- The fixture has 10 exact top-level roots, 31 unique classified rows and real
  incumbent producer crypto with the exact 14/6/11 census. Binding headers,
  framework symbols, RunnerTests source/resource membership, entitlements and
  privacy manifests are present and verified.

## Graph grounding

| Graph fact | Final value |
|---|---|
| Freshness / confidence | `current` / `anchored` |
| Plan-373 graph identity | `e0344a42ddda114c` |
| Nodes / edges | 77,902 / 114,905 |
| TDD overlay | 1,597 files / 15,747 named tests / 1,257 production targets / 1,517 registered files |
| `graph.json` SHA-256 | `46675acfc4c3ea3202cf4ec26966cf68f7a1d332d3ee091db64b7fa8e9b31134` |
| `manifest.json` SHA-256 | `7560b8172a1225c3da9a0247208995a4040a83c70b6a1d404366e9a71bb64df7` |
| `tdd-overlay.json` SHA-256 | `c4d793fd420d89b9fcb5b1ce6527090d9dbebe793d061b7b668bfb267a67d3b8` |
| Incremental refresh | 9 changed / 3,253 unchanged / 0 deleted |

The shared fixture JSON produces an expected zero-node Graphify warning; the
refresh is current and anchored. Executable gates and the final independent
audit remain authoritative.

## Frozen tested state

An alternate Git index captured the accepted Plan 373 implementation without
changing the shared index. Closure documentation and evidence are deliberately
absent from the frozen tree and may differ from it only on the successor-parser
whitelist.

| Identity | Value |
|---|---|
| Capture date | `2026-08-16` (Europe/Berlin) |
| Branch | `protected-view` |
| Base HEAD | `e7b99e12c520e02624a0eeeaaef4186e052a0d40` |
| Base/HEAD tree | `44ddfc489208fe1011aabb33a1cfeb5d3ab113f7` |
| Frozen tested tree | `cfa123c59afa97cefd06fe6128caffcfa894c6c4` |
| Porcelain-v2 workspace snapshot SHA-256 | `bf81fb428fcc2403d439f7bd1765c4c0b06de89e7c26497d458e3d6e6109cd51` |
| Porcelain-v2 status lines / records / bytes | `60` / `56` / `8,077` |
| Compressed snapshot SHA-256 | `79c53ab55559473987676107e994aa11c042c02022c04a3021c3d9035e9ed7b3` |
| Frozen paths / added / modified / deleted | `56` / `14` / `42` / `0` |
| Frozen paths SHA-256 | `dd19dce8bfaf63683c3d060fdfc5b748774e637e966034ef91374c7a5acda7a3` |
| Frozen name-status SHA-256 | `6381cf1e920fda9ebbd2173a7ae150b5683ed0b8e71b47a8e6233660b554f230` |
| Frozen numstat SHA-256 | `32372a75c7e8880fe5c16dd53d8b45a2255901c241dac877339523ffc8ce8d48` |
| Shared-index entries / bytes / SHA-256 | `6,456` / `917,053` / `b227fe840c4d3f3e0be94245e06855e9f49d14b8d1d0c4e35f0e34f16453a46f` |
| Shared-index staged entries | `0` |
| Alternate-index entries / bytes / SHA-256 | `6,470` / `918,646` / `f8de59591b2120acf1015c2c35ccaa5a0a66c45fc1cb56e7599ce01bed0945e4` |
| Graphify fingerprint | `e0344a42ddda114c` |

Machine-readable identities:

```text
Base HEAD: e7b99e12c520e02624a0eeeaaef4186e052a0d40
Frozen tested tree: cfa123c59afa97cefd06fe6128caffcfa894c6c4
Dirty snapshot SHA-256: bf81fb428fcc2403d439f7bd1765c4c0b06de89e7c26497d458e3d6e6109cd51
Graphify fingerprint: e0344a42ddda114c
```

`workspace-porcelain-v2.txt.gz` decompresses byte-exactly to the snapshot whose
SHA-256 is recorded above. `graphify-fingerprint.txt` contains the exact
16-hex graph identity. Both files, this README and its sibling checksum are
successor-verifiable committed evidence.

This README, checksum, archive, fingerprint file and the final
plan/status/index/coverage closure necessarily postdate and are absent from the
frozen tested tree. They add no production, test, native, fixture, script or
Graphify transaction after the accepted gates.

## Independent audit and residual boundaries

Independent final review passed against the exact 56-path scope and found no
Android, Plan 374/375, unrelated documentation or hidden product drift. The
native runner is non-vacuously registered once and absent from dart-only; all
three mutations restored source bytes before the final suite.

The final-fixture selected Dart rerun and curated `1to1` result are terminal
attestations rather than retained hash artifacts; this provenance limitation is
explicit and does not transform the older artifacts into final-fixture proof.
Physical Apple lifecycle/file-protection assertions remain deliberately
deferred. No live route/provider, deployment, activation or release action was
taken.

## Handoff

Plan 374 may proceed independently from the checksum-bound Plan 372 contract.
Plan 375 may consume this receipt's single shared readiness owner and iOS
adoption fact only after validating the exact marker, checksum, frozen-tree,
workspace-snapshot, graph and ancestry contract. It must not infer Android
readiness, capability activation or live acceptance from this iOS mechanism
receipt.
