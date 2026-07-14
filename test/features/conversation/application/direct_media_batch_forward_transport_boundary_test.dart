import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/build_direct_media_library_batch_forward.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/share/application/direct_media_batch_forward_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

const _sourceContactPeerId = 'source-contact-peer';

ContactModel _contact(String peerId) => ContactModel(
  peerId: peerId,
  publicKey: 'public-$peerId',
  rendezvous: '/dns4/relay/tcp/443',
  username: peerId,
  signature: 'signature-$peerId',
  scannedAt: '2026-07-11T18:00:00.000Z',
  mlKemPublicKey: 'mlkem-$peerId',
);

IdentityModel _identity() => IdentityModel(
  peerId: 'sender-peer',
  publicKey: 'sender-public',
  privateKey: 'sender-private',
  mnemonic12: 'one two three four five six seven eight nine ten eleven twelve',
  mlKemPublicKey: 'sender-mlkem-public',
  mlKemSecretKey: 'sender-mlkem-secret',
  username: 'Sender',
  createdAt: '2026-07-11T18:00:00.000Z',
  updatedAt: '2026-07-11T18:00:00.000Z',
);

DirectMediaLibraryBatchForwardItemDraft _item({
  required String id,
  required String path,
  required String caption,
  required String token,
}) => DirectMediaLibraryBatchForwardItemDraft(
  identity: DirectReceivedMediaActionIdentity(
    messageId: 'source-message-$id',
    attachmentId: 'source-attachment-$id',
  ),
  resolvedPath: path,
  parentTimestamp: '2026-07-11T18:00:00.000Z',
  caption: caption,
  forwardProvenance: ForwardProvenance(operationDedupKey: token),
);

ImageProcessor _imageProcessor() => ImageProcessor(
  compressFile:
      ({
        required path,
        required quality,
        required keepExif,
        minWidth = 1920,
        minHeight = 1080,
      }) async => null,
  compressVideo: ({required path, required compress, onProgress}) async =>
      const VideoProcessResult(path: '/tmp/video.mp4'),
);

class _Harness {
  _Harness({InMemoryContactRepository? contacts})
    : contacts = contacts ?? InMemoryContactRepository(),
      messages = InMemoryMessageRepository(),
      attachments = InMemoryMediaAttachmentRepository();

  final InMemoryContactRepository contacts;
  final InMemoryMessageRepository messages;
  final InMemoryMediaAttachmentRepository attachments;
  final PassthroughCryptoBridge bridge = PassthroughCryptoBridge();

  late final DefaultShareBatchDeliveryCoordinator ordinary =
      DefaultShareBatchDeliveryCoordinator(
        identityRepository: FakeIdentityRepository()..seed(_identity()),
        contactRepository: contacts,
        messageRepository: messages,
        mediaAttachmentRepository: attachments,
        groupRepository: InMemoryGroupRepository(),
        groupMessageRepository: InMemoryGroupMessageRepository(),
        bridge: bridge,
        p2pService: FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'sender-peer'),
        ),
        mediaFileManager: FakeMediaFileManager(),
        imageProcessor: _imageProcessor(),
        processSharedMediaFn: (intent) async {
          final path = intent.filePaths.single;
          final file = File(path);
          if (!file.existsSync() || path.contains('oversized')) {
            return ProcessedShareMediaBatch(
              processedMedia: const [],
              skippedOversizedGifCount: path.contains('oversized') ? 1 : 0,
            );
          }
          return ProcessedShareMediaBatch(
            processedMedia: [
              PendingComposerMedia(file: file, budgetBytes: file.lengthSync()),
            ],
          );
        },
      );

  DirectMediaBatchForwardDeliveryCoordinator app({
    void Function(DirectMediaLibraryBatchForwardDraft draft)? onRevalidated,
  }) => DirectMediaBatchForwardDeliveryCoordinator(
    revalidateForDispatch: ({required contactPeerId, required draft}) async {
      expect(contactPeerId, _sourceContactPeerId);
      onRevalidated?.call(draft);
      return DirectMediaLibraryBatchForwardResult.ready(draft);
    },
    contactRepository: contacts,
    deliverStrict: ({required shareIntent, required contacts, onProgress}) =>
        ordinary.deliverDirectMediaBatchForwardStrict(
          shareIntent: shareIntent,
          contacts: contacts,
          onProgress: onProgress,
        ),
  );
}

class _InvalidateOnSecondReadContacts extends InMemoryContactRepository {
  _InvalidateOnSecondReadContacts(this.invalidPeerId);

  final String invalidPeerId;
  final Map<String, int> reads = {};

