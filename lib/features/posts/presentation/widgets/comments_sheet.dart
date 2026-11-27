import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

class CommentsSheet extends StatefulWidget {
  final PostModel post;
  final List<PostCommentModel> comments;
  final String? focusedCommentId;
  final String? viewerPeerId;
  final Future<List<PostCommentModel>> Function(String text) onSubmitComment;
  final Future<List<PostCommentModel>> Function(
    PostCommentModel comment,
    bool isActive,
  )?
  onToggleCommentHeart;

  const CommentsSheet({
    super.key,
    required this.post,
    required this.comments,
    this.focusedCommentId,
    this.viewerPeerId,
    required this.onSubmitComment,
    this.onToggleCommentHeart,
  });

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _commentsScrollController = ScrollController();
  late List<PostCommentModel> _comments;
  bool _isSubmitting = false;
  final Set<String> _heartingCommentIds = <String>{};

  @override
  void initState() {
    super.initState();
    _comments = _sortComments(widget.comments);
    _scheduleScrollToLatest();
  }

  @override
  void didUpdateWidget(covariant CommentsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comments != widget.comments) {
      final previousComments = _comments;
      final updatedComments = _sortComments(widget.comments);
      final previousLatestCommentId = previousComments.isEmpty
          ? null
          : previousComments.last.id;
      final updatedLatestCommentId = updatedComments.isEmpty
          ? null
          : updatedComments.last.id;
      _comments = updatedComments;
      if (updatedComments.length != previousComments.length ||
          updatedLatestCommentId != previousLatestCommentId) {
        _scheduleScrollToLatest();
      }
    }
  }

  @override
  void dispose() {
    _commentsScrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final trimmed = _textController.text.trim();
    if (trimmed.isEmpty || _isSubmitting) {
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final updatedComments = await widget.onSubmitComment(trimmed);
      if (!mounted) {
        return;
      }
      setState(() => _comments = _sortComments(updatedComments));
      _textController.clear();
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _toggleCommentHeart(PostCommentModel comment) async {
    final callback = widget.onToggleCommentHeart;
    if (callback == null || _heartingCommentIds.contains(comment.id)) {
      return;
    }
    setState(() => _heartingCommentIds.add(comment.id));
    try {
      final updatedComments = await callback(
        comment,
        !comment.viewerHasHearted,
      );
      if (!mounted) {
        return;
      }
      setState(() => _comments = _sortComments(updatedComments));
    } finally {
      if (mounted) {
        setState(() => _heartingCommentIds.remove(comment.id));
      }
    }
  }

  List<PostCommentModel> _sortComments(List<PostCommentModel> comments) {
    final sorted = List<PostCommentModel>.from(comments);
    sorted.sort((a, b) {
      final timestampCompare = a.commentedAt.compareTo(b.commentedAt);
      if (timestampCompare != 0) {
        return timestampCompare;
      }
      return a.id.compareTo(b.id);
    });
    return sorted;
  }

  void _scheduleScrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_commentsScrollController.hasClients) {
        return;
      }
      final targetOffset = _commentsScrollController.position.maxScrollExtent;
      if ((_commentsScrollController.offset - targetOffset).abs() < 0.5) {
        return;
      }
      _commentsScrollController.jumpTo(targetOffset);
    });
  }

  @override
  Widget build(BuildContext context) {
    final comments = _comments;
    final l10n = AppLocalizations.of(context)!;
    final colors = context.backgroundReadableColors;
    final light = colors.isLightSurface;
    final ink = light ? colors.textPrimary : Colors.white;
    final panel = light ? colors.surfaceSubtle : const Color(0xFF1A1F27);
    final actionFill = light
        ? colors.surfaceRaised
        : const Color.fromRGBO(255, 255, 255, 0.08);
    final detail = light
        ? colors.textSecondary
        : const Color.fromRGBO(255, 255, 255, 0.54);

    return Material(
      color: light ? colors.surfaceRaised : const Color(0xFF12161D),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 540,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: light
                          ? colors.divider
                          : const Color.fromRGBO(255, 255, 255, 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(4, 0, 0, 0),
                  decoration: BoxDecoration(
                    color: panel,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        UserAvatar(peerId: widget.post.authorPeerId, size: 42),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      widget.post.authorUsername,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: ink,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _formatRelativeTimestamp(
                                      widget.post.createdAt,
                                      context,
                                    ),
                                    style: TextStyle(
                                      color: light
                                          ? colors.textMuted
                                          : const Color.fromRGBO(
                                              255,
                                              255,
                                              255,
                                              0.36,
                                            ),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.post.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textDirection: detectTextDirection(
                                  widget.post.text,
                                ),
                                style: TextStyle(
                                  color: light
                                      ? colors.textSecondary
                                      : const Color.fromRGBO(
                                          255,
                                          255,
                                          255,
                                          0.48,
                                        ),
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () => Navigator.of(context).maybePop(),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: actionFill,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close,
                              size: 20,
                              color: light
                                  ? colors.iconSecondary
                                  : const Color.fromRGBO(255, 255, 255, 0.52),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  l10n.comments_count(comments.length),
                  style: TextStyle(
                    color: detail,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: comments.isEmpty
                      ? Center(
                          child: Text(
                            l10n.comments_empty,
                            style: TextStyle(color: detail),
                          ),
                        )
                      : ListView.separated(
                          key: const ValueKey<String>('comments-list'),
                          controller: _commentsScrollController,
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: comments.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            thickness: 1,
                            color: light
                                ? colors.divider
                                : const Color.fromRGBO(255, 255, 255, 0.08),
                          ),
                          itemBuilder: (context, index) {
                            final comment = comments[index];
                            return _CommentTile(
                              comment: comment,
                              isFocused: comment.id == widget.focusedCommentId,
                              isHearting: _heartingCommentIds.contains(
                                comment.id,
                              ),
                              onToggleHeart: widget.onToggleCommentHeart == null
                                  ? null
                                  : () => _toggleCommentHeart(comment),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    UserAvatar(peerId: widget.viewerPeerId, size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        key: const ValueKey<String>('comments-composer-pill'),
                        padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
                        decoration: BoxDecoration(
                          color: panel,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: light
                                ? colors.inputBorder
                                : const Color.fromRGBO(255, 255, 255, 0.06),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _textController,
                                minLines: 1,
                                maxLines: 4,
                                textDirection: detectTextDirection(
                                  _textController.text,
                                ),
                                onChanged: (_) => setState(() {}),
                                style: TextStyle(color: ink),
                                decoration: InputDecoration(
                                  hintText: AppLocalizations.of(context)!
                                      .comment_hint,
                                  hintStyle: TextStyle(
                                    color: light
                                        ? colors.placeholderText
                                        : const Color.fromRGBO(
                                            255,
                                            255,
                                            255,
                                            0.42,
                                          ),
                                  ),
                                  border: InputBorder.none,
                                  // The surrounding container paints the fill;
                                  // the light theme's filled
                                  // InputDecorationTheme would otherwise paint
                                  // a square fill rect on top of it.
                                  filled: false,
                                  isCollapsed: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Material(
                              color: actionFill,
                              shape: const CircleBorder(),
                              child: IconButton(
                                onPressed: _isSubmitting ? null : _submit,
                                icon: Icon(
                                  _isSubmitting
                                      ? Icons.hourglass_top
                                      : Icons.send_rounded,
                                  color: light
                                      ? colors.sendIcon
                                      : const Color.fromRGBO(
                                          255,
                                          255,
                                          255,
                                          0.72,
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final PostCommentModel comment;
  final bool isFocused;
  final bool isHearting;
  final VoidCallback? onToggleHeart;

  const _CommentTile({
    required this.comment,
    this.isFocused = false,
    this.isHearting = false,
    this.onToggleHeart,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.backgroundReadableColors;
    final light = colors.isLightSurface;
    final detail = light
        ? colors.textMuted
        : const Color.fromRGBO(255, 255, 255, 0.36);
    final displayName = comment.authorUsername.isEmpty
        ? comment.senderPeerId
        : comment.authorUsername;

    final focusFill = light
        ? colors.navActiveFill
        : const Color.fromRGBO(143, 214, 181, 0.08);
    final focusBorder = light
        ? colors.accent
        : const Color.fromRGBO(143, 214, 181, 0.28);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      decoration: BoxDecoration(
        color: isFocused ? focusFill : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: isFocused ? Border.all(color: focusBorder) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(peerId: comment.senderPeerId, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: light ? colors.textPrimary : Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatRelativeTimestamp(comment.commentedAt, context),
                      style: TextStyle(
                        color: light
                            ? colors.textMuted
                            : const Color.fromRGBO(255, 255, 255, 0.32),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.body,
                  textDirection: detectTextDirection(comment.body),
                  style: TextStyle(
                    color: light
                        ? colors.textPrimary
                        : const Color.fromRGBO(255, 255, 255, 0.82),
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: onToggleHeart,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    comment.viewerHasHearted
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: comment.viewerHasHearted
                        ? (light
                              ? Theme.of(context).colorScheme.error
                              : const Color(0xFFEF7C8E))
                        : detail,
                    size: 20,
                  ),
                  if (comment.heartCount > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      comment.heartCount.toString(),
                      style: TextStyle(
                        color: detail,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  if (isHearting) ...[
                    const SizedBox(width: 6),
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatRelativeTimestamp(String rawTimestamp, BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  final timestamp = DateTime.tryParse(rawTimestamp)?.toUtc();
  if (timestamp == null) {
    return rawTimestamp;
  }
  final diff = DateTime.now().toUtc().difference(timestamp);
  if (diff.inSeconds < 0) {
    return '';
  }
  if (diff.inMinutes < 1) {
    return l10n.time_just_now;
  }
  if (diff.inMinutes < 60) {
    return l10n.time_min_ago(diff.inMinutes);
  }
  if (diff.inHours < 24) {
    return l10n.time_hour_ago(diff.inHours);
  }
  if (diff.inDays < 7) {
    return l10n.time_day_ago(diff.inDays);
  }
  return l10n.time_week_ago((diff.inDays / 7).floor());
}
