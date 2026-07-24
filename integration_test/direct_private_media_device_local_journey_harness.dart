import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_viewer_controller.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/private_media_action_eligibility.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_private_media_lifecycle_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_private_media_viewer.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import '../test/core/bridge/fake_bridge.dart';
import '../test/shared/fakes/in_memory_message_repository.dart';

const _artifactMarker = 'P234_DEVICE_ARTIFACT=';
const _role = String.fromEnvironment('P234_ROLE');
const _deviceId = String.fromEnvironment('P234_DEVICE_ID');
const _correlatedPrivateMessageId = 'p234-private-fixture';
const _correlatedPrivateAttachmentId = 'p234-private-fixture-attachment';
const _privateFixtureText = 'never disclose this caption';
const _productionOutgoingFixtureId = 'p260-production-outgoing';
const _productionIncomingFixtureId = 'p260-production-incoming';
const _productionTerminalFixtureId = 'p260-production-terminal';
const _pendingOpenFixtureId = 'p262-sender-pending';
const _pendingOpenAttachmentId = 'p262-sender-pending-attachment';
const _pendingOpenSqlStateSequence = <String>[
  'available',
  'opening',
  'viewing',
  'consumed',
];
const _pendingOpenProofSequence = <String>[
  'pending_sql_authority_verified',
  'repository_mirror_seeded',
  'open_tapped',
  'opening_sql_observed',
  'viewer_first_frame',
  'viewing_sql_observed',
  'viewer_back_tapped',
  'conversation_route_resumed',
  'consumed_sql_observed',
  'attachment_cleanup_observed',
  'pending_source_cleanup_observed',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('instrumented Plan 234 device-local journey', (tester) async {
    flowEventLoggingEnabled = false;
    addTearDown(() {
      flowEventLoggingEnabled = true;
    });
    expect(_deviceId, isNotEmpty, reason: 'P234_DEVICE_ID is required');
    expect(
      _role,
      anyOf('sender', 'recipient'),
      reason: 'P234_ROLE must be sender or recipient',
    );

    final productionConversation = await _runProductionConversationProof(
      tester,
    );
    final artifact = _role == 'sender'
        ? await _runSenderProof(tester, productionConversation)
        : await _runRecipientProof(productionConversation);
    final encoded = base64Url.encode(utf8.encode(jsonEncode(artifact)));
    // The runner captures exactly one marker and performs strict combined
    // validation. The artifact contains no payload text, path, key, or nonce.
    // ignore: avoid_print
    print('$_artifactMarker$encoded');
    await tester.pump();
  });
}

