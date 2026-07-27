# DTR Wave 1 host-all evidence

Date: 2026-07-26  
Scope: DTR-03, DTR-04, and DTR-05  
Execution shape: full `host-all`, batched Flutter, concurrency 1,
`failures-only`, continue-on-failure

Both archives are deterministic `gzip -n` copies of the original logs. The
“uncompressed SHA-256” values identify the exact original log bytes.

| Attempt | Verdict | Archive | Uncompressed SHA-256 | Archive SHA-256 |
|---|---|---|---|---|
| 1 | Non-green: one Flutter assertion required consecutive requests to use the same TCP source port; all eight Go tails passed | `wave1-host-all-attempt-1-non-green.log.gz` | `2a8d20fca9d4c60cab49194f89071153b9f9108fae1d1d8245b002dfae397401` | `40d38709edab5e78ce406b062966fc2e70d14be48378bfe1197109ce1106b895` |
| 2 | Accepted: Flutter `+12,863 ~1`, all eight Go tails passed, overall exit 0 | `wave1-host-all-attempt-2-accepted.log.gz` | `781a669fbfbdebf0b50bb7abad824fac9166aef83f5ddce0ee34efc9805b22b5` | `1708287be02ebf6186b7bf186e81aca66ecf9ba0e4cf47884bfa0c272ba33c4e` |

Each attempt planned 1,265 exact Dart test paths plus eight Go tails, for 1,273
items. Attempt 1 completed Flutter at `+12,862 ~1 -1`; its only failure was
`account_migration_local_transfer_runtime_test.dart` expecting one request's
TCP source port to equal the preceding request's port. Dart may choose another
pooled socket. The test-only correction removed that port-equality assertion
while retaining the killed-connection timeout classification, command order,
forced client close, cleanup, and telemetry checks. No production source
changed.

Correction validation before Attempt 2:

- corrected selector: 20/20 repeated passes;
- complete runtime test file: 40 passed;
- `move-feature`: `+442 ~1`, no failures.

Attempt 2 is the Wave 1 acceptance run:

- 1,265 Flutter paths;
- 12,863 tests passed and one skipped;
- all eight Go tails passed;
- final `PASS: host tests completed for scope: host-all`.

The test state was Git `95d754e03fc67e21d5006efd1fbec2dddaada394`
plus the uncommitted test-only assertion correction. Concurrent documentation
and Graphify-output changes were present but did not alter the executed tests.