  @override
  Future<ContactModel?> getContact(String peerId) async {
    final read = (reads[peerId] ?? 0) + 1;
    reads[peerId] = read;
    if (peerId == invalidPeerId && read >= 2) {
      await deleteContact(peerId);
      return null;
    }
    return super.getContact(peerId);
  }
}

void main() {
  test(
    'all-valid two by two composes four fresh encrypted ordinary messages without source provenance',
    () async {
      final dir = Directory.systemTemp.createTempSync('plan249_transport_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final firstFile = File('${dir.path}/first.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final secondFile = File('${dir.path}/second.jpg')
        ..writeAsBytesSync([4, 5, 6]);
      final firstContact = _contact('recipient-one');
      final secondContact = _contact('recipient-two');
      final harness = _Harness();
      await harness.contacts.addContact(firstContact);
      await harness.contacts.addContact(secondContact);
      final draft = DirectMediaLibraryBatchForwardDraft(
        items: [
          _item(
            id: '1',
            path: firstFile.path,
            caption: 'first caption',
            token: 'operation-token-one',
          ),
          _item(
            id: '2',
            path: secondFile.path,
            caption: '',
            token: 'operation-token-two',
          ),
        ],
      );

      final result = await harness.app().deliverInitial(
        sourceContactPeerId: _sourceContactPeerId,
        draft: draft,
        contactPeerIds: [firstContact.peerId, secondContact.peerId],
      );

      expect(result.isDenied, isFalse);
      expect(result.matrix!.cells, hasLength(4));
      expect(result.matrix!.sentCount, 4);
      final firstRows = await harness.messages.getMessagesForContact(
        firstContact.peerId,
      );
      final secondRows = await harness.messages.getMessagesForContact(
        secondContact.peerId,
      );
      expect(firstRows, hasLength(2));
      expect(secondRows, hasLength(2));
      final allRows = [...firstRows, ...secondRows];
      expect(allRows.map((row) => row.id).toSet(), hasLength(4));
      expect(allRows.where((row) => row.text == 'first caption'), hasLength(2));
      expect(allRows.where((row) => row.text.isEmpty), hasLength(2));
      expect(allRows.map((row) => row.dedupKey).toSet(), {
        'operation-token-one',
        'operation-token-two',
      });
      final attachmentByMessageId = <String, MediaAttachment>{};
      for (final row in allRows) {
        final media = await harness.attachments.getAttachmentsForMessage(
          row.id,
          owner: MediaOwnerLane.direct,
        );
        expect(media, hasLength(1));
        expect(media.single.messageId, row.id);
        attachmentByMessageId[row.id] = media.single;
      }
      final allMedia = attachmentByMessageId.values.toList(growable: false);
      expect(allMedia, hasLength(4));
      expect(allMedia.map((media) => media.id).toSet(), hasLength(4));
      expect(
        allMedia.map((media) => media.encryptionKeyBase64).toSet(),
        hasLength(4),
      );
      expect(
        allMedia.every(
          (media) => media.encryptionKeyBase64?.isNotEmpty ?? false,
        ),
        isTrue,
      );
      expect(
        allMedia.map((media) => media.encryptionNonce).toSet(),
        hasLength(4),
      );
      expect(
        allMedia.every((media) => media.encryptionNonce?.isNotEmpty ?? false),
        isTrue,
      );
      expect(allMedia.map((media) => media.encryptionScheme).toSet(), {
        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      });

      final bridgeRequests = harness.bridge.sentMessages
          .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
          .toList(growable: false);
      final uploadRequests = bridgeRequests
          .where((request) => request['cmd'] == 'media:upload')
          .map((request) => request['payload'] as Map<String, dynamic>)
          .toList(growable: false);
      expect(uploadRequests, hasLength(4));
      expect(uploadRequests.map((payload) => payload['id']).toSet(), {
        for (final media in allMedia) media.id,
      });
      for (final contact in [firstContact, secondContact]) {
        final destinationUploads = uploadRequests
            .where((payload) => payload['to'] == contact.peerId)
            .toList(growable: false);
        expect(destinationUploads, hasLength(2));
        for (final payload in destinationUploads) {
          expect(payload['mime'], kOpaqueMediaTransportMime);
          final encryptedPath = payload['filePath'] as String;
          expect(encryptedPath, endsWith('.enc'));
          expect(encryptedPath, isNot(firstFile.path));
          expect(encryptedPath, isNot(secondFile.path));
        }
      }

      final encryptRequests = bridgeRequests
          .where((request) => request['cmd'] == 'message.encrypt')
          .map((request) => request['payload'] as Map<String, dynamic>)
          .toList(growable: false);
      expect(encryptRequests, hasLength(4));
      for (final row in allRows) {
        final media = attachmentByMessageId[row.id]!;
        final matching = encryptRequests
            .where((request) {
              final inner =
                  jsonDecode(request['plaintext'] as String)
                      as Map<String, dynamic>;
              return inner['id'] == row.id;
            })
            .toList(growable: false);
        expect(matching, hasLength(1));
        final request = matching.single;
        expect(request['recipientPublicKey'], 'mlkem-${row.contactPeerId}');
        final inner =
            jsonDecode(request['plaintext'] as String) as Map<String, dynamic>;
        final wireMedia =
            (inner['media'] as List<dynamic>).single as Map<String, dynamic>;
        expect(wireMedia['id'], media.id);
        expect(wireMedia['encryptionKeyBase64'], media.encryptionKeyBase64);
        expect(wireMedia['encryptionNonce'], media.encryptionNonce);
        expect(wireMedia['encryptionScheme'], media.encryptionScheme);

        final envelope = jsonDecode(row.wireEnvelope!) as Map<String, dynamic>;
        expect(envelope['type'], 'chat_message');
        expect(envelope['version'], '2');
        expect(envelope['id'], row.id);
        final encrypted = envelope['encrypted'] as Map<String, dynamic>;
        expect(encrypted['kem'], isNotEmpty);
        expect(encrypted['nonce'], isNotEmpty);
        expect(
          encrypted['ciphertext'],
          request['plaintext'],
          reason:
              'the passthrough fake exposes envelope linkage, not real cryptographic strength',
        );
      }
      final destinationEvidence = allRows
          .map((row) => '${row.id}|${row.text}|${row.wireEnvelope}')
          .join('\n');
      for (final forbidden in <String>[
        'source-message-1',
        'source-message-2',
        'source-attachment-1',
        'source-attachment-2',
        firstFile.path,
        secondFile.path,
      ]) {
        expect(destinationEvidence, isNot(contains(forbidden)));
      }
    },
  );

  test(
    'post-preflight missing or oversized source fails every cell with zero caption-only message',
    () async {
      for (final scenario in <String>['missing', 'oversized']) {
        final dir = Directory.systemTemp.createTempSync(
          'plan249_transport_$scenario',
        );
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/$scenario.jpg')
          ..writeAsBytesSync([7, 8, 9]);
        final contact = _contact('recipient-$scenario');
        final harness = _Harness();
        await harness.contacts.addContact(contact);
        final draft = DirectMediaLibraryBatchForwardDraft(
          items: [
            _item(
              id: scenario,
              path: file.path,
              caption: 'must never become text-only',
              token: 'token-$scenario',
            ),
          ],
        );

        final result = await harness
            .app(
              onRevalidated: (_) {
                if (scenario == 'missing') file.deleteSync();
              },
            )
            .deliverInitial(
              sourceContactPeerId: _sourceContactPeerId,
              draft: draft,
              contactPeerIds: [contact.peerId],
            );

        expect(
          result.matrix!.cells.single.status,
          DirectMediaBatchForwardCellStatus.failed,
        );
        expect(
          await harness.messages.getMessagesForContact(contact.peerId),
          isEmpty,
        );
      }
    },
  );

  test(
    'contact invalidated after application preflight fails only that cell without stale fallback',
    () async {
      final dir = Directory.systemTemp.createTempSync('plan249_contact_race_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/source.jpg')..writeAsBytesSync([1, 2]);
      final invalid = _contact('recipient-invalidated');
      final valid = _contact('recipient-valid');
      final contacts = _InvalidateOnSecondReadContacts(invalid.peerId);
      final harness = _Harness(contacts: contacts);
      await contacts.addContact(invalid);
      await contacts.addContact(valid);

      final result = await harness.app().deliverInitial(
        sourceContactPeerId: _sourceContactPeerId,
        draft: DirectMediaLibraryBatchForwardDraft(
          items: [
            _item(
              id: 'race',
              path: file.path,
              caption: 'caption',
              token: 'token-race',
            ),
          ],
        ),
        contactPeerIds: [invalid.peerId, valid.peerId],
      );

      expect(result.matrix!.cells.map((cell) => cell.status), [
        DirectMediaBatchForwardCellStatus.failed,
        DirectMediaBatchForwardCellStatus.sent,
      ]);
      expect(
        await harness.messages.getMessagesForContact(invalid.peerId),
        isEmpty,
      );
      expect(
        await harness.messages.getMessagesForContact(valid.peerId),
        hasLength(1),
      );
      expect(contacts.reads[invalid.peerId], greaterThanOrEqualTo(2));
    },
  );
}
