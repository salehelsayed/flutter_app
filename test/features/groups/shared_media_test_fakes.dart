import 'dart:async';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

const validGroupMediaHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

class GroupMediaPageRequest {
  const GroupMediaPageRequest({
    required this.scope,
    required this.filter,
    required this.limit,
    required this.cursor,
  });

  final MediaLibraryScope scope;
  final MediaLibraryFilter filter;
  final int limit;
  final String? cursor;
}

class StrictGroupMediaLibraryRepository
    implements MediaLibraryRepository, MediaLibraryStateRepository {
  StrictGroupMediaLibraryRepository({
    required this.expectedGroupId,
    Iterable<MediaLibraryEntry> entries = const [],
  }) : _entries = entries.toList();

  final String expectedGroupId;
  List<MediaLibraryEntry> _entries;
  final List<GroupMediaPageRequest> requests = [];
  final List<(String, bool)> bookmarkWrites = [];
  Completer<void>? nextRequestGate;

  void replaceEntries(Iterable<MediaLibraryEntry> entries) {
    _entries = entries.toList();
  }

  @override
  Future<MediaLibraryPage> getMediaLibraryPage({
    required MediaLibraryScope scope,
    MediaLibraryFilter filter = const MediaLibraryFilter(),
    int limit = 50,
    String? cursor,
  }) async {
    if (scope != MediaLibraryScope.group(expectedGroupId)) {
      throw ArgumentError('wrong group scope');
    }
    if (limit < 1 || limit > kMediaLibraryMaxPageSize) {
      throw ArgumentError('invalid limit');
    }
    requests.add(
      GroupMediaPageRequest(
        scope: scope,
        filter: filter,
        limit: limit,
        cursor: cursor,
      ),
    );
    final gate = nextRequestGate;
    nextRequestGate = null;
    if (gate != null) await gate.future;

    final signature =
        '${filter.kind.name}:${filter.bookmarkedOnly ? 'b' : 'a'}:'
        '${filter.incomingOnly ? 'i' : 'x'}';
    var offset = 0;
    if (cursor != null) {
      final parts = cursor.split('|');
      if (parts.length != 3 ||
          parts[0] != expectedGroupId ||
          parts[1] != signature) {
        throw ArgumentError('cursor signature mismatch');
      }
      offset = int.parse(parts[2]);
    }
    final filtered = _entries.where((entry) {
      final attachment = entry.attachment;
      if (filter.bookmarkedOnly && !attachment.isBookmarked) return false;
      return filter.kind.mediaTypes.contains(attachment.mediaType);
    }).toList();
    final page = filtered.skip(offset).take(limit).toList();
    final nextOffset = offset + page.length;
    return MediaLibraryPage(
      entries: page,
      nextCursor: nextOffset < filtered.length
          ? '$expectedGroupId|$signature|$nextOffset'
          : null,
    );
  }

  @override
  Future<void> setBookmarked(String id, {required bool bookmarked}) async {
    bookmarkWrites.add((id, bookmarked));
    _entries = [
      for (final entry in _entries)
        if (entry.attachment.id == id)
          MediaLibraryEntry(
            attachment: entry.attachment.copyWith(isBookmarked: bookmarked),
            parentTimestamp: entry.parentTimestamp,
            parentSenderPeerId: entry.parentSenderPeerId,
          )
        else
          entry,
    ];
  }

  @override
  Future<void> updatePlaybackPosition(String id, int positionMs) async {}
}

MediaLibraryEntry groupMediaEntry(
  String id, {
  String? messageId,
  String mediaType = 'image',
  String? mime,
  String downloadStatus = 'evicted',
  String? localPath,
  bool bookmarked = false,
  MediaOwnerLane? ownerLane = MediaOwnerLane.group,
  String? contentHash = validGroupMediaHash,
  String? parentTimestamp,
}) {
  return MediaLibraryEntry(
    attachment: MediaAttachment(
      id: id,
      messageId: messageId ?? 'message-$id',
      mime: mime ?? (mediaType == 'video' ? 'video/mp4' : 'image/jpeg'),
      size: 128,
      mediaType: mediaType,
      localPath: localPath,
      downloadStatus: downloadStatus,
      createdAt: '2026-07-10T10:00:00.000Z',
      isBookmarked: bookmarked,
      ownerLane: ownerLane,
      contentHash: contentHash,
      encryptionKeyBase64: 'a2V5',
      encryptionNonce: 'bm9uY2U=',
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    ),
    parentTimestamp: parentTimestamp ?? '2026-07-10T10:00:00.000Z',
    parentSenderPeerId: 'peer-sender',
  );
}
