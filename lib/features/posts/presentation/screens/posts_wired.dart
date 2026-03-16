import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
import 'package:flutter_app/features/posts/application/dismiss_pin_use_case.dart';
import 'package:flutter_app/features/posts/application/edit_pinned_post_use_case.dart';
import 'package:flutter_app/features/posts/application/load_post_comments_use_case.dart';
import 'package:flutter_app/features/posts/application/load_pinned_posts_use_case.dart';
import 'package:flutter_app/features/posts/application/load_posts_feed_use_case.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/application/pass_post_along_use_case.dart';
import 'package:flutter_app/features/posts/application/pin_post_use_case.dart';
import 'package:flutter_app/features/posts/application/post_delivery_runner.dart'
    as delivery;
import 'package:flutter_app/features/posts/application/remove_pin_use_case.dart';
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
import 'package:flutter_app/features/posts/presentation/widgets/edit_pinned_post_sheet.dart';
import 'package:flutter_app/features/posts/presentation/widgets/pass_post_along_sheet.dart';

class PostsWired extends StatefulWidget {
  final IdentityRepository identityRepo;
  final ContactRepository contactRepo;
  final PostRepository postRepo;
  final P2PService p2pService;
  final Bridge? bridge;
  final MediaFileManager? mediaFileManager;
  final SecureKeyStore? secureKeyStore;
  final ImageProcessor? imageProcessor;
  final Future<List<PostMediaDraft>> Function()? onAttachMedia;
  final UploadPostMediaFn? uploadPostMediaFn;
  final AudioRecorderService? audioRecorderService;
  final String activeTab;
  final void Function(String tab) onSwitchView;
  final PendingPostTargetStore? pendingTargetStore;
  final PostsPrivacySettingsRepository postsPrivacySettingsRepository;
  final ContactPresenceSnapshotRepository? contactPresenceSnapshotRepository;
  final NearbyLocationService? nearbyLocationService;
  final MessageRepository? messageRepo;
  final ChatMessageListener? chatMessageListener;
  final MediaAttachmentRepository? mediaAttachmentRepo;
  final ReactionRepository? reactionRepo;
  final ReactionListener? reactionListener;
  final IntroductionRepository? introductionRepository;
  final ActiveConversationTracker? conversationTracker;

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
    this.onAttachMedia,
    this.uploadPostMediaFn,
    this.audioRecorderService,
    this.pendingTargetStore,
    required this.postsPrivacySettingsRepository,
    this.contactPresenceSnapshotRepository,
    this.nearbyLocationService,
    this.messageRepo,
    this.chatMessageListener,
    this.mediaAttachmentRepo,
    this.reactionRepo,
    this.reactionListener,
    this.introductionRepository,
    this.conversationTracker,
  });

  @override
  State<PostsWired> createState() => _PostsWiredState();
}

class _PostsWiredState extends State<PostsWired> {
  static const Duration _postChangeRefreshDebounce = Duration(
    milliseconds: 100,
  );

