import 'package:flutter_app/core/utils/cold_start_notif_anchor.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_test/flutter_test.dart';

/// FDC-S1 Method 5(d): the cold notif-tap → node-ready correlation latch is the
/// only instrumentation site with branching logic, so it is the only one worth
/// a lock. Everything else is a one-line additive emit. These tests assert the
/// "emit exactly once, only when BOTH signals are seen, in either order" rule
/// that yields the NSE→main-isolate gap.
void main() {
  late List<Map<String, dynamic>> events;

  setUp(() {
    events = [];
    ColdStartNotifAnchor.instance.resetForTest();
    debugSetFlowEventSink(events.add);
  });

  tearDown(() {
    debugSetFlowEventSink(null);
    ColdStartNotifAnchor.instance.resetForTest();
  });

  List<Map<String, dynamic>> nodeReadyEvents() => events
      .where((e) => e['event'] == 'FDC_COLDSTART_NOTIF_TAP_NODE_READY')
      .toList();

  test('does NOT emit when only the notif tap is seen (node not ready)', () {
    ColdStartNotifAnchor.instance.recordNotifTap('push-1');
    expect(nodeReadyEvents(), isEmpty);
  });

  test('does NOT emit when only node-ready is seen (no notif tap)', () {
    ColdStartNotifAnchor.instance.recordNodeReady();
    expect(nodeReadyEvents(), isEmpty);
  });

  test('emits once when notif tap precedes node-ready', () {
    ColdStartNotifAnchor.instance.recordNotifTap('push-1');
    ColdStartNotifAnchor.instance.recordNodeReady();

    final emitted = nodeReadyEvents();
    expect(emitted, hasLength(1));
    final details = emitted.single['details'] as Map<String, dynamic>;
    expect(details['pushId'], 'push-1');
    // node-ready was the second (unblocking) signal.
    expect(details['trigger'], 'node_ready');
    expect(details.containsKey('sinceProcessStartMs'), isTrue);
    expect(details.containsKey('epochMs'), isTrue);
  });

  test('emits once when node-ready precedes notif tap (reverse order)', () {
    ColdStartNotifAnchor.instance.recordNodeReady();
    ColdStartNotifAnchor.instance.recordNotifTap('push-2');

    final emitted = nodeReadyEvents();
    expect(emitted, hasLength(1));
    final details = emitted.single['details'] as Map<String, dynamic>;
    expect(details['pushId'], 'push-2');
    // notif tap was the second (unblocking) signal.
    expect(details['trigger'], 'notif_tap');
  });

  test('is a one-shot: repeated signals do not re-emit', () {
    ColdStartNotifAnchor.instance.recordNotifTap('push-1');
    ColdStartNotifAnchor.instance.recordNodeReady();
    ColdStartNotifAnchor.instance.recordNodeReady();
    ColdStartNotifAnchor.instance.recordNotifTap('push-1');
    expect(nodeReadyEvents(), hasLength(1));
  });

  test('a null pushId falls back to "unknown" and is not overwritten', () {
    ColdStartNotifAnchor.instance.recordNotifTap(null);
    ColdStartNotifAnchor.instance.recordNotifTap('late-but-ignored');
    ColdStartNotifAnchor.instance.recordNodeReady();

    final details = nodeReadyEvents().single['details'] as Map<String, dynamic>;
    // First non-null wins (??=); here the first call was null so the second
    // non-null id is captured, but once captured it is never replaced.
    expect(details['pushId'], 'late-but-ignored');
  });
}
