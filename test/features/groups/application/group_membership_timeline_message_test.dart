import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'UP-002 builds readable durable add remove and re-add timeline events',
    () {
      const groupId = 'grp-up002-timeline-builders';
      const alicePeerId = 'peer-up002-alice';
      const charliePeerId = 'peer-up002-charlie';
      final firstAddAt = DateTime.utc(2026, 5, 16, 9);
      final removeAt = firstAddAt.add(const Duration(minutes: 1));
      final readdAt = firstAddAt.add(const Duration(minutes: 2));

      final firstAdd = buildMembersAddedTimelineMessage(
        groupId: groupId,
        addedMembers: const [(peerId: charliePeerId, username: 'Charlie')],
        senderId: alicePeerId,
        senderUsername: 'Alice',
        eventAt: firstAddAt,
      );
      final removal = buildMemberRemovedTimelineMessage(
        groupId: groupId,
        removedPeerId: charliePeerId,
        removedUsername: 'Charlie',
        senderId: alicePeerId,
        senderUsername: 'Alice',
        eventAt: removeAt,
      );
      final readd = buildMembersAddedTimelineMessage(
        groupId: groupId,
        addedMembers: const [(peerId: charliePeerId, username: 'Charlie')],
        senderId: alicePeerId,
        senderUsername: 'Alice',
        eventAt: readdAt,
      );

      expect(firstAdd.text, 'Alice added Charlie');
      expect(removal.text, 'Alice removed Charlie');
      expect(readd.text, 'Alice added Charlie');
      expect(
        firstAdd.id,
        startsWith('sys-members_added:$groupId:$charliePeerId'),
      );
      expect(
        removal.id,
        startsWith('sys-member_removed:$groupId:$charliePeerId'),
      );
      expect(readd.id, isNot(firstAdd.id));
      expect(
        [firstAdd, removal, readd].map((message) => message.timestamp).toList(),
        orderedEquals([firstAddAt, removeAt, readdAt]),
      );
      expect(
        [firstAdd, removal, readd].every(
          (message) =>
              message.status == 'delivered' &&
              message.isIncoming &&
              message.createdAt == message.timestamp,
        ),
        isTrue,
      );
    },
  );
}
