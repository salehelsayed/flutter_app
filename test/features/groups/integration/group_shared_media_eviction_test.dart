import 'package:flutter/material.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_batch_actions.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_shared_media_library_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared_media_test_fakes.dart';

void main() {
  testWidgets('GML-09 eviction retains entries and truthful eligibility', (
    tester,
  ) async {
    final repository = StrictGroupMediaLibraryRepository(
      expectedGroupId: 'group-a',
      entries: [
        groupMediaEntry(
          'media-a',
          messageId: 'parent-a',
          downloadStatus: 'done',
          localPath: '/missing/current.jpg',
          bookmarked: true,
        ),
      ],
    );
    var egressCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GroupSharedMediaLibraryScreen(
          groupId: 'group-a',
          libraryRepository: repository,
          stateRepository: repository,
          capabilitiesForEntry: (entry) => {
            GroupSharedMediaAction.bookmark,
            GroupSharedMediaAction.goToMessage,
            if (entry.attachment.downloadStatus == 'done') ...{
              GroupSharedMediaAction.save,
              GroupSharedMediaAction.share,
              GroupSharedMediaAction.evict,
            },
          },
          dispatchEgress: (_, destination) async {
            egressCalls++;
            return const GroupSharedMediaBatchResult(
              items: [],
              egressResult: null,
            );
          },
          dispatchEviction: (entries) async {
            repository.replaceEntries([
              groupMediaEntry(
                'media-a',
                messageId: 'parent-a',
                downloadStatus: 'evicted',
                bookmarked: true,
              ),
            ]);
            return {'media-a'};
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.longPress(
      find.byKey(const ValueKey('group-shared-media-tile-media-a')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('group-shared-media-action-evict')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('group-shared-media-action-evict')),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('group-shared-media-tile-media-a')),
      findsOneWidget,
      reason: 'message/library/bookmark identity survives local eviction',
    );
    expect(repository.bookmarkWrites, isEmpty);
    await tester.longPress(
      find.byKey(const ValueKey('group-shared-media-tile-media-a')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('group-shared-media-action-save')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('group-shared-media-action-share')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('group-shared-media-action-evict')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('group-shared-media-action-bookmark')),
      findsOneWidget,
    );
    expect(egressCalls, 0);
  });
}
