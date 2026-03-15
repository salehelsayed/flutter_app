import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
import 'package:flutter_app/features/posts/application/load_post_comments_use_case.dart';
import 'package:flutter_app/features/posts/application/load_posts_feed_use_case.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/application/send_post_comment_reaction_use_case.dart';
import 'package:flutter_app/features/posts/application/send_post_comment_use_case.dart';
import 'package:flutter_app/features/posts/application/send_post_reaction_use_case.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/application/sweep_expired_posts_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/posts_privacy_settings.dart';
import 'package:flutter_app/features/posts/domain/repositories/contact_presence_snapshot_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/posts_privacy_settings_repository.dart';
import 'package:flutter_app/features/posts/presentation/screens/posts_screen.dart';
import 'package:flutter_app/features/posts/presentation/widgets/comments_sheet.dart';
import 'package:flutter_app/features/posts/presentation/widgets/compose_post_sheet.dart';

class PostsWired extends StatefulWidget {
  final IdentityRepository identityRepo;
  final ContactRepository contactRepo;
  final PostRepository postRepo;
  final P2PService p2pService;
  final Bridge? bridge;
  final MediaFileManager? mediaFileManager;
  final SecureKeyStore? secureKeyStore;
  final ImageProcessor? imageProcessor;
  final AudioRecorderService? audioRecorderService;
  final String activeTab;
  final void Function(String tab) onSwitchView;
  final PendingPostTargetStore? pendingTargetStore;
  final PostsPrivacySettingsRepository postsPrivacySettingsRepository;
  final ContactPresenceSnapshotRepository? contactPresenceSnapshotRepository;
  final NearbyLocationService? nearbyLocationService;

  const PostsWired({
    super.key,
    required this.identityRepo,
    required this.contactRepo,
    required this.postRepo,
    required this.p2pService,
    required this.activeTab,
    required this.onSwitchView,
    this.bridge,
    this.mediaFileManager,
    this.secureKeyStore,
    this.imageProcessor,
    this.audioRecorderService,
    this.pendingTargetStore,
    required this.postsPrivacySettingsRepository,
    this.contactPresenceSnapshotRepository,
    this.nearbyLocationService,
  });

  @override
  State<PostsWired> createState() => _PostsWiredState();
}

