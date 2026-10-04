import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/debug_group_delivery_observer.dart';

void main() {
  tearDown(() {
    debugGroupDeliveryObserver = null;
    debugGroupInboundObserver = null;
  });

  test('no observer is installed by default', () {
    expect(debugGroupDeliveryObserver, isNull);
  });

  test('only the durable delivery commands and the topic leave are observable', () {
    expect(debugObservedGroupDeliveryCommands, {
      'group:inboxStore',
      'group:sendReliable',
      'group:leave',
    });
  });

  test('a debug journey can install and clear an observer', () {
    void observer(String cmd, Map<String, dynamic> p, Map<dynamic, dynamic> r) {}
    debugGroupDeliveryObserver = observer;
    expect(debugGroupDeliveryObserver, same(observer));
    debugGroupDeliveryObserver = null;
    expect(debugGroupDeliveryObserver, isNull);
  });

  test('no inbound observer is installed by default', () {
    expect(debugGroupInboundObserver, isNull);
  });

  test('a debug journey can install and clear an inbound observer', () {
    void observer(String kind, Map<String, dynamic> data) {}
    debugGroupInboundObserver = observer;
    expect(debugGroupInboundObserver, same(observer));
    debugGroupInboundObserver = null;
    expect(debugGroupInboundObserver, isNull);
  });
}
