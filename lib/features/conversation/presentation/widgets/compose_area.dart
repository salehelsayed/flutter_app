import 'dart:ui';
import 'package:flutter/material.dart';

/// Compose area at the bottom of the conversation screen.
///
/// Auto-growing text field with glassmorphic styling,
/// animated send button (hidden when empty), and + attachment button.
class ComposeArea extends StatefulWidget {
  final ValueChanged<String> onSend;
  final VoidCallback? onAttach;
  final bool hasAttachments;
  final bool isProcessing;

  const ComposeArea({
    super.key,
    required this.onSend,
    this.onAttach,
    this.hasAttachments = false,
    this.isProcessing = false,
  });

  @override
  State<ComposeArea> createState() => _ComposeAreaState();
}

class _ComposeAreaState extends State<ComposeArea>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasFocus = false;
  bool _hasText = false;

  late final AnimationController _sendButtonController;
  late final Animation<double> _sendOpacity;
  late final Animation<double> _sendScale;

  @override
  void initState() {
    super.initState();

    _sendButtonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _sendOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _sendButtonController, curve: Curves.ease),
    );
    _sendScale = Tween<double>(begin: 0.9, end: 1).animate(
      CurvedAnimation(parent: _sendButtonController, curve: Curves.ease),
    );

    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);

    if (widget.hasAttachments) {
      _sendButtonController.value = 1.0;
    }
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
      _updateSendButton();
    }
  }

  void _updateSendButton() {
    final shouldShow = _hasText || widget.hasAttachments;
    if (shouldShow) {
      _sendButtonController.forward();
    } else {
      _sendButtonController.reverse();
    }
  }

  @override
  void didUpdateWidget(ComposeArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hasAttachments != widget.hasAttachments) {
      _updateSendButton();
    }
  }

  void _onFocusChanged() {
    setState(() => _hasFocus = _focusNode.hasFocus);
  }

  void _onSendPressed() {
    final text = _controller.text.trim();
    if (text.isEmpty && !widget.hasAttachments) return;
    _controller.clear();
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
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomPadding),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Color.fromRGBO(10, 10, 15, 0.95),
              ],
              stops: [0.0, 0.2],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Text input
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                constraints: const BoxConstraints(
                  minHeight: 44,
                  maxHeight: 160,
                ),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(255, 255, 255, 0.06),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: _hasFocus
                        ? const Color.fromRGBO(255, 255, 255, 0.20)
                        : const Color.fromRGBO(255, 255, 255, 0.10),
                  ),
                  boxShadow: _hasFocus
                      ? const [
                          BoxShadow(
                            color: Color.fromRGBO(255, 255, 255, 0.08),
                            blurRadius: 0,
                            spreadRadius: 1,
                          ),
                          BoxShadow(
                            color: Color.fromRGBO(0, 0, 0, 0.3),
                            blurRadius: 20,
                            offset: Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: null,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color.fromRGBO(255, 255, 255, 0.95),
                    height: 1.5,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Write something...',
                    hintStyle: TextStyle(
                      fontSize: 15,
                      color: Color.fromRGBO(
                        255,
                        255,
                        255,
                        _hasFocus ? 0.2 : 0.3,
                      ),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Action row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Attachment button
                  GestureDetector(
                    onTap: widget.isProcessing ? null : widget.onAttach,
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Icon(
                          Icons.add_circle_outline,
                          size: 22,
                          color: Color.fromRGBO(
                            255, 255, 255,
                            widget.isProcessing ? 0.15 : 0.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Length hint
                  if (_controller.text.length > 2000)
                    const Text(
                      'Long letters are lovely',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color.fromRGBO(255, 255, 255, 0.25),
                      ),
                    ),
                  // Send button
                  AnimatedBuilder(
                    animation: _sendButtonController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _sendOpacity.value,
                        child: Transform.scale(
                          scale: _sendScale.value,
                          child: child,
                        ),
                      );
                    },
                    child: GestureDetector(
                      onTap: !widget.isProcessing && (_hasText || widget.hasAttachments)
                          ? _onSendPressed
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(29, 185, 84, 0.15),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: const Color.fromRGBO(29, 185, 84, 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.send_rounded,
                              size: 18,
                              color: Color(0xFF1DB954),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Send',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1DB954),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
