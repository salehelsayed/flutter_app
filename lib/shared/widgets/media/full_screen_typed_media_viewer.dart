import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'ios_capture_protected_image.dart';
import 'media_picture_in_picture_controller.dart';
import 'media_playback_adapter.dart';
import 'media_video_controls.dart';
import 'media_video_resume_controller.dart';
import 'media_viewer_item.dart';

typedef MediaPictureInPictureAuthorizationLoader =
    Future<MediaPictureInPictureAuthorization?> Function(MediaViewerItem item);

typedef MediaPictureInPictureControllerFactory =
    MediaPictureInPictureController Function({
      required MediaPictureInPictureCurrentAuthorizer reloadCurrent,
      required MediaPictureInPictureRestorePlayback restorePlayback,
    });

enum _CompactVideoOverflowAction {
  save,
  share,
  info,
  reply,
  forward,
  pictureInPicture,
  delete,
}

/// 230: typed, callback-only full-screen media viewer.
///
/// Knows which received attachment is visible (stable id + owner lane), renders
/// only the actions the lane owner authorized, shows current-item metadata, and
/// provides accessible video controls with durable owner-aware resume. It is
/// transport-free: no [P2PService], bridge, relay, send/delete use case, or
/// message repository is imported here. Concrete per-lane action policies and
/// side effects live in plans 231-242; this viewer only invokes [onAction] with
/// the exact current item.
class FullScreenTypedMediaViewer extends StatefulWidget {
  const FullScreenTypedMediaViewer({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.onAction,
    this.onPageChanged,
    this.resumeStore,
    this.playbackAdapterFactory,
    this.pictureInPictureControllerFactory,
    this.loadPictureInPictureAuthorization,
    this.privacyMinimized = false,
    this.onFirstRenderedFrame,
    this.onPreFrameFailure,
    this.onPostFrameFailure,
    this.onBackRequested,
  }) : assert(
         (pictureInPictureControllerFactory == null) ==
             (loadPictureInPictureAuthorization == null),
         'PiP controller factory and authorization loader must be supplied together.',
       );

  final List<MediaViewerItem> items;
  final int initialIndex;

  /// Notified with the new current index after every page change (233: the
  /// shared-media library uses this to append the next page lazily near the
  /// viewer boundary). Purely observational — the viewer keeps its own
  /// current-item state either way.
  final ValueChanged<int>? onPageChanged;

  /// Invoked with the exact current item + action. Awaited once; the viewer
  /// never pops or mutates a chat optimistically on failure.
  final MediaViewerActionCallback? onAction;

  /// Owner-aware durable resume persistence (video only). Null disables resume.
  final MediaViewerResumeStore? resumeStore;

  /// Builds one playback adapter per video item. Tests inject fakes; production
  /// defaults to [defaultMediaPlaybackAdapterFactory].
  final MediaPlaybackAdapterFactory? playbackAdapterFactory;

  /// Route-owned PiP composition. The viewer owns the returned controller and
  /// supplies its exact current item plus the active video playback owner.
  /// Leaving either seam absent keeps PiP completely hidden.
  final MediaPictureInPictureControllerFactory?
  pictureInPictureControllerFactory;
  final MediaPictureInPictureAuthorizationLoader?
  loadPictureInPictureAuthorization;

  /// Dedicated private-route rendering mode. It suppresses every ordinary
  /// metadata/action/resume surface; the lane wrapper owns its generic safe
  /// controls and lifecycle callbacks.
  final bool privacyMinimized;

  /// For private routes, authorizes the first visible image frame or video
  /// playback. Decoding/initialization completes first, but content remains
  /// covered and video remains paused until this future returns true.
  final Future<bool> Function()? onFirstRenderedFrame;
  final VoidCallback? onPreFrameFailure;
  final VoidCallback? onPostFrameFailure;

  /// Optional route-owner back coordinator. Null preserves the ordinary
  /// viewer's direct Navigator pop; private owners use this to route the
  /// visible AppBar Back through their fail-closed PopScope.
  final Future<void> Function()? onBackRequested;

  @override
  State<FullScreenTypedMediaViewer> createState() =>
      _FullScreenTypedMediaViewerState();
}

