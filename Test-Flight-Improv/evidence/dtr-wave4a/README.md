# DTR Wave 4A acceptance evidence

Date: 2026-07-28

Scope: DTR-12 / Plan 288 and DTR-13 / Plan 289, including the authorized
Plans 290–292 closure work and narrow Plan-252 correction

Wave verdict: **Wave-accepted** on 2026-07-28

Execution shape: full `host-all`, batched Flutter, concurrency 4,
`failures-only`, continue-on-failure

## Aggregate receipt

The exact accepted command was:

```bash
./scripts/run_host_test_gates.sh host-all --continue-on-failure --batch-flutter --concurrency 4 --reporter failures-only
```

It planned and passed all 1,265 items:

- 1,257 exact Flutter test paths;
- 12,798 Flutter tests passed, one declared test skipped, and zero failed;
- all eight serial Go tails passed:
  - connected-peer bridge test;
  - node key-rotation suite;
  - address-visibility suite;
  - node feature-flags suite;
  - bridge partial-feature-flags suite;
  - wake-token suite;
  - node libp2p-refactor contract;
  - bridge-entrypoint-refactor contract;
- final `PASS: host tests completed for scope: host-all`;
- process exit 0;
- duration 1,136 seconds.

The accepted original log and deterministic `gzip -n` archive are:

| Artifact | Path | SHA-256 |
|---|---|---|
| Original log | `build/wave4a-logs/wave4a-host-all-accepted.log` | `d61df5a5ab9949f44887bcf32c1e877dcc39a10ef110682e066bfb6cbbb4f899` |
| Deterministic archive | `Test-Flight-Improv/evidence/dtr-wave4a/wave4a-host-all-accepted.log.gz` | `428e449eabfabda52828461df64badee532c6905673375017745c3b5280a7434` |

Decompressing the archive reproduces the original-log SHA-256 exactly.

## Tested state and workspace disclosure

The aggregate ran in the shared dirty workspace, not in a detached worktree.
It used the workspace and toolchain state already present at execution time.
No ignored native or runtime prerequisite was copied into another worktree for
this `host-all` run.

The tested state was captured through an alternate Git index that included
tracked files plus untracked, nonignored files. It did not rewrite the shared
index:

- base commit and unchanged `HEAD`:
  `765be74523b25ce592ff200ff435653b35c66b4d`;
- tested tree:
  `14a72da9b5b702b37466e155a77007e0335d0559`;
- synthetic commit:
  `669c7039846f321a8171b63df09e087e43b1f319`;
- annotated tag:
  `dtr-wave4a-tested-tree-20260728`;
- annotated-tag object:
  `75f0230dc0e6509b4a4045c0588fd7b03d0fce0d`;
- shared-index SHA-256 before and after capture:
  `9aa55ac41a8db648ae4a8eb12a95820c0d3882ce09a01d1fa94ead8ef1c670dc`.

The synthetic commit has the base commit as its parent and the tested tree as
its tree. The later closure-document edits and deterministic archive are
post-test receipts and are not represented as files in that tested tree.

## Coherent Sims receipts

The final coherent Sims source digest is
`73f4339412d85b7846f45894a122aa174f87141771fa121666a3ff06a3f0e825`.
Every final report and proof was independently reverified against the coherent
receipt set and was green.

| Journey | Accepted result | Report SHA-256 | Proof SHA-256 |
|---|---|---|---|
| Android wake directionality | 2/2 PASS | `0a286828746388173e6c489b864cad57b1defda10f17fffb889b7577556827e2` | `f5067faf9b1bdca64480fb39fca44fd4c295f8ff87e848aab55998dcf0771bc5` |
| Introduction notification roles | 2/2 PASS | `e75c34a00b01c967b4d0ef825ec6a71437a3696b7972e6613080da410c5b1cf6` | `1cd87227a523523c9a490787b0a8ab0cad98fb1e942b9bccd2904113ebafcc5b` |
| Group and announcement reactions | 4/4 PASS | `c0d14c28193c5f750320c8addf2b22f415ca287dc4e5ca836b37f0f32f9b0672` | `76299c7874dd9684df81e8beba88fa3fe14cff2388f6b79c9a6e883ad51b52b1` |
| iOS APNs/NSE/offline tap | 7/7 assertions PASS | `1dae730ef1a55c9328ad922b9fa95b68804ffa8ce667652bfbb627e149cee5fa` | `36dd4c649b40b2aa9ad9f139bb423ce618f8de20923f21fefa5fea5fe88ff653` |

The iOS build report SHA-256 is
`69b351e9c607cd803eac76192d0e12ee5d5ca4b963297252d05ec80cc72a00a5`.
The final iOS receipt also records `apps=[]` cleanup, no private-handoff
residue, `childBuildCount=0`, and `manualActionCount=0`.

## Integrated closure receipts

- `core-host-all`: 362 planned items, 2,825 tests passed, renderer manifest
  PASS, and approximately 428 seconds;
- strict analysis: PASS with zero diagnostics in 306.8 seconds;
- incremental Graphify graph SHA-256:
  `af9593753ea0236ca568db561d8d6af2c0eacefb2ac7689b073483037c080b53`;
- deterministic Graphify overlay SHA-256:
  `fc87b54355ea8eea9fb9b726cbd50c088c3c0d805da065c8c2acfa2d45cbe7cb`.

The accepted boundary remains exactly 182 forbidden dependencies, 24
placement pins, and 92 debug exceptions. No exception was rebaselined. The
manual smoke roots, smoke runner, and supported Sims profiles remain retained.

This receipt accepts DTR-12 and DTR-13 in Wave 4A and closes
`DTR13-AUTH-01`'s authorized implementation/acceptance scope. It clears the
DTR-14 and DTR-15 predecessor dependencies for **planning only**; it does not
authorize either plan's execution. The final release-closure `host-all`
remains a separate later obligation.
