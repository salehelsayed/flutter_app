import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/posts/domain/thought_quote.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';

/// One author's current thought, full screen.
///
/// The host decides whose thought this is: a friend's card offers reactions
/// and a reply field, the user's own card offers Delete.
class ThoughtCardScreen extends StatefulWidget {
  const ThoughtCardScreen({
    super.key,
    required this.initialPost,
    required this.authorName,
    required this.postRepo,
    required this.loadCurrentThought,
    required this.onReply,
    required this.downloadMedia,
    this.onDelete,
    this.eligibilityChanges,
    this.nowProvider,
  });

  final PostModel initialPost;
  final String authorName;
  final PostRepository postRepo;

  /// The author's current live thought, or null once there is none to show.
  final Future<PostModel?> Function() loadCurrentThought;

  /// Sends [text] to the author, quoting this thought, once the card has
  /// closed. A reaction arrives as its lone glyph.
  final void Function(String text, String postId)? onReply;

  /// Deletes the displayed thought for everyone. Completes once the local copy
  /// is gone; throws when it could not be deleted.
  final Future<void> Function(String postId)? onDelete;
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
  bool _deleting = false;
  int _mediaReadGeneration = 0;
  final _replyController = TextEditingController();
  final _replyFocus = FocusNode();

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
    _replyFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _replyController.addListener(() {
      if (mounted) setState(() {});
    });
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
        // The thought is already on screen; it stays unseen and is marked on
        // the next open.
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