class _FullScreenTypedMediaViewerState
    extends State<FullScreenTypedMediaViewer> {
  static const List<MediaViewerAction> _actionOrder = <MediaViewerAction>[
    MediaViewerAction.reply,
    MediaViewerAction.messageSender,
    MediaViewerAction.save,
    MediaViewerAction.share,
    MediaViewerAction.forward,
    MediaViewerAction.bookmark,
    MediaViewerAction.info,
    MediaViewerAction.delete,
  ];
  static const List<MediaViewerAction> _compactMenuOrder = <MediaViewerAction>[
    MediaViewerAction.save,
    MediaViewerAction.share,
    MediaViewerAction.info,
    MediaViewerAction.reply,
  ];
  static const List<_CompactVideoOverflowAction> _compactVideoMenuOrder =
      <_CompactVideoOverflowAction>[
        _CompactVideoOverflowAction.save,
        _CompactVideoOverflowAction.share,
        _CompactVideoOverflowAction.info,
        _CompactVideoOverflowAction.reply,
        _CompactVideoOverflowAction.forward,
        _CompactVideoOverflowAction.pictureInPicture,
        _CompactVideoOverflowAction.delete,
      ];
  static const double _compactTapExtent = 48;
  static const double _compactVisualExtent = 36;
  static const double _compactEdgeInset = 12;
  static const double _compactResultBottom =
      _compactEdgeInset + _compactTapExtent + _compactEdgeInset;

  late final PageController _pageController;
  late int _currentIndex;
  bool _dispatching = false;
  MediaViewerActionResult? _lastResult;
  bool _renderLifecycleSettled = false;
  bool _postFrameFailureReported = false;
  Future<bool>? _renderAuthorization;
  MediaPictureInPictureController? _pictureInPictureController;
  final Map<String, GlobalKey<_TypedVideoPageState>> _videoPageKeys = {};
  bool _pictureInPictureVisible = false;
  bool _pictureInPictureRequestInFlight = false;
  int _pictureInPictureRefreshGeneration = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    final factory = widget.pictureInPictureControllerFactory;
    if (!widget.privacyMinimized && factory != null) {
      _pictureInPictureController = factory(
        reloadCurrent: _loadCurrentPictureInPictureAuthorization,
        restorePlayback: _restorePictureInPicturePlayback,
      );
      unawaited(_refreshPictureInPictureVisibility());
    }
  }

  @override
  void didUpdateWidget(FullScreenTypedMediaViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentIndex >= widget.items.length) {
      _currentIndex = widget.items.length - 1;
    }
    _videoPageKeys.removeWhere(
      (identity, _) => !widget.items.any(
        (item) => item.isVideo && _pictureInPictureIdentity(item) == identity,
      ),
    );
    unawaited(_refreshPictureInPictureVisibility());
  }

  @override
  void dispose() {
    _pictureInPictureRefreshGeneration++;
    final controller = _pictureInPictureController;
    if (controller != null) unawaited(controller.dispose());
    _pageController.dispose();
    super.dispose();
  }

  MediaViewerItem get _currentItem => widget.items[_currentIndex];

  String _pictureInPictureIdentity(MediaViewerItem item) =>
      '${item.owner?.dbValue ?? 'none'}:${item.messageId}:${item.attachmentId}';

  GlobalKey<_TypedVideoPageState> _videoPageKey(MediaViewerItem item) =>
      _videoPageKeys.putIfAbsent(
        _pictureInPictureIdentity(item),
        () => GlobalKey<_TypedVideoPageState>(
          debugLabel: 'typed-video-${item.attachmentId}',
        ),
      );

  Future<MediaPictureInPictureAuthorization?>
  _loadCurrentPictureInPictureAuthorization() {
    final loader = widget.loadPictureInPictureAuthorization;
    if (loader == null || widget.privacyMinimized) {
      return Future.value(null);
    }
    return loader(_currentItem);
  }

  Future<void> _refreshPictureInPictureVisibility() async {
    final generation = ++_pictureInPictureRefreshGeneration;
    final controller = _pictureInPictureController;
    final loader = widget.loadPictureInPictureAuthorization;
    final item = _currentItem;
    if (controller == null ||
        loader == null ||
        widget.privacyMinimized ||
        !item.isVideo ||
        !item.canEnterPictureInPicture ||
        !item.isActionEligible) {
      if (mounted && generation == _pictureInPictureRefreshGeneration) {
        setState(() => _pictureInPictureVisible = false);
      }
      return;
    }

    // Platform capability is checked first. Therefore iOS/other platforms do
    // not even load media authority, much less pause or dispose Flutter video.
    final capability = await controller.capability();
    if (!mounted || generation != _pictureInPictureRefreshGeneration) return;
    if (!capability.isVisible || !capability.isSupported) {
      setState(() => _pictureInPictureVisible = false);
      return;
    }

    MediaPictureInPictureAuthorization? authorization;
    try {
      authorization = await loader(item);
    } catch (_) {
      authorization = null;
    }
    if (!mounted || generation != _pictureInPictureRefreshGeneration) return;
    final isAllowed =
        authorization != null &&
        _pictureInPictureIdentity(authorization.item) ==
            _pictureInPictureIdentity(item) &&
        MediaPictureInPicturePolicy.evaluate(authorization).isAllowed;
    setState(() => _pictureInPictureVisible = isAllowed);
  }

  Future<void> _requestPictureInPicture() async {
    if (_pictureInPictureRequestInFlight || !_pictureInPictureVisible) return;
    final controller = _pictureInPictureController;
    final loader = widget.loadPictureInPictureAuthorization;
    final item = _currentItem;
    final page = _videoPageKeys[_pictureInPictureIdentity(item)]?.currentState;
    if (controller == null ||
        loader == null ||
        page == null ||
        !page.canStartPictureInPicture) {
      return;
    }
    setState(() => _pictureInPictureRequestInFlight = true);
    MediaPictureInPictureAuthorization? authorization;
    try {
      authorization = await loader(item);
    } catch (_) {
      authorization = null;
    }
    if (!mounted) return;
    if (authorization == null ||
        _pictureInPictureIdentity(authorization.item) !=
            _pictureInPictureIdentity(item) ||
        !MediaPictureInPicturePolicy.evaluate(authorization).isAllowed) {
      setState(() {
        _pictureInPictureRequestInFlight = false;
        _pictureInPictureVisible = false;
      });
      _showPictureInPictureStartFailure();
      return;
    }
    MediaPictureInPictureStartOutcome? outcome;
    try {
      outcome = await page.startPictureInPicture(controller, authorization);
    } catch (_) {
      outcome = null;
    }
    if (!mounted) return;
    final startFailed =
        outcome == null ||
        outcome == MediaPictureInPictureStartOutcome.denied ||
        outcome == MediaPictureInPictureStartOutcome.nativeRejected;
    final becameHidden = outcome == MediaPictureInPictureStartOutcome.hidden;
    setState(() {
      _pictureInPictureRequestInFlight = false;
      if (startFailed || becameHidden) _pictureInPictureVisible = false;
    });
    if (startFailed) {
      _showPictureInPictureStartFailure();
    } else if (!becameHidden) {
      unawaited(_refreshPictureInPictureVisibility());
    }
  }

  void _showPictureInPictureStartFailure() {
    if (!mounted) return;
    final message = AppLocalizations.of(
      context,
    )!.media_viewer_picture_in_picture_start_failed;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Semantics(
          key: const ValueKey('media_picture_in_picture_start_failure'),
          container: true,
          liveRegion: true,
          label: message,
          excludeSemantics: true,
          child: Text(message),
        ),
      ),
    );
  }

  Future<void> _restorePictureInPicturePlayback(
    MediaPictureInPictureRestore restore,
  ) async {
    final identity = _pictureInPictureIdentity(restore.item);
    if (!mounted || identity != _pictureInPictureIdentity(_currentItem)) return;
    final page = _videoPageKeys[identity]?.currentState;
    if (page == null) return;
    await page.restorePictureInPicturePlayback(restore);
    if (mounted) unawaited(_refreshPictureInPictureVisibility());
  }

  void _onVideoPlaybackStateChanged() {
    if (mounted) setState(() {});
  }

  Future<bool> _reportFirstRenderedFrame() {
    if (_renderLifecycleSettled) return Future<bool>.value(false);
    return _renderAuthorization ??= () async {
      var accepted = false;
      try {
        accepted = await widget.onFirstRenderedFrame!.call();
      } catch (_) {
        accepted = false;
        _reportPostFrameFailure();
      }
      _renderLifecycleSettled = true;
      return accepted;
    }();
  }

  void _reportPreFrameFailure() {
    if (_renderLifecycleSettled) return;
    _renderLifecycleSettled = true;
    widget.onPreFrameFailure?.call();
  }

  void _reportPostFrameFailure() {
    if (_postFrameFailureReported) return;
    _postFrameFailureReported = true;
    widget.onPostFrameFailure?.call();
  }

  Future<void> _dispatch(MediaViewerAction action) async {
    if (_dispatching) return;
    // Recheck the EXACT current item + owner immediately before dispatch.
    final item = _currentItem;
    if (!item.canDispatch(action)) return;
    final callback = widget.onAction;
    if (callback == null) return;

    setState(() => _dispatching = true);
    MediaViewerActionResult result;
    try {
      result = await callback(item, action);
    } catch (_) {
      result = MediaViewerActionResult.failure;
    }
    _emitActionDiagnostic(item, action, result.status);
    if (!mounted) return;
    setState(() {
      _dispatching = false;
      _lastResult = result;
    });
  }

  void _emitActionDiagnostic(
    MediaViewerItem item,
    MediaViewerAction action,
    MediaViewerActionStatus status,
  ) {
    final id = item.attachmentId;
    final shortId = id.length > 8 ? id.substring(0, 8) : id;
    // Redacted by construction: only stable short IDs + outcomes, never a
    // path, caption, sender label, or the item's toString().
    emitFlowEvent(
      layer: 'UI',
      event: 'MEDIA_VIEWER_ACTION',
      details: <String, dynamic>{
        'attachmentId': shortId,
        'action': action.name,
        'outcome': status.name,
        'owner': item.owner?.dbValue ?? 'none',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = widget.items;
    final showIndicator = items.length > 1;
    final current = _currentItem;
    final compactImageActions =
        current.actionPresentation ==
        MediaViewerActionPresentation.compactImageOverlay;
    final compactVideoActions =
        current.actionPresentation ==
        MediaViewerActionPresentation.compactVideoOverflow;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onBackRequested == null
              ? () => Navigator.of(context).pop()
              : () => unawaited(widget.onBackRequested!()),
        ),
        title: showIndicator
            ? Text(
                '${_currentIndex + 1} / ${items.length}',
                key: const ValueKey('media_viewer_page_position'),
                style: const TextStyle(
                  color: Color.fromRGBO(255, 255, 255, 0.7),
                  fontSize: 14,
                ),
              )
            : null,
        centerTitle: true,
        actions: widget.privacyMinimized
            ? const <Widget>[]
            : <Widget>[
                if (_pictureInPictureVisible && !compactVideoActions)
                  IconButton(
                    key: const ValueKey('media_action_picture_in_picture'),
                    tooltip: l10n.media_viewer_action_picture_in_picture,
                    color: Colors.white,
                    icon: const Icon(Icons.picture_in_picture_alt_rounded),
                    onPressed:
                        !_pictureInPictureRequestInFlight &&
                            (_videoPageKeys[_pictureInPictureIdentity(current)]
                                    ?.currentState
                                    ?.canStartPictureInPicture ??
                                false)
                        ? _requestPictureInPicture
                        : null,
                  ),
                ...(compactImageActions
                    ? _buildCompactTopActions(l10n, current)
                    : compactVideoActions
                    ? _buildCompactVideoTopActions(l10n, current)
                    : _buildActions(l10n, current)),
              ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: items.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
                _pictureInPictureVisible = false;
              });
              widget.onPageChanged?.call(index);
              unawaited(_refreshPictureInPictureVisibility());
            },
            itemBuilder: (context, index) => _buildPage(items[index], index),
          ),
          if (!widget.privacyMinimized)
            Positioned(
              top: MediaQuery.of(context).padding.top + kToolbarHeight,
              left: 0,
              right: 0,
              child: _MediaViewerMetadata(item: current),
            ),
          if (!widget.privacyMinimized && compactImageActions)
            _buildCompactBottomActions(l10n, current),
          if (_lastResult != null)
            if (!widget.privacyMinimized && compactImageActions)
              PositionedDirectional(
                end: _compactEdgeInset,
                bottom:
                    MediaQuery.of(context).padding.bottom +
                    _compactResultBottom,
                child: _MediaViewerActionResultChip(result: _lastResult!),
              )
            else
              Positioned(
                right: 16,
                bottom: 16,
                child: _MediaViewerActionResultChip(result: _lastResult!),
              ),
        ],
      ),
    );
  }

  List<Widget> _buildActions(AppLocalizations l10n, MediaViewerItem item) {
    final actions = <Widget>[];
    for (final action in _actionOrder) {
      // Unauthorized capabilities are absent (never merely disabled).
      if (!item.capabilities.allows(action)) continue;
      // Present-but-ineligible (unresolved owner / unavailable / protected) or
      // an in-flight dispatch renders disabled — fail closed.
      final enabled = item.isActionEligible && !_dispatching;
      actions.add(
        IconButton(
          key: ValueKey('media_action_${action.name}'),
          tooltip: _actionTooltip(l10n, action),
          color: Colors.white,
          icon: Icon(_actionIcon(action)),
          onPressed: enabled ? () => _dispatch(action) : null,
        ),
      );
    }
    return actions;
  }

  List<Widget> _buildCompactTopActions(
    AppLocalizations l10n,
    MediaViewerItem item,
  ) {
    if (widget.onAction == null) return const <Widget>[];
    final actions = _compactMenuOrder
        .where(item.capabilities.allows)
        .toList(growable: false);
    if (actions.isEmpty) return const <Widget>[];
    final enabled = item.isActionEligible && !_dispatching;
    return <Widget>[
      Padding(
        padding: const EdgeInsetsDirectional.only(end: _compactEdgeInset),
        child: SizedBox.square(
          dimension: _compactTapExtent,
          child: PopupMenuButton<MediaViewerAction>(
            key: const ValueKey('media_action_more'),
            tooltip: l10n.media_viewer_more_actions,
            enabled: enabled,
            padding: EdgeInsets.zero,
            position: PopupMenuPosition.under,
            color: const Color(0xFF1C1C1E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0x66FFFFFF)),
            ),
            onSelected: (action) => unawaited(_dispatch(action)),
            itemBuilder: (context) => [
              for (final action in actions)
                PopupMenuItem<MediaViewerAction>(
                  key: ValueKey('media_action_${action.name}'),
                  value: action,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_actionIcon(action), size: 20, color: Colors.white),
                      const SizedBox(width: 12),
                      Text(
                        _compactActionLabel(l10n, action),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
            ],
            child: Center(
              child: _compactActionVisual(
                name: 'more',
                icon: Icons.more_horiz_rounded,
                enabled: enabled,
              ),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildCompactVideoTopActions(
    AppLocalizations l10n,
    MediaViewerItem item,
  ) {
    final actions = _compactVideoMenuOrder
        .where((action) {
          final mediaAction = _compactVideoMediaAction(action);
          if (mediaAction != null) {
            return widget.onAction != null &&
                item.capabilities.allows(mediaAction);
          }
          return _pictureInPictureVisible;
        })
        .toList(growable: false);
    if (actions.isEmpty) return const <Widget>[];

    final mediaEnabled =
        widget.onAction != null && item.isActionEligible && !_dispatching;
    final page = _videoPageKeys[_pictureInPictureIdentity(item)]?.currentState;
    final pictureInPictureEnabled =
        _pictureInPictureVisible &&
        !_pictureInPictureRequestInFlight &&
        (page?.canStartPictureInPicture ?? false);
    final enabled = item.isActionEligible && !_dispatching;

    return <Widget>[
      Padding(
        padding: const EdgeInsetsDirectional.only(end: _compactEdgeInset),
        child: SizedBox.square(
          dimension: _compactTapExtent,
          child: PopupMenuButton<_CompactVideoOverflowAction>(
            key: const ValueKey('media_action_more'),
            tooltip: l10n.media_viewer_more_actions,
            enabled: enabled,
            padding: EdgeInsets.zero,
            position: PopupMenuPosition.under,
            color: const Color(0xFF1C1C1E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0x66FFFFFF)),
            ),
            onSelected: (action) {
              final mediaAction = _compactVideoMediaAction(action);
              if (mediaAction != null) {
                unawaited(_dispatch(mediaAction));
              } else {
                unawaited(_requestPictureInPicture());
              }
            },
            itemBuilder: (context) => [
              for (final action in actions)
                PopupMenuItem<_CompactVideoOverflowAction>(
                  key: ValueKey(
                    'media_action_${_compactVideoActionName(action)}',
                  ),
                  value: action,
                  enabled:
                      action == _CompactVideoOverflowAction.pictureInPicture
                      ? pictureInPictureEnabled
                      : mediaEnabled,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _compactVideoActionIcon(action),
                        size: 20,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          _compactVideoActionLabel(l10n, action),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            child: Center(
              child: _compactActionVisual(
                name: 'more',
                icon: Icons.more_horiz_rounded,
                enabled: enabled,
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildCompactBottomActions(
    AppLocalizations l10n,
    MediaViewerItem item,
  ) {
    if (widget.onAction == null) return const SizedBox.shrink();
    final controls = <Widget>[];
    for (final entry
        in const <({MediaViewerAction action, AlignmentGeometry alignment})>[
          (
            action: MediaViewerAction.forward,
            alignment: AlignmentDirectional.bottomEnd,
          ),
          (
            action: MediaViewerAction.delete,
            alignment: AlignmentDirectional.bottomStart,
          ),
        ]) {
      if (!item.capabilities.allows(entry.action)) continue;
      controls.add(
        Align(
          alignment: entry.alignment,
          child: _compactActionButton(l10n, item, entry.action),
        ),
      );
    }
    if (controls.isEmpty) return const SizedBox.shrink();
    return Positioned.fill(
      child: SafeArea(
        minimum: const EdgeInsets.all(_compactEdgeInset),
        child: Stack(children: controls),
      ),
    );
  }

  Widget _compactActionButton(
    AppLocalizations l10n,
    MediaViewerItem item,
    MediaViewerAction action,
  ) {
    final enabled = item.isActionEligible && !_dispatching;
    return SizedBox.square(
      dimension: _compactTapExtent,
      child: IconButton(
        key: ValueKey('media_action_${action.name}'),
        tooltip: _actionTooltip(l10n, action),
        padding: const EdgeInsets.all(
          (_compactTapExtent - _compactVisualExtent) / 2,
        ),
        constraints: const BoxConstraints.tightFor(
          width: _compactTapExtent,
          height: _compactTapExtent,
        ),
        onPressed: enabled ? () => unawaited(_dispatch(action)) : null,
        icon: _compactActionVisual(
          name: action.name,
          icon: _actionIcon(action),
          enabled: enabled,
        ),
      ),
    );
  }

  Widget _compactActionVisual({
    required String name,
    required IconData icon,
    required bool enabled,
  }) {
    return Container(
      key: ValueKey('media_action_${name}_visual'),
      width: _compactVisualExtent,
      height: _compactVisualExtent,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled ? const Color(0xCC1C1C1E) : const Color(0x661C1C1E),
        shape: BoxShape.circle,
        border: Border.all(
          color: enabled ? const Color(0x66FFFFFF) : const Color(0x33FFFFFF),
        ),
      ),
      child: Icon(
        icon,
        size: 20,
        color: enabled ? Colors.white : Colors.white38,
      ),
    );
  }

  Widget _buildPage(MediaViewerItem item, int index) {
    final isActive = index == _currentIndex;
    switch (item.kind) {
      case MediaViewerKind.video:
        return _TypedVideoPage(
          key: _videoPageKey(item),
          item: item,
          isActive: isActive,
          adapterFactory:
              widget.playbackAdapterFactory ??
              defaultMediaPlaybackAdapterFactory,
          resumeStore: widget.privacyMinimized ? null : widget.resumeStore,
          showControls: !widget.privacyMinimized,
          onFirstRenderedFrame: widget.onFirstRenderedFrame == null
              ? null
              : _reportFirstRenderedFrame,
          onPreFrameFailure: _reportPreFrameFailure,
          onPlaybackStateChanged: _onVideoPlaybackStateChanged,
        );
      case MediaViewerKind.image:
        return _TypedImagePage(
          item: item,
          captureProtected:
              widget.privacyMinimized &&
              defaultTargetPlatform == TargetPlatform.iOS,
          onFirstRenderedFrame: widget.onFirstRenderedFrame == null
              ? null
              : _reportFirstRenderedFrame,
          onPreFrameFailure: _reportPreFrameFailure,
          onPostFrameFailure: _reportPostFrameFailure,
        );
      case MediaViewerKind.gif:
        return _TypedImagePage(
          item: item,
          // ImageIO renders the first GIF frame through the same protected
          // native surface. A static preview is safer than leaking animation
          // pixels through Flutter's ordinary image compositor.
          captureProtected:
              widget.privacyMinimized &&
              defaultTargetPlatform == TargetPlatform.iOS,
          onFirstRenderedFrame: widget.onFirstRenderedFrame == null
              ? null
              : _reportFirstRenderedFrame,
          onPreFrameFailure: _reportPreFrameFailure,
          onPostFrameFailure: _reportPostFrameFailure,
        );
    }
  }
}

MediaViewerAction? _compactVideoMediaAction(
  _CompactVideoOverflowAction action,
) {
  switch (action) {
    case _CompactVideoOverflowAction.save:
      return MediaViewerAction.save;
    case _CompactVideoOverflowAction.share:
      return MediaViewerAction.share;
    case _CompactVideoOverflowAction.info:
      return MediaViewerAction.info;
    case _CompactVideoOverflowAction.reply:
      return MediaViewerAction.reply;
    case _CompactVideoOverflowAction.forward:
      return MediaViewerAction.forward;
    case _CompactVideoOverflowAction.pictureInPicture:
      return null;
    case _CompactVideoOverflowAction.delete:
      return MediaViewerAction.delete;
  }
}

String _compactVideoActionName(_CompactVideoOverflowAction action) {
  if (action == _CompactVideoOverflowAction.pictureInPicture) {
    return 'picture_in_picture';
  }
  return _compactVideoMediaAction(action)!.name;
}

IconData _compactVideoActionIcon(_CompactVideoOverflowAction action) {
  if (action == _CompactVideoOverflowAction.pictureInPicture) {
    return Icons.picture_in_picture_alt_rounded;
  }
  return _actionIcon(_compactVideoMediaAction(action)!);
}

String _compactVideoActionLabel(
  AppLocalizations l10n,
  _CompactVideoOverflowAction action,
) {
  if (action == _CompactVideoOverflowAction.pictureInPicture) {
    return l10n.media_viewer_action_picture_in_picture;
  }
  return _actionTooltip(l10n, _compactVideoMediaAction(action)!);
}

IconData _actionIcon(MediaViewerAction action) {
  switch (action) {
    case MediaViewerAction.save:
      return Icons.download_rounded;
    case MediaViewerAction.share:
      return Icons.ios_share_rounded;
    case MediaViewerAction.forward:
      return Icons.forward_rounded;
    case MediaViewerAction.bookmark:
      return Icons.bookmark_border_rounded;
    case MediaViewerAction.info:
      return Icons.info_outline_rounded;
    case MediaViewerAction.reply:
      return Icons.reply_rounded;
    case MediaViewerAction.messageSender:
      return Icons.chat_bubble_outline_rounded;
    case MediaViewerAction.delete:
      return Icons.delete_outline_rounded;
  }
}

String _actionTooltip(AppLocalizations l10n, MediaViewerAction action) {
  switch (action) {
    case MediaViewerAction.save:
      return l10n.media_viewer_action_save;
    case MediaViewerAction.share:
      return l10n.media_viewer_action_share;
    case MediaViewerAction.forward:
      return l10n.media_viewer_action_forward;
    case MediaViewerAction.bookmark:
      return l10n.media_viewer_action_bookmark;
    case MediaViewerAction.info:
      return l10n.media_viewer_action_info;
    case MediaViewerAction.reply:
      return l10n.media_viewer_action_reply;
    case MediaViewerAction.messageSender:
      return l10n.announcement_private_reply_action;
    case MediaViewerAction.delete:
      return l10n.media_viewer_action_delete;
  }
}

String _compactActionLabel(AppLocalizations l10n, MediaViewerAction action) {
  if (action == MediaViewerAction.save) {
    return l10n.media_viewer_action_save_image;
  }
  return _actionTooltip(l10n, action);
}

/// Current-item metadata: sender, timestamp, caption, MIME/type, byte size, and
/// image dimensions or video duration. Never renders the local path.
class _MediaViewerMetadata extends StatelessWidget {
  const _MediaViewerMetadata({required this.item});

  final MediaViewerItem item;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Colors.white, fontSize: 13);
    const subStyle = TextStyle(
      color: Color.fromRGBO(255, 255, 255, 0.7),
      fontSize: 12,
    );

    final children = <Widget>[];
    if (item.showMetadataDetails) {
      if (item.senderLabel != null) {
        children.add(
          Text(
            item.senderLabel!,
            key: const ValueKey('media_meta_sender'),
            style: style,
          ),
        );
      }
      if (item.timestamp != null) {
        children.add(
          Text(
            _formatTimestamp(item.timestamp!),
            key: const ValueKey('media_meta_timestamp'),
            style: subStyle,
          ),
        );
      }
    }
    if (item.caption != null && item.caption!.isNotEmpty) {
      children.add(
        Text(
          item.caption!,
          key: const ValueKey('media_meta_caption'),
          style: style,
        ),
      );
    }

    if (item.showMetadataDetails) {
      final info = <Widget>[
        Text(
          item.mime,
          key: const ValueKey('media_meta_mime'),
          style: subStyle,
        ),
        if (item.sizeBytes != null)
          Text(
            _formatBytes(item.sizeBytes!),
            key: const ValueKey('media_meta_size'),
            style: subStyle,
          ),
        if (item.isVideo && item.durationMs != null)
          Text(
            _formatDurationMs(item.durationMs!),
            key: const ValueKey('media_meta_duration'),
            style: subStyle,
          ),
        if (!item.isVideo && item.width != null && item.height != null)
          Text(
            _formatDimensions(item.width!, item.height!),
            key: const ValueKey('media_meta_dimensions'),
            style: subStyle,
          ),
      ];
      children.add(Wrap(spacing: 10, runSpacing: 2, children: info));
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey('media_viewer_metadata_content'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _MediaViewerActionResultChip extends StatelessWidget {
  const _MediaViewerActionResultChip({required this.result});

  final MediaViewerActionResult result;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    switch (result.status) {
      case MediaViewerActionStatus.success:
        icon = Icons.check_circle_rounded;
        break;
      case MediaViewerActionStatus.cancelled:
        icon = Icons.cancel_rounded;
        break;
      case MediaViewerActionStatus.failure:
        icon = Icons.error_rounded;
        break;
    }
    return Container(
      key: ValueKey('media_action_result_${result.status.name}'),
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Color.fromRGBO(0, 0, 0, 0.55),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }
}

class _TypedImagePage extends StatefulWidget {
  const _TypedImagePage({
    required this.item,
    required this.captureProtected,
    required this.onFirstRenderedFrame,
    required this.onPreFrameFailure,
    required this.onPostFrameFailure,
  });

  final MediaViewerItem item;
  final bool captureProtected;
  final Future<bool> Function()? onFirstRenderedFrame;
  final VoidCallback onPreFrameFailure;
  final VoidCallback onPostFrameFailure;

  @override
  State<_TypedImagePage> createState() => _TypedImagePageState();
}

class _TypedImagePageState extends State<_TypedImagePage> {
  bool _authorizationStarted = false;
  bool _revealed = false;

  Future<void> _authorizeReveal() async {
    if (_authorizationStarted) return;
    _authorizationStarted = true;
    final authorize = widget.onFirstRenderedFrame;
    if (authorize == null) {
      if (mounted) setState(() => _revealed = true);
      return;
    }
    final accepted = await authorize();
    if (accepted && mounted) setState(() => _revealed = true);
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.item.localPath;
    if (path == null) {
      if (!_authorizationStarted) {
        _authorizationStarted = true;
        scheduleMicrotask(widget.onPreFrameFailure);
      }
      return const Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 48,
          color: Color.fromRGBO(255, 255, 255, 0.25),
        ),
      );
    }
    if (widget.captureProtected) {
      return InteractiveViewer(
        child: SizedBox.expand(
          child: IosCaptureProtectedImage(
            key: ValueKey(
              'ios-private-image:${widget.item.owner?.dbValue ?? 'none'}:'
              '${widget.item.messageId}:${widget.item.attachmentId}',
            ),
            path: path,
            onFirstRenderedFrame: widget.onFirstRenderedFrame,
            onPreFrameFailure: widget.onPreFrameFailure,
            onPostFrameFailure: widget.onPostFrameFailure,
          ),
        ),
      );
    }
    return InteractiveViewer(
      child: Center(
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame != null || wasSynchronouslyLoaded) {
              scheduleMicrotask(_authorizeReveal);
            }
            if (widget.onFirstRenderedFrame == null || _revealed) return child;
            return const ColoredBox(
              key: ValueKey('typed-image-prereveal-cover'),
              color: Colors.black,
            );
          },
          errorBuilder: (context, error, stackTrace) {
            scheduleMicrotask(widget.onPreFrameFailure);
            return const Icon(
              Icons.broken_image_outlined,
              size: 48,
              color: Color.fromRGBO(255, 255, 255, 0.25),
            );
          },
        ),
      ),
    );
  }
}

class _TypedVideoPage extends StatefulWidget {
  const _TypedVideoPage({
    super.key,
    required this.item,
    required this.isActive,
    required this.adapterFactory,
    required this.showControls,
    required this.onFirstRenderedFrame,
    required this.onPreFrameFailure,
    required this.onPlaybackStateChanged,
    this.resumeStore,
  });

  final MediaViewerItem item;
  final bool isActive;
  final MediaPlaybackAdapterFactory adapterFactory;
  final MediaViewerResumeStore? resumeStore;
  final bool showControls;
  final Future<bool> Function()? onFirstRenderedFrame;
  final VoidCallback onPreFrameFailure;
  final VoidCallback onPlaybackStateChanged;

  @override
  State<_TypedVideoPage> createState() => _TypedVideoPageState();
}

class _TypedVideoPageState extends State<_TypedVideoPage>
    with WidgetsBindingObserver {
  late MediaPlaybackAdapter _adapter;
  late MediaVideoResumeController _resume;
  late MediaViewerItem _playbackItem;
  bool _initialized = false;
  bool _ownsPlaybackAdapter = true;
  bool _pictureInPictureTransferPending = false;
  Object? _error;
  bool _surfaceFrameScheduled = false;
  bool _failureReported = false;
  bool _revealAuthorized = false;
  int _adapterGeneration = 0;

  bool get canStartPictureInPicture =>
      widget.isActive &&
      _ownsPlaybackAdapter &&
      !_pictureInPictureTransferPending &&
      _initialized &&
      _error == null &&
      _adapter.isInitialized;

  @override
  void initState() {
    super.initState();
    _installPlaybackOwner(widget.item);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize(_adapterGeneration));
  }

  void _installPlaybackOwner(MediaViewerItem item) {
    _adapterGeneration++;
    _playbackItem = item;
    _adapter = widget.adapterFactory(item);
    _resume = MediaVideoResumeController(
      item: item,
      adapter: _adapter,
      store: widget.resumeStore,
    );
    _ownsPlaybackAdapter = true;
    _initialized = false;
    _error = null;
    _surfaceFrameScheduled = false;
  }

  Future<void> _initialize(
    int generation, {
    MediaPictureInPictureRestore? restore,
  }) async {
    final adapter = _adapter;
    final resume = _resume;
    try {
      await adapter.initialize();
      if (!mounted ||
          generation != _adapterGeneration ||
          !identical(adapter, _adapter)) {
        await adapter.dispose();
        return;
      }
      adapter.addListener(_onAdapterTick);
      setState(() {
        _initialized = true;
        _pictureInPictureTransferPending = false;
      });
      widget.onPlaybackStateChanged();
      // Never start a non-current page.
      if (widget.isActive) {
        if (restore == null) {
          await resume.restore();
        } else {
          final durationMs = adapter.duration.inMilliseconds;
          final boundedPosition = durationMs > 0
              ? restore.positionMs.clamp(0, durationMs)
              : restore.positionMs.clamp(0, 0x7fffffff);
          await adapter.seekTo(Duration(milliseconds: boundedPosition));
        }
        if (!mounted || generation != _adapterGeneration) return;
        if (restore?.shouldPlay == true ||
            (restore == null && widget.onFirstRenderedFrame == null)) {
          await adapter.play();
        }
      }
    } catch (error) {
      if (!mounted || generation != _adapterGeneration) return;
      // Initialization failure pauses/keeps the owned controller idle; it must
      // never auto-play.
      setState(() => _error = error);
      widget.onPreFrameFailure();
      widget.onPlaybackStateChanged();
    }
  }

  Future<MediaPictureInPictureStartOutcome> startPictureInPicture(
    MediaPictureInPictureController controller,
    MediaPictureInPictureAuthorization authorization,
  ) async {
    if (!canStartPictureInPicture ||
        _pictureInPictureIdentityForItem(authorization.item) !=
            _pictureInPictureIdentityForItem(_playbackItem)) {
      return MediaPictureInPictureStartOutcome.denied;
    }
    final transferredAdapter = _adapter;
    setState(() => _pictureInPictureTransferPending = true);
    widget.onPlaybackStateChanged();
    late final MediaPictureInPictureStartOutcome outcome;
    try {
      outcome = await controller.start(
        authorization: authorization,
        playback: transferredAdapter,
      );
    } catch (_) {
      if (mounted && identical(_adapter, transferredAdapter)) {
        setState(() => _pictureInPictureTransferPending = false);
        widget.onPlaybackStateChanged();
      }
      rethrow;
    }
    if (!mounted) return outcome;

    // A synchronous native rejection can recreate Flutter playback through
    // [restorePictureInPicturePlayback] before start returns. Only detach the
    // adapter when this is still the exact owner that was handed off.
    if (identical(_adapter, transferredAdapter)) {
      if (outcome == MediaPictureInPictureStartOutcome.started) {
        try {
          transferredAdapter.removeListener(_onAdapterTick);
        } catch (_) {}
        setState(() {
          _ownsPlaybackAdapter = false;
          _initialized = false;
          _pictureInPictureTransferPending = false;
        });
      } else {
        setState(() => _pictureInPictureTransferPending = false);
      }
      widget.onPlaybackStateChanged();
    }
    return outcome;
  }

  Future<void> restorePictureInPicturePlayback(
    MediaPictureInPictureRestore restore,
  ) async {
    if (_pictureInPictureIdentityForItem(restore.item) !=
        _pictureInPictureIdentityForItem(widget.item)) {
      return;
    }
    final previous = _adapter;
    try {
      previous.removeListener(_onAdapterTick);
    } catch (_) {}
    _installPlaybackOwner(restore.item);
    _pictureInPictureTransferPending = true;
    if (mounted) setState(() {});
    widget.onPlaybackStateChanged();
    await _initialize(_adapterGeneration, restore: restore);
  }

  String _pictureInPictureIdentityForItem(MediaViewerItem item) =>
      '${item.owner?.dbValue ?? 'none'}:${item.messageId}:${item.attachmentId}';

  void _onAdapterTick() {
    final runtimeError = _adapter.initializationError;
    if (runtimeError != null) {
      _handleSurfaceFailure(runtimeError);
      return;
    }
    _resume.onTick();
    if (mounted) setState(() {});
  }

  void _handleSurfaceFailure(Object error) {
    if (_error != null) return;
    if (mounted) {
      setState(() => _error = error);
    } else {
      _error = error;
    }
    if (!_failureReported) {
      _failureReported = true;
      widget.onPreFrameFailure();
    }
    widget.onPlaybackStateChanged();
  }

  Future<void> _authorizeRevealAndPlayback() async {
    final authorize = widget.onFirstRenderedFrame;
    if (authorize == null || _revealAuthorized || !mounted) return;
    final accepted = await authorize();
    if (!accepted || !mounted || _error != null) return;
    if (widget.isActive) await _adapter.play();
    if (mounted) setState(() => _revealAuthorized = true);
  }

  @override
  void didUpdateWidget(_TypedVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) return;
    // The parent app bar rebuild that changes the current index runs before
    // this child receives its new [isActive] value. Notify it once after this
    // frame so a ready newly-current playback owner can enable PiP without
    // weakening the exact-current page gate.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onPlaybackStateChanged();
    });
    if (!_initialized || _error != null) return;
    if (widget.isActive) {
      _resume.restore();
      if (widget.onFirstRenderedFrame == null || _revealAuthorized) {
        _adapter.play();
      }
    } else {
      _resume.flush();
      _adapter.pause();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.isActive || !_initialized || _error != null) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _resume.flush();
        _adapter.pause();
        break;
      case AppLifecycleState.resumed:
        // Foreground alone does not auto-play.
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _adapterGeneration++;
    if (_ownsPlaybackAdapter) {
      _adapter.removeListener(_onAdapterTick);
      _resume.flush();
      _adapter.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _buildError(context);
    }
    if (_pictureInPictureTransferPending || !_ownsPlaybackAdapter) {
      return const ColoredBox(color: Colors.black);
    }
    if (!_initialized || !_adapter.isInitialized) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white70,
          ),
        ),
      );
    }
    final Widget surface;
    try {
      surface = _adapter.buildSurface();
    } catch (error) {
      scheduleMicrotask(() => _handleSurfaceFailure(error));
      return _buildError(context);
    }
    final runtimeError = _adapter.initializationError;
    if (runtimeError != null) {
      scheduleMicrotask(() => _handleSurfaceFailure(runtimeError));
      return _buildError(context);
    }
    if (!_surfaceFrameScheduled && widget.onFirstRenderedFrame != null) {
      _surfaceFrameScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _initialized &&
            _error == null &&
            _adapter.initializationError == null) {
          _authorizeRevealAndPlayback();
        }
      });
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: AspectRatio(aspectRatio: _adapter.aspectRatio, child: surface),
        ),
        if (widget.onFirstRenderedFrame != null && !_revealAuthorized)
          const Positioned.fill(child: ColoredBox(color: Colors.black)),
        if (widget.showControls)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MediaVideoControls(adapter: _adapter),
          ),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 42,
            color: Color.fromRGBO(255, 255, 255, 0.55),
          ),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.of(context)!.media_video_load_failed,
            style: const TextStyle(
              color: Color.fromRGBO(255, 255, 255, 0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTimestamp(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final rendered = value >= 100 || value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$rendered ${units[unitIndex]}';
}

String _formatDimensions(int width, int height) => '$width × $height';

String _formatDurationMs(int durationMs) {
  final totalSeconds = (durationMs / 1000).round();
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
