import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/app/bootstrap/best_effort_startup_backfill.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// A self-healing startup backfill must never be able to abort the deferred
/// runtime start, because `StartupRouter._doStartP2P` awaits that start before
/// it calls `startP2PNode`. An escaping error leaves the P2P node unstarted, so
/// the connection badge renders "Offline" until the app is relaunched
/// (device-reproduced 2026-08-21, iPhone 11 + iPhone 13).
void main() {
  final captured = <Map<String, dynamic>>[];

  setUp(() {
    captured.clear();
    debugSetFlowEventSink(captured.add);
  });

  tearDown(() => debugSetFlowEventSink(null));

  test('a throwing backfill is reported and skipped, never rethrown', () async {
    await expectLater(
      runBestEffortStartupBackfill(
        'group_context_backfill',
        () async => throw StateError(
          'group notification projection owner is unavailable',
        ),
      ),
      completes,
    );

    final skipped = captured
        .where((e) => e['event'] == 'RUNTIME_STARTUP_BACKFILL_SKIPPED')
        .toList();
    expect(skipped, hasLength(1));
    expect(skipped.single['details']['step'], 'group_context_backfill');
    expect(skipped.single['details']['errorType'], 'StateError');
  });

  test('a successful backfill runs and emits no skip event', () async {
    var ran = false;
    await runBestEffortStartupBackfill('group_context_backfill', () async {
      ran = true;
    });

    expect(ran, isTrue);
    expect(
      captured.where((e) => e['event'] == 'RUNTIME_STARTUP_BACKFILL_SKIPPED'),
      isEmpty,
    );
  });
}
