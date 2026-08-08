import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/video_thumbnail_cache.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  for (final scenario in const <({String name, bool isForwarded})>[
    (name: 'external share', isForwarded: false),
    (name: 'forward', isForwarded: true),
  ]) {
    testWidgets(
      '${scenario.name} image/video output opens both sender viewer items with direct ownership',
      (tester) async {
        final sourceDir = Directory.systemTemp.createTempSync(
          'outgoing_share_owner_${scenario.isForwarded}_',
        );
        final image = File('${sourceDir.path}/shared.png')
          ..writeAsBytesSync(_tinyPngBytes);
        final video = File('${sourceDir.path}/shared.mp4')
          ..writeAsBytesSync(const [
            0x00,
            0x00,
            0x00,
            0x18,
            0x66,
            0x74,
            0x79,
            0x70,
            0x69,
            0x73,
            0x6f,
            0x6d,
          ]);
        final thumbnail = File('${sourceDir.path}/video-thumb.png')
          ..writeAsBytesSync(_tinyPngBytes);
        debugSetVideoThumbnailGenerator((_) async => thumbnail);
        MediaFileManager.cacheDocumentsDir(FakeMediaFileManager.testRootPath);
        addTearDown(() {
          debugSetVideoThumbnailGenerator(null);
          MediaFileManager.debugResetDocumentsDirCache();
          if (sourceDir.existsSync()) {
            sourceDir.deleteSync(recursive: true);
          }
          final fakeRoot = Directory(FakeMediaFileManager.testRootPath);
          if (fakeRoot.existsSync()) {
            fakeRoot.deleteSync(recursive: true);
          }
        });

        const ownPeerId = 'outgoing-share-own-peer';
        const contactPeerId = 'outgoing-share-contact-peer';
        const timestamp = '2026-07-14T12:00:00.000Z';
        final identity = IdentityModel(
          peerId: ownPeerId,
          publicKey: 'own-public-key',
          privateKey: 'own-private-key',
          mnemonic12:
              'one two three four five six seven eight nine ten eleven twelve',
          username: 'Me',
          createdAt: timestamp,
          updatedAt: timestamp,
        );
        final contact = ContactModel(
          peerId: contactPeerId,
          publicKey: 'contact-public-key',
          mlKemPublicKey: 'contact-mlkem-key',
          rendezvous: '/dns4/relay.example/tcp/443',
          username: 'Friend',
          signature: 'contact-signature',
          scannedAt: timestamp,
        );
        final identities = FakeIdentityRepository()..seed(identity);
        final contacts = InMemoryContactRepository();
        await contacts.addContact(contact);
        final messages = InMemoryMessageRepository();
        final media = InMemoryMediaAttachmentRepository()
          ..enableDirectMediaInboxCustodyForTest(messages);
        final p2pService = _AckOrExpiryFakeP2PService(
          initialState: const NodeState(peerId: ownPeerId, isStarted: true),
        );
        final coordinator = DefaultShareBatchDeliveryCoordinator(
          identityRepository: identities,
          contactRepository: contacts,
          messageRepository: messages,
          mediaAttachmentRepository: media,
          groupRepository: null,
          groupMessageRepository: null,
          bridge: PassthroughCryptoBridge(),
          p2pService: p2pService,
          mediaFileManager: FakeMediaFileManager(),
          imageProcessor: ImageProcessor(
            compressFile:
                ({
                  required path,
                  required quality,
                  required keepExif,
                  minWidth = 1920,
                  minHeight = 1080,
                }) async => null,
            compressVideo:
                ({required path, required compress, onProgress}) async => null,
          ),
          processSharedMediaFn: (_) async => ProcessedShareMediaBatch(
            processedMedia: [
              PendingComposerMedia(
                file: image,
                budgetBytes: image.lengthSync(),
              ),
              PendingComposerMedia(
                file: video,
                budgetBytes: video.lengthSync(),
                durationMs: 1000,
              ),
            ],
          ),
        );
        final provenance = scenario.isForwarded
            ? const ForwardProvenance(
                operationDedupKey: 'outgoing-share-forward-operation',
              )
            : null;

        final result = (await tester.runAsync(
          () => coordinator.deliver(
            shareIntent: ShareIntent(
              type: ShareIntentType.files,
              filePaths: [image.path, video.path],
              forwardProvenance: provenance,
            ),
            targets: [ShareTargetSelection.contact(contact)],
          ),
        ))!;

        expect(result.failureCount, 0, reason: result.results.single.detail);
        final message = (await messages.getMessagesForContact(
          contactPeerId,
        )).single;
        expect(message.isForwarded, scenario.isForwarded);
        expect(message.media.map((attachment) => attachment.mediaType), [
          'image',
          'video',
        ]);
        expect(
          message.media.map((attachment) => attachment.ownerLane),
          everyElement(MediaOwnerLane.direct),
        );
        expect(
          message.media.map((attachment) => attachment.messageId),
          everyElement(message.id),
        );
        expect(p2pService.custodyStores, hasLength(1));
        final custodyStore = p2pService.custodyStores.single;
        expect(custodyStore.recipientPeerId, contactPeerId);
        expect(custodyStore.custodyKind, AckCustodyKind.directTextV108);
        expect(custodyStore.wireEnvelope, message.wireEnvelope);
        final paths = message.media
            .map(
              (attachment) =>
                  MediaFileManager.resolveStoredPathSync(attachment.localPath!),
            )
            .toList(growable: false);
        expect(paths.every((path) => File(path).existsSync()), isTrue);

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ConversationScreen(
                contactPeerId: contactPeerId,
                contactUsername: contact.username,
                connectionDate: 'July 14, 2026',
                ownPeerId: ownPeerId,
                messages: [message],
                initialLoadDone: true,
                onSend: (_) {},
                onBack: () {},
                mediaViewerBuilder:
                    ({
                      required localPath,
                      required allPaths,
                      required initialIndex,
                    }) => Scaffold(
                      body: Column(
                        children: [
                          Text('owner-viewer-path:$localPath'),
                          Text('owner-viewer-index:$initialIndex'),
                          Text('owner-viewer-all:${allPaths.join('|')}'),
                        ],
                      ),
                    ),
              ),
            ),
          ),
        );
        await _pumpFrames(tester);

        for (var index = 0; index < message.media.length; index++) {
          final attachment = message.media[index];
          await tester.tap(
            find.byKey(
              ValueKey('media-grid-cell-${message.id}-${attachment.id}'),
            ),
          );
          await _pumpFrames(tester);
          expect(
            find.text('owner-viewer-path:${paths[index]}'),
            findsOneWidget,
          );
          expect(find.text('owner-viewer-index:$index'), findsOneWidget);
          expect(
            find.text('owner-viewer-all:${paths.join('|')}'),
            findsOneWidget,
          );
          Navigator.of(
            tester.element(find.text('owner-viewer-index:$index')),
          ).pop();
          await _pumpFrames(tester);
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}

class _AckOrExpiryFakeP2PService extends FakeP2PService
    implements AckOrExpiryInboxStore {
  _AckOrExpiryFakeP2PService({required NodeState initialState})
    : super(initialState: initialState, storeInInboxResult: true);

  final List<
    ({String recipientPeerId, String wireEnvelope, AckCustodyKind custodyKind})
  >
  custodyStores = [];

  @override
  Future<InboxStoreOutcome> storeInAckCustodyInboxDetailed(
    String toPeerId,
    String message, {
    required AckCustodyKind custodyKind,
    int? timeoutMs,
  }) async {
    custodyStores.add((
      recipientPeerId: toPeerId,
      wireEnvelope: message,
      custodyKind: custodyKind,
    ));
    if (custodyKind != AckCustodyKind.directTextV108) {
      return const InboxStoreOutcome(
        status: InboxStoreStatus.failed,
        errorCode: 'WRONG_CUSTODY_KIND',
      );
    }
    return const InboxStoreOutcome(
      status: InboxStoreStatus.stored,
      storeStatus: 'stored',
      expiresAtMs: 4102444800000,
      custodyContract: ackOrExpiryInboxCustodyContract,
    );
  }
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

final List<int> _tinyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