  String _username = 'Username';
  String? _peerId;
  List<PostModel> _posts = <PostModel>[];
  List<PostModel> _pinnedPosts = <PostModel>[];
  String? _focusedPostId;
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _postKeys = <String, GlobalKey>{};
  StreamSubscription<String>? _postChangeSubscription;
  Timer? _postChangeRefreshTimer;
  bool _isPostChangeRefreshInFlight = false;
  bool _hasTrailingPostChangeRefresh = false;
  bool _isResolvingPendingTarget = false;
  bool _isOpeningPendingComments = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeSurface());
    _postChangeSubscription = widget.postRepo.postChanges.listen((_) {
      _schedulePostChangeRefresh();
      unawaited(_tryResolvePendingTarget());
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
    _postChangeRefreshTimer?.cancel();
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

  Future<void> _initializeSurface() async {
    final mediaFileManager = widget.mediaFileManager;
    if (mediaFileManager != null) {
      await sweepExpiredPosts(
        postRepo: widget.postRepo,
        mediaFileManager: mediaFileManager,
      );
    }
    final identity = await widget.identityRepo.loadIdentity();
    if (mounted && identity != null) {
      setState(() {
        _username = identity.username;
        _peerId = identity.peerId;
      });
    }
    await _loadSurface(reconcileLingeringSending: true);
  }

  Future<void> _loadSurface({bool reconcileLingeringSending = false}) async {
    var feed = await loadPostsFeed(
      postRepo: widget.postRepo,
      mediaFileManager: widget.mediaFileManager,
      viewerPeerId: _peerId,
    );
    var pinned = await loadPinnedPosts(
      postRepo: widget.postRepo,
      mediaFileManager: widget.mediaFileManager,
      viewerPeerId: _peerId,
    );
    if (reconcileLingeringSending) {
      final reconciledPosts = await _reconcileLingeringSendingPosts(<PostModel>[
        ...feed,
        ...pinned,
      ]);
      feed = feed
          .map((post) => reconciledPosts[post.id] ?? post)
          .toList(growable: false);
      pinned = pinned
          .map((post) => reconciledPosts[post.id] ?? post)
          .toList(growable: false);
    }
    if (!mounted) return;
    setState(() {
      _posts = feed;
      _pinnedPosts = pinned;
    });
  }

  void _schedulePostChangeRefresh() {
    _postChangeRefreshTimer?.cancel();
    _postChangeRefreshTimer = Timer(_postChangeRefreshDebounce, () {
      _postChangeRefreshTimer = null;
      unawaited(_runPostChangeRefresh());
    });
  }

  Future<void> _runPostChangeRefresh() async {
    if (_isPostChangeRefreshInFlight) {
      _hasTrailingPostChangeRefresh = true;
      return;
    }
    _isPostChangeRefreshInFlight = true;
    try {
      do {
        _hasTrailingPostChangeRefresh = false;
        await _loadSurface();
      } while (_hasTrailingPostChangeRefresh);
    } finally {
      _isPostChangeRefreshInFlight = false;
    }
  }

  Future<Map<String, PostModel>> _reconcileLingeringSendingPosts(
    Iterable<PostModel> posts,
  ) async {
    final reconciled = <String, PostModel>{};
    for (final post in posts) {
      if (reconciled.containsKey(post.id) ||
          post.deliveryStatus != 'sending' ||
          post.isIncoming) {
        reconciled.putIfAbsent(post.id, () => post);
        continue;
      }

      final deliveries = await widget.postRepo.getRecipientDeliveries(post.id);
      final aggregate = delivery.aggregatePostDeliveryStatusFromDeliveries(
        deliveries,
      );
      if (aggregate.deliveryStatus == 'sending') {
        reconciled[post.id] = post;
        continue;
      }

      final updatedPost = post.copyWith(
        deliveryStatus: aggregate.deliveryStatus,
      );
      await widget.postRepo.savePost(updatedPost);
      reconciled[post.id] = updatedPost;
    }
    return reconciled;
  }

  Future<void> _compose() async {
    final contacts = await widget.contactRepo.getActiveContacts();
    contacts.removeWhere((contact) => contact.isBlocked);
    final viewerPeerId = _peerId;
    final activePinCount = viewerPeerId == null
        ? 0
        : _pinnedPosts
              .where((post) => post.authorPeerId == viewerPeerId)
              .length;
    final postsPrivacySettings = await widget.postsPrivacySettingsRepository
        .load();
    final nearbyAvailability = await _loadNearbyComposeAvailability(
      postsPrivacySettings,
    );
    delivery.CreatedLocalPost? createdPost;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ComposePostSheet(
        eligibleContacts: contacts,
        onSubmitWithOutcome: (result) async {
          final identity = await widget.identityRepo.loadIdentity();
          if (identity == null) {
            return ComposePostSubmitOutcome.closeSheet;
          }
          final (createResult, created) = await createLocalPost(
            postRepo: widget.postRepo,
            contactRepo: widget.contactRepo,
            senderPeerId: identity.peerId,
            senderUsername: identity.username,
            text: result.text,
            audience: result.audience,
            mediaDrafts: result.mediaDrafts,
            contactPresenceSnapshotRepository:
                widget.contactPresenceSnapshotRepository,
            postsPrivacySettingsRepository:
                widget.postsPrivacySettingsRepository,
          );
          if (createResult != SendPostResult.success || created == null) {
            return ComposePostSubmitOutcome.keepSheetOpen;
          }
          createdPost = created;
          return ComposePostSubmitOutcome.closeSheet;
        },
        onAttachMedia: widget.onAttachMedia ?? _pickMediaDrafts,
        audioRecorderService: widget.audioRecorderService,
        nearbyAvailability: nearbyAvailability,
        activePinCount: activePinCount,
        onManagePins: activePinCount == 0
            ? null
            : () {
                Navigator.of(context).pop();
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                );
              },
        onRefreshNearby: widget.nearbyLocationService == null
            ? null
            : () => widget.nearbyLocationService!
                  .refreshInteractivelyFromCompose(),
        onOpenNearbySettings: widget.nearbyLocationService == null
            ? null
            : widget.nearbyLocationService!.openAppSettings,
      ),
    );
    final created = createdPost;
    if (created != null) {
      unawaited(_startBackgroundDelivery(created));
    }
  }

  Future<void> _startBackgroundDelivery(
    delivery.CreatedLocalPost created,
  ) async {
    final (prepareResult, prepared) = await prepareCreatedLocalPostMedia(
      created: created,
      postRepo: widget.postRepo,
      secureKeyStore: widget.secureKeyStore,
      imageProcessor: widget.imageProcessor,
      mediaFileManager: widget.mediaFileManager,
      uploadPostMediaFn: widget.uploadPostMediaFn,
      bridge: widget.bridge,
    );
    if (prepareResult != SendPostResult.success || prepared == null) {
      return;
    }
    await delivery.PostDeliveryRunner(
      p2pService: widget.p2pService,
      postRepo: widget.postRepo,
      bridge: widget.bridge,
    ).execute(prepared);
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
        viewerPeerId: _peerId,
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
    await _loadSurface();
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
    await _loadSurface();
  }

  Future<void> _passAlong(PostModel post) async {
    final peerId = _peerId;
    if (peerId == null) {
      return;
    }
    final contacts = await widget.contactRepo.getActiveContacts();
    contacts.removeWhere(
      (contact) =>
          contact.isBlocked ||
          contact.peerId == peerId ||
          contact.peerId == post.authorPeerId,
    );
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PassPostAlongSheet(
        eligibleContacts: contacts,
        onSubmit: (recipientPeerIds) async {
          await passPostAlong(
            p2pService: widget.p2pService,
            postRepo: widget.postRepo,
            contactRepo: widget.contactRepo,
            postId: post.id,
            senderPeerId: peerId,
            senderUsername: _username,
            recipientPeerIds: recipientPeerIds,
          );
          await _loadSurface();
        },
      ),
    );
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
    await _loadSurface();
    return loadPostComments(
      postRepo: widget.postRepo,
      postId: post.id,
      viewerPeerId: _peerId,
    );
  }

  Future<void> _dismissPinnedPost(PostModel post) async {
    await dismissPin(postRepo: widget.postRepo, postId: post.id);
    await _loadSurface();
  }

  Future<void> _pinPost(PostModel post) async {
    final peerId = _peerId;
    if (peerId == null) {
      return;
    }
    final (result, _) = await pinPost(
      p2pService: widget.p2pService,
      postRepo: widget.postRepo,
      postId: post.id,
      senderPeerId: peerId,
    );
    if (!mounted) {
      return;
    }
    setState(() => _statusMessage = _pinStatusMessage(result));
    await _loadSurface();
  }

  Future<void> _editPinnedPost(PostModel post) async {
    final peerId = _peerId;
    if (peerId == null || !mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditPinnedPostSheet(
        initialText: post.text,
        onSubmit: (text) async {
          final (result, _) = await editPinnedPost(
            p2pService: widget.p2pService,
            postRepo: widget.postRepo,
            postId: post.id,
            senderPeerId: peerId,
            text: text,
          );
          if (!mounted) {
            return;
          }
          setState(() => _statusMessage = _editPinnedPostStatusMessage(result));
          await _loadSurface();
        },
      ),
    );
  }

  Future<void> _removePinnedPost(PostModel post) async {
    final peerId = _peerId;
    if (peerId == null) {
      return;
    }
    final (result, _) = await removePin(
      p2pService: widget.p2pService,
      postRepo: widget.postRepo,
      postId: post.id,
      senderPeerId: peerId,
    );
    if (!mounted) {
      return;
    }
    setState(() => _statusMessage = _removePinStatusMessage(result));
    await _loadSurface();
  }

  String? _pinStatusMessage(PinPostResult result) {
    return switch (result) {
      PinPostResult.success => null,
      PinPostResult.partiallySettled => 'Pin update will continue retrying',
      PinPostResult.queuedForRetry => 'Pin update queued for retry',
      PinPostResult.sendFailed => 'Pin update failed',
      PinPostResult.nodeNotRunning ||
      PinPostResult.postNotFound ||
      PinPostResult.notAuthor ||
      PinPostResult.noRecipients => 'Could not pin post',
    };
  }

  String? _editPinnedPostStatusMessage(EditPinnedPostResult result) {
    return switch (result) {
      EditPinnedPostResult.success => null,
      EditPinnedPostResult.partiallySettled =>
        'Pinned post update will continue retrying',
      EditPinnedPostResult.queuedForRetry =>
        'Pinned post update queued for retry',
      EditPinnedPostResult.sendFailed => 'Pinned post update failed',
      EditPinnedPostResult.nodeNotRunning ||
      EditPinnedPostResult.postNotFound ||
      EditPinnedPostResult.notAuthor ||
      EditPinnedPostResult.notPinned ||
      EditPinnedPostResult.noRecipients => 'Could not update pinned post',
    };
  }

  String? _removePinStatusMessage(RemovePinResult result) {
    return switch (result) {
      RemovePinResult.success => null,
      RemovePinResult.partiallySettled => 'Pin removal will continue retrying',
      RemovePinResult.queuedForRetry => 'Pin removal queued for retry',
      RemovePinResult.sendFailed => 'Pin removal failed',
      RemovePinResult.nodeNotRunning ||
      RemovePinResult.postNotFound ||
      RemovePinResult.notAuthor ||
      RemovePinResult.notPinned ||
      RemovePinResult.noRecipients => 'Could not remove pin',
    };
  }

  Future<void> _messagePinnedPostAuthor(PostModel post) async {
    final messageRepo = widget.messageRepo;
    final chatListener = widget.chatMessageListener;
    final mediaAttachmentRepo = widget.mediaAttachmentRepo;
    if (messageRepo == null ||
        chatListener == null ||
        mediaAttachmentRepo == null ||
        !mounted) {
      return;
    }
    final contact = await widget.contactRepo.getContact(post.authorPeerId);
    if (contact == null || !mounted) {
      return;
    }

    await Navigator.of(context).push(
      buildConversationSlideUpRoute(
        builder: (_) => ConversationWired(
          contact: contact,
          identityRepo: widget.identityRepo,
          messageRepo: messageRepo,
          chatMessageListener: chatListener,
          p2pService: widget.p2pService,
          bridge: widget.bridge,
          contactRepo: widget.contactRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: widget.mediaFileManager,
          imageProcessor: widget.imageProcessor,
          conversationTracker: widget.conversationTracker,
          audioRecorderService: widget.audioRecorderService,
          reactionRepo: widget.reactionRepo,
          reactionListener: widget.reactionListener,
          introductionRepository: widget.introductionRepository,
        ),
      ),
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
    final canMessagePinnedAuthors =
        widget.messageRepo != null &&
        widget.chatMessageListener != null &&
        widget.mediaAttachmentRepo != null;
    return PostsScreen(
      username: _username,
      posts: _posts,
      pinnedPosts: _pinnedPosts,
      viewerPeerId: _peerId,
      scrollController: _scrollController,
      postKeys: _postKeys,
      activeTab: widget.activeTab,
      onSwitchView: widget.onSwitchView,
      onCompose: _compose,
      onOpenComments: _openComments,
      onToggleHeart: _togglePostHeart,
      onPassAlong: _passAlong,
      onPinPost: _pinPost,
      onDismissPin: _dismissPinnedPost,
      onMessageFromPin: canMessagePinnedAuthors
          ? _messagePinnedPostAuthor
          : null,
      onEditPinnedPost: _editPinnedPost,
      onRemovePin: _removePinnedPost,
      focusedPostId: _focusedPostId,
      statusMessage: _statusMessage ?? widget.pendingTargetStore?.statusMessage,
      activePinnedPostIds: _pinnedPosts.map((post) => post.id).toSet(),
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
