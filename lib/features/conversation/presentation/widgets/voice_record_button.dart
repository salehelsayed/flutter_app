import 'package:flutter/material.dart';

/// Mic button for voice recording. Replaces the send button when text is empty.
///
/// Long press to start recording, release to stop and send.
/// Drag away to cancel.
class VoiceRecordButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => onTapDown(),
      onLongPressEnd: (_) => onTapUp(),
      onLongPressCancel: () => onTapCancel(),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color.fromRGBO(29, 185, 84, 0.15),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: const Color.fromRGBO(29, 185, 84, 0.3),
          ),
        ),
        child: Center(
          child: Icon(
            isRecording ? Icons.stop_rounded : Icons.mic_rounded,
            size: 22,
            color: const Color(0xFF1DB954),
          ),
        ),
      ),
    );
  }
}
