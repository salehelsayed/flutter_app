import 'package:flutter/services.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/migration_transfer_keep_alive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Map<String, dynamic>> flowEvents;

  setUp(() {
    flowEvents = <Map<String, dynamic>>[];
    debugSetFlowEventSink(flowEvents.add);
  });

  tearDown(() {
    debugSetFlowEventSink(null);
  });

  List<Map<String, dynamic>> eventsNamed(String name) => flowEvents
      .where((event) => event['event'] == name)
      .toList(growable: false);

  group('MigrationTransferKeepAlive', () {
    test('starts the platform keep-alive once and stops on last release', () async {
      final calls = <String>[];
      final keepAlive = MigrationTransferKeepAlive(
        invoker: (method, args) async => calls.add(method),
      );

      await keepAlive.acquire(reason: 'old_phone_transfer');
      await keepAlive.acquire(reason: 'new_phone_receiver');
      expect(calls, ['start']);
      expect(keepAlive.activeHolds, 2);

      await keepAlive.release(reason: 'old_phone_transfer');
      expect(calls, ['start']);

      await keepAlive.release(reason: 'new_phone_receiver');
      expect(calls, ['start', 'stop']);
      expect(keepAlive.activeHolds, 0);
      expect(
        eventsNamed('ACCOUNT_MIGRATION_KEEPALIVE_STARTED'),
        hasLength(1),
      );
      expect(
        eventsNamed('ACCOUNT_MIGRATION_KEEPALIVE_STOPPED'),
        hasLength(1),
      );
    });

    test('missing platform implementation degrades to a silent no-op', () async {
      var attempts = 0;
      final keepAlive = MigrationTransferKeepAlive(
        invoker: (method, args) async {
          attempts++;
          throw MissingPluginException();
        },
      );

      await keepAlive.acquire(reason: 'first');
      await keepAlive.release(reason: 'first');
      await keepAlive.acquire(reason: 'second');
      await keepAlive.release(reason: 'second');

      // One probe, then permanently unavailable; never throws to callers.
      expect(attempts, 1);
      expect(
        eventsNamed('ACCOUNT_MIGRATION_KEEPALIVE_UNAVAILABLE'),
        hasLength(1),
      );
      expect(eventsNamed('ACCOUNT_MIGRATION_KEEPALIVE_STOPPED'), isEmpty);
    });

    test('platform start failure is tolerated and never stops unstarted', () async {
      final calls = <String>[];
      final keepAlive = MigrationTransferKeepAlive(
        invoker: (method, args) async {
          calls.add(method);
          if (method == 'start') {
            throw PlatformException(code: 'boom');
          }
        },
      );

      await keepAlive.acquire(reason: 'transfer');
      await keepAlive.release(reason: 'transfer');

      expect(calls, ['start']);
      expect(
        eventsNamed('ACCOUNT_MIGRATION_KEEPALIVE_START_FAILED'),
        hasLength(1),
      );
      expect(eventsNamed('ACCOUNT_MIGRATION_KEEPALIVE_STOPPED'), isEmpty);
    });

    test('platform stop failure is tolerated', () async {
      final keepAlive = MigrationTransferKeepAlive(
        invoker: (method, args) async {
          if (method == 'stop') {
            throw PlatformException(code: 'boom');
          }
        },
      );

      await keepAlive.acquire(reason: 'transfer');
      await keepAlive.release(reason: 'transfer');

      expect(
        eventsNamed('ACCOUNT_MIGRATION_KEEPALIVE_STOP_FAILED'),
        hasLength(1),
      );
      expect(keepAlive.activeHolds, 0);
    });

    test('release without acquire is a no-op', () async {
      final calls = <String>[];
      final keepAlive = MigrationTransferKeepAlive(
        invoker: (method, args) async => calls.add(method),
      );

      await keepAlive.release(reason: 'stray');

      expect(calls, isEmpty);
      expect(keepAlive.activeHolds, 0);
    });
  });
}
