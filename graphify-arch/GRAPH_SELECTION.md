# Graphify Graph Selection

## Definitions
- Full graph: `graphify-out/graph.json`. Broad code-only index of every detected code file in the repo, including platform/vendor/generated code.
- Architecture graph: `graphify-arch/graphify-out/graph.json`. Focused app-owned graph built from `.graphify-arch-src/` symlinks and `.graphifyignore` filters.

## Selection Rule
- Use the architecture graph for app architecture, feature flows, repository/service/UI relationships, and day-to-day code navigation.
- Use the full graph when you need exhaustive symbol lookup across generated/native/vendor/platform code.
- `tdd_context.py query` checks exact filename/path targets against both manifests. A compact-graph miss reports `full_graph_fallback` when the full graph owns the target, or `raw_search_fallback` when neither graph can answer it.

## Compact Query Measurement

Each compact query prints a `query_id`. Link the one allowed broad-result refinement with:

```bash
python3 graphify-arch/tdd_context.py query "<exact refinement>" \
  --profile general --budget 600 \
  --stage refinement --refines <query_id>
```

Usage telemetry stores hashed Codex session/thread identifiers, output size,
truncation, route, stage, and confidence without storing question text.

```bash
python3 graphify-arch/tdd_context.py stats --last 100
python3 graphify-arch/tdd_context.py benchmark
```

The repository benchmark verifies delivered source/proof paths and required
output markers under the configured budgets. It complements Graphify's corpus
compression benchmark below; the two measure different boundaries.

## Metrics
| Metric | Full | Architecture | Delta |
| --- | ---: | ---: | ---: |
| nodes | 125920 | 63016 | -49.96% |
| edges | 213557 | 96398 | -54.86% |
| communities | 4883 | 1195 | -75.53% |
| source files | 6459 | 2885 | -55.33% |
| avg edges per node | 1.696 | 1.5297 | -9.81% |
| avg nodes per community | 25.79 | 52.73 | +104.46% |
| app-owned ratio | 0.4831 | 0.9603 | +98.78% |
| noise ratio | 0.175 | 0.0 | -100.00% |
| unknown-source ratio | 0.0268 | 0.0397 | +48.13% |
| top-10 hub noise ratio | 0.4 | 0.0 | -100.00% |

## Top Hubs
Full graph top hubs:
- `sqlite3.c` (4359 edges, noise) `ios/Pods/SQLCipher/sqlite3.c`
- `sqlite3.c` (4359 edges, noise) `macos/Pods/SQLCipher/sqlite3.c`
- `group_multi_party_device_real_harness.dart` (2073 edges, signal) `integration_test/group_multi_party_device_real_harness.dart`
- `package:flutter_test/flutter_test.dart` (1340 edges, signal) ``
- `SQLITE_PRIVATE` (1036 edges, noise) `ios/Pods/SQLCipher/sqlite3.c`
- `SQLITE_PRIVATE` (1036 edges, noise) `macos/Pods/SQLCipher/sqlite3.c`
- `app_localizations.dart` (953 edges, signal) `lib/l10n/app_localizations.dart`
- `app_localizations_ar.dart` (934 edges, signal) `lib/l10n/app_localizations_ar.dart`
- `app_localizations_de.dart` (934 edges, signal) `lib/l10n/app_localizations_de.dart`
- `app_localizations_en.dart` (934 edges, signal) `lib/l10n/app_localizations_en.dart`

Architecture graph top hubs:
- `group_multi_party_device_real_harness.dart` (2045 edges, signal) `integration_test/group_multi_party_device_real_harness.dart`
- `package:flutter_test/flutter_test.dart` (1406 edges, signal) ``
- `group_multi_party_device_criteria.dart` (690 edges, signal) `integration_test/scripts/group_multi_party_device_criteria.dart`
- `dart:convert` (608 edges, signal) ``
- `dart:io` (586 edges, signal) ``
- `reaction_notification_proof_support.dart` (553 edges, signal) `integration_test/scripts/reaction_notification_proof_support.dart`
- `group_conversation_wired.dart` (524 edges, signal) `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `package:flutter/material.dart` (521 edges, signal) ``
- `dart:async` (487 edges, signal) ``
- `conversation_wired.dart` (473 edges, signal) `lib/features/conversation/presentation/screens/conversation_wired.dart`

## Method
- Efficiency means fewer nodes, fewer edges, fewer communities, and lower average traversal breadth for the same app-level question.
- Value means more app-owned source nodes, less vendored/generated noise, and fewer generic/vendor symbols among the top hubs.
- Graphify's built-in benchmark measures token compression against each graph's own corpus baseline. Use it as a cost proxy, not as the only value metric.
- Rebuild the architecture graph and refresh this comparison:

```bash
graphify-arch/refresh_arch_graph.sh
```

- Re-run this comparison after rebuilding either graph:

```bash
python3 graphify-arch/compare_graphs.py \
  --full graphify-out/graph.json \
  --arch graphify-arch/graphify-out/graph.json \
  --out graphify-arch/GRAPH_SELECTION.md \
  --json-out graphify-arch/comparison.json
```

Optional token-compression benchmark:

```bash
graphify benchmark graphify-out/graph.json
graphify benchmark graphify-arch/graphify-out/graph.json
```
