import 'dart:async';
import 'package:flutter_app/features/posts/presentation/widgets/thought_voice.dart';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';

/// A front-card-only view. Removing it also disposes any voice player. Its
/// generation prevents a previous card's asynchronous media from reappearing.
class OrbitDepthMedia extends StatefulWidget {
  const OrbitDepthMedia({
    super.key,
    required this.postId,
    required this.load,
    required this.download,
    required this.onOpen,
    this.postChanges,
    this.onPlayVideo,
    this.onActivate,
    this.lastLoaded,
  });
  final String postId;
  final Future<List<PostMediaAttachmentModel>> Function(String) load;
  final Future<PostMediaAttachmentModel> Function(PostMediaAttachmentModel, int)
  download;
  final Stream<String>? postChanges;
  final VoidCallback onOpen;

  /// Replaces [onOpen] for a lone downloaded video, which plays at once.
  final VoidCallback? onPlayVideo;

  /// The screen reader's open, when it must differ from a finger's [onOpen].
  final VoidCallback? onActivate;

  /// Media this card showed before, by post id. The card is rebuilt on every
  /// entry into depth; starting from it avoids a spinner flash before the
  /// same photo reappears.
  final Map<String, List<PostMediaAttachmentModel>>? lastLoaded;
  @override
  State<OrbitDepthMedia> createState() => _OrbitDepthMediaState();
}

