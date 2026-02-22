import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';

/// Pill-shaped single-line inline reply input with animated send button.
///
/// Used in collapsed thread cards for quick replies without leaving the feed.
/// GestureDetector wrapping absorbs taps to prevent parent card interaction.
class InlineReplyInput extends StatefulWidget {
  final String hintText;
  final ValueChanged<String> onSend;
  final bool enabled;
  final String initialText;
  final bool shouldRequestFocus;
  final ValueChanged<String>? onDraftChanged;
  final ValueChanged<bool>? onFocusChanged;
  final VoidCallback? onAttach;

  const InlineReplyInput({
    super.key,
    this.hintText = 'Reply...',
    required this.onSend,
    this.enabled = true,
    this.initialText = '',
    this.shouldRequestFocus = false,
    this.onDraftChanged,
    this.onFocusChanged,
    this.onAttach,
  });

  @override
  State<InlineReplyInput> createState() => _InlineReplyInputState();
}

class _InlineReplyInputState extends State<InlineReplyInput>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _hasFocus = false;

  late final AnimationController _sendButtonController;
  late final Animation<double> _sendScale;
  late final Animation<double> _sendOpacity;

  @override
  void initState() {
    super.initState();
    _sendButtonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    final sendCurve = CurvedAnimation(
      parent: _sendButtonController,
      curve: Curves.easeOut,
    );
    _sendScale = Tween<double>(begin: 0.86, end: 1.0).animate(sendCurve);
    _sendOpacity = Tween<double>(begin: 0.46, end: 1.0).animate(sendCurve);
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
    if (widget.initialText.isNotEmpty) {
      _controller.text = widget.initialText;
      _hasText = widget.initialText.trim().isNotEmpty;
      if (_hasText) _sendButtonController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(InlineReplyInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialText != oldWidget.initialText && !_focusNode.hasFocus) {
      _controller.text = widget.initialText;
    }
    if (widget.shouldRequestFocus && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
      if (hasText) {
        _sendButtonController.forward();
      } else {
        _sendButtonController.reverse();
      }
    }
    widget.onDraftChanged?.call(_controller.text);
  }

  void _onFocusChanged() {
    setState(() => _hasFocus = _focusNode.hasFocus);
    widget.onFocusChanged?.call(_focusNode.hasFocus);
  }

  void _onSendPressed() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    widget.onDraftChanged?.call('');
    _focusNode.unfocus();
    widget.onSend(text);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _sendButtonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // absorb taps
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 44,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _hasFocus
                ? const [
                    Color.fromRGBO(255, 255, 255, 0.09),
                    Color.fromRGBO(255, 255, 255, 0.05),
                  ]
                : const [
                    Color.fromRGBO(255, 255, 255, 0.07),
                    Color.fromRGBO(255, 255, 255, 0.04),
                  ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _hasFocus
                ? FeedColors.accentTeal.withValues(alpha: 0.32)
                : const Color.fromRGBO(255, 255, 255, 0.10),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
            if (_hasFocus)
              BoxShadow(
                color: FeedColors.accentTeal.withValues(alpha: 0.10),
                blurRadius: 14,
                spreadRadius: 1,
              ),
          ],
        ),
        child: Row(
          children: [
            if (widget.onAttach != null)
              GestureDetector(
                onTap: widget.onAttach,
                child: Container(
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.only(left: 6, right: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.fromRGBO(255, 255, 255, 0.13),
                        Color.fromRGBO(255, 255, 255, 0.07),
                      ],
                    ),
                    border: Border.all(
                      color: const Color.fromRGBO(255, 255, 255, 0.12),
                    ),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 18,
                    color: Color.fromRGBO(255, 255, 255, 0.56),
                  ),
                ),
              ),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: widget.enabled,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color.fromRGBO(255, 255, 255, 0.90),
                  height: 1.3,
                ),
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: const TextStyle(
                    fontSize: 14,
                    color: Color.fromRGBO(255, 255, 255, 0.40),
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.only(
                    left: widget.onAttach != null ? 6 : 14,
                    right: 10,
                    top: 10,
                    bottom: 10,
                  ),
                  isDense: true,
                ),
              ),
            ),
            ScaleTransition(
              scale: _sendScale,
              child: FadeTransition(
                opacity: _sendOpacity,
                child: GestureDetector(
                  onTap: _hasText ? _onSendPressed : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 32,
                    height: 32,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          FeedColors.accentTeal.withValues(
                            alpha: _hasText ? 0.42 : 0.24,
                          ),
                          FeedColors.accentTeal.withValues(
                            alpha: _hasText ? 0.28 : 0.16,
                          ),
                        ],
                      ),
                      border: Border.all(
                        color: FeedColors.accentTeal.withValues(
                          alpha: _hasText ? 0.58 : 0.24,
                        ),
                      ),
                      boxShadow: _hasText
                          ? [
                              BoxShadow(
                                color: FeedColors.accentTeal.withValues(
                                  alpha: 0.20,
                                ),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      Icons.arrow_upward_rounded,
                      size: 18,
                      color: FeedColors.accentTeal.withValues(
                        alpha: _hasText ? 0.96 : 0.68,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
