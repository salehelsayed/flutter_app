import 'dart:io';
import 'package:flutter_app/core/config/direct_linked_event_fanout_flag.dart';
import 'package:flutter_app/core/config/direct_linked_media_fanout_flag.dart';
import 'package:flutter_app/core/database/direct_event_fanout_contract.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart'
    show DirectMediaFanoutStageAuthority, DirectMediaFanoutTargetBinding;
import 'package:flutter_app/features/conversation/application/direct_event_fanout_coordinator.dart';
import 'package:flutter_app/features/conversation/application/direct_media_fanout_admission.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/config/direct_media_blob_custody_client_flag.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/direct_media_blob_custody_db_helpers.dart'
    show kDirectMediaBlobCustodyTable;
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/core/media/direct_private_media_transfer_registry.dart';
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/application/remove_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_media_blob_generation_result.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/date_separator.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/outgoing_ordinary_mutation_result.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_conversation_modality_gate.dart';
import 'package:flutter_app/features/conversation/presentation/controllers/reaction_optimistic_attempt_guard.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/conversation_header.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/direct_received_media_action_sheet.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/shared/widgets/media/recording_overlay.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/settings/application/media_download_policy.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/features/settings/domain/models/media_download_preferences.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/bridge/fake_bridge.dart';
import '../../../../shared/fakes/fake_audio_recorder_service.dart';
import '../../../../shared/fakes/fake_mic_permission_gateway.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/helpers/legacy_upload_media_fn.dart';
import '../../../../shared/fakes/recording_media_auto_download_decider.dart';
import '../../../../shared/fakes/fake_media_picker.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../../shared/fakes/fake_upload_wake_lock_driver.dart';
import '../../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../domain/repositories/fake_media_attachment_repository.dart';
import '../../domain/repositories/fake_reaction_repository.dart';

const _tinyPngBytes = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x02,
  0x00,
  0x00,
  0x00,
  0x90,
  0x77,
  0x53,
  0xDE,
  0x00,
  0x00,
  0x00,
  0x0C,
  0x49,
  0x44,
  0x41,
  0x54,
  0x08,
  0xD7,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0x00,
  0x00,
  0x03,
  0x01,
  0x01,
  0x00,
  0x18,
  0xDD,
  0x8D,
  0xB1,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

const _tinyGifBytes = <int>[
  0x47,
  0x49,
  0x46,
  0x38,
  0x39,
  0x61,
  0x01,
  0x00,
  0x01,
  0x00,
  0x80,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0xFF,
  0xFF,
  0xFF,
  0x21,
  0xF9,
  0x04,
  0x01,
  0x00,
  0x00,
  0x00,
  0x00,
  0x2C,
  0x00,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x01,
  0x00,
  0x00,
  0x02,
  0x02,
  0x44,
  0x01,
  0x00,
  0x3B,
];

const _gifReplacementPolicyTestName =
    'replacing a private image draft with GIF resets to keep in chat before optimistic persistence';

/// 362: the strict composer fake with the fanout capability and natural
/// (attachment, recipient) row identity, so the routed composer scenario can
/// run inside the widget zone without a real database.
class _FanoutComposerMediaRepository extends _StrictComposerMediaRepository
    implements OutgoingDirectLinkedMediaBlobFanoutRepository {
  _FanoutComposerMediaRepository({
    required this.snapshot,
    this.onFreshFanoutGenerationPublished,
  });

  final DirectContactFanoutSnapshot snapshot;
  final Future<void> Function(ConversationMessage markedParent)?
  onFreshFanoutGenerationPublished;
  final Map<String, DirectMediaBlobCustodyRow> fanoutRows =
      <String, DirectMediaBlobCustodyRow>{};
  int snapshotReads = 0;
  bool throwOnSnapshotRead = false;
  bool applyFanoutInboxStage = false;
  DirectMediaFanoutStageAuthority? fanoutInboxAuthority;
  DirectContactFanoutSnapshot? fanoutInboxSnapshot;
  List<DirectMediaFanoutTargetBinding> fanoutInboxBindings =
      const <DirectMediaFanoutTargetBinding>[];

  String _key(String attachmentId, String recipientPeerId) =>
      '$attachmentId|$recipientPeerId';

  @override
  bool get supportsDirectLinkedMediaBlobFanout => true;

  @override
  Future<DirectContactFanoutSnapshot?> readDirectContactFanoutSnapshotForMedia(
    String contactAccountPeerId,
  ) async {
    snapshotReads++;
    if (throwOnSnapshotRead) {
      throw StateError('persisted composer survivor must not read the roster');
    }
    return contactAccountPeerId == snapshot.contactAccountPeerId
        ? snapshot
        : null;
  }

  @override
  Future<DirectMediaBlobGenerationStageResult>
  stageOutgoingDirectLinkedMediaBlobFanoutGeneration({
    required ConversationMessage expectedParent,
    required List<MediaAttachment> expectedAttachments,
    required List<MediaAttachment> preparedAttachments,
    required List<DirectMediaBlobCustodyRow> custodyRows,
    required String contactAccountPeerId,
    required DirectContactFanoutSnapshot expectedSnapshot,
    bool allowFreshParent = false,
    String? authorizedForwardDedupKey,
  }) async {
    if (fanoutRows.isNotEmpty ||
        contactAccountPeerId != snapshot.contactAccountPeerId ||
        !expectedSnapshot.sameSnapshotAs(snapshot) ||
        custodyRows.length !=
            expectedAttachments.length * snapshot.targets.length) {
      return const DirectMediaBlobGenerationStageResult.refused();
    }
    seed(preparedAttachments);
    for (final row in custodyRows) {
      fanoutRows[_key(row.attachmentId, row.recipientPeerId!)] = row;
    }
    await onFreshFanoutGenerationPublished?.call(
      expectedParent.copyWith(directEventFanoutGenerationId: expectedParent.id),
    );
    return DirectMediaBlobGenerationStageResult(
      outcome: DirectMediaBlobGenerationStageOutcome.applied,
      attachments: preparedAttachments,
      custodyRows: custodyRows,
    );
  }

  @override
  Future<DirectMediaFanoutInboxCustodyStageResult>
  stageOutgoingDirectMediaFanoutInboxCustody({
    required ConversationMessage expected,
    required ConversationMessage staged,
    required List<MediaAttachment> attachments,
    required String senderTransportPeerId,
    required String contactAccountPeerId,
    required DirectMediaFanoutStageAuthority authority,
    required DirectContactFanoutSnapshot? expectedSnapshot,
    required List<DirectMediaFanoutTargetBinding> targetBindings,
  }) async {
    fanoutInboxAuthority = authority;
    fanoutInboxSnapshot = expectedSnapshot;
    fanoutInboxBindings = List<DirectMediaFanoutTargetBinding>.of(
      targetBindings,
    );
    if (!applyFanoutInboxStage) {
      throw StateError('the faked send function owns v108 in this test');
    }
    return DirectMediaFanoutInboxCustodyStageResult(
      outcome: OutgoingOrdinaryMutationOutcome.applied,
      message: staged.copyWith(
        directMediaCustodyIntentId: null,
        media: attachments,
      ),
      attachments: attachments,
      custodyRows: <Map<String, Object?>>[
        for (final binding in targetBindings)
          <String, Object?>{
            'recipient_peer_id': binding.recipientPeerId,
            'wire_envelope': binding.wireEnvelope,
          },
      ],
    );
  }

  @override
  Future<DirectMediaBlobCustodyRow?>
  loadOutgoingDirectMediaBlobCustodyForTarget({
    required String attachmentId,
    required String recipientPeerId,
  }) async =>
      fanoutRows[_key(attachmentId, recipientPeerId)] ??
      await super.loadOutgoingDirectMediaBlobCustodyForTarget(
        attachmentId: attachmentId,
        recipientPeerId: recipientPeerId,
      );

  @override
  Future<List<DirectMediaBlobCustodyRow>>
  loadDirectMediaBlobCustodyRowsForAttachment(
    String attachmentId,
  ) async => <DirectMediaBlobCustodyRow>[
    ...fanoutRows.values.where((row) => row.attachmentId == attachmentId),
    ...await super.loadDirectMediaBlobCustodyRowsForAttachment(attachmentId),
  ];

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadDirectMediaBlobCustodyForMessage(
    String messageId,
  ) async => <DirectMediaBlobCustodyRow>[
    ...fanoutRows.values.where((row) => row.messageId == messageId),
    ...await super.loadDirectMediaBlobCustodyForMessage(messageId),
  ];

  @override
  Future<bool> transitionDirectMediaBlobCustodyIfExact({
    required DirectMediaBlobCustodyRow expected,
    required DirectMediaBlobCustodyRow next,
  }) async {
    final key = _key(expected.attachmentId, expected.recipientPeerId!);
    final current = fanoutRows[key];
    if (current == null) {
      return super.transitionDirectMediaBlobCustodyIfExact(
        expected: expected,
        next: next,
      );
    }
    if (!current.exactDatabaseProjectionMatches(expected) ||
        !expected.canTransitionTo(next)) {
      return false;
    }
    fanoutRows[key] = next;
    return true;
  }
}

class _StrictComposerMediaRepository extends FakeMediaAttachmentRepository
    implements DirectMediaBlobCustodyRepository {
  final Map<String, DirectMediaBlobCustodyRow> rows =
      <String, DirectMediaBlobCustodyRow>{};

  @override
  bool get supportsDirectMediaBlobCustody => true;

  @override
  Future<T> runDirectMediaBlobCustodyLifecycle<T>(
    Future<T> Function() action,
  ) => action();

  @override
  Future<DirectMediaBlobGenerationStageResult>
  stageOutgoingDirectMediaBlobGeneration({
    required ConversationMessage expectedParent,
    required List<MediaAttachment> expectedAttachments,
    required List<MediaAttachment> preparedAttachments,
    required List<DirectMediaBlobCustodyRow> custodyRows,
  }) async {
    final current = await getAttachmentsForMessage(
      expectedParent.id,
      owner: MediaOwnerLane.direct,
    );
    final currentIds = current.map((attachment) => attachment.id).toSet();
    final expectedIds = expectedAttachments
        .map((attachment) => attachment.id)
        .toSet();
    if (rows.isNotEmpty ||
        preparedAttachments.isEmpty ||
        currentIds.length != expectedIds.length ||
        !currentIds.containsAll(expectedIds) ||
        preparedAttachments.length != custodyRows.length) {
      return const DirectMediaBlobGenerationStageResult.refused();
    }
    seed(preparedAttachments);
    for (final row in custodyRows) {
      rows[row.attachmentId] = row;
    }
    return DirectMediaBlobGenerationStageResult(
      outcome: DirectMediaBlobGenerationStageOutcome.applied,
      attachments: preparedAttachments,
      custodyRows: custodyRows,
    );
  }

  @override
  Future<List<DirectMediaBlobCustodyRow>>
  loadDirectMediaBlobCustodyRowsForAttachment(String attachmentId) async {
    final row = rows[attachmentId];
    return row == null
        ? const <DirectMediaBlobCustodyRow>[]
        : <DirectMediaBlobCustodyRow>[row];
  }

  @override
  Future<DirectMediaBlobCustodyRow?>
  loadIncomingDirectMediaBlobCustodyForAttachment(String attachmentId) async {
    final row = rows[attachmentId];
    return row != null &&
            row.direction == DirectMediaBlobCustodyDirection.incoming
        ? row
        : null;
  }

  @override
  Future<DirectMediaBlobCustodyRow?>
  loadOutgoingDirectMediaBlobCustodyForTarget({
    required String attachmentId,
    required String recipientPeerId,
  }) async {
    final row = rows[attachmentId];
    return row != null &&
            row.direction == DirectMediaBlobCustodyDirection.outgoing &&
            row.recipientPeerId == recipientPeerId
        ? row
        : null;
  }

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadDirectMediaBlobCustodyForMessage(
    String messageId,
  ) async => rows.values
      .where((row) => row.messageId == messageId)
      .toList(growable: false);

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadDirectMediaBlobCustodyByStates(
    Set<DirectMediaBlobCustodyState> states, {
    int limit = 50,
  }) async => rows.values
      .where((row) => states.contains(row.state))
      .take(limit)
      .toList(growable: false);

  @override
  Future<bool> transitionDirectMediaBlobCustodyIfExact({
    required DirectMediaBlobCustodyRow expected,
    required DirectMediaBlobCustodyRow next,
  }) async {
    final current = rows[expected.attachmentId];
    if (current == null ||
        !current.exactDatabaseProjectionMatches(expected) ||
        !expected.canTransitionTo(next)) {
      return false;
    }
    rows[expected.attachmentId] = next;
    return true;
  }

  @override
  Future<bool> deleteDirectMediaBlobCleanupPendingIfExact(
    DirectMediaBlobCustodyRow expected,
  ) async => false;
}

class _SynchronousUploadWakeLockDriver implements UploadWakeLockDriver {
  @override
  Future<void> enable() => SynchronousFuture<void>(null);

  @override
  Future<void> disable() => SynchronousFuture<void>(null);
}

class FakeIdentityRepository implements IdentityRepository {
  IdentityModel? identity;

  FakeIdentityRepository(this.identity);

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    this.identity = identity;
  }
}

class FakeContactRepository implements ContactRepository {
  FakeContactRepository({this.contactExistsResult = true});

  final bool contactExistsResult;

  @override
  Future<void> addContact(ContactModel contact) async {}

  @override
  Future<bool> contactExists(String peerId) async => contactExistsResult;

  @override
  Future<void> deleteContact(String peerId) async {}

  @override
  Future<List<ContactModel>> getAllContacts() async => [];

  @override
  Future<ContactModel?> getContact(String peerId) async => null;

  @override
  Future<int> getContactCount() async => 0;

  @override
  Future<void> archiveContact(String peerId) async {}

  @override
  Future<void> unarchiveContact(String peerId) async {}

  @override
  Future<List<ContactModel>> getActiveContacts() async => [];

  @override
  Future<List<ContactModel>> getArchivedContacts() async => [];

  @override
  Future<void> blockContact(String peerId) async {}

  @override
  Future<void> unblockContact(String peerId) async {}

  @override
  Future<void> dismissIntroBanner(String peerId) async {}

  @override
  Future<void> setIntrosSentAt(String peerId, String timestamp) async {}
}

class _SingleContactRepository extends FakeContactRepository {
  _SingleContactRepository(this.contact);

  final ContactModel contact;

  @override
  Future<ContactModel?> getContact(String peerId) async =>
      peerId == contact.peerId ? contact : null;
}

class TrackingDurableConversationMediaFileManager extends FakeMediaFileManager {
  TrackingDurableConversationMediaFileManager(this.rootDir);

  final Directory rootDir;
  int copyCalls = 0;
  final List<String> deletedPendingUploadDirs = <String>[];
  final Completer<void> pendingUploadDirDeleted = Completer<void>();

  @override
  Future<String> copyToDurableStorage({
    required String sourceFilePath,
    required String messageId,
    required String attachmentId,
    required String mime,
  }) async {
    copyCalls++;
    final dotIndex = sourceFilePath.lastIndexOf('.');
    final ext = dotIndex >= 0 ? sourceFilePath.substring(dotIndex) : '';
    final dir = Directory('${rootDir.path}/pending_uploads/$messageId');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final destinationPath = '${dir.path}/$attachmentId$ext';
    await File(sourceFilePath).copy(destinationPath);
    return 'pending_uploads/$messageId/$attachmentId$ext';
  }

  @override
  Future<String> resolveStoredPath(String storedPath) async {
    if (storedPath.startsWith('pending_uploads/') ||
        storedPath.startsWith('pending_uploads\\') ||
        storedPath.startsWith('media/') ||
        storedPath.startsWith('media\\') ||
        storedPath.startsWith('post_media/') ||
        storedPath.startsWith('post_media\\')) {
      return '${rootDir.path}/$storedPath';
    }
    return storedPath;
  }

  @override
  Future<String> trustedMediaRootPath() async => '${rootDir.path}/media';

  @override
  Future<String> trustedPendingUploadRootPath() async =>
      '${rootDir.path}/pending_uploads';

  @override
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async {
    final relativePath = relativePathForAttachment(
      contactPeerId: contactPeerId,
      blobId: blobId,
      mime: mime,
    );
    final absolutePath = '${rootDir.path}/$relativePath';
    final file = File(absolutePath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    return absolutePath;
  }

  @override
  Future<void> deletePendingUploadDir(String messageId) async {
    deletedPendingUploadDirs.add(messageId);
    final dir = Directory('${rootDir.path}/pending_uploads/$messageId');
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
    if (!pendingUploadDirDeleted.isCompleted) {
      pendingUploadDirDeleted.complete();
    }
  }
}

class _ThrowingPendingPlaintextDeleteMediaFileManager
    extends TrackingDurableConversationMediaFileManager {
  _ThrowingPendingPlaintextDeleteMediaFileManager(super.rootDir);

  int deleteAttempts = 0;
  List<String?> attemptedStoredPaths = const <String?>[];

  @override
  Future<void> deleteOwnedPendingUploadFilesForMessage({
    required String messageId,
    required Iterable<String?> storedPaths,
  }) async {
    deleteAttempts++;
    attemptedStoredPaths = storedPaths.toList(growable: false);
    throw StateError('simulated pending plaintext deletion failure');
  }
}

/// 127-Bug-B: records whether each attachment was already marked in-flight at
/// its FIRST persist. The optimistic persist happens BEFORE the upload loop, so
/// this proves the in-flight mark is set early enough (the timing-hole fix),
/// not only at the later relay-upload step where the retrier could already have
/// raced in.
class InFlightAtFirstSaveMediaRepository extends FakeMediaAttachmentRepository {
  final Map<String, bool> inFlightAtFirstSave = {};

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {
    inFlightAtFirstSave.putIfAbsent(
      attachment.id,
      () => mediaUploadInFlightTracker.isInFlight(attachment.id),
    );
    await super.saveAttachment(attachment, owner: owner);
  }
}

class FakeMessageRepository
    implements
        MessageRepository,
        MessageRepositoryChangeSource,
        OutgoingTransportMutationRepository {
  final Map<String, ConversationMessage> store = {};
  int getMessagesPageCalls = 0;
  int saveMessageCallCount = 0;
  int deleteMessageCallCount = 0;
  Completer<void>? getMessagesPageGate;
  List<ConversationMessage>? getMessagesPageSnapshot;

  /// 233 sentinel: the exact (limit, beforeTimestamp) of every page request,
  /// so pagination tests can prove the 50-row window and cursor use.
  final List<(int, String?)> getMessagesPageRequests = <(int, String?)>[];
  final StreamController<ConversationMessage> _messageChangeController =
      StreamController<ConversationMessage>.broadcast();

  @override
  Stream<ConversationMessage> get messageChanges =>
      _messageChangeController.stream;

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async {
    final messages =
        store.values.where((m) => m.contactPeerId == contactPeerId).toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return messages;
  }

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async {
    final messages = await getMessagesForContact(contactPeerId);
    return messages.isEmpty ? null : messages.last;
  }

  @override
  Future<ConversationMessage?> getMessage(String id) async => store[id];

  @override
  Future<bool> messageExists(String id) async => store.containsKey(id);

  @override
  Future<bool> existsByContent(
    String contactPeerId,
    String senderPeerId,
    String text,
    String timestamp,
  ) async => false;

  @override
  Future<bool> existsByDedupKey(
    String contactPeerId,
    String senderPeerId,
    String dedupKey,
  ) async => false;

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    saveMessageCallCount++;
    store[message.id] = message;
    _messageChangeController.add(message);
  }

  @override
  Future<void> updateMessageStatus(String id, String status) async {
    final message = store[id];
    if (message == null) return;
    final updated = message.copyWith(status: status);
    store[id] = updated;
    _messageChangeController.add(updated);
  }

  @override
  Future<int> getMessageCountForContact(String contactPeerId) async {
    return store.values.where((m) => m.contactPeerId == contactPeerId).length;
  }

  @override
  Future<int> markConversationAsRead(String contactPeerId) async => 0;

  @override
  Future<int> getUnreadCountForContact(String contactPeerId) async => 0;

  @override
  Future<int> getTotalUnreadCount() async => 0;

  @override
  Future<int> getTotalUnreadCountExcludingArchived() async => 0;

  @override
  Future<int> deleteMessagesForContact(String contactPeerId) async => 0;

  @override
  Future<int> deleteMessage(String id) async {
    deleteMessageCallCount++;
    final removed = store.remove(id);
    return removed == null ? 0 : 1;
  }

  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async {
    getMessagesPageCalls++;
    getMessagesPageRequests.add((limit, beforeTimestamp));
    final gate = getMessagesPageGate;
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }
    var messages = (getMessagesPageSnapshot ?? store.values)
        .where((m) => m.contactPeerId == contactPeerId)
        .toList();
    if (beforeTimestamp != null) {
      messages = messages
          .where((m) => m.timestamp.compareTo(beforeTimestamp) < 0)
          .toList();
    }
    messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final page = messages.take(limit).toList();
    return page.reversed.toList();
  }

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async => [];

  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) async => [];

  @override
  Future<int> recoverStuckSendingMessages({
    required Duration olderThan,
  }) async => 0;

  @override
  Future<void> updateWireEnvelope(String id, String envelope) async {}

  @override
  Future<List<ConversationMessage>> getStuckSendingOutgoingMessages({
    required Duration olderThan,
  }) async => [];

  @override
  Future<List<ConversationMessage>> getSendingOutgoingMessages() async => [];

  @override
  Future<int> conditionalTransitionStatus(
    String id, {
    required String fromStatus,
    required String toStatus,
  }) async {
    final current = store[id];
    if (current == null || current.status != fromStatus) return 0;
    final updated = current.copyWith(status: toStatus);
    store[id] = updated;
    _messageChangeController.add(updated);
    return 1;
  }

  @override
  Future<OutgoingOrdinaryMutationResult> stageOutgoingOrdinaryAttempt({
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required OutgoingOrdinaryAttemptKind kind,
  }) async {
    final current = store[staged.id];
    if (kind == OutgoingOrdinaryAttemptKind.fresh) {
      if (expected != null || current != null) {
        return _ordinaryResult(
          OutgoingOrdinaryMutationOutcome.refused,
          current,
        );
      }
      return _applyOrdinary(staged);
    }
    if (expected == null) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.refused, current);
    }
    if (current == null) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.removed, null);
    }
    if (_sameConversationSnapshot(current, staged)) {
      return _ordinaryResult(
        OutgoingOrdinaryMutationOutcome.idempotent,
        current,
      );
    }
    if (!_sameConversationSnapshot(current, expected)) {
      return _ordinaryResult(
        OutgoingOrdinaryMutationOutcome.preserved,
        current,
      );
    }
    return _applyOrdinary(
      staged.copyWith(
        transport: null,
        relayExpiresAt: null,
        custodyCheckedAt: null,
      ),
    );
  }

  @override
  Future<OutgoingOrdinaryMutationResult> settleOutgoingOrdinaryTransport({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
  }) => _settleOrdinary(
    messageId: messageId,
    expectedContactPeerId: expectedContactPeerId,
    expectedEnvelope: expectedEnvelope,
    status: status,
    transport: transport,
    relayExpiresAt: relayExpiresAt,
    mode: mode,
    tombstone: false,
  );

  @override
  Future<OutgoingOrdinaryMutationResult> settleOutgoingOrdinaryDeleteTombstone({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
  }) => _settleOrdinary(
    messageId: messageId,
    expectedContactPeerId: expectedContactPeerId,
    expectedEnvelope: expectedEnvelope,
    status: status,
    transport: transport,
    relayExpiresAt: relayExpiresAt,
    mode: mode,
    tombstone: true,
  );

  Future<OutgoingOrdinaryMutationResult> _settleOrdinary({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
    required bool tombstone,
  }) async {
    final current = store[messageId];
    if (current == null) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.removed, null);
    }
    if (current.isIncoming ||
        current.contactPeerId != expectedContactPeerId ||
        current.isDeleted != tombstone) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.refused, current);
    }
    if (current.status == 'delivered') {
      return _ordinaryResult(
        status == 'delivered'
            ? OutgoingOrdinaryMutationOutcome.idempotent
            : OutgoingOrdinaryMutationOutcome.preserved,
        current,
      );
    }
    if (current.wireEnvelope != expectedEnvelope) {
      return _ordinaryResult(
        OutgoingOrdinaryMutationOutcome.preserved,
        current,
      );
    }
    if (current.status == status) {
      return _ordinaryResult(
        OutgoingOrdinaryMutationOutcome.idempotent,
        current,
      );
    }
    final predecessors = mode == OutgoingOrdinarySettlementMode.receipt
        ? const <String>{'inboxed', 'sent', 'failed'}
        : switch (status) {
            'delivered' => const <String>{
              'sending',
              'sent',
              'inboxed',
              'failed',
            },
            'inboxed' => const <String>{'sending', 'sent', 'failed'},
            'sent' => const <String>{'sending', 'failed'},
            'failed' => const <String>{'sending'},
            _ => const <String>{},
          };
    if (!predecessors.contains(current.status)) {
      return _ordinaryResult(
        OutgoingOrdinaryMutationOutcome.preserved,
        current,
      );
    }
    return _applyOrdinary(
      current.copyWith(
        status: status,
        transport: transport,
        wireEnvelope: status == 'delivered' ? null : expectedEnvelope,
        relayExpiresAt: relayExpiresAt,
        custodyCheckedAt: null,
        hiddenAt: tombstone && status == 'delivered' ? current.deletedAt : null,
      ),
    );
  }

  @override
  Future<OutgoingOrdinaryMutationResult> invalidateOutgoingOrdinaryEnvelope({
    required String messageId,
    required String expectedContactPeerId,
    required String expectedEnvelope,
  }) async {
    final current = store[messageId];
    if (current == null) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.removed, null);
    }
    if (current.isIncoming ||
        current.isDeleted ||
        current.contactPeerId != expectedContactPeerId ||
        !const <String>{'sending', 'failed'}.contains(current.status)) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.refused, current);
    }
    if (current.wireEnvelope != expectedEnvelope) {
      return _ordinaryResult(
        OutgoingOrdinaryMutationOutcome.preserved,
        current,
      );
    }
    return _applyOrdinary(current.copyWith(wireEnvelope: null));
  }

  @override
  Future<OutgoingOrdinaryMutationResult>
  quarantineUnsafeLegacyOutgoingEnvelope({
    required String messageId,
    required String expectedContactPeerId,
    required String expectedEnvelope,
    required bool isDeleteTombstone,
  }) async {
    final current = store[messageId];
    if (current == null) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.removed, null);
    }
    if (current.isIncoming ||
        current.contactPeerId != expectedContactPeerId ||
        current.isDeleted != isDeleteTombstone ||
        current.status != 'sent') {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.refused, current);
    }
    if (current.wireEnvelope != expectedEnvelope) {
      return _ordinaryResult(
        OutgoingOrdinaryMutationOutcome.preserved,
        current,
      );
    }
    return _applyOrdinary(
      current.copyWith(
        status: 'failed',
        transport: null,
        relayExpiresAt: null,
        custodyCheckedAt: null,
      ),
    );
  }

  OutgoingOrdinaryMutationResult _applyOrdinary(ConversationMessage message) {
    store[message.id] = message;
    _messageChangeController.add(message);
    return _ordinaryResult(OutgoingOrdinaryMutationOutcome.applied, message);
  }

  OutgoingOrdinaryMutationResult _ordinaryResult(
    OutgoingOrdinaryMutationOutcome outcome,
    ConversationMessage? message,
  ) => OutgoingOrdinaryMutationResult(outcome: outcome, message: message);
}

bool _sameConversationSnapshot(
  ConversationMessage left,
  ConversationMessage right,
) {
  final leftMap = left.toMap();
  final rightMap = right.toMap();
  return leftMap.length == rightMap.length &&
      leftMap.entries.every((entry) => rightMap[entry.key] == entry.value);
}

class _ManualRetryFakeMessageRepository extends FakeMessageRepository
    implements DirectManualUploadRetryRearmRepository {
  _ManualRetryFakeMessageRepository(this.mediaAttachmentRepo);

  final FakeMediaAttachmentRepository mediaAttachmentRepo;
  int manualRearmCalls = 0;

  @override
  Future<bool> rearmUploadRetryForManualRetry({
    required String messageId,
    required List<ManualUploadRetryAttachmentExpectation> attachments,
  }) async {
    manualRearmCalls++;
    final parent = await getMessage(messageId);
    if (parent == null || parent.isIncoming || parent.status != 'failed') {
      return false;
    }
    final persisted = await mediaAttachmentRepo.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.direct,
    );
    final unfinished = persisted
        .where((attachment) => attachment.downloadStatus != 'done')
        .toList(growable: false);
    if (unfinished.length != attachments.length) return false;
    for (final expected in attachments) {
      if (!unfinished.any(
        (attachment) =>
            attachment.id == expected.attachmentId &&
            attachment.localPath == expected.storedLocalPath &&
            attachment.downloadStatus == expected.downloadStatus &&
            (attachment.uploadRetryCount ?? 0) == expected.uploadRetryCount,
      )) {
        return false;
      }
    }

    await saveMessage(parent.copyWith(status: 'sending', wireEnvelope: null));
    for (final expected in attachments) {
      if (expected.downloadStatus != 'upload_failed') continue;
      final attachment = unfinished.singleWhere(
        (candidate) => candidate.id == expected.attachmentId,
      );
      await mediaAttachmentRepo.saveAttachment(
        attachment.copyWith(
          downloadStatus: 'upload_pending',
          uploadRetryCount: 0,
        ),
        owner: MediaOwnerLane.direct,
      );
    }
    return true;
  }
}

class _FakeIncomingConversationListener extends ChatMessageListener {
  final _incomingController = StreamController<ConversationMessage>.broadcast();

  _FakeIncomingConversationListener({
    required super.messageRepo,
    required super.contactRepo,
  }) : super(chatMessageStream: const Stream<ChatMessage>.empty());

  @override
  Stream<ConversationMessage> get incomingMessageStream =>
      _incomingController.stream;

  void emitIncomingMessage(ConversationMessage message) {
    _incomingController.add(message);
  }

  @override
  void dispose() {
    _incomingController.close();
    super.dispose();
  }
}

class _FakeReactionListener extends ReactionListener {
  final _reactionEmitter = StreamController<MessageReaction>.broadcast();
  final _reactionChangeEmitter = StreamController<ReactionChange>.broadcast();

  _FakeReactionListener({
    required super.messageRepo,
    required super.reactionRepo,
    required super.contactRepo,
    required super.bridge,
  }) : super(
         reactionStream: const Stream.empty(),
         getOwnMlKemSecretKey: () async => null,
       );

  @override
  Stream<MessageReaction> get incomingReactionStream => _reactionEmitter.stream;

  @override
  Stream<ReactionChange> get incomingReactionChangeStream =>
      _reactionChangeEmitter.stream;

  void emitReaction(MessageReaction reaction) {
    _reactionEmitter.add(reaction);
    _reactionChangeEmitter.add(ReactionChange.upsert(reaction));
  }

  void emitReactionChange(ReactionChange change) =>
      _reactionChangeEmitter.add(change);

  @override
  void dispose() {
    _reactionEmitter.close();
    _reactionChangeEmitter.close();
    super.dispose();
  }
}

class SlowInitialPageMessageRepository extends FakeMessageRepository {
  final Completer<void> firstPageGate = Completer<void>();

  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async {
    await firstPageGate.future;
    return super.getMessagesPage(
      contactPeerId,
      limit: limit,
      beforeTimestamp: beforeTimestamp,
    );
  }
}

class FakeP2PService implements P2PService {
  final bool localPeer;
  final bool localMediaResult;
  final StreamController<NodeState> _stateController =
      StreamController<NodeState>.broadcast();
  NodeState _currentState;
  int sendLocalMediaCallCount = 0;
  int sendMessageCallCount = 0;
  int storeInInboxCallCount = 0;
  String? lastLocalMediaId;
  String? lastLocalMediaPath;
  String? lastLocalMediaMime;

  FakeP2PService({
    this.localPeer = false,
    this.localMediaResult = false,
    NodeState? initialState,
  }) : _currentState =
           initialState ?? const NodeState(isStarted: true, peerId: 'me');

  @override
  NodeState get currentState => _currentState;

  void emitState(NodeState state) {
    _currentState = state;
    _stateController.add(state);
  }

  @override
  void dispose() {
    _stateController.close();
  }

  // FDC-04 (TC-04-09): record eager-warm calls fired on conversation open.
  final List<String> warmPeerCalls = [];

  @override
  Future<void> warmPeer(String peerId, {bool preferQuic = false}) async {
    warmPeerCalls.add(peerId);
  }

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
    bool preferQuic = false,
  }) async => true;

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async =>
      null;

  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async =>
      [];

  @override
  Future<bool> sendMessage(String peerId, String message) async {
    sendMessageCallCount++;
    return true;
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async => const SendMessageResult(sent: true, reply: 'received: ok');

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;

  @override
  Stream<NodeState> get stateStream => _stateController.stream;

  @override
  Future<bool> stopNode() async => true;

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    storeInInboxCallCount++;
    return false;
  }

  @override
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  bool isLocalPeer(String peerId) => localPeer;

  @override
  String? lastKnownGoodTransport(String peerId) => null;

  @override
  void recordSuccessfulTransport(String peerId, String transport) {}

  @override
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async => false;

  @override
  Stream<LocalMediaReady> get incomingLocalMediaStream => const Stream.empty();

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async => false;

  @override
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
    bool enc = false,
    String? encScheme,
  }) async {
    sendLocalMediaCallCount++;
    lastLocalMediaId = mediaId;
    lastLocalMediaPath = filePath;
    lastLocalMediaMime = mime;
    return localMediaResult;
  }

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      false;

  @override
  Future<void> warmBackground() async {}

  @override
  String? get lastRecoveryMethod => null;
}

/// 131: simulates the relay offline-inbox drain landing a new message in the
/// local DB. Each `drainOfflineInbox()` writes the next pending message
/// straight into [repo.store] (no `messageChanges` emit — mirroring a DB write
/// the open screen's no-replay live stream would miss), so only an explicit
/// re-fetch can surface it.
class DrainPersistsP2PService extends FakeP2PService {
  final FakeMessageRepository repo;
  final List<ConversationMessage> pending;
  int drainCallCount = 0;

  DrainPersistsP2PService({required this.repo, required this.pending});

  @override
  Future<void> drainOfflineInbox() async {
    drainCallCount++;
    if (pending.isNotEmpty) {
      final msg = pending.removeAt(0);
      repo.store[msg.id] = msg;
    }
  }
}

/// 131: like [DrainPersistsP2PService] but the FIRST drain blocks on [gate], so
/// a second recovery trigger (resume) can arrive while the first is in-flight.
class GatedDrainP2PService extends FakeP2PService {
  final FakeMessageRepository repo;
  final List<ConversationMessage> pending;
  Completer<void>? gate;
  int drainCallCount = 0;

  GatedDrainP2PService({required this.repo, required this.pending});

  @override
  Future<void> drainOfflineInbox() async {
    drainCallCount++;
    final g = gate;
    if (g != null && !g.isCompleted) {
      gate = null; // only the first drain is gated
      await g.future;
    }
    if (pending.isNotEmpty) {
      final msg = pending.removeAt(0);
      repo.store[msg.id] = msg;
    }
  }
}

/// 131: throws on the first [throwTimes] drains, then persists like
/// [DrainPersistsP2PService] — exercises the recovery error path + guard reset.
class ThrowingDrainP2PService extends FakeP2PService {
  final FakeMessageRepository repo;
  final List<ConversationMessage> pending;
  int throwTimes;
  int drainCallCount = 0;

  ThrowingDrainP2PService({
    required this.repo,
    required this.pending,
    this.throwTimes = 1,
  });

  @override
  Future<void> drainOfflineInbox() async {
    drainCallCount++;
    if (throwTimes > 0) {
      throwTimes--;
      throw StateError('drain failed');
    }
    if (pending.isNotEmpty) {
      final msg = pending.removeAt(0);
      repo.store[msg.id] = msg;
    }
  }
}

class TrackingLocalMediaP2PService extends FakeP2PService {
  final List<String> callOrder;

  TrackingLocalMediaP2PService({
    required this.callOrder,
    super.localPeer,
    super.localMediaResult,
  });

  @override
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
    bool enc = false,
    String? encScheme,
  }) async {
    callOrder.add('sendLocalMedia');
    return super.sendLocalMedia(
      peerId: peerId,
      filePath: filePath,
      mime: mime,
      mediaId: mediaId,
      fromPeerId: fromPeerId,
      durationMs: durationMs,
      waveform: waveform,
      filename: filename,
    );
  }
}

class InboxRetryP2PService extends FakeP2PService {
  InboxRetryP2PService({this.relayOnline = false});

  /// 185×187/192: a terminal-rung connectivity failure carrying an envelope
  /// (non-null failedMessage) is kept in the retriable self-healing lane —
  /// offline OR online — and never restores a failed draft. The restored-
  /// failed-draft retry tests therefore reach failed+restored via the sendFn-
  /// throws seam (catch handler), with the relay online so the row itself is
  /// a genuine failure, not the offline lane.
  final bool relayOnline;

  @override
  NodeState get currentState => relayOnline
      ? super.currentState.copyWith(relayState: 'online')
      : super.currentState;

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    storeInInboxCallCount++;
    return true;
  }
}

/// 228 TC-228-05B: records the lane and post-terminalization row statuses of
/// every [markUploadPendingAttachmentsFailedForMessage] call, so a widget
/// flow that afterwards deletes its own lane's rows can still prove the
/// direct row BECAME upload_failed (and that no sibling lane was touched).
class TerminalizationRecordingMediaAttachmentRepository
    extends FakeMediaAttachmentRepository {
  final List<MediaOwnerLane> terminalizedLanes = [];
  final Map<String, String> statusAfterTerminalization = {};

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    final count = await super.markUploadPendingAttachmentsFailedForMessage(
      messageId,
      owner: owner,
    );
    terminalizedLanes.add(owner);
    for (final attachment in await getAttachmentsForMessage(
      messageId,
      owner: owner,
    )) {
      statusAfterTerminalization[attachment.id] = attachment.downloadStatus;
    }
    return count;
  }
}

class _RecordingComposerUploadProjection
    implements DirectUploadRetryProjectionRepository {
  int callCount = 0;
  String? messageId;
  String? attachmentId;
  UploadMediaFailed? failure;

  @override
  Future<UploadRetryProjectionResult> projectUploadFailure({
    required String messageId,
    required String attachmentId,
    required UploadMediaFailed failure,
  }) async {
    callCount++;
    this.messageId = messageId;
    this.attachmentId = attachmentId;
    this.failure = failure;
    return const UploadRetryProjectionResult(
      state: UploadRetryProjectionState.retryPending,
    );
  }
}

class _TerminalComposerUploadProjection
    implements DirectUploadRetryProjectionRepository {
  @override
  Future<UploadRetryProjectionResult> projectUploadFailure({
    required String messageId,
    required String attachmentId,
    required UploadMediaFailed failure,
  }) async => const UploadRetryProjectionResult(
    state: UploadRetryProjectionState.terminal,
  );
}

void main() {
  late FakeUploadWakeLockDriver wakeLockDriver;

  setUp(() {
    wakeLockDriver = FakeUploadWakeLockDriver();
    UploadWakeLockController.debugReset(driver: wakeLockDriver);
  });

  tearDown(() {
    UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
  });

  ContactModel makeContact() {
    return ContactModel(
      peerId: '12D3KooWContactPeer123',
      publicKey: 'pub',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'Alice',
      signature: 'sig',
      scannedAt: '2026-02-11T10:00:00.000Z',
    );
  }

  IdentityModel makeIdentity() {
    return IdentityModel(
      peerId: '12D3KooWMyPeer123',
      publicKey: 'pub',
      privateKey: 'priv',
      mnemonic12:
          'one two three four five six seven eight nine ten eleven twelve',
      username: 'Me',
      createdAt: '2026-02-11T09:00:00.000Z',
      updatedAt: '2026-02-11T09:00:00.000Z',
    );
  }

  Future<void> seedPersistedIncumbentContact(
    MediaRepositoryRealDbFixture fixture,
  ) async {
    final contact = makeContact();
    await fixture.db.insert('contacts', <String, Object?>{
      'peer_id': contact.peerId,
      'public_key': contact.publicKey,
      'rendezvous': contact.rendezvous,
      'username': contact.username,
      'signature': contact.signature,
      'scanned_at': contact.scannedAt,
      'ml_kem_public_key': 'contact-ml-kem-public-key',
    });
  }

  Future<void> seedPersistedLinkedContact(
    MediaRepositoryRealDbFixture fixture,
  ) async {
    await seedPersistedIncumbentContact(fixture);
    final contact = makeContact();
    const linkedPeerId = '12D3KooWComposerLinkedDevice';
    const now = '2026-08-14T10:00:00.000Z';
    await fixture.db
        .insert('direct_contact_device_roster_metadata', <String, Object?>{
          'contact_account_peer_id': contact.peerId,
          'roster_initialized': 1,
          'legacy_target_state': 'active',
          'initialized_at': now,
          'legacy_revoked_at': null,
          'updated_at': now,
        });
    await fixture.db.insert('direct_contact_device_bindings', <String, Object?>{
      'contact_account_peer_id': contact.peerId,
      'device_id': 'tc366-composer-linked-device',
      'verified_account_signing_public_key': contact.publicKey,
      'transport_peer_id': linkedPeerId,
      'transport_public_key': 'tc366-composer-transport-key',
      'device_ml_kem_public_key': 'tc366-composer-linked-mlkem',
      'binding_fingerprint': '9' * 64,
      'state': 'active',
      'staged_at': now,
      'decided_at': now,
    });
  }

  group('Plan 343 reaction optimistic attempt authority', () {
    MessageReaction optimistic(
      ReactionOptimisticAttempt attempt,
      String emoji,
    ) => MessageReaction(
      id: attempt.optimisticReactionId,
      messageId: attempt.messageId,
      emoji: emoji,
      senderPeerId: 'self-peer',
      timestamp: '2026-08-07T12:00:00.000Z',
      createdAt: '2026-08-07T12:00:00.000Z',
    );

    test('guard unit accepts its still-current optimistic sentinel', () {
      final guard = ReactionOptimisticAttemptGuard();
      final attempt = guard.begin('message-1');

      expect(
        guard.canAdopt(
          attempt: attempt,
          senderPeerId: 'self-peer',
          visibleReactions: <MessageReaction>[optimistic(attempt, '👍')],
        ),
        isTrue,
      );
    });

    test('guard unit rejects an older generation after newer user intent', () {
      final removeGuard = ReactionOptimisticAttemptGuard();
      final beforeRemove = removeGuard.begin('message-1');
      removeGuard.begin('message-1');
      expect(
        removeGuard.canAdopt(
          attempt: beforeRemove,
          senderPeerId: 'self-peer',
          visibleReactions: <MessageReaction>[optimistic(beforeRemove, '👍')],
        ),
        isFalse,
      );

      final addGuard = ReactionOptimisticAttemptGuard();
      final olderAdd = addGuard.begin('message-1');
      final newerAdd = addGuard.begin('message-1');
      final visible = <MessageReaction>[optimistic(newerAdd, '🔥')];
      expect(
        addGuard.canAdopt(
          attempt: olderAdd,
          senderPeerId: 'self-peer',
          visibleReactions: visible,
        ),
        isFalse,
      );
      expect(
        addGuard.canAdopt(
          attempt: newerAdd,
          senderPeerId: 'self-peer',
          visibleReactions: visible,
        ),
        isTrue,
      );
    });
  });

  // 112 Phase 4: the real prepareEncryptedMediaArtifact does file I/O that
  // cannot complete inside the testWidgets fake-async zone (deadlocks at
  // the 10-min timeout). All widget tests get this SYNC-I/O stub so the
  // LAN encrypt-once leg stays deterministic.
  Future<EncryptedMediaArtifact> syncPrepareEncryptedArtifactStub({
    required Bridge bridge,
    required String localFilePath,
  }) async {
    final encryptedPath = '$localFilePath.enc';
    File(localFilePath).copySync(encryptedPath);
    return EncryptedMediaArtifact(
      encryptedPath: encryptedPath,
      keyBase64: 'stub-blob-key',
      nonce: 'stub-blob-nonce',
      scheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      contentHash: 'stub-content-hash',
      plaintextSize: File(localFilePath).lengthSync(),
    );
  }

  PreparedDirectMediaBlobCustodyCoordinator strictComposerCoordinator({
    required DirectMediaBlobCustodyRepository repository,
    required Directory artifactRoot,
    required DirectMediaBlobStrictUploadFn strictUpload,
  }) {
    return PreparedDirectMediaBlobCustodyCoordinator(
      repository: repository,
      artifactStore: DirectMediaBlobArtifactStore(
        documentsDirectoryProvider: () async => artifactRoot,
      ),
      prepareArtifact:
          ({required Bridge bridge, required String localFilePath}) async {
            final bytes = File(localFilePath).readAsBytesSync();
            final encryptedPath = '$localFilePath.plan347-test.enc';
            File(encryptedPath).writeAsBytesSync(bytes, flush: true);
            return EncryptedMediaArtifact(
              encryptedPath: encryptedPath,
              keyBase64: 'plan347-test-key-$localFilePath',
              nonce: 'plan347-test-nonce-$localFilePath',
              scheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
              contentHash: sha256.convert(bytes).toString(),
              plaintextSize: bytes.length,
            );
          },
      strictUpload: strictUpload,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeIdentityRepository identityRepo,
    required MessageRepository messageRepo,
    required ChatMessageListener chatListener,
    required SendChatMessageFn sendFn,
    SendPrivateMediaFanoutChatMessageFn? sendPrivateMediaFanoutFn,
    EditChatMessageFn? editFn,
    DeleteMessageForMeFn? deleteForMeFn,
    DeleteMessageForEveryoneFn? deleteForEveryoneFn,
    P2PService? p2pService,
    Bridge? bridge,
    LegacyTestUploadMediaFn? uploadMediaFn,
    UploadMediaFn? typedUploadMediaFn,
    DirectUploadRetryProjectionRepository? uploadRetryProjectionRepo,
    SendVoiceMessageFn? sendVoiceMessageFn,
    MediaAttachmentRepository? mediaAttachmentRepo,
    ContactRepository? contactRepo,
    ReactionRepository? reactionRepo,
    ReactionListener? reactionListener,
    SendReactionFn? sendReactionFn,
    RemoveReactionFn? removeReactionFn,
    MediaFileManager? mediaFileManager,
    FakeAudioRecorderService? audioRecorderService,
    MicPermissionGateway? micPermissionGateway,
    ImageProcessor? imageProcessor,
    MediaPicker? mediaPicker,
    DownloadMediaFn? downloadMediaFn,
    String? initialText,
    List<File>? initialAttachments,
    List<PendingComposerMedia>? initialPendingMedia,
    List<ConversationMessage>? initialMessages,
    ImageQualityPreference qualityPreference =
        ImageQualityPreference.compressed,
    ImageQualityPreference videoQualityPreference =
        ImageQualityPreference.compressed,
    int maxAttachmentBudgetBytes = kGeneralMediaAttachmentBudgetBytes,
    DateTime? notificationTappedAt,
    ThemeData? themeOverride,
    MediaAutoDownloadDecider? autoDownloadDecider,
    ReceivedMediaActionController? receivedMediaActionController,
    PreparedDirectMediaBlobCustodyCoordinator?
    preparedDirectMediaBlobCustodyCoordinator,
    DirectConversationModalityGate? modalityGate,
    DirectEventFanoutAuthoring? directEventFanout,
    DirectLinkedMediaFanoutSelector? directLinkedMediaFanoutSelector,
    bool? directMediaBlobCustodyClientEnabled,
    bool? directLinkedEventFanoutEnabled,
    ActiveConversationTracker? conversationTracker,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: themeOverride,
        home: ConversationWired(
          contact: makeContact(),
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatMessageListener: chatListener,
          p2pService: p2pService ?? FakeP2PService(),
          notificationTappedAt: notificationTappedAt,
          bridge: bridge,
          sendChatMessageFn: sendFn,
          sendPrivateMediaFanoutChatMessageFn:
              sendPrivateMediaFanoutFn ?? sendChatMessage,
          directEventFanout: directEventFanout,
          directLinkedMediaFanoutSelector:
              directLinkedMediaFanoutSelector ??
              const DirectLinkedMediaFanoutSelector(),
          directMediaBlobCustodyClientEnabled:
              directMediaBlobCustodyClientEnabled ??
              kDirectMediaBlobCustodyClientEnabled,
          directLinkedEventFanoutEnabled:
              directLinkedEventFanoutEnabled ?? kDirectLinkedEventFanoutEnabled,
          editChatMessageFn: editFn ?? editChatMessage,
          deleteMessageForMeFn: deleteForMeFn ?? deleteMessageForMe,
          deleteMessageForEveryoneFn:
              deleteForEveryoneFn ?? deleteMessageForEveryone,
          uploadMediaFn:
              typedUploadMediaFn ??
              (uploadMediaFn == null
                  ? uploadMedia
                  : adaptLegacyTestUploadMediaFn(uploadMediaFn)),
          uploadRetryProjectionRepo: uploadRetryProjectionRepo,
          sendVoiceMessageFn: sendVoiceMessageFn ?? sendVoiceMessage,
          prepareEncryptedMediaArtifactFn: syncPrepareEncryptedArtifactStub,
          contactRepo: contactRepo,
          reactionRepo: reactionRepo,
          reactionListener: reactionListener,
          sendReactionFn: sendReactionFn ?? sendReaction,
          removeReactionFn: removeReactionFn ?? removeReaction,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
          audioRecorderService: audioRecorderService,
          micPermissionGateway:
              micPermissionGateway ?? FakeMicPermissionGateway(),
          imageProcessor: imageProcessor,
          mediaPicker: mediaPicker,
          downloadMediaFn: downloadMediaFn ?? downloadMedia,
          qualityPreference: qualityPreference,
          videoQualityPreference: videoQualityPreference,
          initialText: initialText,
          initialMessages: initialMessages,
          initialAttachments: initialAttachments,
          initialPendingMedia: initialPendingMedia,
          maxAttachmentBudgetBytes: maxAttachmentBudgetBytes,
          conversationTracker: conversationTracker,
          autoDownloadDecider: autoDownloadDecider,
          receivedMediaActionController: receivedMediaActionController,
          preparedDirectMediaBlobCustodyCoordinator:
              preparedDirectMediaBlobCustodyCoordinator,
          modalityGate: modalityGate ?? const DirectConversationModalityGate(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('TC-393-01 direct read requires resumed exact tracking', (
    tester,
  ) async {
    ConversationMessage unread(String id) {
      const timestamp = '2026-08-21T08:00:00.000Z';
      return ConversationMessage(
        id: id,
        contactPeerId: makeContact().peerId,
        senderPeerId: makeContact().peerId,
        text: 'Unread notification lifecycle row',
        timestamp: timestamp,
        status: 'delivered',
        isIncoming: true,
        createdAt: timestamp,
      );
    }

    Future<void> mount({
      required InMemoryMessageRepository repository,
      ActiveConversationTracker? tracker,
    }) => pumpScreen(
      tester,
      identityRepo: FakeIdentityRepository(makeIdentity()),
      messageRepo: repository,
      chatListener: ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: repository,
        contactRepo: FakeContactRepository(),
      ),
      sendFn: _instantSuccessSendFn,
      bridge: FakeBridge(),
      conversationTracker: tracker,
    );

    final trackedRepository = InMemoryMessageRepository();
    await trackedRepository.saveMessage(unread('tc-393-paused'));
    final tracker = ActiveConversationTracker();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    await mount(repository: trackedRepository, tracker: tracker);
    expect(
      await trackedRepository.getUnreadCountForContact(makeContact().peerId),
      1,
      reason: 'a mounted but paused conversation cannot consume unread state',
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 800));
    expect(tracker.isViewing(makeContact().peerId), isTrue);
    expect(
      await trackedRepository.getUnreadCountForContact(makeContact().peerId),
      0,
      reason: 'resume plus the exact tracked peer marks once',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final untrackedRepository = InMemoryMessageRepository();
    await untrackedRepository.saveMessage(unread('tc-393-untracked'));
    await mount(repository: untrackedRepository);
    await tester.pump(const Duration(milliseconds: 1));
    expect(
      await untrackedRepository.getUnreadCountForContact(makeContact().peerId),
      1,
      reason: 'an absent tracker is unknown authority and must fail closed',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  group('Plan 343 wired reaction attempt authority', () {
    ConversationMessage reactionMessage() => ConversationMessage(
      id: 'message-343',
      contactPeerId: makeContact().peerId,
      senderPeerId: makeContact().peerId,
      text: 'react to me',
      timestamp: '2026-08-07T11:59:00.000Z',
      status: 'delivered',
      isIncoming: true,
      createdAt: '2026-08-07T11:59:00.000Z',
    );

    MessageReaction committedReaction(String id, String emoji) =>
        MessageReaction(
          id: id,
          messageId: 'message-343',
          emoji: emoji,
          senderPeerId: makeIdentity().peerId,
          timestamp: '2026-08-07T12:00:00.000Z',
          createdAt: '2026-08-07T12:00:00.000Z',
        );

    Future<void> pumpReactionHarness(
      WidgetTester tester, {
      required SendReactionFn sendReactionFn,
      required RemoveReactionFn removeReactionFn,
    }) async {
      final messageRepo = FakeMessageRepository();
      final message = reactionMessage();
      messageRepo.store[message.id] = message;
      await pumpScreen(
        tester,
        identityRepo: FakeIdentityRepository(makeIdentity()),
        messageRepo: messageRepo,
        chatListener: ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        ),
        sendFn: _instantSuccessSendFn,
        bridge: FakeBridge(),
        reactionRepo: FakeReactionRepository(),
        initialMessages: <ConversationMessage>[message],
        sendReactionFn: sendReactionFn,
        removeReactionFn: removeReactionFn,
      );
    }

    testWidgets(
      'TC-343-06b wired caller adopts current committed ADD for durable diagnostics',
      (tester) async {
        for (final diagnostic in <SendReactionResult>[
          SendReactionResult.nodeNotRunning,
          SendReactionResult.sendFailed,
        ]) {
          final committed = committedReaction(
            'committed-${diagnostic.name}',
            '👍',
          );

          Future<(SendReactionResult, MessageReaction?)> sendStub({
            required P2PService p2pService,
            required Bridge bridge,
            required ReactionRepository reactionRepo,
            required String targetPeerId,
            required String messageId,
            required String emoji,
            required String senderPeerId,
            required String recipientMlKemPublicKey,
            DirectEventFanoutAuthoring? directEventFanout,
          }) async => (diagnostic, committed);

          Future<RemoveReactionResult> removeStub({
            required P2PService p2pService,
            required Bridge bridge,
            required ReactionRepository reactionRepo,
            required String targetPeerId,
            required String messageId,
            required String emoji,
            required String senderPeerId,
            required String recipientMlKemPublicKey,
            DirectEventFanoutAuthoring? directEventFanout,
          }) async => RemoveReactionResult.success;

          await pumpReactionHarness(
            tester,
            sendReactionFn: sendStub,
            removeReactionFn: removeStub,
          );

          tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .onReactionSelected!
              .call('message-343', '👍');
          await tester.pump();

          final visible = tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .reactions['message-343']!;
          expect(visible, hasLength(1));
          expect(visible.single.id, committed.id);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );

    testWidgets(
      'TC-343-06c late older ADD cannot overwrite newer REMOVE or ADD intent',
      (tester) async {
        final addCompletions =
            <Completer<(SendReactionResult, MessageReaction?)>>[
              Completer<(SendReactionResult, MessageReaction?)>(),
              Completer<(SendReactionResult, MessageReaction?)>(),
            ];
        var addCalls = 0;

        Future<(SendReactionResult, MessageReaction?)> orderedSend({
          required P2PService p2pService,
          required Bridge bridge,
          required ReactionRepository reactionRepo,
          required String targetPeerId,
          required String messageId,
          required String emoji,
          required String senderPeerId,
          required String recipientMlKemPublicKey,
          DirectEventFanoutAuthoring? directEventFanout,
        }) => addCompletions[addCalls++].future;

        Future<RemoveReactionResult> immediateRemove({
          required P2PService p2pService,
          required Bridge bridge,
          required ReactionRepository reactionRepo,
          required String targetPeerId,
          required String messageId,
          required String emoji,
          required String senderPeerId,
          required String recipientMlKemPublicKey,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async => RemoveReactionResult.success;

        await pumpReactionHarness(
          tester,
          sendReactionFn: orderedSend,
          removeReactionFn: immediateRemove,
        );
        var screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        screen.onReactionSelected!.call('message-343', '👍');
        await tester.pump();
        screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        screen.onReactionSelected!.call('message-343', '🔥');
        await tester.pump();

        addCompletions.first.complete((
          SendReactionResult.success,
          committedReaction('older-add', '👍'),
        ));
        await tester.pump();
        var visible = tester
            .widget<ConversationScreen>(find.byType(ConversationScreen))
            .reactions['message-343']!;
        expect(visible.single.emoji, '🔥');
        expect(visible.single.id, isNot('older-add'));

        addCompletions.last.complete((
          SendReactionResult.success,
          committedReaction('newer-add', '🔥'),
        ));
        await tester.pump();
        visible = tester
            .widget<ConversationScreen>(find.byType(ConversationScreen))
            .reactions['message-343']!;
        expect(visible.single.id, 'newer-add');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        final delayedAdd = Completer<(SendReactionResult, MessageReaction?)>();
        final removeCompletion = Completer<RemoveReactionResult>();

        Future<(SendReactionResult, MessageReaction?)> delayedSend({
          required P2PService p2pService,
          required Bridge bridge,
          required ReactionRepository reactionRepo,
          required String targetPeerId,
          required String messageId,
          required String emoji,
          required String senderPeerId,
          required String recipientMlKemPublicKey,
          DirectEventFanoutAuthoring? directEventFanout,
        }) => delayedAdd.future;

        Future<RemoveReactionResult> delayedRemove({
          required P2PService p2pService,
          required Bridge bridge,
          required ReactionRepository reactionRepo,
          required String targetPeerId,
          required String messageId,
          required String emoji,
          required String senderPeerId,
          required String recipientMlKemPublicKey,
          DirectEventFanoutAuthoring? directEventFanout,
        }) => removeCompletion.future;

        await pumpReactionHarness(
          tester,
          sendReactionFn: delayedSend,
          removeReactionFn: delayedRemove,
        );
        screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        screen.onReactionSelected!.call('message-343', '👍');
        await tester.pump();
        screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        screen.onReactionSelected!.call('message-343', '👍');
        await tester.pump();
        expect(
          tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .reactions['message-343'],
          isEmpty,
        );

        delayedAdd.complete((
          SendReactionResult.success,
          committedReaction('removed-add', '👍'),
        ));
        await tester.pump();
        expect(
          tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .reactions['message-343'],
          isEmpty,
        );
        removeCompletion.complete(RemoveReactionResult.success);
        await tester.pump();
      },
    );
  });

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    int maxPumps = 20,
    Duration step = const Duration(milliseconds: 100),
  }) async {
    for (var i = 0; i < maxPumps; i++) {
      if (condition()) {
        await tester.pump(const Duration(milliseconds: 500));
        return;
      }
      await tester.pump(step);
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(condition(), isTrue);
  }

  Future<void> pumpUntilAsyncIo(
    WidgetTester tester,
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 5),
    Duration pollInterval = const Duration(milliseconds: 10),
  }) async {
    final stopwatch = Stopwatch()..start();
    while (!condition() && stopwatch.elapsed < timeout) {
      await tester.runAsync(() => Future<void>.delayed(pollInterval));
      await tester.pump(pollInterval);
    }
    expect(condition(), isTrue);
  }

  void installPrivateMediaProtectionEventChannelStub(WidgetTester tester) {
    final previousFlowEventLogging = flowEventLoggingEnabled;
    flowEventLoggingEnabled = false;
    addTearDown(() => flowEventLoggingEnabled = previousFlowEventLogging);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMessageHandler(
      kPrivateMediaProtectionEventChannel,
      (_) async => const StandardMethodCodec().encodeSuccessEnvelope(null),
    );
    addTearDown(
      () => messenger.setMockMessageHandler(
        kPrivateMediaProtectionEventChannel,
        null,
      ),
    );
  }

  group('FDC-04 warm on open', () {
    // TC-04-09: opening the conversation screen fires warmPeer(contact.peerId)
    // exactly once (fire-and-forget), on EVERY open. Mutation: remove the warm
    // call from initState → re-red.
    testWidgets('TC-04-09: conversation open fires warmPeer once', (
      tester,
    ) async {
      final messageRepo = FakeMessageRepository();
      final p2p = FakeP2PService();
      await pumpScreen(
        tester,
        identityRepo: FakeIdentityRepository(makeIdentity()),
        messageRepo: messageRepo,
        chatListener: ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        ),
        sendFn: _instantSuccessSendFn,
        p2pService: p2p,
      );
      expect(p2p.warmPeerCalls, [makeContact().peerId]);
    });
  });

  group('ConversationWired optimistic send', () {
    Future<void> runStrictComposerScenario(WidgetTester tester) async {
      installPrivateMediaProtectionEventChannelStub(tester);
      flowEventLoggingEnabled = true;
      UploadWakeLockController.debugReset(
        driver: _SynchronousUploadWakeLockDriver(),
      );
      final tempDir = Directory.systemTemp.createTempSync(
        'conv_347_strict_composer_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final first = File('${tempDir.path}/first.png')
        ..writeAsBytesSync(_tinyPngBytes);
      final second = File('${tempDir.path}/second.png')
        ..writeAsBytesSync(<int>[..._tinyPngBytes, 0x01]);
      final repository = _StrictComposerMediaRepository();
      final DirectMediaBlobCustodyRepository blobRepository = repository;
      final messages = FakeMessageRepository();
      final manager = TrackingDurableConversationMediaFileManager(tempDir);
      final networkOrder = <String>[];
      var firstNetworkSawCompleteGeneration = false;
      var legacyUploadCalls = 0;
      var sendCalls = 0;
      List<MediaAttachment>? sentAttachments;
      final scenarioBridge = FakeBridge();

      final coordinator = PreparedDirectMediaBlobCustodyCoordinator(
        repository: blobRepository,
        artifactStore: DirectMediaBlobArtifactStore(
          documentsDirectoryProvider: () async => tempDir,
        ),
        prepareArtifact:
            ({required Bridge bridge, required String localFilePath}) async {
              final ciphertextPath = '$localFilePath.strict.enc';
              final bytes = File(localFilePath).readAsBytesSync();
              File(ciphertextPath).writeAsBytesSync(bytes, flush: true);
              return EncryptedMediaArtifact(
                encryptedPath: ciphertextPath,
                keyBase64: 'strict-composer-key-$localFilePath',
                nonce: 'strict-composer-nonce-$localFilePath',
                scheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                contentHash: sha256.convert(bytes).toString(),
                plaintextSize: bytes.length,
              );
            },
        strictUpload:
            ({
              required bridge,
              required attachmentId,
              required recipientPeerId,
              required ciphertextPath,
              required contentHash,
              required ciphertextSize,
            }) async {
              final rows = await blobRepository
                  .loadDirectMediaBlobCustodyByStates(
                    <DirectMediaBlobCustodyState>{
                      DirectMediaBlobCustodyState.outgoingPrepared,
                      DirectMediaBlobCustodyState.outgoingStored,
                    },
                  );
              expect(rows, hasLength(2));
              final durableAttachments = await repository
                  .getAttachmentsForMessage(
                    rows.first.messageId,
                    owner: MediaOwnerLane.direct,
                  );
              expect(durableAttachments, hasLength(2));
              expect(
                durableAttachments.every(
                  (attachment) =>
                      attachment.downloadStatus == 'upload_pending' &&
                      attachment.contentHash != null &&
                      attachment.encryptionKeyBase64 != null &&
                      attachment.encryptionNonce != null,
                ),
                isTrue,
              );
              if (networkOrder.isEmpty) {
                firstNetworkSawCompleteGeneration = true;
              }
              networkOrder.add('strict:$attachmentId');
              expect(
                sha256
                    .convert(File(ciphertextPath).readAsBytesSync())
                    .toString(),
                contentHash,
              );
              return <String, dynamic>{
                'ok': true,
                'id': attachmentId,
                'storeStatus': 'stored',
                'custodyKind': 'direct_media_blob_v1',
                'custodyContract': 'ack_or_expiry_v1',
                'contentHash': contentHash,
                'size': ciphertextSize,
                'mime': 'application/octet-stream',
                'expiresAtMs': 2000000000000 + networkOrder.length,
                'custodyRelayPeerId': 'relay-347',
              };
            },
      );

      await pumpScreen(
        tester,
        identityRepo: FakeIdentityRepository(makeIdentity()),
        messageRepo: messages,
        chatListener: ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messages,
          contactRepo: FakeContactRepository(),
        ),
        sendFn:
            ({
              required p2pService,
              required messageRepo,
              required targetPeerId,
              required text,
              required senderPeerId,
              required senderUsername,
              messageId,
              required bool preassignedMessageIdIsFresh,
              timestamp,
              bridge,
              recipientMlKemPublicKey,
              quotedMessageId,
              mediaAttachments,
              privateMediaPolicy,
              mediaAttachmentRepo,
              transportMetrics,
              directEventFanout,
            }) async {
              sendCalls++;
              networkOrder.add('envelope');
              sentAttachments = List<MediaAttachment>.from(
                mediaAttachments ?? const <MediaAttachment>[],
              );
              return (
                SendChatMessageResult.success,
                await messageRepo.getMessage(messageId!),
              );
            },
        bridge: scenarioBridge,
        mediaAttachmentRepo: repository,
        mediaFileManager: manager,
        typedUploadMediaFn:
            ({
              required bridge,
              required localFilePath,
              required mime,
              required recipientPeerId,
              mediaFileManager,
              width,
              height,
              durationMs,
              waveform,
              allowedPeers,
              blobId,
              deleteSourceWhenDone = false,
              preparedArtifact,
            }) async {
              legacyUploadCalls++;
              return const UploadMediaFailed(
                stage: UploadMediaStage.transport,
                disposition: UploadMediaDisposition.terminal,
                errorCode: 'LEGACY_UPLOAD_MUST_NOT_RUN',
              );
            },
        initialAttachments: <File>[first, second],
        preparedDirectMediaBlobCustodyCoordinator: coordinator,
      );
      await tester.enterText(find.byType(TextField), 'Strict pair');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        final sendDeadline = Stopwatch()..start();
        while (sendCalls == 0 &&
            legacyUploadCalls == 0 &&
            sendDeadline.elapsed < const Duration(seconds: 5)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(
        legacyUploadCalls,
        0,
        reason:
            'strict selection fell through; blobRows=${repository.rows.length}',
      );
      expect(
        sendCalls,
        1,
        reason:
            'strict coordinator retained/refused; blobRows='
            '${repository.rows.values.map((row) => row.state.name).toList()} '
            'networkOrder=$networkOrder parentSaves='
            '${messages.saveMessageCallCount} mediaSaves='
            '${repository.allSavedAttachments.length} copies='
            '${manager.copyCalls} bridge=${scenarioBridge.commandLog}',
      );
      expect(firstNetworkSawCompleteGeneration, isTrue);
      expect(networkOrder, hasLength(3));
      expect(
        networkOrder.take(2).every((entry) => entry.startsWith('strict:')),
        isTrue,
      );
      expect(networkOrder.last, 'envelope');
      expect(sentAttachments, hasLength(2));
      expect(
        sentAttachments!.every(
          (attachment) =>
              attachment.downloadStatus == 'done' &&
              attachment.blobCustody?.isValid == true,
        ),
        isTrue,
      );
      final messageId = sentAttachments!.first.messageId;
      final rows = await blobRepository.loadDirectMediaBlobCustodyForMessage(
        messageId,
      );
      expect(rows, hasLength(2));
      expect(
        rows.every(
          (row) => row.state == DirectMediaBlobCustodyState.outgoingStored,
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    testWidgets(
      'TC-347-02e complete strict manifest publishes before first network',
      runStrictComposerScenario,
      skip: !kDirectMediaBlobCustodyClientEnabled,
    );

    testWidgets(
      'TC-347-08 prepared ordinary composer selects strict blob coordinator',
      runStrictComposerScenario,
      skip: !kDirectMediaBlobCustodyClientEnabled,
    );

    Future<void> runFanoutRoutedComposerScenario(
      WidgetTester tester, {
      required bool selectorOn,
      bool retryAfterInitialSendFailure = false,
    }) async {
      final tempDir = Directory.systemTemp.createTempSync(
        'composer_fanout_route_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final contact = makeContact();
      const linkedTransport = 'peer-composer-linked-device';
      final snapshot = DirectContactFanoutSnapshot(
        contactAccountPeerId: contact.peerId,
        contactAccountSigningPublicKey: 'composer-signing-key',
        rosterInitialized: true,
        targets: <DirectContactFanoutTargetFact>[
          DirectContactFanoutTargetFact(
            peerId: contact.peerId,
            mlKemPublicKey: 'mlkem-legacy-account',
            isLegacyAccountTarget: true,
            fingerprint: 'f' * 64,
          ),
          DirectContactFanoutTargetFact(
            peerId: linkedTransport,
            mlKemPublicKey: 'mlkem-composer-a',
            isLegacyAccountTarget: false,
            fingerprint: 'e' * 64,
            deviceId: 'composer-device-a',
            transportPublicKey: 'transport-key-composer-a',
          ),
        ],
      );
      final messages = FakeMessageRepository();
      final repository = _FanoutComposerMediaRepository(
        snapshot: snapshot,
        // The production v114 transaction publishes this marker with the
        // linked rows. Keep the in-memory repository contract faithful so the
        // same durable parent can be handed to the restart retrier below.
        onFreshFanoutGenerationPublished: messages.saveMessage,
      );

      final strictUploadRecipients = <String>[];
      final coordinator = PreparedDirectMediaBlobCustodyCoordinator(
        repository: repository,
        artifactStore: DirectMediaBlobArtifactStore(
          documentsDirectoryProvider: () async => tempDir,
        ),
        prepareArtifact:
            ({required Bridge bridge, required String localFilePath}) async {
              final ciphertextPath = '$localFilePath.strict.enc';
              final bytes = File(localFilePath).readAsBytesSync();
              File(ciphertextPath).writeAsBytesSync(bytes, flush: true);
              return EncryptedMediaArtifact(
                encryptedPath: ciphertextPath,
                keyBase64: 'fanout-key',
                nonce: 'fanout-nonce',
                scheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                contentHash: sha256.convert(bytes).toString(),
                plaintextSize: bytes.length,
              );
            },
        strictUpload:
            ({
              required bridge,
              required attachmentId,
              required recipientPeerId,
              required ciphertextPath,
              required contentHash,
              required ciphertextSize,
            }) async {
              strictUploadRecipients.add(recipientPeerId);
              return <String, dynamic>{
                'ok': true,
                'id': attachmentId,
                'storeStatus': 'stored',
                'custodyKind': 'direct_media_blob_v1',
                'custodyContract': 'ack_or_expiry_v1',
                'contentHash': contentHash,
                'size': ciphertextSize,
                'mime': 'application/octet-stream',
                'expiresAtMs': 2000000000000 + strictUploadRecipients.length,
                'custodyRelayPeerId': 'relay-362',
              };
            },
      );
      // The route decision consults only the selector and the LIVE persisted
      // snapshot; every other authoring delegate must stay unreachable.
      Never neverCalled() =>
          throw StateError('route decision must not author events');
      final authoring = DirectEventFanoutAuthoring(
        selector: selectorOn
            ? const DirectLinkedEventFanoutSelector.enabled()
            : const DirectLinkedEventFanoutSelector.disabled(),
        linkedOrigin: false,
        senderTransportPeerId: 'my-peer-id-12345',
        readSnapshot: repository.readDirectContactFanoutSnapshotForMedia,
        encrypt:
            ({required recipientMlKemPublicKey, required plaintext}) async =>
                neverCalled(),
        loadTextSiblings: (_) async => neverCalled(),
        stageTextFanout:
            ({
              required stagedRow,
              required messageId,
              required contactAccountPeerId,
              required senderTransportPeerId,
              required expectedSnapshot,
              required candidates,
            }) async => neverCalled(),
        loadEventSiblings: (_) async => neverCalled(),
        stageMutationFanout:
            ({
              required expectedRow,
              required stagedRow,
              required kind,
              required eventId,
              required parentMessageId,
              required contactAccountPeerId,
              required senderTransportPeerId,
              required expectedSnapshot,
              required candidates,
            }) async => neverCalled(),
        stageReactionFanout:
            ({
              required reactionRow,
              required action,
              required parentMessageId,
              required contactAccountPeerId,
              required senderTransportPeerId,
              required expectedSnapshot,
              required candidates,
            }) async => neverCalled(),
      );

      var sendCalls = 0;
      var legacyUploadCalls = 0;
      final source = File('${tempDir.path}/fanout.jpg')
        ..writeAsBytesSync(List<int>.generate(64, (index) => index));

      await pumpScreen(
        tester,
        identityRepo: FakeIdentityRepository(makeIdentity()),
        messageRepo: messages,
        chatListener: ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messages,
          contactRepo: FakeContactRepository(),
        ),
        sendFn:
            ({
              required p2pService,
              required messageRepo,
              required targetPeerId,
              required text,
              required senderPeerId,
              required senderUsername,
              messageId,
              required bool preassignedMessageIdIsFresh,
              timestamp,
              bridge,
              recipientMlKemPublicKey,
              quotedMessageId,
              mediaAttachments,
              privateMediaPolicy,
              mediaAttachmentRepo,
              transportMetrics,
              directEventFanout,
            }) async {
              sendCalls++;
              if (retryAfterInitialSendFailure) {
                return (SendChatMessageResult.sendFailed, null);
              }
              return (
                SendChatMessageResult.success,
                await messageRepo.getMessage(messageId!),
              );
            },
        bridge: FakeBridge(),
        mediaAttachmentRepo: repository,
        mediaFileManager: TrackingDurableConversationMediaFileManager(tempDir),
        typedUploadMediaFn:
            ({
              required bridge,
              required localFilePath,
              required mime,
              required recipientPeerId,
              mediaFileManager,
              width,
              height,
              durationMs,
              waveform,
              allowedPeers,
              blobId,
              deleteSourceWhenDone = false,
              preparedArtifact,
            }) async {
              legacyUploadCalls++;
              return const UploadMediaFailed(
                stage: UploadMediaStage.transport,
                disposition: UploadMediaDisposition.terminal,
                errorCode: 'LEGACY_UPLOAD_MUST_NOT_RUN',
              );
            },
        initialAttachments: <File>[source],
        preparedDirectMediaBlobCustodyCoordinator: coordinator,
        directEventFanout: authoring,
        directLinkedMediaFanoutSelector: selectorOn
            ? const DirectLinkedMediaFanoutSelector.enabled()
            : const DirectLinkedMediaFanoutSelector.disabled(),
        directMediaBlobCustodyClientEnabled: true,
        directLinkedEventFanoutEnabled: true,
      );
      await tester.enterText(find.byType(TextField), 'Fanout route');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        final deadline = Stopwatch()..start();
        while (sendCalls == 0 &&
            deadline.elapsed < const Duration(seconds: 5)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          if (!selectorOn && deadline.elapsed.inMilliseconds > 1500) break;
        }
        if (selectorOn && retryAfterInitialSendFailure) {
          while (messages.store.values.every(
                (message) => message.status != 'failed',
              ) &&
              deadline.elapsed < const Duration(seconds: 5)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        }
      });
      await tester.pump();

      expect(legacyUploadCalls, 0);
      if (selectorOn) {
        // 362: the fresh generation reached the ALL-TARGET owner — one
        // upload per persisted target in snapshot order, linked rows for
        // both targets, and the canonical send proceeded.
        expect(strictUploadRecipients.toSet(), <String>{
          contact.peerId,
          linkedTransport,
        });
        expect(sendCalls, 1);
        expect(repository.fanoutRows.values, hasLength(2));
        expect(
          repository.fanoutRows.values.every(
            (row) =>
                row.contactAccountPeerId == contact.peerId &&
                row.recipientMlKemPublicKey != null &&
                row.state == DirectMediaBlobCustodyState.outgoingStored,
          ),
          isTrue,
        );
        if (retryAfterInitialSendFailure) {
          final messageId = repository.fanoutRows.values.first.messageId;
          final failedParent = messages.store[messageId];
          expect(failedParent?.status, 'failed');
          expect(failedParent?.directEventFanoutGenerationId, messageId);

          final snapshotReadsBeforeRestart = repository.snapshotReads;
          repository
            ..throwOnSnapshotRead = true
            ..applyFanoutInboxStage = true;
          final retryBridge = FakeBridge();
          final retryP2p = FakeP2PService(
            initialState: NodeState(
              isStarted: true,
              peerId: makeIdentity().peerId,
            ),
          );
          var retryLegacyUploadCalls = 0;
          late int retried;
          await tester.runAsync(() async {
            retried = await retryIncompleteUploads(
              mediaAttachmentRepo: repository,
              messageRepo: messages,
              bridge: retryBridge,
              p2pService: retryP2p,
              identityRepo: FakeIdentityRepository(makeIdentity()),
              contactRepo: FakeContactRepository(),
              uploadMediaFn:
                  ({
                    required bridge,
                    required localFilePath,
                    required mime,
                    required recipientPeerId,
                    mediaFileManager,
                    width,
                    height,
                    durationMs,
                    waveform,
                    allowedPeers,
                    blobId,
                    deleteSourceWhenDone = false,
                    preparedArtifact,
                  }) async {
                    retryLegacyUploadCalls++;
                    return const UploadMediaFailed(
                      stage: UploadMediaStage.transport,
                      disposition: UploadMediaDisposition.terminal,
                      errorCode: 'LEGACY_UPLOAD_MUST_NOT_RUN',
                    );
                  },
              directMediaBlobCustodyCoordinator: coordinator,
              restrictToMessageIds: <String>{messageId},
            );
          });

          expect(retried, 1);
          expect(retryLegacyUploadCalls, 0);
          expect(repository.snapshotReads, snapshotReadsBeforeRestart);
          expect(
            repository.fanoutInboxAuthority,
            DirectMediaFanoutStageAuthority.persistedV114Survivors,
          );
          expect(repository.fanoutInboxSnapshot, isNull);
          expect(
            repository.fanoutInboxBindings
                .map(
                  (binding) => (
                    binding.recipientPeerId,
                    binding.recipientMlKemPublicKey,
                  ),
                )
                .toList(growable: false),
            <(String, String)>[
              (contact.peerId, 'mlkem-legacy-account'),
              (linkedTransport, 'mlkem-composer-a'),
            ],
          );
          expect(
            retryBridge.commandLog.where(
              (command) => command == 'message.encrypt',
            ),
            hasLength(2),
          );
          expect(retryP2p.sendMessageCallCount, 2);
        }
      } else {
        // 362: an initialized roster with a required selector OFF refuses
        // BEFORE media crypto/upload and never demotes to one target.
        expect(strictUploadRecipients, isEmpty);
        expect(sendCalls, 0);
        expect(repository.fanoutRows, isEmpty);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Fanout route',
          reason: 'admission refusal must preserve the composer draft',
        );
      }
      // Settle the message-card entrance timer before removing the route.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    testWidgets(
      'TC-362-02a composer routes a fresh strict generation through the '
      'all-target owner',
      (tester) => runFanoutRoutedComposerScenario(tester, selectorOn: true),
    );

    testWidgets(
      'TC-362-02a composer refuses a fresh strict send when a required '
      'selector is off',
      (tester) => runFanoutRoutedComposerScenario(tester, selectorOn: false),
    );

    testWidgets(
      'TC-362-02b default-build composer failure restarts from persisted v114 '
      'without a roster resolver',
      (tester) => runFanoutRoutedComposerScenario(
        tester,
        selectorOn: true,
        retryAfterInitialSendFailure: true,
      ),
    );

    testWidgets(
      'TC-366-01b supported private initials fan out while unsupported shapes '
      'refuse before effects',
      (tester) async {
        final priorFlowLogging = flowEventLoggingEnabled;
        flowEventLoggingEnabled = true;
        installPrivateMediaProtectionEventChannelStub(tester);
        final tempDir = Directory.systemTemp.createTempSync(
          'tc366_private_composer_fanout_',
        );
        addTearDown(() {
          debugConversationWiredInitialPrivateMediaPolicy = null;
          flowEventLoggingEnabled = priorFlowLogging;
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final image = File('${tempDir.path}/private.png')
          ..writeAsBytesSync(_tinyPngBytes);
        final fixture = (await tester.runAsync(
          MediaRepositoryRealDbFixture.create,
        ))!;
        addTearDown(fixture.dispose);
        await tester.runAsync(() => seedPersistedLinkedContact(fixture));
        expect(
          (fixture.repo
                  as OutgoingDirectPrivateMediaBlobFanoutGenerationRepository)
              .supportsOutgoingDirectPrivateMediaBlobFanoutGeneration,
          isTrue,
        );
        expect(
          (fixture.messageRepo
                  as OutgoingDirectPrivateMediaFanoutInboxCustodyRepository)
              .supportsOutgoingDirectPrivateMediaFanoutInboxCustody,
          isTrue,
        );
        final seededSnapshot = await tester.runAsync(
          () => (fixture.repo as OutgoingDirectLinkedMediaBlobFanoutRepository)
              .readDirectContactFanoutSnapshotForMedia(makeContact().peerId),
        );
        expect(seededSnapshot?.rosterInitialized, isTrue);
        expect(seededSnapshot?.targets, hasLength(2));
        final strictRecipients = <String>[];
        final coordinator = strictComposerCoordinator(
          repository: fixture.repo as DirectMediaBlobCustodyRepository,
          artifactRoot: tempDir,
          strictUpload:
              ({
                required bridge,
                required attachmentId,
                required recipientPeerId,
                required ciphertextPath,
                required contentHash,
                required ciphertextSize,
              }) async {
                strictRecipients.add(recipientPeerId);
                return <String, dynamic>{
                  'ok': true,
                  'id': attachmentId,
                  'storeStatus': 'stored',
                  'custodyKind': 'direct_media_blob_v1',
                  'custodyContract': 'ack_or_expiry_v1',
                  'contentHash': contentHash,
                  'size': ciphertextSize,
                  'mime': 'application/octet-stream',
                  'expiresAtMs': 2100000000000 + strictRecipients.length,
                  'custodyRelayPeerId': 'relay-tc366-private-composer',
                };
              },
        );
        var incumbentSendCalls = 0;
        var privateSendCalls = 0;
        DirectPrivateMediaFanoutContext? observedContext;
        List<MediaAttachment>? observedAttachments;

        Future<(SendChatMessageResult, ConversationMessage?)> incumbentSend({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          incumbentSendCalls++;
          return (
            SendChatMessageResult.success,
            await messageRepo.getMessage(messageId!),
          );
        }

        Future<(SendChatMessageResult, ConversationMessage?)> privateSend({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
          required DirectPrivateMediaFanoutContext directPrivateMediaFanout,
        }) async {
          privateSendCalls++;
          observedContext = directPrivateMediaFanout;
          observedAttachments = List<MediaAttachment>.of(
            mediaAttachments ?? const <MediaAttachment>[],
          );
          return (
            SendChatMessageResult.success,
            await messageRepo.getMessage(messageId!),
          );
        }

        debugConversationWiredInitialPrivateMediaPolicy =
            const PrivateMediaPolicy.protected();
        await pumpScreen(
          tester,
          identityRepo: FakeIdentityRepository(makeIdentity()),
          messageRepo: fixture.messageRepo,
          chatListener: ChatMessageListener(
            chatMessageStream: const Stream.empty(),
            messageRepo: fixture.messageRepo,
            contactRepo: FakeContactRepository(),
          ),
          sendFn: incumbentSend,
          sendPrivateMediaFanoutFn: privateSend,
          bridge: FakeBridge(),
          mediaAttachmentRepo: fixture.repo,
          contactRepo: FakeContactRepository(),
          mediaFileManager: TrackingDurableConversationMediaFileManager(
            tempDir,
          ),
          initialPendingMedia: <PendingComposerMedia>[
            PendingComposerMedia(file: image, budgetBytes: image.lengthSync()),
          ],
          preparedDirectMediaBlobCustodyCoordinator: coordinator,
          directLinkedMediaFanoutSelector:
              const DirectLinkedMediaFanoutSelector.enabled(),
          directMediaBlobCustodyClientEnabled: true,
          directLinkedEventFanoutEnabled: true,
        );
        await tester.pump(const Duration(seconds: 1));
        final compose = tester.widget<ComposeArea>(find.byType(ComposeArea));
        expect(
          compose.privateMediaPolicy,
          const PrivateMediaPolicy.protected(),
        );
        expect(compose.hasAttachments, isTrue);
        expect(compose.isSending, isFalse);
        expect(compose.privateMediaEligibility.allowsNewPrivateMedia, isTrue);
        expect(
          isPrivateMediaComposerPolicyEligible(
            selectedPolicy: compose.privateMediaPolicy,
            eligibility: compose.privateMediaEligibility,
          ),
          isTrue,
        );
        final directAdmission = await tester.runAsync(
          () => resolveDirectMediaFanoutAdmission(
            mediaAttachmentRepository: fixture.repo,
            contactAccountPeerId: makeContact().peerId,
            canServeLinkedFanout: true,
          ),
        );
        expect(directAdmission?.requiresLinkedFanout, isTrue);
        await tester.runAsync(() async {
          tester.widget<ComposeArea>(find.byType(ComposeArea)).onSend('');
          final deadline = Stopwatch()..start();
          while (privateSendCalls == 0 &&
              deadline.elapsed < const Duration(seconds: 8)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pump();

        final diagnosticMessages = await tester.runAsync(
          () => fixture.db.query('messages'),
        );
        final diagnosticAttachments = await tester.runAsync(
          () => fixture.db.query('media_attachments'),
        );
        final diagnosticBlobs = await tester.runAsync(
          () => fixture.db.query('direct_media_blob_custody'),
        );
        expect(
          privateSendCalls,
          1,
          reason:
              'incumbent=$incumbentSendCalls strict=$strictRecipients '
              'messages=$diagnosticMessages attachments='
              '$diagnosticAttachments blobs=$diagnosticBlobs',
        );
        expect(incumbentSendCalls, 0);
        expect(strictRecipients.toSet(), <String>{
          makeContact().peerId,
          '12D3KooWComposerLinkedDevice',
        });
        expect(observedContext?.snapshot, isNotNull);
        expect(observedContext?.targetRows, hasLength(2));
        expect(
          observedContext?.targetRows.values.every(
            (rows) =>
                rows.length == 1 &&
                rows.single.state == DirectMediaBlobCustodyState.outgoingStored,
          ),
          isTrue,
        );
        expect(observedAttachments, hasLength(1));
        expect(observedAttachments!.single.blobCustody?.isValid, isTrue);

        // An unsupported private GIF is rejected at the composer shape gate:
        // it never exposes the private selector and creates no new row before
        // the user can initiate any send-owned effect.
        final messagesBeforeUnsupported = (await tester.runAsync(
          () => fixture.db.query('messages'),
        ))!.length;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        final gif = File('${tempDir.path}/unsupported.gif')
          ..writeAsBytesSync(_tinyGifBytes);
        debugConversationWiredInitialPrivateMediaPolicy =
            const PrivateMediaPolicy.protected();
        await pumpScreen(
          tester,
          identityRepo: FakeIdentityRepository(makeIdentity()),
          messageRepo: fixture.messageRepo,
          chatListener: ChatMessageListener(
            chatMessageStream: const Stream.empty(),
            messageRepo: fixture.messageRepo,
            contactRepo: FakeContactRepository(),
          ),
          sendFn: incumbentSend,
          sendPrivateMediaFanoutFn: privateSend,
          bridge: FakeBridge(),
          mediaAttachmentRepo: fixture.repo,
          contactRepo: FakeContactRepository(),
          mediaFileManager: TrackingDurableConversationMediaFileManager(
            tempDir,
          ),
          initialPendingMedia: <PendingComposerMedia>[
            PendingComposerMedia(file: gif, budgetBytes: gif.lengthSync()),
          ],
          preparedDirectMediaBlobCustodyCoordinator: coordinator,
          directLinkedMediaFanoutSelector:
              const DirectLinkedMediaFanoutSelector.enabled(),
          directMediaBlobCustodyClientEnabled: true,
          directLinkedEventFanoutEnabled: true,
        );
        expect(
          find.byKey(const ValueKey('private-media-selector')),
          findsNothing,
        );
        expect(privateSendCalls, 1);
        expect(strictRecipients, hasLength(2));
        expect(
          (await tester.runAsync(() => fixture.db.query('messages')))!.length,
          messagesBeforeUnsupported,
        );
        await pumpUntilAsyncIo(
          tester,
          () => find
              .byKey(const ValueKey('conversation-loading-shell'))
              .evaluate()
              .isEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    DirectEventFanoutAuthoring mediaMutationFanoutAuthoring(
      _FanoutComposerMediaRepository repository,
    ) {
      Never unreachable() => throw StateError(
        'the widget must dispatch once; the use case owns fanout routing',
      );
      return DirectEventFanoutAuthoring(
        selector: const DirectLinkedEventFanoutSelector.enabled(),
        linkedOrigin: false,
        senderTransportPeerId: makeIdentity().peerId,
        readSnapshot: repository.readDirectContactFanoutSnapshotForMedia,
        encrypt:
            ({required recipientMlKemPublicKey, required plaintext}) async =>
                unreachable(),
        loadTextSiblings: (_) async => unreachable(),
        stageTextFanout:
            ({
              required stagedRow,
              required messageId,
              required contactAccountPeerId,
              required senderTransportPeerId,
              required expectedSnapshot,
              required candidates,
            }) async => unreachable(),
        loadEventSiblings: (_) async => unreachable(),
        stageMutationFanout:
            ({
              required expectedRow,
              required stagedRow,
              required kind,
              required eventId,
              required parentMessageId,
              required contactAccountPeerId,
              required senderTransportPeerId,
              required expectedSnapshot,
              required candidates,
            }) async => unreachable(),
        stageReactionFanout:
            ({
              required reactionRow,
              required action,
              required parentMessageId,
              required contactAccountPeerId,
              required senderTransportPeerId,
              required expectedSnapshot,
              required candidates,
            }) async => unreachable(),
      );
    }

    testWidgets(
      'TC-366-02a initialized media caption edit dispatches once and preserves draft on custody refusal',
      (tester) async {
        final contact = makeContact();
        const messageId = 'tc362-caption-refusal';
        const attachment = MediaAttachment(
          id: '$messageId-att',
          messageId: messageId,
          mime: 'image/jpeg',
          size: 512,
          mediaType: 'image',
          downloadStatus: 'done',
          createdAt: '2026-08-13T10:00:00.000Z',
          ownerLane: MediaOwnerLane.direct,
        );
        final message = ConversationMessage(
          id: messageId,
          contactPeerId: contact.peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Original media caption',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          status: 'delivered',
          isIncoming: false,
          createdAt: DateTime.now().toUtc().toIso8601String(),
          media: const <MediaAttachment>[attachment],
        );
        final messages = FakeMessageRepository()..store[messageId] = message;
        final media = _FanoutComposerMediaRepository(
          snapshot: DirectContactFanoutSnapshot(
            contactAccountPeerId: contact.peerId,
            contactAccountSigningPublicKey: contact.publicKey,
            rosterInitialized: true,
            targets: const <DirectContactFanoutTargetFact>[
              DirectContactFanoutTargetFact(
                peerId: 'peer-caption-linked',
                mlKemPublicKey: 'mlkem-caption-linked',
                isLegacyAccountTarget: false,
                fingerprint:
                    'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd',
                deviceId: 'caption-device',
                transportPublicKey: 'caption-transport-key',
              ),
            ],
          ),
        )..seed(const <MediaAttachment>[attachment]);
        final authoring = mediaMutationFanoutAuthoring(media);
        var editCalls = 0;
        DirectEventFanoutAuthoring? dispatchedFanout;
        Future<(SendChatMessageResult, ConversationMessage?)> refuseEdit({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required ConversationMessage originalMessage,
          required String updatedText,
          required String senderUsername,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          MediaAttachmentRepository? mediaAttachmentRepo,
          bool emitTimingEvent = true,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          editCalls++;
          dispatchedFanout = directEventFanout;
          expect(originalMessage.media, hasLength(1));
          expect(updatedText, 'Edited draft survives');
          return (SendChatMessageResult.sendFailed, null);
        }

        await pumpScreen(
          tester,
          identityRepo: FakeIdentityRepository(makeIdentity()),
          messageRepo: messages,
          chatListener: ChatMessageListener(
            chatMessageStream: const Stream.empty(),
            messageRepo: messages,
            contactRepo: FakeContactRepository(),
          ),
          sendFn: _instantSuccessSendFn,
          editFn: refuseEdit,
          mediaAttachmentRepo: media,
          initialMessages: <ConversationMessage>[message],
          directEventFanout: authoring,
        );

        await tester.longPress(find.text('Original media caption'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.editActionKey));
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'Edited draft survives');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump(const Duration(milliseconds: 200));

        expect(editCalls, 1);
        expect(dispatchedFanout, same(authoring));
        expect(
          media.snapshotReads,
          0,
          reason: 'the use case, not the widget, owns persisted routing',
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Edited draft survives',
        );
        expect(
          find.byKey(ConversationScreen.editModeBannerKey),
          findsOneWidget,
        );
        expect(messages.store[messageId]?.text, 'Original media caption');
      },
    );

    testWidgets(
      'TC-366-02b initialized media DFE dispatches plural custody once',
      (tester) async {
        final contact = makeContact();
        const messageId = 'tc362-dfe-refusal';
        const attachment = MediaAttachment(
          id: '$messageId-att',
          messageId: messageId,
          mime: 'image/jpeg',
          size: 512,
          mediaType: 'image',
          downloadStatus: 'done',
          createdAt: '2026-08-13T10:00:00.000Z',
          ownerLane: MediaOwnerLane.direct,
        );
        final message = ConversationMessage(
          id: messageId,
          contactPeerId: contact.peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Media DFE refusal',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          status: 'delivered',
          isIncoming: false,
          createdAt: DateTime.now().toUtc().toIso8601String(),
          media: const <MediaAttachment>[attachment],
        );
        final messages = FakeMessageRepository()..store[messageId] = message;
        final media = _FanoutComposerMediaRepository(
          snapshot: DirectContactFanoutSnapshot(
            contactAccountPeerId: contact.peerId,
            contactAccountSigningPublicKey: contact.publicKey,
            rosterInitialized: true,
            targets: const <DirectContactFanoutTargetFact>[
              DirectContactFanoutTargetFact(
                peerId: 'peer-dfe-linked',
                mlKemPublicKey: 'mlkem-dfe-linked',
                isLegacyAccountTarget: false,
                fingerprint:
                    'dededededededededededededededededededededededededededededededede',
                deviceId: 'dfe-device',
                transportPublicKey: 'dfe-transport-key',
              ),
            ],
          ),
        )..seed(const <MediaAttachment>[attachment]);
        final authoring = mediaMutationFanoutAuthoring(media);
        var deleteCalls = 0;
        DirectEventFanoutAuthoring? dispatchedFanout;
        Future<(SendChatMessageResult, ConversationMessage?)> refuseDelete({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required ConversationMessage originalMessage,
          ReactionRepository? reactionRepo,
          MediaAttachmentRepository? mediaAttachmentRepo,
          MediaFileManager? mediaFileManager,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          bool emitTimingEvent = true,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          deleteCalls++;
          dispatchedFanout = directEventFanout;
          expect(originalMessage.media, hasLength(1));
          return (SendChatMessageResult.sendFailed, null);
        }

        await pumpScreen(
          tester,
          identityRepo: FakeIdentityRepository(makeIdentity()),
          messageRepo: messages,
          chatListener: ChatMessageListener(
            chatMessageStream: const Stream.empty(),
            messageRepo: messages,
            contactRepo: FakeContactRepository(),
          ),
          sendFn: _instantSuccessSendFn,
          deleteForEveryoneFn: refuseDelete,
          mediaAttachmentRepo: media,
          initialMessages: <ConversationMessage>[message],
          directEventFanout: authoring,
        );

        await tester.longPress(find.text('Media DFE refusal'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
        await pumpUntil(
          tester,
          () => find
              .byKey(ConversationWired.deleteForEveryoneKey)
              .evaluate()
              .isNotEmpty,
        );
        tester
            .widget<InkWell>(
              find.descendant(
                of: find.byKey(ConversationWired.deleteForEveryoneKey),
                matching: find.byType(InkWell),
              ),
            )
            .onTap!();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(deleteCalls, 1);
        expect(dispatchedFanout, same(authoring));
        expect(
          media.snapshotReads,
          0,
          reason: 'the widget never preflights or demotes plural custody',
        );
        expect(messages.store[messageId]?.isDeleted, isFalse);
        expect(find.text('Media DFE refusal'), findsOneWidget);
      },
    );

    testWidgets(
      'TC-358-01a disappearing initial publishes v110 and v111 before first '
      'network',
      (tester) async {
        installPrivateMediaProtectionEventChannelStub(tester);
        UploadWakeLockController.debugReset(
          driver: _SynchronousUploadWakeLockDriver(),
        );
        final tempDir = Directory.systemTemp.createTempSync(
          'conv_358_disappearing_composer_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final image = File('${tempDir.path}/disappearing.png')
          ..writeAsBytesSync(_tinyPngBytes);
        final fixture = (await tester.runAsync(
          MediaRepositoryRealDbFixture.create,
        ))!;
        addTearDown(fixture.dispose);
        await tester.runAsync(() => seedPersistedIncumbentContact(fixture));
        final messageRepo = fixture.messageRepo;
        final manager = TrackingDurableConversationMediaFileManager(tempDir);
        final networkOrder = <String>[];
        var legacyUploadCalls = 0;
        var sendCalls = 0;
        String? intentAtFirstNetwork;
        List<String>? v111StatesAtFirstNetwork;
        List<MediaAttachment>? sentAttachments;
        PrivateMediaPolicy? sentPolicy;

        final strictCoordinator = strictComposerCoordinator(
          repository: fixture.repo as DirectMediaBlobCustodyRepository,
          artifactRoot: tempDir,
          strictUpload:
              ({
                required bridge,
                required attachmentId,
                required recipientPeerId,
                required ciphertextPath,
                required contentHash,
                required ciphertextSize,
              }) async {
                if (networkOrder.isEmpty) {
                  // The complete v111 generation and its v110 predecessor must
                  // already be durable before the FIRST blob callback.
                  final rows = await fixture.db.query(
                    kDirectMediaBlobCustodyTable,
                  );
                  v111StatesAtFirstNetwork = rows
                      .map((row) => row['state']! as String)
                      .toList(growable: false);
                  final parents = await fixture.db.query('messages');
                  intentAtFirstNetwork =
                      parents.single['direct_media_custody_intent_id']
                          as String?;
                }
                networkOrder.add('strict:$attachmentId');
                return <String, dynamic>{
                  'ok': true,
                  'id': attachmentId,
                  'storeStatus': 'stored',
                  'custodyKind': 'direct_media_blob_v1',
                  'custodyContract': 'ack_or_expiry_v1',
                  'contentHash': contentHash,
                  'size': ciphertextSize,
                  'mime': 'application/octet-stream',
                  'expiresAtMs': 2000000000000,
                  'custodyRelayPeerId': 'relay-358',
                };
              },
        );
        debugConversationWiredInitialPrivateMediaPolicy =
            PrivateMediaPolicy.disappearing(3600);
        addTearDown(
          () => debugConversationWiredInitialPrivateMediaPolicy = null,
        );

        await pumpScreen(
          tester,
          identityRepo: FakeIdentityRepository(makeIdentity()),
          messageRepo: messageRepo,
          chatListener: ChatMessageListener(
            chatMessageStream: const Stream.empty(),
            messageRepo: messageRepo,
            contactRepo: FakeContactRepository(),
          ),
          contactRepo: FakeContactRepository(),
          sendFn:
              ({
                required p2pService,
                required messageRepo,
                required targetPeerId,
                required text,
                required senderPeerId,
                required senderUsername,
                messageId,
                required bool preassignedMessageIdIsFresh,
                timestamp,
                bridge,
                recipientMlKemPublicKey,
                quotedMessageId,
                mediaAttachments,
                privateMediaPolicy,
                mediaAttachmentRepo,
                transportMetrics,
                directEventFanout,
              }) async {
                sendCalls++;
                networkOrder.add('envelope');
                sentPolicy = privateMediaPolicy;
                sentAttachments = List<MediaAttachment>.from(
                  mediaAttachments ?? const <MediaAttachment>[],
                );
                return (
                  SendChatMessageResult.success,
                  await messageRepo.getMessage(messageId!),
                );
              },
          bridge: FakeBridge(),
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: manager,
          preparedDirectMediaBlobCustodyCoordinator: strictCoordinator,
          initialPendingMedia: <PendingComposerMedia>[
            PendingComposerMedia(file: image, budgetBytes: image.lengthSync()),
          ],
          typedUploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                blobId,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async {
                legacyUploadCalls++;
                return const UploadMediaFailed(
                  stage: UploadMediaStage.transport,
                  disposition: UploadMediaDisposition.terminal,
                  errorCode: 'LEGACY_UPLOAD_MUST_NOT_RUN',
                );
              },
        );

        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(() async {
          await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
          final deadline = Stopwatch()..start();
          while (sendCalls == 0 &&
              legacyUploadCalls == 0 &&
              deadline.elapsed < const Duration(seconds: 8)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });

        expect(
          legacyUploadCalls,
          0,
          reason: 'a selected disappearing initial never takes legacy upload',
        );
        expect(sendCalls, 1, reason: 'networkOrder=$networkOrder');
        expect(
          intentAtFirstNetwork,
          isNotNull,
          reason: 'the v110 token is durable before the first blob callback',
        );
        expect(
          v111StatesAtFirstNetwork,
          <String>['outgoing_prepared'],
          reason: 'v111 commits before the first LAN/relay blob call',
        );
        expect(networkOrder, <String>[
          'strict:${sentAttachments!.single.id}',
          'envelope',
        ]);
        expect(sentPolicy?.mode, PrivateMediaMode.disappearing);
        expect(sentPolicy?.durationSeconds, 3600);
        expect(sentAttachments, hasLength(1));
        expect(sentAttachments!.single.blobCustody?.isValid, isTrue);
        expect(sentAttachments!.single.downloadStatus, 'done');
        final finalRows = await tester.runAsync(
          () => fixture.db.query(kDirectMediaBlobCustodyTable),
        );
        expect(finalRows, hasLength(1));
        expect(finalRows!.single['state'], 'outgoing_stored');
        final parent = (await tester.runAsync(
          () => messageRepo.getMessage(sentAttachments!.single.messageId),
        ))!;
        expect(parent.privateMediaMode, PrivateMediaMode.disappearing);
        expect(parent.privateMediaDurationSeconds, 3600);
        // The sender is not a receiver: no local disappearance clock exists.
        expect(parent.privateMediaReceivedAtMs, isNull);
        expect(parent.privateMediaExpiresAtMs, isNull);
        expect(parent.privateMediaClockHighWaterMs, isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
      skip: !kDirectMediaBlobCustodyClientEnabled,
    );

    testWidgets(
      'TC-345-05 ordinary media and voice persist manifest-bound custody intent before upload',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync(
          'conv_345_producer_intent_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final first = File('${tempDir.path}/first.jpg')
          ..writeAsBytesSync(_tinyPngBytes);
        final second = File('${tempDir.path}/second.jpg')
          ..writeAsBytesSync(_tinyPngBytes);

        final completeMessages = FakeMessageRepository();
        final completeMedia = FakeMediaAttachmentRepository();
        final completeListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: completeMessages,
          contactRepo: FakeContactRepository(),
        );
        ConversationMessage? parentObservedBeforeUpload;
        List<MediaAttachment>? rowsObservedBeforeUpload;
        Future<UploadMediaOutcome> stopAtCompleteUpload({
          required Bridge bridge,
          required String localFilePath,
          required String mime,
          required String recipientPeerId,
          MediaFileManager? mediaFileManager,
          int? width,
          int? height,
          int? durationMs,
          List<double>? waveform,
          List<String>? allowedPeers,
          String? blobId,
          bool deleteSourceWhenDone = false,
          EncryptedMediaArtifact? preparedArtifact,
        }) async {
          final parents = completeMessages.store.values
              .where((message) => !message.isIncoming)
              .toList(growable: false);
          parentObservedBeforeUpload = parents.single;
          rowsObservedBeforeUpload = await completeMedia
              .getAttachmentsForMessage(
                parents.single.id,
                owner: MediaOwnerLane.direct,
              );
          return const UploadMediaFailed(
            stage: UploadMediaStage.transport,
            disposition: UploadMediaDisposition.connectivityRetryable,
            errorCode: 'TEST_UPLOAD_BARRIER',
          );
        }

        await pumpScreen(
          tester,
          identityRepo: FakeIdentityRepository(makeIdentity()),
          messageRepo: completeMessages,
          chatListener: completeListener,
          sendFn: _instantSuccessSendFn,
          bridge: FakeBridge(),
          mediaAttachmentRepo: completeMedia,
          typedUploadMediaFn: stopAtCompleteUpload,
          initialAttachments: <File>[first, second],
        );
        await tester.enterText(find.byType(TextField), 'Two attachments');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpUntil(tester, () => parentObservedBeforeUpload != null);

        final completeParent = parentObservedBeforeUpload!;
        final completeRows = rowsObservedBeforeUpload!;
        expect(completeRows, hasLength(2));
        expect(
          completeRows.every(
            (attachment) => attachment.downloadStatus == 'upload_pending',
          ),
          isTrue,
        );
        expect(
          completeParent.directMediaCustodyIntentId,
          computeDirectMediaCustodyIntentId(
            messageId: completeParent.id,
            attachmentIds: completeRows.map((attachment) => attachment.id),
          ),
          reason: 'the full authored manifest is durable before upload begins',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        final partialMessages = FakeMessageRepository();
        final partialMedia = FakeMediaAttachmentRepository();
        final partialListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: partialMessages,
          contactRepo: FakeContactRepository(),
        );
        final attemptedAttachmentIds = <String>[];
        partialMedia.onSaveAttachment = (attachment) {
          attemptedAttachmentIds.add(attachment.id);
          if (attemptedAttachmentIds.length == 2) {
            throw StateError('interrupt sequential attachment persistence');
          }
        };
        var partialUploadCalls = 0;
        Future<UploadMediaOutcome> stopPartialUpload({
          required Bridge bridge,
          required String localFilePath,
          required String mime,
          required String recipientPeerId,
          MediaFileManager? mediaFileManager,
          int? width,
          int? height,
          int? durationMs,
          List<double>? waveform,
          List<String>? allowedPeers,
          String? blobId,
          bool deleteSourceWhenDone = false,
          EncryptedMediaArtifact? preparedArtifact,
        }) async {
          partialUploadCalls++;
          return const UploadMediaFailed(
            stage: UploadMediaStage.transport,
            disposition: UploadMediaDisposition.connectivityRetryable,
            errorCode: 'TEST_PARTIAL_UPLOAD_BARRIER',
          );
        }

        await pumpScreen(
          tester,
          identityRepo: FakeIdentityRepository(makeIdentity()),
          messageRepo: partialMessages,
          chatListener: partialListener,
          sendFn: _instantSuccessSendFn,
          bridge: FakeBridge(),
          mediaAttachmentRepo: partialMedia,
          typedUploadMediaFn: stopPartialUpload,
          initialAttachments: <File>[first, second],
        );
        await tester.enterText(find.byType(TextField), 'Interrupted pair');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpUntil(
          tester,
          () => attemptedAttachmentIds.length == 2 && partialUploadCalls > 0,
        );

        final partialParent = partialMessages.store.values.single;
        final survivingRows = await partialMedia.getAttachmentsForMessage(
          partialParent.id,
          owner: MediaOwnerLane.direct,
        );
        expect(survivingRows, hasLength(1));
        expect(
          partialParent.directMediaCustodyIntentId,
          computeDirectMediaCustodyIntentId(
            messageId: partialParent.id,
            attachmentIds: attemptedAttachmentIds,
          ),
        );
        expect(
          partialParent.directMediaCustodyIntentId,
          isNot(
            computeDirectMediaCustodyIntentId(
              messageId: partialParent.id,
              attachmentIds: survivingRows.map((attachment) => attachment.id),
            ),
          ),
          reason:
              'a restart cannot mistake the surviving subset for the authored set',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        final voiceMessages = FakeMessageRepository();
        final voiceMedia = FakeMediaAttachmentRepository();
        final voiceListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: voiceMessages,
          contactRepo: FakeContactRepository(),
        );
        final voiceFile = File('${tempDir.path}/voice.m4a')
          ..writeAsBytesSync(List<int>.filled(64, 1));
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 1200
          ..fakeOutputPath = voiceFile.path;
        ConversationMessage? voiceParentObserved;
        MediaAttachment? voiceAttachmentObserved;
        Future<(SendVoiceMessageResult, ConversationMessage?)> captureVoice({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String senderPeerId,
          required String senderUsername,
          required AudioRecording recording,
          required Bridge bridge,
          String? recipientMlKemPublicKey,
          MediaAttachmentRepository? mediaAttachmentRepo,
          MediaFileManager? mediaFileManager,
          String? text,
          String? quotedMessageId,
          List<double>? waveform,
          String? messageId,
          String? timestamp,
          String? blobId,
          EncryptedMediaArtifact? preparedArtifact,
          mediaAdmission,
        }) async {
          voiceParentObserved = await messageRepo.getMessage(messageId!);
          final rows = await mediaAttachmentRepo!.getAttachmentsForMessage(
            messageId,
            owner: MediaOwnerLane.direct,
          );
          voiceAttachmentObserved = rows.single;
          return (SendVoiceMessageResult.sendFailed, null);
        }

        await pumpScreen(
          tester,
          identityRepo: FakeIdentityRepository(makeIdentity()),
          messageRepo: voiceMessages,
          chatListener: voiceListener,
          sendFn: _instantSuccessSendFn,
          p2pService: FakeP2PService(),
          bridge: FakeBridge(),
          audioRecorderService: recorder,
          mediaAttachmentRepo: voiceMedia,
          sendVoiceMessageFn: captureVoice,
        );
        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        await (screen.onRecordStart! as Future<void> Function())();
        await tester.pump(const Duration(milliseconds: 100));
        final recordingScreen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        await (recordingScreen.onRecordStop! as Future<void> Function())();
        await pumpUntil(tester, () => voiceParentObserved != null);

        expect(voiceAttachmentObserved?.downloadStatus, 'upload_pending');
        expect(
          voiceParentObserved?.directMediaCustodyIntentId,
          computeDirectMediaCustodyIntentId(
            messageId: voiceParentObserved!.id,
            attachmentIds: <String>[voiceAttachmentObserved!.id],
          ),
          reason: 'voice preparation is durable before its upload delegate',
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'TC-345-05b ordinary upload cannot launder authored identity or delete pending custody',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync(
          'conv_345_upload_identity_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final source = File('${tempDir.path}/source.jpg')
          ..writeAsBytesSync(_tinyPngBytes);
        final messages = FakeMessageRepository();
        final media = FakeMediaAttachmentRepository();
        final manager = TrackingDurableConversationMediaFileManager(tempDir);
        final listener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messages,
          contactRepo: FakeContactRepository(),
        );
        var uploadCalls = 0;
        var sendCalls = 0;
        bool? deleteSourceWhenDoneObserved;

        Future<UploadMediaOutcome> crossedUpload({
          required Bridge bridge,
          required String localFilePath,
          required String mime,
          required String recipientPeerId,
          MediaFileManager? mediaFileManager,
          int? width,
          int? height,
          int? durationMs,
          List<double>? waveform,
          List<String>? allowedPeers,
          String? blobId,
          bool deleteSourceWhenDone = false,
          EncryptedMediaArtifact? preparedArtifact,
        }) async {
          uploadCalls++;
          deleteSourceWhenDoneObserved = deleteSourceWhenDone;
          return UploadMediaSucceeded(
            MediaAttachment(
              id: '${blobId!}-crossed',
              messageId: '',
              mime: mime,
              size: File(localFilePath).lengthSync() + 1,
              mediaType: MediaAttachment.mediaTypeFromMime(mime),
              width: width,
              height: height,
              durationMs: durationMs,
              localPath: 'media/crossed.jpg',
              downloadStatus: 'done',
              createdAt: '2099-01-01T00:00:00.000Z',
              waveform: waveform,
              contentHash:
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              encryptionKeyBase64: 'crossed-key',
              encryptionNonce: 'crossed-nonce',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ),
          );
        }

        Future<(SendChatMessageResult, ConversationMessage?)> shouldNotSend({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          sendCalls++;
          return (SendChatMessageResult.sendFailed, null);
        }

        await pumpScreen(
          tester,
          identityRepo: FakeIdentityRepository(makeIdentity()),
          messageRepo: messages,
          chatListener: listener,
          sendFn: shouldNotSend,
          bridge: FakeBridge(),
          mediaAttachmentRepo: media,
          mediaFileManager: manager,
          typedUploadMediaFn: crossedUpload,
          initialAttachments: <File>[source],
        );
        await tester.enterText(find.byType(TextField), 'Authored identity');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpUntilAsyncIo(tester, () => uploadCalls == 1);
        await pumpUntil(
          tester,
          () =>
              messages.store.isNotEmpty &&
              messages.store.values.single.status == 'failed',
        );

        final parent = messages.store.values.single;
        final durableRows = await media.getAttachmentsForMessage(
          parent.id,
          owner: MediaOwnerLane.direct,
        );
        expect(sendCalls, 0);
        expect(deleteSourceWhenDoneObserved, isFalse);
        expect(
          media.allSavedAttachments,
          hasLength(2),
          reason:
              'only the optimistic and durable-pending preparation saves run',
        );
        expect(durableRows, hasLength(1));
        expect(durableRows.single.downloadStatus, 'upload_pending');
        expect(parent.directMediaCustodyIntentId, isNotNull);
        expect(manager.deletedPendingUploadDirs, isEmpty);
        final pendingPath = await manager.resolveStoredPath(
          durableRows.single.localPath!,
        );
        expect(File(pendingPath).existsSync(), isTrue);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(_gifReplacementPolicyTestName, (tester) async {
      installPrivateMediaProtectionEventChannelStub(tester);
      final tempDir = Directory.systemTemp.createTempSync(
        'private_media_send_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final image = File('${tempDir.path}/private.png')
        ..writeAsBytesSync(_tinyPngBytes);
      final nextGif = File('${tempDir.path}/next.gif')
        ..writeAsBytesSync(_tinyGifBytes);
      final mediaPicker = FakeMediaPicker()
        ..multipleMediaResult = [XFile(nextGif.path)];
      final fixture = (await tester.runAsync(
        MediaRepositoryRealDbFixture.create,
      ))!;
      addTearDown(fixture.dispose);
      await tester.runAsync(() => seedPersistedIncumbentContact(fixture));
      final messageRepo = fixture.messageRepo;
      final durableMediaFileManager =
          TrackingDurableConversationMediaFileManager(tempDir);
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final capturedPolicies = <PrivateMediaPolicy>[];
      final optimisticPoliciesAtSend = <PrivateMediaPolicy>[];
      final capturedMediaMimes = <List<String>>[];
      var completedSends = 0;
      String? privateMessageId;
      String? privateAttachmentId;
      String? latestAttachmentId;
      final strictCoordinator = strictComposerCoordinator(
        repository: fixture.repo as DirectMediaBlobCustodyRepository,
        artifactRoot: tempDir,
        strictUpload:
            ({
              required bridge,
              required attachmentId,
              required recipientPeerId,
              required ciphertextPath,
              required contentHash,
              required ciphertextSize,
            }) async => <String, dynamic>{
              'ok': true,
              'id': attachmentId,
              'storeStatus': 'stored',
              'custodyKind': 'direct_media_blob_v1',
              'custodyContract': 'ack_or_expiry_v1',
              'contentHash': contentHash,
              'size': ciphertextSize,
              'mime': 'application/octet-stream',
              'expiresAtMs': 2000000000000,
              'custodyRelayPeerId': 'relay-policy-test',
            },
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        contactRepo: FakeContactRepository(),
        initialAttachments: [image],
        mediaPicker: mediaPicker,
        bridge: FakeBridge(),
        mediaAttachmentRepo: fixture.repo,
        mediaFileManager: durableMediaFileManager,
        preparedDirectMediaBlobCustodyCoordinator: strictCoordinator,
        uploadMediaFn:
            ({
              required bridge,
              required localFilePath,
              required mime,
              required recipientPeerId,
              mediaFileManager,
              blobId,
              width,
              height,
              durationMs,
              waveform,
              allowedPeers,
              deleteSourceWhenDone = false,
              preparedArtifact,
            }) async {
              final canonicalPath = durableMediaFileManager
                  .relativePathForAttachment(
                    contactPeerId: recipientPeerId,
                    blobId: blobId!,
                    mime: mime,
                  );
              final canonicalAbsolutePath = await durableMediaFileManager
                  .localPathForAttachment(
                    contactPeerId: recipientPeerId,
                    blobId: blobId,
                    mime: mime,
                  );
              await File(localFilePath).copy(canonicalAbsolutePath);
              return MediaAttachment(
                id: blobId,
                messageId: '',
                mime: mime,
                size: File(localFilePath).lengthSync(),
                mediaType: MediaAttachment.mediaTypeFromMime(mime),
                localPath: canonicalPath,
                downloadStatus: 'done',
                createdAt: DateTime.now().toUtc().toIso8601String(),
                contentHash: 'private-policy-test-hash',
                encryptionKeyBase64: 'private-policy-test-key',
                encryptionNonce: 'private-policy-test-nonce',
                encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
              );
            },
        sendFn:
            ({
              required p2pService,
              required messageRepo,
              required targetPeerId,
              required text,
              required senderPeerId,
              required senderUsername,
              messageId,
              required bool preassignedMessageIdIsFresh,
              timestamp,
              bridge,
              recipientMlKemPublicKey,
              quotedMessageId,
              mediaAttachments,
              privateMediaPolicy,
              mediaAttachmentRepo,
              transportMetrics,
              directEventFanout,
            }) async {
              final policy =
                  privateMediaPolicy ?? const PrivateMediaPolicy.ordinary();
              capturedPolicies.add(policy);
              final optimisticMessage = messageId == null
                  ? null
                  : await messageRepo.getMessage(messageId);
              if (optimisticMessage == null) {
                throw StateError(
                  'optimistic message must exist before the injected send seam',
                );
              }
              optimisticPoliciesAtSend.add(
                optimisticMessage.privateMediaPolicy,
              );
              capturedMediaMimes.add(
                mediaAttachments
                        ?.map((attachment) => attachment.mime)
                        .toList(growable: false) ??
                    const <String>[],
              );
              latestAttachmentId = mediaAttachments?.singleOrNull?.id;
              if (policy.isPrivate) {
                privateMessageId = messageId;
                privateAttachmentId = latestAttachmentId;
              }
              final result = await _instantSuccessSendFn(
                p2pService: p2pService,
                messageRepo: messageRepo,
                targetPeerId: targetPeerId,
                text: text,
                senderPeerId: senderPeerId,
                senderUsername: senderUsername,
                messageId: messageId,
                preassignedMessageIdIsFresh: preassignedMessageIdIsFresh,
                timestamp: timestamp,
                bridge: bridge,
                recipientMlKemPublicKey: recipientMlKemPublicKey,
                quotedMessageId: quotedMessageId,
                mediaAttachments: mediaAttachments,
                privateMediaPolicy: privateMediaPolicy,
                mediaAttachmentRepo: mediaAttachmentRepo,
                transportMetrics: transportMetrics,
              );
              completedSends++;
              return result;
            },
      );
      await tester.tap(find.byKey(const ValueKey('private-media-selector')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.byKey(const ValueKey('private-media-option-protected')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final policySheetScrollable = find.descendant(
        of: find.byKey(const ValueKey('private-media-policy-sheet')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('private-media-use-mode')),
        200,
        scrollable: policySheetScrollable,
      );
      await tester.tap(find.byKey(const ValueKey('private-media-use-mode')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpUntilAsyncIo(
        tester,
        () => completedSends == 1,
        timeout: const Duration(seconds: 10),
      );

      await pumpUntilAsyncIo(tester, () {
        final attachmentId = privateAttachmentId;
        return attachmentId != null &&
            !directPrivateMediaTransferRegistry.isActive(attachmentId);
      }, timeout: const Duration(seconds: 10));
      await pumpUntilAsyncIo(tester, () {
        final attachmentId = privateAttachmentId;
        return attachmentId != null &&
            !mediaUploadInFlightTracker.isInFlight(attachmentId);
      }, timeout: const Duration(seconds: 10));
      await pumpUntilAsyncIo(tester, () {
        final messageId = privateMessageId;
        final attachmentId = privateAttachmentId;
        if (messageId == null || attachmentId == null) return false;
        final pendingPath =
            '${tempDir.path}/pending_uploads/$messageId/$attachmentId.png';
        return !File(pendingPath).existsSync();
      }, timeout: const Duration(seconds: 10));

      expect(capturedPolicies.single, const PrivateMediaPolicy.protected());

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump(const Duration(milliseconds: 500));
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Media Library'))
          .onTap!();
      await pumpUntil(tester, () => find.text('GIF').evaluate().isNotEmpty);
      expect(
        find.byKey(const ValueKey('private-media-selector')),
        findsNothing,
        reason: 'a replacement GIF remains ordinary-only in the composer',
      );

      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        final deadline = Stopwatch()..start();
        while (completedSends < 2 &&
            deadline.elapsed < const Duration(seconds: 5)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await pumpUntilAsyncIo(tester, () => completedSends == 2);
      await pumpUntilAsyncIo(tester, () {
        final attachmentId = latestAttachmentId;
        return attachmentId != null &&
            !mediaUploadInFlightTracker.isInFlight(attachmentId);
      }, timeout: const Duration(seconds: 10));
      expect(capturedPolicies, const [
        PrivateMediaPolicy.protected(),
        PrivateMediaPolicy.ordinary(),
      ]);
      expect(optimisticPoliciesAtSend, const [
        PrivateMediaPolicy.protected(),
        PrivateMediaPolicy.ordinary(),
      ]);
      expect(capturedMediaMimes.last, const ['image/gif']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('video replacement blocks stale view-once send', (
      tester,
    ) async {
      installPrivateMediaProtectionEventChannelStub(tester);
      final tempDir = Directory.systemTemp.createTempSync(
        'private_media_stale_video_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final video = File('${tempDir.path}/replacement.mp4')
        ..writeAsBytesSync(_tinyPngBytes);
      final fixture = (await tester.runAsync(
        MediaRepositoryRealDbFixture.create,
      ))!;
      addTearDown(fixture.dispose);
      await tester.runAsync(() => seedPersistedIncumbentContact(fixture));
      final messageRepo = fixture.messageRepo;
      final durableMediaFileManager =
          TrackingDurableConversationMediaFileManager(tempDir);
      var uploadCalls = 0;
      var sendCalls = 0;
      String? attemptedAttachmentId;
      final strictCoordinator = strictComposerCoordinator(
        repository: fixture.repo as DirectMediaBlobCustodyRepository,
        artifactRoot: tempDir,
        strictUpload:
            ({
              required bridge,
              required attachmentId,
              required recipientPeerId,
              required ciphertextPath,
              required contentHash,
              required ciphertextSize,
            }) async {
              uploadCalls++;
              attemptedAttachmentId = attachmentId;
              throw StateError('retain strict upload for stale-policy proof');
            },
      );
      debugConversationWiredInitialPrivateMediaPolicy =
          const PrivateMediaPolicy.viewOnce();
      addTearDown(() => debugConversationWiredInitialPrivateMediaPolicy = null);

      await pumpScreen(
        tester,
        identityRepo: FakeIdentityRepository(makeIdentity()),
        messageRepo: messageRepo,
        chatListener: ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        ),
        contactRepo: FakeContactRepository(),
        initialPendingMedia: [
          PendingComposerMedia(file: video, budgetBytes: video.lengthSync()),
        ],
        bridge: FakeBridge(),
        mediaAttachmentRepo: fixture.repo,
        mediaFileManager: durableMediaFileManager,
        preparedDirectMediaBlobCustodyCoordinator: strictCoordinator,
        uploadMediaFn:
            ({
              required bridge,
              required localFilePath,
              required mime,
              required recipientPeerId,
              mediaFileManager,
              blobId,
              width,
              height,
              durationMs,
              waveform,
              allowedPeers,
              deleteSourceWhenDone = false,
              preparedArtifact,
            }) async {
              uploadCalls++;
              attemptedAttachmentId = blobId;
              return null;
            },
        sendFn:
            ({
              required p2pService,
              required messageRepo,
              required targetPeerId,
              required text,
              required senderPeerId,
              required senderUsername,
              messageId,
              required bool preassignedMessageIdIsFresh,
              timestamp,
              bridge,
              recipientMlKemPublicKey,
              quotedMessageId,
              mediaAttachments,
              privateMediaPolicy,
              mediaAttachmentRepo,
              transportMetrics,
              directEventFanout,
            }) async {
              sendCalls++;
              return _instantSuccessSendFn(
                p2pService: p2pService,
                messageRepo: messageRepo,
                targetPeerId: targetPeerId,
                text: text,
                senderPeerId: senderPeerId,
                senderUsername: senderUsername,
                messageId: messageId,
                preassignedMessageIdIsFresh: preassignedMessageIdIsFresh,
                timestamp: timestamp,
                bridge: bridge,
                recipientMlKemPublicKey: recipientMlKemPublicKey,
                quotedMessageId: quotedMessageId,
                mediaAttachments: mediaAttachments,
                privateMediaPolicy: privateMediaPolicy,
                mediaAttachmentRepo: mediaAttachmentRepo,
                transportMetrics: transportMetrics,
              );
            },
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('private-media-selector')),
          matching: find.text('Keep in chat'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(
        find.text('Private media needs one photo or video with no caption.'),
        findsOneWidget,
      );
      expect(uploadCalls, 0);
      expect(sendCalls, 0);
      expect(
        await tester.runAsync(
          () => messageRepo.getMessagesForContact(makeContact().peerId),
        ),
        isEmpty,
        reason: 'the rejected tap must not publish an optimistic parent',
      );

      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        final deadline = Stopwatch()..start();
        while (uploadCalls == 0 &&
            deadline.elapsed < const Duration(seconds: 5)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await pumpUntilAsyncIo(tester, () => uploadCalls == 1);
      await pumpUntilAsyncIo(tester, () {
        final attachmentId = attemptedAttachmentId;
        return attachmentId != null &&
            !directPrivateMediaTransferRegistry.isActive(attachmentId) &&
            !mediaUploadInFlightTracker.isInFlight(attachmentId);
      });

      expect(uploadCalls, 1);
      expect(sendCalls, 0);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('failed private upload restores the exact selected policy', (
      tester,
    ) async {
      installPrivateMediaProtectionEventChannelStub(tester);
      final tempDir = Directory.systemTemp.createTempSync(
        'private_media_restore_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final image = File('${tempDir.path}/private.png')
        ..writeAsBytesSync(_tinyPngBytes);
      // Plan 354 sentinel scope: this pins the LEGACY private upload lane, so
      // the strict private generation capability is deliberately absent.
      final fixture = (await tester.runAsync(
        () => MediaRepositoryRealDbFixture.create(
          wireOutgoingDirectPrivateMediaBlobGeneration: false,
        ),
      ))!;
      addTearDown(fixture.dispose);
      await tester.runAsync(() => seedPersistedIncumbentContact(fixture));
      final messageRepo = fixture.messageRepo;
      final durableMediaFileManager =
          TrackingDurableConversationMediaFileManager(tempDir);
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      var sendCalls = 0;
      String? failedAttachmentId;

      await pumpScreen(
        tester,
        identityRepo: FakeIdentityRepository(makeIdentity()),
        messageRepo: messageRepo,
        chatListener: chatListener,
        contactRepo: FakeContactRepository(),
        initialAttachments: [image],
        bridge: FakeBridge(),
        mediaAttachmentRepo: fixture.repo,
        mediaFileManager: durableMediaFileManager,
        uploadRetryProjectionRepo: _TerminalComposerUploadProjection(),
        uploadMediaFn:
            ({
              required bridge,
              required localFilePath,
              required mime,
              required recipientPeerId,
              mediaFileManager,
              blobId,
              width,
              height,
              durationMs,
              waveform,
              allowedPeers,
              deleteSourceWhenDone = false,
              preparedArtifact,
            }) async {
              failedAttachmentId = blobId;
              return null;
            },
        sendFn:
            ({
              required p2pService,
              required messageRepo,
              required targetPeerId,
              required text,
              required senderPeerId,
              required senderUsername,
              messageId,
              required bool preassignedMessageIdIsFresh,
              timestamp,
              bridge,
              recipientMlKemPublicKey,
              quotedMessageId,
              mediaAttachments,
              privateMediaPolicy,
              mediaAttachmentRepo,
              transportMetrics,
              directEventFanout,
            }) async {
              sendCalls++;
              return _instantSuccessSendFn(
                p2pService: p2pService,
                messageRepo: messageRepo,
                targetPeerId: targetPeerId,
                text: text,
                senderPeerId: senderPeerId,
                senderUsername: senderUsername,
                messageId: messageId,
                preassignedMessageIdIsFresh: preassignedMessageIdIsFresh,
                timestamp: timestamp,
                bridge: bridge,
                recipientMlKemPublicKey: recipientMlKemPublicKey,
                quotedMessageId: quotedMessageId,
                mediaAttachments: mediaAttachments,
                privateMediaPolicy: privateMediaPolicy,
                mediaAttachmentRepo: mediaAttachmentRepo,
                transportMetrics: transportMetrics,
              );
            },
      );
      await tester.tap(find.byKey(const ValueKey('private-media-selector')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.byKey(const ValueKey('private-media-option-view-once')),
      );
      await tester.pump();
      final policySheetScrollable = find.descendant(
        of: find.byKey(const ValueKey('private-media-policy-sheet')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('private-media-use-mode')),
        200,
        scrollable: policySheetScrollable,
      );
      await tester.tap(find.byKey(const ValueKey('private-media-use-mode')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpUntilAsyncIo(
        tester,
        () => find
            .text('Failed to upload media. Try again.')
            .evaluate()
            .isNotEmpty,
        timeout: const Duration(seconds: 10),
      );
      await pumpUntilAsyncIo(tester, () {
        final attachmentId = failedAttachmentId;
        return attachmentId != null &&
            !directPrivateMediaTransferRegistry.isActive(attachmentId) &&
            !mediaUploadInFlightTracker.isInFlight(attachmentId);
      }, timeout: const Duration(seconds: 10));

      expect(sendCalls, 0);
      expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
      // The restored policy shows in the composer selector; the failed
      // outgoing bubble now ALSO carries a mode label, so anchor the finder
      // to the selector instead of counting bare text matches.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('private-media-selector')),
          matching: find.text('View once'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('prefills shared text into the composer', (tester) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        initialText: 'Shared hello',
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, 'Shared hello');
    });

    testWidgets(
      'TC-342-03e canonical fresh text stays memory-optimistic and enters send as fresh',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final sendGate = Completer<void>();
        String? capturedText;
        String? capturedMessageId;
        bool? capturedPreassignedMessageIdIsFresh;

        Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          capturedText = text;
          capturedMessageId = messageId;
          capturedPreassignedMessageIdIsFresh = preassignedMessageIdIsFresh;
          await sendGate.future;

          final delivered = ConversationMessage(
            id: messageId!,
            contactPeerId: targetPeerId,
            senderPeerId: senderPeerId,
            text: text,
            timestamp: timestamp!,
            status: 'delivered',
            isIncoming: false,
            createdAt: timestamp,
          );
          await messageRepo.saveMessage(delivered);
          return (SendChatMessageResult.success, delivered);
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
        );

        const rawText = 'مرحبا\u202E Hello\u200E 123';
        final sanitizedText = sanitizeMessageText(rawText);

        await tester.enterText(find.byType(TextField), rawText);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump();

        expect(capturedText, sanitizedText);
        expect(capturedPreassignedMessageIdIsFresh, isTrue);
        expect(find.text(rawText), findsNothing);
        expect(find.text(sanitizedText), findsOneWidget);
        expect(
          messageRepo.store,
          isEmpty,
          reason:
              'fresh text must have no durable predecessor before the atomic '
              'message-plus-custody stage owned by sendChatMessage',
        );

        sendGate.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(capturedMessageId, isNotNull);
        expect(find.text(rawText), findsNothing);
        expect(find.text(sanitizedText), findsOneWidget);
        expect(messageRepo.store, hasLength(1));
        expect(messageRepo.store.values.single.text, sanitizedText);
        expect(messageRepo.store.values.single.status, 'delivered');
      },
    );

    testWidgets('shows both initialText and initialAttachments together', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final tempDir = Directory.systemTemp.createTempSync(
        'conversation_share_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final attachment = File('${tempDir.path}/shared.jpg')
        ..writeAsStringSync('image');

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        initialText: 'Shared hello',
        initialAttachments: [attachment],
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, 'Shared hello');
      expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
    });

    testWidgets(
      'hydrated initialPendingMedia uses budget bytes instead of file size',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final tempDir = Directory.systemTemp.createTempSync(
          'conversation_hydrated_budget_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final smallFile = File('${tempDir.path}/hydrated.jpg')
          ..writeAsStringSync('12');

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          initialPendingMedia: [
            PendingComposerMedia(file: smallFile, budgetBytes: 12),
          ],
          maxAttachmentBudgetBytes: 10,
        );

        expect(find.text('Media Too Large'), findsOneWidget);
      },
    );

    testWidgets('shows loading shell until the initial page resolves', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = SlowInitialPageMessageRepository();
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-load-1',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeContact().peerId,
          text: 'Loaded after delay',
          timestamp: '2026-02-11T10:05:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-11T10:05:00.000Z',
        ),
      );
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
      );

      expect(
        find.byKey(const ValueKey('conversation-loading-shell')),
        findsOneWidget,
      );
      expect(find.text('Loaded after delay'), findsNothing);

      messageRepo.firstPageGate.complete();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(const ValueKey('conversation-loading-shell')),
        findsNothing,
      );
      expect(find.text('Loaded after delay'), findsOneWidget);
    });

    testWidgets('shows message immediately then transitions to delivered', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      final gate = Completer<void>();
      String? sentMessageId;
      String? sentTimestamp;

      Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
        required P2PService p2pService,
        required MessageRepository messageRepo,
        required String targetPeerId,
        required String text,
        required String senderPeerId,
        required String senderUsername,
        String? messageId,
        required bool preassignedMessageIdIsFresh,
        String? timestamp,
        Bridge? bridge,
        String? recipientMlKemPublicKey,
        String? quotedMessageId,
        List<MediaAttachment>? mediaAttachments,
        PrivateMediaPolicy? privateMediaPolicy,
        MediaAttachmentRepository? mediaAttachmentRepo,
        TransportMetrics? transportMetrics,
        DirectEventFanoutAuthoring? directEventFanout,
      }) async {
        sentMessageId = messageId;
        sentTimestamp = timestamp;
        await gate.future;

        final delivered = ConversationMessage(
          id: messageId!,
          contactPeerId: targetPeerId,
          senderPeerId: senderPeerId,
          text: text,
          timestamp: timestamp!,
          status: 'delivered',
          isIncoming: false,
          createdAt: timestamp,
        );
        await messageRepo.saveMessage(delivered);
        return (SendChatMessageResult.success, delivered);
      }

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: sendFn,
      );

      await tester.enterText(find.byType(TextField), 'Hello optimistic');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(find.text('Hello optimistic'), findsOneWidget);
      // 184: on 1:1 the inline glyph is transport-aware. In-flight ('sending')
      // shows a single tick (clock→tick); the two-tick done_all is the custody
      // state, never in-flight.
      expect(find.byIcon(Icons.done_rounded), findsOneWidget);
      expect(find.byIcon(Icons.done_all_rounded), findsNothing);

      gate.complete();
      await tester.pump(const Duration(milliseconds: 50));

      expect(sentMessageId, isNotNull);
      expect(sentTimestamp, isNotNull);
      // 155: reached with no resolved transport → single-check fallback.
      expect(find.byIcon(Icons.done_rounded), findsOneWidget);
      expect(find.byIcon(Icons.done_all_rounded), findsNothing);
      expect(messageRepo.store[sentMessageId!]!.status, 'delivered');
    });

    testWidgets(
      'restores draft and removes fresh memory-only optimism when send returns null without custody authority',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );

        final gate = Completer<void>();
        String? sentMessageId;
        bool? sentMessageIdIsFresh;

        Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          sentMessageId = messageId;
          sentMessageIdIsFresh = preassignedMessageIdIsFresh;
          await gate.future;
          return (SendChatMessageResult.nodeNotRunning, null);
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
        );

        await tester.enterText(find.byType(TextField), 'Fail me');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump();

        expect(find.text('Fail me'), findsOneWidget);
        expect(messageRepo.store, isEmpty);
        // 184: in-flight ('sending') shows a single tick on 1:1 (clock→tick).
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);

        gate.complete();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump();

        expect(sentMessageId, isNotNull);
        expect(sentMessageIdIsFresh, isTrue);
        expect(find.text('Fail me'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Fail me',
        );
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
        expect(messageRepo.store[sentMessageId!], isNull);
      },
    );

    testWidgets(
      'sending unchanged restored failed text retries the original row',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final contactRepo = FakeContactRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );
        // 185×187/192: restored-failed-draft retry is a GENUINE-failure flow.
        // Post-192 a connectivity-class result carrying an envelope is kept
        // 'sent' (self-healing lane) even when the relay reads online, so the
        // terminal failed+restored-draft state is reached via the exception
        // path: the use case persisted the envelope, then the send flow threw.
        final p2pService = InboxRetryP2PService(relayOnline: true);
        var sendCalls = 0;
        String? failedMessageId;

        Future<(SendChatMessageResult, ConversationMessage?)> failFirstSend({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          sendCalls++;
          if (sendCalls > 1) {
            fail('restored failed draft should retry the failed row');
          }
          failedMessageId = messageId;
          final failed = ConversationMessage(
            id: messageId!,
            contactPeerId: targetPeerId,
            senderPeerId: senderPeerId,
            text: text,
            timestamp: timestamp!,
            status: 'failed',
            isIncoming: false,
            createdAt: timestamp,
            wireEnvelope:
                '{"type":"chat_message","version":"2","encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}',
          );
          await messageRepo.saveMessage(failed);
          throw Exception('send flow threw after envelope persist');
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: failFirstSend,
          p2pService: p2pService,
          bridge: FakeBridge(),
          contactRepo: contactRepo,
        );

        await tester.enterText(find.byType(TextField), 'Retry this message');
        await tester.pump(const Duration(milliseconds: 300));
        tester
            .widget<ConversationScreen>(find.byType(ConversationScreen))
            .onSend('Retry this message');
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 300));

        expect(failedMessageId, isNotNull);
        expect(messageRepo.store[failedMessageId]?.status, 'failed');
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Retry this message',
        );

        ScaffoldMessenger.of(
          tester.element(find.byType(ConversationWired)),
        ).clearSnackBars();
        await tester.pump(const Duration(milliseconds: 400));

        tester
            .widget<ConversationScreen>(find.byType(ConversationScreen))
            .onSend('Retry this message');
        await tester.pump(const Duration(milliseconds: 50));
        await pumpUntil(
          tester,
          // F6: relay re-store is custody, not delivery — settles 'inboxed'.
          () => messageRepo.store[failedMessageId]?.status == 'inboxed',
        );

        expect(sendCalls, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(messageRepo.store.keys.toList(), [failedMessageId]);
        expect(messageRepo.store[failedMessageId]?.text, 'Retry this message');
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          '',
        );
      },
    );

    testWidgets(
      'automatic retry settling a restored failed draft prevents a second send',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final contactRepo = FakeContactRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );
        // 185×187/192: restored-failed-draft retry is a GENUINE-failure flow.
        // Post-192 a connectivity-class result carrying an envelope is kept
        // 'sent' (self-healing lane) even when the relay reads online, so the
        // terminal failed+restored-draft state is reached via the exception
        // path: the use case persisted the envelope, then the send flow threw.
        final p2pService = InboxRetryP2PService(relayOnline: true);
        var sendCalls = 0;
        String? failedMessageId;

        Future<(SendChatMessageResult, ConversationMessage?)> failFirstSend({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          sendCalls++;
          if (sendCalls > 1) {
            fail('settled restored failed draft should not send a new row');
          }
          failedMessageId = messageId;
          final failed = ConversationMessage(
            id: messageId!,
            contactPeerId: targetPeerId,
            senderPeerId: senderPeerId,
            text: text,
            timestamp: timestamp!,
            status: 'failed',
            isIncoming: false,
            createdAt: timestamp,
            wireEnvelope:
                '{"type":"chat_message","version":"2","encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}',
          );
          await messageRepo.saveMessage(failed);
          throw Exception('send flow threw after envelope persist');
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: failFirstSend,
          p2pService: p2pService,
          bridge: FakeBridge(),
          contactRepo: contactRepo,
        );

        await tester.enterText(find.byType(TextField), 'Retry this message');
        await tester.pump(const Duration(milliseconds: 300));
        tester
            .widget<ConversationScreen>(find.byType(ConversationScreen))
            .onSend('Retry this message');
        await tester.pump(const Duration(milliseconds: 300));

        expect(failedMessageId, isNotNull);
        expect(messageRepo.store[failedMessageId]?.status, 'failed');
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Retry this message',
        );

        await messageRepo.saveMessage(
          messageRepo.store[failedMessageId]!.copyWith(
            status: 'delivered',
            transport: 'inbox',
            wireEnvelope: null,
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));

        tester
            .widget<ConversationScreen>(find.byType(ConversationScreen))
            .onSend('Retry this message');
        await tester.pump(const Duration(milliseconds: 300));

        expect(sendCalls, 1);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(messageRepo.store.keys.toList(), [failedMessageId]);
        expect(messageRepo.store[failedMessageId]?.status, 'delivered');
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          '',
        );
        expect(find.text('Could not retry message.'), findsNothing);
      },
    );

    testWidgets('shows delivered status when inbox fallback returns success', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      final gate = Completer<void>();
      String? sentMessageId;

      Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
        required P2PService p2pService,
        required MessageRepository messageRepo,
        required String targetPeerId,
        required String text,
        required String senderPeerId,
        required String senderUsername,
        String? messageId,
        required bool preassignedMessageIdIsFresh,
        String? timestamp,
        Bridge? bridge,
        String? recipientMlKemPublicKey,
        String? quotedMessageId,
        List<MediaAttachment>? mediaAttachments,
        PrivateMediaPolicy? privateMediaPolicy,
        MediaAttachmentRepository? mediaAttachmentRepo,
        TransportMetrics? transportMetrics,
        DirectEventFanoutAuthoring? directEventFanout,
      }) async {
        sentMessageId = messageId;
        await gate.future;
        final delivered = ConversationMessage(
          id: messageId!,
          contactPeerId: targetPeerId,
          senderPeerId: senderPeerId,
          text: text,
          timestamp: timestamp!,
          status: 'delivered',
          isIncoming: false,
          createdAt: timestamp,
        );
        await messageRepo.saveMessage(delivered);
        return (SendChatMessageResult.success, delivered);
      }

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: sendFn,
      );

      await tester.enterText(find.byType(TextField), 'Inbox delivered');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(find.text('Inbox delivered'), findsOneWidget);
      // 184: in-flight ('sending') → single tick on 1:1 (clock→tick).
      expect(find.byIcon(Icons.done_rounded), findsOneWidget);

      gate.complete();
      await tester.pump(const Duration(milliseconds: 50));

      // 155: reached with no resolved transport → single-check fallback.
      expect(find.byIcon(Icons.done_rounded), findsOneWidget);
      expect(find.byIcon(Icons.done_all_rounded), findsNothing);
      expect(messageRepo.store[sentMessageId!]!.status, 'delivered');
    });

    testWidgets('persists upload_pending attachments before upload starts', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final mediaAttachmentRepo = FakeMediaAttachmentRepository();
      final callOrder = <String>[];
      mediaAttachmentRepo.onSaveAttachment = (attachment) =>
          callOrder.add('save:${attachment.downloadStatus}');

      final tempDir = Directory.systemTemp.createTempSync(
        'conv_pending_upload_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final attachment = File('${tempDir.path}/pending.jpg')
        ..writeAsStringSync('image');

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        bridge: FakeBridge(),
        mediaAttachmentRepo: mediaAttachmentRepo,
        uploadMediaFn:
            ({
              required bridge,
              required localFilePath,
              required mime,
              required recipientPeerId,
              mediaFileManager,
              blobId,
              width,
              height,
              durationMs,
              waveform,
              allowedPeers,
              deleteSourceWhenDone = false,
              preparedArtifact,
            }) async {
              callOrder.add('uploadMedia');
              return MediaAttachment(
                id: 'uploaded-1',
                messageId: '',
                mime: mime,
                size: 1,
                mediaType: MediaAttachment.mediaTypeFromMime(mime),
                localPath: localFilePath,
                downloadStatus: 'done',
                createdAt: DateTime.now().toUtc().toIso8601String(),
              );
            },
        initialAttachments: [attachment],
      );

      await tester.enterText(find.byType(TextField), 'Photo');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpUntil(tester, () => callOrder.contains('uploadMedia'));

      expect(
        callOrder,
        containsAllInOrder(['save:upload_pending', 'uploadMedia']),
      );
      final savedAttachment = mediaAttachmentRepo.allSavedAttachments
          .firstWhere(
            (attachment) => attachment.downloadStatus == 'upload_pending',
          );
      expect(savedAttachment.messageId, isNotEmpty);
      expect(savedAttachment.localPath, attachment.path);
      expect(savedAttachment.size, attachment.lengthSync());
    });

    testWidgets(
      'TC-345-05c retryable manifest-bound composer failure uses exact authority and keeps queued lane',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final legacyProjection = _RecordingComposerUploadProjection();
        var exactProjectionCalls = 0;
        ConversationMessage? exactParent;
        List<MediaAttachment>? exactAttachments;
        String? exactFailedAttachmentId;
        UploadMediaFailed? exactFailure;
        mediaAttachmentRepo.onProjectDirectMediaCustodyUploadFailure =
            ({
              required expectedParent,
              required expectedAttachments,
              required failedAttachmentId,
              required failure,
            }) async {
              exactProjectionCalls++;
              exactParent = expectedParent;
              exactAttachments = List<MediaAttachment>.from(
                expectedAttachments,
              );
              exactFailedAttachmentId = failedAttachmentId;
              exactFailure = failure;
              return const UploadRetryProjectionResult(
                state: UploadRetryProjectionState.retryPending,
              );
            };
        final tempDir = Directory.systemTemp.createTempSync(
          'conv_retryable_projection_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachment = File('${tempDir.path}/pending.jpg')
          ..writeAsBytesSync(_tinyPngBytes);

        Future<UploadMediaOutcome> connectivityFailure({
          required Bridge bridge,
          required String localFilePath,
          required String mime,
          required String recipientPeerId,
          MediaFileManager? mediaFileManager,
          int? width,
          int? height,
          int? durationMs,
          List<double>? waveform,
          List<String>? allowedPeers,
          String? blobId,
          bool deleteSourceWhenDone = false,
          EncryptedMediaArtifact? preparedArtifact,
        }) async => const UploadMediaFailed(
          stage: UploadMediaStage.transport,
          disposition: UploadMediaDisposition.connectivityRetryable,
          errorCode: 'NOT_INITIALIZED',
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          bridge: FakeBridge(),
          mediaAttachmentRepo: mediaAttachmentRepo,
          typedUploadMediaFn: connectivityFailure,
          uploadRetryProjectionRepo: legacyProjection,
          initialAttachments: [attachment],
        );

        await tester.enterText(find.byType(TextField), 'Queued photo');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpUntil(tester, () => exactProjectionCalls == 1);

        expect(exactProjectionCalls, 1);
        expect(legacyProjection.callCount, 0);
        expect(exactParent?.directMediaCustodyIntentId, isNotNull);
        expect(exactAttachments, hasLength(1));
        expect(exactFailedAttachmentId, exactAttachments!.single.id);
        expect(
          exactFailure?.disposition,
          UploadMediaDisposition.connectivityRetryable,
        );
        expect(
          mediaAttachmentRepo.allSavedAttachments.where(
            (row) => row.downloadStatus == 'upload_failed',
          ),
          isEmpty,
        );
        expect(messageRepo.store[exactParent!.id]?.status, 'sending');
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          isEmpty,
        );
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets(
      'TC-345-05d manifest-bound composer failure refuses crossed unsupported and global-v108 state without legacy fallback',
      (tester) async {
        for (final scenario in <String>[
          'metadata',
          'partial',
          'token',
          'unsupported',
          'global-v108',
        ]) {
          final identityRepo = FakeIdentityRepository(makeIdentity());
          final messageRepo = FakeMessageRepository();
          final mediaAttachmentRepo = FakeMediaAttachmentRepository();
          final legacyProjection = _RecordingComposerUploadProjection();
          final listener = ChatMessageListener(
            chatMessageStream: const Stream.empty(),
            messageRepo: messageRepo,
            contactRepo: FakeContactRepository(),
          );
          final tempDir = Directory.systemTemp.createTempSync(
            'conv_345_failure_refusal_$scenario',
          );
          final first = File('${tempDir.path}/first.jpg')
            ..writeAsBytesSync(_tinyPngBytes);
          final second = File('${tempDir.path}/second.jpg')
            ..writeAsBytesSync(_tinyPngBytes);
          addTearDown(() {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          });
          var uploadCalls = 0;
          var sendCalls = 0;
          var exactProjectionCalls = 0;
          List<MediaAttachment>? exactAttachments;
          if (scenario != 'unsupported') {
            mediaAttachmentRepo.onProjectDirectMediaCustodyUploadFailure =
                ({
                  required expectedParent,
                  required expectedAttachments,
                  required failedAttachmentId,
                  required failure,
                }) async {
                  exactProjectionCalls++;
                  exactAttachments = List<MediaAttachment>.from(
                    expectedAttachments,
                  );
                  if (scenario == 'global-v108') {
                    return const UploadRetryProjectionResult.notApplied();
                  }
                  return const UploadRetryProjectionResult(
                    state: UploadRetryProjectionState.retryPending,
                  );
                };
          }

          Future<UploadMediaOutcome> crossedFailure({
            required Bridge bridge,
            required String localFilePath,
            required String mime,
            required String recipientPeerId,
            MediaFileManager? mediaFileManager,
            int? width,
            int? height,
            int? durationMs,
            List<double>? waveform,
            List<String>? allowedPeers,
            String? blobId,
            bool deleteSourceWhenDone = false,
            EncryptedMediaArtifact? preparedArtifact,
          }) async {
            uploadCalls++;
            final parent = messageRepo.store.values.single;
            final rows = await mediaAttachmentRepo.getAttachmentsForMessage(
              parent.id,
              owner: MediaOwnerLane.direct,
            );
            switch (scenario) {
              case 'metadata':
                await mediaAttachmentRepo.saveAttachment(
                  rows.first.copyWith(width: (rows.first.width ?? 0) + 1),
                  owner: MediaOwnerLane.direct,
                );
                break;
              case 'partial':
                await mediaAttachmentRepo.deleteAttachmentsForMessage(
                  parent.id,
                  owner: MediaOwnerLane.direct,
                );
                await mediaAttachmentRepo.saveAttachment(
                  rows.first,
                  owner: MediaOwnerLane.direct,
                );
                break;
              case 'token':
                messageRepo.store[parent.id] = parent.copyWith(
                  directMediaCustodyIntentId:
                      'ffffffffffffffffffffffffffffffff',
                );
                break;
              case 'unsupported':
              case 'global-v108':
                break;
            }
            return const UploadMediaFailed(
              stage: UploadMediaStage.transport,
              disposition: UploadMediaDisposition.connectivityRetryable,
              errorCode: 'TEST_MANIFEST_FAILURE',
            );
          }

          Future<(SendChatMessageResult, ConversationMessage?)> shouldNotSend({
            required P2PService p2pService,
            required MessageRepository messageRepo,
            required String targetPeerId,
            required String text,
            required String senderPeerId,
            required String senderUsername,
            String? messageId,
            required bool preassignedMessageIdIsFresh,
            String? timestamp,
            Bridge? bridge,
            String? recipientMlKemPublicKey,
            String? quotedMessageId,
            List<MediaAttachment>? mediaAttachments,
            PrivateMediaPolicy? privateMediaPolicy,
            MediaAttachmentRepository? mediaAttachmentRepo,
            TransportMetrics? transportMetrics,
            DirectEventFanoutAuthoring? directEventFanout,
          }) async {
            sendCalls++;
            return (SendChatMessageResult.sendFailed, null);
          }

          await pumpScreen(
            tester,
            identityRepo: identityRepo,
            messageRepo: messageRepo,
            chatListener: listener,
            sendFn: shouldNotSend,
            bridge: FakeBridge(),
            mediaAttachmentRepo: mediaAttachmentRepo,
            typedUploadMediaFn: crossedFailure,
            uploadRetryProjectionRepo: legacyProjection,
            initialAttachments: <File>[first, second],
          );
          final draft = 'Refuse $scenario';
          await tester.enterText(find.byType(TextField), draft);
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
          await pumpUntil(
            tester,
            () => find
                .text('Failed to upload media. Try again.')
                .evaluate()
                .isNotEmpty,
          );

          expect(uploadCalls, 1, reason: scenario);
          expect(sendCalls, 0, reason: scenario);
          expect(legacyProjection.callCount, 0, reason: scenario);
          expect(
            exactProjectionCalls,
            scenario == 'global-v108' ? 1 : 0,
            reason: scenario,
          );
          if (scenario == 'global-v108') {
            expect(exactAttachments, hasLength(2));
          }
          final parent = messageRepo.store.values.single;
          expect(parent.status, 'sending', reason: scenario);
          expect(
            parent.directMediaCustodyIntentId,
            isNotNull,
            reason: scenario,
          );
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller?.text,
            draft,
            reason: scenario,
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );

    testWidgets(
      'post-send image/video viewer keeps the canonical direct owner projection',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final tempDir = Directory.systemTemp.createTempSync(
          'conv_outgoing_owner_projection_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final image = File('${tempDir.path}/outgoing.png')
          ..writeAsBytesSync(_tinyPngBytes);
        final video = File('${tempDir.path}/outgoing.mp4')
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
        final uploadedOwnerLanes = <MediaOwnerLane?>[];

        Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          expectSync(mediaAttachments, hasLength(2));
          expectSync(
            mediaAttachments!.every(
              (attachment) => attachment.ownerLane == null,
            ),
            isTrue,
            reason: 'upload results are production-shaped and unresolved',
          );
          final canonical = mediaAttachments
              .map(
                (attachment) => attachment.copyWith(
                  messageId: messageId,
                  ownerLane: MediaOwnerLane.direct,
                ),
              )
              .toList(growable: false);
          final delivered = ConversationMessage(
            id: messageId!,
            contactPeerId: targetPeerId,
            senderPeerId: senderPeerId,
            text: text,
            timestamp: timestamp!,
            status: 'delivered',
            isIncoming: false,
            createdAt: timestamp,
            media: canonical,
          );
          await messageRepo.saveMessage(delivered);
          return (SendChatMessageResult.success, delivered);
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
          bridge: FakeBridge(),
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                blobId,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async {
                final attachment = MediaAttachment(
                  id: blobId!,
                  messageId: '',
                  mime: mime,
                  size: File(localFilePath).lengthSync(),
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  width: width,
                  height: height,
                  durationMs: durationMs,
                  localPath: localFilePath,
                  downloadStatus: 'done',
                  createdAt: '2026-07-14T12:00:00.000Z',
                );
                uploadedOwnerLanes.add(attachment.ownerLane);
                return attachment;
              },
          initialAttachments: [image, video],
        );

        tester
            .widget<ConversationScreen>(find.byType(ConversationScreen))
            .onSend('');
        await pumpUntil(
          tester,
          () =>
              messageRepo.store.values.any(
                (message) =>
                    message.status == 'delivered' && message.media.length == 2,
              ) &&
              tester
                  .widget<ConversationScreen>(find.byType(ConversationScreen))
                  .messages
                  .any(
                    (message) =>
                        message.status == 'delivered' &&
                        message.media.length == 2,
                  ),
        );

        expect(uploadedOwnerLanes, [null, null]);
        final displayed = tester
            .widget<ConversationScreen>(find.byType(ConversationScreen))
            .messages
            .singleWhere((message) => message.status == 'delivered');
        expect(
          displayed.media.map((attachment) => attachment.ownerLane),
          everyElement(MediaOwnerLane.direct),
        );

        for (var index = 0; index < displayed.media.length; index++) {
          final attachment = displayed.media[index];
          final cell = find.byKey(
            ValueKey('media-grid-cell-${displayed.id}-${attachment.id}'),
          );
          tester.widget<GestureDetector>(cell).onTap!.call();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          final viewer = tester.widget<FullScreenTypedMediaViewer>(
            find.byType(FullScreenTypedMediaViewer),
          );
          expect(viewer.initialIndex, index);
          expect(
            viewer.items.map((item) => item.owner),
            everyElement(MediaOwnerLane.direct),
          );
          Navigator.of(
            tester.element(find.byType(FullScreenTypedMediaViewer)),
          ).pop();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
        }
      },
    );

    testWidgets(
      'durable media prep stores upload_pending rows in app-owned storage when MediaFileManager is available',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final callOrder = <String>[];
        final uploadStarted = Completer<void>();
        final uploadGate = Completer<void>();
        mediaAttachmentRepo.onSaveAttachment = (attachment) =>
            callOrder.add('save:${attachment.downloadStatus}');

        final tempDir = Directory.systemTemp.createTempSync(
          'conv_durable_upload_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        addTearDown(() {
          if (!uploadGate.isCompleted) {
            uploadGate.complete();
          }
        });
        final mediaFileManager = TrackingDurableConversationMediaFileManager(
          tempDir,
        );
        final attachment = File('${tempDir.path}/source.jpg')
          ..writeAsBytesSync(_tinyPngBytes);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          bridge: FakeBridge(),
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                blobId,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async {
                callOrder.add('uploadMedia');
                uploadStarted.complete();
                await uploadGate.future;
                return MediaAttachment(
                  id: blobId ?? 'uploaded-1',
                  messageId: '',
                  mime: mime,
                  size: _tinyPngBytes.length,
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath:
                      mediaFileManager?.relativePathForAttachment(
                        contactPeerId: recipientPeerId,
                        blobId: blobId ?? 'uploaded-1',
                        mime: mime,
                      ) ??
                      localFilePath,
                  downloadStatus: 'done',
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                );
              },
          initialAttachments: [attachment],
        );

        await tester.enterText(find.byType(TextField), 'Durable photo');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpUntilAsyncIo(tester, () => uploadStarted.isCompleted);

        expect(mediaFileManager.copyCalls, 1);
        expect(callOrder, contains('save:upload_pending'));
        final pendingAttachment = mediaAttachmentRepo.allSavedAttachments
            .firstWhere(
              (attachment) => attachment.downloadStatus == 'upload_pending',
            );
        expect(pendingAttachment.size, _tinyPngBytes.length);
        final durableDir = Directory('${tempDir.path}/pending_uploads');
        expect(durableDir.existsSync(), isTrue);
        final durableFiles = durableDir
            .listSync(recursive: true)
            .whereType<File>()
            .toList(growable: false);
        expect(durableFiles, isNotEmpty);
        expect(durableFiles.single.existsSync(), isTrue);

        uploadGate.complete();
        await pumpUntilAsyncIo(
          tester,
          () => mediaFileManager.pendingUploadDirDeleted.isCompleted,
        );
        expect(mediaFileManager.deletedPendingUploadDirs, isNotEmpty);
      },
    );

    testWidgets(
      'outgoing repository status updates keep hydrated media instead of wiping sender bubbles',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();

        final tempDir = Directory.systemTemp.createTempSync(
          'conv_repo_change_media_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final imageFile = File('${tempDir.path}/bubble.png')
          ..writeAsBytesSync(_tinyPngBytes);

        final sentAt = DateTime.now().toUtc().toIso8601String();
        const messageId = 'msg-media-hydrated-001';
        final message = ConversationMessage(
          id: messageId,
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: '',
          timestamp: sentAt,
          status: 'sent',
          isIncoming: false,
          createdAt: sentAt,
        );
        messageRepo.store[messageId] = message;
        mediaAttachmentRepo.seed([
          MediaAttachment(
            id: 'att-media-hydrated-001',
            messageId: messageId,
            mime: 'image/png',
            size: _tinyPngBytes.length,
            mediaType: 'image',
            localPath: imageFile.path,
            downloadStatus: 'done',
            createdAt: sentAt,
          ),
        ]);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        ConversationScreen screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        ConversationMessage visibleMessage = screen.messages.firstWhere(
          (message) => message.id == messageId,
        );
        expect(visibleMessage.media, isNotEmpty);

        await messageRepo.saveMessage(message.copyWith(status: 'delivered'));
        await pumpUntil(tester, () {
          final nextScreen = tester.widget<ConversationScreen>(
            find.byType(ConversationScreen),
          );
          final nextMessage = nextScreen.messages.firstWhere(
            (message) => message.id == messageId,
          );
          return nextMessage.status == 'delivered' &&
              nextMessage.media.isNotEmpty;
        });

        screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        visibleMessage = screen.messages.firstWhere(
          (message) => message.id == messageId,
        );
        expect(visibleMessage.status, 'delivered');
        expect(visibleMessage.media, isNotEmpty);
        expect(visibleMessage.media.single.id, 'att-media-hydrated-001');
      },
    );

    // -----------------------------------------------------------------------
    // 156 QW-9 (reactive-streams-2): gate the per-event attachments read so a
    // text/status-only repo change does not hit the DB. Uses a call-count DELTA
    // (not absolute) around the emit, with NO bridge/mediaFileManager so
    // _recoverVisibleMedia never fires and the only reads are the resolver's.
    // -----------------------------------------------------------------------
    testWidgets(
      'TC-16: text/status-only repo change does NOT read attachments (delta 0)',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();

        final sentAt = DateTime.now().toUtc().toIso8601String();
        const messageId = 'msg-text-status-only';
        messageRepo.store[messageId] = ConversationMessage(
          id: messageId,
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'plain text',
          timestamp: sentAt,
          status: 'sent',
          isIncoming: false,
          createdAt: sentAt,
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        final before = mediaAttachmentRepo.getAttachmentsForMessageCallCount;

        await messageRepo.updateMessageStatus(messageId, 'delivered');
        await pumpUntil(tester, () {
          final screen = tester.widget<ConversationScreen>(
            find.byType(ConversationScreen),
          );
          final matches = screen.messages.where((m) => m.id == messageId);
          return matches.isNotEmpty && matches.first.status == 'delivered';
        });

        final delta =
            mediaAttachmentRepo.getAttachmentsForMessageCallCount - before;
        expect(delta, 0);
        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        expect(screen.messages.any((m) => m.id == messageId), isTrue);
      },
    );

    testWidgets(
      'TC-17: media repo change DOES resolve attachments (delta >= 1)',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();

        final sentAt = DateTime.now().toUtc().toIso8601String();
        const messageId = 'msg-relay-drained-media';
        // Relay-drained media: attachments live in-table; the emitted message
        // carries EMPTY inline media but is a NEW (not-yet-shown) message.
        mediaAttachmentRepo.seed([
          MediaAttachment(
            id: 'att-relay-drained-001',
            messageId: messageId,
            mime: 'image/png',
            size: 10,
            mediaType: 'image',
            downloadStatus: 'pending',
            createdAt: sentAt,
          ),
        ]);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        final before = mediaAttachmentRepo.getAttachmentsForMessageCallCount;

        await messageRepo.saveMessage(
          ConversationMessage(
            id: messageId,
            contactPeerId: makeContact().peerId,
            senderPeerId: makeContact().peerId,
            text: '',
            timestamp: sentAt,
            status: 'sent',
            isIncoming: true,
            createdAt: sentAt,
          ),
        );
        await pumpUntil(tester, () {
          final screen = tester.widget<ConversationScreen>(
            find.byType(ConversationScreen),
          );
          return screen.messages.any((m) => m.id == messageId);
        });

        final delta =
            mediaAttachmentRepo.getAttachmentsForMessageCallCount - before;
        expect(delta, greaterThanOrEqualTo(1));
      },
    );

    testWidgets(
      'TC-18: already-shown media change does not double-resolve (delta 0)',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();

        final sentAt = DateTime.now().toUtc().toIso8601String();
        const messageId = 'msg-already-shown-media';
        messageRepo.store[messageId] = ConversationMessage(
          id: messageId,
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: '',
          timestamp: sentAt,
          status: 'sent',
          isIncoming: false,
          createdAt: sentAt,
        );
        mediaAttachmentRepo.seed([
          MediaAttachment(
            id: 'att-shown-001',
            messageId: messageId,
            mime: 'image/png',
            size: 10,
            mediaType: 'image',
            downloadStatus: 'pending',
            createdAt: sentAt,
          ),
        ]);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        // Wait until the seeded media is hydrated into the already-shown row.
        await pumpUntil(tester, () {
          final screen = tester.widget<ConversationScreen>(
            find.byType(ConversationScreen),
          );
          final matches = screen.messages.where((m) => m.id == messageId);
          return matches.isNotEmpty && matches.first.media.isNotEmpty;
        });

        final before = mediaAttachmentRepo.getAttachmentsForMessageCallCount;

        await messageRepo.updateMessageStatus(messageId, 'delivered');
        await pumpUntil(tester, () {
          final screen = tester.widget<ConversationScreen>(
            find.byType(ConversationScreen),
          );
          final matches = screen.messages.where((m) => m.id == messageId);
          return matches.isNotEmpty && matches.first.status == 'delivered';
        });

        final delta =
            mediaAttachmentRepo.getAttachmentsForMessageCallCount - before;
        expect(delta, 0);
        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        final shown = screen.messages.firstWhere((m) => m.id == messageId);
        expect(shown.media, isNotEmpty);
      },
    );

    testWidgets(
      'relay media send reuses optimistic attachment id and clears upload_pending placeholder',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final tempDir = Directory.systemTemp.createTempSync(
          'conv_stable_media_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachment = File('${tempDir.path}/stable.jpg')
          ..writeAsStringSync('image');

        String? uploadedBlobId;
        String? sentMessageId;

        Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          sentMessageId = messageId;
          if (mediaAttachments != null && mediaAttachmentRepo != null) {
            for (final attachment in mediaAttachments) {
              await mediaAttachmentRepo.saveAttachment(
                attachment.copyWith(messageId: messageId!),
                owner: MediaOwnerLane.direct,
              );
            }
          }

          final delivered = ConversationMessage(
            id: messageId!,
            contactPeerId: targetPeerId,
            senderPeerId: senderPeerId,
            text: text,
            timestamp: timestamp!,
            status: 'delivered',
            isIncoming: false,
            createdAt: timestamp,
          );
          await messageRepo.saveMessage(delivered);
          return (
            SendChatMessageResult.success,
            delivered.copyWith(media: mediaAttachments ?? const []),
          );
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
          bridge: FakeBridge(),
          mediaAttachmentRepo: mediaAttachmentRepo,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                blobId,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async {
                uploadedBlobId = blobId;
                return MediaAttachment(
                  id: blobId ?? 'fallback-upload-id',
                  messageId: '',
                  mime: mime,
                  size: 1,
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath: localFilePath,
                  downloadStatus: 'done',
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                );
              },
          initialAttachments: [attachment],
        );

        await tester.enterText(find.byType(TextField), 'Photo');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpUntil(
          tester,
          () => uploadedBlobId != null && sentMessageId != null,
        );

        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          sentMessageId!,
          owner: MediaOwnerLane.direct,
        );
        expect(uploadedBlobId, isNotNull);
        expect(attachments.length, 1);
        expect(attachments.single.id, uploadedBlobId);
        expect(attachments.single.downloadStatus, 'done');
        final pending = await mediaAttachmentRepo.getUploadPendingAttachments(
          owner: MediaOwnerLane.direct,
        );
        expect(
          pending.where((attachment) => attachment.messageId == sentMessageId!),
          isEmpty,
        );

        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'outgoing message changes preserve displayable media over stale hydrated paths',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final tempDir = Directory.systemTemp.createTempSync(
          'conv_preserve_media_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        const messageId = 'msg-preserve-displayable-media';
        const attachmentId = 'att-preserve-displayable-media';
        final visibleFile = File('${tempDir.path}/visible.png')
          ..writeAsBytesSync(_tinyPngBytes);
        final visibleAttachment = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/png',
          size: _tinyPngBytes.length,
          mediaType: 'image',
          localPath: visibleFile.path,
          downloadStatus: 'done',
          createdAt: '2026-06-18T12:00:00.000Z',
        );
        final staleAttachment = visibleAttachment.copyWith(
          localPath: 'pending_uploads/$messageId/$attachmentId.png',
          downloadStatus: 'done',
        );
        final message = ConversationMessage(
          id: messageId,
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: '',
          timestamp: '2026-06-18T12:00:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-06-18T12:00:00.000Z',
          media: [visibleAttachment],
        );
        messageRepo.store[messageId] = message.copyWith(media: const []);
        mediaAttachmentRepo.seed([staleAttachment]);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: TrackingDurableConversationMediaFileManager(
            tempDir,
          ),
          initialMessages: [message],
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('Media unavailable'), findsNothing);

        await messageRepo.saveMessage(message.copyWith(media: const []));
        await pumpUntil(tester, () {
          final screen = tester.widget<ConversationScreen>(
            find.byType(ConversationScreen),
          );
          final visible = screen.messages.firstWhere(
            (candidate) => candidate.id == messageId,
          );
          return visible.media.single.localPath == visibleFile.path;
        });

        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        final visible = screen.messages.firstWhere(
          (candidate) => candidate.id == messageId,
        );
        expect(visible.media.single.localPath, visibleFile.path);
        expect(find.text('Media unavailable'), findsNothing);
      },
    );

    testWidgets(
      '127-Bug-A: own-sent media renders (not "Media unavailable") when send '
      'returns a null message and localPath is relative',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final tempDir = Directory.systemTemp.createTempSync('conv_bug_a_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final attachment = File('${tempDir.path}/pick.png')
          ..writeAsBytesSync(_tinyPngBytes);

        var sendCalled = false;
        // The crux: the send use case returns NO persisted message. Pre-fix,
        // this branch only updated status and left the optimistic message
        // pointing at the deleted picker temp -> "Media unavailable".
        Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          sendCalled = true;
          return (SendChatMessageResult.success, null);
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
          bridge: FakeBridge(),
          // mediaFileManager present (needed by the resolution-under-test) but
          // NO mediaAttachmentRepo, so durable-prep is skipped and the relay
          // result's RELATIVE localPath reaches the post-send branch verbatim
          // (exactly the production shape that triggered Bug A).
          mediaFileManager: TrackingDurableConversationMediaFileManager(
            tempDir,
          ),
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                blobId,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async {
                // Production: own-sent media is stored with a RELATIVE path and
                // the durable plaintext copy lives under media/<peer>/<blob>.png.
                final relPath = 'media/${makeContact().peerId}/$blobId.png';
                File('${tempDir.path}/$relPath')
                  ..createSync(recursive: true)
                  ..writeAsBytesSync(_tinyPngBytes);
                // Mirror production deleteSourceWhenDone: the picker temp the
                // optimistic message points at is gone after upload, so pre-fix
                // the message==null branch would render "Media unavailable".
                if (deleteSourceWhenDone && File(localFilePath).existsSync()) {
                  File(localFilePath).deleteSync();
                }
                return MediaAttachment(
                  id: blobId ?? 'fallback-id',
                  messageId: '',
                  mime: mime,
                  size: _tinyPngBytes.length,
                  mediaType: 'image',
                  localPath: relPath,
                  downloadStatus: 'done',
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                );
              },
          initialAttachments: [attachment],
        );

        await tester.enterText(find.byType(TextField), 'photo');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpUntil(tester, () => sendCalled);
        await tester.pump(const Duration(milliseconds: 500));

        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        final outgoing = screen.messages.where((m) => !m.isIncoming).toList();
        expect(outgoing, isNotEmpty);
        final media = outgoing.last.media;
        expect(media, isNotEmpty);
        // The on-screen attachment must carry the RESOLVED ABSOLUTE durable
        // path (not the deleted picker temp), and the file must exist.
        expect(media.single.localPath, startsWith(tempDir.path));
        expect(media.single.localPath, contains('/media/'));
        expect(File(media.single.localPath!).existsSync(), isTrue);
        expect(find.text('Media unavailable'), findsNothing);
      },
    );

    testWidgets(
      '127-Bug-A: own-sent MULTI-image (3) all render when send returns null',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final tempDir = Directory.systemTemp.createTempSync(
          'conv_bug_a_multi_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final files = List.generate(3, (i) {
          return File('${tempDir.path}/pick$i.png')
            ..writeAsBytesSync(_tinyPngBytes);
        });

        var sendCalled = false;
        Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          sendCalled = true;
          return (SendChatMessageResult.success, null);
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
          bridge: FakeBridge(),
          mediaFileManager: TrackingDurableConversationMediaFileManager(
            tempDir,
          ),
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                blobId,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async {
                final relPath = 'media/${makeContact().peerId}/$blobId.png';
                File('${tempDir.path}/$relPath')
                  ..createSync(recursive: true)
                  ..writeAsBytesSync(_tinyPngBytes);
                if (deleteSourceWhenDone && File(localFilePath).existsSync()) {
                  File(localFilePath).deleteSync();
                }
                return MediaAttachment(
                  id: blobId ?? 'fallback-id',
                  messageId: '',
                  mime: mime,
                  size: _tinyPngBytes.length,
                  mediaType: 'image',
                  localPath: relPath,
                  downloadStatus: 'done',
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                );
              },
          initialAttachments: files,
        );

        await tester.enterText(find.byType(TextField), 'photos');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpUntil(tester, () => sendCalled);
        await tester.pump(const Duration(milliseconds: 500));

        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        final outgoing = screen.messages.where((m) => !m.isIncoming).toList();
        expect(outgoing, isNotEmpty);
        final media = outgoing.last.media;
        expect(media, hasLength(3));
        for (final m in media) {
          expect(m.localPath, contains('/media/'));
          expect(File(m.localPath!).existsSync(), isTrue);
        }
        expect(find.text('Media unavailable'), findsNothing);
      },
    );

    testWidgets(
      '127-Bug-B: foreground send marks the blob in-flight during upload and '
      'clears it after',
      (tester) async {
        mediaUploadInFlightTracker.clearAll();
        addTearDown(mediaUploadInFlightTracker.clearAll);
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final tempDir = Directory.systemTemp.createTempSync('conv_bug_b_wire_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final attachment = File('${tempDir.path}/stable.jpg')
          ..writeAsStringSync('image');

        String? capturedBlobId;
        var inFlightDuringUpload = false;
        String? sentMessageId;

        Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          sentMessageId = messageId;
          final delivered = ConversationMessage(
            id: messageId!,
            contactPeerId: targetPeerId,
            senderPeerId: senderPeerId,
            text: text,
            timestamp: timestamp!,
            status: 'delivered',
            isIncoming: false,
            createdAt: timestamp,
          );
          await messageRepo.saveMessage(delivered);
          return (
            SendChatMessageResult.success,
            delivered.copyWith(media: mediaAttachments ?? const []),
          );
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
          bridge: FakeBridge(),
          mediaAttachmentRepo: mediaAttachmentRepo,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                blobId,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async {
                // The retrier consults this exact tracker — prove the live send
                // owns the blob WHILE uploading so the retrier can't race it.
                capturedBlobId = blobId;
                inFlightDuringUpload =
                    blobId != null &&
                    mediaUploadInFlightTracker.isInFlight(blobId);
                return MediaAttachment(
                  id: blobId ?? 'fallback-upload-id',
                  messageId: '',
                  mime: mime,
                  size: 1,
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath: localFilePath,
                  downloadStatus: 'done',
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                );
              },
          initialAttachments: [attachment],
        );

        await tester.enterText(find.byType(TextField), 'photo');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpUntil(tester, () => sentMessageId != null);
        await tester.pump(const Duration(milliseconds: 300));

        expect(capturedBlobId, isNotNull);
        expect(
          inFlightDuringUpload,
          isTrue,
          reason: 'blob must be in-flight DURING the live upload',
        );
        expect(
          mediaUploadInFlightTracker.isInFlight(capturedBlobId!),
          isFalse,
          reason: 'in-flight mark must be cleared once the send completes',
        );
      },
    );

    testWidgets(
      '127-Bug-B: blob is in-flight at the FIRST (optimistic) persist — before '
      'any upload, closing the LAN-window retrier race',
      (tester) async {
        mediaUploadInFlightTracker.clearAll();
        addTearDown(mediaUploadInFlightTracker.clearAll);
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = InFlightAtFirstSaveMediaRepository();
        final tempDir = Directory.systemTemp.createTempSync(
          'conv_bug_b_early_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final attachment = File('${tempDir.path}/stable.jpg')
          ..writeAsStringSync('image');

        String? capturedBlobId;
        String? sentMessageId;

        Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          sentMessageId = messageId;
          final delivered = ConversationMessage(
            id: messageId!,
            contactPeerId: targetPeerId,
            senderPeerId: senderPeerId,
            text: text,
            timestamp: timestamp!,
            status: 'delivered',
            isIncoming: false,
            createdAt: timestamp,
          );
          await messageRepo.saveMessage(delivered);
          return (
            SendChatMessageResult.success,
            delivered.copyWith(media: mediaAttachments ?? const []),
          );
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
          bridge: FakeBridge(),
          mediaAttachmentRepo: mediaAttachmentRepo,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                blobId,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async {
                capturedBlobId = blobId;
                return MediaAttachment(
                  id: blobId ?? 'fallback-upload-id',
                  messageId: '',
                  mime: mime,
                  size: 1,
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath: localFilePath,
                  downloadStatus: 'done',
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                );
              },
          initialAttachments: [attachment],
        );

        await tester.enterText(find.byType(TextField), 'photo');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpUntil(tester, () => sentMessageId != null);
        await tester.pump(const Duration(milliseconds: 300));

        expect(capturedBlobId, isNotNull);
        // The optimistic persist runs BEFORE the upload loop; with the fix the
        // blob is already in-flight there. Pre-fix (begin only at the relay
        // step) this was false and the retrier could race in.
        expect(
          mediaAttachmentRepo.inFlightAtFirstSave[capturedBlobId],
          isTrue,
          reason:
              'blob must be in-flight at the optimistic persist, before any upload',
        );
      },
    );

    testWidgets(
      'local-peer GIF transport is attempted before relay upload fallback',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final tempDir = Directory.systemTemp.createTempSync('conv_local_gif_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachment = File('${tempDir.path}/local.gif')
          ..writeAsBytesSync(_tinyGifBytes);
        final callOrder = <String>[];
        mediaAttachmentRepo.onSaveAttachment = (attachment) =>
            callOrder.add('save:${attachment.downloadStatus}');
        final p2pService = TrackingLocalMediaP2PService(
          callOrder: callOrder,
          localPeer: true,
          localMediaResult: true,
        );
        String? sentMessageId;
        String? uploadedBlobId;
        String? uploadedLocalPath;

        Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          sentMessageId = messageId;
          if (mediaAttachments != null && mediaAttachmentRepo != null) {
            for (final attachment in mediaAttachments) {
              await mediaAttachmentRepo.saveAttachment(
                attachment.copyWith(messageId: messageId!),
                owner: MediaOwnerLane.direct,
              );
            }
          }

          final delivered = ConversationMessage(
            id: messageId!,
            contactPeerId: targetPeerId,
            senderPeerId: senderPeerId,
            text: text,
            timestamp: timestamp!,
            status: 'delivered',
            isIncoming: false,
            createdAt: timestamp,
          );
          await messageRepo.saveMessage(delivered);
          return (
            SendChatMessageResult.success,
            delivered.copyWith(media: mediaAttachments ?? const []),
          );
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
          bridge: FakeBridge(),
          p2pService: p2pService,
          mediaAttachmentRepo: mediaAttachmentRepo,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                blobId,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async {
                uploadedBlobId = blobId;
                uploadedLocalPath = localFilePath;
                callOrder.add('uploadMedia');
                return MediaAttachment(
                  id: blobId ?? 'unexpected-upload',
                  messageId: '',
                  mime: mime,
                  size: _tinyGifBytes.length,
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath: localFilePath,
                  downloadStatus: 'done',
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                );
              },
          initialAttachments: [attachment],
        );

        await tester.enterText(find.byType(TextField), 'funny');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpUntil(
          tester,
          () => callOrder.contains('uploadMedia') && sentMessageId != null,
        );

        expect(
          callOrder,
          containsAllInOrder([
            'save:upload_pending',
            'sendLocalMedia',
            'uploadMedia',
          ]),
        );
        expect(p2pService.sendLocalMediaCallCount, 1);
        expect(uploadedBlobId, p2pService.lastLocalMediaId);
        // 112 Phase 4 (encrypt once): the LAN leg streams the encrypted
        // artifact built from the SAME source the relay upload consumes —
        // never the raw bytes.
        expect(p2pService.lastLocalMediaPath, '$uploadedLocalPath.enc');

        final optimisticAttachment = mediaAttachmentRepo.allSavedAttachments
            .firstWhere(
              (attachment) => attachment.downloadStatus == 'upload_pending',
            );
        expect(optimisticAttachment.localPath, attachment.path);
        expect(optimisticAttachment.mime, 'image/gif');

        expect(sentMessageId, isNotNull);
        final finalAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(
              sentMessageId!,
              owner: MediaOwnerLane.direct,
            );
        expect(finalAttachments.single.mime, 'image/gif');
        expect(finalAttachments.single.isAnimated, isTrue);
        expect(finalAttachments.single.id, uploadedBlobId);
        expect(finalAttachments.single.downloadStatus, 'done');

        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'shows the inbox transport glyph when inbox delivered message is returned',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );

        final gate = Completer<void>();
        String? sentMessageId;

        Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          sentMessageId = messageId;
          await gate.future;
          final delivered = ConversationMessage(
            id: messageId!,
            contactPeerId: targetPeerId,
            senderPeerId: senderPeerId,
            text: text,
            timestamp: timestamp!,
            status: 'delivered',
            transport: 'inbox',
            isIncoming: false,
            createdAt: timestamp,
          );
          await messageRepo.saveMessage(delivered);
          return (SendChatMessageResult.success, delivered);
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
        );

        await tester.enterText(find.byType(TextField), 'Inbox delivered');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump();

        expect(find.text('Inbox delivered'), findsOneWidget);
        // 184: in-flight ('sending') → single tick on 1:1 (clock→tick).
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);

        gate.complete();
        await tester.pump(const Duration(milliseconds: 50));

        // 155: reached with transport 'inbox' → the inbox transport glyph
        // (Icons.inbox via _transportIcon), never the retired two-tick.
        expect(find.byIcon(Icons.inbox), findsOneWidget);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);
        expect(messageRepo.store[sentMessageId!]!.status, 'delivered');
        expect(messageRepo.store[sentMessageId!]!.transport, 'inbox');
      },
    );

    testWidgets(
      'guards against rapid duplicate sends and resets after success',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );

        final gate = Completer<void>();
        var sendCallCount = 0;

        Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          sendCallCount += 1;
          await gate.future;
          final delivered = ConversationMessage(
            id: messageId!,
            contactPeerId: targetPeerId,
            senderPeerId: senderPeerId,
            text: text,
            timestamp: timestamp!,
            status: 'delivered',
            isIncoming: false,
            createdAt: timestamp,
          );
          await messageRepo.saveMessage(delivered);
          return (SendChatMessageResult.success, delivered);
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
        );

        await tester.enterText(find.byType(TextField), 'First send');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.tap(
          find.byIcon(Icons.arrow_upward_rounded),
          warnIfMissed: false,
        );
        await tester.pump();

        expect(sendCallCount, 1);
        expect(find.text('First send'), findsOneWidget);

        gate.complete();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.enterText(find.byType(TextField), 'Second send');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump();

        expect(sendCallCount, 2);
      },
    );

    testWidgets(
      'shows a newly received message while the conversation stays mounted',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = _FakeIncomingConversationListener(
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        addTearDown(chatListener.dispose);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        expect(find.text('Live receive while open'), findsNothing);

        chatListener.emitIncomingMessage(
          ConversationMessage(
            id: 'live-receive-while-open',
            contactPeerId: makeContact().peerId,
            senderPeerId: makeContact().peerId,
            text: 'Live receive while open',
            timestamp: '2026-02-09T15:30:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-02-09T15:30:01.000Z',
          ),
        );

        await pumpUntil(
          tester,
          () => find.text('Live receive while open').evaluate().isNotEmpty,
        );

        expect(find.text('Live receive while open'), findsOneWidget);
      },
    );

    testWidgets(
      'inserts delayed incoming messages by timestamp instead of arrival order',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = _FakeIncomingConversationListener(
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        addTearDown(chatListener.dispose);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        chatListener.emitIncomingMessage(
          ConversationMessage(
            id: 'newer-live-message',
            contactPeerId: makeContact().peerId,
            senderPeerId: makeContact().peerId,
            text: 'Second image',
            timestamp: '2026-02-09T15:31:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-02-09T15:31:00.500Z',
          ),
        );
        await pumpUntil(
          tester,
          () => find.text('Second image').evaluate().isNotEmpty,
        );

        chatListener.emitIncomingMessage(
          ConversationMessage(
            id: 'older-delayed-message',
            contactPeerId: makeContact().peerId,
            senderPeerId: makeContact().peerId,
            text: 'First delayed image',
            timestamp: '2026-02-09T15:30:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-02-09T15:32:00.000Z',
          ),
        );
        await pumpUntil(
          tester,
          () => find.text('First delayed image').evaluate().isNotEmpty,
        );

        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        expect(screen.messages.map((message) => message.text).toList(), [
          'First delayed image',
          'Second image',
        ]);
      },
    );

    testWidgets('direct unavailable retry downloads failed attachment', (
      tester,
    ) async {
      const messageId = 'incoming-direct-retry';
      const attachmentId = 'incoming-direct-retry-attachment';
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final mediaAttachmentRepo = FakeMediaAttachmentRepository();
      final mediaFileManager = FakeMediaFileManager();
      final tempDir = Directory.systemTemp.createTempSync(
        'conversation_direct_retry_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final chatListener = _FakeIncomingConversationListener(
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      addTearDown(chatListener.dispose);

      final failedAttachment = MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 42,
        mediaType: 'image',
        downloadStatus: 'failed',
        createdAt: '2026-02-09T15:30:00.000Z',
      );
      final message = ConversationMessage(
        id: messageId,
        contactPeerId: makeContact().peerId,
        senderPeerId: makeContact().peerId,
        text: 'retry this image',
        timestamp: '2026-02-09T15:30:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-02-09T15:30:00.000Z',
        media: [failedAttachment],
      );
      await messageRepo.saveMessage(message);
      await mediaAttachmentRepo.saveAttachment(
        failedAttachment,
        owner: MediaOwnerLane.direct,
      );

      var downloadCalls = 0;
      MediaAttachment? requestedAttachment;
      Future<MediaAttachment?> retryDownloadFn({
        required Bridge bridge,
        required MediaAttachmentRepository mediaAttachmentRepo,
        required MediaFileManager mediaFileManager,
        required MediaAttachment attachment,
        required String contactPeerId,
        required MediaOwnerLane owner,
        MessageRepository? messageRepo,
        MediaDownloadIntent? intent,
      }) async {
        downloadCalls++;
        requestedAttachment = attachment;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final recoveredFile = File('${tempDir.path}/recovered-direct-retry.jpg')
          ..writeAsBytesSync(_tinyPngBytes);
        final recovered = attachment.copyWith(
          localPath: recoveredFile.path,
          downloadStatus: 'done',
        );
        await mediaAttachmentRepo.saveAttachment(recovered, owner: owner);
        return recovered;
      }

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        bridge: FakeBridge(),
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
        initialMessages: [message],
        downloadMediaFn: retryDownloadFn,
      );

      var screen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      screen.onRetryUnavailableMedia!(messageId, attachmentId);
      screen.onRetryUnavailableMedia!(messageId, attachmentId);
      await tester.pump();

      expect(downloadCalls, 1);
      expect(requestedAttachment?.id, attachmentId);

      await pumpUntil(tester, () {
        screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        return screen.messages.single.media.single.downloadStatus == 'done';
      });

      final refreshed = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      expect(refreshed.messages.single.id, messageId);
      expect(refreshed.messages.single.media.single.id, attachmentId);
      expect(refreshed.messages.single.media.single.localPath, isNotNull);
    });

    testWidgets(
      'async media refresh cannot resurrect deleted or private-terminal media',
      (tester) async {
        const deletedMessageId = 'async-refresh-deleted';
        const terminalMessageId = 'async-refresh-private-terminal';
        const ordinaryMessageId = 'async-refresh-ordinary';
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final mediaFileManager = FakeMediaFileManager();
        final tempDir = Directory.systemTemp.createTempSync(
          'conversation_async_media_refresh_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );

        ConversationMessage message(String id, int second) {
          final createdAt = '2026-02-09T15:30:0$second.000Z';
          return ConversationMessage(
            id: id,
            contactPeerId: makeContact().peerId,
            senderPeerId: makeContact().peerId,
            text: id,
            timestamp: createdAt,
            status: 'delivered',
            isIncoming: true,
            createdAt: createdAt,
          );
        }

        MediaAttachment attachment(String messageId) => MediaAttachment(
          id: '$messageId-attachment',
          messageId: messageId,
          mime: 'image/png',
          size: _tinyPngBytes.length,
          mediaType: 'image',
          downloadStatus: kMediaDownloadStatusEvicted,
          createdAt: '2026-02-09T15:30:00.000Z',
          ownerLane: MediaOwnerLane.direct,
        );

        final deletedMessage = message(deletedMessageId, 1);
        final terminalMessage = message(terminalMessageId, 2);
        final ordinaryMessage = message(ordinaryMessageId, 3);
        final messages = [deletedMessage, terminalMessage, ordinaryMessage];
        final attachments = messages
            .map((item) => attachment(item.id))
            .toList();
        for (final item in messages) {
          messageRepo.store[item.id] = item;
        }
        mediaAttachmentRepo.seed(attachments);

        final releaseDownloads = Completer<void>();
        final startedAttachmentIds = <String>{};
        Future<MediaAttachment?> controlledDownload({
          required Bridge bridge,
          required MediaAttachmentRepository mediaAttachmentRepo,
          required MediaFileManager mediaFileManager,
          required MediaAttachment attachment,
          required String contactPeerId,
          required MediaOwnerLane owner,
          MessageRepository? messageRepo,
          MediaDownloadIntent? intent,
        }) async {
          startedAttachmentIds.add(attachment.id);
          await releaseDownloads.future;
          if (attachment.messageId == terminalMessageId) {
            throw StateError('force hydrated-media fallback');
          }
          final recoveredFile = File(
            '${tempDir.path}/${attachment.messageId}.png',
          )..writeAsBytesSync(_tinyPngBytes);
          final recovered = attachment.copyWith(
            localPath: recoveredFile.path,
            downloadStatus: 'done',
          );
          await mediaAttachmentRepo.saveAttachment(recovered, owner: owner);
          return recovered;
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          bridge: FakeBridge(),
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
          initialMessages: messages,
          downloadMediaFn: controlledDownload,
        );

        var screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        for (final item in messages) {
          screen.onRetryUnavailableMedia!(item.id, '${item.id}-attachment');
        }
        await pumpUntil(
          tester,
          () => startedAttachmentIds.length == attachments.length,
        );

        messageRepo.store[deletedMessageId] = deletedMessage.copyWith(
          deletedAt: '2026-02-09T15:31:00.000Z',
          deletedByPeerId: makeIdentity().peerId,
          media: const <MediaAttachment>[],
        );
        messageRepo.store[terminalMessageId] = terminalMessage.copyWith(
          privateMediaPolicy: const PrivateMediaPolicy.protected(),
          privateMediaState: PrivateMediaLifecycleState.consumed,
          media: const <MediaAttachment>[],
        );
        releaseDownloads.complete();

        await pumpUntil(tester, () {
          screen = tester.widget<ConversationScreen>(
            find.byType(ConversationScreen),
          );
          final visibleById = {
            for (final item in screen.messages) item.id: item,
          };
          final ordinaryMedia =
              visibleById[ordinaryMessageId]?.media ??
              const <MediaAttachment>[];
          return visibleById[deletedMessageId]?.media.isEmpty == true &&
              visibleById[terminalMessageId]?.media.isEmpty == true &&
              ordinaryMedia.length == 1 &&
              ordinaryMedia.single.downloadStatus == 'done';
        });

        expect(
          find.byKey(
            const ValueKey(
              'media-grid-cell-async-refresh-deleted-async-refresh-deleted-attachment',
            ),
          ),
          findsNothing,
        );
        expect(
          find.byKey(
            const ValueKey(
              'media-grid-cell-async-refresh-private-terminal-async-refresh-private-terminal-attachment',
            ),
          ),
          findsNothing,
        );
        final ordinaryCell = find.byKey(
          const ValueKey(
            'media-grid-cell-async-refresh-ordinary-async-refresh-ordinary-attachment',
          ),
        );
        expect(ordinaryCell, findsOneWidget);
        expect(find.byType(FullScreenTypedMediaViewer), findsNothing);
        await tester.tap(ordinaryCell);
        await pumpUntil(
          tester,
          () => find.byType(FullScreenTypedMediaViewer).evaluate().isNotEmpty,
        );
        expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
      },
    );

    testWidgets(
      'active private identity survives initial and live hydration until terminal',
      (tester) async {
        const initialMessageId = 'private-initial-active';
        const liveMessageId = 'private-live-active';
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );

        ConversationMessage activeParent({
          required String id,
          required String timestamp,
        }) => ConversationMessage(
          id: id,
          contactPeerId: makeContact().peerId,
          senderPeerId: makeContact().peerId,
          text: 'SECRET $id caption',
          timestamp: timestamp,
          status: 'delivered',
          isIncoming: true,
          createdAt: timestamp,
          privateMediaPolicy: const PrivateMediaPolicy.protected(),
          privateMediaState: PrivateMediaLifecycleState.available,
        );

        MediaAttachment privateAttachment(String messageId) => MediaAttachment(
          id: '$messageId-attachment',
          messageId: messageId,
          mime: 'image/png',
          size: _tinyPngBytes.length,
          mediaType: 'image',
          downloadStatus: 'done',
          createdAt: '2026-02-09T15:40:00.000Z',
          ownerLane: MediaOwnerLane.direct,
        );

        final initialParent = activeParent(
          id: initialMessageId,
          timestamp: '2026-02-09T15:40:00.000Z',
        );
        final initialAttachment = privateAttachment(initialMessageId);
        messageRepo.store[initialMessageId] = initialParent;
        mediaAttachmentRepo.seed([initialAttachment]);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        ConversationScreen screen() =>
            tester.widget<ConversationScreen>(find.byType(ConversationScreen));
        ConversationMessage? maybeVisible(String id) {
          final matches = screen().messages.where(
            (message) => message.id == id,
          );
          return matches.isEmpty ? null : matches.single;
        }

        ConversationMessage visible(String id) => maybeVisible(id)!;

        await pumpUntil(tester, () => maybeVisible(initialMessageId) != null);
        expect(
          visible(initialMessageId).media.map((attachment) => attachment.id),
          <String>[initialAttachment.id],
        );
        await pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey('private-media-card-visual'))
              .evaluate()
              .isNotEmpty,
        );
        expect(
          find.byKey(const ValueKey('private-media-unsupported')),
          findsNothing,
        );
        expect(find.textContaining('SECRET'), findsNothing);
        expect(
          find.byKey(
            const ValueKey(
              'media-grid-cell-private-initial-active-private-initial-active-attachment',
            ),
          ),
          findsNothing,
          reason: 'private bytes stay redacted from the ordinary LetterCard',
        );

        final liveParent = activeParent(
          id: liveMessageId,
          timestamp: '2026-02-09T15:41:00.000Z',
        );
        final liveAttachment = privateAttachment(liveMessageId);
        await mediaAttachmentRepo.saveAttachment(
          liveAttachment,
          owner: MediaOwnerLane.direct,
        );
        await messageRepo.saveMessage(liveParent);

        await pumpUntil(tester, () => maybeVisible(liveMessageId) != null);
        expect(
          visible(liveMessageId).media.map((attachment) => attachment.id),
          <String>[liveAttachment.id],
        );
        await pumpUntil(
          tester,
          () =>
              find
                  .byKey(const ValueKey('private-media-card-visual'))
                  .evaluate()
                  .length ==
              2,
        );
        expect(
          find.byKey(const ValueKey('private-media-unsupported')),
          findsNothing,
        );
        expect(find.textContaining('SECRET'), findsNothing);

        await messageRepo.saveMessage(
          liveParent.copyWith(
            privateMediaState: PrivateMediaLifecycleState.consumed,
            media: const <MediaAttachment>[],
          ),
        );
        await pumpUntil(
          tester,
          () =>
              maybeVisible(liveMessageId)?.media.isEmpty == true &&
              find
                      .byKey(const ValueKey('private-terminal-consumed'))
                      .evaluate()
                      .length ==
                  1,
        );

        expect(
          find.byKey(const ValueKey('private-media-card-visual')),
          findsOneWidget,
          reason: 'the initial active parent remains openable',
        );
        expect(visible(initialMessageId).media.single.id, initialAttachment.id);
        expect(visible(liveMessageId).media, isEmpty);
        expect(find.textContaining('SECRET'), findsNothing);
      },
    );

    testWidgets(
      'loadInitialPage does not overwrite newer streamed media repair',
      (tester) async {
        const messageId = 'incoming-stale-load';
        const attachmentId = 'incoming-stale-load-attachment';
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository()
          ..getMessagesPageGate = Completer<void>();
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final chatListener = _FakeIncomingConversationListener(
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        addTearDown(chatListener.dispose);

        final staleAttachment = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 42,
          mediaType: 'image',
          downloadStatus: 'failed',
          createdAt: '2026-02-09T15:30:00.000Z',
        );
        final repairedAttachment = staleAttachment.copyWith(
          localPath: '/tmp/repaired-stale-load.jpg',
          downloadStatus: 'done',
        );
        final staleMessage = ConversationMessage(
          id: messageId,
          contactPeerId: makeContact().peerId,
          senderPeerId: makeContact().peerId,
          text: 'stale load image',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:30:00.000Z',
          media: [staleAttachment],
        );
        messageRepo.getMessagesPageSnapshot = [staleMessage];
        mediaAttachmentRepo.seedAttachments(
          messageId: messageId,
          attachments: [staleAttachment],
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        chatListener.emitIncomingMessage(
          staleMessage.copyWith(media: [repairedAttachment]),
        );
        await pumpUntil(
          tester,
          () => tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .messages
              .any(
                (message) =>
                    message.id == messageId &&
                    message.media.single.downloadStatus == 'done',
              ),
        );

        messageRepo.getMessagesPageGate!.complete();
        await tester.pump(const Duration(milliseconds: 400));

        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        expect(screen.messages.single.id, messageId);
        expect(screen.messages.single.media.single.id, attachmentId);
        expect(screen.messages.single.media.single.downloadStatus, 'done');
        expect(screen.messages.single.media.single.localPath, isNotNull);
      },
    );
  });

  group('ConversationWired 131 stale-on-open recovery', () {
    ConversationMessage makeMsg({
      required String id,
      required String text,
      required bool isIncoming,
      required String ts,
    }) => ConversationMessage(
      id: id,
      contactPeerId: makeContact().peerId,
      senderPeerId: makeContact().peerId,
      text: text,
      timestamp: ts,
      status: 'delivered',
      isIncoming: isIncoming,
      createdAt: ts,
    );

    testWidgets(
      'notification-tap entry drains and re-fetches to surface a message that '
      'arrived after the initial load',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        // Existing history is what the one-shot initial DB read returns.
        final old = makeMsg(
          id: 'old-1',
          text: 'old history',
          isIncoming: false,
          ts: '2026-05-04T09:39:00.000Z',
        );
        messageRepo.store[old.id] = old;
        // The just-received reply only lands in the DB once the relay drains.
        final fresh = makeMsg(
          id: 'fresh-1',
          text: 'just received reply',
          isIncoming: true,
          ts: '2026-05-04T14:05:00.000Z',
        );
        final p2p = DrainPersistsP2PService(
          repo: messageRepo,
          pending: [fresh],
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          p2pService: p2p,
          notificationTappedAt: DateTime.utc(2026, 5, 4, 14, 5),
        );

        await pumpUntil(
          tester,
          () => tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .messages
              .any((m) => m.id == 'fresh-1'),
        );

        expect(p2p.drainCallCount, 1);
        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        expect(screen.messages.any((m) => m.id == 'old-1'), isTrue);
        expect(screen.messages.any((m) => m.id == 'fresh-1'), isTrue);
      },
    );

    testWidgets('plain (orbit) entry does NOT auto-drain on open', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final p2p = DrainPersistsP2PService(repo: messageRepo, pending: []);

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        p2pService: p2p,
        // No notificationTappedAt — this is an orbit/contact-list open.
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(p2p.drainCallCount, 0);
    });

    testWidgets(
      'app resume drains and re-fetches to surface a backgrounded message',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final fresh = makeMsg(
          id: 'resume-fresh-1',
          text: 'arrived while backgrounded',
          isIncoming: true,
          ts: '2026-05-04T14:06:00.000Z',
        );
        final p2p = DrainPersistsP2PService(
          repo: messageRepo,
          pending: [fresh],
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          p2pService: p2p,
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(p2p.drainCallCount, 0);

        // The test binding starts in `detached`; the only valid transition is
        // to `resumed`, which is exactly the foreground event Fix B handles.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );

        await pumpUntil(
          tester,
          () => tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .messages
              .any((m) => m.id == 'resume-fresh-1'),
        );
        expect(p2p.drainCallCount, greaterThanOrEqualTo(1));
      },
    );

    testWidgets(
      'an INCOMING message persisted via the repo-change stream is rendered',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        // saveMessage emits on messageChanges (NOT on incomingMessageStream),
        // mirroring a relay drain persisting an incoming message while open.
        await messageRepo.saveMessage(
          makeMsg(
            id: 'repo-incoming-1',
            text: 'surfaced via repo change',
            isIncoming: true,
            ts: '2026-05-04T14:07:00.000Z',
          ),
        );

        await pumpUntil(
          tester,
          () => tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .messages
              .any((m) => m.id == 'repo-incoming-1'),
        );
        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        expect(screen.messages.any((m) => m.id == 'repo-incoming-1'), isTrue);
      },
    );

    testWidgets(
      'a resume during an in-flight notif_tap drain is coalesced, not dropped',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final fresh1 = makeMsg(
          id: 'co-1',
          text: 'first backlog',
          isIncoming: true,
          ts: '2026-05-04T14:05:00.000Z',
        );
        final fresh2 = makeMsg(
          id: 'co-2',
          text: 'second backlog',
          isIncoming: true,
          ts: '2026-05-04T14:06:00.000Z',
        );
        final gate = Completer<void>();
        final p2p = GatedDrainP2PService(
          repo: messageRepo,
          pending: [fresh1, fresh2],
        )..gate = gate;

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          p2pService: p2p,
          notificationTappedAt: DateTime.utc(2026, 5, 4, 14, 5),
        );
        // notif_tap drain is in-flight, blocked on the gate.
        await tester.pump();
        expect(p2p.drainCallCount, 1);

        // A resume arrives mid-drain — must be remembered, not dropped.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(
          p2p.drainCallCount,
          1,
          reason: 'still coalesced behind the gate',
        );

        // Release the in-flight drain → the coalesced pass runs a 2nd drain.
        gate.complete();
        await pumpUntil(tester, () => p2p.drainCallCount >= 2);
        expect(p2p.drainCallCount, greaterThanOrEqualTo(2));
        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        expect(screen.messages.any((m) => m.id == 'co-1'), isTrue);
        expect(screen.messages.any((m) => m.id == 'co-2'), isTrue);
      },
    );

    testWidgets(
      'a throwing drain does not crash and clears the guard so a later resume retries',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final fresh = makeMsg(
          id: 'err-then-ok-1',
          text: 'lands on retry',
          isIncoming: true,
          ts: '2026-05-04T14:07:00.000Z',
        );
        final p2p = ThrowingDrainP2PService(
          repo: messageRepo,
          pending: [fresh],
          throwTimes: 1,
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          p2pService: p2p,
          notificationTappedAt: DateTime.utc(2026, 5, 4, 14, 7),
        );
        await tester.pump(const Duration(milliseconds: 400));
        // First drain threw — screen survived, no exception escaped.
        expect(find.byType(ConversationScreen), findsOneWidget);
        expect(p2p.drainCallCount, 1);

        // Guard was cleared in finally, so a later resume drains successfully.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pumpUntil(
          tester,
          () => tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .messages
              .any((m) => m.id == 'err-then-ok-1'),
        );
        expect(p2p.drainCallCount, greaterThanOrEqualTo(2));
      },
    );

    testWidgets(
      'a live incoming message arriving on BOTH streams renders exactly once',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = _FakeIncomingConversationListener(
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        addTearDown(chatListener.dispose);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        final m = makeMsg(
          id: 'dual-1',
          text: 'arrives on both streams',
          isIncoming: true,
          ts: '2026-05-04T14:08:00.000Z',
        );
        // Production order: persist (messageChanges) then live emit.
        await messageRepo.saveMessage(m);
        chatListener.emitIncomingMessage(m);

        await pumpUntil(
          tester,
          () => tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .messages
              .any((x) => x.id == 'dual-1'),
        );
        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        expect(
          screen.messages.where((x) => x.id == 'dual-1').length,
          1,
          reason: 'id-keyed upsert dedupes the double-path',
        );
      },
    );

    // TC-10 (145): the "catching up" affordance is threaded from the in-flight
    // drain into the view.
    testWidgets(
      'syncing affordance is visible during an in-flight notif-tap drain and '
      'gone after it completes',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final fresh = makeMsg(
          id: 'sync-fresh-1',
          text: 'arrives via the gated drain',
          isIncoming: true,
          ts: '2026-05-04T14:05:00.000Z',
        );
        final gate = Completer<void>();
        final p2p = GatedDrainP2PService(repo: messageRepo, pending: [fresh])
          ..gate = gate;

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          p2pService: p2p,
          notificationTappedAt: DateTime.utc(2026, 5, 4, 14, 5),
        );

        // Drain is in-flight behind the gate → affordance visible.
        await tester.pump();
        expect(
          find.byKey(const ValueKey('conversation-syncing-banner')),
          findsOneWidget,
          reason: 'affordance shows while the notif-tap drain is in flight',
        );

        // Release the drain → it completes → affordance clears.
        gate.complete();
        await pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey('conversation-syncing-banner'))
              .evaluate()
              .isEmpty,
        );
        expect(
          find.byKey(const ValueKey('conversation-syncing-banner')),
          findsNothing,
        );
      },
    );

    // TC-12 (145): the post-drain "live render" timing event, emitted exactly
    // once per notif-tap when the drain surfaces a new incoming message — in
    // addition to the existing stale-render event.
    testWidgets(
      'live-render timing event is emitted exactly once after a notif-tap drain '
      'surfaces a new message (in addition to the stale-render event)',
      (tester) async {
        final captured = <Map<String, dynamic>>[];
        debugSetFlowEventSink(captured.add);
        addTearDown(() => debugSetFlowEventSink(null));

        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final fresh = makeMsg(
          id: 'live-fresh-1',
          text: 'surfaced by the drain',
          isIncoming: true,
          ts: '2026-05-04T14:05:00.000Z',
        );
        final p2p = DrainPersistsP2PService(
          repo: messageRepo,
          pending: [fresh],
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          p2pService: p2p,
          notificationTappedAt: DateTime.utc(2026, 5, 4, 14, 5),
        );
        await pumpUntil(
          tester,
          () => tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .messages
              .any((m) => m.id == 'live-fresh-1'),
        );

        final live = captured
            .where(
              (e) => e['event'] == 'NOTIFICATION_TAP_TO_LIVE_MESSAGE_TIMING',
            )
            .toList();
        expect(live, hasLength(1));
        expect((live.first['details'] as Map)['addedIncoming'], isTrue);
        expect((live.first['details'] as Map)['milestone'], 'live_render');

        // The live-render event is in ADDITION to the existing stale-render one.
        final stale = captured
            .where((e) => e['event'] == 'NOTIFICATION_TAP_TO_MESSAGE_TIMING')
            .toList();
        expect(stale, isNotEmpty);
        expect((stale.first['details'] as Map)['milestone'], 'stale_render');
      },
    );

    testWidgets(
      'live-render timing event is not double-emitted across coalesced drain '
      'passes',
      (tester) async {
        final captured = <Map<String, dynamic>>[];
        debugSetFlowEventSink(captured.add);
        addTearDown(() => debugSetFlowEventSink(null));

        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final fresh1 = makeMsg(
          id: 'live-co-1',
          text: 'first backlog',
          isIncoming: true,
          ts: '2026-05-04T14:05:00.000Z',
        );
        final fresh2 = makeMsg(
          id: 'live-co-2',
          text: 'second backlog',
          isIncoming: true,
          ts: '2026-05-04T14:06:00.000Z',
        );
        final gate = Completer<void>();
        final p2p = GatedDrainP2PService(
          repo: messageRepo,
          pending: [fresh1, fresh2],
        )..gate = gate;

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          p2pService: p2p,
          notificationTappedAt: DateTime.utc(2026, 5, 4, 14, 5),
        );
        await tester.pump();
        // A resume mid-drain coalesces into a second pass behind the gate.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        gate.complete();
        await pumpUntil(tester, () => p2p.drainCallCount >= 2);

        final live = captured
            .where(
              (e) => e['event'] == 'NOTIFICATION_TAP_TO_LIVE_MESSAGE_TIMING',
            )
            .toList();
        expect(
          live,
          hasLength(1),
          reason: 'one-shot latch prevents double-emit across coalesced passes',
        );
      },
    );

    testWidgets('plain (orbit) entry emits no live-render timing event', (
      tester,
    ) async {
      final captured = <Map<String, dynamic>>[];
      debugSetFlowEventSink(captured.add);
      addTearDown(() => debugSetFlowEventSink(null));

      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final p2p = DrainPersistsP2PService(repo: messageRepo, pending: []);

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        p2pService: p2p,
        // No notificationTappedAt — orbit/contact-list open.
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        captured.where(
          (e) => e['event'] == 'NOTIFICATION_TAP_TO_LIVE_MESSAGE_TIMING',
        ),
        isEmpty,
      );
    });

    // TC-13 (145): the drain-refetch event carries a numeric per-pass duration.
    testWidgets('CONV_FL_NOTIF_DRAIN_REFETCH carries a numeric drainMs', (
      tester,
    ) async {
      final captured = <Map<String, dynamic>>[];
      debugSetFlowEventSink(captured.add);
      addTearDown(() => debugSetFlowEventSink(null));

      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final fresh = makeMsg(
        id: 'drainms-1',
        text: 'surfaced by the drain',
        isIncoming: true,
        ts: '2026-05-04T14:05:00.000Z',
      );
      final p2p = DrainPersistsP2PService(repo: messageRepo, pending: [fresh]);

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        p2pService: p2p,
        notificationTappedAt: DateTime.utc(2026, 5, 4, 14, 5),
      );
      await pumpUntil(
        tester,
        () => tester
            .widget<ConversationScreen>(find.byType(ConversationScreen))
            .messages
            .any((m) => m.id == 'drainms-1'),
      );

      final refetch = captured
          .where((e) => e['event'] == 'CONV_FL_NOTIF_DRAIN_REFETCH')
          .toList();
      expect(refetch, isNotEmpty);
      final details = refetch.first['details'] as Map;
      expect(details['trigger'], 'notif_tap');
      expect(details['drainMs'], isA<int>());
      expect(details['drainMs'], greaterThanOrEqualTo(0));
    });
  });

  group('ConversationWired media props', () {
    testWidgets('passes onAttach to screen — shows bottom sheet on tap', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
      );

      // Tap the attachment button
      await tester.tap(find.byIcon(Icons.add_rounded));
      // Use pump with duration instead of pumpAndSettle because
      // AmbientBackground has a repeating 8s animation that never settles.
      await tester.pump(const Duration(milliseconds: 500));

      // Bottom sheet should show Media Library, Take Photo, and Record Video options
      expect(find.text('Media Library'), findsOneWidget);
      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Record Video'), findsOneWidget);
    });

    // 204 TC-204-02 (BUG-1, 1:1): the attach sheet must expose an explicit
    // Cancel affordance so a user who changed their mind can go back to the
    // chat. RED on HEAD: no Cancel row => the key findsNothing.
    testWidgets('attach sheet shows a Cancel affordance (1:1)', (tester) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
      );

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump(const Duration(milliseconds: 500));

      // Cancel is additive: the three pickers are still present.
      expect(find.text('Media Library'), findsOneWidget);
      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Record Video'), findsOneWidget);

      // Anchor on the ValueKey (not the icon/text, which are ambiguous with the
      // delete sheet / recording overlay).
      final cancel = find.byKey(ConversationWired.attachSheetCancelKey);
      expect(cancel, findsOneWidget);
      expect(
        find.descendant(of: cancel, matching: find.text('Cancel')),
        findsOneWidget,
      );
    });

    // 204 TC-204-03 (BUG-1, 1:1): Cancel dismisses the sheet ONLY — it must not
    // invoke a picker and must not clear already-staged media.
    testWidgets(
      'Cancel closes the attach sheet without picking and keeps staged media (1:1)',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final tempDir = Directory.systemTemp.createTempSync(
          'conversation_cancel_staged_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachment = File('${tempDir.path}/staged.jpg')
          ..writeAsStringSync('image');
        final mediaPicker = FakeMediaPicker();

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          mediaPicker: mediaPicker,
          initialAttachments: [attachment],
        );

        // Baseline: one attachment is staged, and no pick has happened yet.
        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(mediaPicker.pickMultipleMediaCalls, 0);

        // Open the sheet, then Cancel it.
        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Media Library'), findsOneWidget);

        // Invoke the Cancel tile's onTap directly (the sheet extends below the
        // short test viewport, so a hit-test tap would miss) — mirrors how this
        // file drives the picker tiles.
        tester
            .widget<ListTile>(
              find.byKey(ConversationWired.attachSheetCancelKey),
            )
            .onTap!();
        await tester.pump(const Duration(milliseconds: 500));

        // SHEET_DISMISSED: the picker options are gone.
        expect(find.text('Media Library'), findsNothing);
        // NOT PICK_INVOKED: Cancel never triggered a gallery pick.
        expect(mediaPicker.pickMultipleMediaCalls, 0);
        // STAGED_INTACT: the previously staged attachment survives.
        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
      },
    );

    testWidgets('does not show AttachmentPreviewStrip initially', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
      );

      expect(find.byType(AttachmentPreviewStrip), findsNothing);
    });

    // 149 TC-05: an oversized pick marks the chip invalid AT PICK TIME (no send
    // press) and shows NO snackbar — the chip carries the reason.
    testWidgets(
      'oversized 1:1 pick marks the chip invalid at pick time and shows no '
      'snackbar',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final tempDir = Directory.systemTemp.createTempSync('conv_oversized_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final bigImage = File('${tempDir.path}/big.jpg')
          ..writeAsBytesSync(_tinyPngBytes);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          initialPendingMedia: [
            PendingComposerMedia(
              file: bigImage,
              budgetBytes: 30 * 1024 * 1024, // > 25 MB image cap
            ),
          ],
        );

        expect(
          find.byKey(const ValueKey('attachment-invalid-0')),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(
            SnackBar,
            'The media is too large even after compression.',
          ),
          findsNothing,
        );
        // The attachment is retained, not silently discarded.
        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
      },
    );

    // 149 TC-05b: an oversized GIF pick marks the chip with the GIF caption
    // (distinct from the generic too-large copy), not a snackbar.
    testWidgets(
      'oversized 1:1 GIF pick marks the chip with the GIF caption (not a '
      'snackbar)',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final tempDir = Directory.systemTemp.createTempSync('conv_gif_over_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final bigGif = File('${tempDir.path}/big.gif')
          ..writeAsBytesSync(_tinyGifBytes);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          initialPendingMedia: [
            PendingComposerMedia(
              file: bigGif,
              budgetBytes: 30 * 1024 * 1024, // > 25 MB GIF cap
            ),
          ],
        );

        expect(find.text('GIF too big'), findsOneWidget);
        expect(find.text('Too large'), findsNothing);
        expect(
          find.widgetWithText(
            SnackBar,
            'GIF files larger than 25 MB cannot be added.',
          ),
          findsNothing,
        );
      },
    );

    // 149 TC-09: tapping Send is a no-op while an invalid attachment is present
    // (Send icon still shown, draft NOT cleared), and re-enables once removed.
    testWidgets(
      'Send tap is a no-op while an invalid attachment is present, and '
      're-enables once all are removed (1:1)',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final tempDir = Directory.systemTemp.createTempSync('conv_send_gate_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final bigImage = File('${tempDir.path}/big.jpg')
          ..writeAsBytesSync(_tinyPngBytes);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          initialText: 'hello',
          initialPendingMedia: [
            PendingComposerMedia(file: bigImage, budgetBytes: 30 * 1024 * 1024),
          ],
        );

        expect(
          find.byKey(const ValueKey('attachment-invalid-0')),
          findsOneWidget,
        );
        // ComposeArea Send is gated off while invalid present.
        expect(
          tester
              .widget<ComposeArea>(find.byType(ComposeArea))
              .hasInvalidAttachment,
          isTrue,
        );

        // Send affordance is the up-arrow (NOT the mic) and tapping it is inert:
        // _onSendPressed never runs, so the draft is NOT cleared. (Dropping the
        // `&& !hasInvalidAttachment` onTap term would clear it — the mutation.)
        expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'hello',
        );

        // Remove the offending attachment → chip clears, Send re-enables.
        await tester.tap(find.byIcon(Icons.close));
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          find.byKey(const ValueKey('attachment-invalid-0')),
          findsNothing,
        );
        expect(find.byIcon(Icons.error_outline), findsNothing);
        expect(
          tester
              .widget<ComposeArea>(find.byType(ComposeArea))
              .hasInvalidAttachment,
          isFalse,
        );
      },
    );

    // 149 TC-11: two oversized picks mark BOTH chips and keep Send disabled
    // until both are removed (mark-all, not first-failure).
    testWidgets(
      'two oversized picks mark BOTH chips invalid and keep Send disabled '
      'until both are removed (1:1 multi-invalid)',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final tempDir = Directory.systemTemp.createTempSync('conv_multi_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final big1 = File('${tempDir.path}/big1.jpg')
          ..writeAsBytesSync(_tinyPngBytes);
        final big2 = File('${tempDir.path}/big2.jpg')
          ..writeAsBytesSync(_tinyPngBytes);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          initialText: 'hi',
          initialPendingMedia: [
            PendingComposerMedia(file: big1, budgetBytes: 30 * 1024 * 1024),
            PendingComposerMedia(file: big2, budgetBytes: 30 * 1024 * 1024),
          ],
        );

        expect(
          find.byKey(const ValueKey('attachment-invalid-0')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('attachment-invalid-1')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<ComposeArea>(find.byType(ComposeArea))
              .hasInvalidAttachment,
          isTrue,
        );

        // Send is inert while ANY invalid present: tapping it preserves the
        // draft (mutation: dropping the onTap term clears it).
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'hi',
        );

        // Remove one → the OTHER stays invalid (index recomputed); Send still
        // disabled.
        await tester.tap(find.byIcon(Icons.close).first);
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          find.byKey(const ValueKey('attachment-invalid-0')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('attachment-invalid-1')),
          findsNothing,
        );
        expect(
          tester
              .widget<ComposeArea>(find.byType(ComposeArea))
              .hasInvalidAttachment,
          isTrue,
        );

        // Remove the last → no red chips + Send re-enabled.
        await tester.tap(find.byIcon(Icons.close));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byIcon(Icons.error_outline), findsNothing);
        expect(
          tester
              .widget<ComposeArea>(find.byType(ComposeArea))
              .hasInvalidAttachment,
          isFalse,
        );
      },
    );

    testWidgets(
      '1:1 total-size overflow (individually-valid attachments) shows a '
      'strip-level note and disables Send (no per-chip)',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final tempDir = Directory.systemTemp.createTempSync('conv_total_over_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        File video(String name) =>
            File('${tempDir.path}/$name.mp4')..writeAsBytesSync(_tinyPngBytes);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          initialText: 'hello',
          initialPendingMedia: [
            // Each 200 MB video is below its 250 MB per-file cap, while their
            // 600 MB total exceeds the 500 MB whole-message budget.
            PendingComposerMedia(
              file: video('v1'),
              budgetBytes: 200 * 1024 * 1024,
            ),
            PendingComposerMedia(
              file: video('v2'),
              budgetBytes: 200 * 1024 * 1024,
            ),
            PendingComposerMedia(
              file: video('v3'),
              budgetBytes: 200 * 1024 * 1024,
            ),
          ],
        );

        for (var index = 0; index < 3; index++) {
          expect(
            find.byKey(ValueKey('attachment-invalid-$index')),
            findsNothing,
          );
        }
        expect(
          find.byKey(const ValueKey('attachment-total-overflow')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<ComposeArea>(find.byType(ComposeArea))
              .hasInvalidAttachment,
          isTrue,
        );

        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'hello',
        );
        expect(messageRepo.store, isEmpty);
      },
    );

    // 149 TC-12: removing a valid sibling shifts the invalid chip to the
    // correct remaining index (the set is recomputed, never a stale snapshot).
    testWidgets(
      'removing a valid attachment shifts the invalid chip to the correct '
      'remaining index (1:1)',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final tempDir = Directory.systemTemp.createTempSync('conv_shift_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final small = File('${tempDir.path}/small.jpg')
          ..writeAsBytesSync(_tinyPngBytes);
        final big = File('${tempDir.path}/big.jpg')
          ..writeAsBytesSync(_tinyPngBytes);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          initialPendingMedia: [
            PendingComposerMedia(file: small, budgetBytes: 1024), // valid @ 0
            PendingComposerMedia(
              file: big,
              budgetBytes: 30 * 1024 * 1024,
            ), // invalid @ 1
          ],
        );

        expect(
          find.byKey(const ValueKey('attachment-invalid-0')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('attachment-invalid-1')),
          findsOneWidget,
        );

        // Remove the valid index 0 → the oversized item shifts to index 0.
        await tester.tap(find.byIcon(Icons.close).first);
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          find.byKey(const ValueKey('attachment-invalid-0')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('attachment-invalid-1')),
          findsNothing,
        );
        // Only one chip remains, and it carries the warning.
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
      },
    );

    testWidgets(
      'gallery multi-video batches keep one processing tile with honest batch context',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final tempDir = Directory.systemTemp.createTempSync(
          'conv_gallery_batch_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final firstVideo = File('${tempDir.path}/video-1.mp4')
          ..writeAsBytesSync(_tinyPngBytes);
        final stillImage = File('${tempDir.path}/image-1.jpg')
          ..writeAsBytesSync(_tinyPngBytes);
        final secondVideo = File('${tempDir.path}/video-2.mp4')
          ..writeAsBytesSync(_tinyPngBytes);
        final processedFirstVideo = File('${tempDir.path}/processed-1.mp4')
          ..writeAsBytesSync(_tinyPngBytes);
        final processedImage = File('${tempDir.path}/processed-1.jpg')
          ..writeAsBytesSync(_tinyPngBytes);
        final processedSecondVideo = File('${tempDir.path}/processed-2.mp4')
          ..writeAsBytesSync(_tinyPngBytes);

        final mediaPicker = FakeMediaPicker()
          ..multipleMediaResult = [
            XFile(firstVideo.path),
            XFile(stillImage.path),
            XFile(secondVideo.path),
          ];
        final videoResults = [
          Completer<VideoProcessResult>(),
          Completer<VideoProcessResult>(),
        ];
        final imageResult = Completer<XFile?>();
        var imageCompressionStarted = false;
        final progressCallbacks = <void Function(double)?>[];
        var videoCallCount = 0;
        final imageProcessor = ImageProcessor(
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async {
                if (path == stillImage.path) {
                  imageCompressionStarted = true;
                  return imageResult.future;
                }
                return null;
              },
          compressVideo:
              ({
                required path,
                required compress,
                void Function(double progress)? onProgress,
              }) async {
                progressCallbacks.add(onProgress);
                final result = videoResults[videoCallCount];
                videoCallCount++;
                return result.future;
              },
        );

        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          imageProcessor: imageProcessor,
          mediaPicker: mediaPicker,
        );

        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump(const Duration(milliseconds: 500));
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Media Library'))
            .onTap!();
        await pumpUntil(tester, () => progressCallbacks.length == 1);

        progressCallbacks.single!(35);
        await tester.pump();

        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(find.text('Processing (1/2)'), findsOneWidget);
        expect(find.text('35%'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        videoResults[0].complete(
          VideoProcessResult(path: processedFirstVideo.path),
        );
        await pumpUntil(tester, () => imageCompressionStarted);
        await tester.pump();

        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(find.text('Processing (1/2)'), findsOneWidget);

        imageResult.complete(XFile(processedImage.path));
        await pumpUntil(tester, () => progressCallbacks.length == 2);

        progressCallbacks.last!(60);
        await tester.pump();

        expect(find.text('Processing (2/2)'), findsOneWidget);
        expect(find.text('60%'), findsOneWidget);

        videoResults[1].complete(
          VideoProcessResult(path: processedSecondVideo.path),
        );
        await tester.pump();
      },
    );

    testWidgets('recorded single video keeps single-item processing copy', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final tempDir = Directory.systemTemp.createTempSync('conv_camera_video_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final cameraVideo = File('${tempDir.path}/camera-video.mp4')
        ..writeAsBytesSync(_tinyPngBytes);
      final processedVideo = File('${tempDir.path}/camera-video-out.mp4')
        ..writeAsBytesSync(_tinyPngBytes);

      final mediaPicker = FakeMediaPicker()
        ..videoResult = XFile(cameraVideo.path);
      final result = Completer<VideoProcessResult>();
      void Function(double progress)? progressCallback;
      final imageProcessor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async => null,
        compressVideo:
            ({
              required path,
              required compress,
              void Function(double progress)? onProgress,
            }) async {
              progressCallback = onProgress;
              return result.future;
            },
      );

      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        imageProcessor: imageProcessor,
        mediaPicker: mediaPicker,
      );

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump(const Duration(milliseconds: 500));
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Record Video'))
          .onTap!();
      await tester.pump();

      expect(progressCallback, isNotNull);

      progressCallback!(40);
      await tester.pump();

      expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
      expect(find.text('Processing'), findsOneWidget);
      expect(find.text('Processing (1/1)'), findsNothing);
      expect(find.text('40%'), findsOneWidget);

      result.complete(VideoProcessResult(path: processedVideo.path));
      await tester.pump();
    });

    testWidgets(
      'recording ticks update composer without rebuilding header or message list',
      (tester) async {
        final contact = makeContact();
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final recorder = FakeAudioRecorderService()..fakeDurationMs = 100;
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-rec-1',
            contactPeerId: contact.peerId,
            text: 'Seed message',
            senderPeerId: contact.peerId,
            timestamp: DateTime.now().toUtc().toIso8601String(),
            status: 'delivered',
            isIncoming: true,
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          audioRecorderService: recorder,
        );

        final headerFinder = find.byType(ConversationHeader);
        final listFinder = find.byKey(const ValueKey('messages'));
        final headerElement = tester.element(headerFinder);
        final listElement = tester.element(listFinder);
        final initialPageLoads = messageRepo.getMessagesPageCalls;

        final gesture = await tester.startGesture(
          tester.getCenter(find.byIcon(Icons.mic_rounded)),
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await tester.pump();

        recorder.emitDuration(const Duration(seconds: 1));
        recorder.emitAmplitude(0.3);
        await tester.pump();

        expect(find.byType(RecordingOverlay), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('0:01'), findsOneWidget);
        expect(identical(headerElement, tester.element(headerFinder)), isTrue);
        expect(identical(listElement, tester.element(listFinder)), isTrue);
        expect(messageRepo.getMessagesPageCalls, initialPageLoads);

        await gesture.up();
        await tester.pump();
      },
    );

    testWidgets('text-only send works without bridge or media repos', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      List<MediaAttachment>? passedMedia;
      MediaAttachmentRepository? passedMediaRepo;

      Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
        required P2PService p2pService,
        required MessageRepository messageRepo,
        required String targetPeerId,
        required String text,
        required String senderPeerId,
        required String senderUsername,
        String? messageId,
        required bool preassignedMessageIdIsFresh,
        String? timestamp,
        Bridge? bridge,
        String? recipientMlKemPublicKey,
        String? quotedMessageId,
        List<MediaAttachment>? mediaAttachments,
        PrivateMediaPolicy? privateMediaPolicy,
        MediaAttachmentRepository? mediaAttachmentRepo,
        TransportMetrics? transportMetrics,
        DirectEventFanoutAuthoring? directEventFanout,
      }) async {
        passedMedia = mediaAttachments;
        passedMediaRepo = mediaAttachmentRepo;

        final delivered = ConversationMessage(
          id: messageId!,
          contactPeerId: targetPeerId,
          senderPeerId: senderPeerId,
          text: text,
          timestamp: timestamp!,
          status: 'delivered',
          isIncoming: false,
          createdAt: timestamp,
        );
        await messageRepo.saveMessage(delivered);
        return (SendChatMessageResult.success, delivered);
      }

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: sendFn,
      );

      await tester.enterText(find.byType(TextField), 'Text only');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump(const Duration(milliseconds: 50));

      // No media should be passed for text-only sends
      expect(passedMedia, isNull);
      expect(passedMediaRepo, isNull);
      expect(find.text('Text only'), findsOneWidget);

      // Let scroll animation and post-frame callbacks complete
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('does not send when text is empty and no attachments', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      var sendCalled = false;

      Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
        required P2PService p2pService,
        required MessageRepository messageRepo,
        required String targetPeerId,
        required String text,
        required String senderPeerId,
        required String senderUsername,
        String? messageId,
        required bool preassignedMessageIdIsFresh,
        String? timestamp,
        Bridge? bridge,
        String? recipientMlKemPublicKey,
        String? quotedMessageId,
        List<MediaAttachment>? mediaAttachments,
        PrivateMediaPolicy? privateMediaPolicy,
        MediaAttachmentRepository? mediaAttachmentRepo,
        TransportMetrics? transportMetrics,
        DirectEventFanoutAuthoring? directEventFanout,
      }) async {
        sendCalled = true;
        return (SendChatMessageResult.success, null);
      }

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: sendFn,
      );

      // Tap send without entering text — the tap won't go through because
      // GestureDetector's onTap is null when no text and no attachments
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(sendCalled, false);
      expect(messageRepo.store, isEmpty);
    });

    testWidgets('swipe-to-reply sends quotedMessageId and clears preview', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final incoming = ConversationMessage(
        id: 'incoming-1',
        contactPeerId: makeContact().peerId,
        senderPeerId: makeContact().peerId,
        text: 'Original incoming',
        timestamp: '2026-02-09T15:30:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-02-09T15:30:01.000Z',
      );
      await messageRepo.saveMessage(incoming);

      String? capturedQuotedMessageId;

      Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
        required P2PService p2pService,
        required MessageRepository messageRepo,
        required String targetPeerId,
        required String text,
        required String senderPeerId,
        required String senderUsername,
        String? messageId,
        required bool preassignedMessageIdIsFresh,
        String? timestamp,
        Bridge? bridge,
        String? recipientMlKemPublicKey,
        String? quotedMessageId,
        List<MediaAttachment>? mediaAttachments,
        PrivateMediaPolicy? privateMediaPolicy,
        MediaAttachmentRepository? mediaAttachmentRepo,
        TransportMetrics? transportMetrics,
        DirectEventFanoutAuthoring? directEventFanout,
      }) async {
        capturedQuotedMessageId = quotedMessageId;
        final delivered = ConversationMessage(
          id: messageId!,
          contactPeerId: targetPeerId,
          senderPeerId: senderPeerId,
          text: text,
          timestamp: timestamp!,
          status: 'delivered',
          isIncoming: false,
          createdAt: timestamp,
          quotedMessageId: quotedMessageId,
        );
        await messageRepo.saveMessage(delivered);
        return (SendChatMessageResult.success, delivered);
      }

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: sendFn,
      );

      expect(find.byType(SwipeToQuoteBubble), findsOneWidget);

      final screen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      screen.onQuoteReply!.call('incoming-1');
      await tester.pump();

      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Original incoming'), findsWidgets);

      await tester.enterText(find.byType(TextField), 'Quoted response');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump(const Duration(milliseconds: 50));

      expect(capturedQuotedMessageId, 'incoming-1');
      expect(find.text('Replying to'), findsNothing);

      final saved = messageRepo.store.values
          .where((message) => message.text == 'Quoted response')
          .first;
      expect(saved.quotedMessageId, 'incoming-1');
    });

    testWidgets(
      'clearing quote removes the preview and the next send has no quotedMessageId',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final incoming = ConversationMessage(
          id: 'incoming-clear-quote',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeContact().peerId,
          text: 'Quote then clear me',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:30:01.000Z',
        );
        await messageRepo.saveMessage(incoming);

        String? capturedQuotedMessageId;

        Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          capturedQuotedMessageId = quotedMessageId;
          final delivered = ConversationMessage(
            id: messageId!,
            contactPeerId: targetPeerId,
            senderPeerId: senderPeerId,
            text: text,
            timestamp: timestamp!,
            status: 'delivered',
            isIncoming: false,
            createdAt: timestamp,
            quotedMessageId: quotedMessageId,
          );
          await messageRepo.saveMessage(delivered);
          return (SendChatMessageResult.success, delivered);
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
        );

        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        screen.onQuoteReply!.call('incoming-clear-quote');
        await tester.pump();

        expect(find.text('Replying to'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pump();

        expect(find.text('Replying to'), findsNothing);

        await tester.enterText(find.byType(TextField), 'No quote left');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump(const Duration(milliseconds: 50));

        expect(capturedQuotedMessageId, isNull);

        final saved = messageRepo.store.values
            .where((message) => message.text == 'No quote left')
            .first;
        expect(saved.quotedMessageId, isNull);
      },
    );

    testWidgets(
      'long-press reply on an outgoing message requests focus and sends quotedMessageId',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final outgoing = ConversationMessage(
          id: 'outgoing-1',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Quote this sent message',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-02-09T15:30:01.000Z',
        );
        await messageRepo.saveMessage(outgoing);

        String? capturedQuotedMessageId;

        Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          capturedQuotedMessageId = quotedMessageId;
          final delivered = ConversationMessage(
            id: messageId!,
            contactPeerId: targetPeerId,
            senderPeerId: senderPeerId,
            text: text,
            timestamp: timestamp!,
            status: 'delivered',
            isIncoming: false,
            createdAt: timestamp,
            quotedMessageId: quotedMessageId,
          );
          await messageRepo.saveMessage(delivered);
          return (SendChatMessageResult.success, delivered);
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
        );

        await tester.longPress(find.text('Quote this sent message'));
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          find.byKey(MessageContextOverlay.selectedMessageKey),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(MessageContextOverlay.selectedMessageKey),
            matching: find.text('Quote this sent message'),
          ),
          findsOneWidget,
        );

        await tester.tap(find.byKey(MessageContextOverlay.replyActionKey));
        await tester.pump();

        expect(find.text('Replying to'), findsOneWidget);
        expect(find.text('Quote this sent message'), findsWidgets);
        expect(
          tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
          isTrue,
        );

        await tester.enterText(
          find.byType(TextField),
          'Quoted after long press',
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump(const Duration(milliseconds: 50));

        expect(capturedQuotedMessageId, 'outgoing-1');
        expect(find.text('Replying to'), findsNothing);

        final saved = messageRepo.store.values
            .where((message) => message.text == 'Quoted after long press')
            .first;
        expect(saved.quotedMessageId, 'outgoing-1');
      },
    );

    testWidgets(
      'edit action prefills the composer and cancel exits edit mode',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final outgoing = ConversationMessage(
          id: 'editable-1',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Fix this typo',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-02-09T15:30:01.000Z',
        );
        await messageRepo.saveMessage(outgoing);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        await tester.longPress(find.text('Fix this typo'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.editActionKey));
        await tester.pump();

        expect(
          find.byKey(ConversationScreen.editModeBannerKey),
          findsOneWidget,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Fix this typo',
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
          isTrue,
        );

        await tester.tap(find.byKey(ConversationScreen.cancelEditKey));
        await tester.pump();

        expect(find.byKey(ConversationScreen.editModeBannerKey), findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          '',
        );
      },
    );

    testWidgets(
      'edit action clears active quote mode before entering edit mode',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'incoming-quoted-parent',
            contactPeerId: makeContact().peerId,
            senderPeerId: makeContact().peerId,
            text: 'Quoted parent',
            timestamp: '2026-02-09T15:29:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-02-09T15:29:01.000Z',
          ),
        );
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'editable-after-quote',
            contactPeerId: makeContact().peerId,
            senderPeerId: makeIdentity().peerId,
            text: 'Edit me after replying',
            timestamp: '2026-02-09T15:30:00.000Z',
            status: 'delivered',
            isIncoming: false,
            createdAt: '2026-02-09T15:30:01.000Z',
          ),
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        screen.onQuoteReply!.call('incoming-quoted-parent');
        await tester.pump();

        expect(find.text('Replying to'), findsOneWidget);

        await tester.longPress(find.text('Edit me after replying'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.editActionKey));
        await tester.pump();

        expect(find.text('Replying to'), findsNothing);
        expect(
          find.byKey(ConversationScreen.editModeBannerKey),
          findsOneWidget,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Edit me after replying',
        );
      },
    );

    testWidgets(
      'pending attachments suppress edit while reply, copy, and delete remain available',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final outgoing = ConversationMessage(
          id: 'busy-overlay-1',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Overlay stays useful while busy',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-02-09T15:30:01.000Z',
        );
        await messageRepo.saveMessage(outgoing);

        final tempDir = Directory.systemTemp.createTempSync(
          'conversation_overlay_busy_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final pendingFile = File('${tempDir.path}/pending.png');
        pendingFile.writeAsBytesSync(_tinyPngBytes);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          initialPendingMedia: [
            PendingComposerMedia(
              file: pendingFile,
              budgetBytes: pendingFile.lengthSync(),
            ),
          ],
        );

        await tester.longPress(find.text('Overlay stays useful while busy'));
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          find.byKey(MessageContextOverlay.replyActionKey),
          findsOneWidget,
        );
        expect(find.byKey(MessageContextOverlay.editActionKey), findsNothing);
        expect(find.byKey(MessageContextOverlay.copyActionKey), findsOneWidget);
        expect(
          find.byKey(MessageContextOverlay.deleteActionKey),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'copy action leaves repo, bridge, and p2p collaborators untouched',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final bridge = FakeBridge();
        final p2pService = FakeP2PService();
        final outgoing = ConversationMessage(
          id: 'copy-isolation-row',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Copy without side effects',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-02-09T15:30:01.000Z',
        );
        await messageRepo.saveMessage(outgoing);

        String? copiedText;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            copiedText =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          bridge: bridge,
          p2pService: p2pService,
        );

        final baselineSaveCalls = messageRepo.saveMessageCallCount;
        final baselineDeleteCalls = messageRepo.deleteMessageCallCount;
        final baselineBridgeCalls = bridge.sendCallCount;
        final baselineSendCalls = p2pService.sendMessageCallCount;
        final baselineInboxCalls = p2pService.storeInInboxCallCount;

        await tester.longPress(find.text('Copy without side effects'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.copyActionKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(copiedText, 'Copy without side effects');
        expect(messageRepo.saveMessageCallCount, baselineSaveCalls);
        expect(messageRepo.deleteMessageCallCount, baselineDeleteCalls);
        expect(bridge.sendCallCount, baselineBridgeCalls);
        expect(p2pService.sendMessageCallCount, baselineSendCalls);
        expect(p2pService.storeInInboxCallCount, baselineInboxCalls);
      },
    );

    testWidgets(
      'copy remains local-only when delete wins during the async clipboard path',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final bridge = FakeBridge();
        final p2pService = FakeP2PService();
        final outgoing = ConversationMessage(
          id: 'copy-delete-race-row',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Copy while delete wins',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-02-09T15:30:01.000Z',
        );
        await messageRepo.saveMessage(outgoing);

        final clipboardCompleter = Completer<void>();
        String? copiedText;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            copiedText =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
            await clipboardCompleter.future;
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          bridge: bridge,
          p2pService: p2pService,
        );

        final baselineSaveCalls = messageRepo.saveMessageCallCount;
        final baselineDeleteCalls = messageRepo.deleteMessageCallCount;
        final baselineBridgeCalls = bridge.sendCallCount;
        final baselineSendCalls = p2pService.sendMessageCallCount;
        final baselineInboxCalls = p2pService.storeInInboxCallCount;

        await tester.longPress(find.text('Copy while delete wins'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.copyActionKey));
        await tester.pump();

        await messageRepo.saveMessage(
          outgoing.copyWith(
            text: '',
            deletedAt: '2026-03-31T11:15:00.000Z',
            deletedByPeerId: outgoing.senderPeerId,
            media: const [],
          ),
        );
        await pumpUntil(
          tester,
          () => find.text('This message was deleted').evaluate().isNotEmpty,
        );

        clipboardCompleter.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(copiedText, 'Copy while delete wins');
        expect(find.text('Copy while delete wins'), findsNothing);
        expect(find.text('This message was deleted'), findsOneWidget);
        expect(messageRepo.saveMessageCallCount, baselineSaveCalls + 1);
        expect(messageRepo.deleteMessageCallCount, baselineDeleteCalls);
        expect(bridge.sendCallCount, baselineBridgeCalls);
        expect(p2pService.sendMessageCallCount, baselineSendCalls);
        expect(p2pService.storeInInboxCallCount, baselineInboxCalls);
      },
    );

    testWidgets('identical-text edit submit is a no-op', (tester) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final outgoing = ConversationMessage(
        id: 'editable-noop',
        contactPeerId: makeContact().peerId,
        senderPeerId: makeIdentity().peerId,
        text: 'Same text',
        timestamp: '2026-02-09T15:30:00.000Z',
        status: 'delivered',
        isIncoming: false,
        createdAt: '2026-02-09T15:30:01.000Z',
      );
      await messageRepo.saveMessage(outgoing);

      var editCalls = 0;

      Future<(SendChatMessageResult, ConversationMessage?)> editFn({
        required P2PService p2pService,
        required MessageRepository messageRepo,
        required ConversationMessage originalMessage,
        required String updatedText,
        required String senderUsername,
        Bridge? bridge,
        String? recipientMlKemPublicKey,
        MediaAttachmentRepository? mediaAttachmentRepo,
        bool emitTimingEvent = true,
        DirectEventFanoutAuthoring? directEventFanout,
      }) async {
        editCalls++;
        return (SendChatMessageResult.success, originalMessage);
      }

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        editFn: editFn,
      );

      await tester.longPress(find.text('Same text'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(MessageContextOverlay.editActionKey));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(editCalls, 0);
      expect(messageRepo.store['editable-noop']?.editedAt, isNull);
      expect(find.byKey(ConversationScreen.editModeBannerKey), findsNothing);
    });

    testWidgets('starting a reply clears active edit mode', (tester) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'editable-before-reply',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Edit me first',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-02-09T15:30:01.000Z',
        ),
      );
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'incoming-reply-target',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeContact().peerId,
          text: 'Then reply to me',
          timestamp: '2026-02-09T15:31:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:31:01.000Z',
        ),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
      );

      await tester.longPress(find.text('Edit me first'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(MessageContextOverlay.editActionKey));
      await tester.pump();

      expect(find.byKey(ConversationScreen.editModeBannerKey), findsOneWidget);

      final screen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      screen.onQuoteReply!.call('incoming-reply-target');
      await tester.pump();

      expect(find.byKey(ConversationScreen.editModeBannerKey), findsNothing);
      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Then reply to me'), findsWidgets);
    });

    testWidgets(
      'changed edit submit updates the same row through the shared edit path',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final outgoing = ConversationMessage(
          id: 'editable-submit',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Before edit',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-02-09T15:30:01.000Z',
          quotedMessageId: 'quoted-parent',
        );
        await messageRepo.saveMessage(outgoing);

        String? capturedOriginalId;
        String? capturedUpdatedText;

        Future<(SendChatMessageResult, ConversationMessage?)> editFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required ConversationMessage originalMessage,
          required String updatedText,
          required String senderUsername,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          MediaAttachmentRepository? mediaAttachmentRepo,
          bool emitTimingEvent = true,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          capturedOriginalId = originalMessage.id;
          capturedUpdatedText = updatedText;
          final edited = originalMessage.copyWith(
            text: updatedText,
            editedAt: '2026-02-09T16:00:00.000Z',
          );
          await messageRepo.saveMessage(edited);
          return (SendChatMessageResult.success, edited);
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          editFn: editFn,
        );

        await tester.longPress(find.text('Before edit'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.editActionKey));
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'After edit');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump();

        expect(capturedOriginalId, 'editable-submit');
        expect(capturedUpdatedText, 'After edit');
        expect(messageRepo.store['editable-submit']?.text, 'After edit');
        expect(
          messageRepo.store['editable-submit']?.quotedMessageId,
          'quoted-parent',
        );
        expect(
          messageRepo.store['editable-submit']?.editedAt,
          '2026-02-09T16:00:00.000Z',
        );
        expect(find.byKey(ConversationScreen.editModeBannerKey), findsNothing);
      },
    );

    testWidgets(
      'delivered outgoing rows offer delete-for-me and delete-for-everyone',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'delete-options-outgoing',
            contactPeerId: makeContact().peerId,
            senderPeerId: makeIdentity().peerId,
            text: 'Delete options',
            timestamp: '2026-02-09T15:30:00.000Z',
            status: 'delivered',
            isIncoming: false,
            createdAt: '2026-02-09T15:30:01.000Z',
          ),
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        await tester.longPress(find.text('Delete options'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
        await pumpUntil(
          tester,
          () => find
              .byKey(ConversationWired.deleteSheetKey)
              .evaluate()
              .isNotEmpty,
        );

        expect(find.byKey(ConversationWired.deleteSheetKey), findsOneWidget);
        expect(find.byKey(ConversationWired.deleteForMeKey), findsOneWidget);
        expect(
          find.byKey(ConversationWired.deleteForEveryoneKey),
          findsOneWidget,
        );
        expect(find.byKey(ConversationWired.deleteCancelKey), findsOneWidget);
      },
    );

    testWidgets('incoming rows only offer delete-for-me and cancel', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'incoming-delete-options',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeContact().peerId,
          text: 'Incoming delete options',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:30:01.000Z',
        ),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
      );

      await tester.longPress(find.text('Incoming delete options'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
      await pumpUntil(
        tester,
        () =>
            find.byKey(ConversationWired.deleteSheetKey).evaluate().isNotEmpty,
      );

      expect(find.byKey(ConversationWired.deleteSheetKey), findsOneWidget);
      expect(find.byKey(ConversationWired.deleteForMeKey), findsOneWidget);
      expect(find.byKey(ConversationWired.deleteForEveryoneKey), findsNothing);
      expect(find.byKey(ConversationWired.deleteCancelKey), findsOneWidget);
    });

    testWidgets('identity-missing rows only offer delete-for-me and cancel', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(null);
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'identity-missing-delete-options',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Identity missing delete options',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-02-09T15:30:01.000Z',
        ),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
      );

      await tester.longPress(find.text('Identity missing delete options'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
      await pumpUntil(
        tester,
        () =>
            find.byKey(ConversationWired.deleteSheetKey).evaluate().isNotEmpty,
      );

      expect(find.byKey(ConversationWired.deleteForMeKey), findsOneWidget);
      expect(find.byKey(ConversationWired.deleteForEveryoneKey), findsNothing);
      expect(find.byKey(ConversationWired.deleteCancelKey), findsOneWidget);
    });

    testWidgets('sender-mismatch rows only offer delete-for-me and cancel', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'sender-mismatch-delete-options',
          contactPeerId: makeContact().peerId,
          senderPeerId: 'someone-else',
          text: 'Sender mismatch delete options',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-02-09T15:30:01.000Z',
        ),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
      );

      await tester.longPress(find.text('Sender mismatch delete options'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
      await pumpUntil(
        tester,
        () =>
            find.byKey(ConversationWired.deleteSheetKey).evaluate().isNotEmpty,
      );

      expect(find.byKey(ConversationWired.deleteForMeKey), findsOneWidget);
      expect(find.byKey(ConversationWired.deleteForEveryoneKey), findsNothing);
      expect(find.byKey(ConversationWired.deleteCancelKey), findsOneWidget);
    });

    testWidgets('failed outgoing rows only offer delete-for-me and cancel', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'failed-delete-options',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Failed delete options',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'failed',
          isIncoming: false,
          createdAt: '2026-02-09T15:30:01.000Z',
        ),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
      );

      await tester.longPress(find.text('Failed delete options'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
      await pumpUntil(
        tester,
        () =>
            find.byKey(ConversationWired.deleteSheetKey).evaluate().isNotEmpty,
      );

      expect(find.byKey(ConversationWired.deleteForMeKey), findsOneWidget);
      expect(find.byKey(ConversationWired.deleteForEveryoneKey), findsNothing);
    });

    testWidgets('delete-for-me removes the row from Orbit locally', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'delete-for-me-row',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeContact().peerId,
          text: 'Delete for me only',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:30:01.000Z',
        ),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
      );

      await tester.longPress(find.text('Delete for me only'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
      await pumpUntil(
        tester,
        () =>
            find.byKey(ConversationWired.deleteSheetKey).evaluate().isNotEmpty,
      );
      tester
          .widget<InkWell>(
            find.descendant(
              of: find.byKey(ConversationWired.deleteForMeKey),
              matching: find.byType(InkWell),
            ),
          )
          .onTap!();
      await pumpUntil(
        tester,
        () => find.text('Delete for me only').evaluate().isEmpty,
      );

      expect(find.text('Delete for me only'), findsNothing);
      expect(messageRepo.store.containsKey('delete-for-me-row'), isFalse);
      expect(find.text('Connected!'), findsWidgets);
    });

    testWidgets('canceling the delete sheet leaves the message unchanged', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'delete-cancel-row',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Do not delete me',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-02-09T15:30:01.000Z',
        ),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
      );

      await tester.longPress(find.text('Do not delete me'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
      await pumpUntil(
        tester,
        () =>
            find.byKey(ConversationWired.deleteSheetKey).evaluate().isNotEmpty,
      );

      tester
          .widget<InkWell>(
            find.descendant(
              of: find.byKey(ConversationWired.deleteCancelKey),
              matching: find.byType(InkWell),
            ),
          )
          .onTap!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(ConversationWired.deleteSheetKey), findsNothing);
      expect(find.text('Do not delete me'), findsOneWidget);
      expect(messageRepo.store.containsKey('delete-cancel-row'), isTrue);
      expect(messageRepo.store['delete-cancel-row']?.isDeleted, isFalse);
    });

    testWidgets(
      'deleting the message currently being edited exits edit mode immediately',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'delete-editing-row',
            contactPeerId: makeContact().peerId,
            senderPeerId: makeIdentity().peerId,
            text: 'Delete me while editing',
            timestamp: '2026-02-09T15:30:00.000Z',
            status: 'delivered',
            isIncoming: false,
            createdAt: '2026-02-09T15:30:01.000Z',
          ),
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        await tester.longPress(
          find.byKey(const ValueKey('msg-delete-editing-row')),
        );
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.editActionKey));
        await tester.pump();

        expect(
          find.byKey(ConversationScreen.editModeBannerKey),
          findsOneWidget,
        );

        await tester.longPress(
          find.byKey(const ValueKey('msg-delete-editing-row')),
        );
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
        await pumpUntil(
          tester,
          () => find
              .byKey(ConversationWired.deleteSheetKey)
              .evaluate()
              .isNotEmpty,
        );
        tester
            .widget<InkWell>(
              find.descendant(
                of: find.byKey(ConversationWired.deleteForMeKey),
                matching: find.byType(InkWell),
              ),
            )
            .onTap!();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byKey(ConversationScreen.editModeBannerKey), findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          '',
        );
        expect(messageRepo.store.containsKey('delete-editing-row'), isFalse);
      },
    );

    testWidgets(
      'deleting the message currently being quoted exits quote mode immediately',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'delete-quoted-row',
            contactPeerId: makeContact().peerId,
            senderPeerId: makeContact().peerId,
            text: 'Delete me while quoted',
            timestamp: '2026-02-09T15:30:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-02-09T15:30:01.000Z',
          ),
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        screen.onQuoteReply!.call('delete-quoted-row');
        await tester.pump();

        expect(find.text('Replying to'), findsOneWidget);

        await tester.longPress(
          find.byKey(const ValueKey('msg-delete-quoted-row')),
        );
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
        await pumpUntil(
          tester,
          () => find
              .byKey(ConversationWired.deleteSheetKey)
              .evaluate()
              .isNotEmpty,
        );
        tester
            .widget<InkWell>(
              find.descendant(
                of: find.byKey(ConversationWired.deleteForMeKey),
                matching: find.byType(InkWell),
              ),
            )
            .onTap!();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Replying to'), findsNothing);
      },
    );

    testWidgets('hidden outgoing tombstones are removed from the Orbit list', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final original = ConversationMessage(
        id: 'delete-for-everyone-row',
        contactPeerId: makeContact().peerId,
        senderPeerId: makeIdentity().peerId,
        text: 'Delete everywhere',
        timestamp: '2026-02-09T15:30:00.000Z',
        status: 'delivered',
        isIncoming: false,
        createdAt: '2026-02-09T15:30:01.000Z',
      );
      await messageRepo.saveMessage(original);

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
      );

      await messageRepo.saveMessage(
        original.copyWith(
          text: '',
          deletedAt: '2026-03-31T11:00:00.000Z',
          deletedByPeerId: original.senderPeerId,
          hiddenAt: '2026-03-31T11:00:00.000Z',
          media: const [],
        ),
      );
      await pumpUntil(
        tester,
        () => find.text('Delete everywhere').evaluate().isEmpty,
      );

      expect(find.text('Delete everywhere'), findsNothing);
      expect(messageRepo.store['delete-for-everyone-row']?.isHidden, isTrue);
    });

    testWidgets(
      'failed outgoing delete tombstones stay visible in the Orbit list',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final original = ConversationMessage(
          id: 'delete-for-everyone-failed-row',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Delete but still pending',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-02-09T15:30:01.000Z',
        );
        await messageRepo.saveMessage(original);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        await messageRepo.saveMessage(
          original.copyWith(
            text: '',
            status: 'failed',
            deletedAt: '2026-03-31T11:02:00.000Z',
            deletedByPeerId: original.senderPeerId,
            media: const [],
          ),
        );
        await pumpUntil(
          tester,
          () => find.text('This message was deleted').evaluate().isNotEmpty,
        );

        expect(find.text('Delete but still pending'), findsNothing);
        expect(find.text('This message was deleted'), findsOneWidget);
        expect(
          messageRepo.store['delete-for-everyone-failed-row']?.isHidden,
          isFalse,
        );
      },
    );

    testWidgets(
      'incoming reactions refresh the open Orbit conversation and stay correct after reopen',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final reactionRepo = FakeReactionRepository();
        final fakeReactionListener = _FakeReactionListener(
          messageRepo: messageRepo,
          reactionRepo: reactionRepo,
          contactRepo: FakeContactRepository(),
          bridge: FakeBridge(),
        );
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final original = ConversationMessage(
          id: 'incoming-reaction-row',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeContact().peerId,
          text: 'React to me',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:30:01.000Z',
        );
        await messageRepo.saveMessage(original);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          reactionRepo: reactionRepo,
          reactionListener: fakeReactionListener,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        expect(find.text('🔥'), findsNothing);

        final reaction = MessageReaction(
          id: 'reaction-1',
          messageId: original.id,
          emoji: '🔥',
          senderPeerId: original.senderPeerId,
          timestamp: '2026-03-31T10:05:00.000Z',
          createdAt: '2026-03-31T10:05:00.000Z',
        );
        await reactionRepo.saveReaction(reaction);
        fakeReactionListener.emitReaction(reaction);

        await pumpUntil(tester, () => find.text('🔥').evaluate().isNotEmpty);

        expect(find.text('🔥'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          reactionRepo: reactionRepo,
          reactionListener: fakeReactionListener,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        expect(find.text('🔥'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'incoming edited messages refresh the open Orbit conversation and stay correct after reopen',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = _FakeIncomingConversationListener(
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final original = ConversationMessage(
          id: 'incoming-edit-refresh',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeContact().peerId,
          text: 'Original incoming edit text',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:30:01.000Z',
        );
        await messageRepo.saveMessage(original);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        expect(find.text('Original incoming edit text'), findsOneWidget);

        final edited = original.copyWith(
          text: 'Edited incoming text',
          editedAt: '2026-03-31T10:06:00.000Z',
        );
        await messageRepo.saveMessage(edited);
        chatListener.emitIncomingMessage(edited);

        await pumpUntil(
          tester,
          () => find.text('Edited incoming text').evaluate().isNotEmpty,
        );

        expect(find.text('Original incoming edit text'), findsNothing);
        expect(find.text('Edited incoming text'), findsOneWidget);
        expect(find.text('(edited)'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        expect(find.text('Edited incoming text'), findsOneWidget);
        expect(find.text('(edited)'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'incoming deleted tombstones refresh into the Orbit placeholder and stay correct after reopen',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final original = ConversationMessage(
          id: 'incoming-tombstone',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeContact().peerId,
          text: 'Original incoming text',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:30:01.000Z',
        );
        await messageRepo.saveMessage(original);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        await messageRepo.saveMessage(
          original.copyWith(
            text: '',
            deletedAt: '2026-03-31T11:05:00.000Z',
            deletedByPeerId: makeContact().peerId,
            media: const [],
          ),
        );
        await pumpUntil(
          tester,
          () => find.text('This message was deleted').evaluate().isNotEmpty,
        );

        expect(find.text('Original incoming text'), findsNothing);
        expect(find.text('This message was deleted'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        expect(find.text('Original incoming text'), findsNothing);
        expect(find.text('This message was deleted'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets('swipe-to-reply voice send preserves quotedMessageId', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final recorder = FakeAudioRecorderService()
        ..fakeDurationMs = 1200
        ..fakeOutputPath = '/tmp/quoted_voice.m4a';
      final incoming = ConversationMessage(
        id: 'incoming-voice-1',
        contactPeerId: makeContact().peerId,
        senderPeerId: makeContact().peerId,
        text: 'Quote this voice parent',
        timestamp: '2026-02-09T15:30:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-02-09T15:30:01.000Z',
      );
      await messageRepo.saveMessage(incoming);

      String? capturedQuotedMessageId;

      Future<(SendVoiceMessageResult, ConversationMessage?)> sendVoiceFn({
        required P2PService p2pService,
        required MessageRepository messageRepo,
        required String targetPeerId,
        required String senderPeerId,
        required String senderUsername,
        required AudioRecording recording,
        required Bridge bridge,
        String? recipientMlKemPublicKey,
        MediaAttachmentRepository? mediaAttachmentRepo,
        MediaFileManager? mediaFileManager,
        String? text,
        String? quotedMessageId,
        List<double>? waveform,
        String? messageId,
        String? timestamp,
        String? blobId,
        preparedArtifact,
        mediaAdmission,
      }) async {
        capturedQuotedMessageId = quotedMessageId;
        final delivered = ConversationMessage(
          id: messageId!,
          contactPeerId: targetPeerId,
          senderPeerId: senderPeerId,
          text: text ?? '',
          timestamp: timestamp!,
          status: 'delivered',
          isIncoming: false,
          createdAt: timestamp,
          quotedMessageId: quotedMessageId,
        );
        await messageRepo.saveMessage(delivered);
        return (SendVoiceMessageResult.success, delivered);
      }

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        bridge: FakeBridge(),
        p2pService: FakeP2PService(localPeer: true, localMediaResult: true),
        audioRecorderService: recorder,
        sendVoiceMessageFn: sendVoiceFn,
      );

      final screen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      screen.onQuoteReply!.call('incoming-voice-1');
      await tester.pump();

      expect(find.text('Replying to'), findsOneWidget);

      final startRecording = screen.onRecordStart! as Future<void> Function();
      await startRecording();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      final recordingScreen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      final stopRecording =
          recordingScreen.onRecordStop! as Future<void> Function();
      final stopFuture = stopRecording();
      await tester.pump(const Duration(milliseconds: 300));
      await stopFuture;

      expect(capturedQuotedMessageId, 'incoming-voice-1');
      expect(find.text('Replying to'), findsNothing);

      final saved = messageRepo.store.values
          .where((message) => message.id != 'incoming-voice-1')
          .firstWhere((message) => !message.isIncoming);
      expect(saved.quotedMessageId, 'incoming-voice-1');
    });

    // 117 Session 3: the 5-minute auto-stop must NOT silently discard the
    // captured recording. It holds the clip for review (send/discard) with a
    // SnackBar — no silent loss, no surprise auto-send.
    group('voice 5-minute auto-stop review', () {
      late File voiceFile;
      late FakeAudioRecorderService recorder;
      late FakeMessageRepository messageRepo;
      late int sendVoiceCalls;

      Future<(SendVoiceMessageResult, ConversationMessage?)> reviewSendVoiceFn({
        required P2PService p2pService,
        required MessageRepository messageRepo,
        required String targetPeerId,
        required String senderPeerId,
        required String senderUsername,
        required AudioRecording recording,
        required Bridge bridge,
        String? recipientMlKemPublicKey,
        MediaAttachmentRepository? mediaAttachmentRepo,
        MediaFileManager? mediaFileManager,
        String? text,
        String? quotedMessageId,
        List<double>? waveform,
        String? messageId,
        String? timestamp,
        String? blobId,
        preparedArtifact,
        mediaAdmission,
      }) async {
        sendVoiceCalls += 1;
        final delivered = ConversationMessage(
          id: messageId!,
          contactPeerId: targetPeerId,
          senderPeerId: senderPeerId,
          text: text ?? '',
          timestamp: timestamp!,
          status: 'delivered',
          isIncoming: false,
          createdAt: timestamp,
        );
        await messageRepo.saveMessage(delivered);
        return (SendVoiceMessageResult.success, delivered);
      }

      Future<ConversationScreen> startThenAutoStop(WidgetTester tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          bridge: FakeBridge(),
          p2pService: FakeP2PService(localPeer: true, localMediaResult: true),
          audioRecorderService: recorder,
          sendVoiceMessageFn: reviewSendVoiceFn,
        );

        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        await (screen.onRecordStart! as Future<void> Function())();
        await tester.pump(const Duration(milliseconds: 100));
        await recorder.triggerAutoStop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        return tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
      }

      setUp(() {
        sendVoiceCalls = 0;
        messageRepo = FakeMessageRepository();
        voiceFile = File(
          '${Directory.systemTemp.path}/autostop_review_'
          '${DateTime.now().microsecondsSinceEpoch}.m4a',
        )..writeAsBytesSync(List<int>.filled(2048, 9));
        recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 300000
          ..fakeSizeBytes = 2048
          ..fakeOutputPath = voiceFile.path;
      });

      tearDown(() {
        if (voiceFile.existsSync()) voiceFile.deleteSync();
      });

      testWidgets('holds the recording for review and does not auto-send', (
        tester,
      ) async {
        await startThenAutoStop(tester);

        expect(
          find.text('Recording reached the 5-minute limit.'),
          findsOneWidget,
        );
        expect(sendVoiceCalls, 0);
        expect(
          messageRepo.store.values.where((m) => !m.isIncoming),
          isEmpty,
          reason: 'auto-stop must not silently auto-send the recording',
        );
        expect(
          voiceFile.existsSync(),
          isTrue,
          reason: 'the captured recording must be preserved for review',
        );
        expect(find.byKey(const ValueKey('voice-review-send')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('voice-review-discard')),
          findsOneWidget,
        );
      });

      testWidgets('review send delivers the held recording', (tester) async {
        final reviewScreen = await startThenAutoStop(tester);

        await (reviewScreen.onReviewSend! as Future<void> Function())();
        await tester.pump(const Duration(milliseconds: 300));

        expect(sendVoiceCalls, 1);
        expect(
          messageRepo.store.values.where((m) => !m.isIncoming),
          isNotEmpty,
        );
        expect(find.byKey(const ValueKey('voice-review-send')), findsNothing);

        // Drain the sent message's letter-card entrance timer before teardown.
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('review discard drops the recording without sending', (
        tester,
      ) async {
        final reviewScreen = await startThenAutoStop(tester);

        await (reviewScreen.onReviewDiscard! as Future<void> Function())();
        await tester.pump(const Duration(milliseconds: 100));

        expect(sendVoiceCalls, 0);
        expect(messageRepo.store.values.where((m) => !m.isIncoming), isEmpty);
        expect(
          voiceFile.existsSync(),
          isFalse,
          reason: 'discard must delete the held recording file',
        );
        expect(find.byKey(const ValueKey('voice-review-send')), findsNothing);
      });
    });

    testWidgets(
      'TC-366-01a voice widget carries one admitted snapshot without a second roster read',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync(
          'tc362_widget_voice_admission_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final voiceFile = File('${tempDir.path}/voice.m4a')
          ..writeAsBytesSync(List<int>.filled(2048, 7));
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 300000
          ..fakeSizeBytes = 2048
          ..fakeOutputPath = voiceFile.path;
        final messages = FakeMessageRepository();
        final contact = makeContact();
        final media = _FanoutComposerMediaRepository(
          snapshot: DirectContactFanoutSnapshot(
            contactAccountPeerId: contact.peerId,
            contactAccountSigningPublicKey: contact.publicKey,
            rosterInitialized: true,
            targets: const <DirectContactFanoutTargetFact>[
              DirectContactFanoutTargetFact(
                peerId: 'peer-voice-linked',
                mlKemPublicKey: 'mlkem-voice-linked',
                isLegacyAccountTarget: false,
                fingerprint:
                    'abababababababababababababababababababababababababababababababab',
                deviceId: 'voice-device',
                transportPublicKey: 'voice-transport-key',
              ),
            ],
          ),
        );
        final manager = TrackingDurableConversationMediaFileManager(tempDir);
        var sendVoiceCalls = 0;
        DirectMediaFanoutAdmission? carriedAdmission;
        Future<(SendVoiceMessageResult, ConversationMessage?)> neverSendVoice({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String senderPeerId,
          required String senderUsername,
          required AudioRecording recording,
          required Bridge bridge,
          String? recipientMlKemPublicKey,
          MediaAttachmentRepository? mediaAttachmentRepo,
          MediaFileManager? mediaFileManager,
          String? text,
          String? quotedMessageId,
          List<double>? waveform,
          String? messageId,
          String? timestamp,
          String? blobId,
          preparedArtifact,
          mediaAdmission,
        }) async {
          sendVoiceCalls++;
          carriedAdmission = mediaAdmission as DirectMediaFanoutAdmission?;
          return (SendVoiceMessageResult.sendFailed, null);
        }

        await pumpScreen(
          tester,
          identityRepo: FakeIdentityRepository(makeIdentity()),
          messageRepo: messages,
          chatListener: ChatMessageListener(
            chatMessageStream: const Stream.empty(),
            messageRepo: messages,
            contactRepo: FakeContactRepository(),
          ),
          sendFn: _instantSuccessSendFn,
          bridge: FakeBridge(),
          p2pService: FakeP2PService(),
          mediaAttachmentRepo: media,
          mediaFileManager: manager,
          audioRecorderService: recorder,
          sendVoiceMessageFn: neverSendVoice,
          directLinkedMediaFanoutSelector:
              const DirectLinkedMediaFanoutSelector.enabled(),
          directMediaBlobCustodyClientEnabled: true,
          directLinkedEventFanoutEnabled: true,
        );
        var screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        await (screen.onRecordStart! as Future<void> Function())();
        await tester.pump(const Duration(milliseconds: 100));
        await recorder.triggerAutoStop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        await tester.runAsync(
          () => (screen.onReviewSend! as Future<void> Function())(),
        );
        await tester.pump(const Duration(milliseconds: 200));

        expect(sendVoiceCalls, 1);
        expect(media.snapshotReads, 1);
        expect(carriedAdmission?.requiresLinkedFanout, isTrue);
        expect(carriedAdmission?.snapshot, same(media.snapshot));
        expect(manager.copyCalls, 1);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      },
    );

    test(
      'TC-366-01a direct-library batch caller reaches the strict fanout entry',
      () {
        final source = File(
          'lib/features/conversation/presentation/screens/conversation_wired.dart',
        ).readAsStringSync();
        final launch = source.indexOf('_launchDirectMediaBatchForward(');
        expect(launch, greaterThanOrEqualTo(0));
        final strict = source.indexOf(
          'ordinary.deliverDirectMediaBatchForwardStrict(',
          launch < 0 ? 0 : launch,
        );
        expect(strict, greaterThan(launch));
        expect(
          source.substring(launch, strict),
          isNot(contains('ordinary.deliver(')),
          reason:
              'the library batch must not bypass the admission-first strict '
              'entry through the generic share route',
        );
      },
    );

    // 117 Session 4 (finding #3c downstream): a sent voice message whose relay
    // upload failed now carries a durable 'upload_pending' owned copy
    // (sendVoiceMessage; see send_voice_message_durable_copy_test.dart).
    // conversation_wired must NOT attempt a relay download for it and must not
    // render "Media unavailable" — the durable file resolves locally and
    // 'upload_pending' is never flipped/recovered.
    testWidgets(
      'sent voice with a durable upload_pending copy is not re-downloaded',
      (tester) async {
        const blobId = 'durable-voice-blob-1';
        final peer = makeContact().peerId;
        // Production stores the ABSOLUTE durable path (so the retry path's raw
        // File(localPath).existsSync() resolves it).
        final durableAbsolute =
            '${Directory.systemTemp.path}/test_docs/media/$peer/$blobId.m4a';
        File(durableAbsolute)
          ..createSync(recursive: true)
          ..writeAsBytesSync(List<int>.filled(2048, 3));
        addTearDown(() {
          final f = File(durableAbsolute);
          if (f.existsSync()) f.deleteSync();
        });

        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();

        final durableAttachment = MediaAttachment(
          id: blobId,
          messageId: 'sent-voice-durable-1',
          mime: 'audio/mp4',
          size: 2048,
          mediaType: 'audio',
          durationMs: 4200,
          localPath: durableAbsolute,
          downloadStatus: 'upload_pending',
          createdAt: '2026-02-09T15:30:00.000Z',
        );
        final voiceMessage = ConversationMessage(
          id: 'sent-voice-durable-1',
          contactPeerId: peer,
          senderPeerId: makeIdentity().peerId,
          text: '',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'failed',
          isIncoming: false,
          createdAt: '2026-02-09T15:30:01.000Z',
          media: [durableAttachment],
        );
        await messageRepo.saveMessage(voiceMessage);
        await mediaAttachmentRepo.saveAttachment(
          durableAttachment,
          owner: MediaOwnerLane.direct,
        );

        var downloadCalls = 0;
        Future<MediaAttachment?> countingDownloadFn({
          required Bridge bridge,
          required MediaAttachmentRepository mediaAttachmentRepo,
          required MediaFileManager mediaFileManager,
          required MediaAttachment attachment,
          required String contactPeerId,
          required MediaOwnerLane owner,
          MessageRepository? messageRepo,
          MediaDownloadIntent? intent,
        }) async {
          downloadCalls += 1;
          return null;
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          bridge: FakeBridge(),
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: FakeMediaFileManager(),
          downloadMediaFn: countingDownloadFn,
        );
        await tester.pump(const Duration(milliseconds: 400));

        // The durable copy resolves locally: no relay re-fetch, not unavailable.
        expect(
          downloadCalls,
          0,
          reason: 'a present durable copy must not trigger a relay download',
        );
        expect(find.text('Media unavailable'), findsNothing);
      },
    );

    testWidgets(
      'voice send persists upload_pending attachment before local transfer',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final callOrder = <String>[];
        mediaAttachmentRepo.onSaveAttachment = (attachment) =>
            callOrder.add('save:${attachment.downloadStatus}');
        // The recording file must exist: the Phase-4 LAN leg encrypts it
        // (the injected stub copySync's it) before sendLocalMedia.
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 1200
          ..fakeOutputPath = (File(
            '/tmp/quoted_voice_pending.m4a',
          )..writeAsBytesSync(List<int>.filled(64, 1))).path;
        addTearDown(() {
          for (final path in const [
            '/tmp/quoted_voice_pending.m4a',
            '/tmp/quoted_voice_pending.m4a.enc',
          ]) {
            final file = File(path);
            if (file.existsSync()) {
              file.deleteSync();
            }
          }
        });
        final p2pService = TrackingLocalMediaP2PService(
          callOrder: callOrder,
          localPeer: true,
          localMediaResult: true,
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          p2pService: p2pService,
          // 112 Phase 4: the voice LAN leg encrypts first and is skipped
          // (fail closed) without a bridge.
          bridge: FakeBridge(),
          audioRecorderService: recorder,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        final startRecording = screen.onRecordStart! as Future<void> Function();
        await startRecording();
        await tester.pump(const Duration(milliseconds: 100));

        final recordingScreen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        final stopRecording =
            recordingScreen.onRecordStop! as Future<void> Function();
        final stopFuture = stopRecording();
        await tester.pump(const Duration(milliseconds: 300));
        await stopFuture;
        await pumpUntil(tester, () => callOrder.contains('sendLocalMedia'));

        expect(
          callOrder,
          containsAllInOrder(['save:upload_pending', 'sendLocalMedia']),
        );
        final savedAttachment = mediaAttachmentRepo.allSavedAttachments
            .firstWhere(
              (attachment) => attachment.downloadStatus == 'upload_pending',
            );
        expect(savedAttachment.messageId, isNotEmpty);
        expect(savedAttachment.localPath, recorder.fakeOutputPath);
        expect(savedAttachment.durationMs, recorder.fakeDurationMs);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'voice local transfer uses relay fallback with the optimistic attachment id',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        // The recording file must exist: the Phase-4 LAN leg encrypts it
        // (the injected stub copySync's it) before sendLocalMedia.
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 1200
          ..fakeOutputPath = (File(
            '/tmp/voice_local_stable.m4a',
          )..writeAsBytesSync(List<int>.filled(64, 1))).path;
        addTearDown(() {
          for (final path in const [
            '/tmp/voice_local_stable.m4a',
            '/tmp/voice_local_stable.m4a.enc',
          ]) {
            final file = File(path);
            if (file.existsSync()) {
              file.deleteSync();
            }
          }
        });
        final callOrder = <String>[];
        final p2pService = TrackingLocalMediaP2PService(
          callOrder: callOrder,
          localPeer: true,
          localMediaResult: true,
        );
        String? capturedBlobId;

        Future<(SendVoiceMessageResult, ConversationMessage?)> sendVoiceFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String senderPeerId,
          required String senderUsername,
          required AudioRecording recording,
          required Bridge bridge,
          String? recipientMlKemPublicKey,
          MediaAttachmentRepository? mediaAttachmentRepo,
          MediaFileManager? mediaFileManager,
          String? text,
          String? quotedMessageId,
          List<double>? waveform,
          String? messageId,
          String? timestamp,
          String? blobId,
          preparedArtifact,
          mediaAdmission,
        }) async {
          capturedBlobId = blobId;
          callOrder.add('sendVoiceMessage');
          if (mediaAttachmentRepo != null && messageId != null) {
            await mediaAttachmentRepo.saveAttachment(
              MediaAttachment(
                id: blobId ?? 'voice-local-relay-upload-id',
                messageId: messageId,
                mime: recording.mime,
                size: recording.sizeBytes,
                mediaType: 'audio',
                durationMs: recording.durationMs,
                localPath: recording.filePath,
                downloadStatus: 'done',
                createdAt:
                    timestamp ?? DateTime.now().toUtc().toIso8601String(),
                waveform: waveform,
              ),
              owner: MediaOwnerLane.direct,
            );
          }

          final delivered = ConversationMessage(
            id: messageId!,
            contactPeerId: targetPeerId,
            senderPeerId: senderPeerId,
            text: text ?? '',
            timestamp: timestamp!,
            status: 'delivered',
            isIncoming: false,
            createdAt: timestamp,
            quotedMessageId: quotedMessageId,
          );
          await messageRepo.saveMessage(delivered);
          return (SendVoiceMessageResult.success, delivered);
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          bridge: FakeBridge(),
          p2pService: p2pService,
          audioRecorderService: recorder,
          mediaAttachmentRepo: mediaAttachmentRepo,
          sendVoiceMessageFn: sendVoiceFn,
        );

        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        final startRecording = screen.onRecordStart! as Future<void> Function();
        await startRecording();
        await tester.pump(const Duration(milliseconds: 100));

        final recordingScreen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        final stopRecording =
            recordingScreen.onRecordStop! as Future<void> Function();
        await stopRecording();
        await tester.pump(const Duration(milliseconds: 300));
        await pumpUntil(tester, () => capturedBlobId != null);

        expect(
          callOrder,
          containsAllInOrder(['sendLocalMedia', 'sendVoiceMessage']),
        );
        expect(capturedBlobId, p2pService.lastLocalMediaId);

        final sentMessage = messageRepo.store.values.firstWhere(
          (message) => !message.isIncoming,
        );
        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          sentMessage.id,
          owner: MediaOwnerLane.direct,
        );
        expect(attachments.length, 1);
        expect(attachments.single.id, capturedBlobId);
        expect(attachments.single.downloadStatus, 'done');
        final pending = await mediaAttachmentRepo.getUploadPendingAttachments(
          owner: MediaOwnerLane.direct,
        );
        expect(
          pending.where((attachment) => attachment.messageId == sentMessage.id),
          isEmpty,
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'voice relay fallback passes optimistic attachment id to sendVoiceMessage',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 1200
          ..fakeOutputPath = '/tmp/voice_relay_stable.m4a';
        String? capturedBlobId;

        Future<(SendVoiceMessageResult, ConversationMessage?)> sendVoiceFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String senderPeerId,
          required String senderUsername,
          required AudioRecording recording,
          required Bridge bridge,
          String? recipientMlKemPublicKey,
          MediaAttachmentRepository? mediaAttachmentRepo,
          MediaFileManager? mediaFileManager,
          String? text,
          String? quotedMessageId,
          List<double>? waveform,
          String? messageId,
          String? timestamp,
          String? blobId,
          preparedArtifact,
          mediaAdmission,
        }) async {
          capturedBlobId = blobId;
          if (mediaAttachmentRepo != null && messageId != null) {
            await mediaAttachmentRepo.saveAttachment(
              MediaAttachment(
                id: blobId ?? 'voice-fallback-upload-id',
                messageId: messageId,
                mime: recording.mime,
                size: recording.sizeBytes,
                mediaType: 'audio',
                durationMs: recording.durationMs,
                localPath: recording.filePath,
                downloadStatus: 'done',
                createdAt:
                    timestamp ?? DateTime.now().toUtc().toIso8601String(),
                waveform: waveform,
              ),
              owner: MediaOwnerLane.direct,
            );
          }

          final delivered = ConversationMessage(
            id: messageId!,
            contactPeerId: targetPeerId,
            senderPeerId: senderPeerId,
            text: text ?? '',
            timestamp: timestamp!,
            status: 'delivered',
            isIncoming: false,
            createdAt: timestamp,
            quotedMessageId: quotedMessageId,
          );
          await messageRepo.saveMessage(delivered);
          return (SendVoiceMessageResult.success, delivered);
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          bridge: FakeBridge(),
          audioRecorderService: recorder,
          mediaAttachmentRepo: mediaAttachmentRepo,
          sendVoiceMessageFn: sendVoiceFn,
        );

        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        final startRecording = screen.onRecordStart! as Future<void> Function();
        await startRecording();
        await tester.pump(const Duration(milliseconds: 100));

        final recordingScreen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        final stopRecording =
            recordingScreen.onRecordStop! as Future<void> Function();
        await stopRecording();
        await tester.pump(const Duration(milliseconds: 300));

        final sentMessage = messageRepo.store.values.firstWhere(
          (message) => !message.isIncoming,
        );
        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          sentMessage.id,
          owner: MediaOwnerLane.direct,
        );
        expect(capturedBlobId, isNotNull);
        expect(attachments.length, 1);
        expect(attachments.single.id, capturedBlobId);
        expect(attachments.single.downloadStatus, 'done');
        final pending = await mediaAttachmentRepo.getUploadPendingAttachments(
          owner: MediaOwnerLane.direct,
        );
        expect(
          pending.where((attachment) => attachment.messageId == sentMessage.id),
          isEmpty,
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'repository change updates failed outgoing reply status in place',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final contact = makeContact();
        final parent = ConversationMessage(
          id: 'parent-retry',
          contactPeerId: contact.peerId,
          senderPeerId: contact.peerId,
          text: 'Original parent',
          timestamp: '2026-02-09T15:29:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:29:01.000Z',
        );
        final failedReply = ConversationMessage(
          id: 'failed-retry',
          contactPeerId: contact.peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Retry me',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'failed',
          isIncoming: false,
          createdAt: '2026-02-09T15:30:00.000Z',
          quotedMessageId: 'parent-retry',
        );
        await messageRepo.saveMessage(parent);
        await messageRepo.saveMessage(failedReply);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
        // TC-185-30: the Retry AFFORDANCE (not just the error glyph) is present
        // while failed. This assertion pair is the lock — it must CLEAR when the
        // row flips to delivered (the delivered bubble must never keep Retry).
        expect(
          find.byKey(const ValueKey('failed-message-retry-failed-retry')),
          findsOneWidget,
        );

        await messageRepo.saveMessage(
          failedReply.copyWith(status: 'delivered'),
        );
        await tester.pump(const Duration(milliseconds: 500));
        // 159: the messageChanges status update applies on the per-frame
        // coalesced flush (post-frame), so pump one more frame for it to land.
        await tester.pump();

        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
        // 155: reached with no resolved transport → single-check fallback
        // (never the retired two-tick).
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);
        // TC-185-30: the Retry control is a pure function of persisted status
        // via messageChanges — it must disappear once delivered.
        expect(
          find.byKey(const ValueKey('failed-message-retry-failed-retry')),
          findsNothing,
          reason: 'a delivered row must not keep the Retry affordance (INV-4)',
        );
      },
    );

    testWidgets(
      'TC-185-33 a failed->delivered flip is durable across a conversation reopen',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final failedReply = ConversationMessage(
          id: 'reopen-durable',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Durable me',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'failed',
          isIncoming: false,
          createdAt: '2026-02-09T15:30:00.000Z',
        );
        await messageRepo.saveMessage(failedReply);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );
        expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
        expect(
          find.byKey(const ValueKey('failed-message-retry-reopen-durable')),
          findsOneWidget,
        );

        // Persist the delivered status (as the receipt arm does), then REOPEN
        // the conversation from scratch (fresh widget over the durable store).
        await messageRepo.saveMessage(
          failedReply.copyWith(status: 'delivered'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        expect(
          find.byIcon(Icons.error_outline_rounded),
          findsNothing,
          reason:
              'the reopened conversation reconstructs the DURABLE delivered '
              'status (mutation: flip only in-memory -> reopen shows failed)',
        );
        expect(
          find.byKey(const ValueKey('failed-message-retry-reopen-durable')),
          findsNothing,
        );

        // Drain the reopened screen's foreground timers before teardown.
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets('upload failure restores quote draft and attachments', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final incoming = ConversationMessage(
        id: 'incoming-upload',
        contactPeerId: makeContact().peerId,
        senderPeerId: makeContact().peerId,
        text: 'Upload parent',
        timestamp: '2026-02-09T15:30:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-02-09T15:30:01.000Z',
      );
      await messageRepo.saveMessage(incoming);

      final tempDir = Directory.systemTemp.createTempSync('conv_retry_upload_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final attachment = File('${tempDir.path}/retry.jpg')
        ..writeAsStringSync('image');

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        bridge: FakeBridge(),
        uploadMediaFn:
            ({
              required bridge,
              required localFilePath,
              required mime,
              required recipientPeerId,
              mediaFileManager,
              blobId,
              width,
              height,
              durationMs,
              waveform,
              allowedPeers,
              deleteSourceWhenDone = false,
              preparedArtifact,
            }) async => null,
        initialAttachments: [attachment],
      );

      final screen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      screen.onQuoteReply!.call('incoming-upload');
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Retry upload');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Upload parent'), findsWidgets);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'Retry upload',
      );
      expect(find.text('Failed to upload media. Try again.'), findsOneWidget);
    });

    testWidgets(
      'offline banner seeds current state and follows both service edges',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final p2pService = FakeP2PService(initialState: NodeState.stopped);
        addTearDown(p2pService.dispose);
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          p2pService: p2pService,
        );

        expect(
          find.byKey(const ValueKey('offline-message-banner')),
          findsOneWidget,
        );
        expect(find.text("You're offline"), findsOneWidget);

        p2pService.emitState(
          const NodeState(
            isStarted: true,
            peerId: 'me',
            sendCapabilityReady: true,
            inboxCapabilityReady: true,
          ),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('offline-message-banner')),
          findsNothing,
        );

        p2pService.emitState(NodeState.stopped);
        await tester.pump();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('offline-message-banner')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'retry progress is message-keyed, attachment-correlated, and cleaned on settle',
      (tester) async {
        final identity = makeIdentity();
        final contact = makeContact();
        final identityRepo = FakeIdentityRepository(identity);
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final createdAt = DateTime.now().toUtc().toIso8601String();
        ConversationMessage queuedMessage(String messageId, String blobId) {
          return ConversationMessage(
            id: messageId,
            contactPeerId: contact.peerId,
            senderPeerId: identity.peerId,
            text: '',
            timestamp: createdAt,
            status: 'sending',
            isIncoming: false,
            createdAt: createdAt,
            media: [
              MediaAttachment(
                id: blobId,
                messageId: messageId,
                mime: 'image/jpeg',
                size: 10,
                mediaType: 'image',
                downloadStatus: 'upload_pending',
                createdAt: createdAt,
              ),
            ],
          );
        }

        final queuedA = queuedMessage('retry-progress-a', 'retry-blob-a');
        final queuedB = queuedMessage('retry-progress-b', 'retry-blob-b');
        await messageRepo.saveMessage(queuedA);
        await messageRepo.saveMessage(queuedB);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          initialMessages: [queuedA, queuedB],
        );

        emitMediaUploadProgressEvent({
          'id': 'wrong-blob',
          'sentBytes': 5,
          'totalBytes': 10,
          'toPeerId': contact.peerId,
        });
        await tester.pump();
        var projectedScreen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        expect(projectedScreen.messageUploadProgress, isEmpty);

        emitMediaUploadProgressEvent({
          'id': 'retry-blob-a',
          'sentBytes': 1,
          'toPeerId': contact.peerId,
        });
        await tester.pump();
        await tester.pump();
        projectedScreen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        expect(
          projectedScreen
              .messageUploadProgress['retry-progress-a']
              ?.attachmentId,
          'retry-blob-a',
        );
        expect(
          projectedScreen.messageUploadProgress['retry-progress-a']?.totalBytes,
          0,
        );

        emitMediaUploadProgressEvent({
          'id': 'retry-blob-a',
          'sentBytes': 5,
          'totalBytes': 10,
          'toPeerId': contact.peerId,
        });
        emitMediaUploadProgressEvent({
          'id': 'retry-blob-b',
          'sentBytes': 2,
          'totalBytes': 10,
          'toPeerId': contact.peerId,
        });
        await tester.pump();
        await tester.pump();
        projectedScreen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        expect(
          projectedScreen.messageUploadProgress['retry-progress-a']?.percent,
          50,
        );
        expect(
          projectedScreen.messageUploadProgress['retry-progress-b']?.percent,
          20,
        );

        emitMediaUploadProgressEvent({
          'id': 'retry-blob-a',
          'sentBytes': 1,
          'totalBytes': 10,
          'toPeerId': contact.peerId,
        });
        await tester.pump();
        projectedScreen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        expect(
          projectedScreen.messageUploadProgress['retry-progress-a']?.percent,
          50,
        );

        await messageRepo.updateMessageStatus(queuedA.id, 'sent');
        await pumpUntil(
          tester,
          () =>
              tester
                  .widget<ConversationScreen>(find.byType(ConversationScreen))
                  .messages
                  .where((message) => message.id == queuedA.id)
                  .single
                  .status ==
              'sent',
        );
        projectedScreen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        expect(
          projectedScreen.messageUploadProgress.containsKey('retry-progress-a'),
          isFalse,
        );
        expect(
          projectedScreen.messageUploadProgress.containsKey('retry-progress-b'),
          isTrue,
        );

        emitMediaUploadProgressEvent({
          'id': 'retry-blob-a',
          'sentBytes': 9,
          'totalBytes': 10,
          'toPeerId': contact.peerId,
        });
        await tester.pump();
        await tester.pump();
        projectedScreen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        expect(
          projectedScreen.messageUploadProgress.containsKey('retry-progress-a'),
          isFalse,
        );
      },
    );

    testWidgets('shows relay upload progress and blocks leaving mid-upload', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final tempDir = Directory.systemTemp.createTempSync(
        'conv_upload_progress_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final attachment = File('${tempDir.path}/progress.jpg')
        ..writeAsStringSync('0123456789');

      final uploadGate = Completer<void>();
      final uploadStarted = Completer<void>();
      String? activeBlobId;

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        bridge: FakeBridge(),
        uploadMediaFn:
            ({
              required bridge,
              required localFilePath,
              required mime,
              required recipientPeerId,
              mediaFileManager,
              blobId,
              width,
              height,
              durationMs,
              waveform,
              allowedPeers,
              deleteSourceWhenDone = false,
              preparedArtifact,
            }) async {
              activeBlobId = blobId;
              uploadStarted.complete();
              await uploadGate.future;
              return MediaAttachment(
                id: blobId ?? 'uploaded-progress-1',
                messageId: '',
                mime: mime,
                size: File(localFilePath).lengthSync(),
                mediaType: MediaAttachment.mediaTypeFromMime(mime),
                localPath: localFilePath,
                downloadStatus: 'done',
                createdAt: DateTime.now().toUtc().toIso8601String(),
              );
            },
        initialAttachments: [attachment],
      );

      await tester.enterText(find.byType(TextField), 'Uploading');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await uploadStarted.future;
      await tester.pump();

      expect(
        find.byKey(const ValueKey('upload-progress-banner')),
        findsOneWidget,
      );
      expect(wakeLockDriver.enableCalls, 1);
      expect(UploadWakeLockController.debugActiveHolds, 1);

      emitMediaUploadProgressEvent({
        'id': activeBlobId,
        'sentBytes': 5,
        'totalBytes': 10,
        'toPeerId': makeContact().peerId,
      });
      await tester.pump();

      expect(find.text('50%'), findsOneWidget);
      expect(find.text('Sending automatically…'), findsOneWidget);
      expect(find.text('Uploading photo · 50%'), findsOneWidget);
      expect(
        find.text('Keep the app open until the upload completes'),
        findsOneWidget,
      );

      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pump();

      expect(find.text('Leave conversation?'), findsOneWidget);
      expect(
        find.text(
          'An upload is in progress. Leaving may interrupt it. Are you sure?',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('upload-leave-stay')));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('upload-progress-banner')),
        findsOneWidget,
      );
      expect(wakeLockDriver.disableCalls, 0);

      uploadGate.complete();
      await pumpUntil(
        tester,
        () =>
            find
                .byKey(const ValueKey('upload-progress-banner'))
                .evaluate()
                .isEmpty &&
            wakeLockDriver.disableCalls == 1,
      );

      expect(UploadWakeLockController.debugActiveHolds, 0);
      expect(find.text('Sending automatically…'), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets(
      'disposing mid-upload detaches UI without releasing wake; terminal '
      'completion releases the exact hold once',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final tempDir = Directory.systemTemp.createTempSync(
          'conv_dispose_upload_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachment = File('${tempDir.path}/dispose.jpg')
          ..writeAsStringSync('0123456789');
        final uploadGate = Completer<void>();
        final uploadStarted = Completer<void>();
        addTearDown(() {
          if (!uploadGate.isCompleted) uploadGate.complete();
        });

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          bridge: FakeBridge(),
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                blobId,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async {
                uploadStarted.complete();
                await uploadGate.future;
                return MediaAttachment(
                  id: blobId ?? 'uploaded-dispose-1',
                  messageId: '',
                  mime: mime,
                  size: File(localFilePath).lengthSync(),
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath: localFilePath,
                  downloadStatus: 'done',
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                );
              },
          initialAttachments: [attachment],
        );

        await tester.enterText(find.byType(TextField), 'Dispose during upload');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await uploadStarted.future;
        await tester.pump();

        expect(
          find.byKey(const ValueKey('upload-progress-banner')),
          findsOneWidget,
        );
        expect(wakeLockDriver.enableCalls, 1);
        expect(wakeLockDriver.disableCalls, 0);
        expect(UploadWakeLockController.debugActiveHolds, 1);

        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        await tester.pump();

        expect(find.byType(ConversationWired), findsNothing);
        expect(
          find.byKey(const ValueKey('upload-progress-banner')),
          findsNothing,
        );
        expect(wakeLockDriver.disableCalls, 0);
        expect(
          UploadWakeLockController.debugActiveHolds,
          1,
          reason: 'view disposal must detach UI without ending the operation',
        );

        uploadGate.complete();
        await pumpUntil(
          tester,
          () =>
              wakeLockDriver.disableCalls == 1 &&
              UploadWakeLockController.debugActiveHolds == 0,
        );

        expect(wakeLockDriver.enableCalls, 1);
        expect(wakeLockDriver.disableCalls, 1);
        expect(UploadWakeLockController.debugActiveHolds, 0);
        await tester.pump(const Duration(milliseconds: 500));
        expect(wakeLockDriver.disableCalls, 1);
      },
    );

    testWidgets(
      'cancel on the active upload banner restores video composer state and suppresses the final send',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final tempDir = Directory.systemTemp.createTempSync(
          'conv_cancel_upload_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachment = File('${tempDir.path}/cancel.mp4')
          ..writeAsStringSync('0123456789');

        final uploadGate = Completer<void>();
        final uploadStarted = Completer<void>();
        var sendCalls = 0;

        Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          sendCalls++;
          return _instantSuccessSendFn(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: targetPeerId,
            text: text,
            senderPeerId: senderPeerId,
            senderUsername: senderUsername,
            messageId: messageId,
            preassignedMessageIdIsFresh: preassignedMessageIdIsFresh,
            timestamp: timestamp,
            bridge: bridge,
            recipientMlKemPublicKey: recipientMlKemPublicKey,
            quotedMessageId: quotedMessageId,
            mediaAttachments: mediaAttachments,
            mediaAttachmentRepo: mediaAttachmentRepo,
          );
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
          bridge: FakeBridge(),
          mediaAttachmentRepo: mediaAttachmentRepo,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                blobId,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async {
                uploadStarted.complete();
                await uploadGate.future;
                return MediaAttachment(
                  id: blobId ?? 'uploaded-cancel-1',
                  messageId: '',
                  mime: mime,
                  size: File(localFilePath).lengthSync(),
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath: localFilePath,
                  downloadStatus: 'done',
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                );
              },
          initialAttachments: [attachment],
        );

        await tester.enterText(find.byType(TextField), 'Cancel upload');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await uploadStarted.future;
        await tester.pump();

        expect(
          find.byKey(const ValueKey('upload-progress-cancel-button')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('upload-progress-cancel-button')),
        );
        await tester.pump();

        expect(
          find.byKey(const ValueKey('upload-progress-cancel-button')),
          findsNothing,
        );

        uploadGate.complete();
        await pumpUntil(
          tester,
          () =>
              find
                  .byKey(const ValueKey('upload-progress-banner'))
                  .evaluate()
                  .isEmpty &&
              wakeLockDriver.disableCalls == 1,
        );

        expect(find.text('Upload cancelled.'), findsOneWidget);
        expect(find.text('Failed to upload media. Try again.'), findsNothing);
        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Cancel upload',
        );
        expect(find.text('Retry'), findsNothing);
        expect(find.text('Delete'), findsNothing);
        expect(messageRepo.store.values.single.status, 'failed');
        final failedMessageId = messageRepo.store.values.single.id;
        final storedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(
              failedMessageId,
              owner: MediaOwnerLane.direct,
            );
        expect(storedAttachments, hasLength(1));
        expect(storedAttachments.single.downloadStatus, 'upload_cancelled');
        expect(sendCalls, 0);
        expect(UploadWakeLockController.debugActiveHolds, 0);
      },
    );

    testWidgets(
      'cancel requested before an upload failure resolves still shows the cancel outcome',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final tempDir = Directory.systemTemp.createTempSync(
          'conv_cancel_upload_failure_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachment = File('${tempDir.path}/cancel-failure.mp4')
          ..writeAsStringSync('0123456789');

        final uploadGate = Completer<void>();
        final uploadStarted = Completer<void>();
        var sendCalls = 0;

        Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async {
          sendCalls++;
          return _instantSuccessSendFn(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: targetPeerId,
            text: text,
            senderPeerId: senderPeerId,
            senderUsername: senderUsername,
            messageId: messageId,
            preassignedMessageIdIsFresh: preassignedMessageIdIsFresh,
            timestamp: timestamp,
            bridge: bridge,
            recipientMlKemPublicKey: recipientMlKemPublicKey,
            quotedMessageId: quotedMessageId,
            mediaAttachments: mediaAttachments,
            mediaAttachmentRepo: mediaAttachmentRepo,
          );
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
          bridge: FakeBridge(),
          mediaAttachmentRepo: mediaAttachmentRepo,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                blobId,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async {
                uploadStarted.complete();
                await uploadGate.future;
                return null;
              },
          initialAttachments: [attachment],
        );

        await tester.enterText(find.byType(TextField), 'Cancel failed upload');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await uploadStarted.future;
        await tester.pump();

        await tester.tap(
          find.byKey(const ValueKey('upload-progress-cancel-button')),
        );
        await tester.pump();

        uploadGate.complete();
        await pumpUntil(
          tester,
          () =>
              find
                  .byKey(const ValueKey('upload-progress-banner'))
                  .evaluate()
                  .isEmpty &&
              wakeLockDriver.disableCalls == 1,
        );

        expect(find.text('Upload cancelled.'), findsOneWidget);
        expect(find.text('Failed to upload media. Try again.'), findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Cancel failed upload',
        );
        expect(find.text('Retry'), findsNothing);
        expect(find.text('Delete'), findsNothing);
        expect(sendCalls, 0);
        expect(messageRepo.store.values.single.status, 'failed');
        final failedMessageId = messageRepo.store.values.single.id;
        final storedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(
              failedMessageId,
              owner: MediaOwnerLane.direct,
            );
        expect(storedAttachments, hasLength(1));
        expect(storedAttachments.single.downloadStatus, 'upload_cancelled');
      },
    );

    testWidgets('retry control re-sends a failed outgoing media row', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final mediaAttachmentRepo = FakeMediaAttachmentRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final failedMessage = ConversationMessage(
        id: 'failed-media-msg',
        contactPeerId: makeContact().peerId,
        senderPeerId: makeIdentity().peerId,
        text: 'Retry me',
        timestamp: '2026-02-11T10:05:00.000Z',
        status: 'failed',
        wireEnvelope: '{"ciphertext":"abc"}',
        isIncoming: false,
        createdAt: '2026-02-11T10:05:00.000Z',
        media: const [
          MediaAttachment(
            id: 'persisted-attachment',
            messageId: 'failed-media-msg',
            mime: 'image/jpeg',
            size: 10,
            mediaType: 'image',
            localPath: '/tmp/retry.jpg',
            downloadStatus: 'done',
            createdAt: '2026-02-11T10:05:00.000Z',
          ),
        ],
      );
      await messageRepo.saveMessage(failedMessage);
      mediaAttachmentRepo.seedAttachments(
        messageId: failedMessage.id,
        attachments: failedMessage.media,
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        bridge: FakeBridge(),
        contactRepo: FakeContactRepository(),
        mediaAttachmentRepo: mediaAttachmentRepo,
        p2pService: InboxRetryP2PService(),
      );
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(
        find.byKey(const ValueKey('failed-media-retry-failed-media-msg')),
      );
      await pumpUntil(
        tester,
        // F6: relay re-store is custody, not delivery — settles 'inboxed'.
        () => messageRepo.store['failed-media-msg']?.status == 'inboxed',
      );

      expect(messageRepo.store['failed-media-msg']?.status, 'inboxed');
      // 184: on 1:1, relay CUSTODY ('inboxed') now renders the two-tick done_all
      // (the honest "the system has it" milestone), not the inbox transport
      // glyph. The relay-inbox re-store still stamps transport 'inbox' in the row.
      expect(messageRepo.store['failed-media-msg']?.transport, 'inbox');
      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      expect(find.byIcon(Icons.inbox), findsNothing);
      expect(find.text('Could not retry media message.'), findsNothing);
    });

    testWidgets(
      'manual retry resolves a relative terminal media path before upload',
      (tester) async {
        mediaUploadInFlightTracker.clearAll();
        addTearDown(mediaUploadInFlightTracker.clearAll);
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final messageRepo = _ManualRetryFakeMessageRepository(
          mediaAttachmentRepo,
        );
        final mediaFileManager = FakeMediaFileManager();
        final contactRepo = _SingleContactRepository(
          makeContact().copyWith(mlKemPublicKey: 'test-mlkem-public-key'),
        );
        final tempDir = Directory.systemTemp.createTempSync(
          'conv_manual_retry_relative_',
        );
        MediaFileManager.cacheDocumentsDir(tempDir.path);
        addTearDown(() {
          MediaFileManager.debugResetDocumentsDirCache();
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final source = File(
          '${tempDir.path}/pending_uploads/failed-relative-media-msg/retry.jpg',
        )..parent.createSync(recursive: true);
        source.writeAsBytesSync(_tinyPngBytes);
        mediaFileManager.resolveResult = source.path;
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );
        const messageId = 'failed-relative-media-msg';
        const attachmentId = 'failed-relative-media-att';
        const storedPath =
            'pending_uploads/failed-relative-media-msg/retry.jpg';
        final failedMessage = ConversationMessage(
          id: messageId,
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Retry relative media',
          timestamp: '2026-02-11T10:06:00.000Z',
          status: 'failed',
          wireEnvelope: '{"stale":true}',
          isIncoming: false,
          createdAt: '2026-02-11T10:06:00.000Z',
          media: const [
            MediaAttachment(
              id: attachmentId,
              messageId: messageId,
              mime: 'image/jpeg',
              size: 10,
              mediaType: 'image',
              localPath: storedPath,
              downloadStatus: 'upload_failed',
              uploadRetryCount: kMaxUploadRetries,
              createdAt: '2026-02-11T10:06:00.000Z',
            ),
          ],
        );
        await messageRepo.saveMessage(failedMessage);
        mediaAttachmentRepo.seedAttachments(
          messageId: messageId,
          attachments: failedMessage.media,
        );
        String? uploadedPath;
        MediaFileManager? uploadedWithManager;

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          bridge: FakeBridge(),
          contactRepo: contactRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                blobId,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async {
                uploadedPath = localFilePath;
                uploadedWithManager = mediaFileManager;
                return MediaAttachment(
                  id: blobId!,
                  messageId: messageId,
                  mime: mime,
                  size: source.lengthSync(),
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath: localFilePath,
                  downloadStatus: 'done',
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                  contentHash:
                      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                  encryptionKeyBase64: 'test-blob-key',
                  encryptionNonce: 'test-blob-nonce',
                  encryptionScheme:
                      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                );
              },
          p2pService: InboxRetryP2PService(),
        );

        final resolveCountBeforeRetry = mediaFileManager.resolveStoredPathCount;
        await tester.tap(
          find.byKey(const ValueKey('failed-media-retry-$messageId')),
        );
        await tester.pump();
        await pumpUntilAsyncIo(
          tester,
          () => messageRepo.store[messageId]?.status == 'inboxed',
        );

        expect(
          mediaFileManager.resolveStoredPathCount,
          greaterThan(resolveCountBeforeRetry),
        );
        expect(uploadedPath, source.path);
        expect(uploadedWithManager, same(mediaFileManager));
        expect(messageRepo.manualRearmCalls, 1);
        expect(mediaUploadInFlightTracker.isInFlight(attachmentId), isFalse);
        final stored = await mediaAttachmentRepo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        );
        expect(stored.single.id, attachmentId);
        expect(stored.single.downloadStatus, 'done');
      },
    );

    testWidgets('delete control removes a failed outgoing media row and files', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final mediaAttachmentRepo = FakeMediaAttachmentRepository();
      final mediaFileManager = FakeMediaFileManager();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final failedMessage = ConversationMessage(
        id: 'failed-delete-msg',
        contactPeerId: makeContact().peerId,
        senderPeerId: makeIdentity().peerId,
        text: '',
        timestamp: '2026-02-11T10:05:00.000Z',
        status: 'failed',
        isIncoming: false,
        createdAt: '2026-02-11T10:05:00.000Z',
        media: const [
          MediaAttachment(
            id: 'pending-delete-attachment',
            messageId: 'failed-delete-msg',
            mime: 'image/jpeg',
            size: 10,
            mediaType: 'image',
            localPath:
                'pending_uploads/failed-delete-msg/pending-delete-attachment.jpg',
            downloadStatus: 'upload_pending',
            createdAt: '2026-02-11T10:05:00.000Z',
          ),
        ],
      );
      await messageRepo.saveMessage(failedMessage);
      mediaAttachmentRepo.seedAttachments(
        messageId: failedMessage.id,
        attachments: failedMessage.media,
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
      );
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(
        find.byKey(const ValueKey('failed-media-delete-failed-delete-msg')),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(messageRepo.store.containsKey(failedMessage.id), isFalse);
      expect(
        await mediaAttachmentRepo.getAttachmentsForMessage(
          failedMessage.id,
          owner: MediaOwnerLane.direct,
        ),
        isEmpty,
      );
      expect(
        mediaFileManager.deletedFilePaths,
        contains(
          endsWith(
            'pending_uploads/failed-delete-msg/pending-delete-attachment.jpg',
          ),
        ),
      );
    });

    testWidgets(
      'ordinary failed-media delete retains durable authority when plaintext deletion throws',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync(
          'ordinary-failed-media-delete-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        const messageId = 'ordinary-delete-file-failure';
        const attachmentId = 'ordinary-delete-file-failure-attachment';
        const storedPath =
            'pending_uploads/ordinary-delete-file-failure/'
            'ordinary-delete-file-failure-attachment.jpg';
        final pendingPlaintext = File('${tempDir.path}/$storedPath')
          ..createSync(recursive: true)
          ..writeAsBytesSync(const <int>[1, 2, 3, 4]);
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final mediaFileManager =
            _ThrowingPendingPlaintextDeleteMediaFileManager(tempDir);
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final failedMessage = ConversationMessage(
          id: messageId,
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: '',
          timestamp: '2026-02-11T10:05:00.000Z',
          status: 'failed',
          isIncoming: false,
          createdAt: '2026-02-11T10:05:00.000Z',
          media: const <MediaAttachment>[
            MediaAttachment(
              id: attachmentId,
              messageId: messageId,
              mime: 'image/jpeg',
              size: 4,
              mediaType: 'image',
              localPath: storedPath,
              downloadStatus: 'upload_pending',
              createdAt: '2026-02-11T10:05:00.000Z',
            ),
          ],
        );
        await messageRepo.saveMessage(failedMessage);
        mediaAttachmentRepo.seedAttachments(
          messageId: messageId,
          attachments: failedMessage.media,
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
        );
        await tester.pump(const Duration(milliseconds: 500));

        await tester.tap(
          find.byKey(const ValueKey('failed-media-delete-$messageId')),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(mediaFileManager.deleteAttempts, 1);
        expect(mediaFileManager.attemptedStoredPaths, const <String?>[
          storedPath,
        ]);
        expect(pendingPlaintext.existsSync(), isTrue);
        expect(messageRepo.store.containsKey(messageId), isTrue);
        final retained = await mediaAttachmentRepo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        );
        expect(retained, hasLength(1));
        expect(retained.single.id, attachmentId);
        expect(retained.single.localPath, storedPath);
        expect(retained.single.downloadStatus, 'upload_failed');
      },
    );

    testWidgets(
      'direct terminalization preserves same id group pending media',
      (tester) async {
        // 228 TC-228-05B: a GROUP message can legally share this message id.
        // The failed-media delete control terminalizes and cleans up the
        // DIRECT lane only — the same-ID group sibling row must stay
        // upload_pending and keep its file.
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final mediaAttachmentRepo =
            TerminalizationRecordingMediaAttachmentRepository();
        final mediaFileManager = FakeMediaFileManager();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final failedMessage = ConversationMessage(
          id: 'collide-lane-msg',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: '',
          timestamp: '2026-02-11T10:05:00.000Z',
          status: 'failed',
          isIncoming: false,
          createdAt: '2026-02-11T10:05:00.000Z',
          media: const [
            MediaAttachment(
              id: 'att-collide-direct',
              messageId: 'collide-lane-msg',
              mime: 'image/jpeg',
              size: 10,
              mediaType: 'image',
              localPath:
                  'pending_uploads/collide-lane-msg/att-collide-direct.jpg',
              downloadStatus: 'upload_pending',
              createdAt: '2026-02-11T10:05:00.000Z',
            ),
          ],
        );
        await messageRepo.saveMessage(failedMessage);
        mediaAttachmentRepo.seedAttachments(
          messageId: failedMessage.id,
          attachments: failedMessage.media,
        );
        // Same-ID sibling in the GROUP lane (different attachment id).
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'att-collide-group',
            messageId: 'collide-lane-msg',
            mime: 'image/jpeg',
            size: 10,
            mediaType: 'image',
            localPath: 'pending_uploads/collide-lane-msg/att-collide-group.jpg',
            downloadStatus: 'upload_pending',
            createdAt: '2026-02-11T10:05:00.000Z',
          ),
          owner: MediaOwnerLane.group,
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
        );
        await tester.pump(const Duration(milliseconds: 500));

        await tester.tap(
          find.byKey(const ValueKey('failed-media-delete-collide-lane-msg')),
        );
        await tester.pump(const Duration(milliseconds: 500));

        // The flow terminalized ONLY the direct lane, and the direct row
        // became upload_failed before its owner-scoped removal.
        expect(mediaAttachmentRepo.terminalizedLanes, [MediaOwnerLane.direct]);
        expect(
          mediaAttachmentRepo.statusAfterTerminalization['att-collide-direct'],
          'upload_failed',
        );
        expect(
          await mediaAttachmentRepo.getAttachmentsForMessage(
            failedMessage.id,
            owner: MediaOwnerLane.direct,
          ),
          isEmpty,
        );
        expect(
          mediaFileManager.deletedFilePaths,
          contains(
            endsWith('pending_uploads/collide-lane-msg/att-collide-direct.jpg'),
          ),
        );

        // The same-ID group sibling row is STILL upload_pending and its
        // file was never deleted.
        final groupSiblings = await mediaAttachmentRepo
            .getAttachmentsForMessage(
              failedMessage.id,
              owner: MediaOwnerLane.group,
            );
        expect(groupSiblings.single.id, 'att-collide-group');
        expect(groupSiblings.single.downloadStatus, 'upload_pending');
        expect(
          mediaFileManager.deletedFilePaths,
          isNot(
            contains(
              endsWith(
                'pending_uploads/collide-lane-msg/att-collide-group.jpg',
              ),
            ),
          ),
        );
      },
    );

    testWidgets(
      'send failure after upload restores quote draft and attachments',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final incoming = ConversationMessage(
          id: 'incoming-send-fail',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeContact().peerId,
          text: 'Send parent',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:30:01.000Z',
        );
        await messageRepo.saveMessage(incoming);

        final tempDir = Directory.systemTemp.createTempSync('conv_retry_send_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachment = File('${tempDir.path}/retry.jpg')
          ..writeAsStringSync('image');

        Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          required bool preassignedMessageIdIsFresh,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          PrivateMediaPolicy? privateMediaPolicy,
          MediaAttachmentRepository? mediaAttachmentRepo,
          TransportMetrics? transportMetrics,
          DirectEventFanoutAuthoring? directEventFanout,
        }) async => (SendChatMessageResult.sendFailed, null);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
          bridge: FakeBridge(),
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                blobId,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async => MediaAttachment(
                id: 'uploaded-1',
                messageId: '',
                mime: mime,
                size: 1,
                mediaType: MediaAttachment.mediaTypeFromMime(mime),
                localPath: localFilePath,
                downloadStatus: 'done',
                createdAt: DateTime.now().toUtc().toIso8601String(),
              ),
          initialAttachments: [attachment],
        );

        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        screen.onQuoteReply!.call('incoming-send-fail');
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'Retry send');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(find.text('Replying to'), findsOneWidget);
        expect(find.text('Send parent'), findsWidgets);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Retry send',
        );
        expect(
          find.text('Failed to send message. Message saved.'),
          findsOneWidget,
        );
      },
    );
  });

  group('ConversationWired recording lifecycle', () {
    Future<FakeAudioRecorderService> pumpAndStartRecording(
      WidgetTester tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final recorder = FakeAudioRecorderService();

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        audioRecorderService: recorder,
      );

      final screen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      final startRecording = screen.onRecordStart! as Future<void> Function();
      await startRecording();
      await tester.pump(const Duration(milliseconds: 100));
      expect(recorder.isRecording, isTrue);
      return recorder;
    }

    testWidgets('disposing the conversation while recording cancels the '
        'recorder', (tester) async {
      final recorder = await pumpAndStartRecording(tester);

      await tester.pumpWidget(const SizedBox.shrink());

      expect(recorder.isRecording, isFalse);
      expect(recorder.cancelCallCount, 1);
    });

    testWidgets('recorder auto-stop resets the composer recording state', (
      tester,
    ) async {
      final recorder = await pumpAndStartRecording(tester);
      expect(find.byType(RecordingOverlay), findsOneWidget);

      await recorder.triggerAutoStop();
      await tester.pump();

      expect(find.byType(RecordingOverlay), findsNothing);
      expect(recorder.isRecording, isFalse);
      expect(recorder.onAutoStopped, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('disposing with a displaced recording session leaves the '
        'recorder untouched', (tester) async {
      final recorder = await pumpAndStartRecording(tester);
      // Another surface took over the shared recorder (its start()
      // force-stopped this one's session and installed its own handler);
      // this screen's recording state is stale.
      recorder.onAutoStopped = (_) {};

      await tester.pumpWidget(const SizedBox.shrink());

      expect(recorder.cancelCallCount, 0);
      expect(recorder.isRecording, isTrue);
      expect(recorder.onAutoStopped, isNotNull);
    });
  });

  group('ConversationScreen WhatsApp date separators', () {
    testWidgets(
      'older-than-yesterday separator uses weekday + day + month format',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );

        // A message comfortably older than yesterday (same calendar year).
        final old = DateTime.now().subtract(const Duration(days: 5));
        final olderMessage = ConversationMessage(
          id: 'older-msg',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-bob',
          text: 'An older letter',
          timestamp: old.toUtc().toIso8601String(),
          status: 'delivered',
          isIncoming: true,
          createdAt: old.toUtc().toIso8601String(),
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          initialMessages: [olderMessage],
        );

        expect(find.text('An older letter'), findsOneWidget);

        final separators = tester
            .widgetList<DateSeparator>(find.byType(DateSeparator))
            .toList();
        expect(separators, hasLength(1));
        // WhatsApp style: e.g. "Wed 9. Jun" -- abbreviated weekday, day,
        // period, abbreviated month. NOT the old "Jun 9" (MMMd) format.
        expect(
          separators.single.label,
          matches(RegExp(r'^[A-Za-z]{3} \d{1,2}\. [A-Za-z]{3}$')),
        );
      },
    );

    testWidgets('today separator shows the localized Today label', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      final todayMessage = ConversationMessage(
        id: 'today-msg',
        contactPeerId: 'peer-bob',
        senderPeerId: 'peer-bob',
        text: 'A fresh letter',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        status: 'delivered',
        isIncoming: true,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        initialMessages: [todayMessage],
      );

      final separators = tester
          .widgetList<DateSeparator>(find.byType(DateSeparator))
          .toList();
      expect(separators, hasLength(1));
      expect(separators.single.label, 'Today');
    });
  });

  group('mic permission denied prompt (152)', () {
    Future<ConversationScreen> driveRecordStartSetup(
      WidgetTester tester, {
      required FakeAudioRecorderService recorder,
      required FakeMicPermissionGateway gateway,
    }) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        bridge: FakeBridge(),
        p2pService: FakeP2PService(localPeer: true, localMediaResult: true),
        audioRecorderService: recorder,
        micPermissionGateway: gateway,
      );
      return tester.widget<ConversationScreen>(find.byType(ConversationScreen));
    }

    testWidgets(
      '1:1 mic denial shows the rationale sheet instead of the snackbar (permanentlyDenied)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final recorder = FakeAudioRecorderService()..permissionGranted = false;
        final gateway = FakeMicPermissionGateway()
          ..statusToReturn = MicPermissionStatus.permanentlyDenied;
        final screen = await driveRecordStartSetup(
          tester,
          recorder: recorder,
          gateway: gateway,
        );

        final pending = (screen.onRecordStart! as Future<void> Function())();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byKey(const ValueKey('mic-perm-sheet')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('mic-perm-open-settings')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('mic-perm-not-now')), findsOneWidget);
        expect(find.text(l10n.perm_microphone_record), findsNothing);
        expect(recorder.startCallCount, 0);

        // Dismiss; the composer must reset to idle. Wait for the sheet route to
        // leave first so its decorative mic cannot satisfy the composer check.
        await tester.tap(find.byKey(const ValueKey('mic-perm-not-now')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await pending;
        await tester.pump();
        expect(find.byKey(const ValueKey('mic-perm-sheet')), findsNothing);
        expect(find.byIcon(Icons.stop_rounded), findsNothing);
        expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      },
    );

    testWidgets('1:1 Open Settings tap deep-links via the injected gateway', (
      tester,
    ) async {
      final recorder = FakeAudioRecorderService()..permissionGranted = false;
      final gateway = FakeMicPermissionGateway()
        ..statusToReturn = MicPermissionStatus.permanentlyDenied;
      final screen = await driveRecordStartSetup(
        tester,
        recorder: recorder,
        gateway: gateway,
      );

      final pending = (screen.onRecordStart! as Future<void> Function())();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('mic-perm-sheet')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mic-perm-open-settings')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await pending;

      expect(gateway.openAppSettingsCallCount, 1);
      expect(find.byKey(const ValueKey('mic-perm-sheet')), findsNothing);
    });

    testWidgets('granted mic permission still starts recording', (
      tester,
    ) async {
      final recorder = FakeAudioRecorderService();
      final gateway = FakeMicPermissionGateway()
        ..statusToReturn = MicPermissionStatus.granted;
      final screen = await driveRecordStartSetup(
        tester,
        recorder: recorder,
        gateway: gateway,
      );

      await (screen.onRecordStart! as Future<void> Function())();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('mic-perm-sheet')), findsNothing);
      expect(recorder.startCallCount, 1);
    });

    // Option A (owner-locked): a first plain `denied` (still re-promptable in
    // app — request() already showed the OS prompt) resets to idle WITHOUT
    // forcing the Settings dialog. Locks the denied-vs-permanentlyDenied axis.
    testWidgets(
      '1:1 first plain denied resets to idle with no sheet/snackbar',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final recorder = FakeAudioRecorderService();
        final gateway = FakeMicPermissionGateway()
          ..statusToReturn = MicPermissionStatus.denied;
        final screen = await driveRecordStartSetup(
          tester,
          recorder: recorder,
          gateway: gateway,
        );

        await (screen.onRecordStart! as Future<void> Function())();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byKey(const ValueKey('mic-perm-sheet')), findsNothing);
        expect(find.text(l10n.perm_microphone_record), findsNothing);
        expect(recorder.startCallCount, 0);
        // Live rendered composer is back to idle (mic shown, not recording).
        expect(find.byIcon(Icons.stop_rounded), findsNothing);
        expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      },
    );
  });

  // 159 sub-change 3 — the per-frame coalescer (which batches the per-event
  // message-apply setState) must NOT touch the 145 "catching up…" banner, the
  // NOTIFICATION_TAP_TO_LIVE_MESSAGE_TIMING milestone, CONV_FL_NOTIF_DRAIN_REFETCH,
  // or the already-coalesced bulk reload, and every drained message (131) must
  // still surface. This preservation lock is authored + GREEN BEFORE the
  // coalescer edit and must stay GREEN after it.
  group('159 coalesce preservation lock (TC-159-07)', () {
    ConversationMessage mkMsg(
      String id, {
      String ts = '2026-05-04T14:05:00.000Z',
    }) => ConversationMessage(
      id: id,
      contactPeerId: makeContact().peerId,
      senderPeerId: makeContact().peerId,
      text: 'drained $id',
      timestamp: ts,
      status: 'delivered',
      isIncoming: true,
      createdAt: ts,
    );

    testWidgets(
      'TC-159-07 coalescer does NOT regress 145 banner/milestone or 131 surfacing',
      (tester) async {
        final captured = <Map<String, dynamic>>[];
        debugSetFlowEventSink(captured.add);
        addTearDown(() => debugSetFlowEventSink(null));

        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final fresh = mkMsg('tc07-fresh');
        final gate = Completer<void>();
        final p2p = GatedDrainP2PService(repo: messageRepo, pending: [fresh])
          ..gate = gate;

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          p2pService: p2p,
          notificationTappedAt: DateTime.utc(2026, 5, 4, 14, 5),
        );

        // 145: the "catching up…" affordance shows while the drain is gated.
        await tester.pump();
        expect(
          find.byKey(const ValueKey('conversation-syncing-banner')),
          findsOneWidget,
          reason: '145 banner must show while the notif-tap drain is in flight',
        );

        // Release the drain → the message surfaces and the banner clears.
        gate.complete();
        await pumpUntil(
          tester,
          () => tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .messages
              .any((m) => m.id == 'tc07-fresh'),
        );
        await pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey('conversation-syncing-banner'))
              .evaluate()
              .isEmpty,
        );

        // 145: banner gone after the drain.
        expect(
          find.byKey(const ValueKey('conversation-syncing-banner')),
          findsNothing,
        );
        // 131: the drained message surfaced.
        expect(
          tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .messages
              .any((m) => m.id == 'tc07-fresh'),
          isTrue,
        );
        // 145: the live-render milestone is emitted exactly once.
        final live = captured
            .where(
              (e) => e['event'] == 'NOTIFICATION_TAP_TO_LIVE_MESSAGE_TIMING',
            )
            .toList();
        expect(live, hasLength(1));
        // 145: the drain-refetch flow event fired for the notif_tap trigger.
        final refetch = captured
            .where((e) => e['event'] == 'CONV_FL_NOTIF_DRAIN_REFETCH')
            .toList();
        expect(refetch, isNotEmpty);
        expect((refetch.first['details'] as Map)['trigger'], 'notif_tap');
      },
    );
  });

  test(
    'payload-ingested message later replayed by the drain renders exactly once',
    () async {
      final messageRepo = InMemoryMessageRepository();
      final payloadIngested = ConversationMessage(
        id: 'payload-drain-same-id',
        contactPeerId: 'peer-alice',
        senderPeerId: 'peer-alice',
        text: 'payload first',
        timestamp: '2026-07-09T12:00:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-07-09T12:00:00.000Z',
        transport: 'push',
      );

      await messageRepo.saveMessage(payloadIngested);
      await messageRepo.saveMessage(
        payloadIngested.copyWith(transport: 'inbox'),
      );

      final messages = await messageRepo.getMessagesForContact('peer-alice');
      expect(messages, hasLength(1));
      expect(messages.single.id, 'payload-drain-same-id');
      expect(messages.single.text, 'payload first');
    },
  );

  // 248 — Signal light overlays. Mounting under AppTheme.lightTheme models the
  // Signal root: the sheets/popup read context.backgroundReadableColors from the
  // ConversationWired State (above the nested AmbientBackground) and now resolve
  // the warm light roles instead of the dark fallback.
  group('248 Signal light overlays', () {
    const light = BackgroundReadableColors.representativeLight;

    testWidgets(
      'Signal attachment sheet uses warm semantic roles and Cancel preserves '
      'draft',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final tempDir = Directory.systemTemp.createTempSync('conv_signal_att_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final attachment = File('${tempDir.path}/staged.jpg')
          ..writeAsStringSync('image');
        final mediaPicker = FakeMediaPicker();

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          mediaPicker: mediaPicker,
          initialText: 'unsent draft copy',
          initialAttachments: [attachment],
          themeOverride: AppTheme.lightTheme,
        );

        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Media Library'), findsOneWidget);

        // The sheet resolved the warm light roles: title text is warm charcoal,
        // not the near-white it would inherit from the dark fallback.
        final title = tester.widget<Text>(find.text('Media Library'));
        expect(title.style!.color, light.textPrimary);

        // Cancel dismisses only — draft + staged attachment survive.
        tester
            .widget<ListTile>(
              find.byKey(ConversationWired.attachSheetCancelKey),
            )
            .onTap!();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Media Library'), findsNothing);
        expect(mediaPicker.pickMultipleMediaCalls, 0);
        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(find.text('unsent draft copy'), findsOneWidget);
      },
    );

    testWidgets(
      'Signal overflow popup uses warm surface with readable semantic actions',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final contactRepo = _OverflowContactRepo();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );

        // The introduce item's label can overflow the narrow (~184px) fixed
        // popup in the short test viewport — a pre-existing, out-of-scope layout
        // quirk that does not affect the item colours under test.
        final priorOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.exceptionAsString().contains('overflowed')) return;
          priorOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = priorOnError);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          contactRepo: contactRepo,
          themeOverride: AppTheme.lightTheme,
        );
        // Let _checkHasOtherFriends resolve so the introduce (success) item shows.
        await tester.pump(const Duration(milliseconds: 400));

        await tester.tap(find.byIcon(Icons.more_vert));
        // The ambient background animates, so settle with fixed pumps.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // The popup Material is the warm raised surface, never the hardcoded
        // dark chrome.
        final materialColors = tester
            .widgetList<Material>(find.byType(Material))
            .map((m) => m.color)
            .toList();
        expect(materialColors, contains(light.surfaceRaised));
        expect(
          materialColors,
          isNot(contains(const Color.fromRGBO(18, 20, 28, 0.98))),
        );

        // Introduce = success #2F7755, block/delete = destructive #B4232F, both
        // readable (never the dark #10B981 / #EF4444 literals).
        final textColors = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.style?.color)
            .toList();
        expect(textColors, contains(const Color(0xFF2F7755)));
        expect(textColors, contains(const Color(0xFFB4232F)));
        expect(textColors, isNot(contains(const Color(0xFF10B981))));
        expect(textColors, isNot(contains(const Color(0xFFEF4444))));
      },
    );

    testWidgets(
      'Signal delete sheet uses warm roles and cancel leaves message unchanged',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'signal-delete-row',
            contactPeerId: makeContact().peerId,
            senderPeerId: makeIdentity().peerId,
            text: 'Keep this message',
            timestamp: '2026-02-09T15:30:00.000Z',
            status: 'delivered',
            isIncoming: false,
            createdAt: '2026-02-09T15:30:01.000Z',
          ),
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          themeOverride: AppTheme.lightTheme,
        );

        await tester.longPress(find.text('Keep this message'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
        await pumpUntil(
          tester,
          () => find
              .byKey(ConversationWired.deleteSheetKey)
              .evaluate()
              .isNotEmpty,
        );

        // Warm light sheet chrome + readable prompt (not the dark literals).
        final sheet = tester.widget<Container>(
          find.byKey(ConversationWired.deleteSheetKey),
        );
        final deco = sheet.decoration! as BoxDecoration;
        expect(deco.color, light.surfaceRaised);
        expect((deco.border! as Border).top.color, light.surfaceBorder);
        final prompt = tester.widget<Text>(
          find.byKey(ConversationWired.deletePromptKey),
        );
        expect(prompt.style!.color, light.textPrimary);

        // Cancel dismisses only — the message survives, undeleted.
        tester
            .widget<InkWell>(
              find.descendant(
                of: find.byKey(ConversationWired.deleteCancelKey),
                matching: find.byType(InkWell),
              ),
            )
            .onTap!();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byKey(ConversationWired.deleteSheetKey), findsNothing);
        expect(find.text('Keep this message'), findsOneWidget);
        expect(messageRepo.store['signal-delete-row']?.isDeleted, isFalse);
      },
    );
  });

  group('229 mounted media recovery obeys direct auto download policy', () {
    ConversationMessage makeIncoming(String id, int secondsOffset) {
      final ts = DateTime.utc(
        2026,
        2,
        11,
        10,
        0,
        secondsOffset,
      ).toIso8601String();
      return ConversationMessage(
        id: id,
        contactPeerId: makeContact().peerId,
        senderPeerId: makeContact().peerId,
        text: 'letter $id',
        timestamp: ts,
        status: 'delivered',
        isIncoming: true,
        createdAt: ts,
      );
    }

    MediaAttachment makeRecoveryAttachment(
      String id,
      String messageId, {
      String status = 'pending',
    }) {
      return MediaAttachment(
        id: id,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 10,
        mediaType: 'image',
        downloadStatus: status,
        downloadRetryCount: 0,
        createdAt: '2026-02-11T10:00:00.000Z',
      );
    }

    /// Seeds 51 incoming messages so the initial page (50) leaves msg 0 for
    /// the older-page trigger. Eligible rows: a pending attachment on the
    /// newest message, a retryable-failed attachment on the oldest (older
    /// page), plus an evicted attachment that must never transfer.
    (FakeMessageRepository, FakeMediaAttachmentRepository)
    seedRecoveryFixture() {
      final messageRepo = FakeMessageRepository();
      final mediaRepo = FakeMediaAttachmentRepository();
      for (var i = 0; i <= 50; i++) {
        final message = makeIncoming('msg-229-$i', i);
        messageRepo.store[message.id] = message;
      }
      mediaRepo.seed([
        makeRecoveryAttachment('att-229-new', 'msg-229-50'),
        makeRecoveryAttachment('att-229-old', 'msg-229-0', status: 'failed'),
        makeRecoveryAttachment(
          'att-229-evicted',
          'msg-229-49',
          status: kMediaDownloadStatusEvicted,
        ),
      ]);
      return (messageRepo, mediaRepo);
    }

    Future<void> driveAllRecoveryTriggers(WidgetTester tester) async {
      // Mount recovery already ran in pumpScreen. Staged-drain reload: the
      // test binding starts detached; resuming fires the drain + reload.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      // Older-page load: any scroll near the load edge of the reversed list.
      await tester.drag(find.byType(ListView).first, const Offset(0, 80));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets(
      'denied policy makes zero transfers across mount, drain reload and '
      'older page',
      (tester) async {
        final (messageRepo, mediaRepo) = seedRecoveryFixture();
        final downloadCalls = <(String, MediaOwnerLane)>[];
        Future<MediaAttachment?> recordingDownload({
          required Bridge bridge,
          required MediaAttachmentRepository mediaAttachmentRepo,
          required MediaFileManager mediaFileManager,
          required MediaAttachment attachment,
          required String contactPeerId,
          required MediaOwnerLane owner,
          MessageRepository? messageRepo,
          MediaDownloadIntent? intent,
        }) async {
          downloadCalls.add((attachment.id, owner));
          return attachment;
        }

        final denying = RecordingMediaAutoDownloadDecider(allow: false);
        await pumpScreen(
          tester,
          identityRepo: FakeIdentityRepository(makeIdentity()),
          messageRepo: messageRepo,
          chatListener: ChatMessageListener(
            chatMessageStream: const Stream.empty(),
            messageRepo: messageRepo,
            contactRepo: FakeContactRepository(),
          ),
          sendFn: _instantSuccessSendFn,
          bridge: FakeBridge(),
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: FakeMediaFileManager(),
          downloadMediaFn: recordingDownload,
          autoDownloadDecider: denying,
        );

        await driveAllRecoveryTriggers(tester);

        expect(
          downloadCalls,
          isEmpty,
          reason:
              'a denied policy must produce zero transfers from mount, '
              'staged-drain reload and older-page recovery',
        );
        // The policy was genuinely consulted (per eligible attachment,
        // immediately before the would-be transfer) with the direct context.
        expect(denying.requests, isNotEmpty);
        for (final request in denying.requests) {
          expect(request.conversationKind, MediaConversationKind.oneToOne);
          expect(request.storageOwner, MediaOwnerLane.direct);
          expect(request.userInitiated, isFalse);
        }
        final consultedStatuses = denying.requests
            .map((r) => r.downloadStatus)
            .toSet();
        expect(consultedStatuses.contains('pending'), isTrue);
        expect(
          consultedStatuses.contains('failed'),
          isTrue,
          reason: 'the older-page retryable row must also be policy-gated',
        );
        expect(
          consultedStatuses.contains(kMediaDownloadStatusEvicted),
          isFalse,
          reason: 'evicted rows are not recovery candidates at all',
        );
        // Rows are untouched: still pending/failed/evicted after all
        // recovery passes.
        final newRows = await mediaRepo.getAttachmentsForMessage(
          'msg-229-50',
          owner: MediaOwnerLane.direct,
        );
        expect(newRows.single.downloadStatus, 'pending');
      },
    );

    testWidgets(
      'private and unsupported parents skip visible recovery before policy or transfer',
      (tester) async {
        final messageRepo = FakeMessageRepository();
        final mediaRepo = FakeMediaAttachmentRepository();
        final protected = makeIncoming('msg-private-recovery', 0).copyWith(
          text: '',
          privateMediaPolicy: const PrivateMediaPolicy.protected(),
          privateMediaState: PrivateMediaLifecycleState.available,
        );
        final unsupported = makeIncoming('msg-unsupported-recovery', 1)
            .copyWith(
              text: '',
              privateMediaPolicy: const PrivateMediaPolicy.unsupported(
                sourceVersion: 9,
              ),
              privateMediaState: PrivateMediaLifecycleState.unsupported,
            );
        messageRepo.store[protected.id] = protected;
        messageRepo.store[unsupported.id] = unsupported;
        mediaRepo.seed([
          makeRecoveryAttachment('att-private-recovery', protected.id),
          makeRecoveryAttachment('att-unsupported-recovery', unsupported.id),
        ]);
        final downloadCalls = <String>[];
        Future<MediaAttachment?> recordingDownload({
          required Bridge bridge,
          required MediaAttachmentRepository mediaAttachmentRepo,
          required MediaFileManager mediaFileManager,
          required MediaAttachment attachment,
          required String contactPeerId,
          required MediaOwnerLane owner,
          MessageRepository? messageRepo,
          MediaDownloadIntent? intent,
        }) async {
          downloadCalls.add(attachment.id);
          return attachment;
        }

        final allowing = RecordingMediaAutoDownloadDecider();

        await pumpScreen(
          tester,
          identityRepo: FakeIdentityRepository(makeIdentity()),
          messageRepo: messageRepo,
          chatListener: ChatMessageListener(
            chatMessageStream: const Stream.empty(),
            messageRepo: messageRepo,
            contactRepo: FakeContactRepository(),
          ),
          sendFn: _instantSuccessSendFn,
          bridge: FakeBridge(),
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: FakeMediaFileManager(),
          downloadMediaFn: recordingDownload,
          autoDownloadDecider: allowing,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));

        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        final visibleProtected = screen.messages.singleWhere(
          (message) => message.id == protected.id,
        );
        expect(visibleProtected.media.single.id, 'att-private-recovery');
        expect(
          find.byKey(const ValueKey('private-media-card-visual')),
          findsOneWidget,
          reason:
              'active private hydration must retain the attachment identity '
              'needed by the guarded open placeholder',
        );
        expect(
          find.byKey(const ValueKey('private-media-unsupported')),
          findsOneWidget,
        );
        expect(downloadCalls, isEmpty);
        expect(
          allowing.requests,
          isEmpty,
          reason: 'private qualification must precede the ordinary auto policy',
        );
        for (final message in [protected, unsupported]) {
          final rows = await mediaRepo.getAttachmentsForMessage(
            message.id,
            owner: MediaOwnerLane.direct,
          );
          expect(rows.single.downloadStatus, 'pending');
        }
      },
    );

    testWidgets(
      'allowed default transfers each eligible attachment once and skips '
      'evicted',
      (tester) async {
        final (messageRepo, mediaRepo) = seedRecoveryFixture();
        final downloadCalls = <(String, MediaOwnerLane)>[];
        Future<MediaAttachment?> persistingDownload({
          required Bridge bridge,
          required MediaAttachmentRepository mediaAttachmentRepo,
          required MediaFileManager mediaFileManager,
          required MediaAttachment attachment,
          required String contactPeerId,
          required MediaOwnerLane owner,
          MessageRepository? messageRepo,
          MediaDownloadIntent? intent,
        }) async {
          downloadCalls.add((attachment.id, owner));
          final done = attachment.copyWith(downloadStatus: 'done');
          await mediaAttachmentRepo.saveAttachment(done, owner: owner);
          return done;
        }

        final allowing = RecordingMediaAutoDownloadDecider();
        await pumpScreen(
          tester,
          identityRepo: FakeIdentityRepository(makeIdentity()),
          messageRepo: messageRepo,
          chatListener: ChatMessageListener(
            chatMessageStream: const Stream.empty(),
            messageRepo: messageRepo,
            contactRepo: FakeContactRepository(),
          ),
          sendFn: _instantSuccessSendFn,
          bridge: FakeBridge(),
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: FakeMediaFileManager(),
          downloadMediaFn: persistingDownload,
          autoDownloadDecider: allowing,
        );

        await driveAllRecoveryTriggers(tester);

        final callsById = <String, int>{};
        for (final (id, owner) in downloadCalls) {
          callsById[id] = (callsById[id] ?? 0) + 1;
          expect(owner, MediaOwnerLane.direct);
        }
        expect(
          callsById['att-229-new'],
          1,
          reason: 'the pending attachment transfers exactly once',
        );
        expect(
          callsById['att-229-old'],
          1,
          reason:
              'the older-page retryable attachment transfers exactly '
              'once',
        );
        expect(
          callsById.containsKey('att-229-evicted'),
          isFalse,
          reason: 'an evicted local copy must never auto-recover',
        );
        expect(allowing.requests, isNotEmpty);
      },
    );

    testWidgets('direct evicted media retries only after visible action', (
      tester,
    ) async {
      final messageRepo = FakeMessageRepository();
      final mediaRepo = FakeMediaAttachmentRepository();
      final message = makeIncoming('msg-evicted-ui', 0);
      messageRepo.store[message.id] = message;
      mediaRepo.seed([
        makeRecoveryAttachment(
          'att-evicted-ui',
          'msg-evicted-ui',
          status: kMediaDownloadStatusEvicted,
        ),
      ]);

      final downloadCalls = <(String, MediaOwnerLane)>[];
      Future<MediaAttachment?> recordingDownload({
        required Bridge bridge,
        required MediaAttachmentRepository mediaAttachmentRepo,
        required MediaFileManager mediaFileManager,
        required MediaAttachment attachment,
        required String contactPeerId,
        required MediaOwnerLane owner,
        MessageRepository? messageRepo,
        MediaDownloadIntent? intent,
      }) async {
        downloadCalls.add((attachment.id, owner));
        final done = attachment.copyWith(downloadStatus: 'done');
        await mediaAttachmentRepo.saveAttachment(done, owner: owner);
        return done;
      }

      // A fully-permissive policy still never auto-transfers evicted rows.
      await pumpScreen(
        tester,
        identityRepo: FakeIdentityRepository(makeIdentity()),
        messageRepo: messageRepo,
        chatListener: ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        ),
        sendFn: _instantSuccessSendFn,
        bridge: FakeBridge(),
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: FakeMediaFileManager(),
        downloadMediaFn: recordingDownload,
        autoDownloadDecider: RecordingMediaAutoDownloadDecider(),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        downloadCalls,
        isEmpty,
        reason: 'mount must make zero transfers for an evicted row',
      );

      // The truthful removed state with its explicit retry is visible.
      const retryKey = ValueKey(
        'evicted-media-retry-msg-evicted-ui-att-evicted-ui',
      );
      expect(find.text('Local copy removed'), findsOneWidget);
      expect(find.byKey(retryKey), findsOneWidget);

      await tester.tap(find.byKey(retryKey));
      await pumpUntil(tester, () => downloadCalls.isNotEmpty);

      expect(
        downloadCalls,
        hasLength(1),
        reason: 'one visible action performs exactly one retry',
      );
      expect(downloadCalls.single.$1, 'att-evicted-ui');
      expect(
        downloadCalls.single.$2,
        MediaOwnerLane.direct,
        reason: 'the explicit retry stays owner-aware',
      );
    });
  });

  // ── 233 sentinel: direct pagination window preservation ──────────────────
  group('233 direct pagination preservation', () {
    testWidgets(
      'initial fifty and older page append without resetting the window',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2160);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final messageRepo = FakeMessageRepository();
        String tsOf(int i) =>
            DateTime.utc(2026, 2, 11, 10, 0, 0, i).toIso8601String();
        for (var i = 0; i < 60; i++) {
          final ts = tsOf(i);
          messageRepo.store['msg-233-$i'] = ConversationMessage(
            id: 'msg-233-$i',
            contactPeerId: makeContact().peerId,
            senderPeerId: makeContact().peerId,
            text: 'letter $i of 233',
            timestamp: ts,
            status: 'delivered',
            isIncoming: true,
            createdAt: ts,
          );
        }

        await pumpScreen(
          tester,
          identityRepo: FakeIdentityRepository(makeIdentity()),
          messageRepo: messageRepo,
          chatListener: ChatMessageListener(
            chatMessageStream: const Stream.empty(),
            messageRepo: messageRepo,
            contactRepo: FakeContactRepository(),
          ),
          sendFn: _instantSuccessSendFn,
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Exactly one initial page at the literal 50-row window, no cursor.
        expect(messageRepo.getMessagesPageRequests, [(50, null)]);
        expect(find.textContaining('letter 59 of 233'), findsOneWidget);

        // Scrolling toward the load edge of the reversed list appends ONE
        // older page whose cursor is the current window's oldest timestamp.
        await tester.drag(find.byType(ListView).first, const Offset(0, 80));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));

        expect(messageRepo.getMessagesPageRequests, hasLength(2));
        expect(messageRepo.getMessagesPageRequests.last, (50, tsOf(10)));

        // The loaded window was appended, not replaced: the live edge is
        // still present without any third page request (no window reset).
        await tester.drag(find.byType(ListView).first, const Offset(0, -400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.textContaining('letter 59 of 233'), findsOneWidget);
        expect(messageRepo.getMessagesPageRequests, hasLength(2));
      },
    );
  });

  // ── 231: 1:1 received media core actions — wired seam ────────────────────
  group('231 direct received media actions', () {
    Directory createMediaTempDir(WidgetTester tester) {
      final tempDir = Directory.systemTemp.createTempSync('wired_media_231_');
      addTearDown(() {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });
      return tempDir;
    }

    testWidgets('viewer delete invokes existing direct whole message cleanup', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir = createMediaTempDir(tester);
      final imagePath = '${tempDir.path}/delete-me.jpg';
      File(imagePath).writeAsBytesSync(const [1, 2, 3]);

      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'media-del-msg',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeContact().peerId,
          text: 'delete my media',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:30:01.000Z',
        ),
      );
      final mediaRepo = FakeMediaAttachmentRepository();
      mediaRepo.seed([
        MediaAttachment(
          id: 'att-del',
          messageId: 'media-del-msg',
          mime: 'image/jpeg',
          size: 3,
          mediaType: 'image',
          localPath: imagePath,
          downloadStatus: 'done',
          createdAt: '2026-02-09T15:30:02.000Z',
          ownerLane: MediaOwnerLane.direct,
        ),
      ]);

      final deleteCalls = <String>[];
      Future<int> recordingDeleteForMe({
        required ConversationMessage message,
        required MessageRepository messageRepo,
        ReactionRepository? reactionRepo,
        MediaAttachmentRepository? mediaAttachmentRepo,
        MediaFileManager? mediaFileManager,
      }) async {
        deleteCalls.add(message.id);
        expect(
          identical(mediaAttachmentRepo, mediaRepo),
          isTrue,
          reason:
              'whole-message cleanup must run against the owner-aware '
              'direct attachment repository',
        );
        await messageRepo.deleteMessage(message.id);
        return 1;
      }

      final controller = ReceivedMediaActionController(
        loadParentMessage: messageRepo.getMessage,
        mediaAttachmentRepo: mediaRepo,
        egressService: _RecordingEgressService(),
        resolveStoredPath: (storedPath) => storedPath,
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        deleteForMeFn: recordingDeleteForMe,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: FakeMediaFileManager(),
        receivedMediaActionController: controller,
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(
        find.byKey(const ValueKey('media-grid-cell-media-del-msg-att-del')),
      );
      await pumpUntil(
        tester,
        () => find.byType(FullScreenTypedMediaViewer).evaluate().isNotEmpty,
      );

      await tester.tap(find.byKey(const ValueKey('media_action_delete')));
      await pumpUntil(
        tester,
        () =>
            find.byKey(ConversationWired.deleteSheetKey).evaluate().isNotEmpty,
      );

      // Viewer closed; exactly ONE local Delete-for-Me choice, labeled as
      // whole-message deletion (message + all attachments, this device).
      expect(find.byType(FullScreenTypedMediaViewer), findsNothing);
      expect(find.byKey(ConversationWired.deleteForMeKey), findsOneWidget);
      expect(find.byKey(ConversationWired.deleteForEveryoneKey), findsNothing);
      expect(
        find.text(
          'Delete this message? The message and all of its attachments '
          'will be removed from this device.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(ConversationWired.deleteForMeKey));
      await pumpUntil(tester, () => deleteCalls.isNotEmpty);

      expect(deleteCalls, ['media-del-msg']);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('delete my media'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'bubble and viewer media egress use controller with zero delivery calls',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2160);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final tempDir = createMediaTempDir(tester);
        final imagePath = '${tempDir.path}/egress.jpg';
        File(imagePath).writeAsBytesSync(const [1, 2, 3]);

        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'media-egress-msg',
            contactPeerId: makeContact().peerId,
            senderPeerId: makeContact().peerId,
            text: 'egress row',
            timestamp: '2026-02-09T15:30:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-02-09T15:30:01.000Z',
          ),
        );
        final mediaRepo = FakeMediaAttachmentRepository();
        mediaRepo.seed([
          MediaAttachment(
            id: 'att-egress',
            messageId: 'media-egress-msg',
            mime: 'image/jpeg',
            size: 3,
            mediaType: 'image',
            localPath: imagePath,
            downloadStatus: 'done',
            createdAt: '2026-02-09T15:30:02.000Z',
            ownerLane: MediaOwnerLane.direct,
          ),
        ]);

        final egressService = _RecordingEgressService();
        final controller = ReceivedMediaActionController(
          loadParentMessage: messageRepo.getMessage,
          mediaAttachmentRepo: mediaRepo,
          egressService: egressService,
          resolveStoredPath: (storedPath) => storedPath,
        );
        final p2pService = _ThrowingDeliveryP2PService();

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _throwingSendFn,
          deleteForEveryoneFn: _throwingDeleteForEveryoneFn,
          p2pService: p2pService,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: FakeMediaFileManager(),
          receivedMediaActionController: controller,
        );
        await tester.pump(const Duration(milliseconds: 300));

        const cellKey = ValueKey('media-grid-cell-media-egress-msg-att-egress');

        // Bubble → Save → Photos traverses screen → wired → controller once.
        await tester.longPress(find.byKey(cellKey));
        await pumpUntil(
          tester,
          () => find
              .byKey(MessageContextOverlay.saveActionKey)
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(find.byKey(MessageContextOverlay.saveActionKey));
        await pumpUntil(
          tester,
          () => find
              .byKey(DirectMediaSaveDestinationSheet.photosActionKey)
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(
          find.byKey(DirectMediaSaveDestinationSheet.photosActionKey),
        );
        await pumpUntil(tester, () => egressService.calls.isNotEmpty);

        expect(egressService.calls, hasLength(1));
        expect(
          egressService.calls.single.destination,
          MediaEgressDestination.photos,
        );
        expect(egressService.calls.single.selection, hasLength(1));
        expect(
          egressService.calls.single.selection.single.attachmentId,
          'att-egress',
        );
        expect(
          egressService.calls.single.selection.single.storedPath,
          imagePath,
        );
        expect(egressService.calls.single.selection.single.mime, 'image/jpeg');

        // Viewer → Share uses the SAME controller seam with exact identity.
        await tester.tap(find.byKey(cellKey));
        await pumpUntil(
          tester,
          () => find.byType(FullScreenTypedMediaViewer).evaluate().isNotEmpty,
        );
        await tester.tap(find.byKey(const ValueKey('media_action_more')));
        await pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey('media_action_share'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(find.byKey(const ValueKey('media_action_share')));
        await pumpUntil(tester, () => egressService.calls.length >= 2);

        expect(egressService.calls, hasLength(2));
        expect(
          egressService.calls.last.destination,
          MediaEgressDestination.share,
        );
        expect(
          egressService.calls.last.selection.single.attachmentId,
          'att-egress',
        );

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pump(const Duration(milliseconds: 500));

        // Stale current row: the controller's reload denies — zero further
        // egress calls and zero delivery calls (the spies would throw).
        await mediaRepo.updateDownloadStatus('att-egress', 'downloading');
        await tester.longPress(find.byKey(cellKey));
        await pumpUntil(
          tester,
          () => find
              .byKey(MessageContextOverlay.saveActionKey)
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(find.byKey(MessageContextOverlay.saveActionKey));
        await pumpUntil(
          tester,
          () => find
              .byKey(DirectMediaSaveDestinationSheet.photosActionKey)
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(
          find.byKey(DirectMediaSaveDestinationSheet.photosActionKey),
        );
        await pumpUntil(
          tester,
          () =>
              find.textContaining('no longer available').evaluate().isNotEmpty,
        );

        expect(egressService.calls, hasLength(2));
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets(
    'TC-361-03b linked runtime starts only direct blob-free event owners — '
    'the restricted conversation surface refuses media and voice authoring '
    'while the default gate keeps the incumbent full surface',
    (tester) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final recorder = FakeAudioRecorderService()..fakeDurationMs = 100;
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        audioRecorderService: recorder,
        modalityGate: const DirectConversationModalityGate.linkedBlobFree(),
      );

      // Voice authoring: the record press never starts a recording session on
      // the restricted surface.
      final micGesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_rounded)),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await tester.pump();
      expect(find.byType(RecordingOverlay), findsNothing);
      expect(recorder.startCallCount, 0);
      expect(
        find.text('Voice messages are not available on this linked device yet'),
        findsOneWidget,
      );
      await micGesture.up();
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      // Media authoring on a fresh restricted surface: the picker sheet
      // never opens; the sender-facing refusal copy shows instead.
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        audioRecorderService: recorder,
        modalityGate: const DirectConversationModalityGate.linkedBlobFree(),
      );
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Media Library'), findsNothing);
      expect(
        find.text('Media is not available on this linked device yet'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      // Contrast: the DEFAULT gate keeps the incumbent full surface — the
      // same tap opens the media sheet.
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        audioRecorderService: recorder,
      );
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Media Library'), findsOneWidget);
    },
  );
}

/// 248 — a contact repo that reports one other active friend so the overflow
/// "introduce to circle" (success) item appears.
class _OverflowContactRepo extends FakeContactRepository {
  @override
  Future<List<ContactModel>> getActiveContacts() async => [
    ContactModel(
      peerId: 'other-friend-peer',
      publicKey: 'pub',
      rendezvous: '/dns4/relay/tcp/443',
      username: 'Bob',
      signature: 'sig',
      scannedAt: '2026-01-01T00:00:00.000Z',
    ),
  ];
}

/// Convenience send function that returns success instantly.
Future<(SendChatMessageResult, ConversationMessage?)> _instantSuccessSendFn({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required String targetPeerId,
  required String text,
  required String senderPeerId,
  required String senderUsername,
  String? messageId,
  required bool preassignedMessageIdIsFresh,
  String? timestamp,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  String? quotedMessageId,
  List<MediaAttachment>? mediaAttachments,
  PrivateMediaPolicy? privateMediaPolicy,
  MediaAttachmentRepository? mediaAttachmentRepo,
  TransportMetrics? transportMetrics,
  DirectEventFanoutAuthoring? directEventFanout,
}) async {
  final delivered = ConversationMessage(
    id: messageId ?? 'msg-default',
    contactPeerId: targetPeerId,
    senderPeerId: senderPeerId,
    text: text,
    timestamp: timestamp ?? DateTime.now().toUtc().toIso8601String(),
    status: 'delivered',
    isIncoming: false,
    createdAt: timestamp ?? DateTime.now().toUtc().toIso8601String(),
    privateMediaPolicy:
        privateMediaPolicy ?? const PrivateMediaPolicy.ordinary(),
    privateMediaState:
        (privateMediaPolicy ?? const PrivateMediaPolicy.ordinary())
            .initialState,
  );
  await messageRepo.saveMessage(delivered);
  return (SendChatMessageResult.success, delivered);
}

/// 231 (TC-231-05W/09W): records every native-boundary egress call without
/// touching a platform channel.
class _RecordingEgressService extends ReceivedMediaEgressService {
  final calls =
      <
        ({
          String requestId,
          MediaEgressDestination destination,
          List<ReceivedMediaEgressCandidate> selection,
        })
      >[];

  @override
  Future<MediaEgressResult> perform({
    required String requestId,
    required MediaEgressDestination destination,
    required List<ReceivedMediaEgressCandidate> selection,
  }) async {
    calls.add((
      requestId: requestId,
      destination: destination,
      selection: selection,
    ));
    return MediaEgressResult(
      requestId: requestId,
      outcome: destination == MediaEgressDestination.share
          ? MediaEgressOutcome.presented
          : MediaEgressOutcome.saved,
      items: [
        for (final candidate in selection)
          MediaEgressItemResult(
            attachmentId: candidate.attachmentId,
            outcome: MediaEgressItemOutcome.saved,
          ),
      ],
    );
  }
}

/// 231 (TC-231-09W): delivery surfaces throw — a media action that reaches
/// any send/store seam fails the test loudly. Mount-time warm/dial from the
/// base fake stays live so the screen opens normally.
class _ThrowingDeliveryP2PService extends FakeP2PService {
  @override
  Future<bool> sendMessage(String peerId, String message) async {
    throw StateError('media action must not call sendMessage');
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    throw StateError('media action must not call sendMessageWithReply');
  }

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    throw StateError('media action must not call storeInInbox');
  }
}

/// 231 (TC-231-09W): the chat send seam must never fire for a media action.
Future<(SendChatMessageResult, ConversationMessage?)> _throwingSendFn({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required String targetPeerId,
  required String text,
  required String senderPeerId,
  required String senderUsername,
  String? messageId,
  required bool preassignedMessageIdIsFresh,
  String? timestamp,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  String? quotedMessageId,
  List<MediaAttachment>? mediaAttachments,
  PrivateMediaPolicy? privateMediaPolicy,
  MediaAttachmentRepository? mediaAttachmentRepo,
  TransportMetrics? transportMetrics,
  DirectEventFanoutAuthoring? directEventFanout,
}) async {
  throw StateError('media action must not call the chat send seam');
}

/// 231 (TC-231-09W): Delete for Everyone's encrypted delivery path must
/// never fire for a local media action.
Future<(SendChatMessageResult, ConversationMessage?)>
_throwingDeleteForEveryoneFn({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required ConversationMessage originalMessage,
  ReactionRepository? reactionRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  bool emitTimingEvent = true,
  DirectEventFanoutAuthoring? directEventFanout,
}) async {
  throw StateError('media action must not call delete-for-everyone delivery');
}
