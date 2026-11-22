import 'dart:async';
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
import 'package:flutter_app/features/posts/presentation/widgets/thought_reply_picker.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// The reply controls for both Thought presentations. The host owns focus,
/// navigation and expiry for its card.
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
    this.onPanelEmoji,
    this.onOpenComposer,
    this.onOpenComposerActivate,
    this.canOpenPicker,
    this.canActivatePicker,
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
  final ValueChanged<ThoughtReaction>? onPanelEmoji;
  final ValueChanged<ThoughtStickerSelection>? onSticker;
  final VoidCallback onSend;
  final bool sendEnabled;

  /// In depth the resting controls use a Reply pill. It opens this same
  /// dock's typing state.
  final VoidCallback? onOpenComposer;
  final VoidCallback? onOpenComposerActivate;
  final bool Function()? canOpenPicker;
  final bool Function()? canActivatePicker;

  /// Null while live. Zero leaves an ended composition visible for closing.
  final int? graceSeconds;
  final bool onScrim;

  @override
  State<ThoughtReplyDock> createState() => _ThoughtReplyDockState();
}

class _ThoughtReplyDockState extends State<ThoughtReplyDock> {
  static const _feedbackDuration = Duration(milliseconds: 1500);

  ModalRoute<dynamic>? _picker;
  bool _openingPicker = false;
  int? _firstGraceSeconds;
  OrbitDepthSend? _sentPreview;
  Timer? _previewTimer;

  @override
  void didUpdateWidget(ThoughtReplyDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.graceSeconds == null) {
      _firstGraceSeconds = widget.graceSeconds;
    }
    if (oldWidget.post.id != widget.post.id || widget.graceSeconds != null) {
      _dismissOwnedPicker();
      _previewTimer?.cancel();
      _sentPreview = null;
    }
    if (widget.graceSeconds != null) return;
    final newAnswer = widget.visit
        .sentOn(widget.post.id)
        .where(
          (send) =>
              !send.restored &&
              oldWidget.visit.sends[send.messageId]?.status !=
                  ThoughtReplyStatus.sent,
        )
        .lastOrNull;
    if (newAnswer != null) {
      _sentPreview = newAnswer;
      _previewTimer?.cancel();
      _previewTimer = Timer(_feedbackDuration, () {
        if (mounted) setState(() => _sentPreview = null);
      });
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
    _previewTimer?.cancel();
    _dismissOwnedPicker();
    super.dispose();
  }

