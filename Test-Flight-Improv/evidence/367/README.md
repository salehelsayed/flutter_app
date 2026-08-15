# Plan 367 Final-Tree N02 Opaque-Handle Foundation Closure Receipt

Date: 2026-08-15 (Europe/Berlin)

This is the dependency-bearing execution receipt for Plan 367. It records the
final source/test tree after the independent counterexample audit and after all
semantic mutations were reverted. No source commit, synthetic commit, tag,
deployment, live migration, cleanup, or activation was created or performed.

## Verdict

- `N02_OPAQUE_HANDLE_FOUNDATION_CODE_COMPLETE = true`
- `N02_COMPLETE = false`
- `N02_LIVE_ACCEPTANCE_PROVEN = false`
- Redis migration and legacy cleanup remain explicit and default-off.
- Plan 368 may consume this receipt after validating `README.md.sha256` and
  copying the frozen-tree and Graphify identities below.

The exact completion marker is:

```text
N02_OPAQUE_HANDLE_FOUNDATION_CODE_COMPLETE
```

This marker covers the encrypted opaque-route host foundation only. It does
not claim the fixed/content-free provider payload, provider-log sanitation,
AC-11 closure, GAP-N02 completion, live key provisioning, fleet admission,
deployment, migration, legacy cleanup, rollback, device proof, or release
eligibility. Plan 368 and WP-07 retain those boundaries.

## Dependency provenance

Plan 366 was revalidated immediately before closure:

| Identity | Verified value |
|---|---|
| Receipt | `Test-Flight-Improv/evidence/366/README.md` |
| Receipt SHA-256 | `5c3843a5f4059652b83a58e57909ab8bcf3a99c78ba5587a5efd6ccdfda5753b` (`shasum -a 256 -c`: `README.md: OK`) |
| Frozen tested tree | `0765646f6c60140424e5320552d38ed0e5a2fce8` |
| Graphify fingerprint | `19e306d1432ccbf1` |
| Marker | `N01_MECHANISM_CODE_COMPLETE = true` |

The unchanged repository base was
`3865aa9b8b8b000ecaf871a839d1fbdecaa0d86c`. A clean commit was not a
prerequisite and is not inferred.

## Implemented contract

- The package-private `pushRouteLease` carries an opaque random handle,
  generation, copied capabilities, and private compare/revoke authority; it
  contains no provider token or platform.
- Memory and Redis backends implement lookup, authenticated resolve, exact
  conditional revoke, and error-bearing unregister with the same route
  contract.
- Redis has disjoint legacy, state-marker, directory, and vault namespaces.
  Marker-absent behavior preserves exact legacy bytes; migrating behavior is
  revision-fenced and write-available; encrypted behavior has no legacy
  fallback.
- Vault records use AES-256-GCM with random nonces, strict codecs, active and
  retained keys, provider-environment binding, and complete AAD over peer,
  handle, generation, platform, capabilities, environment, and exact legacy
  source digest.
- Migration is explicitly admitted, crash-resumable, idempotent, SCAN-
  deduplicated, and converges only after an exact stable-revision bijection.
  Verification crossings retry on marker drift and fail loudly on unchanged
  corruption.
- Token, platform, and trusted-environment changes rotate handle/generation;
  capability and retained-key changes preserve identity while atomically
  resealing. Every encrypted mutation preserves one directory to one vault and
  removes superseded vault rows.
- One private `PushService` gateway is the sole production resolver and the
  sole token/platform injection point. Direct, direct-reaction,
  group-reaction, and group adapters pass only an immutable route and
  token-free message factory. Explicit stale gets one bounded full reselection.
- Initial and strict-fallback permanent provider failures revoke only the
  exact lease. Authenticated unregister acknowledges only after atomic durable
  deletion and returns a finite error on failure.
- `push-token-vault migrate --fleet-receipt-sha256 <64-lower-hex>` and
  `push-token-vault cleanup-legacy` are explicit CLI operations. Merely
  provisioning a keyring does not change marker-absent behavior.
- The tagged process handoff is registered as one exact synthetic later-wave
  `host-all` row. No new service, package, queue, worker, scheduler, daemon,
  admin endpoint, reverse index, device code, or payload-privacy claim was
  introduced.

## TDD evidence

