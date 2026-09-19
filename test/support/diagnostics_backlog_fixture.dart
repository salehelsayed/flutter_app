import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// Synthetic, consented history at the scale of the retained phone profile.
/// All identifiers are generated fixture IDs, never captured user metadata.
Future<int> writeDiagnosticsBacklogFixture(
  Directory directory, {
  required DateTime now,
  required String platform,
}) => Isolate.run(() async {
  String id(int value) =>
      '00000000-0000-4000-8000-${value.toRadixString(16).padLeft(12, '0')}';
  final at = now.millisecondsSinceEpoch;
  final events = <Map<String, Object?>>[
    for (var index = 0; index < 9760; index++)
      {
        'schemaVersion': 1,
        'eventId': id(1000000 + index),
        'source': 'flutter',
        'runId': id(1),
        'sequence': index + 1,
        'occurredAtMs': at - 1000,
        'elapsedMs': index,
        'feature': 'media',
        'stage': 'download',
        'outcome': 'ok',
        'reason': 'none',
        'build': 'connectivity-fixture',
        'platform': platform,
        'traceId': id(1000 + index ~/ 122),
        'values': {'durationMs': 1},
      },
  ];
  final state = {
    'schemaVersion': 1,
    'enabled': true,
    'consentEpoch': at,
    'clearPending': false,
    'nativeClearPending': false,
    'dropped': 0,
    'nativeDroppedSeen': 0,
    'lastUploadAtMs': 0,
    'bindingSalt': '1' * 64,
    'bindings': {
      for (var index = 0; index < 1000; index++)
        index.toRadixString(16).padLeft(64, '0'): {
          'traceId': id(20000 + index),
          'updatedAtMs': at - 1000,
        },
    },
    'events': events,
    'uploaded': events.map((event) => event['eventId']).toList(),
    'open': <Object?>[],
  };
  final bytes = utf8.encode(jsonEncode(state));
  await directory.create(recursive: true);
  await File('${directory.path}/state.json').writeAsBytes(bytes, flush: true);
  return bytes.length;
});
