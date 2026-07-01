import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/feed/presentation/widgets/quote_preview_bar.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/recording_overlay.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/voice_record_button.dart';

enum VoiceRecordingState { idle, arming, recording, stopping, reviewing }

extension VoiceRecordingStateX on VoiceRecordingState {
  bool get isActive => this != VoiceRecordingState.idle;

  /// The recorder auto-stopped at the max duration and the captured clip is
  /// being held for the user to review (send or discard) — 117 Session 3.
  bool get isReviewing => this == VoiceRecordingState.reviewing;
}

/// Compose area at the bottom of the conversation screen.
///
/// Auto-growing text field with glassmorphic styling,
/// animated send button (hidden when empty), and + attachment button.
/// When text is empty and no attachments: shows mic button for voice recording.
class ComposeArea extends StatefulWidget {
  final ValueChanged<String> onSend;
  final VoidCallback? onAttach;
  final bool hasAttachments;

  /// True when at least one picked attachment failed a size/GIF SEND policy
  /// (149). Disables the Send tap (the composer keeps the Send affordance
  /// visible-but-inert) while an invalid attachment is present.
  final bool hasInvalidAttachment;
  final bool isProcessing;
  final bool isSending;
  final bool isRecording;
  final VoiceRecordingState recordingState;
  final VoidCallback? onRecordStart;
  final VoidCallback? onRecordStop;
  final VoidCallback? onRecordCancel;
  final VoidCallback? onReviewSend;
  final VoidCallback? onReviewDiscard;
  final Duration recordingDuration;
  final List<double> amplitudeValues;
  final String? initialText;
  final ValueChanged<String>? onDraftChanged;
  final String? quotedText;
  final bool isQuoteUnavailable;
  final VoidCallback? onClearQuote;
  final bool shouldRequestFocus;

  const ComposeArea({
    super.key,
    required this.onSend,
    this.onAttach,
    this.hasAttachments = false,
    this.hasInvalidAttachment = false,
    this.isProcessing = false,
    this.isSending = false,
    this.isRecording = false,
    this.recordingState = VoiceRecordingState.idle,
    this.onRecordStart,
    this.onRecordStop,
    this.onRecordCancel,
    this.onReviewSend,
    this.onReviewDiscard,
    this.recordingDuration = Duration.zero,
    this.amplitudeValues = const [],
    this.initialText,
    this.onDraftChanged,
    this.quotedText,
    this.isQuoteUnavailable = false,
    this.onClearQuote,
    this.shouldRequestFocus = false,
  });

  @override
  State<ComposeArea> createState() => _ComposeAreaState();
}

class _ComposeAreaState extends State<ComposeArea>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  TextDirection _inputDirection = TextDirection.ltr;
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
    _controller.addListener(_updateInputDirection);
    _focusNode.addListener(_onFocusChanged);

    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _controller.text = widget.initialText!;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }

    _updateInputDirection();

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
    if (widget.shouldRequestFocus &&
        !oldWidget.shouldRequestFocus &&
        !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  void _updateInputDirection() {
    final nextDirection = detectTextDirection(_controller.text);
    if (nextDirection != _inputDirection) {
      setState(() => _inputDirection = nextDirection);
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

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// 117 Session 3: read-only preview of the auto-stopped recording held for
  /// review (a voice glyph + its duration), shown in place of the text input.
  Widget _buildReviewPreview(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.10)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.graphic_eq_rounded,
            size: 20,
            color: Color(0xFF4ecdc4),
          ),
          const SizedBox(width: 10),
          Text(
            _formatDuration(widget.recordingDuration),
            style: const TextStyle(
              fontSize: 14,
              color: Color.fromRGBO(255, 255, 255, 0.95),
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  /// 117 Session 3: discard / send controls for the held review recording.
  Widget _buildReviewActions(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          key: const ValueKey('voice-review-discard'),
          onTap: widget.onReviewDiscard,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color.fromRGBO(255, 255, 255, 0.08),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: const Color.fromRGBO(255, 80, 80, 0.4)),
            ),
            child: const Center(
              child: Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: Color.fromRGBO(255, 120, 120, 0.9),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          key: const ValueKey('voice-review-send'),
          onTap: widget.onReviewSend,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color.fromRGBO(29, 185, 84, 0.15),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: const Color.fromRGBO(29, 185, 84, 0.3)),
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
      ],
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_updateInputDirection);
    _controller.dispose();
    _focusNode.dispose();
    _sendButtonController.dispose();
    super.dispose();
  }

  bool get _shouldShowSendButton =>
      (_hasText || widget.hasAttachments) && !_isRecording;

  bool get _canRecordVoice =>
      widget.onRecordStart != null && widget.onRecordStop != null;

  bool get _isRecording => widget.recordingState != VoiceRecordingState.idle
      ? widget.recordingState.isActive
      : widget.isRecording;

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
                      onTap: widget.isProcessing || _isRecording
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
                  // Review preview, recording overlay, or text input
                  Expanded(
                    child: widget.recordingState.isReviewing
                        ? _buildReviewPreview(context)
                        : _isRecording
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
                              textDirection: _inputDirection,
                              maxLines: null,
                              maxLength: maxMessageLength,
                              enabled: !_isRecording,
                              style: const TextStyle(
                                fontSize: 15,
                                color: Color.fromRGBO(255, 255, 255, 0.95),
                                height: 1.5,
                              ),
                              decoration: InputDecoration(
                                hintText: AppLocalizations.of(
                                  context,
                                )!.conversation_hint,
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
                  // Review actions, mic button, or send button
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: widget.recordingState.isReviewing
                        ? _buildReviewActions(context)
                        : _shouldShowMicButton
                        ? VoiceRecordButton(
                            onTapDown: widget.onRecordStart!,
                            onTapUp: widget.onRecordStop!,
                            onTapCancel: widget.onRecordCancel ?? () {},
                            isRecording: _isRecording,
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
                                      !widget.hasInvalidAttachment &&
                                      (_hasText || widget.hasAttachments)
                                  ? _onSendPressed
                                  : null,
                              child: Container(
                                // Match the VoiceRecordButton (48x48) so the
                                // send affordance is the same size as the mic
                                // and the slot doesn't resize when text is typed.
                                width: 48,
                                height: 48,
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
