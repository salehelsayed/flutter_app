import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/orbit/domain/orbit_depth_visit.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/thought_quote.dart';
import 'package:flutter_app/features/posts/domain/thought_reply_status.dart';
import 'package:flutter_app/features/posts/presentation/widgets/thought_reaction_circle.dart';
import 'package:flutter_app/features/stickers/presentation/custom_sticker_scope.dart';
import 'package:flutter_app/features/stickers/presentation/sticker_panel.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// The reply controls for a Thought in either presentation. The host owns
/// focus and expiry because it also owns the card and its Back action.
class ThoughtReplyDock extends StatefulWidget {
  const ThoughtReplyDock({
    super.key,
    required this.post,
    required this.authorName,
    required this.media,
    required this.controller,
    required this.focusNode,
    required this.typing,
    required this.visit,
    required this.reactionKeyPrefix,
    required this.onReaction,
    required this.onSend,
    this.onSticker,
    this.onReactionActivate,
    this.sendEnabled = true,
    this.graceSeconds,
    this.onScrim = false,
  });

  final PostModel post;
  final String authorName;
  final List<PostMediaAttachmentModel> media;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool typing;
  final OrbitDepthVisit visit;
  final String reactionKeyPrefix;
  final ValueChanged<ThoughtReaction> onReaction;
  final ValueChanged<ThoughtReaction>? onReactionActivate;
  final VoidCallback onSend;
  final bool sendEnabled;
  final ValueChanged<ThoughtStickerSelection>? onSticker;

  /// Null while live. Zero leaves an ended composition visible for closing.
  final int? graceSeconds;
  final bool onScrim;

  @override
  State<ThoughtReplyDock> createState() => _ThoughtReplyDockState();
}

class _ThoughtReplyDockState extends State<ThoughtReplyDock> {
  ModalRoute<dynamic>? _picker;
  bool _openingPicker = false;
  int? _firstGraceSeconds;

