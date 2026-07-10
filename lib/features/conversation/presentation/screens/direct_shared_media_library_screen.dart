import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';

import '../../application/direct_media_library_batch_actions.dart';
import '../../application/direct_media_library_batch_delete.dart';
import '../../application/direct_media_library_controller.dart';
import '../../application/received_media_action_controller.dart';
import '../../domain/models/media_attachment.dart';
import '../../domain/models/media_library.dart';
import '../../domain/repositories/media_attachment_repository.dart';
import '../widgets/direct_received_media_action_sheet.dart';

/// Result a shared-media-library route can pop with.
sealed class DirectSharedMediaLibraryResult {
  const DirectSharedMediaLibraryResult();
}

/// The user asked to jump to one attachment's owning direct message.
class DirectSharedMediaGoToMessage extends DirectSharedMediaLibraryResult {
  const DirectSharedMediaGoToMessage(this.messageId);

  final String messageId;
}

bool _defaultFileExists(String resolvedPath) => File(resolvedPath).existsSync();

/// 233: the 1:1 Shared Media library.
///
/// Strictly direct-scoped: the screen accepts ONLY a contact peer id — the
/// [DirectMediaLibraryController] builds `MediaLibraryScope.direct` itself,
/// so no caller can hand this surface a sibling scope. Local-only: pages come
/// from the plan-228 repository, bookmark writes go through the plan-228
/// ID-based state API, and nothing here touches transport, bridge, or
/// download machinery — a missing/evicted row renders a truthful state and
/// never triggers an implicit transfer. Batch Save/Share/Delete dispatch
/// through injected coordinator seams with the shared ten-item selection
/// ceiling; Delete requires explicit whole-message confirmation.
class DirectSharedMediaLibraryScreen extends StatefulWidget {
  const DirectSharedMediaLibraryScreen({
    super.key,
    required this.contactPeerId,
    required this.contactUsername,
    required this.libraryRepository,
    required this.stateRepository,
    this.dispatchEgress,
    this.dispatchDelete,
    this.onMessagesDeleted,
    this.resolveStoredPath = MediaFileManager.resolveStoredPathSync,
    // Sync existence probe: widget tests run in a fake-async zone where
    // awaited real dart:io never completes (same seam as plan 231).
    this.fileExists = _defaultFileExists,
  });

  final String contactPeerId;
  final String contactUsername;
  final MediaLibraryRepository libraryRepository;
  final MediaLibraryStateRepository stateRepository;

  /// Batch/current-item Save and Share authority (plan-231 current-row
  /// qualification + one plan-227 list-capable native call). Null leaves
  /// Save/Share unwired.
  final DirectMediaLibraryEgressDispatch? dispatchEgress;

  /// Confirmed whole-message Delete-for-Me authority. Null leaves Delete
  /// unwired.
  final DirectMediaLibraryDeleteDispatch? dispatchDelete;

  /// Notifies the owning conversation of locally deleted message ids so its
  /// open window can reconcile.
  final void Function(Set<String> deletedMessageIds)? onMessagesDeleted;

  final String Function(String storedPath) resolveStoredPath;
  final bool Function(String resolvedPath) fileExists;

  @override
  State<DirectSharedMediaLibraryScreen> createState() =>
      _DirectSharedMediaLibraryScreenState();
}

