import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_app/core/notifications/canonical_recovery_authority_storage_keys.dart';
import 'package:flutter_app/core/notifications/dropped_push_recovery_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  late List<String> trace;
  late _FakeAuthorityMutationPublisher publisher;
  late bool storageWriteFails;
  Completer<void>? storageWriteGate;
  Completer<void>? storageWriteEntered;

  setUp(() {
    trace = <String>[];
    publisher = _FakeAuthorityMutationPublisher(trace);
    storageWriteFails = false;
    storageWriteGate = null;
    storageWriteEntered = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (call) async {
          final arguments = call.arguments as Map<Object?, Object?>;
          trace.add('storage:${call.method}:${arguments['key'] ?? '-'}');
          final entered = storageWriteEntered;
          if (entered != null && !entered.isCompleted) entered.complete();
          await storageWriteGate?.future;
          if (storageWriteFails) {
            throw PlatformException(code: 'secure_write_failed');
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
  });

  group('FlutterSecureKeyStore', () {
    test('defaults to app-only Apple keychain scope', () {
      final store = FlutterSecureKeyStore();

      expect(store.appleAccessGroup, isNull);
    });

    test('can be constructed with the shared Apple access group', () {
      final store = FlutterSecureKeyStore(
        appleAccessGroup: mknoonSharedAppleAccessGroup,
      );

      expect(store.appleAccessGroup, mknoonSharedAppleAccessGroup);
      expect(store.appleAccessGroup, '397R9Q4WMX.group.com.mknoon.app.share');
    });

    test(
      'every watched authority write begins before storage and finishes after it',
      () async {
        final store = FlutterSecureKeyStore(
          authorityMutationPublisher: publisher,
        );
        expect(
          canonicalRecoveryAuthorityStorageKeys,
          contains(identityPrivateKeyStorageKey),
          reason: 'identity private-key rotation changes recovery authority',
        );

        publisher.beginGate = Completer<void>();
        storageWriteGate = Completer<void>();
        storageWriteEntered = Completer<void>();
        final heldWrite = store.write(
          canonicalRuntimeAccountBindingStorageKey,
          'authority-value',
        );
        await Future<void>.delayed(Duration.zero);
        expect(trace, <String>['begin']);

        publisher.beginGate?.complete();
        await storageWriteEntered?.future;
        expect(trace, <String>[
          'begin',
          'storage:write:$canonicalRuntimeAccountBindingStorageKey',
        ]);

        storageWriteGate?.complete();
        await heldWrite;
        expect(trace, <String>[
          'begin',
          'storage:write:$canonicalRuntimeAccountBindingStorageKey',
          'finish:authority-token',
        ]);

        publisher.beginGate = null;
        storageWriteGate = null;
        storageWriteEntered = null;
        for (final key in canonicalRecoveryAuthorityStorageKeys.where(
          (key) => key != canonicalRuntimeAccountBindingStorageKey,
        )) {
          trace.clear();

          await store.write(key, 'authority-value');

          expect(trace, <String>[
            'begin',
            'storage:write:$key',
            'finish:authority-token',
          ], reason: key);
        }

        trace.clear();
        await store.write('ordinary_secure_value', 'value');
        expect(trace, <String>['storage:write:ordinary_secure_value']);
      },
    );

    test('rejected begin and finish publications fail closed', () async {
      final store = FlutterSecureKeyStore(
        authorityMutationPublisher: publisher,
      );
      publisher.beginPublication =
          const DroppedPushRecoveryAuthorityMutationPublication.rejected();

      await expectLater(
        store.write(canonicalRuntimeAccountBindingStorageKey, 'binding-a'),
        throwsA(
          isA<CanonicalRecoveryAuthorityMutationException>()
              .having((error) => error.operation, 'operation', 'write')
              .having((error) => error.phase, 'phase', 'begin'),
        ),
      );
      expect(trace, <String>['begin']);

      trace.clear();
      publisher
        ..beginPublication = _committedBegin
        ..finishPublication =
            const DroppedPushRecoveryAuthorityMutationPublication.rejected();
      await expectLater(
        store.write(canonicalRuntimeAccountBindingStorageKey, 'binding-b'),
        throwsA(
          isA<CanonicalRecoveryAuthorityMutationException>()
              .having((error) => error.operation, 'operation', 'write')
              .having((error) => error.phase, 'phase', 'finish')
              .having((error) => error.primaryError, 'primaryError', isNull),
        ),
      );
      expect(trace, <String>[
        'begin',
        'storage:write:$canonicalRuntimeAccountBindingStorageKey',
        'finish:authority-token',
      ]);
    });

    test(
      'storage failure still finishes the fence and preserves the primary error',
      () async {
        final store = FlutterSecureKeyStore(
          authorityMutationPublisher: publisher,
        );
        storageWriteFails = true;

        await expectLater(
          store.write(canonicalRuntimeAccountBindingStorageKey, 'binding-a'),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'secure_write_failed',
            ),
          ),
        );
        expect(trace, <String>[
          'begin',
          'storage:write:$canonicalRuntimeAccountBindingStorageKey',
          'finish:authority-token',
        ]);

        trace.clear();
        publisher.finishPublication =
            const DroppedPushRecoveryAuthorityMutationPublication.rejected();
        await expectLater(
          store.write(canonicalRuntimeAccountBindingStorageKey, 'binding-b'),
          throwsA(
            isA<CanonicalRecoveryAuthorityMutationException>()
                .having((error) => error.phase, 'phase', 'finish')
                .having(
                  (error) => error.primaryError,
                  'primaryError',
                  isA<PlatformException>().having(
                    (error) => error.code,
                    'code',
                    'secure_write_failed',
                  ),
                ),
          ),
        );
        expect(trace, <String>[
          'begin',
          'storage:write:$canonicalRuntimeAccountBindingStorageKey',
          'finish:authority-token',
        ]);
      },
    );
  });
}

const _committedBegin = DroppedPushRecoveryAuthorityMutationPublication(
  changed: true,
  committed: true,
  token: 'authority-token',
  currentBinding: 'v1:binding',
  recoveryWorkEnabled: false,
  authorityRevision: 3,
  authorityMutationInProgress: true,
);

const _committedFinish = DroppedPushRecoveryAuthorityMutationPublication(
  changed: true,
  committed: true,
  token: null,
  currentBinding: 'v1:binding',
  recoveryWorkEnabled: true,
  authorityRevision: 4,
  authorityMutationInProgress: false,
);

final class _FakeAuthorityMutationPublisher
    implements DroppedPushRecoveryAuthorityMutationPublisher {
  _FakeAuthorityMutationPublisher(this.trace);

  final List<String> trace;
  DroppedPushRecoveryAuthorityMutationPublication beginPublication =
      _committedBegin;
  DroppedPushRecoveryAuthorityMutationPublication finishPublication =
      _committedFinish;
  Completer<void>? beginGate;

  @override
  Future<DroppedPushRecoveryAuthorityMutationPublication>
  beginRecoveryAuthorityMutation() async {
    trace.add('begin');
    await beginGate?.future;
    return beginPublication;
  }

  @override
  Future<DroppedPushRecoveryAuthorityMutationPublication>
  finishRecoveryAuthorityMutation(String token) async {
    trace.add('finish:$token');
    return finishPublication;
  }
}
