import 'dart:async';

import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared_media_test_fakes.dart';

void main() {
  test(
    'AML-03 pager preserves incoming only cursor identity across filters and races',
    () async {
      final repository = StrictGroupMediaLibraryRepository(
        expectedGroupId: 'announcement-a',
        entries: [groupMediaEntry('one')],
      );
      final controller = GroupSharedMediaLibraryController(
        groupId: 'announcement-a',
        incomingOnly: true,
        libraryRepository: repository,
        stateRepository: repository,
      );
      await controller.loadNextPage();
      expect(repository.requests.single.filter.incomingOnly, isTrue);
      expect(repository.requests.single.limit, inInclusiveRange(1, 100));

      for (final filter in GroupSharedMediaFilter.values) {
        if (filter == controller.filter) continue;
        await controller.setFilter(filter);
        expect(repository.requests.last.filter.incomingOnly, isTrue);
      }

      final gate = Completer<void>();
      repository.nextRequestGate = gate;
      final older = controller.setFilter(GroupSharedMediaFilter.images);
      final newer = controller.setFilter(GroupSharedMediaFilter.videos);
      gate.complete();
      await Future.wait([older, newer]);
      expect(controller.filter, GroupSharedMediaFilter.videos);
      expect(repository.requests.every((r) => r.filter.incomingOnly), isTrue);
    },
  );
}
