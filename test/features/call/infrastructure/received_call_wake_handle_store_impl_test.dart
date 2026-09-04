import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/infrastructure/issued_call_wake_handle_store_impl.dart';
import 'package:flutter_app/features/call/infrastructure/received_call_wake_handle_store_impl.dart';
import 'package:flutter_app/features/push/infrastructure/received_wake_token_store_impl.dart';
import 'package:flutter_app/features/push/infrastructure/wake_token_store_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  const issuer = '12D3KooWIssuerAccount1';
  const recipient = '12D3KooWRecipientDevice1';
  const nowMs = 1_750_000_000_000;

  CallWakeHandleGrant grant({
    int epoch = 4,
    int generation = 1,
    String handle = '0123456789abcdef0123456789abcdef',
    String recipientDevicePeerId = recipient,
    int issuedAtMs = nowMs - 1000,
    int expiresAtMs = nowMs + 1000,
  }) => CallWakeHandleGrant(
    handle: handle,
    recipientDevicePeerId: recipientDevicePeerId,
    deviceKeyEpoch: epoch,
    generation: generation,
    issuedAtMs: issuedAtMs,
    expiresAtMs: expiresAtMs,
  );

  test('stores only strictly newer valid grants and survives reload', () async {
    final keyStore = FakeSecureKeyStore();
    final store = ReceivedCallWakeHandleStoreImpl(secureKeyStore: keyStore);

    expect(
      await store.storeIfStrictlyNewer(
        issuerAccountPeerId: issuer,
        grant: grant(),
        nowMs: nowMs,
      ),
      isTrue,
    );
    expect(
      await store.storeIfStrictlyNewer(
        issuerAccountPeerId: issuer,
        grant: grant(generation: 1, handle: '11111111111111111111111111111111'),
        nowMs: nowMs,
      ),
      isFalse,
    );
    expect(
      await store.storeIfStrictlyNewer(
        issuerAccountPeerId: issuer,
        grant: grant(generation: 2),
        nowMs: nowMs,
      ),
      isTrue,
    );
    expect(
      await store.storeIfStrictlyNewer(
        issuerAccountPeerId: issuer,
        grant: grant(epoch: 5, generation: 1),
        nowMs: nowMs,
      ),
      isFalse,
    );
    expect(
      await store.storeIfStrictlyNewer(
        issuerAccountPeerId: issuer,
        grant: grant(epoch: 3, generation: 3),
        nowMs: nowMs,
      ),
      isTrue,
    );

    final reloaded = ReceivedCallWakeHandleStoreImpl(secureKeyStore: keyStore);
    final loaded = await reloaded.readForIssuer(issuer);
    expect(loaded?.deviceKeyEpoch, 3);
    expect(loaded?.generation, 3);
  });

  test('expired grants are rejected without a write', () async {
    final keyStore = FakeSecureKeyStore();
    final store = ReceivedCallWakeHandleStoreImpl(secureKeyStore: keyStore);

    expect(
      await store.storeIfStrictlyNewer(
        issuerAccountPeerId: issuer,
        grant: grant(expiresAtMs: nowMs),
        nowMs: nowMs,
      ),
      isFalse,
    );
    expect(await store.readForIssuer(issuer), isNull);
    expect(
      await keyStore.read(receivedCallWakeHandlesSecureStorageKey),
      isNull,
    );
  });

  test(
    'failed durable write is not cached and the same grant can retry',
    () async {
      final keyStore = _FailFirstWriteSecureKeyStore();
      final store = ReceivedCallWakeHandleStoreImpl(secureKeyStore: keyStore);
      final candidate = grant();

      await expectLater(
        store.storeIfStrictlyNewer(
          issuerAccountPeerId: issuer,
          grant: candidate,
          nowMs: nowMs,
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        await store.readForIssuer(issuer),
        isNull,
        reason: 'a failed secure-storage write must not publish cache state',
      );
      expect(
        await store.storeIfStrictlyNewer(
          issuerAccountPeerId: issuer,
          grant: candidate,
          nowMs: nowMs,
        ),
        isTrue,
        reason: 'the exact uncommitted grant must remain retryable',
      );
      expect(await store.readForIssuer(issuer), candidate);

      final reloaded = ReceivedCallWakeHandleStoreImpl(
        secureKeyStore: keyStore,
      );
      expect(await reloaded.readForIssuer(issuer), candidate);
    },
  );

  test('corrupt ledger self-heals and later writes remain usable', () async {
    final keyStore = FakeSecureKeyStore();
    await keyStore.write(receivedCallWakeHandlesSecureStorageKey, 'not-json{');
    final store = ReceivedCallWakeHandleStoreImpl(secureKeyStore: keyStore);

    expect(await store.readForIssuer(issuer), isNull);
    expect(
      await store.storeIfStrictlyNewer(
        issuerAccountPeerId: issuer,
        grant: grant(),
        nowMs: nowMs,
      ),
      isTrue,
    );
    expect(await store.readForIssuer(issuer), isNotNull);
  });

  test('received and issued keys are distinct from both wt stores', () {
    expect(
      receivedCallWakeHandlesSecureStorageKey,
      isNot(issuedCallWakeHandlesSecureStorageKey),
    );
    expect(
      receivedCallWakeHandlesSecureStorageKey,
      isNot(wakeTokensSecureStorageKey),
    );
    expect(
      receivedCallWakeHandlesSecureStorageKey,
      isNot(receivedWakeTokensSecureStorageKey),
    );
  });
}

final class _FailFirstWriteSecureKeyStore extends FakeSecureKeyStore {
  var _shouldFail = true;

  @override
  Future<void> write(String key, String value) async {
    if (_shouldFail && key == receivedCallWakeHandlesSecureStorageKey) {
      _shouldFail = false;
      throw StateError('injected secure-storage write failure');
    }
    await super.write(key, value);
  }
}
