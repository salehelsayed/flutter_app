import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';

/// One author's current thought, without the retired Posts engagement controls.
///
/// The host decides whose thought this is: a friend's card offers Message, the
/// user's own card (a null [onMessage]) has no action yet.
class ThoughtCardScreen extends StatefulWidget {
  const ThoughtCardScreen({
    super.key,
    required this.initialPost,
    required this.authorName,
    required this.postRepo,
    required this.loadCurrentThought,
    required this.onMessage,
    required this.downloadMedia,
    this.eligibilityChanges,
    this.nowProvider,
  });

  final PostModel initialPost;
  final String authorName;
  final PostRepository postRepo;

  /// The author's current live thought, or null once there is none to show.
  final Future<PostModel?> Function() loadCurrentThought;
  final VoidCallback? onMessage;
  final Future<PostMediaAttachmentModel> Function(PostMediaAttachmentModel)
  downloadMedia;
  final Stream<void>? eligibilityChanges;
  final DateTime Function()? nowProvider;

  @override
  State<ThoughtCardScreen> createState() => _ThoughtCardScreenState();
}

class _ThoughtCardScreenState extends State<ThoughtCardScreen>
    with WidgetsBindingObserver {
  late PostModel _post;
  List<PostMediaAttachmentModel> _media = const [];
  StreamSubscription<String>? _postSubscription;
  StreamSubscription<void>? _eligibilitySubscription;
  Timer? _expiryTimer;
  Timer? _ageTimer;
  ModalRoute<dynamic>? _cardRoute;
  Route<void>? _mediaRoute;
  NavigatorState? _navigator;
  final _markedIds = <String>{};
  final _markPendingIds = <String>{};
  final _attemptedDownloads = <String>{};
  final _inFlightDownloads = <String>{};
  bool _validated = false;
  bool _loadFailed = false;
  bool _mediaLoading = false;
  bool _mediaLoadFailed = false;
  bool _refreshing = false;
  bool _refreshAgain = false;
  bool _closing = false;
  int _mediaReadGeneration = 0;

  DateTime get _now => (widget.nowProvider ?? DateTime.now)().toUtc();

  bool get _isLive {
    final expiry = DateTime.tryParse(_post.expiresAt)?.toUtc();
    return expiry != null && expiry.isAfter(_now);
  }

  @override
  void initState() {
    super.initState();
    _post = widget.initialPost;
    WidgetsBinding.instance.addObserver(this);
    _postSubscription = widget.postRepo.postChanges.listen(
      (_) => _requestRefresh(),
    );
    _eligibilitySubscription = widget.eligibilityChanges?.listen(
      (_) => _requestRefresh(),
    );
    _ageTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted || _closing) return;
      if (!_isLive) {
        _close();
      } else {
        setState(() {});
      }
    });
    _armExpiry();
    _requestRefresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cardRoute = ModalRoute.of(context);
    _navigator = Navigator.of(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_closing) {
      if (!_isLive) {
        _close();
      } else {
        _requestRefresh();
      }
    }
  }

  void _armExpiry() {
    _expiryTimer?.cancel();
    final expiry = DateTime.tryParse(_post.expiresAt)?.toUtc();
    final remaining = expiry?.difference(_now) ?? Duration.zero;
    _expiryTimer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (!mounted || _closing) return;
      if (_isLive) {
        _armExpiry();
      } else {
        _close();
      }
    });
  }

  void _requestRefresh() {
    if (!mounted || _closing) return;
    _refreshAgain = true;
    if (!_refreshing) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    _refreshing = true;
    try {
      while (_refreshAgain && mounted && !_closing) {
        _refreshAgain = false;
        final displayedId = _post.id;
        final storedCurrent = await widget.postRepo.getPost(displayedId);
        if (!mounted || _closing) return;
        if (_post.id != displayedId) continue;
        // Deletion ends this presentation; an older surviving copy must not
        // silently replace the thought the user was viewing.
        if (storedCurrent == null) {
          _close();
          return;
        }
        final current = await widget.loadCurrentThought();
        if (!mounted || _closing) return;
        if (_post.id != displayedId) continue;
        if (current == null) {
          _close();
          return;
        }
        final changedPost = _post.id != current.id;
        if (changedPost) _closeMediaViewer();
        setState(() {
          _post = current;
          _validated = true;
          _loadFailed = false;
          if (changedPost) _media = const [];
        });
        _armExpiry();
        _markWhenShown();
        unawaited(_loadMedia(current.id));
      }
    } catch (_) {
      if (mounted && !_closing) setState(() => _loadFailed = true);
    } finally {
      _refreshing = false;
    }
  }

  void _markWhenShown() {
    final postId = _post.id;
    // The author does not "read" their own thought.
    if (!_post.isIncoming ||
        _markedIds.contains(postId) ||
        !_markPendingIds.add(postId)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted ||
            _closing ||
            _post.id != postId ||
            _cardRoute?.isCurrent != true ||
            !_isLive ||
            _loadFailed) {
          return;
        }
        await widget.postRepo.markFocused(postId);
        _markedIds.add(postId);
      } catch (_) {
        if (mounted && !_closing) setState(() => _loadFailed = true);
      } finally {
        _markPendingIds.remove(postId);
      }
    });
  }

  Future<void> _loadMedia(String postId) async {
    final generation = ++_mediaReadGeneration;
    if (mounted && !_closing) {
      setState(() {
        _mediaLoading = true;
        _mediaLoadFailed = false;
      });
    }
    try {
      final media = (await widget.postRepo.loadPostMediaAttachments(
        postId,
      )).toList(growable: false);
      if (!mounted ||
          _closing ||
          _post.id != postId ||
          generation != _mediaReadGeneration) {
        return;
      }
      media.sort((a, b) => a.position.compareTo(b.position));
      setState(() {
        _media = media;
        _mediaLoading = false;
      });
      for (final attachment in media) {
        final localPath = attachment.localPath;
        final isLocal =
            attachment.downloadStatus == 'done' &&
            localPath != null &&
            File(
              MediaFileManager.resolveStoredPathSync(localPath),
            ).existsSync();
        if (!isLocal &&
            attachment.downloadStatus != 'downloading' &&
            !_attemptedDownloads.contains(attachment.mediaId)) {
          unawaited(_download(attachment));
        }
      }
    } catch (_) {
      if (mounted &&
          !_closing &&
          _post.id == postId &&
          generation == _mediaReadGeneration) {
        setState(() {
          _mediaLoading = false;
          _mediaLoadFailed = true;
        });
      }
    }
  }

  Future<void> _download(PostMediaAttachmentModel attachment) async {
    if (_closing ||
        attachment.postId != _post.id ||
        !_isLive ||
        !_inFlightDownloads.add(attachment.mediaId)) {
      return;
    }
    _attemptedDownloads.add(attachment.mediaId);
    _replaceMedia(attachment.copyWith(downloadStatus: 'downloading'));
    try {
      final downloaded = await widget.downloadMedia(attachment);
      _replaceMedia(downloaded);
    } catch (_) {
      _replaceMedia(attachment.copyWith(downloadStatus: 'failed'));
    } finally {
      _inFlightDownloads.remove(attachment.mediaId);
      // The existing downloader persists its result. A final read supersedes
      // any older in-flight read of its intermediate downloading state.
      if (mounted && !_closing && _post.id == attachment.postId) {
        unawaited(_loadMedia(attachment.postId));
      }
    }
  }

  void _replaceMedia(PostMediaAttachmentModel attachment) {
    if (!mounted || _closing || _post.id != attachment.postId) return;
    setState(() {
      _media = _media
          .map((item) => item.mediaId == attachment.mediaId ? attachment : item)
          .toList(growable: false);
    });
  }

  void _closeMediaViewer() {
    final route = _mediaRoute;
    _mediaRoute = null;
    if (route != null && route.isActive) _navigator?.removeRoute(route);
  }

  void _close({VoidCallback? afterClose}) {
    if (!mounted || _closing) return;
    setState(() => _closing = true);
    _expiryTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = _navigator;
      final route = _cardRoute;
      if (!mounted ||
          navigator == null ||
          !navigator.mounted ||
          route == null ||
          !route.isActive) {
        return;
      }
      _closeMediaViewer();
      if (route.isActive) {
        if (route.isCurrent && navigator.canPop()) {
          navigator.pop();
        } else if (!route.isFirst) {
          navigator.removeRoute(route);
        }
      }
      afterClose?.call();
    });
  }

  Future<void> _openMedia(int index) async {
    if (_closing ||
        !_isLive ||
        _mediaRoute != null ||
        _cardRoute?.isCurrent != true) {
      return;
    }
    final visualMedia = _media
        .where((item) => item.kind != 'voice')
        .toList(growable: false);
    if (index < 0 || index >= visualMedia.length) return;
    final selected = visualMedia[index];
    if (selected.downloadStatus != 'done' ||
        selected.localPath == null ||
        !File(
          MediaFileManager.resolveStoredPathSync(selected.localPath!),
        ).existsSync()) {
      return;
    }
    final items = visualMedia
        .map(
          (attachment) => MediaViewerItem(
            attachmentId: attachment.blobId,
            messageId: attachment.postId,
            kind: attachment.kind == 'video'
                ? MediaViewerKind.video
                : attachment.mime == 'image/gif'
                ? MediaViewerKind.gif
                : MediaViewerKind.image,
            mime: attachment.mime,
            localPath: attachment.localPath == null
                ? null
                : MediaFileManager.resolveStoredPathSync(attachment.localPath!),
            sizeBytes: attachment.sizeBytes,
            width: attachment.width,
            height: attachment.height,
            durationMs: attachment.durationMs,
            showMetadataDetails: false,
            protection: MediaViewerProtection(
              isDownloaded: attachment.downloadStatus == 'done',
            ),
          ),
        )
        .toList(growable: false);
    final route = MaterialPageRoute<void>(
      builder: (_) => FullScreenTypedMediaViewer(
        key: const ValueKey('thought-media-viewer'),
        items: items,
        initialIndex: index,
      ),
    );
    _mediaRoute = route;
    await _navigator!.push(route);
    if (identical(_mediaRoute, route)) _mediaRoute = null;
    if (mounted && !_closing) _markWhenShown();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _postSubscription?.cancel();
    _eligibilitySubscription?.cancel();
    _expiryTimer?.cancel();
    _ageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.backgroundReadableColors;
    final visible = _validated && !_loadFailed && !_closing && _isLive;
    final onMessage = widget.onMessage;
    return Scaffold(
      key: const ValueKey('thought-card-screen'),
      appBar: AppBar(title: Text(widget.authorName)),
      body: _closing
          ? const SizedBox.shrink()
          : _loadFailed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.load_retry_hint),
                  TextButton(
                    onPressed: _requestRefresh,
                    child: Text(l10n.btn_retry),
                  ),
                ],
              ),
            )
          : !visible
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _relativeAge(l10n),
                    key: const ValueKey('thought-age'),
                    style: TextStyle(color: colors.textMuted),
                  ),
                  if (_post.text.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    LinkableText(
                      text: _post.text,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(color: colors.textPrimary),
                    ),
                  ],
                  if (_post.mediaKind != 'none' || _media.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildMedia(l10n),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: visible && onMessage != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  key: const ValueKey('thought-message'),
                  onPressed: () {
                    if (!_isLive) {
                      _close();
                      return;
                    }
                    _close(afterClose: onMessage);
                  },
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: Text(l10n.pinned_message(widget.authorName)),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildMedia(AppLocalizations l10n) {
    if (_media.isEmpty) {
      return _mediaLoading
          ? const Center(child: CircularProgressIndicator())
          : TextButton(
              onPressed: () => unawaited(_loadMedia(_post.id)),
              child: Text(l10n.btn_retry),
            );
    }
    final voice = _media.where((item) => item.kind == 'voice');
    final visual = _media
        .where((item) => item.kind != 'voice')
        .toList(growable: false);
    return Column(
      children: [
        if (_mediaLoadFailed)
          TextButton(
            onPressed: () => unawaited(_loadMedia(_post.id)),
            child: Text(l10n.btn_retry),
          ),
        for (final attachment in voice)
          AudioPlayerWidget(
            key: ValueKey('thought-voice-${attachment.mediaId}'),
            attachment: attachment.toSharedMediaAttachment(),
            onRetryUnavailableMedia: () => unawaited(_download(attachment)),
          ),
        if (visual.isNotEmpty)
          MediaGrid(
            media: visual
                .map((attachment) => attachment.toSharedMediaAttachment())
                .toList(growable: false),
            onTap: (index) => unawaited(_openMedia(index)),
            onRetryUnavailableMedia: (attachment) {
              final original = visual
                  .where((item) => item.blobId == attachment.id)
                  .firstOrNull;
              if (original != null) unawaited(_download(original));
            },
          ),
      ],
    );
  }

  String _relativeAge(AppLocalizations l10n) {
    final created = DateTime.tryParse(_post.createdAt)?.toUtc();
    final age = created == null ? Duration.zero : _now.difference(created);
    if (age.inMinutes < 1) return l10n.time_just_now;
    if (age.inMinutes < 60) return l10n.time_min_ago(age.inMinutes);
    if (age.inHours < 24) return l10n.time_hour_ago(age.inHours);
    return l10n.time_day_ago(age.inDays);
  }
}
