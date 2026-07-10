import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_batch_actions.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_shared_media_library_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/media_grid_cell.dart';
import 'package:flutter_app/shared/widgets/media/media_thumbnail_image.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared_media_test_fakes.dart';

void main() {
  testWidgets(
    'GML-03 grid virtualizes pages and bounds static thumbnail decode',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final temp = Directory.systemTemp.createTempSync('group-library-grid-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final image = File('${temp.path}/large.jpg')..writeAsBytesSync(_tinyPng);
      final repository = StrictGroupMediaLibraryRepository(
        expectedGroupId: 'group-a',
        entries: [
          groupMediaEntry(
            'large',
            downloadStatus: 'done',
            localPath: image.path,
          ),
          for (var index = 1; index < 105; index++)
            groupMediaEntry(
              'image-$index',
              parentTimestamp: '2026-07-10T10:00:00.000Z',
            ),
        ],
      );

      await tester.pumpWidget(_app(repository));
      await tester.pump(const Duration(milliseconds: 100));
      expect(repository.requests, hasLength(1));
      expect(find.byType(MediaGridCell).evaluate().length, lessThan(50));
      final thumbnail = tester.widget<MediaThumbnailImage>(
        find.byType(MediaThumbnailImage).first,
      );
      expect(thumbnail.cacheWidth, lessThanOrEqualTo(400));

      final gate = Completer<void>();
      repository.nextRequestGate = gate;
      await tester.drag(
        find.byKey(const ValueKey('group-shared-media-grid')),
        const Offset(0, -4000),
      );
      await tester.pump();
      await tester.drag(
        find.byKey(const ValueKey('group-shared-media-grid')),
        const Offset(0, -1000),
      );
      await tester.pump();
      expect(
        repository.requests,
        hasLength(2),
        reason: 'in-flight loads coalesce',
      );
      gate.complete();
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('group-shared-media-grid')),
        const Offset(0, -5000),
      );
      await tester.pumpAndSettle();
      expect(repository.requests, hasLength(3));
      expect(
        repository.requests.every((request) => request.limit <= 100),
        isTrue,
      );
      expect(
        find.byKey(const ValueKey('group-shared-media-tile-image-104')),
        findsNothing,
        reason: 'off-screen third-page cells remain virtualized',
      );
    },
  );

  testWidgets('GML-05 selection cap and capability intersection fail closed', (
    tester,
  ) async {
    final repository = StrictGroupMediaLibraryRepository(
      expectedGroupId: 'group-a',
      entries: [
        for (var index = 0; index < 11; index++) groupMediaEntry('a$index'),
      ],
    );
    final controller = GroupSharedMediaLibraryController(
      groupId: 'group-a',
      libraryRepository: repository,
      stateRepository: repository,
    );
    await controller.loadNextPage();
    for (var index = 0; index < 10; index++) {
      expect(controller.toggleSelection('a$index'), isTrue);
    }
    final requestsBeforeEleventh = repository.requests.length;
    expect(controller.toggleSelection('a10'), isFalse);
    expect(controller.selectedCount, kGroupSharedMediaSelectionLimit);
    expect(repository.requests, hasLength(requestsBeforeEleventh));
    expect(repository.bookmarkWrites, isEmpty);

    await tester.pumpWidget(
      _app(
        StrictGroupMediaLibraryRepository(
          expectedGroupId: 'group-a',
          entries: [groupMediaEntry('a'), groupMediaEntry('b')],
        ),
        dispatchDelete: (_) async => const GroupSharedMediaBatchDeleteOutcome(
          deletedMessageIds: {},
          failedMessageIds: {},
          deletedAttachmentIds: {},
          failedAttachmentIds: {},
        ),
        dispatchForward: (_) async => true,
        dispatchEgress: (_, destination) =>
            throw StateError('must stay hidden'),
        capabilitiesForEntry: (entry) => {
          GroupSharedMediaAction.bookmark,
          GroupSharedMediaAction.delete,
          GroupSharedMediaAction.goToMessage,
          if (entry.attachment.id == 'a') ...{
            GroupSharedMediaAction.save,
            GroupSharedMediaAction.share,
          },
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.longPress(
      find.byKey(const ValueKey('group-shared-media-tile-a')),
    );
    await tester.pump();
    await tester.longPress(
      find.byKey(const ValueKey('group-shared-media-tile-b')),
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
      find.byKey(const ValueKey('group-shared-media-action-forward')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('group-shared-media-action-delete')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('group-shared-media-action-bookmark')),
      findsOneWidget,
    );
  });
}

Widget _app(
  StrictGroupMediaLibraryRepository repository, {
  GroupSharedMediaDeleteDispatch? dispatchDelete,
  GroupSharedMediaForwardDispatch? dispatchForward,
  GroupSharedMediaEgressDispatch? dispatchEgress,
  GroupSharedMediaCapabilityResolver? capabilitiesForEntry,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: GroupSharedMediaLibraryScreen(
      groupId: 'group-a',
      libraryRepository: repository,
      stateRepository: repository,
      dispatchDelete: dispatchDelete,
      dispatchForward: dispatchForward,
      dispatchEgress: dispatchEgress,
      capabilitiesForEntry: capabilitiesForEntry,
    ),
  );
}

const _tinyPng = <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  8,
  215,
  99,
  248,
  207,
  192,
  240,
  31,
  0,
  5,
  0,
  1,
  255,
  137,
  153,
  61,
  29,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];