  Future<void> _confirmDelete() async {
    final onDelete = widget.onDelete;
    if (onDelete == null || _deleting || _closing || !_isLive) return;
    final l10n = AppLocalizations.of(context)!;
    final postId = _post.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.thought_delete_confirm_title),
        content: Text(l10n.thought_delete_confirm_body),
        actions: [
          TextButton(
            key: const ValueKey('thought-delete-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.btn_cancel),
          ),
          FilledButton(
            key: const ValueKey('thought-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.thought_delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _closing || _post.id != postId) {
      return;
    }
    setState(() => _deleting = true);
    try {
      await onDelete(postId);
      _close();
    } catch (_) {
      if (!mounted || _closing) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.thought_delete_failed)));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _postSubscription?.cancel();
    _eligibilitySubscription?.cancel();
    _expiryTimer?.cancel();
    _ageTimer?.cancel();
    _replyController.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  void _sendReply(String text) {
    final onReply = widget.onReply;
    final trimmed = text.trim();
    if (onReply == null || trimmed.isEmpty) return;
    if (!_isLive) {
      _close();
      return;
    }
    _replyFocus.unfocus();
    final postId = _post.id;
    _close(afterClose: () => onReply(trimmed, postId));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final visible = _validated && !_loadFailed && !_closing && _isLive;
    final visual = _media
        .where((item) => item.kind != 'voice')
        .toList(growable: false);
    final hasVisual = visual.isNotEmpty || _expectsVisualMedia;
    final typing = _replyFocus.hasFocus;
    return Scaffold(
      key: const ValueKey('thought-card-screen'),
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: _closing
          ? const SizedBox.shrink()
          : _loadFailed
          ? _failure(l10n)
          : !visible
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: hasVisual
                      ? const BoxDecoration(color: Colors.black)
                      : const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF0F766E), Color(0xFF134E4A)],
                          ),
                        ),
                ),
                if (_localPhoto(visual) case final photo?)
                  _BlurredFill(image: FileImage(File(photo)))
                else if (_pendingPreview(visual) case final preview?)
                  _BlurredFill(image: MemoryImage(preview)),
                if (hasVisual)
                  Center(child: _visualMedia(l10n, visual))
                else
                  _centeredText(),
                const _Scrim(top: true),
                const _Scrim(top: false),
                AnimatedOpacity(
                  opacity: typing ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: IgnorePointer(
                    ignoring: !typing,
                    child: GestureDetector(
                      key: const ValueKey('thought-reply-dismiss'),
                      onTap: _replyFocus.unfocus,
                      child: const ColoredBox(color: Color(0x61000000)),
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      _topChrome(l10n),
                      const Spacer(),
                      _bottomChrome(l10n, showText: hasVisual, typing: typing),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// The photo of a one-photo thought, once it is on this phone.
  String? _localPhoto(List<PostMediaAttachmentModel> visual) {
    if (visual.length != 1) return null;
    final photo = visual.single;
    final localPath = photo.localPath;
    if (photo.kind != 'image' ||
        photo.downloadStatus != 'done' ||
        localPath == null) {
      return null;
    }
    return MediaFileManager.resolveStoredPathSync(localPath);
  }

  /// The sender's tiny preview of a one-photo thought still on its way.
  Uint8List? _pendingPreview(List<PostMediaAttachmentModel> visual) {
    if (visual.length != 1 || _localPhoto(visual) != null) return null;
    final preview = visual.single.previewBase64;
    if (visual.single.kind != 'image' || preview == null) return null;
    try {
      return base64Decode(preview);
    } on FormatException {
      return null;
    }
  }

  bool get _expectsVisualMedia =>
      const {'image', 'image_carousel', 'video'}.contains(_post.mediaKind);

  Widget _failure(AppLocalizations l10n) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.load_retry_hint, style: const TextStyle(color: Colors.white)),
        TextButton(onPressed: _requestRefresh, child: Text(l10n.btn_retry)),
      ],
    ),
  );

  Widget _centeredText() => Center(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(28, 120, 28, 200),
      child: SingleChildScrollView(
        child: DefaultTextStyle.merge(
          textAlign: TextAlign.center,
          child: LinkableText(
            text: _post.text,
            textDirection: detectTextDirection(_post.text),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _visualMedia(
    AppLocalizations l10n,
    List<PostMediaAttachmentModel> visual,
  ) {
    final height = MediaQuery.sizeOf(context).height;
    final single = visual.length == 1 ? visual.single : null;
    final photoPending =
        single != null &&
        single.kind == 'image' &&
        _localPhoto(visual) == null &&
        single.downloadStatus != 'failed';
    if (visual.isEmpty || photoPending) {
      // Not here yet: hold the photo's place, in its own shape, instead of a
      // spinner.
      final width = single?.width ?? 0;
      final height = single?.height ?? 0;
      return _MediaPlaceholder(
        key: const ValueKey('thought-media-placeholder'),
        preview: _pendingPreview(visual),
        aspectRatio: width > 0 && height > 0 ? width / height : 3 / 4,
        failed: visual.isEmpty && _mediaLoadFailed && !_mediaLoading,
        onRetry: () => unawaited(_loadMedia(_post.id)),
        retryLabel: l10n.btn_retry,
      );
    }
    return MediaGrid(
      media: visual
          .map((attachment) => attachment.toSharedMediaAttachment())
          .toList(growable: false),
      singleMaxHeight: height,
      onTap: (index) => unawaited(_openMedia(index)),
      onRetryUnavailableMedia: (attachment) {
        final original = visual
            .where((item) => item.blobId == attachment.id)
            .firstOrNull;
        if (original != null) unawaited(_download(original));
      },
    );
  }

  Widget _topChrome(AppLocalizations l10n) {
    final created = DateTime.tryParse(_post.createdAt)?.toUtc();
    final expiry = DateTime.tryParse(_post.expiresAt)?.toUtc();
    final total = created != null && expiry != null
        ? expiry.difference(created)
        : Duration.zero;
    final left = expiry?.difference(_now) ?? Duration.zero;
    final lifeLeft = total.inSeconds <= 0
        ? 0.0
        : (left.inSeconds / total.inSeconds).clamp(0.0, 1.0);
    final goneIn = left.inMinutes >= 60
        ? l10n.thought_gone_in_hours(left.inHours)
        : l10n.thought_gone_in_minutes(left.inMinutes.clamp(1, 59));
    final name = widget.authorName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                key: const ValueKey('thought-life-bar'),
                value: lifeLeft,
                minHeight: 3,
                color: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: const Color(0xFFE9A23B),
                child: Text(
                  name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF1B1B1F),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${_relativeAge(l10n)} · $goneIn',
                      key: const ValueKey('thought-age'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('thought-close'),
                tooltip: l10n.thought_close,
                onPressed: _close,
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bottomChrome(
    AppLocalizations l10n, {
    required bool showText,
    required bool typing,
  }) {
    final voice = _media.where((item) => item.kind == 'voice');
    final onReply = widget.onReply;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showText && _post.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.3,
                ),
                child: SingleChildScrollView(
                  child: LinkableText(
                    text: _post.text,
                    textDirection: detectTextDirection(_post.text),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: typing ? 18 : 21,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      shadows: const [
                        Shadow(color: Color(0x59000000), blurRadius: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          for (final attachment in voice)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AudioPlayerWidget(
                key: ValueKey('thought-voice-${attachment.mediaId}'),
                attachment: attachment.toSharedMediaAttachment(),
                onRetryUnavailableMedia: () => unawaited(_download(attachment)),
              ),
            ),
          if (onReply != null) ...[
            if (!typing)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    for (final reaction in ThoughtReaction.values) ...[
                      _ReactionButton(
                        key: ValueKey('thought-react-${reaction.name}'),
                        reaction: reaction,
                        label: switch (reaction) {
                          ThoughtReaction.love => l10n.thought_react_love,
                          ThoughtReaction.laugh => l10n.thought_react_laugh,
                          ThoughtReaction.fire => l10n.thought_react_fire,
                          ThoughtReaction.applause =>
                            l10n.thought_react_applause,
                        },
                        onPressed: () => _sendReply(reaction.glyph),
                      ),
                      const SizedBox(width: 10),
                    ],
                  ],
                ),
              ),
            _ReplyField(
              controller: _replyController,
              focusNode: _replyFocus,
              hint: l10n.thought_reply_hint(widget.authorName),
              sendLabel: l10n.thought_reply_send,
              onSend: () => _sendReply(_replyController.text),
            ),
          ] else if (widget.onDelete != null)
            OutlinedButton.icon(
              key: const ValueKey('thought-delete'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _deleting ? null : () => unawaited(_confirmDelete()),
              icon: const Icon(Icons.delete_outline),
              label: Text(l10n.thought_delete),
            ),
        ],
      ),
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

class _Scrim extends StatelessWidget {
  const _Scrim({required this.top});

  final bool top;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Align(
      alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: top ? 0.22 : 0.42,
        widthFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: top ? 0.45 : 0.6),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// The photo itself, blurred and dimmed, filling the screen behind it.
class _BlurredFill extends StatelessWidget {
  const _BlurredFill({required this.image});

  final ImageProvider image;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ClipRect(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Color(0x66000000),
            BlendMode.darken,
          ),
          child: Image(
            image: ResizeImage.resizeIfNeeded(120, null, image),
            key: const ValueKey('thought-photo-fill'),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({
    super.key,
    this.preview,
    required this.aspectRatio,
    required this.failed,
    required this.onRetry,
    required this.retryLabel,
  });

  /// The sender's tiny preview, shown blurred until the photo arrives.
  final Uint8List? preview;
  final double aspectRatio;
  final bool failed;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: aspectRatio,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2B2F3A), Color(0xFF1A1C22)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (preview case final preview?)
            ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Image.memory(
                  preview,
                  key: const ValueKey('thought-photo-preview'),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          if (failed)
            Center(
              child: TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: Text(retryLabel),
              ),
            )
          else
            const Align(
              alignment: Alignment.bottomCenter,
              child: LinearProgressIndicator(
                minHeight: 2,
                color: Colors.white70,
                backgroundColor: Colors.transparent,
              ),
            ),
        ],
      ),
    ),
  );
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    super.key,
    required this.reaction,
    required this.label,
    required this.onPressed,
  });

  final ThoughtReaction reaction;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: Material(
      color: Colors.white.withValues(alpha: 0.16),
      shape: CircleBorder(
        side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Text(reaction.glyph, style: const TextStyle(fontSize: 22)),
          ),
        ),
      ),
    ),
  );
}

class _ReplyField extends StatelessWidget {
  const _ReplyField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.sendLabel,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final String sendLabel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final canSend = controller.text.trim().isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: focusNode.hasFocus ? 0.22 : 0.16),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('thought-reply-field'),
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(color: Colors.white, fontSize: 15),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(18, 13, 8, 13),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(5),
            child: IconButton.filled(
              key: const ValueKey('thought-reply-send'),
              tooltip: sendLabel,
              onPressed: canSend ? onSend : null,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                disabledBackgroundColor: Colors.white,
                foregroundColor: Colors.white,
                disabledForegroundColor: const Color(0xFF0F766E),
              ),
              icon: const Icon(Icons.send_rounded, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
