import 'package:flutter/material.dart';

import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

class CommentsSheet extends StatefulWidget {
  final PostModel post;
  final List<PostCommentModel> comments;
  final String? focusedCommentId;
  final Future<List<PostCommentModel>> Function(String text) onSubmitComment;
  final Future<List<PostCommentModel>> Function(
    PostCommentModel comment,
    bool isActive,
  )? onToggleCommentHeart;

  const CommentsSheet({
    super.key,
    required this.post,
    required this.comments,
    this.focusedCommentId,
    required this.onSubmitComment,
    this.onToggleCommentHeart,
  });

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final TextEditingController _textController = TextEditingController();
  late List<PostCommentModel> _comments;
  bool _isSubmitting = false;
  final Set<String> _heartingCommentIds = <String>{};

  @override
  void initState() {
    super.initState();
    _comments = _sortComments(widget.comments);
  }

  @override
  void didUpdateWidget(covariant CommentsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comments != widget.comments) {
      _comments = _sortComments(widget.comments);
    }
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final comments = _comments;

    return Material(
      color: const Color(0xFF12161D),
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
                      color: const Color.fromRGBO(255, 255, 255, 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1F27),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.post.authorUsername,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.post.text,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '${comments.length} comments',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: comments.isEmpty
                      ? const Center(
                          child: Text(
                            'No comments yet',
                            style: TextStyle(
                              color: Color.fromRGBO(255, 255, 255, 0.54),
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: comments.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final comment = comments[index];
                            return _CommentTile(
                              comment: comment,
                              isFocused: comment.id == widget.focusedCommentId,
                              isHearting: _heartingCommentIds.contains(comment.id),
                              onToggleHeart: widget.onToggleCommentHeart == null
                                  ? null
                                  : () => _toggleCommentHeart(comment),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        minLines: 1,
                        maxLines: 4,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Add a comment',
                          hintStyle: const TextStyle(
                            color: Color.fromRGBO(255, 255, 255, 0.42),
                          ),
                          filled: true,
                          fillColor: const Color(0xFF1A1F27),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filled(
                      onPressed: _isSubmitting ? null : _submit,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF8FD6B5),
                        foregroundColor: const Color(0xFF132118),
                      ),
                      icon: Icon(
                        _isSubmitting
                            ? Icons.hourglass_top
                            : Icons.arrow_upward,
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
    final displayName = comment.authorUsername.isEmpty
        ? comment.senderPeerId
        : comment.authorUsername;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isFocused ? const Color(0xFF1D2A33) : const Color(0xFF171C23),
        borderRadius: BorderRadius.circular(18),
        border: isFocused
            ? Border.all(color: const Color(0xFF8FD6B5))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  comment.body,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    IconButton(
                      onPressed: onToggleHeart,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      icon: Icon(
                        comment.viewerHasHearted
                            ? Icons.favorite
                            : Icons.favorite_border,
                        size: 18,
                      ),
                      color: comment.viewerHasHearted
                          ? const Color(0xFFEF7C8E)
                          : const Color(0xFF8FD6B5),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      comment.heartCount == 1
                          ? '1 heart'
                          : '${comment.heartCount} hearts',
                      style: const TextStyle(
                        color: Color.fromRGBO(255, 255, 255, 0.54),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (isHearting) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(
            Icons.favorite_border,
            color: Color.fromRGBO(255, 255, 255, 0.48),
            size: 18,
          ),
        ],
      ),
    );
  }
}
