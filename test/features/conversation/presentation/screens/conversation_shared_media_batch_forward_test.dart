import 'dart:async';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/build_direct_media_library_batch_forward.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_shared_media_library_screen.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/share/application/direct_media_batch_forward_delivery_coordinator.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/fake_mic_permission_gateway.dart';
import '../../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../domain/repositories/strict_direct_media_library_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

const _contactPeerId = '12D3KooWPlan249SourceContact';

DirectReceivedMediaActionIdentity _identity(String attachmentId) =>
    DirectReceivedMediaActionIdentity(
      messageId: 'message-$attachmentId',
      attachmentId: attachmentId,
    );

MediaLibraryEntry _entry(
  String attachmentId, {
  String? localPath,
  String parentTimestamp = '2026-07-11T18:00:00.000Z',
}) => makeDirectLibraryEntry(
  attachmentId,
  contactPeerId: _contactPeerId,
  messageId: 'message-$attachmentId',
  localPath: localPath ?? 'media/$attachmentId.jpg',
  parentTimestamp: parentTimestamp,
);

ContactModel _contact() => const ContactModel(
  peerId: _contactPeerId,
  publicKey: 'source-contact-public-key',
  rendezvous: '/dns4/relay.invalid/tcp/443',
  username: 'Alice',
  signature: 'source-contact-signature',
  scannedAt: '2026-07-11T18:00:00.000Z',
  mlKemPublicKey: 'source-contact-mlkem-key',
);

ConversationMessage _parent(
  String attachmentId, {
  required String timestamp,
  required String caption,
}) => ConversationMessage(
  id: 'message-$attachmentId',
  contactPeerId: _contactPeerId,
  senderPeerId: _contactPeerId,
  text: caption,
  timestamp: timestamp,
  status: 'delivered',
  isIncoming: true,
  createdAt: timestamp,
);

ImageProcessor _imageProcessor({VoidCallback? onProcess}) => ImageProcessor(
  compressFile:
      ({
        required path,
        required quality,
        required keepExif,
        minWidth = 1920,
        minHeight = 1080,
      }) async {
        onProcess?.call();
        return null;
      },
  compressVideo: ({required path, required compress, onProgress}) async {
    onProcess?.call();
    return VideoProcessResult(path: path);
  },
);

class _TrackingMessageRepository extends InMemoryMessageRepository {
  _TrackingMessageRepository(this.timeline);

  final List<String> timeline;

  @override
  Future<ConversationMessage?> getMessage(String id) async {
    timeline.add('parent:$id');
    return super.getMessage(id);
  }
}

class _TrackingLibraryRepository extends StrictDirectMediaLibraryRepository {
  _TrackingLibraryRepository({required this.timeline})
    : super(expectedContactPeerId: _contactPeerId);

  final List<String> timeline;

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    timeline.add('attachment:$messageId');
    return super.getAttachmentsForMessage(messageId, owner: owner);
  }
}

class _TrackingContactRepository extends InMemoryContactRepository {
  int getContactCalls = 0;

  @override
  Future<ContactModel?> getContact(String peerId) async {
    getContactCalls += 1;
    return super.getContact(peerId);
  }
}

