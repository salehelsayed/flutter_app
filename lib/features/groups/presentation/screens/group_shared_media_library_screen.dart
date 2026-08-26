import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/notifications/app_visibility_route_binding.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/direct_received_media_action_sheet.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_batch_actions.dart';
import 'package:flutter_app/features/groups/application/group_media_batch_forward.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_app/features/share/application/group_media_batch_forward_delivery_coordinator.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_grid_cell.dart';
import 'package:flutter_app/shared/widgets/media/media_video_resume_controller.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';

sealed class GroupSharedMediaLibraryResult {
  const GroupSharedMediaLibraryResult();
}

class GroupSharedMediaGoToMessage extends GroupSharedMediaLibraryResult {
  const GroupSharedMediaGoToMessage({
    required this.groupId,
    required this.messageId,
  });

  final String groupId;
  final String messageId;
}

typedef GroupSharedMediaEvictionDispatch =
    Future<Set<String>> Function(List<MediaLibraryEntry> entries);
typedef GroupSharedMediaForwardDispatch =
    Future<bool> Function(GroupSharedMediaIdentity identity);
typedef GroupSharedMediaViewerEntryQualification =
    Future<bool> Function(GroupSharedMediaIdentity identity);
typedef GroupSharedMediaBookmarkDispatch =
    Future<GroupSharedMediaLocalBatchResult> Function(
      List<GroupSharedMediaIdentity> identities,
    );

enum GroupSharedMediaAction {
  save,
  share,
  bookmark,
  delete,
  evict,
  forward,
  goToMessage,
  pictureInPicture,
}

typedef GroupSharedMediaCapabilityResolver =
    Set<GroupSharedMediaAction> Function(MediaLibraryEntry entry);

/// Local, cursor-backed media library for one active discussion group.
class GroupSharedMediaLibraryScreen extends StatefulWidget {
  const GroupSharedMediaLibraryScreen({
    super.key,
    required this.groupId,
    this.incomingOnly = false,
    required this.libraryRepository,
    required this.stateRepository,
    this.dispatchEgress,
    this.dispatchDelete,
    this.dispatchEviction,
    this.dispatchForward,
    this.launchBatchForward,
    this.qualifyViewerEntry,
    this.pictureInPictureControllerFactory,
    this.loadPictureInPictureAuthorization,
    this.mediaViewerResumeStore,
    this.dispatchBookmark,
    this.onMessagesDeleted,
    this.capabilitiesForEntry,
  });

  final String groupId;
  final bool incomingOnly;
  final MediaLibraryRepository libraryRepository;
  final MediaLibraryStateRepository stateRepository;
  final GroupSharedMediaEgressDispatch? dispatchEgress;
  final GroupSharedMediaDeleteDispatch? dispatchDelete;
  final GroupSharedMediaEvictionDispatch? dispatchEviction;
  final GroupSharedMediaForwardDispatch? dispatchForward;
  final GroupMediaBatchForwardLibraryLaunch? launchBatchForward;
  final GroupSharedMediaViewerEntryQualification? qualifyViewerEntry;
  final MediaPictureInPictureControllerFactory?
  pictureInPictureControllerFactory;
  final MediaPictureInPictureAuthorizationLoader?
  loadPictureInPictureAuthorization;
  final MediaViewerResumeStore? mediaViewerResumeStore;
  final GroupSharedMediaBookmarkDispatch? dispatchBookmark;
  final void Function(Set<String> messageIds)? onMessagesDeleted;
  final GroupSharedMediaCapabilityResolver? capabilitiesForEntry;

  @override
  State<GroupSharedMediaLibraryScreen> createState() =>
      _GroupSharedMediaLibraryScreenState();
}