class _PostsWiredState extends State<PostsWired> {
  String _username = 'Username';
  String? _peerId;
  List<PostModel> _posts = <PostModel>[];
  String? _focusedPostId;
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _postKeys = <String, GlobalKey>{};
  StreamSubscription<String>? _postChangeSubscription;
  bool _isResolvingPendingTarget = false;
  bool _isOpeningPendingComments = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadIdentity());
    unawaited(_runFeedMaintenanceAndLoad());
    _postChangeSubscription = widget.postRepo.postChanges.listen((_) {
      unawaited(_loadFeed());
      _tryResolvePendingTarget();
    });
    widget.pendingTargetStore?.addListener(_onPendingTargetStoreChanged);
    _tryResolvePendingTarget();
    final nearbyLocationService = widget.nearbyLocationService;
    if (nearbyLocationService != null) {
      unawaited(nearbyLocationService.refreshSilentlyOnPostsOpen());
    }
  }

  @override
  void dispose() {
    _postChangeSubscription?.cancel();
    _scrollController.dispose();
    widget.pendingTargetStore?.removeListener(_onPendingTargetStoreChanged);
    super.dispose();
  }

  void _onPendingTargetStoreChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    unawaited(_tryResolvePendingTarget());
  }

  Future<void> _loadIdentity() async {
    final identity = await widget.identityRepo.loadIdentity();
    if (!mounted || identity == null) return;
    setState(() {
      _username = identity.username;
      _peerId = identity.peerId;
    });
    await _loadFeed();
  }

  Future<void> _runFeedMaintenanceAndLoad() async {
    final mediaFileManager = widget.mediaFileManager;
    if (mediaFileManager != null) {
      await sweepExpiredPosts(
        postRepo: widget.postRepo,
        mediaFileManager: mediaFileManager,
      );
    }
    await _loadFeed();
  }

  Future<void> _loadFeed() async {
    final feed = await loadPostsFeed(
      postRepo: widget.postRepo,
      mediaFileManager: widget.mediaFileManager,
      viewerPeerId: _peerId,
    );
    if (!mounted) return;
    setState(() => _posts = feed);
  }

  Future<void> _compose() async {
    final contacts = await widget.contactRepo.getActiveContacts();
    contacts.removeWhere((contact) => contact.isBlocked);
    final postsPrivacySettings = await widget.postsPrivacySettingsRepository
        .load();
    final nearbyAvailability = await _loadNearbyComposeAvailability(
      postsPrivacySettings,
    );
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ComposePostSheet(
        eligibleContacts: contacts,
        onSubmit: (result) async {
          final identity = await widget.identityRepo.loadIdentity();
          if (identity == null) return;
          await sendPost(
            p2pService: widget.p2pService,
            postRepo: widget.postRepo,
            contactRepo: widget.contactRepo,
            senderPeerId: identity.peerId,
            senderUsername: identity.username,
            text: result.text,
            audience: result.audience,
            mediaDrafts: result.mediaDrafts,
            secureKeyStore: widget.secureKeyStore,
            imageProcessor: widget.imageProcessor,
            mediaFileManager: widget.mediaFileManager,
            bridge: widget.bridge,
            contactPresenceSnapshotRepository:
                widget.contactPresenceSnapshotRepository,
            postsPrivacySettingsRepository:
                widget.postsPrivacySettingsRepository,
          );
          await _loadFeed();
        },
        onAttachMedia: _pickMediaDrafts,
        audioRecorderService: widget.audioRecorderService,
        nearbyAvailability: nearbyAvailability,
        onRefreshNearby: widget.nearbyLocationService == null
            ? null
            : () =>
                widget.nearbyLocationService!.refreshInteractivelyFromCompose(),
        onOpenNearbySettings: widget.nearbyLocationService == null
            ? null
            : widget.nearbyLocationService!.openAppSettings,
      ),
    );
  }

  Future<NearbyComposeAvailability> _loadNearbyComposeAvailability(
    PostsPrivacySettings settings,
  ) async {
    final nearbyLocationService = widget.nearbyLocationService;
    if (nearbyLocationService != null) {
      return nearbyLocationService.loadComposeAvailability();
    }
    return NearbyComposeAvailability(
      state: settings.sharingEnabled
          ? NearbyComposeAvailabilityState.ready
          : NearbyComposeAvailabilityState.sharingOff,
    );
  }

  Future<void> _tryResolvePendingTarget() async {
    if (_isResolvingPendingTarget) {
      return;
    }
    final store = widget.pendingTargetStore;
    final target = store?.target;
    if (store == null || target == null) {
      return;
    }

    _isResolvingPendingTarget = true;
    try {
      final post = await widget.postRepo.getPost(target.postId);
      if (!mounted || post == null) return;

      if (target.opensComments && target.commentId != null) {
        final comments = await loadPostComments(
          postRepo: widget.postRepo,
          postId: target.postId,
          viewerPeerId: _peerId,
        );
        final hasTargetComment = comments.any(
          (comment) => comment.id == target.commentId,
        );
        if (!hasTargetComment) {
          return;
        }
      }

      await widget.postRepo.markFocused(target.postId);
      if (!mounted) return;
      setState(() => _focusedPostId = target.postId);
      _ensureFocusedPostVisible(target.postId);
      if (!target.opensComments || _isOpeningPendingComments) {
        store.clear();
        return;
      }
      _isOpeningPendingComments = true;
      store.clear();
      await _openComments(post, focusCommentId: target.commentId);
      _isOpeningPendingComments = false;
    } finally {
      _isResolvingPendingTarget = false;
    }
  }

  Future<void> _openComments(PostModel post, {String? focusCommentId}) async {
    final comments = await loadPostComments(
      postRepo: widget.postRepo,
      postId: post.id,
      viewerPeerId: _peerId,
    );
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommentsSheet(
        post: post,
        comments: comments,
        focusedCommentId: focusCommentId,
        onSubmitComment: (text) => _submitComment(post, text),
        onToggleCommentHeart: (comment, isActive) =>
            _toggleCommentHeart(post, comment.id, isActive),
      ),
    );
  }

  Future<List<PostCommentModel>> _submitComment(
    PostModel post,
    String text,
  ) async {
    final peerId = _peerId;
    if (peerId == null) {
      return loadPostComments(
        postRepo: widget.postRepo,
        postId: post.id,
        viewerPeerId: _peerId,
      );
    }
    await sendPostComment(
      p2pService: widget.p2pService,
      postRepo: widget.postRepo,
      contactRepo: widget.contactRepo,
      postId: post.id,
      senderPeerId: peerId,
      senderUsername: _username,
      body: text,
    );
    await _loadFeed();
    return loadPostComments(
      postRepo: widget.postRepo,
      postId: post.id,
      viewerPeerId: _peerId,
    );
  }

  Future<void> _togglePostHeart(PostModel post) async {
    final peerId = _peerId;
    if (peerId == null) {
      return;
    }
    await sendPostReaction(
      p2pService: widget.p2pService,
      postRepo: widget.postRepo,
      contactRepo: widget.contactRepo,
      postId: post.id,
      senderPeerId: peerId,
      isActive: !post.viewerHasHearted,
    );
    await _loadFeed();
  }

  Future<List<PostCommentModel>> _toggleCommentHeart(
    PostModel post,
    String commentId,
    bool isActive,
  ) async {
    final peerId = _peerId;
    if (peerId == null) {
      return loadPostComments(
        postRepo: widget.postRepo,
        postId: post.id,
        viewerPeerId: _peerId,
      );
    }
    await sendPostCommentReaction(
      p2pService: widget.p2pService,
      postRepo: widget.postRepo,
      contactRepo: widget.contactRepo,
      postId: post.id,
      commentId: commentId,
      senderPeerId: peerId,
      isActive: isActive,
    );
    await _loadFeed();
    return loadPostComments(
      postRepo: widget.postRepo,
      postId: post.id,
      viewerPeerId: _peerId,
    );
  }

  Future<List<PostMediaDraft>> _pickMediaDrafts() async {
    final picker = SystemMediaPicker();
    final selections = await picker.pickMultipleMedia();
    if (selections.isEmpty) {
      return const <PostMediaDraft>[];
    }

    final firstMime = _mimeFromPath(selections.first.path);
    final firstKind = _kindFromMime(firstMime);
    final filtered = selections
        .where((file) {
          return _kindFromMime(_mimeFromPath(file.path)) == firstKind;
        })
        .toList(growable: false);
    final limited = firstKind == 'image' ? filtered : filtered.take(1).toList();
    return limited
        .map(
          (file) => PostMediaDraft(
            localFilePath: file.path,
            mime: _mimeFromPath(file.path),
          ),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return PostsScreen(
      username: _username,
      posts: _posts,
      scrollController: _scrollController,
      postKeys: _postKeys,
      activeTab: widget.activeTab,
      onSwitchView: widget.onSwitchView,
      onCompose: _compose,
      onOpenComments: _openComments,
      onToggleHeart: _togglePostHeart,
      focusedPostId: _focusedPostId,
      statusMessage: widget.pendingTargetStore?.statusMessage,
    );
  }

  void _ensureFocusedPostVisible(String postId) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final postContext = _postKeys[postId]?.currentContext;
      if (!mounted || postContext == null) {
        return;
      }
      await Scrollable.ensureVisible(
        postContext,
        duration: const Duration(milliseconds: 220),
        alignment: 0.12,
      );
    });
  }
}

String _mimeFromPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.heic')) return 'image/heic';
  if (lower.endsWith('.mp4')) return 'video/mp4';
  if (lower.endsWith('.mov')) return 'video/quicktime';
  if (lower.endsWith('.m4a')) return 'audio/mp4';
  if (lower.endsWith('.mp3')) return 'audio/mpeg';
  if (lower.endsWith('.ogg')) return 'audio/ogg';
  return 'application/octet-stream';
}

String _kindFromMime(String mime) {
  if (mime.startsWith('image/')) return 'image';
  if (mime.startsWith('video/')) return 'video';
  if (mime.startsWith('audio/')) return 'voice';
  return 'other';
}
