import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';

void main() {
  group('GroupKeyInfo', () {
    Map<String, dynamic> makeMap({
      String groupId = 'group-1',
      int keyGeneration = 1,
      String encryptedKey = 'base64-encrypted-key',
      String createdAt = '2026-01-15T12:00:00.000Z',
    }) {
      return {
        'group_id': groupId,
        'key_generation': keyGeneration,
        'encrypted_key': encryptedKey,
        'created_at': createdAt,
      };
    }

    test('fromMap/toMap round-trip preserves all fields', () {
      final map = makeMap();
      final model = GroupKeyInfo.fromMap(map);
      final result = model.toMap();

      expect(result['group_id'], 'group-1');
      expect(result['key_generation'], 1);
      expect(result['encrypted_key'], 'base64-encrypted-key');
      expect(result['created_at'], '2026-01-15T12:00:00.000Z');
    });

    test('equality based on groupId and keyGeneration', () {
      final a = GroupKeyInfo.fromMap(makeMap(groupId: 'g1', keyGeneration: 1));
      final b = GroupKeyInfo.fromMap(
        makeMap(groupId: 'g1', keyGeneration: 1, encryptedKey: 'different'),
      );
      final c = GroupKeyInfo.fromMap(makeMap(groupId: 'g1', keyGeneration: 2));

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
