import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/core/permissions/mic_permission_prompt.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/posts/application/load_thought_activity_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/posts/domain/thought_quote.dart';
import 'package:flutter_app/features/posts/domain/thought_reply_status.dart';
import 'package:flutter_app/features/translate_preview/on_device_ai.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/features/translate_preview/translate_preview_widgets.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';
import 'package:flutter_app/shared/widgets/conversation/conversation_voice_capture_controller.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';
import 'package:uuid/uuid.dart';

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
    this.onOpenChat,
    this.replyChanges,
    this.retryPosting,
    this.onShown,
    this.loadActivity,
    this.eligibilityChanges,
    this.nowProvider,
    this.onVoiceReply,
    this.audioRecorderService,
    this.micPermissionGateway = const PermissionHandlerMicGateway(),
  });

  final PostModel initialPost;
  final String authorName;
  final PostRepository postRepo;

  /// The author's current live thought, or null once there is none to show.
  final Future<PostModel?> Function() loadCurrentThought;

  /// Sends an ordinary quoted reply in place. Retry keeps the same message ID.
  final ThoughtReplySender? onReply;
  final VoidCallback? onOpenChat;
  final Stream<ConversationMessage>? replyChanges;
  final Future<int> Function()? retryPosting;
  final Future<void> Function(String postId)? onShown;
  final Future<ThoughtActivity> Function(String postId)? loadActivity;

  /// Deletes the displayed thought for everyone. Completes once the local copy
  /// is gone; throws when it could not be deleted.
  final Future<void> Function(String postId)? onDelete;
  final Future<PostMediaAttachmentModel> Function(PostMediaAttachmentModel)
  downloadMedia;
  final Stream<void>? eligibilityChanges;
  final DateTime Function()? nowProvider;

  /// Takes a recorded voice reply to the author's chat, which sends it. Null
  /// hides the mic.
  final ValueChanged<ThoughtVoiceReply>? onVoiceReply;
  final AudioRecorderService? audioRecorderService;
  final MicPermissionGateway micPermissionGateway;

  @override
  State<ThoughtCardScreen> createState() => _ThoughtCardScreenState();
}