Widget _wiredApp({
  required _TrackingLibraryRepository repository,
  required _TrackingMessageRepository messageRepository,
  required _TrackingContactRepository contactRepository,
  required ChatMessageListener listener,
  required FakeBridge bridge,
  required FakeMediaFileManager mediaFileManager,
  required ImageProcessor imageProcessor,
  required bool includeBatchDependencies,
  DirectMediaBatchForwardPickerLauncher? pickerLauncher,
}) {
  final identityRepository = FakeIdentityRepository()
    ..seed(
      FakeIdentityRepository.makeIdentity(
        peerId: '12D3KooWPlan249OwnPeer',
        mlKemPublicKey: 'own-mlkem-public-key',
        mlKemSecretKey: 'own-mlkem-secret-key',
      ),
    );
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ConversationWired(
      contact: _contact(),
      identityRepo: identityRepository,
      messageRepo: messageRepository,
      chatMessageListener: listener,
      p2pService: FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: '12D3KooWPlan249OwnPeer',
        ),
      ),
      bridge: includeBatchDependencies ? bridge : null,
      contactRepo: contactRepository,
      mediaAttachmentRepo: repository,
      mediaFileManager: mediaFileManager,
      imageProcessor: imageProcessor,
      micPermissionGateway: FakeMicPermissionGateway(),
      directMediaBatchForwardPickerLauncher: pickerLauncher,
    ),
  );
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 12}) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> _openWiredLibrary(WidgetTester tester) async {
  await _pumpFrames(tester, count: 24);
  expect(tester.takeException(), isNull, reason: 'conversation mount');
  await tester.tap(find.byIcon(Icons.more_vert));
  await _pumpFrames(tester, count: 24);
  expect(tester.takeException(), isNull, reason: 'contact menu');
  await tester.tap(
    find.byKey(const ValueKey('conversation-shared-media-action')),
  );
  await _pumpFrames(tester);
  expect(find.byType(DirectSharedMediaLibraryScreen), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Widget _app({
  required StrictDirectMediaLibraryRepository repository,
  DirectMediaBatchForwardLibraryLaunch? launchBatchForward,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: DirectSharedMediaLibraryScreen(
    contactPeerId: _contactPeerId,
    contactUsername: 'Source contact',
    libraryRepository: repository,
    stateRepository: repository,
    resolveStoredPath: (path) => path,
    fileExists: (_) => true,
    launchBatchForward: launchBatchForward,
  ),
);

Finder _tile(String id) => find.byKey(ValueKey('shared-media-tile-$id'));

Future<void> _select(WidgetTester tester, String id) async {
  await tester.longPress(_tile(id));
  await tester.pump();
}

void main() {
  testWidgets(
    'ConversationWired hides batch forward when production dependencies are incomplete',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 2560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final timeline = <String>[];
      final repository = _TrackingLibraryRepository(timeline: timeline)
        ..seedPage(entries: [_entry('hidden')], nextCursor: null);
      final messages = _TrackingMessageRepository(timeline);
      final contacts = _TrackingContactRepository()..addTestContact(_contact());
      final listener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messages,
        contactRepo: contacts,
      );
      addTearDown(listener.dispose);
      var launcherCalls = 0;

      await tester.pumpWidget(
        _wiredApp(
          repository: repository,
          messageRepository: messages,
          contactRepository: contacts,
          listener: listener,
          bridge: FakeBridge(),
          mediaFileManager: FakeMediaFileManager(),
          imageProcessor: _imageProcessor(),
          includeBatchDependencies: false,
          pickerLauncher: (context, draft, deliveryCoordinator) async {
            launcherCalls += 1;
            return null;
          },
        ),
      );
      await _openWiredLibrary(tester);
      await _select(tester, 'hidden');

      expect(
        find.byKey(const ValueKey('shared-media-action-forward')),
        findsNothing,
      );
      expect(launcherCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ConversationWired source denial stops before picker contact file route or delivery work',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 2560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final timeline = <String>[];
      final repository = _TrackingLibraryRepository(timeline: timeline);
      final deniedEntry = _entry('denied', localPath: '/missing/denied.jpg');
      repository
        ..seedPage(entries: [deniedEntry], nextCursor: null)
        ..seed([deniedEntry.attachment]);
      final messages = _TrackingMessageRepository(timeline);
      final contacts = _TrackingContactRepository()..addTestContact(_contact());
      final listener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messages,
        contactRepo: contacts,
      );
      addTearDown(listener.dispose);
      final bridge = FakeBridge();
      final mediaFileManager = FakeMediaFileManager();
      var processingCalls = 0;
      var launcherCalls = 0;

      await tester.pumpWidget(
        _wiredApp(
          repository: repository,
          messageRepository: messages,
          contactRepository: contacts,
          listener: listener,
          bridge: bridge,
          mediaFileManager: mediaFileManager,
          imageProcessor: _imageProcessor(
            onProcess: () => processingCalls += 1,
          ),
          includeBatchDependencies: true,
          pickerLauncher: (context, draft, deliveryCoordinator) async {
            launcherCalls += 1;
            return null;
          },
        ),
      );
      await _openWiredLibrary(tester);
      await _select(tester, 'denied');
      timeline.clear();
      contacts.getContactCalls = 0;
      bridge.commandLog.clear();

      await tester.tap(
        find.byKey(const ValueKey('shared-media-action-forward')),
      );
      await _pumpFrames(tester);

      expect(timeline, ['parent:message-denied']);
      expect(launcherCalls, 0);
      expect(contacts.getContactCalls, 0);
      expect(mediaFileManager.resolveStoredPathCount, 0);
      expect(processingCalls, 0);
      expect(bridge.commandLog, isEmpty);
      expect(repository.allSavedAttachments, isEmpty);
      expect(await messages.getMessagesForContact(_contactPeerId), isEmpty);
      expect(
        find.byKey(const ValueKey('direct-batch-forward-picker')),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('shared-media-batch-forward-source-unavailable'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ConversationWired preflights exact sources before its dedicated picker and maps cancellation and completion',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 2560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = Directory.systemTemp.createTempSync(
        'plan249_conversation_wired_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final olderPath = File('${directory.path}/older.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final newerPath = File('${directory.path}/newer.jpg')
        ..writeAsBytesSync([4, 5, 6]);
      const olderTimestamp = '2026-07-11T18:00:01.000Z';
      const newerTimestamp = '2026-07-11T18:00:02.000Z';
      final olderEntry = _entry(
        'a1',
        localPath: olderPath.path,
        parentTimestamp: olderTimestamp,
      );
      final newerEntry = _entry(
        'a2',
        localPath: newerPath.path,
        parentTimestamp: newerTimestamp,
      );
      final timeline = <String>[];
      final repository = _TrackingLibraryRepository(timeline: timeline)
        ..seedPage(entries: [newerEntry, olderEntry], nextCursor: null)
        ..seed([olderEntry.attachment, newerEntry.attachment]);
      final messages = _TrackingMessageRepository(timeline);
      await messages.saveMessage(
        _parent(
          'a1',
          timestamp: olderTimestamp,
          caption: 'older independent caption',
        ),
      );
      await messages.saveMessage(
        _parent(
          'a2',
          timestamp: newerTimestamp,
          caption: 'newer independent caption',
        ),
      );
      final contacts = _TrackingContactRepository()..addTestContact(_contact());
      final listener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messages,
        contactRepo: contacts,
      );
      addTearDown(listener.dispose);
      final capturedDrafts = <DirectMediaLibraryBatchForwardDraft>[];
      final capturedCoordinators =
          <DirectMediaBatchForwardDeliveryCoordinator>[];

      await tester.pumpWidget(
        _wiredApp(
          repository: repository,
          messageRepository: messages,
          contactRepository: contacts,
          listener: listener,
          bridge: FakeBridge(),
          mediaFileManager: FakeMediaFileManager(),
          imageProcessor: _imageProcessor(),
          includeBatchDependencies: true,
          pickerLauncher: (context, draft, deliveryCoordinator) async {
            timeline.add('launcher');
            capturedDrafts.add(draft);
            capturedCoordinators.add(deliveryCoordinator);
            if (capturedDrafts.length == 1) return null;
            final matrix = DirectMediaBatchForwardMatrix(
              cells: [
                DirectMediaBatchForwardCellResult(
                  key: DirectMediaBatchForwardCellKey(
                    sourceIdentity: _identity('a1'),
                    contactPeerId: 'recipient',
                  ),
                  status: DirectMediaBatchForwardCellStatus.sent,
                ),
                DirectMediaBatchForwardCellResult(
                  key: DirectMediaBatchForwardCellKey(
                    sourceIdentity: _identity('a2'),
                    contactPeerId: 'recipient',
                  ),
                  status: DirectMediaBatchForwardCellStatus.failed,
                ),
              ],
            );
            return DirectMediaBatchForwardCompletion.fromMatrix(matrix);
          },
        ),
      );
      await _openWiredLibrary(tester);
      await _select(tester, 'a1');
      await _select(tester, 'a2');
      timeline.clear();

      await tester.tap(
        find.byKey(const ValueKey('shared-media-action-forward')),
      );
      await _pumpFrames(tester);

      expect(timeline, [
        'parent:message-a1',
        'attachment:message-a1',
        'parent:message-a2',
        'attachment:message-a2',
        'launcher',
      ]);
      expect(capturedDrafts, hasLength(1));
      expect(capturedCoordinators, hasLength(1));
      expect(
        capturedCoordinators.single,
        isA<DirectMediaBatchForwardDeliveryCoordinator>(),
      );
      final canonical = capturedDrafts.single;
      expect(canonical.items.map((item) => item.identity).toList(), [
        _identity('a2'),
        _identity('a1'),
      ]);
      expect(canonical.items.map((item) => item.resolvedPath).toList(), [
        newerPath.path,
        olderPath.path,
      ]);
      expect(canonical.items.map((item) => item.caption).toList(), [
        'newer independent caption',
        'older independent caption',
      ]);
      final tokens = canonical.items
          .map((item) => item.forwardProvenance.operationDedupKey)
          .toList();
      expect(tokens.every((token) => token.trim().isNotEmpty), isTrue);
      expect(tokens.toSet(), hasLength(2));
      expect(find.text('2 selected'), findsOneWidget);

      timeline.clear();
      await tester.tap(
        find.byKey(const ValueKey('shared-media-action-forward')),
      );
      await _pumpFrames(tester);

      expect(timeline, [
        'parent:message-a1',
        'attachment:message-a1',
        'parent:message-a2',
        'attachment:message-a2',
        'launcher',
      ]);
      expect(capturedDrafts, hasLength(2));
      expect(capturedCoordinators, hasLength(2));
      expect(find.text('1 selected'), findsOneWidget);
      expect(
        tester.getSemantics(_tile('a1')).flagsCollection.isSelected,
        Tristate.isFalse,
      );
      expect(
        tester.getSemantics(_tile('a2')).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'batch forward action is nullable reentry guarded and cancel preserves exact selection',
    (tester) async {
      final repository = StrictDirectMediaLibraryRepository(
        expectedContactPeerId: _contactPeerId,
      )..seedPage(entries: [_entry('a1'), _entry('a2')], nextCursor: null);

      await tester.pumpWidget(_app(repository: repository));
      await tester.pump();
      await _select(tester, 'a1');
      expect(
        find.byKey(const ValueKey('shared-media-action-forward')),
        findsNothing,
      );

      // Tear down the first screen so the second mount starts with an empty
      // selection; this test intentionally exercises both callback states.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      final pending = Completer<DirectMediaBatchForwardLibraryLaunchResult>();
      final calls = <List<DirectReceivedMediaActionIdentity>>[];
      await tester.pumpWidget(
        _app(
          repository: repository,
          launchBatchForward: (identities) {
            calls.add(List.unmodifiable(identities));
            return pending.future;
          },
        ),
      );
      await tester.pump();
      await _select(tester, 'a1');
      await _select(tester, 'a2');

      final action = find.byKey(const ValueKey('shared-media-action-forward'));
      expect(action, findsOneWidget);
      await tester.tap(action);
      await tester.tap(action, warnIfMissed: false);
      await tester.pump();

      expect(
        calls,
        hasLength(1),
        reason: 'a live route launch is single-flight',
      );
      expect(calls.single.toSet(), {_identity('a1'), _identity('a2')});

      pending.complete(
        const DirectMediaBatchForwardLibraryLaunchResult.cancelled(),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('shared-media-selection-title')),
        findsOneWidget,
      );
      expect(find.text('2 selected'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('shared-media-batch-forward-source-unavailable'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'source unavailable is generic and completion clears only fully settled sources',
    (tester) async {
      final repository = StrictDirectMediaLibraryRepository(
        expectedContactPeerId: _contactPeerId,
      )..seedPage(entries: [_entry('a1'), _entry('a2')], nextCursor: null);
      var result =
          const DirectMediaBatchForwardLibraryLaunchResult.sourceUnavailable();

      await tester.pumpWidget(
        _app(repository: repository, launchBatchForward: (_) async => result),
      );
      await tester.pump();
      await _select(tester, 'a1');
      await _select(tester, 'a2');
      await tester.tap(
        find.byKey(const ValueKey('shared-media-action-forward')),
      );
      await tester.pump();

      expect(
        find.byKey(
          const ValueKey('shared-media-batch-forward-source-unavailable'),
        ),
        findsOneWidget,
      );
      expect(find.text('2 selected'), findsOneWidget);
      for (final forbidden in <String>[
        'private',
        'expired',
        'corrupt',
        'media/a1.jpg',
      ]) {
        expect(
          find.textContaining(forbidden, findRichText: true),
          findsNothing,
        );
      }

      final matrix = DirectMediaBatchForwardMatrix(
        cells: [
          DirectMediaBatchForwardCellResult(
            key: DirectMediaBatchForwardCellKey(
              sourceIdentity: _identity('a1'),
              contactPeerId: 'recipient',
            ),
            status: DirectMediaBatchForwardCellStatus.sent,
          ),
          DirectMediaBatchForwardCellResult(
            key: DirectMediaBatchForwardCellKey(
              sourceIdentity: _identity('a2'),
              contactPeerId: 'recipient',
            ),
            status: DirectMediaBatchForwardCellStatus.failed,
          ),
        ],
      );
      result = DirectMediaBatchForwardLibraryLaunchResult.completed(
        DirectMediaBatchForwardCompletion.fromMatrix(matrix),
      );
      await tester.tap(
        find.byKey(const ValueKey('shared-media-action-forward')),
      );
      await tester.pump();

      expect(find.text('1 selected'), findsOneWidget);
      final a1 = tester.getSemantics(_tile('a1'));
      final a2 = tester.getSemantics(_tile('a2'));
      expect(a1.flagsCollection.isSelected, Tristate.isFalse);
      expect(a2.flagsCollection.isSelected, Tristate.isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('batch forward does not replace existing selection actions', (
    tester,
  ) async {
    final repository = StrictDirectMediaLibraryRepository(
      expectedContactPeerId: _contactPeerId,
    )..seedPage(entries: [_entry('a1')], nextCursor: null);

    await tester.pumpWidget(
      _app(
        repository: repository,
        launchBatchForward: (_) async =>
            const DirectMediaBatchForwardLibraryLaunchResult.cancelled(),
      ),
    );
    await tester.pump();
    await _select(tester, 'a1');

    expect(
      find.byKey(const ValueKey('shared-media-action-forward')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('shared-media-action-goto')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
