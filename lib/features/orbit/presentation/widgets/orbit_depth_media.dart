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
  bool _refreshRequested = false;
  int _generation = 0;
  final _attempts = <String, int>{};
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
      _refreshRequested = false;
      _media = widget.lastLoaded?[widget.postId] ?? const [];
      unawaited(_load());
    }
  }

  void _bindPostChanges() {
    unawaited(_postSubscription?.cancel());
    _postSubscription = widget.postChanges?.listen((postId) {
      if (!mounted || postId != widget.postId) return;
      if (_loading) {
        _refreshRequested = true;
      } else {
        unawaited(_load(downloadMissing: false));
      }
    });
  }

  bool _hasLocalFile(PostMediaAttachmentModel attachment) {
    final path = attachment.localPath;
    return path != null &&
        path.isNotEmpty &&
        File(MediaFileManager.resolveStoredPathSync(path)).existsSync();
  }

  Future<void> _load({
    bool downloadMissing = true,
    bool transientOnly = false,
  }) async {
    if (downloadMissing) {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
    final generation = ++_generation;
    final postId = widget.postId;
    setState(() {
      _loading = true;
      _failed = false;
    });
    bool current() =>
        mounted && generation == _generation && widget.postId == postId;
    try {
      var media = await widget
          .load(postId)
          .timeout(const Duration(seconds: 30));
      if (!current()) return;
      if (downloadMissing) {
        setState(() => _media = media);
        for (final attachment in media) {
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
            await widget
                .download(attachment, attempt)
                .timeout(const Duration(seconds: 30));
          } catch (_) {
            if (!current()) return;
          }
        }
        if (!current()) return;
        media = await widget.load(postId).timeout(const Duration(seconds: 30));
      }
      if (!current()) return;
      final waiting = media.any(
        (item) =>
            item.downloadStatus == kMediaDownloadStatusRetryWaiting &&
            !_hasLocalFile(item),
      );
      if (downloadMissing && !transientOnly && waiting) {
        _retryTimer = Timer(const Duration(seconds: 1), () {
          _retryTimer = null;
          if (mounted && widget.postId == postId) {
            unawaited(_load(transientOnly: true));
          }
        });
      } else if (!waiting) {
        _retryTimer?.cancel();
        _retryTimer = null;
      }
      widget.lastLoaded?[postId] = media;
      setState(() {
        _media = media;
        _loading = false;
        _failed =
            (downloadMissing && media.isEmpty) ||
            media.any((item) => !_hasLocalFile(item));
      });
    } catch (_) {
      if (current()) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    } finally {
      if (current() && _refreshRequested) {
        _refreshRequested = false;
        unawaited(_load(downloadMissing: false));
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    _retryTimer?.cancel();
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
