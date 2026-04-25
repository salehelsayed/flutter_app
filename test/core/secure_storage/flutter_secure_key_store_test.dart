import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';

void main() {
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
    });
  });
}
