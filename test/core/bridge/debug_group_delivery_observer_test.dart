import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/debug_group_delivery_observer.dart';

void main() {
  tearDown(() => debugGroupDeliveryObserver = null);

  test('no observer is installed by default', () {
    expect(debugGroupDeliveryObserver, isNull);
  });

  test('only the two durable group delivery commands are observable', () {
    expect(debugObservedGroupDeliveryCommands, {
      'group:inboxStore',
      'group:sendReliable',
    });
  });

  test('a debug journey can install and clear an observer', () {
    void observer(String cmd, Map<String, dynamic> p, Map<dynamic, dynamic> r) {}
    debugGroupDeliveryObserver = observer;
    expect(debugGroupDeliveryObserver, same(observer));
    debugGroupDeliveryObserver = null;
    expect(debugGroupDeliveryObserver, isNull);
  });
}