class _GroupSharedMediaLibraryScreenState
    extends State<GroupSharedMediaLibraryScreen>
    with WidgetsBindingObserver {
  late final GroupSharedMediaLibraryController _controller;
  final ScrollController _scrollController = ScrollController();
  final Map<String, MediaLibraryEntry> _qualifiedEntries = {};
  final Map<String, MediaLibraryEntry> _qualificationFlights = {};
  bool _batchForwardActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = GroupSharedMediaLibraryController(
      groupId: widget.groupId,
      incomingOnly: widget.incomingOnly,
      libraryRepository: widget.libraryRepository,
      stateRepository: widget.stateRepository,
    )..addListener(_onControllerChanged);
    _scrollController.addListener(_onScroll);
    _controller.loadNextPage();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.refreshCurrentPage();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final liveKeys = {
      for (final entry in _controller.entries) _qualificationKey(entry),
    };
    _qualifiedEntries.removeWhere((key, _) => !liveKeys.contains(key));
    _qualificationFlights.removeWhere((key, _) => !liveKeys.contains(key));
    setState(() {});
    _schedulePendingQualifications();
  }

  String _qualificationKey(MediaLibraryEntry entry) =>
      '${entry.attachment.messageId}\u0000${entry.attachment.id}';

  bool _isEntryQualified(MediaLibraryEntry entry) {
    if (widget.qualifyViewerEntry == null) return true;
    return identical(_qualifiedEntries[_qualificationKey(entry)], entry);
  }

  void _schedulePendingQualifications() {
    final qualify = widget.qualifyViewerEntry;
    if (qualify == null || !mounted) return;
    for (final entry in _controller.entries) {
      final key = _qualificationKey(entry);
      if (identical(_qualifiedEntries[key], entry) ||
          identical(_qualificationFlights[key], entry)) {
        continue;
      }
      _qualificationFlights[key] = entry;
      unawaited(_qualifyEntry(entry, key, qualify));
    }
  }

  Future<void> _qualifyEntry(
    MediaLibraryEntry entry,
    String key,
    GroupSharedMediaViewerEntryQualification qualify,
  ) async {
    var allowed = false;
    try {
      allowed = await qualify(
        GroupSharedMediaIdentity(
          groupId: widget.groupId,
          messageId: entry.attachment.messageId,
          attachmentId: entry.attachment.id,
        ),
      );
    } catch (_) {
      allowed = false;
    }
    if (!mounted || !identical(_qualificationFlights[key], entry)) return;
    _qualificationFlights.remove(key);
    final current = _controller.entryFor(entry.attachment.id);
    if (!identical(current, entry)) {
      _schedulePendingQualifications();
      return;
    }
    if (!allowed) {
      _qualifiedEntries.remove(key);
      _controller.removeEntriesForMessages({entry.attachment.messageId});
      return;
    }
    setState(() => _qualifiedEntries[key] = entry);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _controller.loadNextPage();
    }
  }

  void _toggleSelection(String id) {
    final changed = _controller.toggleSelection(id);
    if (!changed && !_controller.isSelected(id) && mounted) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              )!.shared_media_selection_limit(kGroupSharedMediaSelectionLimit),
            ),
          ),
        );
    }
  }

  Future<void> _performEgress(MediaEgressDestination destination) async {
    final dispatch = widget.dispatchEgress;
    if (dispatch == null) return;
    final identities = _controller.identitiesFor(_controller.selectedIds);
    if (identities.isEmpty) return;
    final result = await dispatch(identities, destination);
    if (!mounted) return;
    _controller.unselect(result.succeededIds);
    await _controller.refreshCurrentPage();
    if (!mounted || result.wasCancelled || result.failedIds.isEmpty) return;
    _showPartialFailure(result.failedIds.length);
  }

  Future<bool> _confirmDelete(int count) async {
    final l10n = AppLocalizations.of(context)!;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            key: const ValueKey('group-shared-media-delete-dialog'),
            title: Text(l10n.shared_media_delete_title(count)),
            content: Text(l10n.shared_media_delete_body),
            actions: [
              TextButton(
                key: const ValueKey('group-shared-media-delete-cancel'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.shared_media_delete_cancel),
              ),
              TextButton(
                key: const ValueKey('group-shared-media-delete-confirm'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.shared_media_delete_confirm),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _performDelete() async {
    final dispatch = widget.dispatchDelete;
    if (dispatch == null) return;
    final identities = _controller.identitiesFor(_controller.selectedIds);
    if (identities.isEmpty) return;
    final parentCount = identities.map((item) => item.messageId).toSet().length;
    if (!await _confirmDelete(parentCount) || !mounted) return;
    final outcome = await dispatch(identities);
    if (!mounted) return;
    _controller.removeEntriesForMessages(outcome.deletedMessageIds);
    widget.onMessagesDeleted?.call(outcome.deletedMessageIds);
    await _controller.refreshCurrentPage();
    if (mounted && outcome.failedAttachmentIds.isNotEmpty) {
      _showPartialFailure(outcome.failedAttachmentIds.length);
    }
  }

  Future<void> _performBookmarks() async {
    final selected = _controller.selectedIds.toList(growable: false);
    final dispatch = widget.dispatchBookmark;
    if (dispatch != null) {
      final result = await dispatch(_controller.identitiesFor(selected));
      if (!mounted) return;
      _controller.unselect(result.succeededIds);
      await _controller.refreshCurrentPage();
      if (mounted && result.failedIds.isNotEmpty) {
        _showPartialFailure(result.failedIds.length);
      }
      return;
    }
    final succeeded = <String>[];
    for (final id in selected) {
      if (await _controller.setBookmarked(id, bookmarked: true)) {
        succeeded.add(id);
      }
    }
    _controller.unselect(succeeded);
    await _controller.refreshCurrentPage();
  }

  Future<void> _performEviction() async {
    final dispatch = widget.dispatchEviction;
    if (dispatch == null) return;
    final entries = _controller.selectedIds
        .map(_controller.entryFor)
        .whereType<MediaLibraryEntry>()
        .toList(growable: false);
    if (entries.isEmpty) return;
    final cleared = await dispatch(entries);
    if (!mounted) return;
    _controller.unselect(cleared);
    await _controller.refreshCurrentPage();
    if (mounted && cleared.length != entries.length) {
      _showPartialFailure(entries.length - cleared.length);
    }
  }

  void _showPartialFailure(int count) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            )!.shared_media_batch_partial_failure(count),
          ),
        ),
      );
  }

  Future<void> _openViewer(String attachmentId) async {
    final messageId = _controller.messageIdOf(attachmentId);
    if (messageId == null) return;
    final identity = GroupSharedMediaIdentity(
      groupId: widget.groupId,
      messageId: messageId,
      attachmentId: attachmentId,
    );
    final qualify = widget.qualifyViewerEntry;
    if (qualify != null) {
      var allowed = false;
      try {
        allowed = await qualify(identity);
      } catch (_) {
        allowed = false;
      }
      if (!mounted) return;
      if (!allowed) {
        // The policy is message-scoped: one denied current parent invalidates
        // every cached thumbnail/viewer item for that parent.
        _controller.removeEntriesForMessages({messageId});
        return;
      }
    }
    if (_controller.entryFor(attachmentId) == null || !mounted) return;
    final visibilityIdentity = AppVisibilityConversationIdentity.tryParse(
      lane: AppVisibilityConversationLane.group,
      value: 'group:${widget.groupId}',
    );
    Widget viewerBuilder(BuildContext _) => _GroupSharedMediaViewerHost(
      screen: widget,
      controller: _controller,
      initialAttachmentId: attachmentId,
      confirmDelete: _confirmDelete,
    );
    Navigator.of(context).push<void>(
      visibilityIdentity == null
          ? MaterialPageRoute<void>(builder: viewerBuilder)
          : AppVisibilityInheritedConversationRoute<void>(
              identity: visibilityIdentity,
              builder: viewerBuilder,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: _controller.hasSelection
            ? Text(
                l10n.shared_media_selection_count(_controller.selectedCount),
                key: const ValueKey('group-shared-media-selection-title'),
              )
            : Text(l10n.shared_media_title),
        leading: _controller.hasSelection
            ? IconButton(
                key: const ValueKey('group-shared-media-selection-close'),
                onPressed: _controller.clearSelection,
                icon: const Icon(Icons.close),
              )
            : null,
      ),
      body: Column(
        children: [
          _buildFilters(l10n),
          Expanded(child: _buildBody(l10n)),
          if (_controller.hasSelection) _buildActionBar(l10n),
        ],
      ),
    );
  }

  Widget _buildFilters(AppLocalizations l10n) {
    Widget chip(GroupSharedMediaFilter filter, String label) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: ValueKey('group-shared-media-filter-${filter.name}'),
        label: Text(label),
        selected: _controller.filter == filter,
        onSelected: (_) => _controller.setFilter(filter),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          chip(GroupSharedMediaFilter.all, l10n.shared_media_title),
          chip(GroupSharedMediaFilter.images, l10n.shared_media_filter_photos),
          chip(GroupSharedMediaFilter.videos, l10n.shared_media_filter_videos),
          chip(
            GroupSharedMediaFilter.bookmarked,
            l10n.shared_media_filter_bookmarked,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_controller.entries.isEmpty) {
      if (_controller.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Text(
          _controller.loadFailed
              ? l10n.shared_media_load_failed
              : l10n.shared_media_empty,
          key: const ValueKey('group-shared-media-empty'),
        ),
      );
    }
    return GridView.builder(
      key: const ValueKey('group-shared-media-grid'),
      controller: _scrollController,
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: _controller.entries.length,
      itemBuilder: (context, index) => _buildTile(_controller.entries[index]),
    );
  }

  Widget _buildTile(MediaLibraryEntry entry) {
    final attachment = entry.attachment;
    if (!_isEntryQualified(entry)) {
      _schedulePendingQualifications();
      return KeyedSubtree(
        key: ValueKey('group-shared-media-tile-${attachment.id}'),
        child: const ColoredBox(color: Color.fromRGBO(0, 0, 0, 0.08)),
      );
    }
    final selected = _controller.isSelected(attachment.id);
    return KeyedSubtree(
      key: ValueKey('group-shared-media-tile-${attachment.id}'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          MediaGridCell(
            attachment: attachment,
            requireVerifiedContentHash: true,
            ownedMediaPeerId: widget.groupId,
            onTap: () => _controller.hasSelection
                ? _toggleSelection(attachment.id)
                : _openViewer(attachment.id),
            onLongPress: () => _toggleSelection(attachment.id),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              key: ValueKey('group-shared-media-bookmark-${attachment.id}'),
              iconSize: 18,
              icon: Icon(
                attachment.isBookmarked
                    ? Icons.bookmark
                    : Icons.bookmark_border,
              ),
              onPressed: () => _controller.toggleBookmark(attachment.id),
            ),
          ),
          if (selected)
            const Positioned(
              left: 5,
              bottom: 5,
              child: Icon(Icons.check_circle_rounded, size: 22),
            ),
        ],
      ),
    );
  }

  Widget _buildActionBar(AppLocalizations l10n) {
    final selectedEntries = _controller.selectedIds
        .map(_controller.entryFor)
        .whereType<MediaLibraryEntry>()
        .toList(growable: false);
    final intersection = selectedEntries.isEmpty
        ? const <GroupSharedMediaAction>{}
        : selectedEntries
              .map(_capabilitiesFor)
              .reduce((left, right) => left.intersection(right));

    Future<void> performBatchForward() async {
      final launch = widget.launchBatchForward;
      if (launch == null || _batchForwardActive) return;
      final identities = _controller.identitiesFor(_controller.selectedIds);
      if (identities.length < kGroupMediaBatchForwardRouteMinItems ||
          identities.length > kGroupMediaBatchForwardMaxItems) {
        return;
      }
      setState(() => _batchForwardActive = true);
      try {
        final result = await launch(identities);
        if (!mounted) return;
        switch (result.status) {
          case GroupMediaBatchForwardLibraryLaunchStatus.cancelled:
            break;
          case GroupMediaBatchForwardLibraryLaunchStatus.denied:
            final denial = result.denial;
            ScaffoldMessenger.maybeOf(context)
              ?..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  key: ValueKey(
                    denial == GroupMediaBatchForwardDenial.sizeLimitExceeded
                        ? 'group-batch-forward-size-limit'
                        : 'group-batch-forward-source-unavailable',
                  ),
                  content: Text(
                    denial == GroupMediaBatchForwardDenial.sizeLimitExceeded
                        ? l10n.media_attachments_too_large_note
                        : l10n.direct_batch_forward_source_unavailable,
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
          case GroupMediaBatchForwardLibraryLaunchStatus.completed:
            final completion = result.completion;
            if (completion != null) {
              _controller.unselect(
                completion.fullySettledSourceIdentities.map(
                  (identity) => identity.attachmentId,
                ),
              );
            }
        }
      } finally {
        if (mounted) setState(() => _batchForwardActive = false);
      }
    }

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          key: const ValueKey('group-shared-media-selection-actions'),
          children: [
            if (intersection.contains(GroupSharedMediaAction.save) &&
                intersection.contains(GroupSharedMediaAction.share) &&
                widget.dispatchEgress != null) ...[
              TextButton.icon(
                key: const ValueKey('group-shared-media-action-save'),
                onPressed: () async {
                  final destination =
                      await DirectMediaSaveDestinationSheet.show(context);
                  if (destination != null && mounted) {
                    await _performEgress(destination);
                  }
                },
                icon: const Icon(Icons.download_rounded),
                label: Text(l10n.shared_media_action_save),
              ),
              TextButton.icon(
                key: const ValueKey('group-shared-media-action-share'),
                onPressed: () => _performEgress(MediaEgressDestination.share),
                icon: const Icon(Icons.ios_share_rounded),
                label: Text(l10n.shared_media_action_share),
              ),
            ],
            if (intersection.contains(GroupSharedMediaAction.bookmark))
              TextButton.icon(
                key: const ValueKey('group-shared-media-action-bookmark'),
                onPressed: _performBookmarks,
                icon: const Icon(Icons.bookmark_border),
                label: Text(l10n.media_viewer_action_bookmark),
              ),
            if (intersection.contains(GroupSharedMediaAction.evict) &&
                widget.dispatchEviction != null)
              TextButton.icon(
                key: const ValueKey('group-shared-media-action-evict'),
                onPressed: _performEviction,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text(l10n.settings_media_storage_clear_type),
              ),
            if (intersection.contains(GroupSharedMediaAction.delete) &&
                widget.dispatchDelete != null)
              TextButton.icon(
                key: const ValueKey('group-shared-media-action-delete'),
                onPressed: _performDelete,
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.shared_media_action_delete),
              ),
            if (_controller.selectedCount >=
                    kGroupMediaBatchForwardRouteMinItems &&
                _controller.selectedCount <= kGroupMediaBatchForwardMaxItems &&
                intersection.contains(GroupSharedMediaAction.forward) &&
                widget.launchBatchForward != null)
              TextButton.icon(
                key: const ValueKey('group-shared-media-action-batch-forward'),
                onPressed: _batchForwardActive ? null : performBatchForward,
                icon: const Icon(Icons.forward_to_inbox_rounded),
                label: Text(l10n.media_viewer_action_forward),
              ),
            if (_controller.selectedCount == 1) ...[
              if (intersection.contains(GroupSharedMediaAction.forward) &&
                  widget.dispatchForward != null)
                TextButton.icon(
                  key: const ValueKey('group-shared-media-action-forward'),
                  onPressed: () async {
                    final identity = _controller
                        .identitiesFor(_controller.selectedIds)
                        .single;
                    await widget.dispatchForward!(identity);
                  },
                  icon: const Icon(Icons.forward_rounded),
                  label: Text(l10n.media_viewer_action_forward),
                ),
              if (intersection.contains(GroupSharedMediaAction.goToMessage))
                TextButton.icon(
                  key: const ValueKey('group-shared-media-action-goto'),
                  onPressed: () {
                    final identity = _controller
                        .identitiesFor(_controller.selectedIds)
                        .single;
                    Navigator.of(context).pop(
                      GroupSharedMediaGoToMessage(
                        groupId: identity.groupId,
                        messageId: identity.messageId,
                      ),
                    );
                  },
                  icon: const Icon(Icons.my_location_rounded),
                  label: Text(l10n.shared_media_action_go_to_message),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Set<GroupSharedMediaAction> _capabilitiesFor(MediaLibraryEntry entry) {
    final resolved = widget.capabilitiesForEntry?.call(entry);
    if (resolved != null) return resolved;
    return {
      GroupSharedMediaAction.bookmark,
      GroupSharedMediaAction.goToMessage,
      if (widget.dispatchDelete != null) GroupSharedMediaAction.delete,
    };
  }
}

class _GroupSharedMediaViewerHost extends StatefulWidget {
  const _GroupSharedMediaViewerHost({
    required this.screen,
    required this.controller,
    required this.initialAttachmentId,
    required this.confirmDelete,
  });

  final GroupSharedMediaLibraryScreen screen;
  final GroupSharedMediaLibraryController controller;
  final String initialAttachmentId;
  final Future<bool> Function(int count) confirmDelete;

  @override
  State<_GroupSharedMediaViewerHost> createState() =>
      _GroupSharedMediaViewerHostState();
}

class _GroupSharedMediaViewerHostState
    extends State<_GroupSharedMediaViewerHost> {
  late int _currentIndex;
  late String _currentAttachmentId;
  final Map<String, MediaLibraryEntry> _qualifiedEntries = {};
  final Map<String, MediaLibraryEntry> _qualificationFlights = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.controller.entries.indexWhere(
      (entry) => entry.attachment.id == widget.initialAttachmentId,
    );
    if (_currentIndex < 0) _currentIndex = 0;
    _currentAttachmentId = widget.initialAttachmentId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNearBoundary());
  }

  void _loadNearBoundary() {
    if (!mounted || !widget.controller.hasMore) return;
    if (_currentIndex >= widget.controller.entries.length - 3) {
      widget.controller.loadNextPage();
    }
  }

  String _qualificationKey(MediaLibraryEntry entry) =>
      '${entry.attachment.messageId}\u0000${entry.attachment.id}';

  bool _isEntryQualified(MediaLibraryEntry entry) {
    if (widget.screen.qualifyViewerEntry == null) return true;
    return identical(_qualifiedEntries[_qualificationKey(entry)], entry);
  }

  void _schedulePendingQualifications(List<MediaLibraryEntry> entries) {
    final qualify = widget.screen.qualifyViewerEntry;
    if (qualify == null || !mounted) return;
    final liveKeys = {for (final entry in entries) _qualificationKey(entry)};
    _qualifiedEntries.removeWhere((key, _) => !liveKeys.contains(key));
    _qualificationFlights.removeWhere((key, _) => !liveKeys.contains(key));
    for (final entry in entries) {
      final key = _qualificationKey(entry);
      if (identical(_qualifiedEntries[key], entry) ||
          identical(_qualificationFlights[key], entry)) {
        continue;
      }
      _qualificationFlights[key] = entry;
      unawaited(_qualifyEntry(entry, key, qualify));
    }
  }

  Future<void> _qualifyEntry(
    MediaLibraryEntry entry,
    String key,
    GroupSharedMediaViewerEntryQualification qualify,
  ) async {
    var allowed = false;
    try {
      allowed = await qualify(
        GroupSharedMediaIdentity(
          groupId: widget.screen.groupId,
          messageId: entry.attachment.messageId,
          attachmentId: entry.attachment.id,
        ),
      );
    } catch (_) {
      allowed = false;
    }
    if (!mounted || !identical(_qualificationFlights[key], entry)) return;
    _qualificationFlights.remove(key);
    final current = widget.controller.entryFor(entry.attachment.id);
    if (!identical(current, entry)) {
      setState(() {});
      return;
    }
    if (!allowed) {
      _qualifiedEntries.remove(key);
      widget.controller.removeEntriesForMessages({entry.attachment.messageId});
      return;
    }
    setState(() => _qualifiedEntries[key] = entry);
  }

  Widget _pendingQualificationPlaceholder() => const ColoredBox(
    key: ValueKey('group-shared-media-viewer-qualification-pending'),
    color: Colors.black,
  );

  Future<MediaViewerActionResult> _onAction(
    MediaViewerItem item,
    MediaViewerAction action,
  ) async {
    final identity = GroupSharedMediaIdentity(
      groupId: widget.screen.groupId,
      messageId: item.messageId,
      attachmentId: item.attachmentId,
    );
    switch (action) {
      case MediaViewerAction.save:
      case MediaViewerAction.share:
        final dispatch = widget.screen.dispatchEgress;
        if (dispatch == null) return MediaViewerActionResult.failure;
        final destination = action == MediaViewerAction.share
            ? MediaEgressDestination.share
            : await DirectMediaSaveDestinationSheet.show(context);
        if (destination == null || !mounted) {
          return MediaViewerActionResult.cancelled;
        }
        final result = await dispatch([identity], destination);
        if (result.wasCancelled) return MediaViewerActionResult.cancelled;
        await widget.controller.refreshCurrentPage();
        return result.succeededIds.contains(item.attachmentId)
            ? MediaViewerActionResult.success
            : MediaViewerActionResult.failure;
      case MediaViewerAction.bookmark:
        final toggled = await widget.controller.toggleBookmark(
          item.attachmentId,
        );
        if (toggled) await widget.controller.refreshCurrentPage();
        return toggled
            ? MediaViewerActionResult.success
            : MediaViewerActionResult.failure;
      case MediaViewerAction.delete:
        final dispatch = widget.screen.dispatchDelete;
        if (dispatch == null || !await widget.confirmDelete(1) || !mounted) {
          return MediaViewerActionResult.cancelled;
        }
        final outcome = await dispatch([identity]);
        if (!outcome.deletedMessageIds.contains(item.messageId)) {
          return MediaViewerActionResult.failure;
        }
        widget.controller.removeEntriesForMessages(outcome.deletedMessageIds);
        widget.screen.onMessagesDeleted?.call(outcome.deletedMessageIds);
        await widget.controller.refreshCurrentPage();
        if (mounted) Navigator.of(context).pop();
        return MediaViewerActionResult.success;
      case MediaViewerAction.forward:
        final dispatch = widget.screen.dispatchForward;
        if (dispatch == null) return MediaViewerActionResult.failure;
        final forwarded = await dispatch(identity);
        await widget.controller.refreshCurrentPage();
        return forwarded
            ? MediaViewerActionResult.success
            : MediaViewerActionResult.failure;
      case MediaViewerAction.info:
      case MediaViewerAction.reply:
      case MediaViewerAction.messageSender:
        // Plan 247 exposes Message sender only from an exact live
        // conversation parent, never from paged Shared Media.
        return MediaViewerActionResult.failure;
    }
  }

  MediaViewerItem _item(MediaLibraryEntry entry) {
    final attachment = entry.attachment;
    final localPath = attachment.localPath;
    final kind = attachment.mediaType == 'video'
        ? MediaViewerKind.video
        : attachment.isAnimated
        ? MediaViewerKind.gif
        : MediaViewerKind.image;
    final capabilities =
        widget.screen.capabilitiesForEntry?.call(entry) ??
        const <GroupSharedMediaAction>{GroupSharedMediaAction.bookmark};
    final egressEligible =
        capabilities.contains(GroupSharedMediaAction.save) &&
        capabilities.contains(GroupSharedMediaAction.share);
    return MediaViewerItem(
      attachmentId: attachment.id,
      messageId: attachment.messageId,
      kind: kind,
      mime: attachment.mime,
      owner: MediaOwnerLane.group,
      localPath: localPath == null
          ? null
          : MediaFileManager.resolveStoredPathSync(localPath),
      sizeBytes: attachment.size,
      width: attachment.width,
      height: attachment.height,
      durationMs: attachment.durationMs,
      senderLabel: entry.parentSenderPeerId,
      timestamp: DateTime.tryParse(entry.parentTimestamp),
      showMetadataDetails:
          kind == MediaViewerKind.gif ||
          (kind == MediaViewerKind.image && widget.screen.incomingOnly),
      canEnterPictureInPicture:
          capabilities.contains(GroupSharedMediaAction.pictureInPicture) &&
          attachment.mediaType == 'video' &&
          egressEligible,
      protection: MediaViewerProtection(
        isDownloaded: egressEligible,
        isIntegrityVerified:
            GroupMediaIntegrityPolicy.hasRequiredVerificationMetadata(
              attachment,
            ),
      ),
      capabilities: MediaViewerActionCapabilities(
        allowed: {
          if (egressEligible && widget.screen.dispatchEgress != null) ...{
            MediaViewerAction.save,
            MediaViewerAction.share,
          },
          MediaViewerAction.bookmark,
          if (capabilities.contains(GroupSharedMediaAction.delete) &&
              widget.screen.dispatchDelete != null)
            MediaViewerAction.delete,
          if (capabilities.contains(GroupSharedMediaAction.forward) &&
              widget.screen.dispatchForward != null)
            MediaViewerAction.forward,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final entries = widget.controller.entries;
        if (entries.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
          return const SizedBox.shrink();
        }
        _schedulePendingQualifications(entries);
        final currentEntry = entries
            .where((entry) => entry.attachment.id == _currentAttachmentId)
            .firstOrNull;
        if (currentEntry == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
          return const SizedBox.shrink();
        }
        if (!_isEntryQualified(currentEntry)) {
          return _pendingQualificationPlaceholder();
        }
        final qualifiedEntries = entries
            .where(_isEntryQualified)
            .toList(growable: false);
        final currentIndex = qualifiedEntries.indexWhere(
          (entry) => entry.attachment.id == _currentAttachmentId,
        );
        if (currentIndex < 0) {
          return _pendingQualificationPlaceholder();
        }
        _currentIndex = currentIndex;
        return FullScreenTypedMediaViewer(
          items: [for (final entry in qualifiedEntries) _item(entry)],
          initialIndex: _currentIndex.clamp(0, qualifiedEntries.length - 1),
          onPageChanged: (index) {
            _currentIndex = index;
            _currentAttachmentId = qualifiedEntries[index].attachment.id;
            _loadNearBoundary();
          },
          onAction: _onAction,
          resumeStore: widget.screen.mediaViewerResumeStore,
          pictureInPictureControllerFactory:
              widget.screen.pictureInPictureControllerFactory,
          loadPictureInPictureAuthorization:
              widget.screen.loadPictureInPictureAuthorization,
        );
      },
    );
  }
}
