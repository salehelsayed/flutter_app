import 'dart:convert';

import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/domain/issued_call_wake_handle_store.dart';
import 'package:flutter_app/features/call/infrastructure/issued_call_wake_handle_store_impl.dart';
import 'package:flutter_app/features/push/infrastructure/received_wake_token_store_impl.dart';
import 'package:flutter_app/features/push/infrastructure/wake_token_store_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  final grant = CallWakeHandleGrant(
    handle: '0123456789abcdef0123456789abcdef',
    recipientDevicePeerId: '12D3KooWRecipientDevice1',
    deviceKeyEpoch: 4,
    generation: 9,
    issuedAtMs: 1_750_000_000_000,
    expiresAtMs: 1_750_086_400_000,
  );

  test(
    'active/distribution state and revoke tombstone survive reload',
    () async {
      final keyStore = FakeSecureKeyStore();
      final store = IssuedCallWakeHandleStoreImpl(secureKeyStore: keyStore);
      final active = CallIssuedWakeHandleRecord(
        contactAccountPeerId: '12D3KooWContactAccount1',
        grant: grant,
        authorizedSenderDevicePeerIds: const <String>{
          '12D3KooWRecipientDevice1',
          '12D3KooWRecipientDevice2',
        },
      );

      await store.write(active);
      final loaded = await store.readForContact(active.contactAccountPeerId);
      expect(loaded?.grant, grant);
      expect(loaded?.distributionPending, isTrue);
      expect(loaded?.revokePending, isFalse);

      await store.write(
        active.copyWith(distributionPending: false, revokePending: true),
      );
      final reloaded = IssuedCallWakeHandleStoreImpl(secureKeyStore: keyStore);
      final tombstone = await reloaded.readForContact(
        active.contactAccountPeerId,
      );
      expect(tombstone?.grant, grant);
      expect(tombstone?.distributionPending, isFalse);
      expect(tombstone?.revokePending, isTrue);
      expect(await reloaded.readAll(), hasLength(1));
    },
  );

  test(
    'exact distribution receipt proof survives persistence and reload',
    () async {
      final keyStore = FakeSecureKeyStore();
      final store = IssuedCallWakeHandleStoreImpl(secureKeyStore: keyStore);
      final proven = CallIssuedWakeHandleRecord(
        contactAccountPeerId: '12D3KooWContactAccount1',
        grant: grant,
        authorizedSenderDevicePeerIds: const <String>{
          '12D3KooWRecipientDevice1',
        },
        distributionPending: false,
        distributionReceiptVersion:
            CallIssuedWakeHandleRecord.currentDistributionReceiptVersion,
      );

      await store.write(proven);

      final raw =
          jsonDecode(
                (await keyStore.read(issuedCallWakeHandlesSecureStorageKey))!,
              )
              as Map<String, dynamic>;
      final rawRecord =
          (raw['records'] as Map<String, dynamic>)[proven.contactAccountPeerId]
              as Map<String, dynamic>;
      expect(
        rawRecord['distributionReceiptVersion'],
        CallIssuedWakeHandleRecord.currentDistributionReceiptVersion,
      );

      final reloaded = IssuedCallWakeHandleStoreImpl(secureKeyStore: keyStore);
      final loaded = await reloaded.readForContact(proven.contactAccountPeerId);
      expect(loaded?.distributionPending, isFalse);
      expect(
        loaded?.distributionReceiptVersion,
        CallIssuedWakeHandleRecord.currentDistributionReceiptVersion,
      );
      expect(loaded?.hasCurrentDistributionReceipt, isTrue);
    },
  );

  test(
    'failed durable receipt write is not cached and the exact update can retry',
    () async {
      final keyStore = _FailNextIssuedWriteSecureKeyStore();
      final store = IssuedCallWakeHandleStoreImpl(secureKeyStore: keyStore);
      final pending = CallIssuedWakeHandleRecord(
        contactAccountPeerId: '12D3KooWContactAccount1',
        grant: grant,
        authorizedSenderDevicePeerIds: const <String>{
          '12D3KooWRecipientDevice1',
        },
      );
      final proven = pending.copyWith(
        distributionPending: false,
        distributionReceiptVersion:
            CallIssuedWakeHandleRecord.currentDistributionReceiptVersion,
      );
      await store.write(pending);

      keyStore.failNextIssuedWrite = true;
      await expectLater(store.write(proven), throwsA(isA<StateError>()));

      final sameInstance = await store.readForContact(
        pending.contactAccountPeerId,
      );
      expect(sameInstance?.distributionPending, isTrue);
      expect(sameInstance?.hasCurrentDistributionReceipt, isFalse);
      final afterFailureReload = IssuedCallWakeHandleStoreImpl(
        secureKeyStore: keyStore,
      );
      expect(
        (await afterFailureReload.readForContact(
          pending.contactAccountPeerId,
        ))?.distributionPending,
        isTrue,
      );

      await store.write(proven);
      expect(
        (await store.readForContact(
          pending.contactAccountPeerId,
        ))?.hasCurrentDistributionReceipt,
        isTrue,
      );
      final afterRetryReload = IssuedCallWakeHandleStoreImpl(
        secureKeyStore: keyStore,
      );
      expect(
        (await afterRetryReload.readForContact(
          pending.contactAccountPeerId,
        ))?.hasCurrentDistributionReceipt,
        isTrue,
      );
    },
  );

  test(
    'legacy distributed record without receipt version loads unproven',
    () async {
      final keyStore = FakeSecureKeyStore();
      final legacyRecord = <String, Object>{
        'contactAccountPeerId': '12D3KooWContactAccount1',
        'grant': grant.toCanonicalMap(),
        'authorizedSenderDevicePeerIds': <String>['12D3KooWRecipientDevice1'],
        'revokePending': false,
        'distributionPending': false,
      };
      await keyStore.write(
        issuedCallWakeHandlesSecureStorageKey,
        jsonEncode(<String, Object>{
          'version': 1,
          'records': <String, Object>{'12D3KooWContactAccount1': legacyRecord},
        }),
      );

      final store = IssuedCallWakeHandleStoreImpl(secureKeyStore: keyStore);
      final loaded = await store.readForContact('12D3KooWContactAccount1');

      expect(loaded, isNotNull);
      expect(loaded?.distributionPending, isFalse);
      expect(loaded?.distributionReceiptVersion, isNull);
      expect(loaded?.hasCurrentDistributionReceipt, isFalse);
    },
  );

  test('pending, revoked, or rotated copies clear exact proof', () {
    final proven = CallIssuedWakeHandleRecord(
      contactAccountPeerId: '12D3KooWContactAccount1',
      grant: grant,
      authorizedSenderDevicePeerIds: const <String>{'12D3KooWRecipientDevice1'},
      distributionPending: false,
      distributionReceiptVersion:
          CallIssuedWakeHandleRecord.currentDistributionReceiptVersion,
    );

    final pending = proven.copyWith(distributionPending: true);
    expect(pending.distributionReceiptVersion, isNull);
    expect(pending.hasCurrentDistributionReceipt, isFalse);

    final revoked = proven.copyWith(revokePending: true);
    expect(revoked.distributionReceiptVersion, isNull);
    expect(revoked.hasCurrentDistributionReceipt, isFalse);

    final rotated = proven.copyWith(
      grant: CallWakeHandleGrant(
        handle: 'fedcba9876543210fedcba9876543210',
        recipientDevicePeerId: grant.recipientDevicePeerId,
        deviceKeyEpoch: grant.deviceKeyEpoch,
        generation: grant.generation + 1,
        issuedAtMs: grant.issuedAtMs,
        expiresAtMs: grant.expiresAtMs,
      ),
    );
    expect(rotated.distributionReceiptVersion, isNull);
    expect(rotated.hasCurrentDistributionReceipt, isFalse);
  });

  test('remove/clear update the durable ledger', () async {
    final keyStore = FakeSecureKeyStore();
    final store = IssuedCallWakeHandleStoreImpl(secureKeyStore: keyStore);
    final record = CallIssuedWakeHandleRecord(
      contactAccountPeerId: '12D3KooWContactAccount1',
      grant: grant,
      authorizedSenderDevicePeerIds: <String>{grant.recipientDevicePeerId},
    );
    await store.write(record);
    await store.removeForContact(record.contactAccountPeerId);
    expect(await store.readForContact(record.contactAccountPeerId), isNull);

    await store.write(record);
    await store.clear();
    expect(await store.readAll(), isEmpty);
    expect(await keyStore.read(issuedCallWakeHandlesSecureStorageKey), isNull);
  });

  test('corrupt ledger self-heals without exposing a partial record', () async {
    final keyStore = FakeSecureKeyStore();
    await keyStore.write(
      issuedCallWakeHandlesSecureStorageKey,
      '{"version":1,"records":{"peer":{"grant":{}}}}',
    );
    final store = IssuedCallWakeHandleStoreImpl(secureKeyStore: keyStore);

    expect(await store.readAll(), isEmpty);
    expect(await keyStore.read(issuedCallWakeHandlesSecureStorageKey), isNull);
  });

  test('issued key is distinct from both ordinary wake-token directions', () {
    expect(
      issuedCallWakeHandlesSecureStorageKey,
      isNot(wakeTokensSecureStorageKey),
    );
    expect(
      issuedCallWakeHandlesSecureStorageKey,
      isNot(receivedWakeTokensSecureStorageKey),
    );
  });
}

final class _FailNextIssuedWriteSecureKeyStore extends FakeSecureKeyStore {
  bool failNextIssuedWrite = false;

  @override
  Future<void> write(String key, String value) async {
    if (failNextIssuedWrite && key == issuedCallWakeHandlesSecureStorageKey) {
      failNextIssuedWrite = false;
      throw StateError('injected issued wake-handle write failure');
    }
    await super.write(key, value);
  }
}
