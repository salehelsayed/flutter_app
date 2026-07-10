import 'dart:async';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/application/direct_media_library_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

import 'fake_media_attachment_repository.dart';

/// Strict plan-228 library contract fake (233): any request that is not the
/// exact direct contact scope, complete filter signature, literal limit 50,
/// and a cursor THIS repository minted under the SAME filter throws before
/// returning data — a permissive fake would hide every scope/cursor bug.
class StrictDirectMediaLibraryRepository extends FakeMediaAttachmentRepository
    implements MediaLibraryRepository, MediaLibraryStateRepository {
  StrictDirectMediaLibraryRepository({required this.expectedContactPeerId});

  final String expectedContactPeerId;

  final Map<String, MediaLibraryPage> _pages = {};
  final Map<String, MediaLibraryFilter> _mintedCursors = {};

  final List<
    ({
      MediaLibraryScope scope,
      MediaLibraryFilter filter,
      int limit,
      String? cursor,
    })
  >
  pageCalls = [];
  final List<({String id, bool bookmarked})> bookmarkCalls = [];

  /// When set, every page request parks on its own completer so tests can
  /// interleave stale/late responses deterministically.
  bool gateRequests = false;
  final List<Completer<void>> gates = [];

  static String filterSignature(MediaLibraryFilter filter) =>
      '${filter.kind.name}:${filter.bookmarkedOnly}';

  String _pageKey(MediaLibraryFilter filter, String? cursor) =>
      '${filterSignature(filter)}|${cursor ?? ''}';

  void seedPage({
    MediaLibraryFilter filter = const MediaLibraryFilter(),
    String? cursor,
    required List<MediaLibraryEntry> entries,
    String? nextCursor,
  }) {
    _pages[_pageKey(filter, cursor)] = MediaLibraryPage(
      entries: entries,
      nextCursor: nextCursor,
    );
    if (nextCursor != null) _mintedCursors[nextCursor] = filter;
  }

  @override
  Future<MediaLibraryPage> getMediaLibraryPage({
    required MediaLibraryScope scope,
    MediaLibraryFilter filter = const MediaLibraryFilter(),
    int limit = 50,
    String? cursor,
  }) async {
    if (scope.lane != MediaOwnerLane.direct) {
      throw StateError('non-direct library scope: ${scope.lane.dbValue}');
    }
    if (scope.id != expectedContactPeerId) {
      throw StateError('wrong contact scope: ${scope.id}');
    }
    if (limit != kDirectMediaLibraryPageSize) {
      throw StateError('non-literal page limit: $limit');
    }
    if (cursor != null) {
      final minted = _mintedCursors[cursor];
      if (minted == null) {
        throw StateError('fabricated or foreign cursor: $cursor');
      }
      if (minted != filter) {
        throw StateError('cursor replayed across filter signatures: $cursor');
      }
    }
    pageCalls.add((scope: scope, filter: filter, limit: limit, cursor: cursor));
    if (gateRequests) {
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
    }
    return _pages[_pageKey(filter, cursor)] ??
        const MediaLibraryPage(entries: [], nextCursor: null);
  }

  @override
  Future<void> setBookmarked(String id, {required bool bookmarked}) async {
    bookmarkCalls.add((id: id, bookmarked: bookmarked));
  }

  @override
  Future<void> updatePlaybackPosition(String id, int positionMs) async {}
}

/// One direct-owned library entry with sensible defaults for widget tests.
MediaLibraryEntry makeDirectLibraryEntry(
  String attachmentId, {
  required String contactPeerId,
  String? messageId,
  String parentTimestamp = '2026-02-11T10:00:00.000Z',
  String mediaType = 'image',
  String mime = 'image/jpeg',
  String? localPath,
  String downloadStatus = 'done',
  MediaOwnerLane? ownerLane = MediaOwnerLane.direct,
  bool bookmarked = false,
}) {
  return MediaLibraryEntry(
    attachment: MediaAttachment(
      id: attachmentId,
      messageId: messageId ?? 'msg-of-$attachmentId',
      mime: mime,
      size: 3,
      mediaType: mediaType,
      localPath: localPath,
      downloadStatus: downloadStatus,
      createdAt: parentTimestamp,
      ownerLane: ownerLane,
      isBookmarked: bookmarked,
    ),
    parentTimestamp: parentTimestamp,
    parentSenderPeerId: contactPeerId,
  );
}
