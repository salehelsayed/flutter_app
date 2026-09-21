import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';

enum VoiceRecordPhase { idle, arming, recording, stopping }

/// Mic button for voice recording. Replaces the send button when text is empty.
///
/// Tap to start recording, tap again to stop. `onTapCancel` is reserved for
/// pointer cancellation while a start gesture is in flight.
class VoiceRecordButton extends StatefulWidget {
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;
  final VoidCallback onTapCancel;
  final bool isRecording;
  final VoiceRecordPhase? phase;

  const VoiceRecordButton({
    super.key,
    required this.onTapDown,
    required this.onTapUp,
    required this.onTapCancel,
    this.isRecording = false,
    this.phase,
  });

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton> {
  int? _activePointer;
  bool _isPressed = false;
  bool _startedRecordingWithThisTap = false;

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null || event.buttons != kPrimaryButton) return;
    _activePointer = event.pointer;
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
    if (_activePointer == null) return;
    _activePointer = null;
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
    if (_activePointer == null) return;
    _activePointer = null;
    final startedRecordingWithThisTap = _startedRecordingWithThisTap;
    setState(() {
      _isPressed = false;
      _startedRecordingWithThisTap = false;
    });

    if (startedRecordingWithThisTap) {
      // Recognizer disposal can cancel after this element is deactivated.
      // Abort the start without tap feedback, which needs an active context.
      widget.onTapCancel();
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_activePointer != event.pointer) return;
    // Pointer dispatch completes the tap arena synchronously. A drag that
    // rejected before onTapDown has no onTapCancel callback, so abort its
    // provisional recording after dispatch if no recognized tap completed it.
    scheduleMicrotask(() {
      if (mounted && _activePointer == event.pointer) _onTapCancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isRecording = widget.isRecording;
    final readableColors = context.backgroundReadableColors;
    final buttonColor = isRecording
        ? readableColors.accent
        : readableColors.micBg;
    final borderColor = isRecording
        ? Colors.transparent
        : readableColors.micBorder;
    final iconColor = isRecording
        ? readableColors.accentIcon
        : readableColors.micIcon;
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(Localizations.localeOf(context));
    final phase =
        widget.phase ??
        (isRecording ? VoiceRecordPhase.recording : VoiceRecordPhase.idle);
    final label = switch (phase) {
      VoiceRecordPhase.idle => l10n.voice_record_action,
      VoiceRecordPhase.arming => l10n.voice_cancel_start_action,
      VoiceRecordPhase.recording => l10n.voice_stop_send_action,
      VoiceRecordPhase.stopping => l10n.voice_finishing_label,
    };
    final hint = switch (phase) {
      VoiceRecordPhase.idle => l10n.voice_record_hint,
      VoiceRecordPhase.arming => l10n.voice_cancel_start_hint,
      VoiceRecordPhase.recording => l10n.voice_stop_send_hint,
      VoiceRecordPhase.stopping => null,
    };
    final enabled = phase != VoiceRecordPhase.stopping;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      hint: hint,
      onTap: enabled ? (isRecording ? widget.onTapUp : widget.onTapDown) : null,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        // A touch tooltip must not win the arena and abort a held recording
        // start. The label/hint and mouse-hover tooltip remain available.
        triggerMode: TooltipTriggerMode.manual,
        child: IgnorePointer(
          ignoring: !enabled,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerUp: _onPointerUp,
            onPointerCancel: (event) {
              if (_activePointer == event.pointer) _onTapCancel();
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTapDown: (_) {},
              onTapUp: (_) => _onTapUp(),
              onTapCancel: _onTapCancel,
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
                        ? [
                            BoxShadow(
                              color: readableColors.micShadow,
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Icon(
                      isRecording
                          ? Icons.arrow_upward_rounded
                          : Icons.mic_rounded,
                      size: 20,
                      color: iconColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
