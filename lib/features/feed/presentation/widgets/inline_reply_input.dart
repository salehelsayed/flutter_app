import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/shared/widgets/media/recording_overlay.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/voice_record_button.dart';

/// Pill-shaped single-line inline reply input with animated send button.
///
/// Used in collapsed thread cards for quick replies without leaving the feed.
/// GestureDetector wrapping absorbs taps to prevent parent card interaction.
/// Styled to match the conversation ComposeArea.
class InlineReplyInput extends StatefulWidget {
  final String hintText;
  final ValueChanged<String> onSend;
  final bool enabled;
  final String initialText;
  final bool shouldRequestFocus;
  final ValueChanged<String>? onDraftChanged;
  final ValueChanged<bool>? onFocusChanged;
  final VoidCallback? onAttach;
  final VoidCallback? onRecordStart;
  final VoidCallback? onRecordStop;
  final VoidCallback? onRecordCancel;
  final bool isRecording;
  final VoiceRecordingState recordingState;
  final Duration recordingDuration;
  final List<double> amplitudeValues;

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
    this.onRecordStart,
    this.onRecordStop,
    this.onRecordCancel,
    this.isRecording = false,
    this.recordingState = VoiceRecordingState.idle,
    this.recordingDuration = Duration.zero,
    this.amplitudeValues = const [],
  });

  @override
  State<InlineReplyInput> createState() => _InlineReplyInputState();
}

class _InlineReplyInputState extends State<InlineReplyInput>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  TextDirection _inputDirection = TextDirection.ltr;
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

    // When voice is available, fully hide send (0→1).
    // When voice is NOT available, keep dimmed send always visible (0.46→1).
    if (_canRecordVoice) {
      _sendScale = Tween<double>(begin: 0.9, end: 1.0).animate(sendCurve);
      _sendOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(sendCurve);
    } else {
      _sendScale = Tween<double>(begin: 0.86, end: 1.0).animate(sendCurve);
      _sendOpacity = Tween<double>(begin: 0.46, end: 1.0).animate(sendCurve);
    }

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
  void didUpdateWidget(InlineReplyInput oldWidget) {
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

  bool get _canRecordVoice =>
      widget.onRecordStart != null && widget.onRecordStop != null;

  VoiceRecordingState get _effectiveRecordingState =>
      widget.recordingState != VoiceRecordingState.idle
      ? widget.recordingState
      : (widget.isRecording
            ? VoiceRecordingState.recording
            : VoiceRecordingState.idle);

  bool get _isRecording => _effectiveRecordingState.isActive;

  bool get _shouldShowMicButton =>
      (!_hasText || _isRecording) && _canRecordVoice;

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
      child: SizedBox(
        height: _isRecording ? 56 : 44,
        child: Row(
          children: [
            if (widget.onAttach != null) ...[
              GestureDetector(
                onTap: widget.onAttach,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(255, 255, 255, 0.08),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: const Color.fromRGBO(255, 255, 255, 0.15),
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.add_rounded,
                      size: 20,
                      color: Color.fromRGBO(255, 255, 255, 0.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: _isRecording
                  ? RecordingOverlay(
                      elapsed: widget.recordingDuration,
                      onCancel: widget.onRecordCancel ?? () {},
                      amplitudeValues: widget.amplitudeValues,
                    )
                  : AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
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
                            : [
                                const BoxShadow(
                                  color: Color.fromRGBO(0, 0, 0, 0.24),
                                  blurRadius: 12,
                                  offset: Offset(0, 6),
                                ),
                              ],
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        textDirection: _inputDirection,
                        enabled: widget.enabled && !_isRecording,
                        maxLines: 1,
                        maxLength: maxMessageLength,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color.fromRGBO(255, 255, 255, 0.95),
                          height: 1.5,
                        ),
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          hintText: widget.hintText,
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
                          isDense: true,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            if (_shouldShowMicButton)
              VoiceRecordButton(
                onTapDown: widget.onRecordStart!,
                onTapUp: widget.onRecordStop!,
                onTapCancel: widget.onRecordCancel ?? () {},
                isRecording: _isRecording,
              )
            else
              ScaleTransition(
                scale: _sendScale,
                child: FadeTransition(
                  opacity: _sendOpacity,
                  child: GestureDetector(
                    onTap: _hasText ? _onSendPressed : null,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(29, 185, 84, 0.15),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: const Color.fromRGBO(29, 185, 84, 0.3),
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
      ),
    );
  }
}
