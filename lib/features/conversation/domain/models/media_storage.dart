import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

/// 229: media-type addressing for the owner-scoped all-media STORAGE query.
/// Distinct from the visual `MediaLibraryKind` (image/video/visual) — storage
/// management must see every type that can occupy local bytes.
enum MediaStorageKind { image, video, audio, file, all }

extension MediaStorageKindTypes on MediaStorageKind {
  List<String> get mediaTypes => switch (this) {
        MediaStorageKind.image => const ['image'],
        MediaStorageKind.video => const ['video'],
        MediaStorageKind.audio => const ['audio'],
        MediaStorageKind.file => const ['file'],
        MediaStorageKind.all => const ['image', 'video', 'audio', 'file'],
      };
}

/// One attachment row surfaced by the storage query (a row with a stored
/// local path under a visible parent). Whether its bytes actually exist —
/// and therefore count toward totals — is decided by the storage manager
/// against the real filesystem, never by the descriptor.
class MediaStorageEntry {
  const MediaStorageEntry({
    required this.attachment,
    required this.parentTimestamp,
  });

  final MediaAttachment attachment;
  final String parentTimestamp;
}

/// One page of the owner-scoped all-media storage query. [nextCursor] is
/// opaque, bound to the exact scope/kind signature that minted it, and null
/// on the final page.
class MediaStoragePage {
  const MediaStoragePage({required this.entries, this.nextCursor});

  final List<MediaStorageEntry> entries;
  final String? nextCursor;
}

/// Exact measured totals for one media type within one scope: only canonical
/// files that exist on disk contribute, at their true on-disk length.
class MediaStorageTypeTotal {
  const MediaStorageTypeTotal({this.count = 0, this.bytes = 0});

  final int count;
  final int bytes;

  MediaStorageTypeTotal add(int fileBytes) =>
      MediaStorageTypeTotal(count: count + 1, bytes: bytes + fileBytes);
}

/// Exact aggregate storage usage of one scope across ALL pages of the
/// storage query (user-invoked; never a startup/timer filesystem scan).
class MediaStorageInventory {
  const MediaStorageInventory({required this.byType});

  final Map<String, MediaStorageTypeTotal> byType;

  int get totalCount =>
      byType.values.fold(0, (sum, total) => sum + total.count);

  int get totalBytes =>
      byType.values.fold(0, (sum, total) => sum + total.bytes);

  MediaStorageTypeTotal totalFor(String mediaType) =>
      byType[mediaType] ?? const MediaStorageTypeTotal();
}
