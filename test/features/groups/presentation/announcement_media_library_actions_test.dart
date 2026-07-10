import 'package:flutter/material.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_batch_actions.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_shared_media_library_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared_media_test_fakes.dart';

void main() {
  testWidgets(
    'AML-07 selection cap and capability intersection fail closed for every batch action',
    (tester) async {
      final repository = StrictGroupMediaLibraryRepository(
        expectedGroupId: 'announcement-a',
        entries: [for (var i = 0; i < 11; i++) groupMediaEntry('a$i')],
      );
      final controller = GroupSharedMediaLibraryController(
        groupId: 'announcement-a',
        incomingOnly: true,
        libraryRepository: repository,
        stateRepository: repository,
      );
      await controller.loadNextPage();
      for (var i = 0; i < 10; i++) {
        expect(controller.toggleSelection('a$i'), isTrue);
      }
      expect(controller.toggleSelection('a10'), isFalse);
      expect(controller.selectedCount, 10);

      final widgetRepository = StrictGroupMediaLibraryRepository(
        expectedGroupId: 'announcement-a',
        entries: [groupMediaEntry('a0'), groupMediaEntry('a1')],
      );
      var dispatches = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupSharedMediaLibraryScreen(
            groupId: 'announcement-a',
            incomingOnly: true,
            libraryRepository: widgetRepository,
            stateRepository: widgetRepository,
            dispatchForward: (_) async {
              dispatches++;
              return true;
            },
            dispatchDelete: (_) async =>
                const GroupSharedMediaBatchDeleteOutcome(
                  deletedMessageIds: {},
                  failedMessageIds: {},
                  deletedAttachmentIds: {},
                  failedAttachmentIds: {},
                ),
            capabilitiesForEntry: (_) => const {
              GroupSharedMediaAction.bookmark,
              GroupSharedMediaAction.delete,
              GroupSharedMediaAction.evict,
              GroupSharedMediaAction.goToMessage,
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 2; i++) {
        await tester.longPress(
          find.byKey(ValueKey('group-shared-media-tile-a$i')),
        );
        await tester.pump();
      }
      expect(
        find.byKey(const ValueKey('group-shared-media-selection-title')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('group-shared-media-action-forward')),
        findsNothing,
      );
      expect(dispatches, 0);
    },
  );
}
