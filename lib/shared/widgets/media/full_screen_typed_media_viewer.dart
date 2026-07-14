import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

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

  late final PageController _pageController;
  late int _currentIndex;
  bool _dispatching = false;
  MediaViewerActionResult? _lastResult;
  bool _renderLifecycleSettled = false;
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

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
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
                if (_pictureInPictureVisible)
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
                ..._buildActions(l10n, current),
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
          if (_lastResult != null)
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
      case MediaViewerKind.gif:
        return _TypedImagePage(
          item: item,
          onFirstRenderedFrame: widget.onFirstRenderedFrame == null
              ? null
              : _reportFirstRenderedFrame,
          onPreFrameFailure: _reportPreFrameFailure,
        );
    }
  }
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
    if (item.caption != null && item.caption!.isNotEmpty) {
      children.add(
        Text(
          item.caption!,
          key: const ValueKey('media_meta_caption'),
          style: style,
        ),
      );
    }

    final info = <Widget>[
      Text(item.mime, key: const ValueKey('media_meta_mime'), style: subStyle),
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

    return Padding(
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
    required this.onFirstRenderedFrame,
    required this.onPreFrameFailure,
  });

  final MediaViewerItem item;
  final Future<bool> Function()? onFirstRenderedFrame;
  final VoidCallback onPreFrameFailure;

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
      return const Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 48,
          color: Color.fromRGBO(255, 255, 255, 0.25),
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
            return const ColoredBox(color: Colors.black);
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