class _ThoughtCardScreenState extends State<ThoughtCardScreen>
    with WidgetsBindingObserver {
  late PostModel _post;
  List<PostMediaAttachmentModel> _media = const [];
  StreamSubscription<String>? _postSubscription;
  StreamSubscription<void>? _eligibilitySubscription;
  StreamSubscription<ConversationMessage>? _replySubscription;
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
  String? _replyMessageId;
  String? _submittedReply;

  /// The photo alone, with every control hidden, after a tap on it.
  bool _immersive = false;

  late final _voice = ConversationVoiceCaptureController(
    onAutoStopOutcome: (outcome) => _handOffVoice(outcome, autoStopped: true),
    // An incoming call takes the microphone; the cut recording is dropped.
    onCallInterruptionOutcome: (outcome) => _deleteRecording(outcome.recording),
  )..addListener(_onVoiceChanged);

  /// A recording handed to [ThoughtCardScreen.onVoiceReply] once the card has
  /// closed. Still set at dispose means it never left, so its file goes.
  AudioRecording? _voiceInHandOff;
  String? _replyPostId;
  ThoughtReplyStatus? _replyStatus;
  bool _sendingReply = false;
  bool _retryingPost = false;
  ThoughtActivity? _activity;
  bool _activityLoading = false;
  bool _activityFailed = false;
  bool _activityExpanded = false;
  int _activityGeneration = 0;

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
    _replySubscription = widget.replyChanges?.listen((message) {
      if (!_post.isIncoming) unawaited(_loadActivity());
      if (!mounted ||
          _closing ||
          message.id != _replyMessageId ||
          _replyPostId != _post.id) {
        return;
      }
      setState(() => _replyStatus = ThoughtReplyStatus.fromMessage(message));
    });
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
    _activityGeneration++;
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
          if (changedPost) {
            _media = const [];
            _replyMessageId = null;
            _submittedReply = null;
            _replyPostId = null;
            _replyStatus = null;
            _sendingReply = false;
            _replyController.clear();
            _activity = null;
            _activityExpanded = false;
            _immersive = false;
          }
        });
        _armExpiry();
        _markWhenShown();
        unawaited(_loadMedia(current.id));
        if (!current.isIncoming) unawaited(_loadActivity());
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
        !_hasVisibleContent ||
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
            !_hasVisibleContent ||
            !_isLive ||
            _loadFailed) {
          return;
        }
        await widget.postRepo.markFocused(postId);
        _markedIds.add(postId);
        // A missing crypto/network prerequisite must not spin a local-focus
        // change loop. The next card open can retry publishing the view.
        try {
          await widget.onShown?.call(postId);
        } catch (_) {}
      } catch (_) {
        // The thought is already on screen; it stays unseen and is marked on
        // the next open.
      } finally {
        _markPendingIds.remove(postId);
      }
    });
  }

  bool get _hasVisibleContent =>
      _post.text.trim().isNotEmpty ||
      _media.any(
        (attachment) =>
            attachment.downloadStatus == 'done' &&
            attachment.localPath != null &&
            File(
              MediaFileManager.resolveStoredPathSync(attachment.localPath!),
            ).existsSync(),
      );

  Future<void> _loadActivity() async {
    final load = widget.loadActivity;
    if (load == null || !mounted || _closing || _post.isIncoming) return;
    final postId = _post.id;
    final generation = ++_activityGeneration;
    setState(() {
      _activityLoading = true;
      _activityFailed = false;
    });
    try {
      final activity = await load(postId);
      if (!mounted ||
          _closing ||
          !_isLive ||
          _post.id != postId ||
          generation != _activityGeneration)
        return;
      setState(() {
        _activity = activity;
        _activityLoading = false;
      });
    } catch (_) {
      if (!mounted ||
          _closing ||
          _post.id != postId ||
          generation != _activityGeneration)
        return;
      setState(() {
        _activity = null;
        _activityLoading = false;
        _activityFailed = true;
      });
    }
  }

  Future<void> _retryPosting() async {
    final retry = widget.retryPosting;
    if (retry == null || _retryingPost || _closing || !_isLive) return;
    final postId = _post.id;
    setState(() => _retryingPost = true);
    try {
      await retry();
    } catch (_) {
      if (mounted && !_closing) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.post_send_failed),
          ),
        );
      }
    } finally {
      if (mounted && !_closing && _post.id == postId) {
        setState(() => _retryingPost = false);
        _requestRefresh();
      }
    }
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
      _markWhenShown();
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
    _markWhenShown();
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
    _replySubscription?.cancel();
    _expiryTimer?.cancel();
    _ageTimer?.cancel();
    _replyController.dispose();
    _replyFocus.dispose();
    _voice
      ..removeListener(_onVoiceChanged)
      ..dispose();
    _deleteRecording(_voiceInHandOff);
    super.dispose();
  }

  void _onVoiceChanged() {
    if (mounted) setState(() {});
  }

  bool get _canRecordVoice =>
      widget.onVoiceReply != null &&
      widget.audioRecorderService != null &&
      !_sendingReply;

  Future<void> _startVoice() async {
    final recorder = widget.audioRecorderService;
    if (recorder == null || _closing || _voice.state.isActive) return;
    final result = await _voice.start(
      recorder: recorder,
      requestPermission: widget.micPermissionGateway.request,
    );
    if (!mounted) return;
    if (result.status == ConversationVoiceCaptureStartStatus.permissionDenied &&
        result.permissionStatus == MicPermissionStatus.permanentlyDenied) {
      await showMicPermissionDeniedPrompt(
        context,
        gateway: widget.micPermissionGateway,
      );
    }
  }

  Future<void> _stopVoice() async {
    if (!_voice.state.isActive) return;
    final outcome = await _voice.stop();
    if (outcome != null) _handOffVoice(outcome);
  }

  /// A finished recording goes to the author's chat, quoting this thought,
  /// the way a typed reply opens that chat after it is sent.
  void _handOffVoice(
    ConversationVoiceCaptureOutcome outcome, {
    bool autoStopped = false,
  }) {
    final recording = outcome.recording;
    final onVoiceReply = widget.onVoiceReply;
    if (recording == null) return;
    if (!mounted ||
        _closing ||
        !_voice.isCurrentOutcome(outcome) ||
        onVoiceReply == null ||
        !_isLive) {
      _deleteRecording(recording);
      if (mounted && !_isLive) _close();
      return;
    }
    final reply = ThoughtVoiceReply(
      recording: recording,
      waveform: outcome.waveform,
      postId: _post.id,
      autoStopped: autoStopped,
    );
    _voiceInHandOff = recording;
    _close(
      afterClose: () {
        _voiceInHandOff = null;
        onVoiceReply(reply);
      },
    );
  }

  /// Removes a finished recording that no chat will send.
  static void _deleteRecording(AudioRecording? recording) {
    if (recording == null) return;
    unawaited(
      File(recording.filePath).delete().then<void>((_) {}, onError: (_) {}),
    );
  }

  Future<void> _sendReply(
    String text, {
    bool retry = false,
    bool openChat = false,
  }) async {
    final onReply = widget.onReply;
    final trimmed = text.trim();
    if (onReply == null || trimmed.isEmpty || _sendingReply || _closing) return;
    if (!_isLive) {
      _close();
      return;
    }
    _replyFocus.unfocus();
    final postId = _post.id;
    final messageId = retry ? _replyMessageId : const Uuid().v4();
    if (messageId == null || (retry && _replyPostId != postId)) return;
    setState(() {
      _sendingReply = true;
      _replyMessageId = messageId;
      _submittedReply = trimmed;
      _replyPostId = postId;
      _replyStatus = ThoughtReplyStatus.queued;
    });
    ThoughtReplyStatus result;
    try {
      final sending = Future<ThoughtReplyStatus>.sync(
        () => onReply(trimmed, postId, messageId),
      );
      // The same durable send continues after the card closes. Chat projects
      // its authored intent immediately, then shows normal delivery and retry.
      // Closing synchronously fences double taps; opening chat never re-sends.
      if (openChat) _close(afterClose: widget.onOpenChat);
      result = await sending;
    } catch (_) {
      result = ThoughtReplyStatus.failed;
    }
    if (!mounted ||
        _closing ||
        _post.id != postId ||
        _replyMessageId != messageId) {
      return;
    }
    setState(() {
      _sendingReply = false;
      _replyStatus = result;
      if (result != ThoughtReplyStatus.failed &&
          _replyController.text.trim() == trimmed) {
        _replyController.clear();
      }
    });
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
                if (hasVisual)
                  Center(child: _visualMedia(l10n, visual))
                else
                  _centeredText(),
                if (!_immersive) ...[
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
                        _bottomChrome(
                          l10n,
                          showText: hasVisual,
                          typing: typing,
                        ),
                      ],
                    ),
                  ),
                ],
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

  /// TRANSLATE_PREVIEW: the "Translate" link under the thought's text. Without
  /// the flag the text is returned as it is.
  Widget _withTranslatePreview(Widget text, {bool stretch = false}) {
    if (!translatePreviewEnabled) return text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: stretch
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.center,
      children: [
        text,
        TranslatePreview(
          text: _post.text,
          ai: translatePreviewAi,
          delivery: translatePreviewDelivery,
          onFreeUpSpace: translatePreviewOpenStorage,
          color: Colors.white,
        ),
      ],
    );
  }

  Widget _centeredText() => Center(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(28, 120, 28, 200),
      child: SingleChildScrollView(
        child: DefaultTextStyle.merge(
          textAlign: TextAlign.center,
          child: _withTranslatePreview(
            LinkableText(
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
    final grid = MediaGrid(
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
    // One photo fills the card the way the full-size viewer shows it: whole,
    // on black. A tap shows it alone and a second tap brings the card back.
    if (_localPhoto(visual) case final photo?) {
      return GestureDetector(
        key: const ValueKey('thought-photo-toggle'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _immersive = !_immersive),
        child: SizedBox.expand(
          child: Image.file(
            File(photo),
            key: const ValueKey('thought-photo-full'),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => grid,
          ),
        ),
      );
    }
    return grid;
  }

  Widget _topChrome(AppLocalizations l10n) {
    final expiry = DateTime.tryParse(_post.expiresAt)?.toUtc();
    final left = expiry?.difference(_now) ?? Duration.zero;
    final goneIn = left.inMinutes >= 60
        ? l10n.thought_gone_in_hours(left.inHours)
        : l10n.thought_gone_in_minutes(left.inMinutes.clamp(1, 59));
    final name = widget.authorName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Column(
        children: [
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
    final content = Column(
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
                child: _withTranslatePreview(
                  LinkableText(
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
                  stretch: true,
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
        if (!_post.isIncoming) ...[
          _postingStatus(l10n),
          if (widget.loadActivity != null) _ownActivity(l10n),
        ],
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
                        ThoughtReaction.applause => l10n.thought_react_applause,
                      },
                      onPressed: _sendingReply
                          ? null
                          : () => unawaited(_sendReply(reaction.glyph)),
                    ),
                    const SizedBox(width: 10),
                  ],
                ],
              ),
            ),
          ComposeArea(
            key: const ValueKey('thought-reply-composer'),
            controller: _replyController,
            focusNode: _replyFocus,
            hintText: l10n.thought_reply_hint(widget.authorName),
            showAttachButton: false,
            clearOnSend: false,
            isSending: _sendingReply,
            onSend: (text) => unawaited(_sendReply(text, openChat: true)),
            onRecordStart: _canRecordVoice
                ? () => unawaited(_startVoice())
                : null,
            onRecordStop: _canRecordVoice
                ? () => unawaited(_stopVoice())
                : null,
            onRecordCancel: () => unawaited(_voice.cancel()),
            recordingState: switch (_voice.state.phase) {
              ConversationVoiceCapturePhase.idle => VoiceRecordingState.idle,
              ConversationVoiceCapturePhase.arming =>
                VoiceRecordingState.arming,
              ConversationVoiceCapturePhase.recording =>
                VoiceRecordingState.recording,
              ConversationVoiceCapturePhase.stopping =>
                VoiceRecordingState.stopping,
            },
            recordingDuration: _voice.state.duration,
            amplitudeValues: _voice.state.amplitudeValues,
          ),
          if (_replyStatus case final status?)
            Row(
              key: const ValueKey('thought-reply-status'),
              children: [
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(switch (status) {
                      ThoughtReplyStatus.sent => l10n.message_status_sent,
                      ThoughtReplyStatus.queued => l10n.post_sending,
                      ThoughtReplyStatus.failed => l10n.error_send_message,
                    }, style: const TextStyle(color: Colors.white)),
                  ),
                ),
                if (!_sendingReply && status != ThoughtReplyStatus.sent)
                  TextButton(
                    key: const ValueKey('thought-reply-retry'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () =>
                        unawaited(_sendReply(_submittedReply!, retry: true)),
                    child: Text(l10n.btn_retry),
                  ),
              ],
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
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: _post.isIncoming
          ? content
          : ConstrainedBox(
              // Keep activity within the inset reserved by the thought's text.
              constraints: BoxConstraints(
                maxHeight: (188 - MediaQuery.paddingOf(context).bottom)
                    .clamp(0.0, 188.0)
                    .toDouble(),
              ),
              child: SingleChildScrollView(primary: false, child: content),
            ),
    );
  }

  Widget _postingStatus(AppLocalizations l10n) {
    final status = _retryingPost ? 'sending' : _post.deliveryStatus;
    final label = switch (status) {
      'sending' =>
        _post.mediaKind != 'none' && _media.isEmpty
            ? l10n.post_uploading
            : l10n.post_sending,
      'partial' => l10n.post_partial,
      'failed' => l10n.post_send_failed,
      'sent' => l10n.message_status_sent,
      _ => null,
    };
    if (label == null) return const SizedBox.shrink();
    return Row(
      key: const ValueKey('thought-posting-status'),
      children: [
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(label, style: const TextStyle(color: Colors.white)),
          ),
        ),
        if (status != 'sent' && widget.retryPosting != null)
          TextButton(
            key: const ValueKey('thought-posting-retry'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: _retryingPost ? null : () => unawaited(_retryPosting()),
            child: Text(l10n.btn_retry),
          ),
      ],
    );
  }

  Widget _ownActivity(AppLocalizations l10n) {
    final activity = _activity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          key: const ValueKey('thought-activity-open'),
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          onPressed: _activityLoading
              ? null
              : () {
                  if (_activityFailed) {
                    unawaited(_loadActivity());
                  } else {
                    setState(() => _activityExpanded = !_activityExpanded);
                  }
                },
          icon: const Icon(Icons.visibility_outlined, size: 18),
          label: Text(
            _activityFailed
                ? l10n.btn_retry
                : activity == null
                ? l10n.thought_activity_title
                : l10n.thought_seen_count(activity.viewers.length),
          ),
        ),
        if (_activityExpanded && activity != null)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.22,
            ),
            child: SingleChildScrollView(
              key: const ValueKey('thought-activity-details'),
              primary: false,
              child: DefaultTextStyle(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.thought_seen_title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      activity.viewers.isEmpty
                          ? l10n.thought_seen_count(0)
                          : activity.viewers
                                .map((viewer) => viewer.name)
                                .join(' · '),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.group_reactions_title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (activity.reactions.isEmpty)
                      Text(l10n.thought_activity_empty),
                    for (final group in activity.reactions) ...[
                      Text(
                        l10n.thought_activity_group(
                          group.participants.first.name,
                          group.participants.length - 1,
                          group.reaction.glyph,
                        ),
                      ),
                      Text(
                        group.participants
                            .map((actor) => actor.name)
                            .join(' · '),
                      ),
                    ],
                  ],
                ),
              ),
            ),
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
  final VoidCallback? onPressed;

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
