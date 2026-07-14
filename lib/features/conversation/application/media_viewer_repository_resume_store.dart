import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/shared/widgets/media/media_video_resume_controller.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';

/// Repository composition for the shared viewer/PiP playback checkpoint seam.
///
/// Every operation reloads the exact owner/message/attachment tuple and
/// permits video rows only. Parent privacy/direction authority remains the
/// route's separate PiP authorization loader; this adapter never upgrades a
/// stale path or caller snapshot into media authority.
class MediaViewerRepositoryResumeStore implements MediaViewerResumeStore {
  const MediaViewerRepositoryResumeStore({
    required MediaAttachmentRepository attachmentRepository,
    required MediaLibraryStateRepository stateRepository,
  }) : _attachmentRepository = attachmentRepository,
       _stateRepository = stateRepository;

  final MediaAttachmentRepository _attachmentRepository;
  final MediaLibraryStateRepository _stateRepository;

  @override
  Future<int?> readResumePosition(MediaViewerItem item) async {
    final current = await _reloadVideo(item);
    return current?.lastPlaybackPositionMs;
  }

  @override
  Future<void> writeResumePosition(MediaViewerItem item, int positionMs) async {
    final current = await _reloadVideo(item);
    if (current == null) return;
    await _stateRepository.updatePlaybackPosition(
      current.id,
      positionMs < 0 ? 0 : positionMs,
    );
  }

  Future<MediaAttachment?> _reloadVideo(MediaViewerItem item) async {
    final owner = item.owner;
    if (owner == null || !item.isVideo || item.messageId.trim().isEmpty) {
      return null;
    }
    final rows = await _attachmentRepository.getAttachmentsForMessage(
      item.messageId,
      owner: owner,
    );
    for (final row in rows) {
      if (row.id == item.attachmentId &&
          row.messageId == item.messageId &&
          row.ownerLane == owner &&
          row.mediaType == 'video') {
        return row;
      }
    }
    return null;
  }
}