The initial TC-367-01 scaffold exposed the incumbent plaintext legacy-row
boundary. Review rejected its first no-plaintext assertion in marker-absent
mode because absent state must preserve exact legacy bytes. The accepted test
therefore proves byte-exact absent behavior first and enters migration/encrypted
state before requiring ciphertext-only custody. The invalid draft is not
counted as acceptance evidence.

The final exact test-contract results were:

| Proof | Final result | Final-session raw log SHA-256 |
|---|---|---|
| Seven focused `TestRelayNotificationClosure_PushRoute...` rows | 7 discovered; 7 top-level PASS; 0 SKIP | `14b2071f2c3ac88b4bf36ccb86def5e1c4baff30fb4568eec0b578cad946fb25` |
| TC-367-03 concurrency owner with `-race` | 1 PASS; 0 SKIP | `329ace07e56f3ae531b83046d24853c2b68445253cce61e4369e4362c9f212da` |
| Tagged process handoff with `-tags integration` | 1 discovered; 1 PASS; 0 SKIP | `91f237e797e807dbe7a4296126ddb61e441f96a7bd4144b4fabd7ea2ed7800f7` |
| Exact preservation sentinels | 13 discovered; 13 PASS; 0 SKIP | `a6f468ab3ff3e324c802e62f1988ecccd9c6e7ad26d676274367458a18163bc2` |

The race command emitted only the known nonfatal macOS linker
`LC_DYSYMTAB` warning. The process source and plan both intentionally use the
`integration` build tag.

### Serial semantic mutations

Each mutation was applied alone to the settled implementation, its owning test
was required to fail, the mutation was reverted, and the same owning test was
required to pass before the next mutation.

| Mutation | Required RED observed | Raw log SHA-256 |
|---|---|---|
| Remove migrating writer revision advancement | Register, unregister, and compare-revoke crossings failed to request reconciliation retry; verification crossings misclassified drift or failed convergence | `e27293ee6631cca4242c5a1fcbb048c658b9efad5cef628304ed85308e7a63d8` |
| Remove capabilities from authenticated AAD | Capability promotion and removal were accepted by `LookupRoute` instead of returning an integrity error | `cdcc6cbd98b8d008be5f24a4d3d70c34c04f319325e61f615cd8bae17fa093ac` |
| Enable retained-legacy fallback after encrypted cutover | Encrypted lookup returned the retained legacy route instead of failing closed | `445ce9462f6a680ec2fe28248f9689c6f7c5af7a6a7b9d8fdb6d892fe1a33e2b` |
| Restore peer-wide permanent-error deletion | A real Firebase permanent response deleted a concurrent refreshed registration | `d78ed6723dbaac59f71c76d721bf056aa1d00e7aa2a6c639e237f270725f49ca` |
| ACK explicit unregister before durable deletion | The stream returned `OK` while deletion was paused; failure paths also violated preservation/atomicity | `a2a3210fe214a353dfa3d084493d2e69c0e7ce618d9e1a12827ee22532c04a72` |
| Admit legacy cleanup before encrypted state | `CleanupLegacy()` succeeded before migration admission | `a4a27bbe789e075156557491a91ae9a507b35ef47a79690ed6d49f5d24c80525` |

No `PLAN367 MUTATION` marker remained in the frozen source. The restored tree
then passed the final focused, race, process, preservation, package, and hygiene
gates below.

## Final gates

| Gate | Final result |
|---|---|
| `bash scripts/run_test_gates.sh 1to1` | exit 0; Dart `+3205 ~10: All other tests passed!`; registered relay, ACK-custody, and media tails passed |
| `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)` | exit 0; `ok github.com/mknoon/relay-server 18.566s` |
| `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go vet ./...)` | exit 0; no warnings |
| All `go-relay-server/*.go` through `gofmt -l` | no output |
| `git diff --check` before and after the Graphify refresh | exit 0; no output |
| `bash -n` for the changed host scripts | exit 0 |
| `bash scripts/test/host_test_gate_batch_contract_test.sh` | `PASS: batched host test gate contract`; 9 rows / 10 Go calls proved |
| Exact synthetic `host-all --only go-relay-server/push_token_vault_process_integration_test.go` dispatch | one planned row; exact list matched; 1 PASS; 0 SKIP; row `#1356` passed |

Full `host-all` was deliberately not run. Repository cadence assigns the one
N02-wave `host-all` to Plan 368 after both relay slices. The exact shared shell
contract and the new synthetic row were run during this plan; registration does
not turn full `host-all` into a per-plan obligation. No phone was justified for
this Go relay storage/gateway slice.

