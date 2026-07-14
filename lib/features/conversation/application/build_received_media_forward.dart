import 'dart:io';

import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'private_media_action_eligibility.dart';
import 'received_media_action_controller.dart';

enum DirectMediaForwardDenial {
  parentNotFound,
  parentDeleted,
  parentNotIncoming,
  privateMediaRestricted,
  policyUnavailable,
  noEligibleVisualMedia,
  currentAttachmentNotEligible,
}

class ReceivedMediaForwardDraft {
  final ShareIntent shareIntent;

  const ReceivedMediaForwardDraft({required this.shareIntent});
}

class ReceivedMediaForwardBuildResult {
  const ReceivedMediaForwardBuildResult.ready(this.draft) : denial = null;
  const ReceivedMediaForwardBuildResult.denied(this.denial) : draft = null;

  final ReceivedMediaForwardDraft? draft;
  final DirectMediaForwardDenial? denial;
}

class ReceivedMediaForwardDispatchCaptureResult {
  const ReceivedMediaForwardDispatchCaptureResult.ready(this.lease)
    : denial = null;
  const ReceivedMediaForwardDispatchCaptureResult.denied(this.denial)
    : lease = null;

  final ReceivedMediaForwardDispatchLease? lease;
  final DirectMediaForwardDenial? denial;
}

/// One dispatch-owned immutable plaintext snapshot. The ordinary batch sender
/// consumes [shareIntent] and always disposes the lease in a `finally` block.
class ReceivedMediaForwardDispatchLease {
  ReceivedMediaForwardDispatchLease._({
    required this.shareIntent,
    required MediaForwardSnapshotLease snapshotLease,
  }) : _snapshotLease = snapshotLease;

  final ShareIntent shareIntent;
  final MediaForwardSnapshotLease _snapshotLease;

  Future<void> dispose() => _snapshotLease.dispose();
}

typedef ForwardOperationTokenFactory = String Function();
typedef DirectForwardParentLoader =
    Future<ConversationMessage?> Function(String messageId);
typedef DirectForwardCanonicalPlaintextValidator =
    Future<CanonicalGroupMediaPlaintextValidationResult> Function({
      required MediaAttachment attachment,
      required String ownerScopeId,
    });
typedef DirectForwardSnapshotCopy =
    Future<void> Function({
      required String sourcePath,
      required String snapshotPath,
    });

String _defaultForwardOperationToken() => const Uuid().v4();
Future<void> _defaultDirectForwardSnapshotCopy({
  required String sourcePath,
  required String snapshotPath,
}) async {
  await File(sourcePath).copy(snapshotPath);
}

class _QualifiedDirectForwardSource {
  const _QualifiedDirectForwardSource({
    required this.parent,
    required this.attachments,
    required this.resolvedPaths,
  });

  final ConversationMessage parent;
  final List<MediaAttachment> attachments;
  final List<String> resolvedPaths;
}

class _DirectForwardQualification {
  const _DirectForwardQualification.ready(this.source) : denial = null;
  const _DirectForwardQualification.denied(this.denial) : source = null;

  final _QualifiedDirectForwardSource? source;
  final DirectMediaForwardDenial? denial;
}

/// Builds a picker-ready draft from freshly loaded direct-owned media rows.
///
/// The picker receives stable local source authority, never source paths as
/// authority. [captureForDispatch] reloads and validates the same exact rows,
/// then snapshots their bytes before ordinary share preprocessing can read.
class BuildReceivedMediaForward {
  BuildReceivedMediaForward({
    required DirectForwardParentLoader loadParentMessage,
    required MediaAttachmentRepository mediaAttachmentRepository,
    ForwardOperationTokenFactory operationTokenFactory =
        _defaultForwardOperationToken,
    MediaFileManager? mediaFileManager,
    MediaAttachmentLifecycleLock? lifecycleLock,
    DirectForwardCanonicalPlaintextValidator? validateCanonicalPlaintext,
    DirectForwardSnapshotCopy copySnapshot = _defaultDirectForwardSnapshotCopy,
    Future<void> Function()? beforeFinalSourceRecheck,
  }) : _loadParentMessage = loadParentMessage,
       _mediaAttachmentRepository = mediaAttachmentRepository,
       _operationTokenFactory = operationTokenFactory,
       _mediaFileManager = mediaFileManager ?? MediaFileManager(),
       _lifecycleLock = lifecycleLock ?? mediaAttachmentLifecycleLock,
       _validateCanonicalPlaintext = validateCanonicalPlaintext,
       _copySnapshot = copySnapshot,
       _beforeFinalSourceRecheck = beforeFinalSourceRecheck;

