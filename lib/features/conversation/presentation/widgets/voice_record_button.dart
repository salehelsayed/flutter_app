import 'package:flutter/material.dart';

/// Mic button for voice recording. Replaces the send button when text is empty.
///
/// Tap to start recording, tap again to stop. `onTapCancel` is reserved for
/// pointer cancellation while a start gesture is in flight.
class VoiceRecordButton extends StatefulWidget {
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;
  final VoidCallback onTapCancel;
  final bool isRecording;

  const VoiceRecordButton({
    super.key,
    required this.onTapDown,
    required this.onTapUp,
    required this.onTapCancel,
    this.isRecording = false,
  });

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton> {
  static const _accentColor = Color(0xFF1DB954);
  bool _isPressed = false;
  bool _startedRecordingWithThisTap = false;

  void _onTapDown() {
    setState(() {
      _isPressed = true;
      _startedRecordingWithThisTap = !widget.isRecording;
    });

    if (!widget.isRecording) {
      Feedback.forTap(context);
      widget.onTapDown();
    }
  }

  void _onTapUp() {
    final startedRecordingWithThisTap = _startedRecordingWithThisTap;
    setState(() {
      _isPressed = false;
      _startedRecordingWithThisTap = false;
    });

    if (!startedRecordingWithThisTap) {
      Feedback.forTap(context);
      widget.onTapUp();
    }
  }

  void _onTapCancel() {
    final startedRecordingWithThisTap = _startedRecordingWithThisTap;
    setState(() {
      _isPressed = false;
      _startedRecordingWithThisTap = false;
    });

    if (startedRecordingWithThisTap) {
      Feedback.forTap(context);
      widget.onTapCancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRecording = widget.isRecording;
    final buttonColor = isRecording
        ? _accentColor
        : const Color.fromRGBO(29, 185, 84, 0.15);
    final borderColor = isRecording
        ? Colors.transparent
        : const Color.fromRGBO(29, 185, 84, 0.3);
    final iconColor = isRecording ? Colors.white : _accentColor;
    final label = isRecording ? 'Stop recording' : 'Start voice recording';
    final hint = isRecording
        ? 'Tap to stop recording'
        : 'Tap to start recording';

    return Semantics(
      button: true,
      label: label,
      hint: hint,
      onTap: isRecording ? widget.onTapUp : widget.onTapDown,
      child: Tooltip(
        message: label,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _onTapDown(),
          onPointerUp: (_) => _onTapUp(),
          onPointerCancel: (_) => _onTapCancel(),
          child: AnimatedScale(
            scale: _isPressed ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: buttonColor,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor),
                boxShadow: isRecording
                    ? const [
                        BoxShadow(
                          color: Color.fromRGBO(29, 185, 84, 0.24),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Icon(
                  isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                  size: 20,
                  color: iconColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
