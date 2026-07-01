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
| nodes | 106978 | 43123 | -59.69% |
| edges | 180983 | 67173 | -62.88% |
| communities | 4524 | 933 | -79.38% |
| source files | 5637 | 2234 | -60.37% |
| avg edges per node | 1.6918 | 1.5577 | -7.93% |
| avg nodes per community | 23.65 | 46.22 | +95.43% |
| app-owned ratio | 0.443 | 0.9611 | +116.95% |
| noise ratio | 0.2045 | 0.0 | -100.00% |
| unknown-source ratio | 0.0189 | 0.0389 | +105.82% |
| top-10 hub noise ratio | 0.5 | 0.0 | -100.00% |

## Top Hubs
Full graph top hubs:
- `sqlite3.c` (4359 edges, noise) `ios/Pods/SQLCipher/sqlite3.c`
- `sqlite3.c` (4359 edges, noise) `macos/Pods/SQLCipher/sqlite3.c`
- `_` (2064 edges, noise) `integration_test/group_multi_party_device_real_harness.dart`
- `package:flutter_test/flutter_test.dart` (1045 edges, signal) ``
- `SQLITE_PRIVATE` (1036 edges, noise) `ios/Pods/SQLCipher/sqlite3.c`
- `SQLITE_PRIVATE` (1036 edges, noise) `macos/Pods/SQLCipher/sqlite3.c`
- `app_localizations.dart` (768 edges, signal) `lib/l10n/app_localizations.dart`
- `app_localizations_ar.dart` (750 edges, signal) `lib/l10n/app_localizations_ar.dart`
- `app_localizations_de.dart` (750 edges, signal) `lib/l10n/app_localizations_de.dart`
- `app_localizations_en.dart` (750 edges, signal) `lib/l10n/app_localizations_en.dart`

Architecture graph top hubs:
- `group_multi_party_device_real_harness.dart` (2029 edges, signal) `integration_test/group_multi_party_device_real_harness.dart`
- `package:flutter_test/flutter_test.dart` (1045 edges, signal) ``
- `group_multi_party_device_criteria.dart` (684 edges, signal) `integration_test/scripts/group_multi_party_device_criteria.dart`
- `main.dart` (593 edges, signal) `lib/main.dart`
- `package:flutter/material.dart` (423 edges, signal) ``
- `dart:convert` (422 edges, signal) ``
- `group_multi_party_device_criteria_test.dart` (398 edges, signal) `test/integration/group_multi_party_device_criteria_test.dart`
- `group_conversation_wired.dart` (370 edges, signal) `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `package:flutter_app/core/utils/flow_event_emitter.dart` (354 edges, signal) ``
- `feed_wired.dart` (352 edges, signal) `lib/features/feed/presentation/screens/feed_wired.dart`

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
