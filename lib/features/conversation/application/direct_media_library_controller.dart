import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';

import '../domain/models/media_library.dart';
import '../domain/repositories/media_attachment_repository.dart';

/// 233: the literal page size every direct shared-media-library request uses.
/// Valid under the shared plan-228 `1..kMediaLibraryMaxPageSize` ceiling.
const int kDirectMediaLibraryPageSize = 50;

/// 233: the selection ceiling for batch Save/Share/Delete. A UI-domain alias
/// of the native egress ceiling so the two can never drift apart silently.
const int kMaxDirectMediaSelection = kMaxMediaEgressItems;

/// The four user-facing library filters, each mapping to one complete
/// plan-228 [MediaLibraryFilter] signature.
enum DirectMediaLibraryFilter { all, photos, videos, bookmarked }

extension DirectMediaLibraryFilterSignature on DirectMediaLibraryFilter {
  MediaLibraryFilter get signature => switch (this) {
    DirectMediaLibraryFilter.all => const MediaLibraryFilter(),
    DirectMediaLibraryFilter.photos => const MediaLibraryFilter(
      kind: MediaLibraryKind.image,
    ),
    DirectMediaLibraryFilter.videos => const MediaLibraryFilter(
      kind: MediaLibraryKind.video,
    ),
    DirectMediaLibraryFilter.bookmarked => const MediaLibraryFilter(
      bookmarkedOnly: true,
    ),
  };
}

/// Paging/filter/selection/bookmark state for ONE direct conversation's
/// shared media library.
///
/// Owns the only [MediaLibraryScope] this surface may query: a strict
/// `MediaLibraryScope.direct(contactPeerId)` built in the constructor —
/// callers cannot inject a sibling (group/announcement) scope. Cursors are
/// opaque and bound to the exact filter that minted them: a filter change
/// bumps the request generation, discards the old cursor/result, and any
/// late response from a superseded generation is dropped. Rows that are not
/// direct-owned fail closed — they never render, select, or bookmark.
class DirectMediaLibraryController extends ChangeNotifier {
  DirectMediaLibraryController({
    required MediaLibraryRepository libraryRepository,
    required MediaLibraryStateRepository stateRepository,
    required String contactPeerId,
  }) : _libraryRepository = libraryRepository,
       _stateRepository = stateRepository,
       _scope = MediaLibraryScope.direct(contactPeerId);

  final MediaLibraryRepository _libraryRepository;
  final MediaLibraryStateRepository _stateRepository;
  final MediaLibraryScope _scope;

  DirectMediaLibraryFilter _filter = DirectMediaLibraryFilter.all;
  final List<MediaLibraryEntry> _entries = [];
  final Set<String> _entryIds = {};
  String? _nextCursor;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadFailed = false;
  int _generation = 0;

  /// Selected attachment IDs (insertion order), capped at
  /// [kMaxDirectMediaSelection]. Selection survives filter changes — it is
  /// identity-based, not view-based.
  final Set<String> _selectedIds = <String>{};

  /// The owning direct message of every id ever selected from a loaded page,
  /// so batch actions can re-qualify `(messageId, attachmentId)` identities.
  final Map<String, String> _messageIdByAttachmentId = {};

  DirectMediaLibraryFilter get filter => _filter;
  List<MediaLibraryEntry> get entries => List.unmodifiable(_entries);
  bool get isLoading => _loading;
  bool get loadFailed => _loadFailed;
  bool get hasMore => _hasMore;
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  int get selectedCount => _selectedIds.length;
  bool get hasSelection => _selectedIds.isNotEmpty;

  bool isSelected(String attachmentId) => _selectedIds.contains(attachmentId);

  /// The parent direct message ID of a loaded (or previously loaded and
  /// selected) attachment — provenance is always a scoped page, never a
  /// caller-supplied value.
  String? messageIdOf(String attachmentId) =>
      _messageIdByAttachmentId[attachmentId];