## Current-source audit

The post-execution audit used production Go files only (`!*_test.go`) and found:

| Guard | Count |
|---|---:|
| `LookupToken` references | 0 |
| `.LookupRoute(` call sites | 1 |
| `.ResolveRoute(` call sites | 1 |
| Adapter calls to `sendRichPushThroughGateway` | 4 |
| `providerMessage.Token = target.Token` injection sites | 1 |
| Platform projection from `target.Platform` | 1 |

The sole lookup is the shared selector, the sole resolver is inside the private
gateway, and the four gateway callers are direct, direct-reaction,
group-reaction, and group notification paths. The exact focused source guard
also passed. An independent final contract audit re-read the strict codecs and
config, all three Redis states, migration/cutover races, startup under live
traffic, rotation/rewrap, exact legacy digest, compare-revoke, unregister,
cleanup, all four adapters, the process proof, and host registration; it found
no remaining semantic or code-contract blocker.

## Graph grounding

The required single incremental refresh ran after the final coherent code
change. A fresh compact review query was anchored on `pushRouteLease` and
`redisPushTokenBackend`.

| Graph fact | Final value |
|---|---|
| Freshness / confidence | `current` / `anchored` |
| Fingerprint | `76c930dc8afc22a2` |
| Nodes / edges | 75,539 / 110,629 |
| TDD overlay | 1,574 files / 15,654 named tests / 1,241 production targets |
| `graphify-arch/graphify-out/graph.json` SHA-256 | `7afa6c66319788c57e6696786ebfe30d87c03941e9568429b095c8516f619733` |
| `graphify-arch/graphify-out/manifest.json` SHA-256 | `b666965df293f74294e48a16d4e4744d17579653a7515edec1d917679fd5bc9c` |
| `graphify-arch/tdd-overlay.json` SHA-256 | `c88739999d5cbb2b691b91c3ff6971fd3011c5b478fb343c4d6b47a13715793f` |

The affected-surface query identified the relay node callers and the incumbent
ACK, dedupe, failover, presence, limits, payload, registration, and reaction
tests. The exact preservation bundle and full relay gate cover those reverse
dependencies.

## Frozen tested state

The shared worktree was intentionally dirty. An alternate Git index captured
all tracked files plus every untracked, nonignored file without replacing or
writing the shared index.

| Identity | Value |
|---|---|
| Capture time | `2026-08-15T11:47:51+02:00` |
| Base and unchanged `HEAD` | `3865aa9b8b8b000ecaf871a839d1fbdecaa0d86c` |
| `HEAD` tree | `a0a945780c196f16d852906607ed85a103770e59` |
| Frozen tested tree | `9ec76e3f99e222ba446801f2e5e1281725bdc05b` |
| Porcelain-v2 workspace snapshot SHA-256 | `3473c3919085622bc9b9dabc9780a682789a3371858e641e2aa1648157075ff8` |
| Porcelain-v2 records | 239 |
| Shared-index entries SHA-256 | `f5e25c72126c695528f43f407191869d53ec6109bd87b2d9be182001ec1a8a4f` |
| Shared-index entries | 6,348 |
| Shared-index byte SHA-256 | `cfa02381018fbb5d3da0f1c137c278bb07d7f1d2bfe7bda0a863105143d87226` |
| Alternate-index byte SHA-256 | `635a13bc17487993c77833846683e237efc2e733bc7ba6765a2bb5912144438d` |
| Toolchain | `go version go1.25.0 darwin/arm64` |

The source, tests, scripts, and refreshed Graphify artifacts in that tree are
the state on which the final gates and audit are based. This README, its sibling
checksum, and the plan's checked acceptance/progress edits necessarily postdate
and are intentionally absent from the self-describing frozen tested tree. No
product or test source changed after the freeze.

## Handoff

Plan 368 must validate this README's external checksum and copy both:

- frozen tested tree `9ec76e3f99e222ba446801f2e5e1281725bdc05b`; and
- Graphify fingerprint `76c930dc8afc22a2`.

It must preserve the immutable generation-bearing route API, exact migrated-
source digest, retained-key/environment rotation, one bounded stale reselect,
and exact compare-revoke semantics while replacing the rich provider payload at
the existing gateway. WP-07 alone may authorize real keys, migration admission,
deployment, observation, rollback, cleanup, or release.
