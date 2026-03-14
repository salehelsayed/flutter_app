import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/feed/presentation/widgets/quote_preview_bar.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/recording_overlay.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/voice_record_button.dart';

/// Compose area at the bottom of the conversation screen.
///
/// Auto-growing text field with glassmorphic styling,
/// animated send button (hidden when empty), and + attachment button.
/// When text is empty and no attachments: shows mic button for voice recording.
class ComposeArea extends StatefulWidget {
  final ValueChanged<String> onSend;
  final VoidCallback? onAttach;
  final bool hasAttachments;
  final bool isProcessing;
  final bool isSending;
  final VoidCallback? onRecordStart;
  final VoidCallback? onRecordStop;
  final VoidCallback? onRecordCancel;
  final bool isRecording;
  final Duration recordingDuration;
  final List<double> amplitudeValues;
  final String? initialText;
  final ValueChanged<String>? onDraftChanged;
  final String? quotedText;
  final bool isQuoteUnavailable;
  final VoidCallback? onClearQuote;

  const ComposeArea({
    super.key,
    required this.onSend,
    this.onAttach,
    this.hasAttachments = false,
    this.isProcessing = false,
    this.isSending = false,
    this.onRecordStart,
    this.onRecordStop,
    this.onRecordCancel,
    this.isRecording = false,
    this.recordingDuration = Duration.zero,
    this.amplitudeValues = const [],
    this.initialText,
    this.onDraftChanged,
    this.quotedText,
    this.isQuoteUnavailable = false,
    this.onClearQuote,
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

    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _controller.text = widget.initialText!;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }

    if (widget.hasAttachments || _controller.text.trim().isNotEmpty) {
      _sendButtonController.value = 1.0;
    }
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
      _updateSendButton();
    }
    widget.onDraftChanged?.call(_controller.text);
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
    final nextText = widget.initialText ?? '';
    final shouldRestoreClearedDraft =
        _controller.text.isEmpty && nextText.isNotEmpty;
    if ((nextText != (oldWidget.initialText ?? '') ||
            shouldRestoreClearedDraft) &&
        nextText != _controller.text) {
      _controller.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
      );
      _hasText = nextText.trim().isNotEmpty;
      _updateSendButton();
    }
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

  bool get _shouldShowSendButton => _hasText || widget.hasAttachments;

  bool get _canRecordVoice =>
      widget.onRecordStart != null && widget.onRecordStop != null;

  bool get _shouldShowMicButton => !_shouldShowSendButton && _canRecordVoice;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final showQuotePreview =
        widget.quotedText != null || widget.isQuoteUnavailable;
    final quotePreviewText = widget.isQuoteUnavailable
        ? 'Message unavailable'
        : widget.quotedText;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomPadding),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color.fromRGBO(10, 10, 15, 0.95)],
              stops: [0.0, 0.2],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showQuotePreview)
                QuotePreviewBar(
                  text: quotePreviewText!,
                  onDismiss: widget.onClearQuote,
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Attachment button
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: GestureDetector(
                      onTap: widget.isProcessing || widget.isRecording
                          ? null
                          : widget.onAttach,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Color.fromRGBO(
                            255,
                            255,
                            255,
                            widget.isProcessing ? 0.04 : 0.08,
                          ),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: Color.fromRGBO(
                              255,
                              255,
                              255,
                              widget.isProcessing ? 0.06 : 0.15,
                            ),
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.add_rounded,
                            size: 20,
                            color: Color.fromRGBO(
                              255,
                              255,
                              255,
                              widget.isProcessing ? 0.15 : 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Text input or recording overlay
                  Expanded(
                    child: widget.isRecording
                        ? RecordingOverlay(
                            elapsed: widget.recordingDuration,
                            onCancel: widget.onRecordCancel ?? () {},
                            amplitudeValues: widget.amplitudeValues,
                          )
                        : AnimatedContainer(
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
                                        color: Color.fromRGBO(
                                          255,
                                          255,
                                          255,
                                          0.08,
                                        ),
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
                              maxLength: maxMessageLength,
                              enabled: !widget.isRecording,
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
                                counterText: '',
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  // Mic button or Send button
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: _shouldShowMicButton
                        ? VoiceRecordButton(
                            onTapDown: widget.onRecordStart!,
                            onTapUp: widget.onRecordStop!,
                            onTapCancel: widget.onRecordCancel ?? () {},
                            isRecording: widget.isRecording,
                          )
                        : AnimatedBuilder(
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
                              onTap:
                                  !widget.isProcessing &&
                                      !widget.isSending &&
                                      (_hasText || widget.hasAttachments)
                                  ? _onSendPressed
                                  : null,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color.fromRGBO(
                                    29,
                                    185,
                                    84,
                                    0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(
                                    color: const Color.fromRGBO(
                                      29,
                                      185,
                                      84,
                                      0.3,
                                    ),
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 20,
                                    color: Color(0xFF1DB954),
                                  ),
                                ),
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
