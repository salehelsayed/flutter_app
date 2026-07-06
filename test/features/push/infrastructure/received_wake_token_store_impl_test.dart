import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/push/infrastructure/received_wake_token_store_impl.dart';
import 'package:flutter_app/features/push/infrastructure/wake_token_store_impl.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

// FDC-09 §12 / CV-14 (217 §D1 / A05) — ReceivedWakeTokenStoreImpl persists the
// SENDER-SIDE {peerId -> {"tok","ts"}} map in SecureKeyStore under a key DISTINCT
// from the recipient-minted store, survives reload, and self-heals a corrupt blob.
void main() {
  test('schema {peerId:{tok,ts}} roundtrip + survives reload', () async {
    final keyStore = FakeSecureKeyStore();
    final store = ReceivedWakeTokenStoreImpl(secureKeyStore: keyStore);

    expect(await store.readTokenFor('peerA'), isNull);

    await store.writeTokenFor('peerA', 'tok-A', '2026-07-06T00:00:00.000Z');
    expect(await store.readTokenFor('peerA'), {
      'tok': 'tok-A',
      'ts': '2026-07-06T00:00:00.000Z',
    });

    // Reload: a NEW impl over the same backing store reads the persisted entry.
    final reloaded = ReceivedWakeTokenStoreImpl(secureKeyStore: keyStore);
    expect(await reloaded.readTokenFor('peerA'), {
      'tok': 'tok-A',
      'ts': '2026-07-06T00:00:00.000Z',
    });
  });

  test('persisted blob is the nested {peerId:{tok,ts}} schema (NOT a flat map)',
      () async {
    final keyStore = FakeSecureKeyStore();
    final store = ReceivedWakeTokenStoreImpl(secureKeyStore: keyStore);
    await store.writeTokenFor('peerA', 'tok-A', '2026-07-06T01:00:00.000Z');

    final raw = await keyStore.read(receivedWakeTokensSecureStorageKey);
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as Map<String, dynamic>;
    // Nested object per peer — a flat Map<String,String> (recipient schema) reds.
    expect(decoded['peerA'], isA<Map<String, dynamic>>());
    expect((decoded['peerA'] as Map)['tok'], 'tok-A');
    expect((decoded['peerA'] as Map)['ts'], '2026-07-06T01:00:00.000Z');
  });

  test('storage key is distinct from the recipient-minted wake-token key',
      () async {
    // A distinct constant AND runtime isolation: writing the received store must
    // never touch the recipient-minted store's key.
    expect(receivedWakeTokensSecureStorageKey, 'fdc09_received_wake_tokens');
    expect(receivedWakeTokensSecureStorageKey, isNot(wakeTokensSecureStorageKey));

    final keyStore = FakeSecureKeyStore();
    final store = ReceivedWakeTokenStoreImpl(secureKeyStore: keyStore);
    await store.writeTokenFor('peerA', 'tok-A', '2026-07-06T02:00:00.000Z');

    // The recipient-minted key stays empty (no cross-store clobber).
    expect(await keyStore.read(wakeTokensSecureStorageKey), isNull);
  });

  test('a corrupt blob reads as empty (never throws) and self-heals', () async {
    final keyStore = FakeSecureKeyStore();
    await keyStore.write(receivedWakeTokensSecureStorageKey, 'not-json{');
    final store = ReceivedWakeTokenStoreImpl(secureKeyStore: keyStore);

    expect(await store.readTokenFor('peerA'), isNull);
    // A subsequent write still lands correctly after self-heal.
    await store.writeTokenFor('peerA', 'tok-A', '2026-07-06T03:00:00.000Z');
    expect(await store.readTokenFor('peerA'), {
      'tok': 'tok-A',
      'ts': '2026-07-06T03:00:00.000Z',
    });
  });

  test(
    'concurrent writes racing the FIRST (cold) load do not lose an entry '
    '(in-flight load is memoized)',
    () async {
      final keyStore = FakeSecureKeyStore();
      final store = ReceivedWakeTokenStoreImpl(secureKeyStore: keyStore);

      // Two handlers both trigger the very first load, then write different
      // peers. Without a memoized in-flight load, each parses its OWN empty map
      // and the second writer clobbers the first's entry.
      await Future.wait([
        store.writeTokenFor('peerA', 'tok-A', '2026-07-06T00:00:00.000Z'),
        store.writeTokenFor('peerB', 'tok-B', '2026-07-06T00:00:00.000Z'),
      ]);

      expect((await store.readTokenFor('peerA'))?['tok'], 'tok-A');
      expect((await store.readTokenFor('peerB'))?['tok'], 'tok-B');

      // Both survived on disk too (a fresh impl reloads both).
      final reloaded = ReceivedWakeTokenStoreImpl(secureKeyStore: keyStore);
      expect((await reloaded.readTokenFor('peerA'))?['tok'], 'tok-A');
      expect((await reloaded.readTokenFor('peerB'))?['tok'], 'tok-B');
    },
  );

  test('clear() empties and removeTokenFor drops a single peer', () async {
    final keyStore = FakeSecureKeyStore();
    final store = ReceivedWakeTokenStoreImpl(secureKeyStore: keyStore);
    await store.writeTokenFor('peerA', 'tok-A', '2026-07-06T04:00:00.000Z');
    await store.writeTokenFor('peerB', 'tok-B', '2026-07-06T04:00:00.000Z');

    await store.removeTokenFor('peerA');
    expect(await store.readTokenFor('peerA'), isNull);
    expect(await store.readTokenFor('peerB'), isNotNull);

    await store.clear();
    expect(await store.readTokenFor('peerB'), isNull);
    expect(await keyStore.read(receivedWakeTokensSecureStorageKey), isNull);
  });
}
