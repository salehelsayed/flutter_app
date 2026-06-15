/// Single dispatched performance entrypoint (124 Phase 5).
///
/// Every UI performance harness was refactored into a pure library exposing a
/// `register<X>Perf()` function that REGISTERS its `testWidgets` cases. This
/// entrypoint selects which harness to register via the `PERF_TARGET`
/// dart-define, e.g.:
///
///   flutter test integration_test/performance_harness.dart \
///       -d DEVICE_ID --dart-define=PERF_TARGET=CONVERSATION
///
/// The `register<X>Perf()` calls run at `main()` top level so their
/// `testWidgets` cases register and `flutter test` runs them — each with a
/// fresh widget tree. Most harnesses self-skip on real mobile devices and
/// capture richer evidence on macOS/desktop; each reads any additional
/// configuration it needs independently. The dispatcher only routes on
/// `PERF_TARGET`.
@Tags(['device'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'conversation_wired_performance_harness.dart';
import 'conversation_wired_subscription_performance_harness.dart';
import 'feed_performance_test.dart';
import 'feed_wired_init_performance_harness.dart';
import 'identity_progress_performance_test.dart';
import 'orbit_performance_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const target = String.fromEnvironment('PERF_TARGET');

  switch (target) {
    case 'FEED':
      registerFeedPerf();
      break;
    case 'FEED_INIT':
      registerFeedInitPerf();
      break;
    case 'CONVERSATION':
      registerConversationPerf();
      break;
    case 'CONVERSATION_SUB':
      registerConversationSubPerf();
      break;
    case 'ORBIT':
      registerOrbitPerf();
      break;
    case 'IDENTITY_PROGRESS':
      registerIdentityProgressPerf();
      break;
    default:
      testWidgets('unknown PERF_TARGET', (tester) async {
        fail('Unknown PERF_TARGET=$target');
      });
  }
}
