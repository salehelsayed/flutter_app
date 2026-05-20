import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/application/group_media_allowed_peers.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';

void main() {
  GroupMember member(String peerId) {
    return GroupMember(
      groupId: 'group-1',
      peerId: peerId,
      username: peerId,
      role: MemberRole.writer,
      publicKey: 'pk-$peerId',
      mlKemPublicKey: 'mlkem-$peerId',
      joinedAt: DateTime.utc(2026, 5, 14),
    );
  }

  test('PL-005 builds media allowedPeers from unique active member rows', () {
    final allowedPeers = groupMediaAllowedPeersForMembers([
      member(' peer-admin '),
      member('peer-bob'),
      member(''),
      member('peer-bob'),
      member('peer-charlie'),
    ]);

    expect(allowedPeers, ['peer-admin', 'peer-bob', 'peer-charlie']);
  });
}
