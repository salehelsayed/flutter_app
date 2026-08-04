import 'dart:convert';

import 'package:flutter_app/features/push/domain/push_registration_health.dart';
import 'package:flutter_app/features/push/infrastructure/push_registration_health_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  group('PushRegistrationHealthStore', () {
    test(
      'round-trips a versioned account and installation-bound safe record',
      () async {
        final secureStore = FakeSecureKeyStore();
        final store = PushRegistrationHealthStore(
          secureKeyStore: secureStore,
          accountPeerId: 'account-peer-secret',
          installationId: 'installation-secret',
        );
        final record = PushRegistrationHealthRecord(
          phase: PushRegistrationHealthPhase.retrying,
          reason: PushRegistrationHealthReason.registrationFailed,
          consecutiveFailures: 2,
          firstFailureAt: DateTime.utc(2026, 8, 1, 8),
          lastAttemptAt: DateTime.utc(2026, 8, 1, 9),
          lastSuccessAt: DateTime.utc(2026, 7, 31, 12),
        );

        await store.write(record);

        final raw = await secureStore.read(
          pushRegistrationHealthSecureStorageKey,
        );
        expect(raw, isNotNull);
        expect(raw, isNot(contains('account-peer-secret')));
        expect(raw, isNot(contains('installation-secret')));
        expect(raw, isNot(contains('fcm-token-secret')));
        expect(raw, isNot(contains('SocketException')));
        final json = jsonDecode(raw!) as Map<String, dynamic>;
        expect(json['schemaVersion'], pushRegistrationHealthSchemaVersion);
        expect(json['accountBindingSha256'], hasLength(64));
        expect(json['installationBindingSha256'], hasLength(64));
        expect(
          json.keys,
          unorderedEquals(<String>{
            'schemaVersion',
            'accountBindingSha256',
            'installationBindingSha256',
            'phase',
            'reason',
            'consecutiveFailures',
            'firstFailureAtMs',
            'lastAttemptAtMs',
            'lastSuccessAtMs',
          }),
        );

        final reopened = PushRegistrationHealthStore(
          secureKeyStore: secureStore,
          accountPeerId: 'account-peer-secret',
          installationId: 'installation-secret',
        );
        expect(await reopened.read(), record);
      },
    );

    test(
      'mismatched account or installation clears the local record',
      () async {
        for (final mismatch in <({String account, String installation})>[
          (account: 'other-account', installation: 'installation-a'),
          (account: 'account-a', installation: 'other-installation'),
        ]) {
          final secureStore = FakeSecureKeyStore();
          final owner = PushRegistrationHealthStore(
            secureKeyStore: secureStore,
            accountPeerId: 'account-a',
            installationId: 'installation-a',
          );
          await owner.write(
            PushRegistrationHealthRecord.healthy(at: DateTime.utc(2026, 8, 1)),
          );

          final other = PushRegistrationHealthStore(
            secureKeyStore: secureStore,
            accountPeerId: mismatch.account,
            installationId: mismatch.installation,
          );

          expect(await other.read(), isNull);
          expect(
            await secureStore.containsKey(
              pushRegistrationHealthSecureStorageKey,
            ),
            isFalse,
          );
        }
      },
    );

    test(
      'corrupt unsupported or mismatched records fail closed and clear',
      () async {
        final fixtures = <String>[
          '{not-json',
          jsonEncode(<String, Object?>{
            'schemaVersion': 999,
            'accountBindingSha256': 'x',
            'installationBindingSha256': 'y',
          }),
          jsonEncode(<String, Object?>{
            'schemaVersion': pushRegistrationHealthSchemaVersion,
            'accountBindingSha256': 'bad-binding',
            'installationBindingSha256': 'bad-binding',
            'phase': 'retrying',
            'reason': 'registrationFailed',
            'consecutiveFailures': 1,
            'firstFailureAtMs': 1,
            'lastAttemptAtMs': 2,
            'lastSuccessAtMs': null,
          }),
        ];

        for (final raw in fixtures) {
          final secureStore = FakeSecureKeyStore();
          await secureStore.write(pushRegistrationHealthSecureStorageKey, raw);
          final store = PushRegistrationHealthStore(
            secureKeyStore: secureStore,
            accountPeerId: 'account-a',
            installationId: 'installation-a',
          );

          expect(await store.read(), isNull);
          expect(
            await secureStore.containsKey(
              pushRegistrationHealthSecureStorageKey,
            ),
            isFalse,
          );
        }
      },
    );

    test(
      'impossible state with valid bindings fails closed and clears',
      () async {
        final secureStore = FakeSecureKeyStore();
        final store = PushRegistrationHealthStore(
          secureKeyStore: secureStore,
          accountPeerId: 'account-a',
          installationId: 'installation-a',
        );
        await store.write(
          PushRegistrationHealthRecord.healthy(at: DateTime.utc(2026, 8, 1)),
        );
        final raw = await secureStore.read(
          pushRegistrationHealthSecureStorageKey,
        );
        final impossible = jsonDecode(raw!) as Map<String, dynamic>
          ..['phase'] = 'retrying'
          ..['reason'] = 'registrationFailed'
          ..['consecutiveFailures'] = -1
          ..['firstFailureAtMs'] = 1;
        await secureStore.write(
          pushRegistrationHealthSecureStorageKey,
          jsonEncode(impossible),
        );

        expect(await store.read(), isNull);
        expect(
          await secureStore.containsKey(pushRegistrationHealthSecureStorageKey),
          isFalse,
        );
      },
    );

    test('empty account or installation binding is rejected', () {
      final secureStore = FakeSecureKeyStore();

      expect(
        () => PushRegistrationHealthStore(
          secureKeyStore: secureStore,
          accountPeerId: ' ',
          installationId: 'installation-a',
        ),
        throwsArgumentError,
      );
      expect(
        () => PushRegistrationHealthStore(
          secureKeyStore: secureStore,
          accountPeerId: 'account-a',
          installationId: '',
        ),
        throwsArgumentError,
      );
    });

    test(
      'resolves the current account and installation for every operation',
      () async {
        final secureStore = FakeSecureKeyStore();
        var binding = (
          accountPeerId: 'account-a',
          installationId: 'installation-a',
        );
        final store = ResolvingPushRegistrationHealthStore(
          secureKeyStore: secureStore,
          resolveBinding: () async => binding,
        );
        final record = PushRegistrationHealthRecord.retrying(
          reason: PushRegistrationHealthReason.registrationFailed,
          consecutiveFailures: 2,
          firstFailureAt: DateTime.utc(2026, 8, 1, 8),
          lastAttemptAt: DateTime.utc(2026, 8, 1, 9),
        );

        await store.write(record);
        expect(await store.read(), record);

        binding = (
          accountPeerId: 'account-b',
          installationId: 'installation-a',
        );
        expect(await store.read(), isNull);
        expect(
          await secureStore.containsKey(pushRegistrationHealthSecureStorageKey),
          isFalse,
        );

        await store.write(record);
        binding = (
          accountPeerId: 'account-b',
          installationId: 'installation-b',
        );
        expect(await store.read(), isNull);
      },
    );

    test(
      'bound writes keep the authority captured before account cutover',
      () async {
        final secureStore = FakeSecureKeyStore();
        var binding = (
          accountPeerId: 'account-a',
          installationId: 'installation-a',
        );
        final resolvingStore = ResolvingPushRegistrationHealthStore(
          secureKeyStore: secureStore,
          resolveBinding: () async => binding,
        );
        final captured = await resolvingStore.resolveBinding();
        binding = (
          accountPeerId: 'account-b',
          installationId: 'installation-b',
        );
        final record = PushRegistrationHealthRecord.healthy(
          at: DateTime.utc(2026, 8, 1),
        );

        await resolvingStore.writeForBinding(captured, record);

        final accountAStore = PushRegistrationHealthStore(
          secureKeyStore: secureStore,
          accountPeerId: 'account-a',
          installationId: 'installation-a',
        );
        expect(await accountAStore.read(), record);
        expect(await resolvingStore.read(), isNull);
      },
    );
  });
}