  Future<void> _openPicker({bool semantics = false}) async {
    final canOpen = semantics
        ? widget.canActivatePicker ?? widget.canOpenPicker
        : widget.canOpenPicker;
    if (_openingPicker || canOpen?.call() == false) return;
    setState(() => _openingPicker = true);
    final postId = widget.post.id;
    try {
      final selected = await showModalBottomSheet<Object>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
            ? AnimationStyle.noAnimation
            : null,
        builder: (sheetContext) {
          _picker = ModalRoute.of(sheetContext);
          return ThoughtReplyPicker(
            postId: postId,
            visit: widget.visit,
            stickersAvailable:
                widget.onSticker != null &&
                widget.visit.stickerFor(postId) == null,
          );
        },
      );
      if (!mounted || widget.post.id != postId || widget.graceSeconds != null) {
        return;
      }
      if (selected is ThoughtReaction) {
        (widget.onPanelEmoji ?? widget.onReaction)(selected);
      } else if (selected is ThoughtStickerSelection) {
        widget.onSticker?.call(selected);
      }
    } finally {
      _picker = null;
      if (mounted) setState(() => _openingPicker = false);
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
    final composing = widget.typing || grace != null;
    final compact = widget.onOpenComposer != null;
    final preview = _sentPreview;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
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
            else ...[
              if (!_openingPicker) _sentLine(l10n, ink),
              _chips(l10n, ink, compact: compact),
            ],
            if (composing || !compact) ...[
              const SizedBox(height: 8),
              _textField(l10n, ink, surface, composing),
            ],
          ],
        ),
        if (!composing && !_openingPicker && preview != null)
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: compact ? 56 : 126,
            child: IgnorePointer(child: _feedback(l10n, preview, ink, surface)),
          ),
      ],
    );
  }

  Widget _textField(
    AppLocalizations l10n,
    Color ink,
    Color surface,
    bool composing,
  ) {
    final grace = widget.graceSeconds;
    final ended = grace == 0;
    final note = switch (grace) {
      null => l10n.thought_reply_private_note(widget.authorName),
      0 => l10n.thought_reply_ended,
      final seconds => l10n.thought_reply_grace(seconds),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
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
              // Empty space for the later microphone control.
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

  Widget _chips(AppLocalizations l10n, Color ink, {required bool compact}) {
    final visit = widget.visit;
    final personal = visit.personalEmoji;
    final open = widget.onOpenComposer;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final reaction in ThoughtReaction.values)
          _chip(
            l10n,
            ink,
            reaction,
            ValueKey('${widget.reactionKeyPrefix}-${reaction.name}'),
          ),
        if (!compact && personal != null)
          _chip(
            l10n,
            ink,
            personal,
            const ValueKey('thought-reply-personal-emoji'),
          ),
        if (!compact)
          SizedBox(
            width: 1,
            height: 24,
            child: ColoredBox(color: ink.withValues(alpha: .28)),
          ),
        Semantics(
          button: true,
          label: l10n.thought_more_label,
          excludeSemantics: true,
          onTap: () => _openPicker(semantics: true),
          child: IconButton(
            key: const ValueKey('thought-reply-more'),
            tooltip: l10n.thought_more_label,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            onPressed: _openPicker,
            style: IconButton.styleFrom(
              foregroundColor: ink,
              side: BorderSide(color: ink.withValues(alpha: .55)),
            ),
            icon: const Icon(Icons.add_reaction_outlined),
          ),
        ),
        if (open != null)
          Flexible(
            child: Semantics(
              button: true,
              excludeSemantics: true,
              label: l10n.conversation_context_reply,
              onTap: widget.onOpenComposerActivate ?? open,
              child: FilledButton(
                key: const ValueKey('orbit-depth-reply'),
                onPressed: open,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  backgroundColor: thoughtReactionGreen,
                  foregroundColor: const Color(0xff04130a),
                ),
                child: Text(
                  l10n.conversation_context_reply,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _chip(
    AppLocalizations l10n,
    Color ink,
    ThoughtReaction reaction,
    Key key,
  ) {
    final postId = widget.post.id;
    final sent = widget.visit
        .sentOn(postId)
        .any((send) => send.reaction == reaction);
    final label = sent
        ? l10n.thought_reaction_sent_label(reaction.glyph)
        : switch (reaction) {
            ThoughtReaction.love => l10n.thought_react_love,
            ThoughtReaction.laugh => l10n.thought_react_laugh,
            ThoughtReaction.fire => l10n.thought_react_fire,
            ThoughtReaction.applause => l10n.thought_react_applause,
            _ => reaction.glyph,
          };
    return ThoughtReactionCircle(
      key: key,
      glyph: reaction.glyph,
      label: label,
      size: 44,
      pressed: widget.visit.pressed(postId, reaction),
      confirmed: sent,
      foregroundColor: ink,
      onTap: () => widget.onReaction(reaction),
      onActivate: () =>
          (widget.onReactionActivate ?? widget.onReaction)(reaction),
    );
  }

  Widget _sentLine(AppLocalizations l10n, Color ink) {
    final sends = widget.visit
        .sentOn(widget.post.id)
        .where((send) => send.messageId != _sentPreview?.messageId)
        .toList(growable: false);
    if (sends.isEmpty) return const SizedBox.shrink();
    final omitted = sends.length > 5 ? sends.length - 5 : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        key: const ValueKey('thought-reply-you-sent'),
        children: [
          Flexible(
            child: Text(
              l10n.thought_you_sent,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final send in sends.skip(omitted)) ...[
            const SizedBox(width: 6),
            if (send.sticker case final sticker?)
              Semantics(
                label: l10n.thought_sticker_sent_label,
                excludeSemantics: true,
                child: SizedBox.square(
                  key: const ValueKey('thought-reply-sent-sticker'),
                  dimension: 28,
                  child: _stickerArt(sticker),
                ),
              )
            else
              SizedBox(
                width: 24,
                height: 28,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    send.reaction!.glyph,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
          ],
          if (omitted > 0) ...[
            const SizedBox(width: 6),
            Text('+$omitted', style: TextStyle(color: ink, fontSize: 13)),
          ],
        ],
      ),
    );
  }

  Widget _feedback(
    AppLocalizations l10n,
    OrbitDepthSend preview,
    Color ink,
    Color surface,
  ) {
    final sticker = preview.sticker;
    final image = sticker == null
        ? Text(
            preview.reaction!.glyph,
            style: const TextStyle(fontSize: 64, height: 1),
          )
        : SizedBox.square(dimension: 120, child: _stickerArt(sticker));
    final child = Center(
      child: Semantics(
        key: const ValueKey('thought-reply-sent-feedback'),
        label: sticker == null
            ? l10n.thought_reaction_sent_label(preview.reaction!.glyph)
            : l10n.thought_sticker_sent_label,
        liveRegion: true,
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            image,
            const SizedBox(height: 6),
            DecoratedBox(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Text(
                  l10n.message_status_sent,
                  style: TextStyle(color: ink, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(preview.messageId),
      tween: Tween(begin: 0, end: 1),
      duration: _feedbackDuration,
      child: child,
      builder: (context, time, child) {
        final fade = ((1 - time) / .14).clamp(0.0, 1.0);
        final rise = (time / .12).clamp(0.0, 1.0);
        return Opacity(
          opacity: fade,
          child: Transform.scale(
            scale: .88 + .12 * rise - .35 * (1 - fade),
            child: child,
          ),
        );
      },
    );
  }

  Widget _stickerArt(ThoughtStickerSelection selection) {
    if (selection.entry case final entry?) {
      return Image.asset(entry.assetPath, fit: BoxFit.contain);
    }
    return Image.file(
      File(selection.customFilePath!),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const Icon(Icons.emoji_emotions_outlined),
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
