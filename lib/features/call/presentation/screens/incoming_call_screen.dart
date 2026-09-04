import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

/// Foreground-only incoming call presentation.
///
/// Answer and decline are available only for the canonical validated ringing
/// state. Incoming validation itself never captures audio or exposes controls.
class IncomingCallScreen extends StatelessWidget {
  const IncomingCallScreen({
    super.key,
    required this.contactPeerId,
    required this.contactUsername,
    required this.state,
    required this.onAnswer,
    required this.onDecline,
  });

  final String contactPeerId;
  final String contactUsername;
  final CallState state;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;

  bool get _canRespond => state == CallState.ringing;

  @override
  Widget build(BuildContext context) {
    final colors = context.backgroundReadableColors;

    return ColoredBox(
      color: colors.surfaceBase,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
          child: Column(
            children: [
              const Spacer(),
              UserAvatar(peerId: contactPeerId, size: 112),
              const SizedBox(height: 24),
              Text(
                contactUsername,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Semantics(
                liveRegion: true,
                label: _canRespond ? 'Incoming call' : 'Checking incoming call',
                excludeSemantics: true,
                child: Text(
                  _canRespond ? 'Incoming call' : 'Checking incoming call',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _IncomingAction(
                    tooltip: _canRespond ? 'Decline' : 'Decline unavailable',
                    label: 'Decline',
                    icon: Icons.call_end_rounded,
                    backgroundColor: const Color(0xFFE5484D),
                    enabled: _canRespond,
                    onPressed: onDecline,
                  ),
                  _IncomingAction(
                    tooltip: _canRespond ? 'Answer' : 'Answer unavailable',
                    label: 'Answer',
                    icon: Icons.call_rounded,
                    backgroundColor: colors.accent,
                    enabled: _canRespond,
                    onPressed: onAnswer,
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

class _IncomingAction extends StatelessWidget {
  const _IncomingAction({
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.enabled,
    required this.onPressed,
  });

  final String tooltip;
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.backgroundReadableColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: tooltip,
          onPressed: enabled ? onPressed : null,
          icon: Icon(icon),
          color: Colors.white,
          disabledColor: colors.disabledForeground,
          iconSize: 30,
          style: IconButton.styleFrom(
            backgroundColor: enabled ? backgroundColor : colors.disabledSurface,
            fixedSize: const Size.square(68),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            color: enabled ? colors.textSecondary : colors.disabledForeground,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