class _OrbitDepthMediaState extends State<OrbitDepthMedia> {
  late List<PostMediaAttachmentModel> _media =
      widget.lastLoaded?[widget.postId] ?? const [];
  bool _loading = true;
  bool _failed = false;
  int _generation = 0;
  int _readVersion = 0;
  int _appliedVersion = 0;
  final _attempts = <String, int>{};
  final _pendingWaits = <Completer<void>>{};
  StreamSubscription<String>? _postSubscription;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _bindPostChanges();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant OrbitDepthMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged = oldWidget.postChanges != widget.postChanges;
    if (sourceChanged) _bindPostChanges();
    if (oldWidget.postId != widget.postId || sourceChanged) {
      _attempts.clear();
      _media = widget.lastLoaded?[widget.postId] ?? const [];
      unawaited(_load());
    }
  }

  void _bindPostChanges() {
    unawaited(_postSubscription?.cancel());
    _postSubscription = widget.postChanges?.listen((postId) {
      if (mounted && postId == widget.postId) unawaited(_refresh(postId));
    });
  }

  Future<void> _refresh(String postId) async {
    final generation = _generation;
    final version = ++_readVersion;
    try {
      final media = await _waitForMedia(widget.load(postId));
      if (media == null ||
          !mounted ||
          generation != _generation ||
          version < _appliedVersion) {
        return;
      }
      // A commit may arrive while the foreground download is still waiting.
      // Publish it now without interrupting the remaining transfers.
      setState(() {
        _applySnapshot(media, version);
        _failed = !_loading && _media.any((item) => !_hasLocalFile(item));
      });
      if (!_waitingForRetry) _cancelRetry();
    } catch (_) {
      // A background read cannot invalidate a visible, working attachment.
    }
  }

  void _applySnapshot(List<PostMediaAttachmentModel> media, int version) {
    if (version < _appliedVersion) return;
    _appliedVersion = version;
    _media = media;
    widget.lastLoaded?[widget.postId] = media;
  }

  bool _hasLocalFile(PostMediaAttachmentModel attachment) {
    final path = attachment.localPath;
    return path != null &&
        path.isNotEmpty &&
        File(MediaFileManager.resolveStoredPathSync(path)).existsSync();
  }

  bool get _waitingForRetry => _media.any(
    (item) =>
        item.downloadStatus == kMediaDownloadStatusRetryWaiting &&
        !_hasLocalFile(item),
  );

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<T?> _waitForMedia<T>(Future<T> operation) async {
    final closed = Completer<void>();
    _pendingWaits.add(closed);
    try {
      return await Future.any<T?>([
        operation,
        closed.future.then<T?>((_) => null),
      ]).timeout(const Duration(seconds: 30));
    } finally {
      _pendingWaits.remove(closed);
    }
  }

  void _cancelMediaWaits() {
    for (final wait in _pendingWaits) {
      wait.complete();
    }
    _pendingWaits.clear();
  }

  Future<void> _load({bool transientOnly = false}) async {
    _cancelRetry();
    _cancelMediaWaits();
    final generation = ++_generation;
    final postId = widget.postId;
    setState(() {
      _loading = true;
      _failed = false;
    });
    bool current() =>
        mounted && generation == _generation && widget.postId == postId;
    try {
      final initialVersion = ++_readVersion;
      final initialMedia = await _waitForMedia(widget.load(postId));
      if (initialMedia == null || !current()) return;
      setState(() => _applySnapshot(initialMedia, initialVersion));
      for (final attachment in _media) {
        if (!current()) return;
        if (_hasLocalFile(attachment) ||
            (transientOnly &&
                attachment.downloadStatus !=
                    kMediaDownloadStatusRetryWaiting)) {
          continue;
        }
        // The downloader joins active transfers and persists their outcome.
        final attempt = _attempts.update(
          attachment.mediaId,
          (previous) => previous + 1,
          ifAbsent: () => 1,
        );
        try {
          await _waitForMedia(widget.download(attachment, attempt));
        } catch (_) {
          if (!current()) return;
        }
      }
      if (!current()) return;
      final finalVersion = ++_readVersion;
      final media = await _waitForMedia(widget.load(postId));
      if (media == null || !current()) return;
      setState(() {
        _applySnapshot(media, finalVersion);
        _loading = false;
        _failed = _media.isEmpty || _media.any((item) => !_hasLocalFile(item));
      });
      if (!transientOnly && _waitingForRetry) {
        _retryTimer = Timer(const Duration(seconds: 1), () {
          _retryTimer = null;
          if (current()) unawaited(_load(transientOnly: true));
        });
      }
    } catch (_) {
      if (current()) {
        setState(() {
          _loading = false;
          _failed =
              _media.isEmpty || _media.any((item) => !_hasLocalFile(item));
        });
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    _cancelRetry();
    _cancelMediaWaits();
    unawaited(_postSubscription?.cancel());
    super.dispose();
  }

  void _tap(List<PostMediaAttachmentModel> visual) {
    final video = visual.length == 1 && visual.single.kind == 'video'
        ? visual.single
        : null;
    final local = video?.localPath;
    final play = widget.onPlayVideo;
    if (play == null ||
        video == null ||
        video.downloadStatus != 'done' ||
        local == null ||
        !File(MediaFileManager.resolveStoredPathSync(local)).existsSync()) {
      widget.onOpen();
      return;
    }
    play();
  }

  @override
  Widget build(BuildContext context) {
    final visual = _media.where((item) => item.kind != 'voice').toList();
    final voiced = _media.any((item) => item.kind == 'voice');
    final column = Column(
      mainAxisSize: visual.isEmpty ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (_loading && _media.isEmpty)
          const SizedBox(
            height: 48,
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_failed)
          TextButton(
            key: const ValueKey('orbit-depth-media-retry'),
            onPressed: () => unawaited(_load()),
            child: Text(AppLocalizations.of(context)!.btn_retry),
          ),
        for (final item in _media.where((item) => item.kind == 'voice')) ...[
          if (item.caption case final caption?) ThoughtVoiceCaption(caption),
          AudioPlayerWidget(
            key: ValueKey('orbit-depth-voice-${item.mediaId}'),
            attachment: item.toSharedMediaAttachment(),
          ),
        ],
        // The whole photo, as large as the space allows, on the scene.
        if (visual.isNotEmpty)
          Expanded(
            child: Semantics(
              onTap: widget.onActivate ?? widget.onOpen,
              child: GestureDetector(
                key: const ValueKey('orbit-depth-photo-frame'),
                onTap: () => _tap(visual),
                excludeFromSemantics: true,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: LayoutBuilder(
                    builder: (context, constraints) => Center(
                      child: MediaGrid(
                        media: visual
                            .map((item) => item.toSharedMediaAttachment())
                            .toList(),
                        singleMaxHeight: constraints.maxHeight,
                        borderRadius: 22,
                        tileFit: BoxFit.contain,
                        squareTiles: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    if (visual.isEmpty || !voiced) return column;
    // A voice note above a photo needs a least height; while a reply leaves
    // less, the pair keeps it and shows its top instead of overflowing. The
    // clip stays mounted so a playing voice note is never rebuilt.
    return LayoutBuilder(
      builder: (context, box) => ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          maxHeight: math.max(box.maxHeight, _voiceAndPhotoMinHeight),
          child: column,
        ),
      ),
    );
  }
}

const _voiceAndPhotoMinHeight = 120.0;
