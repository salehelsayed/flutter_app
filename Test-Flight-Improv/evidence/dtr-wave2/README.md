# DTR Wave 2 host-all evidence

Date: 2026-07-27  
Scope: retained DTR-06 and Plan-green DTR-07 / Plan 286  
Wave verdict: **Wave-accepted** on 2026-07-27
Execution shape: full `host-all`, batched Flutter, concurrency 4,
`failures-only`, continue-on-failure

All three archives are deterministic `gzip -n` copies of the original logs.
The “uncompressed SHA-256” values identify the exact original log bytes.

| Attempt | Verdict | Archive | Uncompressed SHA-256 | Archive SHA-256 |
|---|---|---|---|---|
| 1 | Non-green integrated-tree diagnostic: Flutter `+12,819 ~1 -5`; all eight Go tails passed | `wave2-host-all-attempt-1-integrated-failures.log.gz` | `c838804bb2095d3841ee8116da6b0e38b510e0345cf7070c395ca8f81fd564c3` | `97870d546fe1b6606bf2da24a43a6e76a0dc6359b382617f7a640a8964811a32` |
| 2 | Rejected execution environment: the temporary `GIT_INDEX_FILE` isolation correctly tripped repository-redirection guards; Flutter `+12,822 ~1 -5`; all eight Go tails passed | `wave2-host-all-attempt-2-rejected-index-env.log.gz` | `6167749d53ce32954e44c0e2ee6d98a39dcfe823443cac623ebe0e7b788285ab` | `921794ff7824c7026516a4507db256de6f5669affc7542e34e9f81ac52c6baa6` |
| 3 | **Accepted:** Flutter `+12,827 ~1`, all eight Go tails passed, overall exit 0 | `wave2-host-all-attempt-3-accepted.log.gz` | `869a75236f97e34f610b4053540f7e7b449ea76103f5d807d52c82aae5d4c135` | `4ea8d999b37de940459fb905cecf894b0ee325ab4f7c9a6ee48d00f9bc9f69b2` |

Each completed attempt planned 1,259 exact Dart test paths plus eight Go tails,
for 1,267 items.

Attempt 1 exposed three integrated closure issues:

- the new Android-only group multi-party harness lacked its reliability
  discovery `support` classification, which failed three fail-closed
  consumers;
- the profile-picture integration test used a fixed 500 ms sleep and asserted
  just before its successful asynchronous update completed under batch load;
- seven already-authorized, terminal DTR-10 source deletions were still
  unstaged, so the real-tree runtime-root guard reported deletion drift.

The correction added the missing support classification, replaced the fixed
sleep with a bounded condition wait, and staged only those seven already
deleted DTR-10 source paths. The last step changed Git index state only; it did
not change file contents or broadly stage the working tree. The discovery
script then passed, the three discovery consumers plus the full profile flow
passed together (37 tests), and the complete analyzer-ratchet/runtime-root pair
passed together (25 tests).

Attempt 2 tested a temporary copied-index alternative before changing the real
index. Four analyzer-guard cases correctly rejected `GIT_INDEX_FILE`, and one
runtime-root fixture inherited that redirected index. This was an invalid
execution environment, not an application failure, and it was not used for
acceptance.

Attempt 3 used the normal repository environment:

```bash
./scripts/run_host_test_gates.sh host-all \
  --continue-on-failure \
  --batch-flutter \
  --concurrency 4 \
  --reporter failures-only
```

It passed all 1,267 planned items:

- 1,259 Flutter paths;
- 12,827 tests passed and one skipped;
- all eight Go tails passed;
- final `PASS: host tests completed for scope: host-all`;
- process exit 0.

The tested state was Git
`95d754e03fc67e21d5006efd1fbec2dddaada394` plus the integrated uncommitted
working-tree delta, including Plan 286 and later DTR-10/Plan-285 work. The two
closure corrections changed only a discovery script and a test. No production
source changed.

Durability note: the later integrated validation snapshot
`ec268ce4a41d94450919170c9df2b1bf1a7ef987` contains this complete evidence
pack and is retained in repository history. It is not claimed as the exact
Wave 2 tested tree: the accepted Wave 2 receipt remains explicitly identified
as `95d754e...` plus its then-current integrated working-tree delta.

Before these completed attempts, a concurrency-1 process was stopped before
completion when the repository gate audit confirmed concurrency 4 as the
supported broad-gate setting. That incomplete process is not acceptance
evidence.
