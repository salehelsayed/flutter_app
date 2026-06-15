import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/diagnostics/app_build_info.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

void main() {
  test(
    'emitAppBuildInfo emits exactly one APP_BUILD_INFO milestone carrying build '
    'provenance',
    () {
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      addTearDown(() => debugSetFlowEventSink(null));

      emitAppBuildInfo();

      final buildInfoEvents = events
          .where((event) => event['event'] == 'APP_BUILD_INFO')
          .toList();
      expect(buildInfoEvents, hasLength(1));

      final entry = buildInfoEvents.single;
      expect(entry['layer'], 'FL');
      final details = entry['details'] as Map<String, dynamic>;
      expect(details.containsKey('gitSha'), isTrue);
      expect(details.containsKey('gitDirty'), isTrue);
      expect(details.containsKey('buildTimestamp'), isTrue);
      // Reflects the compile-time --dart-define values (empty when not supplied,
      // e.g. a plain `flutter test`/`flutter run`).
      expect(details['gitSha'], const String.fromEnvironment('GIT_SHA'));
      expect(details['gitDirty'], const String.fromEnvironment('GIT_DIRTY'));
    },
  );
}
