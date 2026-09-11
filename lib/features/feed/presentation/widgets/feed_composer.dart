import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/feed_tokens.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';

/// The single, screen-level composer for the redesigned Feed (134 §6/§8 P5).
///
/// Unlike the legacy per-card [InlineReplyInput], this composer is mounted ONCE
/// at the bottom of the focused Feed surface and is shown ONLY while a card is
/// focused. Its defining behaviours:
///
///  * It NEVER unfocuses on send (contrast `inline_reply_input.dart:141`). On
///    send it clears the text and KEEPS keyboard focus so the user can fire off
///    a second line immediately — the hint flips to "Add another…".
///  * Its placeholder verb is supplied by the host (`hintText`) and is derived
///    from the focused thread kind (1:1 / group / system), never from a sender
///    run's peerId.
///
/// The "open full conversation" history entry point is NOT here (134 §1/§3): it
/// lives in the focused-thread header at the TOP of the column (see
/// `FeedScreen._buildFocusedHeader`).
class FeedComposer extends StatefulWidget {
  /// Resting placeholder, e.g. `Reply to <name>…`. After the first send in a
  /// focus session this is replaced by [addAnotherHint].
  final String hintText;

  /// Placeholder shown after at least one line has been sent in the current
  /// focus session ("Add another…").
  final String addAnotherHint;

  /// Invoked with the trimmed body when the user presses send. Must NOT clear
  /// the host's focus — the composer keeps the keyboard up itself.
  final ValueChanged<String> onSend;

  /// Invoked on every keystroke with the raw (untrimmed) text.
  final ValueChanged<String>? onDraftChanged;

  /// Text retained by the host for this thread, including across focus changes.
  final String draftText;

  const FeedComposer({
    super.key,
    required this.hintText,
    required this.addAnotherHint,
    required this.onSend,
    this.onDraftChanged,
    this.draftText = '',
  });

  @override
  State<FeedComposer> createState() => _FeedComposerState();
}

class _FeedComposerState extends State<FeedComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  TextDirection _inputDirection = TextDirection.ltr;
  bool _hasText = false;
  bool _hasSentThisSession = false;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.draftText;
    _hasText = widget.draftText.trim().isNotEmpty;
    _inputDirection = detectTextDirection(widget.draftText);
    _controller.addListener(_onTextChanged);
    // Request focus once mounted so the keyboard rises with the composer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant FeedComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draftText == widget.draftText ||
        _controller.text == widget.draftText) {
      return;
    }
    _controller.removeListener(_onTextChanged);
    _controller.value = TextEditingValue(
      text: widget.draftText,
      selection: TextSelection.collapsed(offset: widget.draftText.length),
    );
    _hasText = widget.draftText.trim().isNotEmpty;
    _inputDirection = detectTextDirection(widget.draftText);
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    final nextDirection = detectTextDirection(_controller.text);
    if (hasText != _hasText || nextDirection != _inputDirection) {
      setState(() {
        _hasText = hasText;
        _inputDirection = nextDirection;
      });
    }
    widget.onDraftChanged?.call(_controller.text);
  }

  void _onSendPressed() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    widget.onDraftChanged?.call('');
    // Intentionally NOT unfocusing — keep the keyboard up (append-stay, 134 §8).
    if (!_hasSentThisSession) {
      setState(() => _hasSentThisSession = true);
    }
    widget.onSend(text);
    // Re-assert focus in case the send path rebuilt anything.
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.feedTokens;
    final hint = _hasSentThisSession ? widget.addAnotherHint : widget.hintText;

    final input = ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radiusFull),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: tokens.blurNav,
          sigmaY: tokens.blurNav,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: tokens.surfaceRaised,
            borderRadius: BorderRadius.circular(tokens.radiusFull),
            border: Border.all(color: tokens.borderSoft, width: 1.0),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('feed-composer-field'),
                  controller: _controller,
                  focusNode: _focusNode,
                  textDirection: _inputDirection,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _onSendPressed(),
                  style: tokens.textMessage,
                  cursorColor: tokens.teal400,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    // The rounded Container above paints the fill; the light
                    // theme's filled InputDecorationTheme would otherwise paint
                    // a square fill rect on top of it.
                    filled: false,
                    hintText: hint,
                    hintStyle: tokens.textMeta,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('feed-composer-send'),
                onPressed: _hasText ? _onSendPressed : null,
                icon: Icon(
                  Icons.arrow_upward_rounded,
                  color: _hasText ? tokens.teal400 : tokens.textMeta.color,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );

    return Column(
      key: const ValueKey('feed-composer'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [input],
    );
  }
}
