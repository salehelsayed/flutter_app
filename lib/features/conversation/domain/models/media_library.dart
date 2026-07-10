import 'package:flutter_app/core/media/media_owner_lane.dart';

import 'media_attachment.dart';

/// Hard ceiling for one shared-media-library page (228). Valid request
/// limits are `1..kMediaLibraryMaxPageSize`; anything else fails with an
/// [ArgumentError] before any SQL runs.
const int kMediaLibraryMaxPageSize = 100;

/// Which visual media kinds a library page includes.
enum MediaLibraryKind { image, video, visual }

extension MediaLibraryKindTypes on MediaLibraryKind {
  List<String> get mediaTypes => switch (this) {
    MediaLibraryKind.image => const ['image'],
    MediaLibraryKind.video => const ['video'],
    MediaLibraryKind.visual => const ['image', 'video'],
  };
}

/// Filter signature for a library page. Part of the opaque cursor's identity:
/// a cursor minted under one filter cannot be replayed under another.
class MediaLibraryFilter {
  const MediaLibraryFilter({
    this.kind = MediaLibraryKind.visual,
    this.bookmarkedOnly = false,
  });

  final MediaLibraryKind kind;
  final bool bookmarkedOnly;

  @override
  bool operator ==(Object other) =>
      other is MediaLibraryFilter &&
      other.kind == kind &&
      other.bookmarkedOnly == bookmarkedOnly;

  @override
  int get hashCode => Object.hash(kind, bookmarkedOnly);
}

/// A shared-media-library scope: one direct conversation or one group.
/// Announcement surfaces use [MediaLibraryScope.group] (their parents are
/// group messages).
class MediaLibraryScope {
  const MediaLibraryScope.direct(this.id) : lane = MediaOwnerLane.direct;

  const MediaLibraryScope.group(this.id) : lane = MediaOwnerLane.group;

  /// The owner lane this scope reads. Never unresolved.
  final MediaOwnerLane lane;

  /// `contactPeerId` for direct scopes, `groupId` for group scopes.
  final String id;

  @override
  bool operator ==(Object other) =>
      other is MediaLibraryScope && other.lane == lane && other.id == id;

  @override
  int get hashCode => Object.hash(lane, id);
}

/// One library row: the hydrated attachment plus aliased parent metadata.
class MediaLibraryEntry {
  const MediaLibraryEntry({
    required this.attachment,
    required this.parentTimestamp,
    this.parentSenderPeerId,
  });

  final MediaAttachment attachment;

  /// The parent message's wire timestamp (page ordering key).
  final String parentTimestamp;

  /// The parent message's sender, when the scope's parent table records one.
  final String? parentSenderPeerId;
}

/// One stable newest-first page. [nextCursor] is opaque; passing it back with
/// the SAME scope and filter yields the next page, anything else throws.
class MediaLibraryPage {
  const MediaLibraryPage({required this.entries, required this.nextCursor});

  final List<MediaLibraryEntry> entries;
  final String? nextCursor;
}
