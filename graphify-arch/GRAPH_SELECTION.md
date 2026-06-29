# Graphify Graph Selection

## Definitions
- Full graph: `graphify-out/graph.json`. Broad code-only index of every detected code file in the repo, including platform/vendor/generated code.
- Architecture graph: `graphify-arch/graphify-out/graph.json`. Focused app-owned graph built from `.graphify-arch-src/` symlinks and `.graphifyignore` filters.

## Selection Rule
- Use the architecture graph for app architecture, feature flows, repository/service/UI relationships, and day-to-day code navigation.
- Use the full graph when you need exhaustive symbol lookup across generated/native/vendor/platform code.

## Metrics
| Metric | Full | Architecture | Delta |
| --- | ---: | ---: | ---: |
| nodes | 106263 | 42868 | -59.66% |
| edges | 180163 | 66833 | -62.90% |
| communities | 4500 | 915 | -79.67% |
| source files | 5596 | 2217 | -60.38% |
| avg edges per node | 1.6954 | 1.559 | -8.05% |
| avg nodes per community | 23.61 | 46.85 | +98.43% |
| app-owned ratio | 0.4437 | 0.9611 | +116.61% |
| noise ratio | 0.2056 | 0.0 | -100.00% |
| unknown-source ratio | 0.0189 | 0.0389 | +105.82% |
| top-10 hub noise ratio | 0.5 | 0.0 | -100.00% |

## Top Hubs
Full graph top hubs:
- `sqlite3.c` (4359 edges, noise) `ios/Pods/SQLCipher/sqlite3.c`
- `sqlite3.c` (4359 edges, noise) `macos/Pods/SQLCipher/sqlite3.c`
- `_` (2064 edges, noise) `integration_test/group_multi_party_device_real_harness.dart`
- `SQLITE_PRIVATE` (1036 edges, noise) `ios/Pods/SQLCipher/sqlite3.c`
- `SQLITE_PRIVATE` (1036 edges, noise) `macos/Pods/SQLCipher/sqlite3.c`
- `package:flutter_test/flutter_test.dart` (1035 edges, signal) ``
- `app_localizations.dart` (768 edges, signal) `lib/l10n/app_localizations.dart`
- `app_localizations_ar.dart` (750 edges, signal) `lib/l10n/app_localizations_ar.dart`
- `app_localizations_de.dart` (750 edges, signal) `lib/l10n/app_localizations_de.dart`
- `app_localizations_en.dart` (750 edges, signal) `lib/l10n/app_localizations_en.dart`

Architecture graph top hubs:
- `group_multi_party_device_real_harness.dart` (2029 edges, signal) `integration_test/group_multi_party_device_real_harness.dart`
- `package:flutter_test/flutter_test.dart` (1035 edges, signal) ``
- `group_multi_party_device_criteria.dart` (684 edges, signal) `integration_test/scripts/group_multi_party_device_criteria.dart`
- `main.dart` (585 edges, signal) `lib/main.dart`
- `package:flutter/material.dart` (423 edges, signal) ``
- `dart:convert` (419 edges, signal) ``
- `group_multi_party_device_criteria_test.dart` (398 edges, signal) `test/integration/group_multi_party_device_criteria_test.dart`
- `group_conversation_wired.dart` (370 edges, signal) `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `feed_wired.dart` (352 edges, signal) `lib/features/feed/presentation/screens/feed_wired.dart`
- `conversation_wired.dart` (350 edges, signal) `lib/features/conversation/presentation/screens/conversation_wired.dart`

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
