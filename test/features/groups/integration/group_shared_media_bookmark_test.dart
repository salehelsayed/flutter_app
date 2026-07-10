import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared_media_test_fakes.dart';

void main() {
  test(
    'GML-07 bookmarks are owner isolated and durable across remount',
    () async {
      final repository = StrictGroupMediaLibraryRepository(
        expectedGroupId: 'group-a',
        entries: [
          groupMediaEntry('group-row'),
          groupMediaEntry('direct-poison', ownerLane: MediaOwnerLane.direct),
          groupMediaEntry('unresolved-poison', ownerLane: null),
        ],
      );
      final first = GroupSharedMediaLibraryController(
        groupId: 'group-a',
        libraryRepository: repository,
        stateRepository: repository,
      );
      await first.loadNextPage();
      expect(await first.toggleBookmark('group-row'), isTrue);
      expect(await first.toggleBookmark('direct-poison'), isFalse);
      expect(repository.bookmarkWrites, [('group-row', true)]);

      final remounted = GroupSharedMediaLibraryController(
        groupId: 'group-a',
        libraryRepository: repository,
        stateRepository: repository,
      );
      await remounted.setFilter(GroupSharedMediaFilter.bookmarked);
      expect(remounted.entries.map((entry) => entry.attachment.id), [
        'group-row',
      ]);
      expect(remounted.entries.single.attachment.isBookmarked, isTrue);

      remounted.toggleSelection('group-row');
      expect(
        await remounted.setBookmarked('group-row', bookmarked: true),
        isTrue,
      );
      expect(
        repository.bookmarkWrites,
        [('group-row', true)],
        reason: 'batch Bookmark is idempotent and never toggles back off',
      );
    },
  );
}
