import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';

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

  const InlineReplyInput({
    super.key,
    this.hintText = 'Reply...',
    required this.onSend,
    this.enabled = true,
    this.initialText = '',
    this.shouldRequestFocus = false,
    this.onDraftChanged,
    this.onFocusChanged,
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

  @override
  void initState() {
    super.initState();
    _sendButtonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _sendScale = CurvedAnimation(
      parent: _sendButtonController,
      curve: Curves.ease,
    );
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
        height: 40,
        decoration: BoxDecoration(
          color: _hasFocus
              ? const Color.fromRGBO(255, 255, 255, 0.06)
              : const Color.fromRGBO(255, 255, 255, 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _hasFocus
                ? const Color.fromRGBO(78, 205, 196, 0.20)
                : const Color.fromRGBO(255, 255, 255, 0.08),
          ),
        ),
        child: Row(
          children: [
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
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: const TextStyle(
                    fontSize: 14,
                    color: Color.fromRGBO(255, 255, 255, 0.25),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.only(
                    left: 16,
                    right: 8,
                    bottom: 10,
                  ),
                  isDense: true,
                ),
              ),
            ),
            ScaleTransition(
              scale: _sendScale,
              child: GestureDetector(
                onTap: _hasText ? _onSendPressed : null,
                child: Container(
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.tealAccent.withValues(alpha: 0.20),
                  ),
                  child: const Icon(
                    Icons.arrow_upward_rounded,
                    size: 18,
                    color: AppColors.tealAccent,
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
