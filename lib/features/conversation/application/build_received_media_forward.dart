import 'dart:io';

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:uuid/uuid.dart';

enum DirectMediaForwardDenial {
  parentDeleted,
  parentNotIncoming,
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

typedef ForwardOperationTokenFactory = String Function();

String _defaultForwardOperationToken() => const Uuid().v4();
bool _defaultForwardFileExists(String path) => File(path).existsSync();

/// Builds a picker-ready draft from freshly loaded direct-owned media rows.
/// No source identity or source dedup key crosses this boundary.
class BuildReceivedMediaForward {
  BuildReceivedMediaForward({
    required MediaAttachmentRepository mediaAttachmentRepository,
    ForwardOperationTokenFactory operationTokenFactory =
        _defaultForwardOperationToken,
    String Function(String storedPath) resolveStoredPath =
        MediaFileManager.resolveStoredPathSync,
    bool Function(String resolvedPath) fileExists = _defaultForwardFileExists,
  }) : _mediaAttachmentRepository = mediaAttachmentRepository,
       _operationTokenFactory = operationTokenFactory,
       _resolveStoredPath = resolveStoredPath,
       _fileExists = fileExists;

  final MediaAttachmentRepository _mediaAttachmentRepository;
  final ForwardOperationTokenFactory _operationTokenFactory;
  final String Function(String storedPath) _resolveStoredPath;
  final bool Function(String resolvedPath) _fileExists;

  Future<ReceivedMediaForwardBuildResult> build({
    required ConversationMessage parent,
    String? currentAttachmentId,
  }) async {
    if (parent.isDeleted) {
      return const ReceivedMediaForwardBuildResult.denied(
        DirectMediaForwardDenial.parentDeleted,
      );
    }
    if (!parent.isIncoming) {
      return const ReceivedMediaForwardBuildResult.denied(
        DirectMediaForwardDenial.parentNotIncoming,
      );
    }

    final rows = await _mediaAttachmentRepository.getAttachmentsForMessage(
      parent.id,
      owner: MediaOwnerLane.direct,
    );
    final eligible = rows.where(_isEligible).toList(growable: false);
    final selected = currentAttachmentId == null
        ? eligible
        : eligible
              .where((row) => row.id == currentAttachmentId)
              .toList(growable: false);
    if (selected.isEmpty) {
      return ReceivedMediaForwardBuildResult.denied(
        currentAttachmentId == null
            ? DirectMediaForwardDenial.noEligibleVisualMedia
            : DirectMediaForwardDenial.currentAttachmentNotEligible,
      );
    }

    final token = _operationTokenFactory().trim();
    if (token.isEmpty) {
      return const ReceivedMediaForwardBuildResult.denied(
        DirectMediaForwardDenial.noEligibleVisualMedia,
      );
    }
    final paths = selected
        .map((row) => _resolveStoredPath(row.localPath!))
        .toList(growable: false);
    return ReceivedMediaForwardBuildResult.ready(
      ReceivedMediaForwardDraft(
        shareIntent: ShareIntent(
          type: parent.text.isEmpty
              ? ShareIntentType.files
              : ShareIntentType.mixed,
          text: parent.text,
          filePaths: paths,
          forwardProvenance: ForwardProvenance(operationDedupKey: token),
        ),
      ),
    );
  }

  bool _isEligible(MediaAttachment row) {
    if (row.ownerLane != MediaOwnerLane.direct) return false;
    if (row.mediaType != 'image' && row.mediaType != 'video') return false;
    if (row.downloadStatus != 'done') return false;
    final path = row.localPath;
    if (path == null || path.isEmpty) return false;
    return _fileExists(_resolveStoredPath(path));
  }
}
