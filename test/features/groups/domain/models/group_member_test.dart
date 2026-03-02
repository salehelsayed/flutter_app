import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';

void main() {
  group('GroupMember', () {
    Map<String, dynamic> makeMap({
      String groupId = 'group-1',
      String peerId = 'peer-1',
      String? username = 'Alice',
      String role = 'writer',
      String? publicKey = 'pk-base64',
      String? mlKemPublicKey = 'mlkem-base64',
      String joinedAt = '2026-01-15T12:00:00.000Z',
    }) {
      return {
        'group_id': groupId,
        'peer_id': peerId,
        'username': username,
        'role': role,
        'public_key': publicKey,
        'ml_kem_public_key': mlKemPublicKey,
        'joined_at': joinedAt,
      };
    }

    test('fromMap/toMap round-trip preserves all fields', () {
      final map = makeMap();
      final model = GroupMember.fromMap(map);
      final result = model.toMap();

      expect(result['group_id'], 'group-1');
      expect(result['peer_id'], 'peer-1');
      expect(result['username'], 'Alice');
      expect(result['role'], 'writer');
      expect(result['public_key'], 'pk-base64');
      expect(result['ml_kem_public_key'], 'mlkem-base64');
      expect(result['joined_at'], '2026-01-15T12:00:00.000Z');
    });

    test('MemberRole enum converts correctly', () {
      expect(MemberRole.fromValue('admin'), MemberRole.admin);
      expect(MemberRole.fromValue('writer'), MemberRole.writer);
      expect(MemberRole.fromValue('reader'), MemberRole.reader);
      expect(MemberRole.admin.toValue(), 'admin');
      expect(MemberRole.writer.toValue(), 'writer');
      expect(MemberRole.reader.toValue(), 'reader');
    });

    test('equality based on groupId and peerId', () {
      final a = GroupMember.fromMap(makeMap(groupId: 'g1', peerId: 'p1'));
      final b = GroupMember.fromMap(makeMap(groupId: 'g1', peerId: 'p1', username: 'Bob'));
      final c = GroupMember.fromMap(makeMap(groupId: 'g1', peerId: 'p2'));

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
