import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

const int kGroupSharedMediaPageSize = 50;
const int kGroupSharedMediaSelectionLimit = kMaxMediaEgressItems;

enum GroupSharedMediaFilter { all, images, videos, bookmarked }

extension GroupSharedMediaFilterSignature on GroupSharedMediaFilter {
  MediaLibraryFilter signature({bool incomingOnly = false}) => switch (this) {
    GroupSharedMediaFilter.all => MediaLibraryFilter(
      incomingOnly: incomingOnly,
    ),
    GroupSharedMediaFilter.images => MediaLibraryFilter(
      kind: MediaLibraryKind.image,
      incomingOnly: incomingOnly,
    ),
    GroupSharedMediaFilter.videos => MediaLibraryFilter(
      kind: MediaLibraryKind.video,
      incomingOnly: incomingOnly,
    ),
    GroupSharedMediaFilter.bookmarked => MediaLibraryFilter(
      bookmarkedOnly: true,
      incomingOnly: incomingOnly,
    ),
  };
}

class GroupSharedMediaIdentity {
  const GroupSharedMediaIdentity({
    required this.groupId,
    required this.messageId,
    required this.attachmentId,
  });

  final String groupId;
  final String messageId;
  final String attachmentId;

  @override
  bool operator ==(Object other) =>
      other is GroupSharedMediaIdentity &&
      other.groupId == groupId &&
      other.messageId == messageId &&
      other.attachmentId == attachmentId;

  @override
  int get hashCode => Object.hash(groupId, messageId, attachmentId);

  @override
  String toString() => 'GroupSharedMediaIdentity(redacted)';
}

/// Strict discussion-group media-library state.
///
/// The scope is constructed from [groupId] and cannot be replaced by callers.
/// Opaque cursors never survive a filter change. Returned rows are still
/// defended at the UI boundary: only resolved group-owned attachments enter
/// the visible/selection/viewer state.
class GroupSharedMediaLibraryController extends ChangeNotifier {
  GroupSharedMediaLibraryController({
    required this.groupId,
    this.incomingOnly = false,
    required MediaLibraryRepository libraryRepository,
    required MediaLibraryStateRepository stateRepository,
  }) : _libraryRepository = libraryRepository,
       _stateRepository = stateRepository,
       _scope = MediaLibraryScope.group(groupId);

  final String groupId;
  final bool incomingOnly;
  final MediaLibraryRepository _libraryRepository;
  final MediaLibraryStateRepository _stateRepository;
  final MediaLibraryScope _scope;

  GroupSharedMediaFilter _filter = GroupSharedMediaFilter.images;
  final List<MediaLibraryEntry> _entries = [];
  final Set<String> _entryIds = {};
  final Set<String> _selectedIds = {};
  final Map<String, String> _messageIdByAttachmentId = {};
  String? _nextCursor;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadFailed = false;
  int _generation = 0;
  Future<void>? _refreshFlight;

  GroupSharedMediaFilter get filter => _filter;
  List<MediaLibraryEntry> get entries => List.unmodifiable(_entries);
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  int get selectedCount => _selectedIds.length;
  bool get hasSelection => _selectedIds.isNotEmpty;
  bool get hasMore => _hasMore;
  bool get isLoading => _loading;
  bool get loadFailed => _loadFailed;

  bool isSelected(String attachmentId) => _selectedIds.contains(attachmentId);

  String? messageIdOf(String attachmentId) =>
      _messageIdByAttachmentId[attachmentId];

  MediaLibraryEntry? entryFor(String attachmentId) {
    for (final entry in _entries) {
      if (entry.attachment.id == attachmentId) return entry;
    }
    return null;
  }

  List<GroupSharedMediaIdentity> identitiesFor(Iterable<String> ids) => [
    for (final id in ids)
      if (_messageIdByAttachmentId[id] case final String messageId)
        GroupSharedMediaIdentity(
          groupId: groupId,
          messageId: messageId,
          attachmentId: id,
        ),
  ];

