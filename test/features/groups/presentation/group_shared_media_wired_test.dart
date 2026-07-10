import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_policy.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_shared_media_library_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../shared_media_test_fakes.dart';

void main() {
  test(
    'GML-02 production gallery is owner isolated under group id collisions',
    () async {
      final fixture = await MediaRepositoryRealDbFixture.create();
      addTearDown(fixture.dispose);
      await fixture.seedGroupParent('live', groupId: 'group-a');
      await fixture.seedGroupParent('deleted', groupId: 'group-a');
      await fixture.seedGroupParent('foreign', groupId: 'group-b');
      await fixture.seedDirectParent('live', contactPeerId: 'contact-a');
      Future<void> save(String id, String messageId, MediaOwnerLane owner) =>
          fixture.repo.saveAttachment(
            MediaAttachment(
              id: id,
              messageId: messageId,
              mime: 'image/jpeg',
              size: 10,
              mediaType: 'image',
              downloadStatus: 'evicted',
              createdAt: '2026-07-10T10:00:00.000Z',
            ),
            owner: owner,
          );
      await save('group-live', 'live', MediaOwnerLane.group);
      await save('group-deleted', 'deleted', MediaOwnerLane.group);
      await save('group-foreign', 'foreign', MediaOwnerLane.group);
      await save('direct-collision', 'live', MediaOwnerLane.direct);
      await dbDeleteGroupMessage(fixture.db, 'deleted');
      final controller = GroupSharedMediaLibraryController(
        groupId: 'group-a',
        libraryRepository: fixture.repo,
        stateRepository: fixture.repo,
      );
      await controller.loadNextPage();
      expect(controller.entries.map((entry) => entry.attachment.id), [
        'group-live',
      ]);
    },
  );

  testWidgets('GML-04 typed viewer crosses parent and cursor boundaries', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final temp = Directory.systemTemp.createTempSync('group-viewer-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final image = File('${temp.path}/one.png')..writeAsBytesSync(_tinyPng);
    final repository = StrictGroupMediaLibraryRepository(
      expectedGroupId: 'group-a',
      entries: [
        for (var index = 0; index < 51; index++)
          groupMediaEntry(
            'a$index',
            messageId: 'm$index',
            downloadStatus: 'done',
            localPath: image.path,
          ),
      ],
    );
    await tester.pumpWidget(_app(repository));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(
      find.byKey(const ValueKey('group-shared-media-grid')),
      const Offset(0, -5000),
    );
    await tester.pump(const Duration(milliseconds: 500));
    tester
        .widget<GestureDetector>(
          find.byKey(const ValueKey('media-grid-cell-m49-a49')),
        )
        .onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final viewer = tester.widget<FullScreenTypedMediaViewer>(
      find.byType(FullScreenTypedMediaViewer),
    );
    expect(viewer.initialIndex, 49);
    expect(viewer.items, hasLength(51));
    expect(
      viewer.items.map((item) => item.attachmentId).toSet(),
      hasLength(51),
    );
    expect(viewer.items[49].messageId, 'm49');
    expect(viewer.items[50].messageId, 'm50');
    expect(repository.requests, hasLength(2));
  });

  testWidgets(
    'GML-06F selected item reaches committed group forward adapter exactly once',
    (tester) async {
      final repository = StrictGroupMediaLibraryRepository(
        expectedGroupId: 'group-a',
        entries: [
          groupMediaEntry('first', messageId: 'message-a'),
          groupMediaEntry('selected', messageId: 'message-b'),
        ],
      );
      final messages = InMemoryGroupMessageRepository();
      final attachments = InMemoryMediaAttachmentRepository();
      await messages.saveMessage(
        GroupMessage(
          id: 'message-b',
          groupId: 'group-a',
          senderPeerId: 'peer',
          text: 'caption',
          timestamp: DateTime.utc(2026, 7, 10),
          isIncoming: true,
          createdAt: DateTime.utc(2026, 7, 10),
        ),
      );
      await attachments.saveAttachment(
        groupMediaEntry(
          'selected',
          messageId: 'message-b',
          downloadStatus: 'done',
          localPath: 'media/group-a/selected.jpg',
        ).attachment,
        owner: MediaOwnerLane.group,
      );
      final builder = GroupMediaForwardRequestBuilder(
        messageRepository: messages,
        mediaAttachmentRepository: attachments,
        operationTokenFactory: () => 'forward-token',
      );
      final group = GroupModel(
        id: 'group-a',
        name: 'Group',
        type: GroupType.chat,
        topicName: 'topic',
        createdAt: DateTime.utc(2026, 7, 10),
        createdBy: 'peer',
        myRole: GroupRole.member,
      );
      final calls = <GroupMediaForwardRequest>[];
      await tester.pumpWidget(
        _app(
          repository,
          dispatchForward: (identity) async {
            final request = await builder.build(
              group: group,
              messageId: identity.messageId,
              attachmentId: identity.attachmentId,
            );
            if (request != null) calls.add(request);
            return request != null;
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.longPress(
        find.byKey(const ValueKey('group-shared-media-tile-selected')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('group-shared-media-action-forward')),
      );
      await tester.pump();
      expect(calls, hasLength(1));
      expect(calls.single.groupId, 'group-a');
      expect(calls.single.messageId, 'message-b');
      expect(calls.single.attachmentId, 'selected');
    },
  );

  testWidgets('GML-11 explicit refresh boundaries remove phantom identities', (
    tester,
  ) async {
    final repository = StrictGroupMediaLibraryRepository(
      expectedGroupId: 'group-a',
      entries: [groupMediaEntry('phantom')],
    );
    final controller = GroupSharedMediaLibraryController(
      groupId: 'group-a',
      libraryRepository: repository,
      stateRepository: repository,
    );
    await controller.loadNextPage();
    controller.toggleSelection('phantom');
    repository.replaceEntries([groupMediaEntry('replacement')]);
    await controller.refreshCurrentPage();
    expect(controller.entries.single.attachment.id, 'replacement');
    expect(controller.selectedIds, isEmpty);

    await tester.pumpWidget(_app(repository));
    await tester.pump(const Duration(milliseconds: 100));
    final mountCalls = repository.requests.length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 100));
    expect(repository.requests.length, mountCalls + 1);

    final temp = Directory.systemTemp.createTempSync('group-refresh-viewer-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final image = File('${temp.path}/viewer.png')..writeAsBytesSync(_tinyPng);
    repository.replaceEntries([
      groupMediaEntry('current', downloadStatus: 'done', localPath: image.path),
      groupMediaEntry(
        'survivor',
        downloadStatus: 'done',
        localPath: image.path,
      ),
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_app(repository));
    await tester.pump(const Duration(milliseconds: 100));
    tester
        .widget<GestureDetector>(
          find.byKey(const ValueKey('media-grid-cell-message-current-current')),
        )
        .onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
    repository.replaceEntries([
      groupMediaEntry(
        'survivor',
        downloadStatus: 'done',
        localPath: image.path,
      ),
    ]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(FullScreenTypedMediaViewer), findsNothing);
    expect(
      find.byKey(const ValueKey('group-shared-media-tile-survivor')),
      findsOneWidget,
    );
  });
}

Widget _app(
  StrictGroupMediaLibraryRepository repository, {
  GroupSharedMediaForwardDispatch? dispatchForward,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: GroupSharedMediaLibraryScreen(
      groupId: 'group-a',
      libraryRepository: repository,
      stateRepository: repository,
      dispatchForward: dispatchForward,
      capabilitiesForEntry: dispatchForward == null
          ? null
          : (_) => const {
              GroupSharedMediaAction.bookmark,
              GroupSharedMediaAction.forward,
              GroupSharedMediaAction.goToMessage,
            },
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
