import 'package:flutter/material.dart';

/// Mic button for voice recording. Replaces the send button when text is empty.
///
/// Long press to start recording, release to stop and send.
/// Drag away to cancel.
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
  static const double _cancelThresholdPx = 96.0;
  bool _cancelTriggered = false;

  void _onLongPressStart() {
    _cancelTriggered = false;
    widget.onTapDown();
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_cancelTriggered) return;
    if (details.offsetFromOrigin.dx <= -_cancelThresholdPx) {
      _cancelTriggered = true;
      widget.onTapCancel();
    }
  }

  void _onLongPressEnd() {
    if (_cancelTriggered) {
      _cancelTriggered = false;
      return;
    }
    widget.onTapUp();
  }

  void _onLongPressCancel() {
    if (!_cancelTriggered) {
      widget.onTapCancel();
    }
    _cancelTriggered = false;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _onLongPressStart(),
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: (_) => _onLongPressEnd(),
      onLongPressCancel: _onLongPressCancel,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color.fromRGBO(29, 185, 84, 0.15),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: const Color.fromRGBO(29, 185, 84, 0.3)),
        ),
        child: Center(
          child: Icon(
            widget.isRecording ? Icons.stop_rounded : Icons.mic_rounded,
            size: 20,
            color: const Color(0xFF1DB954),
          ),
        ),
      ),
    );
  }
}
