import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/push/infrastructure/wake_token_store_impl.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

// FDC-09 §12 — WakeTokenStoreImpl persists the recipient's minted {contact ->
// token} map in SecureKeyStore (mirrors PushTokenStoreImpl) and survives reload.
void main() {
  test('writes, reads back, and survives a reload', () async {
    final keyStore = FakeSecureKeyStore();
    final store = WakeTokenStoreImpl(secureKeyStore: keyStore);

    expect(await store.readTokens(), isEmpty);

    await store.writeTokens({'c1': 'tok-1', 'c2': 'tok-2'});
    expect(await store.readTokens(), {'c1': 'tok-1', 'c2': 'tok-2'});

    // Reload: a NEW impl over the same backing store reads the persisted map.
    final reloaded = WakeTokenStoreImpl(secureKeyStore: keyStore);
    expect(await reloaded.readTokens(), {'c1': 'tok-1', 'c2': 'tok-2'});
  });

  test('writing an empty map clears the entry', () async {
    final keyStore = FakeSecureKeyStore();
    final store = WakeTokenStoreImpl(secureKeyStore: keyStore);
    await store.writeTokens({'c1': 'tok-1'});
    await store.writeTokens({});
    expect(await store.readTokens(), isEmpty);
  });

  test('a corrupt blob reads as empty (never throws)', () async {
    final keyStore = FakeSecureKeyStore();
    await keyStore.write(wakeTokensSecureStorageKey, 'not-json{');
    final store = WakeTokenStoreImpl(secureKeyStore: keyStore);
    expect(await store.readTokens(), isEmpty);
  });
}
