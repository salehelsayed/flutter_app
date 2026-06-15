/// Single dispatched benchmark entrypoint (124 Phase 5).
///
/// Every simulator/device benchmark harness was refactored into a pure library
/// exposing a `run<X>Benchmark(WidgetTester)` function. This entrypoint builds
/// the app ONCE and selects which benchmark to run via the `BENCHMARK`
/// dart-define, e.g.:
///
///   flutter test integration_test/benchmark_harness.dart \
///       -d DEVICE_ID --dart-define=BENCHMARK=ENCRYPTION
///
/// Per-benchmark fixtures (CLI_PEER_FIXTURE, BENCHMARK_SHARED_DIR,
/// BENCHMARK_RUN_ID) continue to be supplied as additional dart-defines and are
/// read independently inside each harness via `String.fromEnvironment`.
@Tags(['device'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'benchmark_1_1_send_harness.dart';
import 'benchmark_ack_harness.dart';
import 'benchmark_background_resume_harness.dart';
import 'benchmark_bridge_crossing_harness.dart';
import 'benchmark_connection_reuse_harness.dart';
import 'benchmark_encryption_harness.dart';
import 'benchmark_event_queue_harness.dart';
import 'benchmark_group_publish_harness.dart';
import 'benchmark_inbox_harness.dart';
import 'benchmark_media_harness.dart';
import 'benchmark_node_startup_harness.dart';
import 'benchmark_notification_tap_harness.dart';
import 'benchmark_relay_recovery_harness.dart';
import 'benchmark_routing_paths_harness.dart';
import 'benchmark_time_to_online_harness.dart';
import 'benchmark_timeout_accuracy_harness.dart';
import 'benchmark_voice_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final key = const String.fromEnvironment('BENCHMARK');

  testWidgets('benchmark $key', (tester) async {
    switch (key) {
      case 'ROUTING_PATHS':
        await runRoutingPathsBenchmark(tester);
      case 'BACKGROUND_RESUME':
        await runBackgroundResumeBenchmark(tester);
      case 'RELAY_RECOVERY':
        await runRelayRecoveryBenchmark(tester);
      case 'TIME_TO_ONLINE':
        await runTimeToOnlineBenchmark(tester);
      case 'NOTIFICATION_TAP':
        await runNotificationTapBenchmark(tester);
      case 'GROUP_PUBLISH':
        await runGroupPublishBenchmark(tester);
      case 'MEDIA':
        await runMediaBenchmark(tester);
      case 'ONE_TO_ONE_SEND':
        await runOneToOneSendBenchmark(tester);
      case 'TIMEOUT_ACCURACY':
        await runTimeoutAccuracyBenchmark(tester);
      case 'ENCRYPTION':
        await runEncryptionBenchmark(tester);
      case 'NODE_STARTUP':
        await runNodeStartupBenchmark(tester);
      case 'CONNECTION_REUSE':
        await runConnectionReuseBenchmark(tester);
      case 'INBOX':
        await runInboxBenchmark(tester);
      case 'ACK':
        await runAckBenchmark(tester);
      case 'BRIDGE_CROSSING':
        await runBridgeCrossingBenchmark(tester);
      case 'EVENT_QUEUE':
        await runEventQueueBenchmark(tester);
      case 'VOICE':
        await runVoiceBenchmark(tester);
      default:
        fail('Unknown BENCHMARK=$key');
    }
  });
}
