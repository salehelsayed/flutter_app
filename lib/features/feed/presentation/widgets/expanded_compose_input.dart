import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';

/// Multi-line auto-growing compose input for expanded thread cards.
///
/// Similar API to [InlineReplyInput] but with multi-line support,
/// auto-growing height (up to ~4 lines), and a send button below the text.
class ExpandedComposeInput extends StatefulWidget {
  final String hintText;
  final ValueChanged<String> onSend;
  final bool enabled;
  final String initialText;
  final bool shouldRequestFocus;
  final ValueChanged<String>? onDraftChanged;
  final ValueChanged<bool>? onFocusChanged;
  final VoidCallback? onAttach;

  const ExpandedComposeInput({
    super.key,
    this.hintText = 'Write something...',
    required this.onSend,
    this.enabled = true,
    this.initialText = '',
    this.shouldRequestFocus = false,
    this.onDraftChanged,
    this.onFocusChanged,
    this.onAttach,
  });

  @override
  State<ExpandedComposeInput> createState() => _ExpandedComposeInputState();
}

class _ExpandedComposeInputState extends State<ExpandedComposeInput>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  TextDirection _inputDirection = TextDirection.ltr;
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
    _controller.addListener(_updateInputDirection);
    _focusNode.addListener(_onFocusChanged);
    if (widget.initialText.isNotEmpty) {
      _controller.text = widget.initialText;
      _hasText = widget.initialText.trim().isNotEmpty;
      if (_hasText) _sendButtonController.value = 1.0;
    }

    _updateInputDirection();
  }

  @override
  void didUpdateWidget(ExpandedComposeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialText != oldWidget.initialText && !_focusNode.hasFocus) {
      _controller.text = widget.initialText;
    }
    if (widget.shouldRequestFocus && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  void _updateInputDirection() {
    final nextDirection = detectTextDirection(_controller.text);
    if (nextDirection != _inputDirection) {
      setState(() => _inputDirection = nextDirection);
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
    _controller.removeListener(_updateInputDirection);
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (widget.onAttach != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 4),
                  child: GestureDetector(
                    onTap: widget.onAttach,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color.fromRGBO(255, 255, 255, 0.08),
                        border: Border.all(
                          color: const Color.fromRGBO(255, 255, 255, 0.12),
                        ),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        size: 20,
                        color: Color.fromRGBO(255, 255, 255, 0.50),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  constraints: const BoxConstraints(
                    minHeight: 44,
                    maxHeight: 120,
                  ),
                  decoration: BoxDecoration(
                    color: _hasFocus
                        ? const Color.fromRGBO(255, 255, 255, 0.08)
                        : const Color.fromRGBO(255, 255, 255, 0.06),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _hasFocus
                          ? const Color.fromRGBO(78, 205, 196, 0.20)
                          : const Color.fromRGBO(255, 255, 255, 0.08),
                    ),
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    textDirection: _inputDirection,
                    enabled: widget.enabled,
                    maxLines: null,
                    maxLength: maxMessageLength,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color.fromRGBO(255, 255, 255, 0.90),
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      hintStyle: const TextStyle(
                        fontSize: 14,
                        color: Color.fromRGBO(255, 255, 255, 0.40),
                      ),
                      border: InputBorder.none,
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ScaleTransition(
              scale: _sendScale,
              child: GestureDetector(
                onTap: _hasText ? _onSendPressed : null,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: FeedColors.accentTeal.withValues(alpha: 0.20),
                  ),
                  child: const Icon(
                    Icons.arrow_upward_rounded,
                    size: 20,
                    color: FeedColors.accentTeal,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
