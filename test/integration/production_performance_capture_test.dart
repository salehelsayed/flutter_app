import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/debug/production_journeys/production_performance_capture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late bool logging;
  setUp(() {
    logging = flowEventLoggingEnabled;
    flowEventLoggingEnabled = false;
  });
  tearDown(() {
    flowEventLoggingEnabled = logging;
    debugSetFlowEventSink(null);
  });
  void emit(String name, [Map<String, Object?> details = const {}]) =>
      emitFlowEvent(layer: 'FL', event: name, details: details);

  test('captures only retained metrics and sanitized immutable facts', () {
    final capture = ProductionPerformanceCapture();
    addTearDown(capture.dispose);
    emit('IRRELEVANT_EVENT', {'text': 'secret-message'});
    emit('TIME_TO_SENDABLE_BADGE', {
      'totalMs': 12,
      'phase': 'cold_start',
      'privateKey': 'never-retain',
      'nested': {'totalMs': 9},
    });
    final snapshot = capture.snapshot();
    final events = snapshot['events'] as List;
    expect(events, hasLength(1));
    expect(events.single['details']['privateKey'], '[redacted]');
    expect(jsonEncode(snapshot), isNot(contains('never-retain')));
    expect(events.single['sequence'], 1);
    expect(events.single['observedMicros'], greaterThanOrEqualTo(0));
    events.single['details']['nested']['totalMs'] = -1;
    expect(
      (capture.snapshot()['events'] as List)
          .single['details']['nested']['totalMs'],
      9,
    );
  });

  testWidgets('observes framework lifecycle without invoking recovery', (
    tester,
  ) async {
    final capture = ProductionPerformanceCapture();
    addTearDown(capture.dispose);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final events = capture.snapshot()['events'] as List;
    expect(events.map((e) => e['details']['state']), ['paused', 'resumed']);
    expect(capture.snapshot()['lifecycle'], 'resumed');
    capture.dispose();
  });

  test('overflow fails closed instead of truncating a passing measurement', () {
    final capture = ProductionPerformanceCapture();
    addTearDown(capture.dispose);
    for (var i = 0; i < 1025; i++) {
      emit('TIME_TO_SENDABLE_BADGE');
    }
    expect(capture.snapshot, throwsStateError);
  });

  testWidgets('pause receipt retains actual state before resume mutations', (
    tester,
  ) async {
    final capture = ProductionPerformanceCapture();
    addTearDown(capture.dispose);
    var ready = true;
    final details = <String, Object?>{'epoch': 1};
    capture.bindPausedObserver(
      () => {...capture.snapshot(), 'sendReady': ready, 'details': details},
    );
    expect(capture.pausedSnapshot, throwsStateError);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    ready = false;
    details['epoch'] = 2;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final paused = capture.pausedSnapshot();
    expect(paused['lifecycle'], 'paused');
    expect(paused['sendReady'], isTrue);
    expect((paused['details'] as Map)['epoch'], 1);
    expect((paused['events'] as List).last['details']['state'], 'paused');
    (paused['details'] as Map)['epoch'] = 99;
    expect((capture.pausedSnapshot()['details'] as Map)['epoch'], 1);
    capture.clearPausedSnapshot();
    expect(capture.pausedSnapshot, throwsStateError);
    capture.dispose();
  });

  testWidgets('a new window cannot reuse the previous pause receipt', (
    tester,
  ) async {
    final capture = ProductionPerformanceCapture();
    addTearDown(capture.dispose);
    capture.bindPausedObserver(capture.snapshot);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final first = capture.pausedSnapshot();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    capture.clearPausedSnapshot();
    expect(capture.pausedSnapshot, throwsStateError);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(
      (capture.pausedSnapshot()['events'] as List).length,
      greaterThan((first['events'] as List).length),
    );
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    capture.dispose();
    expect(capture.pausedSnapshot, throwsStateError);
  });

  test('paused observer ownership cannot be replaced or revived', () {
    final capture = ProductionPerformanceCapture();
    capture.bindPausedObserver(capture.snapshot);
    expect(() => capture.bindPausedObserver(() => {}), throwsStateError);
    capture.dispose();
    expect(() => capture.bindPausedObserver(() => {}), throwsStateError);
  });

  test('disposal restores the existing observer and rejects stale reads', () {
    var received = 0;
    debugSetFlowEventSink((_) => received++);
    final capture = ProductionPerformanceCapture();
    capture.dispose();
    capture.dispose();
    emit('TIME_TO_SENDABLE_BADGE');
    expect(received, 1);
    expect(capture.snapshot, throwsStateError);
  });

  testWidgets('expired capture releases ownership without passing', (
    tester,
  ) async {
    var received = 0;
    debugSetFlowEventSink((_) => received++);
    final capture = ProductionPerformanceCapture();
    await tester.pump(const Duration(minutes: 20));
    expect(capture.snapshot, throwsStateError);
    emit('TIME_TO_SENDABLE_BADGE');
    expect(received, 1);
  });
}
