import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/posts/application/load_posts_feed_use_case.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/posts/presentation/screens/posts_screen.dart';
import 'package:flutter_app/features/posts/presentation/widgets/compose_post_sheet.dart';

class PostsWired extends StatefulWidget {
  final IdentityRepository identityRepo;
  final ContactRepository contactRepo;
  final PostRepository postRepo;
  final P2PService p2pService;
  final Bridge? bridge;
  final String activeTab;
  final void Function(String tab) onSwitchView;
  final PendingPostTargetStore? pendingTargetStore;

  const PostsWired({
    super.key,
    required this.identityRepo,
    required this.contactRepo,
    required this.postRepo,
    required this.p2pService,
    required this.activeTab,
    required this.onSwitchView,
    this.bridge,
    this.pendingTargetStore,
  });

  @override
  State<PostsWired> createState() => _PostsWiredState();
}

class _PostsWiredState extends State<PostsWired> {
  String _username = 'Username';
  List<PostModel> _posts = <PostModel>[];
  String? _focusedPostId;
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _postKeys = <String, GlobalKey>{};
  StreamSubscription<String>? _postChangeSubscription;
  bool _isResolvingPendingTarget = false;

  @override
  void initState() {
    super.initState();
    _loadIdentity();
    _loadFeed();
    _postChangeSubscription = widget.postRepo.postChanges.listen((_) {
      unawaited(_loadFeed());
      _tryResolvePendingTarget();
    });
    widget.pendingTargetStore?.addListener(_onPendingTargetStoreChanged);
    _tryResolvePendingTarget();
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
    setState(() => _username = identity.username);
  }

  Future<void> _loadFeed() async {
    final feed = await loadPostsFeed(postRepo: widget.postRepo);
    if (!mounted) return;
    setState(() => _posts = feed);
  }

  Future<void> _compose() async {
    final contacts = await widget.contactRepo.getActiveContacts();
    contacts.removeWhere((contact) => contact.isBlocked);
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
            bridge: widget.bridge,
          );
          await _loadFeed();
        },
      ),
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

      await widget.postRepo.markFocused(target.postId);
      if (!mounted) return;
      setState(() => _focusedPostId = target.postId);
      _ensureFocusedPostVisible(target.postId);
      store.clear();
    } finally {
      _isResolvingPendingTarget = false;
    }
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
