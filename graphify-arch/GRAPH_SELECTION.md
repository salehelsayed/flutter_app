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
| nodes | 99982 | 39955 | -60.04% |
| edges | 172181 | 62368 | -63.78% |
| communities | 4293 | 852 | -80.15% |
| source files | 5286 | 2044 | -61.33% |
| avg edges per node | 1.7221 | 1.561 | -9.35% |
| avg nodes per community | 23.29 | 46.9 | +101.37% |
| app-owned ratio | 0.4375 | 0.9616 | +119.79% |
| noise ratio | 0.2182 | 0.0 | -100.00% |
| unknown-source ratio | 0.0184 | 0.0384 | +108.70% |
| top-10 hub noise ratio | 0.5 | 0.0 | -100.00% |

## Top Hubs
Full graph top hubs:
- `sqlite3.c` (4359 edges, noise) `ios/Pods/SQLCipher/sqlite3.c`
- `sqlite3.c` (4359 edges, noise) `macos/Pods/SQLCipher/sqlite3.c`
- `_` (2035 edges, noise) `integration_test/group_multi_party_device_real_harness.dart`
- `SQLITE_PRIVATE` (1036 edges, noise) `ios/Pods/SQLCipher/sqlite3.c`
- `SQLITE_PRIVATE` (1036 edges, noise) `macos/Pods/SQLCipher/sqlite3.c`
- `package:flutter_test/flutter_test.dart` (951 edges, signal) ``
- `group_multi_party_device_criteria.dart` (687 edges, signal) `integration_test/scripts/group_multi_party_device_criteria.dart`
- `app_localizations.dart` (669 edges, signal) `lib/l10n/app_localizations.dart`
- `app_localizations_ar.dart` (651 edges, signal) `lib/l10n/app_localizations_ar.dart`
- `app_localizations_de.dart` (651 edges, signal) `lib/l10n/app_localizations_de.dart`

Architecture graph top hubs:
- `group_multi_party_device_real_harness.dart` (2002 edges, signal) `integration_test/group_multi_party_device_real_harness.dart`
- `package:flutter_test/flutter_test.dart` (951 edges, signal) ``
- `group_multi_party_device_criteria.dart` (681 edges, signal) `integration_test/scripts/group_multi_party_device_criteria.dart`
- `main.dart` (565 edges, signal) `lib/main.dart`
- `dart:convert` (400 edges, signal) ``
- `group_multi_party_device_criteria_test.dart` (398 edges, signal) `test/integration/group_multi_party_device_criteria_test.dart`
- `package:flutter/material.dart` (394 edges, signal) ``
- `feed_wired.dart` (354 edges, signal) `lib/features/feed/presentation/screens/feed_wired.dart`
- `group_conversation_wired.dart` (343 edges, signal) `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `conversation_wired.dart` (329 edges, signal) `lib/features/conversation/presentation/screens/conversation_wired.dart`

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
