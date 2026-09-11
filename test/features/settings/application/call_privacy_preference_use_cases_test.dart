import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/settings/application/call_privacy_preference_use_cases.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

class _UnreadableStore extends FakeSecureKeyStore {
  _UnreadableStore({this.pending = false});
  final bool pending;

  @override
  Future<String?> read(String key) => pending
      ? Completer<String?>().future
      : Future.error(StateError('storage unavailable'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'absence is normal; explicit opt-in and opt-out are durable values',
    () async {
      final store = FakeSecureKeyStore();
      expect(
        await loadAlwaysRelayCallsPreference(secureKeyStore: store),
        false,
      );
      for (final value in [true, false]) {
        await saveAlwaysRelayCallsPreference(
          secureKeyStore: store,
          alwaysRelay: value,
        );
        expect(await store.read(alwaysRelayCallsStorageKey), '$value');
        expect(
          await resolveCallTransportPolicy(
            secureKeyStore: store,
            forceRelay: false,
          ),
          value ? CallTransportPolicy.relayOnly : CallTransportPolicy.all,
        );
      }
    },
  );

  test('rollout restriction never writes over the saved opt-out', () async {
    final store = FakeSecureKeyStore();
    await saveAlwaysRelayCallsPreference(
      secureKeyStore: store,
      alwaysRelay: false,
    );
    expect(
      await resolveCallTransportPolicy(secureKeyStore: store, forceRelay: true),
      CallTransportPolicy.relayOnly,
    );
    expect(await store.read(alwaysRelayCallsStorageKey), 'false');
    expect(
      await resolveCallTransportPolicy(
        secureKeyStore: store,
        forceRelay: false,
      ),
      CallTransportPolicy.all,
    );
  });

  test(
    'unknown, corrupt and unreadable preferences fail closed without overwriting',
    () async {
      final store = FakeSecureKeyStore();
      for (final value in ['', 'TRUE', 'future-version', '0']) {
        await store.write(alwaysRelayCallsStorageKey, value);
        expect(
          await resolveCallTransportPolicy(
            secureKeyStore: store,
            forceRelay: false,
          ),
          CallTransportPolicy.relayOnly,
        );
        expect(await store.read(alwaysRelayCallsStorageKey), value);
        await expectLater(
          loadAlwaysRelayCallsPreference(secureKeyStore: store),
          throwsFormatException,
        );
      }
      expect(
        await resolveCallTransportPolicy(
          secureKeyStore: _UnreadableStore(),
          forceRelay: false,
        ),
        CallTransportPolicy.relayOnly,
      );
    },
  );

  test(
    'a stalled privacy read resolves relay-only within the call setup budget',
    () {
      fakeAsync((time) {
        CallTransportPolicy? resolved;
        resolveCallTransportPolicy(
          secureKeyStore: _UnreadableStore(pending: true),
          forceRelay: false,
        ).then((value) => resolved = value);
        time.elapse(const Duration(milliseconds: 1999));
        expect(resolved, isNull);
        time.elapse(const Duration(milliseconds: 1));
        expect(resolved, CallTransportPolicy.relayOnly);
      });
    },
  );

  test(
    'production secure-store reconstruction preserves both choices across restarts/upgrades',
    () async {
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final persisted = <String, String>{};
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments as Map;
        final key = args['key'] as String;
        if (call.method == 'write') persisted[key] = args['value'] as String;
        if (call.method == 'read') return persisted[key];
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      for (final value in [true, false]) {
        await saveAlwaysRelayCallsPreference(
          secureKeyStore: FlutterSecureKeyStore(),
          alwaysRelay: value,
        );
        // A new production wrapper reads the same native key; build flags are not
        // an initialization/migration source for this key.
        expect(
          await loadAlwaysRelayCallsPreference(
            secureKeyStore: FlutterSecureKeyStore(),
          ),
          value,
        );
        expect(persisted, {'settings_always_relay_calls': '$value'});
      }
    },
  );
}
