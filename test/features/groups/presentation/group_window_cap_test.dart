import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/conversation/domain/utils/message_window_cap.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';

void main() {
  GroupMessage msg(int i) => GroupMessage(
    id: 'g$i',
    groupId: 'group-1',
    senderPeerId: 'peer-a',
    text: 'm$i',
    timestamp: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
    createdAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
  );

  // TC-159-10 — the group mirror: the SAME shared trim helper caps the group
  // in-memory window newest-first (oldest evicted, live edge retained). The
  // group has no incremental older-page pagination, so the self-heal for an
  // evicted row is a full `_loadMessages` re-fetch (no `_hasMoreOlderMessages`).
  group('TC-159-10 group window cap (shared helper, newest-first)', () {
    test('caps group messages to the newest kMax, evicting the oldest', () {
      final messages = List<GroupMessage>.generate(
        kMaxInMemoryMessages + 7,
        msg,
      );
      final capped = trimToNewestInMemoryCap(messages);
      expect(capped.length, kMaxInMemoryMessages);
      // Oldest 0..6 evicted; window starts at g7.
      expect(capped.first.id, 'g7');
      // Newest (live edge) retained.
      expect(capped.last.id, 'g${kMaxInMemoryMessages + 6}');
    });

    test('131 guard: a just-upserted newest group row is never evicted', () {
      final messages = List<GroupMessage>.generate(
        kMaxInMemoryMessages + 1,
        msg,
      );
      final capped = trimToNewestInMemoryCap(messages);
      expect(capped.last.id, 'g$kMaxInMemoryMessages');
      expect(capped.any((m) => m.id == 'g0'), isFalse);
    });

    test('is a no-op when the group window is within the cap', () {
      final messages = List<GroupMessage>.generate(10, msg);
      expect(identical(trimToNewestInMemoryCap(messages), messages), isTrue);
    });
  });
}