  /// Loads the next page of the CURRENT filter through the scope-bound
  /// cursor. In-flight fenced: concurrent calls coalesce into one request.
  /// A response whose generation was superseded by a filter change is
  /// discarded without touching state.
  Future<void> loadNextPage() async {
    if (_loading || !_hasMore) return;
    _loading = true;
    _loadFailed = false;
    notifyListeners();
    final generation = _generation;
    try {
      final page = await _libraryRepository.getMediaLibraryPage(
        scope: _scope,
        filter: _filter.signature,
        limit: kDirectMediaLibraryPageSize,
        cursor: _nextCursor,
      );
      if (generation != _generation) return;
      for (final entry in page.entries) {
        // Fail closed: only direct-owned rows may cross this boundary. A
        // same-ID group sibling or unresolved legacy row is dropped here —
        // it never renders, selects, or reaches a mutation.
        if (entry.attachment.ownerLane != MediaOwnerLane.direct) continue;
        if (_entryIds.add(entry.attachment.id)) {
          _entries.add(entry);
          _messageIdByAttachmentId[entry.attachment.id] =
              entry.attachment.messageId;
        }
      }
      _nextCursor = page.nextCursor;
      _hasMore = page.nextCursor != null;
    } catch (_) {
      if (generation == _generation) _loadFailed = true;
    } finally {
      if (generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Switches the active filter: bumps the generation (fencing any in-flight
  /// response), discards the old cursor and entries, and loads the first
  /// page under the new complete filter signature. Selection is preserved.
  Future<void> setFilter(DirectMediaLibraryFilter filter) async {
    if (filter == _filter) return;
    _filter = filter;
    _generation++;
    _entries.clear();
    _entryIds.clear();
    _nextCursor = null;
    _hasMore = true;
    _loading = false;
    _loadFailed = false;
    notifyListeners();
    await loadNextPage();
  }

  /// Toggles selection for an attachment that is on a loaded scoped page.
  /// Returns false (refusing the toggle) for unknown IDs and for the
  /// selection that would exceed [kMaxDirectMediaSelection].
  bool toggleSelection(String attachmentId) {
    if (!_entryIds.contains(attachmentId)) return false;
    if (_selectedIds.remove(attachmentId)) {
      notifyListeners();
      return true;
    }
    if (_selectedIds.length >= kMaxDirectMediaSelection) return false;
    _selectedIds.add(attachmentId);
    notifyListeners();
    return true;
  }

  void clearSelection() {
    if (_selectedIds.isEmpty) return;
    _selectedIds.clear();
    notifyListeners();
  }

  /// Drops [attachmentIds] from the selection (batch success reconcile —
  /// failed items stay selected for truthful retry).
  void unselect(Iterable<String> attachmentIds) {
    var changed = false;
    for (final id in attachmentIds) {
      changed = _selectedIds.remove(id) || changed;
    }
    if (changed) notifyListeners();
  }

  /// Toggles the durable bookmark flag through the plan-228 ID-based state
  /// API — but ONLY for an attachment obtained from the current
  /// direct-scoped pages. Unknown IDs and non-direct rows fail closed with
  /// zero writes. Under the Bookmarked filter an un-bookmarked entry leaves
  /// the visible list without disturbing unrelated selection.
  Future<bool> toggleBookmark(String attachmentId) async {
    final index = _entries.indexWhere((e) => e.attachment.id == attachmentId);
    if (index < 0) return false;
    final entry = _entries[index];
    if (entry.attachment.ownerLane != MediaOwnerLane.direct) return false;
    final next = !entry.attachment.isBookmarked;
    await _stateRepository.setBookmarked(attachmentId, bookmarked: next);
    final reconciled = MediaLibraryEntry(
      attachment: entry.attachment.copyWith(isBookmarked: next),
      parentTimestamp: entry.parentTimestamp,
      parentSenderPeerId: entry.parentSenderPeerId,
    );
    if (_filter == DirectMediaLibraryFilter.bookmarked && !next) {
      _entries.removeAt(index);
      _entryIds.remove(attachmentId);
    } else {
      _entries[index] = reconciled;
    }
    notifyListeners();
    return true;
  }

  /// Removes every loaded entry owned by [messageId] (post-delete
  /// reconcile) and drops those attachments from the selection.
  void removeEntriesForMessage(String messageId) {
    final removedIds = <String>[];
    _entries.removeWhere((entry) {
      if (entry.attachment.messageId != messageId) return false;
      removedIds.add(entry.attachment.id);
      return true;
    });
    if (removedIds.isEmpty) return;
    for (final id in removedIds) {
      _entryIds.remove(id);
      _selectedIds.remove(id);
    }
    notifyListeners();
  }
}
