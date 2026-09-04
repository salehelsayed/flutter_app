import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';

/// Foreground audio controls driven by the current engine projection.
///
/// This widget does not optimistically toggle any state. Callers update
/// [isMuted] and [isSpeakerOn] only after the audio layer reports the result.
class CallControls extends StatelessWidget {
  const CallControls({
    super.key,
    required this.isMuted,
    required this.isMuteAvailable,
    required this.isSpeakerOn,
    required this.isSpeakerAvailable,
    required this.selectedRoute,
    required this.audioStatusMessage,
    required this.muteUnavailableMessage,
    required this.speakerUnavailableMessage,
    required this.onMute,
    required this.onSpeaker,
    required this.onEnd,
  });

  final bool isMuted;
  final bool isMuteAvailable;
  final bool isSpeakerOn;
  final bool isSpeakerAvailable;
  final CallAudioOutputRoute selectedRoute;
  final String? audioStatusMessage;
  final String muteUnavailableMessage;
  final String speakerUnavailableMessage;
  final VoidCallback onMute;
  final VoidCallback onSpeaker;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.backgroundReadableColors;
    final muteTooltip = isMuteAvailable
        ? (isMuted ? 'Unmute' : 'Mute')
        : _truthfulMuteUnavailableMessage;
    final speakerTooltip = isSpeakerAvailable
        ? (isSpeakerOn ? 'Turn speaker off' : 'Speaker')
        : _truthfulSpeakerUnavailableMessage;
    final statusMessage = _truthfulAudioStatusMessage;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Call controls',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: true,
            label: 'Audio output: $_selectedRouteLabel',
            excludeSemantics: true,
            child: Text(
              'Audio output: $_selectedRouteLabel',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (statusMessage != null) ...[
            const SizedBox(height: 6),
            Semantics(
              liveRegion: true,
              label: statusMessage,
              excludeSemantics: true,
              child: Text(
                statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Control(
                tooltip: muteTooltip,
                label: isMuted ? 'Unmute' : 'Mute',
                icon: isMuted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
                backgroundColor: isMuteAvailable
                    ? (isMuted ? colors.accent : colors.surfaceRaised)
                    : colors.disabledSurface,
                foregroundColor: isMuteAvailable
                    ? (isMuted ? colors.accentIcon : colors.iconPrimary)
                    : colors.disabledForeground,
                semanticsEnabled: isMuteAvailable,
                onPressed: isMuteAvailable
                    ? onMute
                    : () => _showUnavailable(
                        context,
                        _truthfulMuteUnavailableMessage,
                      ),
              ),
              _Control(
                tooltip: speakerTooltip,
                label: 'Speaker',
                icon: isSpeakerOn
                    ? Icons.volume_up_rounded
                    : Icons.volume_down_outlined,
                backgroundColor: isSpeakerAvailable
                    ? (isSpeakerOn ? colors.accent : colors.surfaceRaised)
                    : colors.disabledSurface,
                foregroundColor: isSpeakerAvailable
                    ? (isSpeakerOn ? colors.accentIcon : colors.iconPrimary)
                    : colors.disabledForeground,
                semanticsEnabled: isSpeakerAvailable,
                onPressed: isSpeakerAvailable
                    ? onSpeaker
                    : () => _showUnavailable(
                        context,
                        _truthfulSpeakerUnavailableMessage,
                      ),
              ),
              _Control(
                tooltip: 'End call',
                label: 'End',
                icon: Icons.call_end_rounded,
                backgroundColor: const Color(0xFFE5484D),
                foregroundColor: Colors.white,
                onPressed: onEnd,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String get _selectedRouteLabel => switch (selectedRoute) {
    CallAudioOutputRoute.systemDefault => 'System default',
    CallAudioOutputRoute.earpiece => 'Earpiece',
    CallAudioOutputRoute.speaker => 'Speaker',
    CallAudioOutputRoute.wiredHeadset => 'Wired headset',
    CallAudioOutputRoute.bluetooth => 'Bluetooth',
  };

  String? get _truthfulAudioStatusMessage {
    final message = audioStatusMessage?.trim();
    return message == null || message.isEmpty ? null : message;
  }

  String get _truthfulSpeakerUnavailableMessage {
    final message = speakerUnavailableMessage.trim();
    return message.isEmpty
        ? 'Speaker is unavailable for the current audio route'
        : message;
  }

  String get _truthfulMuteUnavailableMessage {
    final message = muteUnavailableMessage.trim();
    return message.isEmpty
        ? 'Microphone controls are unavailable until audio is ready'
        : message;
  }

  void _showUnavailable(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Control extends StatelessWidget {
  const _Control({
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
    this.semanticsEnabled = true,
  });

  final String tooltip;
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onPressed;
  final bool semanticsEnabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      enabled: semanticsEnabled,
      label: semanticsEnabled ? label : '$label. $tooltip',
      onTap: semanticsEnabled ? onPressed : null,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon),
            color: foregroundColor,
            iconSize: 28,
            style: IconButton.styleFrom(
              backgroundColor: backgroundColor,
              fixedSize: const Size.square(64),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: semanticsEnabled
                  ? context.backgroundReadableColors.textSecondary
                  : context.backgroundReadableColors.disabledForeground,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