class _DirectSharedMediaLibraryScreenState
    extends State<DirectSharedMediaLibraryScreen> {
  late final DirectMediaLibraryController _controller;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = DirectMediaLibraryController(
      libraryRepository: widget.libraryRepository,
      stateRepository: widget.stateRepository,
      contactPeerId: widget.contactPeerId,
    );
    _controller.addListener(_onControllerChanged);
    _scrollController.addListener(_onScroll);
    _controller.loadNextPage();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _controller.loadNextPage();
    }
  }

  void _toggleSelection(String attachmentId) {
    final toggled = _controller.toggleSelection(attachmentId);
    if (!toggled && !_controller.isSelected(attachmentId)) {
      // The refused ELEVENTH selection: a truthful bounded-selection notice.
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l10n.shared_media_selection_limit(kMaxDirectMediaSelection),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  List<DirectReceivedMediaActionIdentity> _identitiesFor(
    Iterable<String> attachmentIds,
  ) {
    return [
      for (final id in attachmentIds)
        if (_controller.messageIdOf(id) != null)
          DirectReceivedMediaActionIdentity(
            messageId: _controller.messageIdOf(id)!,
            attachmentId: id,
          ),
    ];
  }

  Future<bool> _confirmDeleteForMe(int messageCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          key: const ValueKey('shared-media-delete-confirm-dialog'),
          title: Text(l10n.shared_media_delete_title(messageCount)),
          content: Text(l10n.shared_media_delete_body),
          actions: [
            TextButton(
              key: const ValueKey('shared-media-delete-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.shared_media_delete_cancel),
            ),
            TextButton(
              key: const ValueKey('shared-media-delete-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.shared_media_delete_confirm),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  /// Applies a confirmed delete outcome: reconciles the grid/selection and
  /// notifies the owning conversation. Failed attachments stay selected.
  void _applyDeleteOutcome(DirectMediaLibraryBatchDeleteOutcome outcome) {
    for (final messageId in outcome.deletedMessageIds) {
      _controller.removeEntriesForMessage(messageId);
    }
    if (outcome.deletedMessageIds.isNotEmpty) {
      widget.onMessagesDeleted?.call(outcome.deletedMessageIds);
    }
    if (outcome.failedAttachmentIds.isNotEmpty) {
      _showPartialFailureNotice(outcome.failedAttachmentIds.length);
    }
  }

  void _showPartialFailureNotice(int failedCount) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.shared_media_batch_partial_failure(failedCount)),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _openViewer(String attachmentId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SharedMediaViewerHost(
          screen: widget,
          controller: _controller,
          initialAttachmentId: attachmentId,
          confirmDelete: _confirmDeleteForMe,
        ),
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
                key: const ValueKey('shared-media-selection-title'),
              )
            : Text(l10n.shared_media_title),
        leading: _controller.hasSelection
            ? IconButton(
                key: const ValueKey('shared-media-selection-close'),
                icon: const Icon(Icons.close),
                onPressed: _controller.clearSelection,
              )
            : null,
      ),
      body: Column(
        children: [
          _buildFilterRow(l10n),
          Expanded(child: _buildBody(l10n)),
          if (_controller.hasSelection) _buildSelectionActionBar(l10n),
        ],
      ),
    );
  }

  Widget _buildFilterRow(AppLocalizations l10n) {
    Widget chip(DirectMediaLibraryFilter filter, String label) {
      final selected = _controller.filter == filter;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          key: ValueKey('shared-media-filter-${filter.name}'),
          label: Text(label),
          selected: selected,
          onSelected: (_) => _controller.setFilter(filter),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          chip(DirectMediaLibraryFilter.all, l10n.shared_media_filter_all),
          chip(
            DirectMediaLibraryFilter.photos,
            l10n.shared_media_filter_photos,
          ),
          chip(
            DirectMediaLibraryFilter.videos,
            l10n.shared_media_filter_videos,
          ),
          chip(
            DirectMediaLibraryFilter.bookmarked,
            l10n.shared_media_filter_bookmarked,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionActionBar(AppLocalizations l10n) {
    final selectedIds = _controller.selectedIds;

    Future<void> performEgress(MediaEgressDestination destination) async {
      final dispatch = widget.dispatchEgress;
      if (dispatch == null) return;
      final identities = _identitiesFor(selectedIds);
      if (identities.isEmpty) return;
      final result = await dispatch(identities, destination);
      if (!mounted) return;
      // Truthful failed-only retry: only successful items clear.
      _controller.unselect(result.succeededIds);
      if (!result.wasCancelled && result.failedIds.isNotEmpty) {
        _showPartialFailureNotice(result.failedIds.length);
      }
    }

    Future<void> performDelete() async {
      final dispatch = widget.dispatchDelete;
      if (dispatch == null) return;
      final identities = _identitiesFor(selectedIds);
      if (identities.isEmpty) return;
      final uniqueParents = identities.map((i) => i.messageId).toSet();
      final confirmed = await _confirmDeleteForMe(uniqueParents.length);
      if (!confirmed || !mounted) return;
      final outcome = await dispatch(identities);
      if (!mounted) return;
      _applyDeleteOutcome(outcome);
    }

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          key: const ValueKey('shared-media-selection-actions'),
          children: [
            if (widget.dispatchEgress != null) ...[
              TextButton.icon(
                key: const ValueKey('shared-media-action-save'),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text(l10n.shared_media_action_save),
                onPressed: () async {
                  final destination = await DirectMediaSaveDestinationSheet.show(
                    context,
                  );
                  if (destination == null || !mounted) return;
                  await performEgress(destination);
                },
              ),
              TextButton.icon(
                key: const ValueKey('shared-media-action-share'),
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: Text(l10n.shared_media_action_share),
                onPressed: () => performEgress(MediaEgressDestination.share),
              ),
            ],
            if (widget.dispatchDelete != null)
              TextButton.icon(
                key: const ValueKey('shared-media-action-delete'),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text(l10n.shared_media_action_delete),
                onPressed: performDelete,
              ),
            if (selectedIds.length == 1)
              TextButton.icon(
                key: const ValueKey('shared-media-action-goto'),
                icon: const Icon(Icons.my_location_rounded, size: 18),
                label: Text(l10n.shared_media_action_go_to_message),
                onPressed: () {
                  final messageId = _controller.messageIdOf(
                    selectedIds.single,
                  );
                  if (messageId == null) return;
                  Navigator.of(
                    context,
                  ).pop(DirectSharedMediaGoToMessage(messageId));
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    final entries = _controller.entries;
    if (entries.isEmpty) {
      if (_controller.isLoading) {
        return const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        );
      }
      return Center(
        child: Text(
          _controller.loadFailed
              ? l10n.shared_media_load_failed
              : l10n.shared_media_empty,
          key: const ValueKey('shared-media-empty'),
          textAlign: TextAlign.center,
        ),
      );
    }
    return GridView.builder(
      key: const ValueKey('shared-media-grid'),
      controller: _scrollController,
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) => _buildTile(l10n, entries[index]),
    );
  }

  Widget _buildTile(AppLocalizations l10n, MediaLibraryEntry entry) {
    final attachment = entry.attachment;
    final stateLabel = _unavailableStateLabel(l10n, attachment);
    final isVideo = attachment.mediaType == 'video';
    final selected = _controller.isSelected(attachment.id);
    final semanticsLabel = [
      isVideo ? l10n.shared_media_kind_video : l10n.shared_media_kind_photo,
      if (attachment.isBookmarked) l10n.media_viewer_action_bookmark,
      ?stateLabel,
    ].join(', ');

    return Semantics(
      key: ValueKey('shared-media-tile-${attachment.id}'),
      label: semanticsLabel,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_controller.hasSelection) {
            _toggleSelection(attachment.id);
          } else {
            _openViewer(attachment.id);
          }
        },
        onLongPress: () => _toggleSelection(attachment.id),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (stateLabel == null)
              Image.file(
                File(widget.resolveStoredPath(attachment.localPath!)),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const ColoredBox(
                  color: Color.fromRGBO(127, 127, 127, 0.2),
                  child: Icon(Icons.broken_image_outlined, size: 28),
                ),
              )
            else
              ColoredBox(
                color: const Color.fromRGBO(127, 127, 127, 0.15),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      stateLabel,
                      key: ValueKey('shared-media-state-${attachment.id}'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            if (isVideo && stateLabel == null)
              const Center(
                child: Icon(Icons.play_circle_outline_rounded, size: 30),
              ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                key: ValueKey('shared-media-bookmark-${attachment.id}'),
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: attachment.isBookmarked
                    ? l10n.shared_media_bookmark_remove
                    : l10n.shared_media_bookmark_add,
                icon: Icon(
                  attachment.isBookmarked
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                ),
                onPressed: () => _controller.toggleBookmark(attachment.id),
              ),
            ),
            if (selected)
              Positioned(
                left: 4,
                bottom: 4,
                child: Icon(
                  Icons.check_circle_rounded,
                  key: ValueKey('shared-media-selected-${attachment.id}'),
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Truthful non-renderable state text, or null when the stored bytes are
  /// present and displayable. Never triggers a download.
  String? _unavailableStateLabel(
    AppLocalizations l10n,
    MediaAttachment attachment,
  ) {
    final status = attachment.downloadStatus;
    if (status == kMediaDownloadStatusIntegrityFailed) {
      return l10n.shared_media_state_unverified;
    }
    if (status == kMediaDownloadStatusEvicted) {
      return l10n.shared_media_state_evicted;
    }
    if (status != kMediaDownloadStatusDone) {
      return l10n.shared_media_state_not_downloaded;
    }
    final storedPath = attachment.localPath;
    if (storedPath == null || storedPath.isEmpty) {
      return l10n.shared_media_state_missing;
    }
    if (!widget.fileExists(widget.resolveStoredPath(storedPath))) {
      return l10n.shared_media_state_missing;
    }
    return null;
  }
}

/// Hosts the plan-230 typed viewer over the library controller's entries:
/// appends the next scope/filter-bound page when the current item nears the
/// boundary (fenced by the controller) and routes current-item actions to
/// the injected coordinators.
class _SharedMediaViewerHost extends StatefulWidget {
  const _SharedMediaViewerHost({
    required this.screen,
    required this.controller,
    required this.initialAttachmentId,
    required this.confirmDelete,
  });

  final DirectSharedMediaLibraryScreen screen;
  final DirectMediaLibraryController controller;
  final String initialAttachmentId;
  final Future<bool> Function(int messageCount) confirmDelete;

  @override
  State<_SharedMediaViewerHost> createState() => _SharedMediaViewerHostState();
}

class _SharedMediaViewerHostState extends State<_SharedMediaViewerHost> {
  static const int _continuationThreshold = 3;

  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.controller.entries.indexWhere(
      (entry) => entry.attachment.id == widget.initialAttachmentId,
    );
    if (_currentIndex < 0) _currentIndex = 0;
    // Post-frame: the controller notifies synchronously when a load starts,
    // and initState runs during the route's first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeRequestContinuation();
    });
  }

  void _onPageChanged(int index) {
    _currentIndex = index;
    _maybeRequestContinuation();
  }

  /// Near the boundary, request ONE next page through the controller's
  /// scope/filter-bound cursor. The controller's in-flight fence coalesces
  /// duplicate boundary signals into a single request.
  void _maybeRequestContinuation() {
    final controller = widget.controller;
    if (!controller.hasMore) return;
    if (_currentIndex >= controller.entries.length - _continuationThreshold) {
      controller.loadNextPage();
    }
  }

  Future<MediaViewerActionResult> _onAction(
    MediaViewerItem item,
    MediaViewerAction action,
  ) async {
    final identity = DirectReceivedMediaActionIdentity(
      messageId: item.messageId,
      attachmentId: item.attachmentId,
    );
    switch (action) {
      case MediaViewerAction.save:
        final dispatch = widget.screen.dispatchEgress;
        if (dispatch == null) return MediaViewerActionResult.failure;
        final destination = await DirectMediaSaveDestinationSheet.show(
          context,
        );
        if (destination == null || !mounted) {
          return MediaViewerActionResult.cancelled;
        }
        return _egressResult(await dispatch([identity], destination), identity);
      case MediaViewerAction.share:
        final dispatch = widget.screen.dispatchEgress;
        if (dispatch == null) return MediaViewerActionResult.failure;
        return _egressResult(
          await dispatch([identity], MediaEgressDestination.share),
          identity,
        );
      case MediaViewerAction.bookmark:
        final toggled = await widget.controller.toggleBookmark(
          item.attachmentId,
        );
        return toggled
            ? MediaViewerActionResult.success
            : MediaViewerActionResult.failure;
      case MediaViewerAction.delete:
        final dispatch = widget.screen.dispatchDelete;
        if (dispatch == null) return MediaViewerActionResult.failure;
        final confirmed = await widget.confirmDelete(1);
        if (!confirmed || !mounted) return MediaViewerActionResult.cancelled;
        final outcome = await dispatch([identity]);
        if (!outcome.deletedMessageIds.contains(identity.messageId)) {
          // Missing/failed parent: a truthful failure with zero deletions —
          // never a synthesized parent.
          return MediaViewerActionResult.failure;
        }
        for (final messageId in outcome.deletedMessageIds) {
          widget.controller.removeEntriesForMessage(messageId);
        }
        widget.screen.onMessagesDeleted?.call(outcome.deletedMessageIds);
        if (mounted) Navigator.of(context).pop();
        return MediaViewerActionResult.success;
      case MediaViewerAction.forward:
      case MediaViewerAction.info:
      case MediaViewerAction.reply:
        // Not offered on the library surface (plan 232 owns Forward; Info/
        // Reply stay on the conversation surface).
        return MediaViewerActionResult.failure;
    }
  }

  MediaViewerActionResult _egressResult(
    DirectMediaLibraryBatchResult result,
    DirectReceivedMediaActionIdentity identity,
  ) {
    if (result.wasCancelled) return MediaViewerActionResult.cancelled;
    return result.succeededIds.contains(identity.attachmentId)
        ? MediaViewerActionResult.success
        : MediaViewerActionResult.failure;
  }

  MediaViewerItem _viewerItem(MediaLibraryEntry entry) {
    final screen = widget.screen;
    final attachment = entry.attachment;
    final storedPath = attachment.localPath;
    final resolved = storedPath == null || storedPath.isEmpty
        ? null
        : screen.resolveStoredPath(storedPath);
    final hasBytes = resolved != null && screen.fileExists(resolved);
    final kind = attachment.mediaType == 'video'
        ? MediaViewerKind.video
        : attachment.isAnimated
        ? MediaViewerKind.gif
        : MediaViewerKind.image;
    return MediaViewerItem(
      attachmentId: attachment.id,
      messageId: attachment.messageId,
      kind: kind,
      mime: attachment.mime,
      // Only a trusted direct owner is forwarded; anything else fails
      // closed as ownerless (action- and resume-ineligible).
      owner: attachment.ownerLane == MediaOwnerLane.direct
          ? MediaOwnerLane.direct
          : null,
      localPath: hasBytes ? resolved : null,
      sizeBytes: attachment.size,
      width: attachment.width,
      height: attachment.height,
      durationMs: attachment.durationMs,
      senderLabel: entry.parentSenderPeerId == screen.contactPeerId
          ? screen.contactUsername
          : null,
      timestamp: DateTime.tryParse(entry.parentTimestamp),
      protection: MediaViewerProtection(
        isDownloaded:
            attachment.downloadStatus == kMediaDownloadStatusDone && hasBytes,
        isIntegrityVerified:
            attachment.downloadStatus != kMediaDownloadStatusIntegrityFailed,
      ),
      capabilities: MediaViewerActionCapabilities(
        allowed: {
          if (screen.dispatchEgress != null) ...{
            MediaViewerAction.save,
            MediaViewerAction.share,
          },
          MediaViewerAction.bookmark,
          if (screen.dispatchDelete != null) MediaViewerAction.delete,
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
        return FullScreenTypedMediaViewer(
          items: [for (final entry in entries) _viewerItem(entry)],
          initialIndex: _currentIndex,
          onPageChanged: _onPageChanged,
          onAction: _onAction,
        );
      },
    );
  }
}