  final DirectForwardParentLoader _loadParentMessage;
  final MediaAttachmentRepository _mediaAttachmentRepository;
  final ForwardOperationTokenFactory _operationTokenFactory;
  final MediaFileManager _mediaFileManager;
  final MediaAttachmentLifecycleLock _lifecycleLock;
  final DirectForwardCanonicalPlaintextValidator? _validateCanonicalPlaintext;
  final DirectForwardSnapshotCopy _copySnapshot;
  final Future<void> Function()? _beforeFinalSourceRecheck;

  Future<ReceivedMediaForwardBuildResult> build({
    required ConversationMessage parent,
    String? currentAttachmentId,
  }) async {
    final initialParent = await _loadParentMessage(parent.id);
    final initialParentDenial = _parentDenial(
      initialParent,
      expectedMessageId: parent.id,
    );
    if (initialParentDenial != null) {
      return ReceivedMediaForwardBuildResult.denied(initialParentDenial);
    }
    final acceptedInitialParent = initialParent!;

    final rows = await _mediaAttachmentRepository.getAttachmentsForMessage(
      parent.id,
      owner: MediaOwnerLane.direct,
    );
    final selectedIds = <String>[];
    final seenIds = <String>{};
    for (final row in rows) {
      if (currentAttachmentId != null && row.id != currentAttachmentId) {
        continue;
      }
      if (_isPreliminarilyEligible(acceptedInitialParent, row) &&
          seenIds.add(row.id)) {
        selectedIds.add(row.id);
      }
    }
    if (selectedIds.isEmpty) {
      return ReceivedMediaForwardBuildResult.denied(
        currentAttachmentId == null
            ? DirectMediaForwardDenial.noEligibleVisualMedia
            : DirectMediaForwardDenial.currentAttachmentNotEligible,
      );
    }

    final sourceDenial = currentAttachmentId == null
        ? DirectMediaForwardDenial.noEligibleVisualMedia
        : DirectMediaForwardDenial.currentAttachmentNotEligible;
    return _withAttachmentLocks(selectedIds, () async {
      final qualification = await _qualifyExactSources(
        contactPeerId: acceptedInitialParent.contactPeerId,
        messageId: parent.id,
        attachmentIds: selectedIds,
        sourceDenial: sourceDenial,
      );
      final source = qualification.source;
      if (source == null) {
        return ReceivedMediaForwardBuildResult.denied(qualification.denial!);
      }

      String token;
      try {
        token = _operationTokenFactory().trim();
      } catch (_) {
        token = '';
      }
      if (token.isEmpty) {
        return const ReceivedMediaForwardBuildResult.denied(
          DirectMediaForwardDenial.noEligibleVisualMedia,
        );
      }
      final authority = DirectForwardSourceAuthority(
        contactPeerId: source.parent.contactPeerId,
        messageId: source.parent.id,
        attachmentIds: source.attachments.map((attachment) => attachment.id),
      );
      return ReceivedMediaForwardBuildResult.ready(
        ReceivedMediaForwardDraft(
          shareIntent: ShareIntent(
            type: source.parent.text.isEmpty
                ? ShareIntentType.files
                : ShareIntentType.mixed,
            text: source.parent.text,
            filePaths: source.resolvedPaths,
            forwardProvenance: ForwardProvenance(operationDedupKey: token),
            directForwardSourceAuthority: authority,
          ),
        ),
      );
    });
  }