Future<Map<String, Object?>> _runProductionConversationProof(
  WidgetTester tester,
) async {
  final tempRoot = await Directory.systemTemp.createTemp(
    'p260-production-private-cards-',
  );
  final databasePath = p.join(tempRoot.path, 'production-cards.db');
  sqlcipher.Database? database;
  try {
    ConversationMessage fixture({
      required String id,
      required bool isIncoming,
      required PrivateMediaPolicy policy,
      required PrivateMediaLifecycleState state,
      int? receivedAtMs,
      int? revealedAtMs,
      int? terminalAtMs,
      int? highWaterMs,
    }) {
      return ConversationMessage(
        id: id,
        contactPeerId: 'p260-production-contact',
        senderPeerId: isIncoming
            ? 'p260-production-contact'
            : 'p260-production-own-peer',
        text: '',
        timestamp: '2026-07-19T10:00:00.000Z',
        status: 'sent',
        isIncoming: isIncoming,
        createdAt: '2026-07-19T10:00:00.000Z',
        privateMediaPolicy: policy,
        privateMediaState: state,
        privateMediaReceivedAtMs: receivedAtMs,
        privateMediaRevealedAtMs: revealedAtMs,
        privateMediaTerminalAtMs: terminalAtMs,
        privateMediaClockHighWaterMs: highWaterMs,
      );
    }

    final durableFixtures = <ConversationMessage>[
      fixture(
        id: _productionOutgoingFixtureId,
        isIncoming: false,
        policy: const PrivateMediaPolicy.protected(),
        state: PrivateMediaLifecycleState.available,
      ),
      fixture(
        id: _productionIncomingFixtureId,
        isIncoming: true,
        policy: const PrivateMediaPolicy.viewOnce(),
        state: PrivateMediaLifecycleState.available,
        receivedAtMs: 1_752_307_200_000,
        highWaterMs: 1_752_307_200_000,
      ),
      fixture(
        id: _productionTerminalFixtureId,
        isIncoming: true,
        policy: const PrivateMediaPolicy.viewOnce(),
        state: PrivateMediaLifecycleState.consumed,
        receivedAtMs: 1_752_307_200_000,
        revealedAtMs: 1_752_307_200_010,
        terminalAtMs: 1_752_307_200_020,
        highWaterMs: 1_752_307_200_020,
      ),
    ];

    database = await _openProofDatabase(databasePath);
    for (final message in durableFixtures) {
      await dbInsertMessage(database, message.toMap());
    }
    await database.close();
    database = await _openProofDatabase(databasePath);

    Future<ConversationMessage> reload(String id) async {
      final row = await dbLoadMessage(database!, id);
      expect(row, isNotNull);
      return ConversationMessage.fromMap(row!);
    }

    final persistedOutgoing = await reload(_productionOutgoingFixtureId);
    final persistedIncoming = await reload(_productionIncomingFixtureId);
    final persistedTerminal = await reload(_productionTerminalFixtureId);

    const bytes = _JourneyDownloadBridge.mediaBytes;
    final contentHash = sha256.convert(bytes).toString();
    Future<MediaAttachment> createAttachment(String messageId) async {
      final path = p.join(tempRoot.path, '$messageId.png');
      await File(path).writeAsBytes(bytes, flush: true);
      return MediaAttachment(
        id: '$messageId-attachment',
        messageId: messageId,
        mime: 'image/png',
        size: bytes.length,
        mediaType: 'image',
        localPath: path,
        downloadStatus: 'done',
        contentHash: contentHash,
        createdAt: '2026-07-19T10:00:00.000Z',
        ownerLane: MediaOwnerLane.direct,
      );
    }

    final outgoingAttachment = await createAttachment(
      _productionOutgoingFixtureId,
    );
    final incomingAttachment = await createAttachment(
      _productionIncomingFixtureId,
    );
    final terminalAttachment = await createAttachment(
      _productionTerminalFixtureId,
    );
    final parentById = <String, ConversationMessage>{
      persistedOutgoing.id: persistedOutgoing,
      persistedIncoming.id: persistedIncoming,
      persistedTerminal.id: persistedTerminal,
    };
    final attachmentById = <String, MediaAttachment>{
      persistedOutgoing.id: outgoingAttachment,
      persistedIncoming.id: incomingAttachment,
      persistedTerminal.id: terminalAttachment,
    };

    List<ConversationMessage> projection({
      required bool terminalAttachmentDeleted,
    }) => <ConversationMessage>[
      persistedOutgoing.copyWith(media: <MediaAttachment>[outgoingAttachment]),
      persistedIncoming.copyWith(media: <MediaAttachment>[incomingAttachment]),
      persistedTerminal.copyWith(
        media: terminalAttachmentDeleted
            ? const <MediaAttachment>[]
            : <MediaAttachment>[terminalAttachment],
      ),
    ];

    Future<void> pumpConversation(List<ConversationMessage> messages) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ConversationScreen(
              contactPeerId: 'p260-production-contact',
              contactUsername: 'Recipient',
              connectionDate: 'July 19, 2026',
              ownPeerId: 'p260-production-own-peer',
              messages: messages,
              onSend: (_) {},
              onBack: () {},
              initialLoadDone: true,
              hasMoreOlderMessages: false,
              onReactionSelected: (_, _) {},
              onQuoteReply: (_) {},
              onDeleteMessage: (_) {},
              onOpenPrivateMedia: (_) async {},
              onLoadPrivateParentDecision: (messageId) async {
                final attachment = attachmentById[messageId];
                return DirectPrivateMediaActionEligibility.evaluate(
                  parent: parentById[messageId],
                  attachment: messageId == _productionTerminalFixtureId
                      ? null
                      : attachment,
                  expectedMessageId: messageId,
                  expectedAttachmentId:
                      messageId == _productionTerminalFixtureId
                      ? null
                      : attachment?.id,
                  attachmentRequired: messageId != _productionTerminalFixtureId,
                  requireIncoming: false,
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    await pumpConversation(projection(terminalAttachmentDeleted: false));
    expect(find.byType(ConversationScreen), findsOneWidget);
    expect(find.byType(LetterCard), findsNWidgets(3));

    await File(terminalAttachment.localPath!).delete();
    attachmentById.remove(_productionTerminalFixtureId);
    await pumpConversation(projection(terminalAttachmentDeleted: true));

    const fixtureIds = <String>[
      _productionOutgoingFixtureId,
      _productionIncomingFixtureId,
      _productionTerminalFixtureId,
    ];
    var privateSlotCount = 0;
    var slotsInsideDecoratedBodies = 0;
    var nonZeroPrivateSlotCount = 0;
    var slotImageWidgetCount = 0;
    var slotDecorationImageCount = 0;

    Finder scopedSlot(String messageId) => find.descendant(
      of: find.byKey(ValueKey('msg-$messageId')),
      matching: find.byKey(ValueKey('private-media-slot-$messageId')),
    );

    for (final messageId in fixtureIds) {
      final row = find.byKey(ValueKey('msg-$messageId'));
      final letterCard = find.descendant(
        of: row,
        matching: find.byType(LetterCard),
      );
      final slot = scopedSlot(messageId);
      final decoratedBody = find.descendant(
        of: row,
        matching: find.byKey(
          ValueKey('private-media-decorated-body-$messageId'),
        ),
      );
      final slotInDecoratedBody = find.descendant(
        of: decoratedBody,
        matching: find.byKey(ValueKey('private-media-slot-$messageId')),
      );

      expect(row, findsOneWidget);
      expect(letterCard, findsOneWidget);
      expect(slot, findsOneWidget);
      expect(decoratedBody, findsOneWidget);
      expect(slotInDecoratedBody, findsOneWidget);
      privateSlotCount += slot.evaluate().length;
      slotsInsideDecoratedBodies += slotInDecoratedBody.evaluate().length;

      final slotSize = tester.getSize(slot);
      if (slotSize.width > 0 && slotSize.height > 0) {
        nonZeroPrivateSlotCount += 1;
      }
      expect(slotSize.width, greaterThan(0));
      expect(slotSize.height, greaterThan(0));

      final imageCount = find
          .descendant(of: slot, matching: find.byType(Image))
          .evaluate()
          .length;
      final rawImageCount = find
          .descendant(of: slot, matching: find.byType(RawImage))
          .evaluate()
          .length;
      final mediaGridCount = find
          .descendant(of: slot, matching: find.byType(MediaGrid))
          .evaluate()
          .length;
      slotImageWidgetCount += imageCount + rawImageCount + mediaGridCount;
      expect(imageCount, 0);
      expect(rawImageCount, 0);
      expect(mediaGridCount, 0);

      final containers = find
          .descendant(of: slot, matching: find.byType(Container))
          .evaluate();
      for (final element in containers) {
        final container = element.widget as Container;
        final decorations = <Decoration?>[
          container.decoration,
          container.foregroundDecoration,
        ];
        for (final decoration in decorations) {
          if (decoration is BoxDecoration && decoration.image != null) {
            slotDecorationImageCount += 1;
          }
        }
      }
    }

    bool visibleAction(String messageId, String actionKey) {
      final action = find.descendant(
        of: scopedSlot(messageId),
        matching: find.byKey(ValueKey(actionKey)),
      );
      if (action.evaluate().length != 1) return false;
      final size = tester.getSize(action);
      return size.width > 0 && size.height > 0;
    }

    final productionConversationMounted =
        find.byType(ConversationScreen).evaluate().length == 1;
    final productionLetterCardCount = find.byType(LetterCard).evaluate().length;
    final outgoingActionVisible = visibleAction(
      _productionOutgoingFixtureId,
      'private-media-open',
    );
    final incomingTile = find.descendant(
      of: scopedSlot(_productionIncomingFixtureId),
      matching: find.byKey(const ValueKey('private-media-card-visual')),
    );
    final incomingRetiredButton = find.descendant(
      of: scopedSlot(_productionIncomingFixtureId),
      matching: find.byKey(const ValueKey('private-media-open')),
    );
    expect(incomingTile, findsOneWidget);
    final incomingTileSize = tester.getSize(incomingTile);
    expect(incomingTileSize.height, 150);
    expect(incomingRetiredButton, findsNothing);
    final incomingActionVisible =
        incomingTileSize.width > 0 && incomingTileSize.height > 0;
    final terminalActionVisibleAfterRepump = visibleAction(
      _productionTerminalFixtureId,
      'private-action-deleteForMe',
    );

    expect(productionConversationMounted, isTrue);
    expect(productionLetterCardCount, 3);
    expect(privateSlotCount, 3);
    expect(slotsInsideDecoratedBodies, 3);
    expect(nonZeroPrivateSlotCount, 3);
    expect(slotImageWidgetCount, 0);
    expect(slotDecorationImageCount, 0);
    expect(outgoingActionVisible, isTrue);
    expect(incomingActionVisible, isTrue);
    expect(terminalActionVisibleAfterRepump, isTrue);

    return <String, Object?>{
      'productionConversationMounted': productionConversationMounted,
      'productionLetterCardCount': productionLetterCardCount,
      'privateSlotCount': privateSlotCount,
      'slotsInsideDecoratedBodies': slotsInsideDecoratedBodies,
      'nonZeroPrivateSlotCount': nonZeroPrivateSlotCount,
      'slotImageWidgetCount': slotImageWidgetCount,
      'slotDecorationImageCount': slotDecorationImageCount,
      'outgoingActionVisible': outgoingActionVisible,
      'incomingActionVisible': incomingActionVisible,
      'terminalActionVisibleAfterRepump': terminalActionVisibleAfterRepump,
    };
  } finally {
    if (database != null && database.isOpen) {
      await database.close();
    }
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  }
}

Future<Map<String, Object?>> _runSenderProof(
  WidgetTester tester,
  Map<String, Object?> productionConversation,
) async {
  final privatePayload = _privatePayload(
    id: _correlatedPrivateMessageId,
    policy: const PrivateMediaPolicy.viewOnce(),
  );
  final innerJson = privatePayload.toInnerJson();
  final fixtureDigest = sha256.convert(utf8.encode(innerJson)).toString();
  final inner = jsonDecode(innerJson) as Map<String, dynamic>;
  // Existing crypto suites prove encryption. This local harness binds the v2
  // envelope projection and recipient fixture without retaining inner bytes.
  final envelopeString = MessagePayload.buildEncryptedEnvelope(
    id: privatePayload.id,
    senderPeerId: privatePayload.senderPeerId,
    senderUsername: privatePayload.senderUsername,
    kem: 'opaque-kem',
    ciphertext: fixtureDigest,
    nonce: 'opaque-nonce',
  );
  final envelope = MessagePayload.parseEncryptedEnvelope(envelopeString);
  final ordinaryInner =
      jsonDecode(
            _privatePayload(
              id: 'p234-ordinary-sender',
              policy: const PrivateMediaPolicy.ordinary(),
            ).toInnerJson(),
          )
          as Map<String, dynamic>;

  expect(envelope, isNotNull);
  expect(envelope!['version'], '2');
  expect(envelope.containsKey('privateMedia'), isFalse);
  expect(
    (envelope['encrypted'] as Map<String, dynamic>)['ciphertext'],
    fixtureDigest,
  );
  expect(inner['privateMedia'], {'version': 1, 'mode': 'view_once'});
  expect(ordinaryInner.containsKey('privateMedia'), isFalse);

  final pendingOpen = await _runSenderPendingOpenProof(tester);

  return <String, Object?>{
    'role': 'sender',
    'deviceId': _deviceId,
    'observationSource': 'instrumented_app',
    'observations': <String, Object?>{
      'fixtureDigest': fixtureDigest,
      'encryptedEnvelopeCodec': 'encrypted-v2',
      'outerPrivateMediaPresent': envelope.containsKey('privateMedia'),
      'innerPrivateMediaPresent': inner.containsKey('privateMedia'),
      'ordinarySendPreserved': !ordinaryInner.containsKey('privateMedia'),
      ...pendingOpen,
      ...productionConversation,
    },
  };
}

Future<Map<String, Object?>> _runSenderPendingOpenProof(
  WidgetTester tester,
) async {
  final tempRoot = await Directory.systemTemp.createTemp(
    'p262-sender-pending-open-',
  );
  final databasePath = p.join(tempRoot.path, 'sender-pending-open.db');
  final mediaFileManager = MediaFileManager();
  final proofSequence = <String>[];
  final sqlStateSequence = <String>[];
  final protectionEvents = StreamController<Object?>();
  sqlcipher.Database? database;
  DirectPrivateMediaViewerController? controller;
  String? pendingStoredPath;
  String? pendingAbsolutePath;
  var openTapCount = 0;
  try {
    final source = File(p.join(tempRoot.path, 'fixture.png'));
    await source.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
        '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
      flush: true,
    );
    expect(await source.length(), greaterThan(0));

    pendingStoredPath = await mediaFileManager.copyToDurableStorage(
      sourceFilePath: source.path,
      messageId: _pendingOpenFixtureId,
      attachmentId: _pendingOpenAttachmentId,
      mime: 'image/png',
    );
    pendingAbsolutePath = await mediaFileManager.resolveStoredPath(
      pendingStoredPath,
    );
    final pendingRoot = p.normalize(
      await mediaFileManager.trustedPendingUploadRootPath(),
    );
    MediaFileManager.cacheDocumentsDir(p.dirname(pendingRoot));
    expect(
      p.normalize(pendingAbsolutePath),
      p.join(
        pendingRoot,
        _pendingOpenFixtureId,
        '$_pendingOpenAttachmentId.png',
      ),
    );
    expect(await File(pendingAbsolutePath).length(), await source.length());

    final parent = ConversationMessage(
      id: _pendingOpenFixtureId,
      contactPeerId: 'p262-contact',
      senderPeerId: 'p262-own-peer',
      text: '',
      timestamp: '2026-07-20T10:00:00.000Z',
      status: 'sent',
      isIncoming: false,
      createdAt: '2026-07-20T10:00:00.000Z',
      transport: 'direct',
      privateMediaPolicy: const PrivateMediaPolicy.protected(),
      privateMediaState: PrivateMediaLifecycleState.available,
    );
    final attachment = MediaAttachment(
      id: _pendingOpenAttachmentId,
      messageId: parent.id,
      mime: 'image/png',
      size: await source.length(),
      mediaType: 'image',
      localPath: pendingStoredPath,
      downloadStatus: 'upload_pending',
      createdAt: '2026-07-20T10:00:00.000Z',
      ownerLane: MediaOwnerLane.direct,
    );

    database = await _openProofDatabase(databasePath);
    await dbInsertMessage(database, parent.toMap());
    // Fixture-only raw SQL seed: the production guarded helper is
    // intentionally incoming-only. The exact row is asserted before the
    // in-memory repository mirror is populated.
    await dbInsertMediaAttachment(database, attachment.toMap());

    final exactParent = await database.query(
      'messages',
      columns: const <String>['id'],
      where:
          'id = ? AND is_incoming = 0 '
          'AND private_media_policy_version = 1 '
          "AND private_media_mode = 'protected' "
          "AND private_media_state = 'available'",
      whereArgs: const <Object?>[_pendingOpenFixtureId],
    );
    expect(exactParent, hasLength(1));
    final exactPending = await database.query(
      'media_attachments',
      columns: const <String>['id'],
      where:
          'id = ? AND message_id = ? AND owner_lane = ? '
          'AND local_path = ? AND download_status = ? AND size = ?',
      whereArgs: <Object?>[
        attachment.id,
        parent.id,
        MediaOwnerLane.direct.dbValue,
        pendingStoredPath,
        'upload_pending',
        attachment.size,
      ],
    );
    expect(exactPending, hasLength(1));

    Future<String> readExactSqlState(String expected) async {
      final rows = await database!.query(
        'messages',
        columns: const <String>['private_media_state'],
        where:
            'id = ? AND is_incoming = 0 '
            'AND private_media_policy_version = 1 '
            "AND private_media_mode = 'protected'",
        whereArgs: const <Object?>[_pendingOpenFixtureId],
        limit: 1,
      );
      expect(rows, hasLength(1));
      final state = rows.single['private_media_state'];
      expect(state, expected);
      return state! as String;
    }

    sqlStateSequence.add(await readExactSqlState('available'));
    proofSequence.add('pending_sql_authority_verified');

    final attachmentRepository = _JourneyMediaAttachmentRepository(
      currentDatabase: () {
        final current = database;
        if (current == null || !current.isOpen) {
          throw StateError('p262 sender database is not open');
        }
        return current;
      },
    );
    expect(
      await attachmentRepository.getAttachmentsForMessage(
        parent.id,
        owner: MediaOwnerLane.direct,
      ),
      isEmpty,
    );
    attachmentRepository.seedAttachment(attachment);
    proofSequence.add('repository_mirror_seeded');

    final lifecycleRepository = _SqlLifecycleRepository(database);
    final lifecycle = DirectPrivateMediaLifecycle(
      messageRepository: lifecycleRepository,
      mediaAttachmentRepository: attachmentRepository,
      mediaFileManager: mediaFileManager,
    );
    var lifecycleNowMs = 1_753_003_200_000;
    final lifecycleEngine = PrivateMediaLifecycleEngine(
      adapter: lifecycle,
      lifecycleLock: attachmentRepository.directPrivateMediaLifecycleLock,
      nowMs: () => lifecycleNowMs++,
    );
    final protectionCoordinator = PrivateMediaProtectionCoordinator(
      invokeMethod: (method, arguments) async => <String, Object?>{
        'ok': true,
        'protectionActive': method == 'enter',
      },
      nativeEvents: protectionEvents.stream,
    );
    controller = DirectPrivateMediaViewerController(
      loadCurrentRows: (identity) async {
        if (identity.messageId != parent.id ||
            identity.attachmentId != attachment.id) {
          return const DirectPrivateMediaCurrentRows(
            parent: null,
            attachment: null,
          );
        }
        final parentRow = await dbLoadMessage(database!, parent.id);
        final attachments = await attachmentRepository.getAttachmentsForMessage(
          parent.id,
          owner: MediaOwnerLane.direct,
        );
        return DirectPrivateMediaCurrentRows(
          parent: parentRow == null
              ? null
              : ConversationMessage.fromMap(parentRow),
          attachment: attachments.length == 1 ? attachments.single : null,
        );
      },
      lifecycleEngine: lifecycleEngine,
      protectionCoordinator: protectionCoordinator,
    );

    final navigatorKey = GlobalKey<NavigatorState>();
    final launchCompleted = Completer<void>();
    DirectPrivateMediaOpenResult? launchedResult;
    var launchPhase = 'not_started';
    String? launchFailureType;
    Future<DirectPrivateMediaOpenResult> launchViewer(
      DirectPrivateMediaViewerIdentity identity,
      DirectPrivateMediaContinuityGuard continuityGuard,
    ) async {
      openTapCount += 1;
      proofSequence.add('open_tapped');
      try {
        launchPhase = 'prepare';
        final activeController = controller!;
        final prepared = await activeController.prepareResult(
          identity,
          continuityGuard,
        );
        final grant = prepared.grant;
        if (grant == null) {
          throw StateError('p262 sender pending open was refused');
        }
        sqlStateSequence.add(await readExactSqlState('opening'));
        proofSequence.add('opening_sql_observed');

        final route = MaterialPageRoute<void>(
          builder: (_) => DirectPrivateMediaViewer(
            grant: grant,
            controller: activeController,
          ),
        );
        late final DirectPrivateMediaSettleResult settled;
        try {
          launchPhase = 'route_push';
          await navigatorKey.currentState!.push<void>(route);
          launchPhase = 'route_completed';
          await route.completed;
        } finally {
          // The viewer starts settlement before its route completes. Calling
          // the idempotent controller seam again is required to await that
          // in-flight operation; `grant.settled` becomes true at operation
          // start and does not itself mean `settleResult` is published yet.
          launchPhase = 'settle';
          settled = await activeController.settle(
            grant,
            DirectPrivateMediaExitReason.close,
            releaseProtection: false,
          );
          launchPhase = 'release_protection';
          await activeController.releaseProtectionOwner(grant);
        }
        launchPhase = 'result';
        launchedResult = DirectPrivateMediaOpenResult.displayed(settled);
        launchPhase = 'complete';
        return launchedResult!;
      } on Object catch (error) {
        launchFailureType = error.runtimeType.toString();
        rethrow;
      } finally {
        if (!launchCompleted.isCompleted) launchCompleted.complete();
      }
    }

    Future<DirectPrivateMediaActionDecision> loadDecision(
      String messageId,
    ) async {
      final row = await dbLoadMessage(database!, messageId);
      final currentParent = row == null
          ? null
          : ConversationMessage.fromMap(row);
      final attachments = await attachmentRepository.getAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.direct,
      );
      return DirectPrivateMediaActionEligibility.evaluate(
        parent: currentParent,
        attachment: attachments.length == 1 ? attachments.single : null,
        expectedMessageId: messageId,
        expectedAttachmentId: attachment.id,
        requireIncoming: false,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ConversationScreen(
            contactPeerId: parent.contactPeerId,
            contactUsername: 'Recipient',
            connectionDate: 'July 20, 2026',
            ownPeerId: parent.senderPeerId,
            messages: <ConversationMessage>[
              parent.copyWith(media: <MediaAttachment>[attachment]),
            ],
            onSend: (_) {},
            onBack: () {},
            initialLoadDone: true,
            hasMoreOlderMessages: false,
            onReactionSelected: (_, _) {},
            onQuoteReply: (_) {},
            onDeleteMessage: (_) {},
            onOpenPrivateMediaResult: launchViewer,
            onLoadPrivateParentDecision: loadDecision,
          ),
        ),
      ),
    );

    final messageRow = find.byKey(const ValueKey('msg-$_pendingOpenFixtureId'));
    final scopedOpen = find.descendant(
      of: messageRow,
      matching: find.byKey(const ValueKey('private-media-open')),
    );
    for (
      var attempt = 0;
      attempt < 80 && scopedOpen.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(messageRow, findsOneWidget);
    expect(scopedOpen, findsOneWidget);
    await tester.tap(scopedOpen);

    final viewer = find.byType(DirectPrivateMediaViewer);
    var viewingObserved = false;
    for (var attempt = 0; attempt < 120; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      final rows = await database.query(
        'messages',
        columns: const <String>['private_media_state'],
        where: 'id = ?',
        whereArgs: const <Object?>[_pendingOpenFixtureId],
        limit: 1,
      );
      viewingObserved =
          viewer.evaluate().length == 1 &&
          rows.length == 1 &&
          rows.single['private_media_state'] == 'viewing';
      if (viewingObserved) break;
    }
    expect(viewingObserved, isTrue);
    expect(
      find.byKey(const ValueKey('direct-private-media-viewer')),
      findsOneWidget,
    );
    proofSequence.add('viewer_first_frame');
    sqlStateSequence.add(await readExactSqlState('viewing'));
    proofSequence.add('viewing_sql_observed');

    final viewerBack = find.descendant(
      of: viewer,
      matching: find.byIcon(Icons.arrow_back),
    );
    expect(viewerBack, findsOneWidget);
    await tester.tap(viewerBack);
    proofSequence.add('viewer_back_tapped');

    for (var attempt = 0; attempt < 120; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (viewer.evaluate().isEmpty && launchCompleted.isCompleted) break;
    }
    await launchCompleted.future;
    expect(viewer, findsNothing);
    expect(find.byType(ConversationScreen), findsOneWidget);
    expect(
      launchFailureType,
      isNull,
      reason: 'pending viewer launch failed at $launchPhase',
    );
    expect(launchedResult?.wasDisplayed, isTrue);
    proofSequence.add('conversation_route_resumed');

    sqlStateSequence.add(await readExactSqlState('consumed'));
    proofSequence.add('consumed_sql_observed');
    final rowsAfterCleanup = await database.query(
      'media_attachments',
      columns: const <String>['id'],
      where: 'id = ? AND message_id = ? AND owner_lane = ?',
      whereArgs: <Object?>[
        attachment.id,
        parent.id,
        MediaOwnerLane.direct.dbValue,
      ],
    );
    expect(rowsAfterCleanup, isEmpty);
    expect(
      await attachmentRepository.getAttachmentsForMessage(
        parent.id,
        owner: MediaOwnerLane.direct,
      ),
      isEmpty,
    );
    proofSequence.add('attachment_cleanup_observed');
    expect(await File(pendingAbsolutePath).exists(), isFalse);
    proofSequence.add('pending_source_cleanup_observed');

    expect(openTapCount, 1);
    expect(sqlStateSequence, _pendingOpenSqlStateSequence);
    expect(proofSequence, _pendingOpenProofSequence);
    return <String, Object?>{
      'pendingOpenTapCount': openTapCount,
      'pendingOpenSqlStateSequence': sqlStateSequence,
      'pendingOpenProofSequence': proofSequence,
    };
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    if (controller != null) await controller.dispose();
    await protectionEvents.close();
    if (database != null && database.isOpen) await database.close();
    if (pendingStoredPath != null) {
      await mediaFileManager.deleteOwnedPendingUploadFilesForMessage(
        messageId: _pendingOpenFixtureId,
        storedPaths: <String?>[pendingStoredPath],
      );
    }
    if (pendingAbsolutePath != null &&
        await File(pendingAbsolutePath).exists()) {
      await File(pendingAbsolutePath).delete();
    }
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  }
}

Future<Map<String, Object?>> _runRecipientProof(
  Map<String, Object?> productionConversation,
) async {
  var sequence = 0;
  var phase = 'setup';
  final tempRoot = await Directory.systemTemp.createTemp('p234-device-local-');
  final databasePath = p.join(tempRoot.path, 'journey.db');
  final mediaFileManager = MediaFileManager();
  sqlcipher.Database? database;
  final attachmentRepository = _JourneyMediaAttachmentRepository(
    currentDatabase: () {
      final current = database;
      if (current == null || !current.isOpen) {
        throw StateError('journey attachment database is not open');
      }
      return current;
    },
  );
  final downloadBridge = _JourneyDownloadBridge();
  final cleanupPaths = <String>{};
  try {
    final fixturePayload = _privatePayload(
      id: _correlatedPrivateMessageId,
      policy: const PrivateMediaPolicy.viewOnce(),
    );
    final innerJson = fixturePayload.toInnerJson();
    final fixtureDigest = sha256.convert(utf8.encode(innerJson)).toString();
    final decoded = MessagePayload.fromDecryptedJson(innerJson);
    expect(decoded, isNotNull);

    const receivedAtMs = 1_752_307_200_000;
    final durableInput = decoded!
        .toConversationMessage(
          contactPeerId: 'peer-sender',
          isIncoming: true,
          transport: 'direct',
        )
        .copyWith(
          privateMediaReceivedAtMs: receivedAtMs,
          privateMediaClockHighWaterMs: receivedAtMs,
        );
    phase = 'initial_sqlcipher_open';
    database = await _openProofDatabase(databasePath);
    phase = 'initial_parent_commit';
    await dbInsertMessage(database, durableInput.toMap());
    await database.close();
    phase = 'durable_parent_reopen';
    database = await _openProofDatabase(databasePath);
    phase = 'durable_parent_hydrate';
    final persistedRow = await dbLoadMessage(database, durableInput.id);
    expect(persistedRow, isNotNull);
    final persisted = ConversationMessage.fromMap(persistedRow!);
    final persistedSequence = ++sequence;
    final privatePayloadPersisted =
        persisted.privateMediaPolicy.mode == PrivateMediaMode.viewOnce &&
        persisted.privateMediaState == PrivateMediaLifecycleState.available &&
        persisted.privateMediaReceivedAtMs == receivedAtMs;

    final privateAttachment = _attachment(
      id: _correlatedPrivateAttachmentId,
      messageId: persisted.id,
      downloadStatus: 'pending',
    );
    await attachmentRepository.seedDurableAttachment(
      privateAttachment,
      nowMs: receivedAtMs,
    );
    final downloadMessageRepository = InMemoryMessageRepository();
    await downloadMessageRepository.saveMessage(persisted);
    final currentDecision = DirectPrivateMediaActionEligibility.evaluate(
      parent: persisted,
      attachment: privateAttachment,
      expectedMessageId: persisted.id,
      expectedAttachmentId: privateAttachment.id,
    );
    final policySequence = ++sequence;
    final privatePolicyApplied =
        currentDecision.requiresPrivacyMinimizedPresentation &&
        currentDecision.safeReplyText == 'Private media' &&
        !currentDecision.allows(DirectPrivateMediaAction.externalShare) &&
        !currentDecision.canEnterPictureInPicture;
    final privateEgressDenied = const <DirectPrivateMediaAction>[
      DirectPrivateMediaAction.saveToPhotos,
      DirectPrivateMediaAction.saveToFiles,
      DirectPrivateMediaAction.externalShare,
      DirectPrivateMediaAction.internalForward,
      DirectPrivateMediaAction.bookmark,
      DirectPrivateMediaAction.sharedMedia,
    ].every((action) => !currentDecision.allows(action));
    final legacyOrdinaryViewerEntryDenied =
        currentDecision.requiresPrivacyMinimizedPresentation;
    final typedPictureInPictureDenied =
        !currentDecision.canEnterPictureInPicture;

    final notificationCopy = notificationBodyForMessage(
      _privateFixtureText,
      <MediaAttachment>[privateAttachment],
      privateMediaPolicy: persisted.privateMediaPolicy,
      locale: const Locale('en'),
    );
    final previewSequence = ++sequence;

    final autoDownloadCount = downloadBridge.commandLog
        .where((command) => command == 'media:download')
        .length;
    final manualDownloadAllowed = currentDecision.allows(
      DirectPrivateMediaAction.explicitDownload,
    );
    final privateCanonicalPath = await mediaFileManager.localPathForAttachment(
      contactPeerId: persisted.contactPeerId,
      blobId: privateAttachment.id,
      mime: privateAttachment.mime,
    );
    cleanupPaths.add(privateCanonicalPath);
    final privateRelativePath = mediaFileManager.relativePathForAttachment(
      contactPeerId: persisted.contactPeerId,
      blobId: privateAttachment.id,
      mime: privateAttachment.mime,
    );
    MediaAttachment? privateDownload;
    var manualDownloadResult = 'denied';
    if (manualDownloadAllowed) {
      phase = 'private_explicit_download';
      privateDownload = await downloadMedia(
        bridge: downloadBridge,
        mediaAttachmentRepo: attachmentRepository,
        mediaFileManager: mediaFileManager,
        attachment: privateAttachment,
        contactPeerId: persisted.contactPeerId,
        owner: MediaOwnerLane.direct,
        messageRepo: downloadMessageRepository,
        intent: MediaDownloadIntent.explicitUser,
        nowMs: () => receivedAtMs + 1,
      );
      final persistedAttachment =
          (await attachmentRepository.getAttachmentsForMessage(
            persisted.id,
            owner: MediaOwnerLane.direct,
          )).single;
      final canonical =
          privateDownload?.localPath == privateCanonicalPath &&
          persistedAttachment.localPath == privateRelativePath &&
          await File(privateCanonicalPath).exists() &&
          await File(privateCanonicalPath).length() == privateAttachment.size;
      if (canonical) {
        manualDownloadResult = 'canonical_durable_storage';
      }
    }
    final manualDownloadCount = downloadBridge.commandLog
        .where((command) => command == 'media:download')
        .length;
    final downloadSequence = ++sequence;

    phase = 'exact_sql_attachment_ready';
    final exactDurableAttachment = await database.query(
      'media_attachments',
      columns: const <String>['id'],
      where:
          'id = ? AND message_id = ? AND owner_lane = ? '
          'AND download_status = ? AND local_path = ?',
      whereArgs: <Object?>[
        privateAttachment.id,
        persisted.id,
        MediaOwnerLane.direct.dbValue,
        'done',
        privateRelativePath,
      ],
    );
    expect(exactDurableAttachment, hasLength(1));

    phase = 'view_once_lifecycle';
    final viewOnceLifecycle = DirectPrivateMediaLifecycle(
      messageRepository: _SqlLifecycleRepository(database),
      mediaAttachmentRepository: attachmentRepository,
      mediaFileManager: mediaFileManager,
    );
    final viewOnceEngine = PrivateMediaLifecycleEngine(
      adapter: viewOnceLifecycle,
      lifecycleLock: attachmentRepository.directPrivateMediaLifecycleLock,
      nowMs: () => receivedAtMs + 10,
    );
    final lease = await viewOnceEngine.openViewOnce(persisted.id);
    expect(lease, isNotNull);
    final firstFrame = await viewOnceEngine.markFirstFrame(lease!);
    final consumed = await viewOnceEngine.terminalizeViewOnce(lease);
    final consumedParent = ConversationMessage.fromMap(
      (await dbLoadMessage(database, persisted.id))!,
    );
    final viewOnceRevealCount =
        consumedParent.privateMediaRevealedAtMs == receivedAtMs + 10 ? 1 : 0;
    final viewOnceCleanupCompleted =
        firstFrame &&
        consumed &&
        consumedParent.privateMediaState ==
            PrivateMediaLifecycleState.consumed &&
        !await File(privateCanonicalPath).exists();
    phase = 'exact_sql_attachment_cleaned';
    final exactDurableAttachmentAfterCleanup = await database.query(
      'media_attachments',
      columns: const <String>['id'],
      where: 'id = ? AND message_id = ? AND owner_lane = ?',
      whereArgs: <Object?>[
        privateAttachment.id,
        persisted.id,
        MediaOwnerLane.direct.dbValue,
      ],
    );
    expect(exactDurableAttachmentAfterCleanup, isEmpty);
    final viewOnceAttachmentPresentAfterCleanup =
        (await attachmentRepository.getAttachmentsForMessage(
          persisted.id,
          owner: MediaOwnerLane.direct,
        )).isNotEmpty ||
        exactDurableAttachmentAfterCleanup.isNotEmpty;
    await database.close();
    phase = 'terminal_parent_reopen';
    database = await _openProofDatabase(databasePath);
    final reopenedViewOnceEngine = PrivateMediaLifecycleEngine(
      adapter: DirectPrivateMediaLifecycle(
        messageRepository: _SqlLifecycleRepository(database),
        mediaAttachmentRepository: attachmentRepository,
        mediaFileManager: mediaFileManager,
      ),
      lifecycleLock: attachmentRepository.directPrivateMediaLifecycleLock,
      nowMs: () => receivedAtMs + 20,
    );
    final reopenedLease = await reopenedViewOnceEngine.openViewOnce(
      persisted.id,
    );
    final reopenedParent = ConversationMessage.fromMap(
      (await dbLoadMessage(database, persisted.id))!,
    );
    final viewOnceAvailableAfterReopen =
        reopenedLease != null ||
        reopenedParent.privateMediaState ==
            PrivateMediaLifecycleState.available ||
        await File(privateCanonicalPath).exists();

    phase = 'disappearing_expiry';
    final disappearingParent = _incomingParent(
      id: 'p234-disappearing',
      policy: PrivateMediaPolicy.disappearing(3600),
      state: PrivateMediaLifecycleState.available,
      receivedAtMs: 1_000,
      expiresAtMs: 3_601_000,
      highWaterMs: 1_000,
    );
    await dbInsertMessage(database, disappearingParent.toMap());
    final disappearingAttachment = _attachment(
      id: 'p234-disappearing-attachment',
      messageId: disappearingParent.id,
      downloadStatus: 'done',
      localPath: mediaFileManager.relativePathForAttachment(
        contactPeerId: disappearingParent.contactPeerId,
        blobId: 'p234-disappearing-attachment',
        mime: 'image/png',
      ),
    );
    final disappearingPath = await mediaFileManager.localPathForAttachment(
      contactPeerId: disappearingParent.contactPeerId,
      blobId: disappearingAttachment.id,
      mime: disappearingAttachment.mime,
    );
    cleanupPaths.add(disappearingPath);
    await File(disappearingPath).parent.create(recursive: true);
    await File(
      disappearingPath,
    ).writeAsBytes(_JourneyDownloadBridge.mediaBytes, flush: true);
    await attachmentRepository.seedDurableAttachment(
      disappearingAttachment,
      nowMs: disappearingParent.privateMediaReceivedAtMs!,
    );
    final disappearingEngine = PrivateMediaLifecycleEngine(
      adapter: DirectPrivateMediaLifecycle(
        messageRepository: _SqlLifecycleRepository(database),
        mediaAttachmentRepository: attachmentRepository,
        mediaFileManager: mediaFileManager,
      ),
      lifecycleLock: attachmentRepository.directPrivateMediaLifecycleLock,
      nowMs: () => 3_601_001,
    );
    final expiry = await disappearingEngine.sweepExpiries();
    final expiredParent = ConversationMessage.fromMap(
      (await dbLoadMessage(database, disappearingParent.id))!,
    );
    final disappearingExpiryCompleted =
        expiry.terminalClaims == 1 &&
        expiry.cleanupCompleted == 1 &&
        expiredParent.privateMediaState == PrivateMediaLifecycleState.expired &&
        !await File(disappearingPath).exists();
    final disappearingAvailableAfterExpiry =
        expiredParent.privateMediaState == PrivateMediaLifecycleState.available;

    phase = 'assert_disappearing_terminal_claim';
    expect(expiry.terminalClaims, 1);
    phase = 'assert_disappearing_cleanup_count';
    expect(expiry.cleanupCompleted, 1);
    phase = 'assert_disappearing_terminal_state';
    expect(expiredParent.privateMediaState, PrivateMediaLifecycleState.expired);
    phase = 'assert_disappearing_file_deleted';
    expect(await File(disappearingPath).exists(), isFalse);

    phase = 'protected_open_decisions';
    final protectedParent = _incomingParent(
      id: 'p234-protected',
      policy: const PrivateMediaPolicy.protected(),
      state: PrivateMediaLifecycleState.available,
      receivedAtMs: receivedAtMs,
      highWaterMs: receivedAtMs,
    );
    final protectedAttachment = _attachment(
      id: 'p234-protected-attachment',
      messageId: protectedParent.id,
      downloadStatus: 'done',
      localPath: mediaFileManager.relativePathForAttachment(
        contactPeerId: protectedParent.contactPeerId,
        blobId: 'p234-protected-attachment',
        mime: 'image/png',
      ),
    );
    final protectedPath = await mediaFileManager.localPathForAttachment(
      contactPeerId: protectedParent.contactPeerId,
      blobId: protectedAttachment.id,
      mime: protectedAttachment.mime,
    );
    cleanupPaths.add(protectedPath);
    await File(protectedPath).parent.create(recursive: true);
    await File(
      protectedPath,
    ).writeAsBytes(_JourneyDownloadBridge.mediaBytes, flush: true);
    final protectedFirst = DirectPrivateMediaActionEligibility.evaluate(
      parent: protectedParent,
      attachment: protectedAttachment,
      expectedMessageId: protectedParent.id,
      expectedAttachmentId: protectedAttachment.id,
    );
    final protectedRepeat = DirectPrivateMediaActionEligibility.evaluate(
      parent: protectedParent,
      attachment: protectedAttachment,
      expectedMessageId: protectedParent.id,
      expectedAttachmentId: protectedAttachment.id,
    );

    phase = 'ordinary_download';
    final ordinaryParent = _incomingParent(
      id: 'p234-ordinary',
      policy: const PrivateMediaPolicy.ordinary(),
      state: PrivateMediaLifecycleState.none,
    );
    final ordinaryAttachment = _attachment(
      id: 'p234-ordinary-attachment',
      messageId: ordinaryParent.id,
      downloadStatus: 'pending',
    );
    final ordinaryDecision = DirectPrivateMediaActionEligibility.evaluate(
      parent: ordinaryParent,
      attachment: ordinaryAttachment,
      expectedMessageId: ordinaryParent.id,
      expectedAttachmentId: ordinaryAttachment.id,
    );
    final ordinaryPreview = notificationBodyForMessage('', <MediaAttachment>[
      ordinaryAttachment,
    ]);
    await downloadMessageRepository.saveMessage(ordinaryParent);
    attachmentRepository.seedAttachment(ordinaryAttachment);
    final ordinaryCanonicalPath = await mediaFileManager.localPathForAttachment(
      contactPeerId: ordinaryParent.contactPeerId,
      blobId: ordinaryAttachment.id,
      mime: ordinaryAttachment.mime,
    );
    cleanupPaths.add(ordinaryCanonicalPath);
    final ordinaryDownload = await downloadMedia(
      bridge: downloadBridge,
      mediaAttachmentRepo: attachmentRepository,
      mediaFileManager: mediaFileManager,
      attachment: ordinaryAttachment,
      contactPeerId: ordinaryParent.contactPeerId,
      owner: MediaOwnerLane.direct,
      messageRepo: downloadMessageRepository,
      intent: MediaDownloadIntent.explicitUser,
      nowMs: () => receivedAtMs + 30,
    );
    final ordinaryManualDownloadSucceeded =
        ordinaryDownload?.localPath == ordinaryCanonicalPath &&
        await File(ordinaryCanonicalPath).exists();
    final consumeReceiptCount = downloadBridge.commandLog
        .where(
          (command) =>
              command.toLowerCase().contains('consume') ||
              command.toLowerCase().contains('receipt'),
        )
        .length;

    phase = 'assert_persistence_and_download';
    expect(privatePayloadPersisted, isTrue);
    expect(privatePolicyApplied, isTrue);
    expect(notificationCopy, 'Private media');
    expect(autoDownloadCount, 0);
    expect(manualDownloadCount, 1);
    expect(manualDownloadResult, 'canonical_durable_storage');
    phase = 'assert_view_once';
    expect(viewOnceRevealCount, 1);
    expect(viewOnceCleanupCompleted, isTrue);
    expect(viewOnceAttachmentPresentAfterCleanup, isFalse);
    expect(viewOnceAvailableAfterReopen, isFalse);
    phase = 'assert_disappearing_expiry';
    expect(disappearingExpiryCompleted, isTrue);
    phase = 'assert_disappearing_unavailable';
    expect(disappearingAvailableAfterExpiry, isFalse);
    phase = 'assert_protected';
    expect(protectedFirst.allows(DirectPrivateMediaAction.openInApp), isTrue);
    expect(protectedRepeat.allows(DirectPrivateMediaAction.openInApp), isTrue);
    expect(
      protectedParent.privateMediaState,
      PrivateMediaLifecycleState.available,
    );
    phase = 'assert_ordinary';
    expect(ordinaryPreview, 'Photo');
    expect(
      ordinaryDecision.allows(DirectPrivateMediaAction.explicitDownload),
      isTrue,
    );
    expect(ordinaryManualDownloadSucceeded, isTrue);
    expect(consumeReceiptCount, 0);

    phase = 'artifact_projection';
    return <String, Object?>{
      'role': 'recipient',
      'deviceId': _deviceId,
      'observationSource': 'instrumented_app',
      'observations': <String, Object?>{
        'fixtureDigest': fixtureDigest,
        'privatePayloadPersisted': privatePayloadPersisted,
        'privatePolicyApplied': privatePolicyApplied,
        'privateEgressDenied': privateEgressDenied,
        'legacyOrdinaryViewerEntryDenied': legacyOrdinaryViewerEntryDenied,
        'typedPictureInPictureDenied': typedPictureInPictureDenied,
        'persistedSequence': persistedSequence,
        'policySequence': policySequence,
        'previewSequence': previewSequence,
        'downloadSequence': downloadSequence,
        'notificationCopy': notificationCopy,
        'quoteCopy': currentDecision.safeReplyText,
        'autoDownloadCount': autoDownloadCount,
        'manualDownloadCount': manualDownloadCount,
        'manualDownloadResult': manualDownloadResult,
        'viewOnceRevealCount': viewOnceRevealCount,
        'viewOnceCleanupCompleted': viewOnceCleanupCompleted,
        'viewOnceAttachmentPresentAfterCleanup':
            viewOnceAttachmentPresentAfterCleanup,
        'viewOnceAvailableAfterReopen': viewOnceAvailableAfterReopen,
        'disappearingExpiryCompleted': disappearingExpiryCompleted,
        'disappearingAvailableAfterExpiry': disappearingAvailableAfterExpiry,
        'protectedFirstOpenDecisionAllowed': protectedFirst.allows(
          DirectPrivateMediaAction.openInApp,
        ),
        'protectedRepeatOpenDecisionAllowed': protectedRepeat.allows(
          DirectPrivateMediaAction.openInApp,
        ),
        'protectedAvailableAfterRepeat':
            protectedParent.privateMediaState ==
            PrivateMediaLifecycleState.available,
        'ordinaryPreviewSucceeded': ordinaryPreview == 'Photo',
        'ordinaryManualDownloadSucceeded': ordinaryManualDownloadSucceeded,
        'consumeReceiptCount': consumeReceiptCount,
        ...productionConversation,
      },
    };
  } on Object catch (error) {
    // This safe diagnostic never includes payload, path, or exception text.
    // The runner withholds raw child output; direct triage can identify the
    // failing production seam without weakening artifact redaction.
    // ignore: avoid_print
    print('P234_RECIPIENT_FAILURE_PHASE=$phase TYPE=${error.runtimeType}');
    rethrow;
  } finally {
    if (database != null && database.isOpen) {
      await database.close();
    }
    for (final path in cleanupPaths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  }
}

Future<sqlcipher.Database> _openProofDatabase(String path) {
  return sqlcipher.openDatabase(
    path,
    password: 'plan-234-session-06-device-local-proof',
    version: 100,
    singleInstance: false,
    onCreate: runProductionOnCreate,
    onUpgrade: runProductionOnUpgrade,
    onDowngrade: sqlcipher.onDatabaseVersionChangeError,
  );
}

MessagePayload _privatePayload({
  required String id,
  required PrivateMediaPolicy policy,
  String text = '',
}) {
  return MessagePayload(
    id: id,
    text: text,
    senderPeerId: 'peer-sender',
    senderUsername: 'Sender',
    timestamp: '2026-07-12T09:00:00.000Z',
    media: <Map<String, dynamic>>[
      <String, dynamic>{
        'id': '$id-attachment',
        'mime': 'image/png',
        'size': 4,
        'mediaType': 'image',
        'createdAt': '2026-07-12T09:00:00.000Z',
      },
    ],
    privateMediaPolicy: policy,
  );
}

ConversationMessage _incomingParent({
  required String id,
  required PrivateMediaPolicy policy,
  required PrivateMediaLifecycleState state,
  int? receivedAtMs,
  int? expiresAtMs,
  int? highWaterMs,
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: 'peer-sender',
    senderPeerId: 'peer-sender',
    text: '',
    timestamp: '2026-07-12T09:00:00.000Z',
    status: 'sent',
    isIncoming: true,
    createdAt: '2026-07-12T09:00:00.000Z',
    privateMediaPolicy: policy,
    privateMediaState: state,
    privateMediaReceivedAtMs: receivedAtMs,
    privateMediaExpiresAtMs: expiresAtMs,
    privateMediaClockHighWaterMs: highWaterMs,
  );
}

MediaAttachment _attachment({
  required String id,
  required String messageId,
  required String downloadStatus,
  String? localPath,
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: 'image/png',
    size: 4,
    mediaType: 'image',
    localPath: localPath,
    downloadStatus: downloadStatus,
    createdAt: '2026-07-12T09:00:00.000Z',
    ownerLane: MediaOwnerLane.direct,
  );
}

class _SqlLifecycleRepository
    implements
        DirectPrivateMediaLifecycleRepository,
        DirectPrivateMediaExactOpeningLeaseRepository {
  const _SqlLifecycleRepository(this.database);

  final sqlcipher.Database database;

  Future<ConversationMessage?> _load(String messageId) async {
    final row = await dbLoadMessage(database, messageId);
    return row == null ? null : ConversationMessage.fromMap(row);
  }

  @override
  Future<ConversationMessage?> loadPrivateMediaLifecycleMessage(
    String messageId,
  ) => _load(messageId);

  @override
  Future<bool> claimPrivateMediaOpening(
    String messageId, {
    required int nowMs,
  }) async =>
      await dbClaimDirectPrivateMediaOpening(
        database,
        messageId,
        nowMs: nowMs,
      ) ==
      1;

  @override
  Future<bool> claimExactPrivateMediaOpening(
    String messageId, {
    required bool isIncoming,
    required PrivateMediaMode mode,
    required String attachmentId,
    required String storedLocalPath,
    required int nowMs,
  }) async =>
      await dbClaimDirectPrivateMediaOpening(
        database,
        messageId,
        nowMs: nowMs,
        isIncoming: isIncoming,
        mode: mode.wireValue,
        attachmentId: attachmentId,
        storedLocalPath: storedLocalPath,
      ) ==
      1;

  @override
  Future<bool> markPrivateMediaViewing(
    String messageId, {
    required int nowMs,
  }) async =>
      await dbMarkDirectPrivateMediaViewing(
        database,
        messageId,
        nowMs: nowMs,
      ) ==
      1;

  @override
  Future<bool> markExactPrivateMediaViewing(
    String messageId, {
    required bool isIncoming,
    required PrivateMediaMode mode,
    required String attachmentId,
    required String storedLocalPath,
    required int nowMs,
  }) async =>
      await dbMarkDirectPrivateMediaViewing(
        database,
        messageId,
        nowMs: nowMs,
        isIncoming: isIncoming,
        mode: mode.wireValue,
        attachmentId: attachmentId,
        storedLocalPath: storedLocalPath,
      ) ==
      1;

  @override
  Future<bool> rollbackPrivateMediaOpening(String messageId) async =>
      await dbRollbackDirectPrivateMediaOpening(database, messageId) == 1;

  @override
  Future<bool> rollbackExactPrivateMediaOpening(
    String messageId, {
    required bool isIncoming,
    required PrivateMediaMode mode,
    required String attachmentId,
    required String storedLocalPath,
  }) async =>
      await dbRollbackDirectPrivateMediaOpening(
        database,
        messageId,
        isIncoming: isIncoming,
        mode: mode.wireValue,
        attachmentId: attachmentId,
        storedLocalPath: storedLocalPath,
      ) ==
      1;

  @override
  Future<bool> consumePrivateMedia(
    String messageId, {
    required int nowMs,
  }) async =>
      await dbConsumeDirectPrivateMedia(database, messageId, nowMs: nowMs) == 1;

  @override
  Future<bool> consumeExactPrivateMedia(
    String messageId, {
    required bool isIncoming,
    required PrivateMediaMode mode,
    required String attachmentId,
    required String storedLocalPath,
    required int nowMs,
  }) async =>
      await dbConsumeDirectPrivateMedia(
        database,
        messageId,
        nowMs: nowMs,
        isIncoming: isIncoming,
        mode: mode.wireValue,
        attachmentId: attachmentId,
        storedLocalPath: storedLocalPath,
      ) ==
      1;

  @override
  Future<bool> advancePrivateMediaClock(
    String messageId, {
    required int nowMs,
  }) async =>
      await dbAdvanceDirectPrivateMediaClock(
        database,
        messageId,
        nowMs: nowMs,
      ) ==
      1;

  @override
  Future<bool> failClosedCorruptPrivateMediaState(
    String messageId, {
    required int nowMs,
  }) async =>
      await dbFailClosedCorruptDirectPrivateMediaState(
        database,
        messageId,
        nowMs: nowMs,
      ) ==
      1;

  @override
  Future<bool> hidePrivateMediaForMe(
    String messageId, {
    required String hiddenAt,
    required int nowMs,
  }) async =>
      await dbHideDirectPrivateMediaForMe(
        database,
        messageId,
        hiddenAt: hiddenAt,
        nowMs: nowMs,
      ) ==
      1;

  @override
  Future<List<ConversationMessage>> loadActiveDisappearingPrivateMedia({
    int limit = 100,
  }) async => (await dbLoadActiveDirectPrivateMediaDisappearing(
    database,
    limit: limit,
  )).map(ConversationMessage.fromMap).toList(growable: false);

  @override
  Future<List<ConversationMessage>> loadPrivateMediaRecoveryCandidates({
    int limit = 100,
  }) async => (await dbLoadDirectPrivateMediaRecoveryCandidates(
    database,
    limit: limit,
  )).map(ConversationMessage.fromMap).toList(growable: false);

  @override
  Future<bool> rotatePrivateMediaRecoveryCandidate(
    String messageId, {
    required int nowMs,
  }) async =>
      await dbRotateDirectPrivateMediaRecoveryCandidate(
        database,
        messageId,
        nowMs: nowMs,
      ) ==
      1;

  @override
  Future<int?> loadNextPrivateMediaExpiryAtMs() =>
      dbLoadNextDirectPrivateMediaExpiryAtMs(database);
}

class _JourneyDownloadBridge extends FakeBridge {
  static const List<int> mediaBytes = <int>[7, 11, 23, 47];

  @override
  Future<String> send(String message) async {
    final decoded = jsonDecode(message) as Map<String, dynamic>;
    if (decoded['cmd'] == 'media:download') {
      final payload = decoded['payload'] as Map<String, dynamic>;
      final output = File(payload['outputPath'] as String);
      await output.parent.create(recursive: true);
      await output.writeAsBytes(mediaBytes, flush: true);
    }
    return super.send(message);
  }
}

class _JourneyMediaAttachmentRepository
    implements
        MediaAttachmentRepository,
        DirectPrivateMediaDownloadStateRepository,
        DirectPrivateMediaCleanupRepository,
        DirectPrivateMediaCleanupRuntime {
  _JourneyMediaAttachmentRepository({required this.currentDatabase});

  final sqlcipher.Database Function() currentDatabase;
  final Map<String, List<MediaAttachment>> _byMessage =
      <String, List<MediaAttachment>>{};
  final MediaAttachmentLifecycleLock _lock = MediaAttachmentLifecycleLock();

  @override
  MediaAttachmentLifecycleLock get directPrivateMediaLifecycleLock => _lock;

  void seedAttachment(MediaAttachment attachment) {
    final rows = _byMessage.putIfAbsent(
      attachment.messageId,
      () => <MediaAttachment>[],
    );
    rows.removeWhere((row) => row.id == attachment.id);
    rows.add(attachment);
  }

  Future<void> seedDurableAttachment(
    MediaAttachment attachment, {
    required int nowMs,
  }) async {
    final saved = await dbSaveDirectPrivateMediaAttachmentGuarded(
      currentDatabase(),
      attachment.toMap(),
      messageId: attachment.messageId,
      nowMs: nowMs,
    );
    if (!saved) {
      throw StateError('journey durable attachment seed was rejected');
    }
    seedAttachment(attachment);
  }

  MediaAttachment? _find(String id) {
    for (final rows in _byMessage.values) {
      for (final row in rows) {
        if (row.id == id) return row;
      }
    }
    return null;
  }

  bool _replace(
    String id,
    MediaAttachment Function(MediaAttachment current) replace,
  ) {
    for (final rows in _byMessage.values) {
      final index = rows.indexWhere((row) => row.id == id);
      if (index >= 0) {
        rows[index] = replace(rows[index]);
        return true;
      }
    }
    return false;
  }

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async => seedAttachment(attachment.copyWith(ownerLane: owner));

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => List<MediaAttachment>.of(
    (_byMessage[messageId] ?? const <MediaAttachment>[]).where(
      (row) => row.ownerLane == owner,
    ),
  );

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async => <String, List<MediaAttachment>>{
    for (final id in messageIds)
      id: await getAttachmentsForMessage(id, owner: owner),
  };

  @override
  Future<void> updateLocalPath(String id, String localPath) async {
    _replace(
      id,
      (row) => row.copyWith(
        localPath: localPath,
        downloadStatus: 'done',
        downloadRetryCount: 0,
      ),
    );
  }

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {
    _replace(id, (row) => row.copyWith(downloadStatus: downloadStatus));
  }

  @override
  Future<int> deleteAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    final rows = _byMessage[messageId];
    if (rows == null) return 0;
    final before = rows.length;
    rows.removeWhere((row) => row.ownerLane == owner);
    return before - rows.length;
  }

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async => 0;

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => 0;

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async => _byMessage.values
      .expand((rows) => rows)
      .where((row) => row.downloadStatus == 'pending')
      .toList(growable: false);

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments({
    required MediaOwnerLane owner,
  }) async => const <MediaAttachment>[];

  @override
  Future<bool> beginDirectPrivateMediaDownload(
    String id, {
    required String messageId,
    required int nowMs,
  }) => _lock.synchronized(
    id,
    () => beginDirectPrivateMediaDownloadWithinLock(
      id,
      messageId: messageId,
      nowMs: nowMs,
    ),
  );

  @override
  Future<bool> beginDirectPrivateMediaDownloadWithinLock(
    String id, {
    required String messageId,
    required int nowMs,
  }) async {
    final current = _find(id);
    if (current == null ||
        current.messageId != messageId ||
        current.downloadStatus == 'downloading') {
      return false;
    }
    final durableClaim = await dbBeginDirectPrivateMediaDownloadIfEligible(
      currentDatabase(),
      messageId: messageId,
      attachmentId: id,
      nowMs: nowMs,
    );
    if (durableClaim != 1) return false;
    if (!_replace(id, (row) => row.copyWith(downloadStatus: 'downloading'))) {
      throw StateError('journey download claim lost its memory mirror');
    }
    return true;
  }

  @override
  Future<bool> qualifyDirectPrivateMediaLocalReady(
    String id, {
    required String messageId,
    required String expectedLocalPath,
    required int nowMs,
  }) => _lock.synchronized(
    id,
    () => qualifyDirectPrivateMediaLocalReadyWithinLock(
      id,
      messageId: messageId,
      expectedLocalPath: expectedLocalPath,
      nowMs: nowMs,
    ),
  );

  @override
  Future<bool> qualifyDirectPrivateMediaLocalReadyWithinLock(
    String id, {
    required String messageId,
    required String expectedLocalPath,
    required int nowMs,
  }) async {
    final current = _find(id);
    if (current?.messageId != messageId ||
        current?.downloadStatus != 'done' ||
        current?.localPath != expectedLocalPath) {
      return false;
    }
    return await dbQualifyDirectPrivateMediaLocalReadyIfEligible(
          currentDatabase(),
          messageId: messageId,
          attachmentId: id,
          expectedLocalPath: expectedLocalPath,
          nowMs: nowMs,
        ) ==
        1;
  }

  @override
  Future<bool> qualifyDirectPrivateMediaDownloadClaimWithinLock(
    String id, {
    required String messageId,
    required int nowMs,
  }) async {
    final current = _find(id);
    if (current?.messageId != messageId ||
        current?.downloadStatus != 'downloading') {
      return false;
    }
    return await dbQualifyDirectPrivateMediaDownloadClaimIfEligible(
          currentDatabase(),
          messageId: messageId,
          attachmentId: id,
          nowMs: nowMs,
        ) ==
        1;
  }

  @override
  Future<bool> recordDirectPrivateMediaDownloadFailure(
    String id, {
    required String messageId,
    required int nowMs,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    String? expectedLocalPath,
    bool clearLocalPath = false,
  }) => _lock.synchronized(
    id,
    () => recordDirectPrivateMediaDownloadFailureWithinLock(
      id,
      messageId: messageId,
      nowMs: nowMs,
      incrementRetryCount: incrementRetryCount,
      failureStatus: failureStatus,
      expectedDownloadStatus: expectedDownloadStatus,
      expectedLocalPath: expectedLocalPath,
      clearLocalPath: clearLocalPath,
    ),
  );

  @override
  Future<bool> recordDirectPrivateMediaDownloadFailureWithinLock(
    String id, {
    required String messageId,
    required int nowMs,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    String? expectedLocalPath,
    bool clearLocalPath = false,
  }) async {
    final current = _find(id);
    if (current == null ||
        current.messageId != messageId ||
        current.downloadStatus != expectedDownloadStatus ||
        (expectedLocalPath != null && current.localPath != expectedLocalPath)) {
      return false;
    }
    final durableFailure =
        await dbRecordDirectPrivateMediaDownloadFailureIfEligible(
          currentDatabase(),
          messageId: messageId,
          attachmentId: id,
          nowMs: nowMs,
          incrementRetryCount: incrementRetryCount,
          failureStatus: failureStatus,
          expectedDownloadStatus: expectedDownloadStatus,
          expectedLocalPath: expectedLocalPath,
          clearLocalPath: clearLocalPath,
        );
    if (durableFailure != 1) return false;
    if (!_replace(
      id,
      (row) => row.copyWith(
        downloadStatus: failureStatus,
        downloadRetryCount: incrementRetryCount
            ? (row.downloadRetryCount ?? 0) + 1
            : row.downloadRetryCount,
        clearLocalPath: clearLocalPath,
      ),
    )) {
      throw StateError('journey download failure lost its memory mirror');
    }
    return true;
  }

  @override
  Future<bool> commitDirectPrivateMediaDownloadLocalPath(
    String id, {
    required String messageId,
    required String localPath,
    required int nowMs,
  }) => _lock.synchronized(
    id,
    () => commitDirectPrivateMediaDownloadLocalPathWithinLock(
      id,
      messageId: messageId,
      localPath: localPath,
      nowMs: nowMs,
    ),
  );

  @override
  Future<bool> commitDirectPrivateMediaDownloadLocalPathWithinLock(
    String id, {
    required String messageId,
    required String localPath,
    required int nowMs,
  }) async {
    final current = _find(id);
    if (current == null ||
        current.messageId != messageId ||
        current.downloadStatus != 'downloading') {
      return false;
    }
    final durableCommit = await dbCommitDirectPrivateMediaDownloadIfEligible(
      currentDatabase(),
      messageId: messageId,
      attachmentId: id,
      localPath: localPath,
      nowMs: nowMs,
    );
    if (durableCommit != 1) return false;
    if (!_replace(
      id,
      (row) => row.copyWith(
        localPath: localPath,
        downloadStatus: 'done',
        downloadRetryCount: 0,
      ),
    )) {
      throw StateError('journey download commit lost its memory mirror');
    }
    return true;
  }

  @override
  Future<List<DirectPrivateMediaLifecycleAttachmentMetadata>>
  loadDirectPrivateMediaLifecycleAttachmentMetadata(String messageId) async {
    final rows = await dbLoadMediaForMessage(
      currentDatabase(),
      messageId,
      ownerLane: MediaOwnerLane.direct.dbValue,
    );
    return rows
        .map(
          (row) => DirectPrivateMediaLifecycleAttachmentMetadata(
            id: row['id'] as String,
            messageId: row['message_id'] as String,
            mime: row['mime'] as String,
            size: (row['size'] as num).toInt(),
            downloadStatus: row['download_status'] as String,
            localPath: row['local_path'] as String?,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<DirectPrivateMediaCleanupAttachment>>
  loadDirectPrivateMediaCleanupAttachments(String messageId) async {
    final rows = await dbLoadMediaForMessage(
      currentDatabase(),
      messageId,
      ownerLane: MediaOwnerLane.direct.dbValue,
    );
    return rows
        .map(
          (row) => DirectPrivateMediaCleanupAttachment(
            id: row['id'] as String,
            messageId: row['message_id'] as String,
            mime: row['mime'] as String,
            size: (row['size'] as num).toInt(),
            downloadStatus: row['download_status'] as String,
            localPath: row['local_path'] as String?,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<bool> deleteDirectPrivateMediaEncryptionKeyWithinLock({
    required String messageId,
    required String attachmentId,
  }) => dbCanCleanupDirectPrivateMediaAttachmentExact(
    currentDatabase(),
    messageId: messageId,
    attachmentId: attachmentId,
  );

  @override
  Future<int> deleteDirectPrivateMediaAttachmentWithinLock({
    required String messageId,
    required String attachmentId,
  }) async {
    final durableDeleted = await dbDeleteDirectPrivateMediaAttachmentExact(
      currentDatabase(),
      messageId: messageId,
      attachmentId: attachmentId,
    );
    if (durableDeleted == 0) return 0;
    final rows = _byMessage[messageId];
    rows?.removeWhere((row) => row.id == attachmentId);
    return durableDeleted;
  }
}