  Future<void> loadNextPage() async {
    if (_loading || !_hasMore) return;
    _loading = true;
    _loadFailed = false;
    notifyListeners();
    final generation = _generation;
    try {
      final page = await _libraryRepository.getMediaLibraryPage(
        scope: _scope,
        filter: _filter.signature(incomingOnly: incomingOnly),
        limit: kGroupSharedMediaPageSize,
        cursor: _nextCursor,
      );
      if (generation != _generation) return;
      _appendSafe(page.entries);
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

  Future<void> setFilter(GroupSharedMediaFilter filter) async {
    if (filter == _filter) return;
    _filter = filter;
    _resetVisibleState();
    notifyListeners();
    await loadNextPage();
  }

  /// One bounded refresh for mount/resume/action completion. It never installs
  /// a repository stream and never reads more than the shared 100-row ceiling.
  /// Existing selection survives only for identities still present.
  Future<void> refreshCurrentPage() {
    return _refreshFlight ??= _refreshCurrentPage().whenComplete(() {
      _refreshFlight = null;
    });
  }

  Future<void> _refreshCurrentPage() async {
    final generation = ++_generation;
    final limit = _entries.length
        .clamp(kGroupSharedMediaPageSize, kMediaLibraryMaxPageSize)
        .toInt();
    final preservedTail = _entries.length > limit
        ? _entries.skip(limit).toList(growable: false)
        : const <MediaLibraryEntry>[];
    _loading = true;
    _loadFailed = false;
    notifyListeners();
    try {
      final page = await _libraryRepository.getMediaLibraryPage(
        scope: _scope,
        filter: _filter.signature(incomingOnly: incomingOnly),
        limit: limit,
      );
      if (generation != _generation) return;
      _entries.clear();
      _entryIds.clear();
      _messageIdByAttachmentId.clear();
      _appendSafe(page.entries);
      _appendSafe(preservedTail);
      _selectedIds.removeWhere((id) => !_entryIds.contains(id));
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

  bool toggleSelection(String attachmentId) {
    if (!_entryIds.contains(attachmentId)) return false;
    if (_selectedIds.remove(attachmentId)) {
      notifyListeners();
      return true;
    }
    if (_selectedIds.length >= kGroupSharedMediaSelectionLimit) return false;
    _selectedIds.add(attachmentId);
    notifyListeners();
    return true;
  }

  void clearSelection() {
    if (_selectedIds.isEmpty) return;
    _selectedIds.clear();
    notifyListeners();
  }

  void unselect(Iterable<String> attachmentIds) {
    var changed = false;
    for (final id in attachmentIds) {
      changed = _selectedIds.remove(id) || changed;
    }
    if (changed) notifyListeners();
  }

  Future<bool> toggleBookmark(String attachmentId) async {
    final index = _entries.indexWhere(
      (entry) => entry.attachment.id == attachmentId,
    );
    if (index < 0) return false;
    final current = _entries[index];
    if (current.attachment.ownerLane != MediaOwnerLane.group) return false;
    final next = !current.attachment.isBookmarked;
    return setBookmarked(attachmentId, bookmarked: next);
  }

  /// Idempotent bookmark writer used by batch Bookmark. Unlike toggle it can
  /// never unbookmark an already-bookmarked selected row.
  Future<bool> setBookmarked(
    String attachmentId, {
    required bool bookmarked,
  }) async {
    final index = _entries.indexWhere(
      (entry) => entry.attachment.id == attachmentId,
    );
    if (index < 0) return false;
    final current = _entries[index];
    if (current.attachment.ownerLane != MediaOwnerLane.group) return false;
    final messageId = _messageIdByAttachmentId[attachmentId];
    final writer = _stateRepository;
    if (messageId == null || writer is! GroupMediaLibraryStateRepository) {
      _removeEntryAt(index);
      notifyListeners();
      return false;
    }
    final groupWriter = writer as GroupMediaLibraryStateRepository;
    final next = bookmarked;
    final changed = await groupWriter.setGroupBookmarkedIfOrdinary(
      groupId: groupId,
      messageId: messageId,
      attachmentId: attachmentId,
      bookmarked: next,
    );
    if (!changed) {
      _removeEntryAt(index);
      notifyListeners();
      return false;
    }
    if (_filter == GroupSharedMediaFilter.bookmarked && !next) {
      _removeEntryAt(index);
    } else {
      _entries[index] = MediaLibraryEntry(
        attachment: current.attachment.copyWith(isBookmarked: next),
        parentTimestamp: current.parentTimestamp,
        parentSenderPeerId: current.parentSenderPeerId,
      );
    }
    notifyListeners();
    return true;
  }

  void _removeEntryAt(int index) {
    final attachmentId = _entries[index].attachment.id;
    _entries.removeAt(index);
    _entryIds.remove(attachmentId);
    _selectedIds.remove(attachmentId);
    _messageIdByAttachmentId.remove(attachmentId);
  }

  void removeEntriesForMessages(Iterable<String> messageIds) {
    final parents = messageIds.toSet();
    if (parents.isEmpty) return;
    final removed = <String>{};
    _entries.removeWhere((entry) {
      if (!parents.contains(entry.attachment.messageId)) return false;
      removed.add(entry.attachment.id);
      return true;
    });
    if (removed.isEmpty) return;
    _entryIds.removeAll(removed);
    _selectedIds.removeAll(removed);
    notifyListeners();
  }

  void _resetVisibleState() {
    _generation++;
    _entries.clear();
    _entryIds.clear();
    _messageIdByAttachmentId.clear();
    _nextCursor = null;
    _hasMore = true;
    _loading = false;
    _loadFailed = false;
  }

  void _appendSafe(Iterable<MediaLibraryEntry> entries) {
    for (final entry in entries) {
      final attachment = entry.attachment;
      if (attachment.ownerLane != MediaOwnerLane.group) continue;
      if (!_entryIds.add(attachment.id)) continue;
      _entries.add(entry);
      _messageIdByAttachmentId[attachment.id] = attachment.messageId;
    }
  }
}