  @override
  void didUpdateWidget(ThoughtReplyDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.graceSeconds == null) {
      _firstGraceSeconds = widget.graceSeconds;
    }
    if (oldWidget.post.id != widget.post.id || widget.graceSeconds != null) {
      _dismissOwnedPicker();
    }
  }

  void _dismissOwnedPicker() {
    final route = _picker;
    _picker = null;
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = route.navigator;
      if (route.isActive && navigator?.mounted == true) {
        navigator!.removeRoute(route);
      }
    });
  }

  @override
  void dispose() {
    _dismissOwnedPicker();
    super.dispose();
  }

  Future<void> _openPicker() async {
    if (_openingPicker || widget.onSticker == null) return;
    _openingPicker = true;
    final postId = widget.post.id;
    final custom = CustomStickerScope.libraryOf(context);
    try {
      final selected = await showModalBottomSheet<ThoughtStickerSelection>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
            ? AnimationStyle.noAnimation
            : null,
        builder: (sheetContext) {
          final route = ModalRoute.of(sheetContext);
          _picker = route;
          return SizedBox(
            height: kStickerPanelHeight,
            child: BundledStickerPanel(
              onSend: (entry) => Navigator.of(
                sheetContext,
              ).pop(ThoughtStickerSelection.bundled(entry)),
              onSendCustom: custom == null
                  ? null
                  : (id) async {
                      final items = await custom.list();
                      final item = items
                          .where((item) => item.id == id)
                          .firstOrNull;
                      if (item != null &&
                          sheetContext.mounted &&
                          route?.isCurrent == true) {
                        Navigator.of(sheetContext).pop(
                          ThoughtStickerSelection.custom(
                            id,
                            item.asset.filePath,
                          ),
                        );
                      }
                    },
            ),
          );
        },
      );
      if (mounted &&
          selected != null &&
          widget.post.id == postId &&
          widget.graceSeconds == null) {
        widget.onSticker?.call(selected);
      }
    } finally {
      _picker = null;
      _openingPicker = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final ink = widget.onScrim ? Colors.white : colors.onSurface;
    final surface = widget.onScrim
        ? const Color(0xff192522)
        : colors.surfaceContainerHigh;
    final grace = widget.graceSeconds;
    final ended = grace == 0;
    final composing = widget.typing || grace != null;
    final note = switch (grace) {
      null => l10n.thought_reply_private_note(widget.authorName),
      0 => l10n.thought_reply_ended,
      final seconds? => l10n.thought_reply_grace(seconds),
    };

    return Column(
      key: const ValueKey('thought-reply-dock'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (composing)
          _ThoughtReplyQuote(
            post: widget.post,
            authorName: widget.authorName,
            media: widget.media,
            ink: ink,
            surface: surface,
          )
        else
          _chips(l10n, ink, surface),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: ink.withValues(alpha: .16)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  label: l10n.thought_reply_field_label(widget.authorName),
                  child: TextField(
                    key: const ValueKey('thought-reply-field'),
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    readOnly: ended,
                    minLines: 1,
                    maxLines: composing ? 2 : 1,
                    textInputAction: TextInputAction.send,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(maxMessageLength),
                    ],
                    style: TextStyle(color: ink, fontSize: 16),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      constraints: const BoxConstraints(minHeight: 48),
                      hintText: l10n.thought_reply_hint(widget.authorName),
                      hintStyle: TextStyle(color: ink.withValues(alpha: .8)),
                      contentPadding: const EdgeInsetsDirectional.fromSTEB(
                        16,
                        12,
                        4,
                        12,
                      ),
                    ),
                    onEditingComplete: () {},
                    onSubmitted: ended || !widget.sendEnabled
                        ? null
                        : (_) => widget.onSend(),
                  ),
                ),
              ),
              // Space in the field for the planned microphone. It has no
              // control or semantics of its own.
              const SizedBox(width: 36),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: widget.controller,
                builder: (context, value, _) => IconButton(
                  key: const ValueKey('thought-reply-send'),
                  tooltip: l10n.thought_reply_send_label,
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  style: IconButton.styleFrom(
                    foregroundColor: ink,
                    disabledForegroundColor: ink.withValues(alpha: .42),
                  ),
                  onPressed:
                      ended || !widget.sendEnabled || value.text.trim().isEmpty
                      ? null
                      : widget.onSend,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          liveRegion:
              grace != null &&
              (grace == _firstGraceSeconds || grace == 10 || ended),
          child: Text(
            note,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: ink, fontSize: 12, height: 1.25),
          ),
        ),
      ],
    );
  }

  Widget _chips(AppLocalizations l10n, Color ink, Color surface) {
    final visit = widget.visit;
    final postId = widget.post.id;
    final sticker = visit.stickerFor(postId);
    final selection = sticker?.sticker;
    final entry = selection?.entry;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final reaction in ThoughtReaction.values)
          ThoughtReactionCircle(
            key: ValueKey('${widget.reactionKeyPrefix}-${reaction.name}'),
            glyph: reaction.glyph,
            label:
                visit.sends.values.any(
                  (send) =>
                      send.postId == postId &&
                      send.reaction == reaction &&
                      send.status == ThoughtReplyStatus.sent,
                )
                ? l10n.thought_reaction_sent_label(reaction.glyph)
                : switch (reaction) {
                    ThoughtReaction.love => l10n.thought_react_love,
                    ThoughtReaction.laugh => l10n.thought_react_laugh,
                    ThoughtReaction.fire => l10n.thought_react_fire,
                    ThoughtReaction.applause => l10n.thought_react_applause,
                  },
            size: 44,
            pressed: visit.pressed(postId, reaction),
            foregroundColor: ink,
            onTap: () => widget.onReaction(reaction),
            onActivate: () =>
                (widget.onReactionActivate ?? widget.onReaction)(reaction),
          ),
        if (sticker?.status == ThoughtReplyStatus.sent && selection != null)
          Semantics(
            key: const ValueKey('thought-sticker-sent'),
            label: l10n.thought_sticker_sent_label,
            liveRegion: true,
            excludeSemantics: true,
            child: SizedBox.square(
              dimension: 44,
              child: entry != null
                  ? Image.asset(entry.assetPath, fit: BoxFit.contain)
                  : Image.file(
                      File(selection.customFilePath!),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          Icon(Icons.emoji_emotions, color: ink),
                    ),
            ),
          )
        else
          IconButton(
            key: const ValueKey('thought-reply-stickers'),
            tooltip: l10n.stickers_title,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            onPressed: sticker == null && widget.onSticker != null
                ? _openPicker
                : null,
            style: IconButton.styleFrom(
              foregroundColor: ink,
              backgroundColor: surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.emoji_emotions_outlined),
          ),
      ],
    );
  }
}

class _ThoughtReplyQuote extends StatelessWidget {
  const _ThoughtReplyQuote({
    required this.post,
    required this.authorName,
    required this.media,
    required this.ink,
    required this.surface,
  });

  final PostModel post;
  final String authorName;
  final List<PostMediaAttachmentModel> media;
  final Color ink;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final attachment = media.firstOrNull;
    final caption = post.text.isEmpty ? attachment?.caption ?? '' : post.text;
    return Container(
      key: const ValueKey('thought-reply-quote'),
      padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 8, 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(10),
        border: BorderDirectional(
          start: BorderSide(color: thoughtReactionGreen, width: 3),
        ),
      ),
      child: Row(
        children: [
          if (post.mediaKind != 'none') ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox.square(
                dimension: 38,
                child: _thumbnail(attachment),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.thought_quote_theirs(authorName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (caption.isNotEmpty)
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: detectTextDirection(caption),
                    style: TextStyle(
                      color: ink.withValues(alpha: .85),
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbnail(PostMediaAttachmentModel? attachment) {
    final placeholder = Icon(
      switch (post.mediaKind) {
        'video' => Icons.play_circle_outline,
        'voice' => Icons.graphic_eq,
        _ => Icons.image_outlined,
      },
      color: ink,
      size: 22,
    );
    final path = attachment?.localPath;
    if (attachment?.kind == 'image' && path != null) {
      return Image.file(
        File(MediaFileManager.resolveStoredPathSync(path)),
        cacheWidth: 80,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      );
    }
    if (attachment?.previewBase64 case final preview?) {
      try {
        return Image.memory(
          base64Decode(preview),
          cacheWidth: 80,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => placeholder,
        );
      } on FormatException {
        return placeholder;
      }
    }
    return placeholder;
  }
}
