import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared_media_test_fakes.dart';

void main() {
  test(
    'GML-02F strict contract rejects request drift and poisoned owner adaptation',
    () async {
      final repository = StrictGroupMediaLibraryRepository(
        expectedGroupId: 'group-a',
        entries: [
          groupMediaEntry('group-row'),
          groupMediaEntry('direct-row', ownerLane: MediaOwnerLane.direct),
          groupMediaEntry('unresolved-row', ownerLane: null),
          groupMediaEntry('video-row', mediaType: 'video'),
        ],
      );
      final controller = GroupSharedMediaLibraryController(
        groupId: 'group-a',
        libraryRepository: repository,
        stateRepository: repository,
      );

      await controller.loadNextPage();
      expect(controller.entries.map((entry) => entry.attachment.id), [
        'group-row',
      ]);
      expect(
        repository.requests.single.scope,
        MediaLibraryScope.group('group-a'),
      );
      expect(repository.requests.single.limit, kGroupSharedMediaPageSize);
      expect(repository.requests.single.cursor, isNull);

      await controller.setFilter(GroupSharedMediaFilter.videos);
      expect(repository.requests.last.cursor, isNull);
      expect(repository.requests.last.filter.kind, MediaLibraryKind.video);
      expect(controller.entries.single.attachment.id, 'video-row');
      expect(controller.toggleSelection('direct-row'), isFalse);
      expect(await controller.toggleBookmark('unresolved-row'), isFalse);
      expect(repository.bookmarkWrites, isEmpty);

      await expectLater(
        repository.getMediaLibraryPage(
          scope: const MediaLibraryScope.group('group-a'),
          limit: 0,
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.getMediaLibraryPage(
          scope: const MediaLibraryScope.group('group-a'),
          limit: 101,
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.getMediaLibraryPage(
          scope: const MediaLibraryScope.group('group-b'),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.getMediaLibraryPage(
          scope: const MediaLibraryScope.group('group-a'),
          filter: const MediaLibraryFilter(kind: MediaLibraryKind.video),
          cursor: 'group-a|image:a|50',
        ),
        throwsArgumentError,
      );
    },
  );
}