  /// Dispatch-time source reload + immutable capture used by the ordinary
  /// contact/group batch coordinator. Caller paths are ignored completely.
  Future<ReceivedMediaForwardDispatchCaptureResult> captureForDispatch(
    ShareIntent pickerIntent,
  ) async {
    final authority = pickerIntent.directForwardSourceAuthority;
    final provenance = pickerIntent.forwardProvenance;
    if (authority == null ||
        provenance == null ||
        provenance.operationDedupKey.trim().isEmpty ||
        authority.contactPeerId.trim().isEmpty ||
        authority.messageId.trim().isEmpty ||
        authority.attachmentIds.isEmpty ||
        authority.attachmentIds.any((id) => id.trim().isEmpty) ||
        authority.attachmentIds.toSet().length !=
            authority.attachmentIds.length) {
      return const ReceivedMediaForwardDispatchCaptureResult.denied(
        DirectMediaForwardDenial.currentAttachmentNotEligible,
      );
    }

    return _withAttachmentLocks(authority.attachmentIds, () async {
      MediaForwardSnapshotLease? snapshotLease;
      try {
        final qualification = await _qualifyExactSources(
          contactPeerId: authority.contactPeerId,
          messageId: authority.messageId,
          attachmentIds: authority.attachmentIds,
          sourceDenial: DirectMediaForwardDenial.currentAttachmentNotEligible,
        );
        final source = qualification.source;
        if (source == null) {
          return ReceivedMediaForwardDispatchCaptureResult.denied(
            qualification.denial!,
          );
        }

        snapshotLease = await _mediaFileManager
            .createMediaForwardSnapshotLease();
        final directory = snapshotLease.directory;
        final snapshotPaths = <String>[];
        for (var index = 0; index < source.attachments.length; index++) {
          final attachment = source.attachments[index];
          final extension = MediaFilePathConvention.extensionFromMime(
            attachment.mime,
          );
          final snapshot = File(
            p.join(directory.path, 'source_$index$extension'),
          );
          await _copySnapshot(
            sourcePath: source.resolvedPaths[index],
            snapshotPath: snapshot.path,
          );
          if (await FileSystemEntity.type(snapshot.path, followLinks: false) !=
                  FileSystemEntityType.file ||
              await snapshot.length() != attachment.size) {
            await snapshotLease.dispose();
            return const ReceivedMediaForwardDispatchCaptureResult.denied(
              DirectMediaForwardDenial.currentAttachmentNotEligible,
            );
          }
          final signature = await GroupMediaMimePolicy.validateFile(
            path: snapshot.path,
            mime: attachment.mime,
            mediaType: attachment.mediaType,
          );
          if (!signature.isValid) {
            await snapshotLease.dispose();
            return const ReceivedMediaForwardDispatchCaptureResult.denied(
              DirectMediaForwardDenial.currentAttachmentNotEligible,
            );
          }
          snapshotPaths.add(snapshot.path);
        }

        // Copying is awaited. Re-run the exact row, parent, path, size, and
        // signature qualification before readable snapshot bytes leave locks.
        final finalQualification = await _qualifyExactSources(
          contactPeerId: authority.contactPeerId,
          messageId: authority.messageId,
          attachmentIds: authority.attachmentIds,
          sourceDenial: DirectMediaForwardDenial.currentAttachmentNotEligible,
          invokeTestHook: false,
        );
        final finalSource = finalQualification.source;
        if (finalSource == null ||
            !_sameQualifiedAuthority(source, finalSource)) {
          await snapshotLease.dispose();
          return ReceivedMediaForwardDispatchCaptureResult.denied(
            finalQualification.denial ??
                DirectMediaForwardDenial.currentAttachmentNotEligible,
          );
        }

        return ReceivedMediaForwardDispatchCaptureResult.ready(
          ReceivedMediaForwardDispatchLease._(
            shareIntent: pickerIntent.copyWith(
              filePaths: snapshotPaths,
              directForwardSourceAuthority: null,
            ),
            snapshotLease: snapshotLease,
          ),
        );
      } catch (_) {
        if (snapshotLease != null) {
          await snapshotLease.dispose();
        }
        return const ReceivedMediaForwardDispatchCaptureResult.denied(
          DirectMediaForwardDenial.currentAttachmentNotEligible,
        );
      }
    });
  }

  Future<_DirectForwardQualification> _qualifyExactSources({
    required String contactPeerId,
    required String messageId,
    required List<String> attachmentIds,
    required DirectMediaForwardDenial sourceDenial,
    bool invokeTestHook = true,
  }) async {
    final first = await _loadAndValidateExactSources(
      contactPeerId: contactPeerId,
      messageId: messageId,
      attachmentIds: attachmentIds,
      sourceDenial: sourceDenial,
    );
    if (first.source == null) return first;

    if (invokeTestHook) {
      try {
        await _beforeFinalSourceRecheck?.call();
      } catch (_) {
        return _DirectForwardQualification.denied(sourceDenial);
      }
    }

    final second = await _loadAndValidateExactSources(
      contactPeerId: contactPeerId,
      messageId: messageId,
      attachmentIds: attachmentIds,
      sourceDenial: sourceDenial,
    );
    if (second.source == null) return second;
    if (!_sameQualifiedAuthority(first.source!, second.source!)) {
      return _DirectForwardQualification.denied(sourceDenial);
    }
    return second;
  }

