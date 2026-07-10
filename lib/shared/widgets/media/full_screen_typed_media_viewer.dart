import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'media_playback_adapter.dart';
import 'media_video_controls.dart';
import 'media_video_resume_controller.dart';
import 'media_viewer_item.dart';

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
    this.resumeStore,
    this.playbackAdapterFactory,
  });

  final List<MediaViewerItem> items;
  final int initialIndex;

  /// Invoked with the exact current item + action. Awaited once; the viewer
  /// never pops or mutates a chat optimistically on failure.
  final MediaViewerActionCallback? onAction;

  /// Owner-aware durable resume persistence (video only). Null disables resume.
  final MediaViewerResumeStore? resumeStore;

  /// Builds one playback adapter per video item. Tests inject fakes; production
  /// defaults to [defaultMediaPlaybackAdapterFactory].
  final MediaPlaybackAdapterFactory? playbackAdapterFactory;

  @override
  State<FullScreenTypedMediaViewer> createState() =>
      _FullScreenTypedMediaViewerState();
}

class _FullScreenTypedMediaViewerState
    extends State<FullScreenTypedMediaViewer> {
  static const List<MediaViewerAction> _actionOrder = <MediaViewerAction>[
    MediaViewerAction.save,
    MediaViewerAction.share,
    MediaViewerAction.forward,
    MediaViewerAction.bookmark,
    MediaViewerAction.delete,
  ];

  late final PageController _pageController;
  late int _currentIndex;
  bool _dispatching = false;
  MediaViewerActionResult? _lastResult;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  MediaViewerItem get _currentItem => widget.items[_currentIndex];

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
        actions: _buildActions(l10n, current),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: items.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) => _buildPage(items[index], index),
          ),
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
          key: ValueKey('typed-video-${item.attachmentId}'),
          item: item,
          isActive: isActive,
          adapterFactory:
              widget.playbackAdapterFactory ??
              defaultMediaPlaybackAdapterFactory,
          resumeStore: widget.resumeStore,
        );
      case MediaViewerKind.image:
      case MediaViewerKind.gif:
        return _TypedImagePage(item: item);
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
    children.add(
      Wrap(spacing: 10, runSpacing: 2, children: info),
    );

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

class _TypedImagePage extends StatelessWidget {
  const _TypedImagePage({required this.item});

  final MediaViewerItem item;

  @override
  Widget build(BuildContext context) {
    final path = item.localPath;
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
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.broken_image_outlined,
            size: 48,
            color: Color.fromRGBO(255, 255, 255, 0.25),
          ),
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
    this.resumeStore,
  });

  final MediaViewerItem item;
  final bool isActive;
  final MediaPlaybackAdapterFactory adapterFactory;
  final MediaViewerResumeStore? resumeStore;

  @override
  State<_TypedVideoPage> createState() => _TypedVideoPageState();
}

class _TypedVideoPageState extends State<_TypedVideoPage>
    with WidgetsBindingObserver {
  late final MediaPlaybackAdapter _adapter;
  late final MediaVideoResumeController _resume;
  bool _initialized = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _adapter = widget.adapterFactory(widget.item);
    _resume = MediaVideoResumeController(
      item: widget.item,
      adapter: _adapter,
      store: widget.resumeStore,
    );
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _adapter.initialize();
      if (!mounted) return;
      _adapter.addListener(_onAdapterTick);
      setState(() => _initialized = true);
      // Never start a non-current page.
      if (widget.isActive) {
        await _resume.restore();
        if (!mounted) return;
        await _adapter.play();
      }
    } catch (error) {
      if (!mounted) return;
      // Initialization failure pauses/keeps the owned controller idle; it must
      // never auto-play.
      setState(() => _error = error);
    }
  }

  void _onAdapterTick() {
    _resume.onTick();
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(_TypedVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) return;
    if (!_initialized || _error != null) return;
    if (widget.isActive) {
      _resume.restore();
      _adapter.play();
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
    _adapter.removeListener(_onAdapterTick);
    _resume.flush();
    _adapter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _buildError(context);
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
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _adapter.aspectRatio,
            child: _adapter.buildSurface(),
          ),
        ),
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