  Future<_DirectForwardQualification> _loadAndValidateExactSources({
    required String contactPeerId,
    required String messageId,
    required List<String> attachmentIds,
    required DirectMediaForwardDenial sourceDenial,
  }) async {
    final attachments = <MediaAttachment>[];
    final resolvedPaths = <String>[];
    for (final attachmentId in attachmentIds) {
      final DirectMediaCurrentRowDecision decision;
      try {
        decision = await qualifyCurrentDirectMediaRow(
          identity: DirectReceivedMediaActionIdentity(
            messageId: messageId,
            attachmentId: attachmentId,
          ),
          loadParentMessage: _loadParentMessage,
          mediaAttachmentRepo: _mediaAttachmentRepository,
          // Canonical path authority below performs the only permitted file
          // probe. The shared direct policy helper remains responsible for
          // current parent/row/private-state qualification.
          resolveStoredPath: (storedPath) => storedPath,
          fileExists: (_) => true,
        );
      } catch (_) {
        return _DirectForwardQualification.denied(sourceDenial);
      }
      if (!decision.isQualified) {
        return _DirectForwardQualification.denied(
          _mapCurrentRowDenial(decision.denial!, fallback: sourceDenial),
        );
      }
      final parent = decision.parent!;
      final attachment = decision.current!;
      if (parent.contactPeerId != contactPeerId ||
          (attachment.mediaType != 'image' &&
              attachment.mediaType != 'video')) {
        return _DirectForwardQualification.denied(sourceDenial);
      }
      final CanonicalGroupMediaPlaintextValidationResult canonical;
      try {
        canonical = await _validateCanonicalSource(
          attachment: attachment,
          ownerScopeId: contactPeerId,
        );
      } catch (_) {
        return _DirectForwardQualification.denied(sourceDenial);
      }
      if (!canonical.isValid) {
        return _DirectForwardQualification.denied(sourceDenial);
      }
      attachments.add(attachment);
      resolvedPaths.add(canonical.resolvedPath!);
    }

    final exactLookup = _mediaAttachmentRepository is MediaAttachmentByIdLookup
        ? _mediaAttachmentRepository as MediaAttachmentByIdLookup
        : null;
    if (exactLookup == null) {
      return _DirectForwardQualification.denied(sourceDenial);
    }

    // Repository row/file mutations share the sorted attachment lifecycle
    // locks held by the caller, so once this stable exact-ID read returns the
    // rows cannot drift before the outer qualification releases those locks.
    final finalRows = await Future.wait(
      attachmentIds.map(exactLookup.getAttachmentById),
    );
    final reloadedAttachments = <MediaAttachment>[];
    for (var index = 0; index < attachmentIds.length; index++) {
      final reloaded = finalRows[index];
      if (reloaded == null ||
          reloaded.id != attachmentIds[index] ||
          !_sameDirectAttachmentAuthority(attachments[index], reloaded)) {
        return _DirectForwardQualification.denied(sourceDenial);
      }
      reloadedAttachments.add(reloaded);
    }

    // TRUE final awaited authority: parents are not attachment-row mutations,
    // so they may change while the exact row read above is suspended. Reload
    // current deleted/hidden/private/terminal policy now, then compare and
    // construct synchronously with no later validator, file probe, or yield.
    final finalParent = await _loadParentMessage(messageId);
    final parentDenial = _parentDenial(
      finalParent,
      expectedMessageId: messageId,
    );
    if (parentDenial != null) {
      return _DirectForwardQualification.denied(parentDenial);
    }
    if (finalParent!.contactPeerId != contactPeerId) {
      return _DirectForwardQualification.denied(sourceDenial);
    }
    for (final attachment in reloadedAttachments) {
      if (!DirectPrivateMediaActionEligibility.evaluate(
        parent: finalParent,
        attachment: attachment,
        expectedMessageId: messageId,
        expectedAttachmentId: attachment.id,
      ).allows(DirectPrivateMediaAction.internalForward)) {
        return const _DirectForwardQualification.denied(
          DirectMediaForwardDenial.privateMediaRestricted,
        );
      }
    }
    return _DirectForwardQualification.ready(
      _QualifiedDirectForwardSource(
        parent: finalParent,
        attachments: List.unmodifiable(reloadedAttachments),
        resolvedPaths: List.unmodifiable(resolvedPaths),
      ),
    );
  }

  Future<CanonicalGroupMediaPlaintextValidationResult>
  _validateCanonicalSource({
    required MediaAttachment attachment,
    required String ownerScopeId,
  }) {
    final override = _validateCanonicalPlaintext;
    if (override != null) {
      return override(attachment: attachment, ownerScopeId: ownerScopeId);
    }
    return GroupMediaIntegrityPolicy.validateCanonicalLocalPlaintext(
      attachment: attachment,
      ownerScopeId: ownerScopeId,
      mediaFileManager: _mediaFileManager,
    );
  }

  Future<T> _withAttachmentLocks<T>(
    Iterable<String> attachmentIds,
    Future<T> Function() action,
  ) {
    final ordered = attachmentIds.toSet().toList()..sort();
    Future<T> acquire(int index) {
      if (index == ordered.length) return action();
      return _lifecycleLock.synchronized(
        ordered[index],
        () => acquire(index + 1),
      );
    }

    return acquire(0);
  }

  DirectMediaForwardDenial? _parentDenial(
    ConversationMessage? parent, {
    required String expectedMessageId,
  }) {
    if (parent == null) return DirectMediaForwardDenial.parentNotFound;
    if (parent.id != expectedMessageId) {
      return DirectMediaForwardDenial.policyUnavailable;
    }
    if (parent.isDeleted) return DirectMediaForwardDenial.parentDeleted;
    if (!parent.isIncoming) return DirectMediaForwardDenial.parentNotIncoming;
    final decision = DirectPrivateMediaActionEligibility.evaluate(
      parent: parent,
      attachment: null,
      expectedMessageId: expectedMessageId,
      attachmentRequired: false,
    );
    if (decision.allows(DirectPrivateMediaAction.internalForward)) return null;
    return decision.isPrivateOrUnsupported
        ? DirectMediaForwardDenial.privateMediaRestricted
        : DirectMediaForwardDenial.policyUnavailable;
  }

  bool _isPreliminarilyEligible(
    ConversationMessage parent,
    MediaAttachment row,
  ) {
    if (row.ownerLane != MediaOwnerLane.direct ||
        row.messageId != parent.id ||
        (row.mediaType != 'image' && row.mediaType != 'video') ||
        row.downloadStatus != kMediaDownloadStatusDone ||
        row.localPath == null ||
        row.localPath!.isEmpty) {
      return false;
    }
    return DirectPrivateMediaActionEligibility.evaluate(
      parent: parent,
      attachment: row,
      expectedMessageId: parent.id,
      expectedAttachmentId: row.id,
    ).allows(DirectPrivateMediaAction.internalForward);
  }

  DirectMediaForwardDenial _mapCurrentRowDenial(
    DirectMediaEgressDenial denial, {
    required DirectMediaForwardDenial fallback,
  }) => switch (denial) {
    DirectMediaEgressDenial.parentNotFound =>
      DirectMediaForwardDenial.parentNotFound,
    DirectMediaEgressDenial.parentDeleted =>
      DirectMediaForwardDenial.parentDeleted,
    DirectMediaEgressDenial.parentNotIncoming =>
      DirectMediaForwardDenial.parentNotIncoming,
    DirectMediaEgressDenial.expired || DirectMediaEgressDenial.protected =>
      DirectMediaForwardDenial.privateMediaRestricted,
    DirectMediaEgressDenial.policyUnavailable =>
      DirectMediaForwardDenial.policyUnavailable,
    _ => fallback,
  };

  bool _sameQualifiedAuthority(
    _QualifiedDirectForwardSource left,
    _QualifiedDirectForwardSource right,
  ) {
    if (left.parent.id != right.parent.id ||
        left.parent.contactPeerId != right.parent.contactPeerId ||
        left.parent.isDeleted != right.parent.isDeleted ||
        left.parent.isHidden != right.parent.isHidden ||
        left.parent.isIncoming != right.parent.isIncoming ||
        left.parent.privateMediaPolicy != right.parent.privateMediaPolicy ||
        left.parent.privateMediaState != right.parent.privateMediaState ||
        left.attachments.length != right.attachments.length ||
        left.resolvedPaths.length != right.resolvedPaths.length) {
      return false;
    }
    for (var index = 0; index < left.attachments.length; index++) {
      final a = left.attachments[index];
      final b = right.attachments[index];
      if (!_sameDirectAttachmentAuthority(a, b) ||
          left.resolvedPaths[index] != right.resolvedPaths[index]) {
        return false;
      }
    }
    return true;
  }

  bool _sameDirectAttachmentAuthority(
    MediaAttachment left,
    MediaAttachment right,
  ) =>
      left.id == right.id &&
      left.messageId == right.messageId &&
      left.ownerLane == right.ownerLane &&
      left.mime == right.mime &&
      left.mediaType == right.mediaType &&
      left.size == right.size &&
      left.downloadStatus == right.downloadStatus &&
      left.localPath == right.localPath &&
      left.contentHash == right.contentHash &&
      left.encryptionScheme == right.encryptionScheme &&
      left.encryptionKeyBase64 == right.encryptionKeyBase64 &&
      left.encryptionNonce == right.encryptionNonce;
}
