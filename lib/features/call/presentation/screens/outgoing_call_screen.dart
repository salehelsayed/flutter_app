import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Foreground-only outgoing call presentation.
///
/// [state] is the canonical reducer state. In particular, this surface never
/// invents `Ringing` before the authenticated remote ringing event is reduced.
class OutgoingCallScreen extends StatelessWidget {
  const OutgoingCallScreen({
    super.key,
    required this.contactPeerId,
    required this.contactUsername,
    required this.state,
    required this.onCancel,
  });

  final String contactPeerId;
  final String contactUsername;
  final CallState state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;

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
                label: _status,
                excludeSemantics: true,
                child: Text(
                  _status,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: l10n.call_cancel,
                onPressed: onCancel,
                icon: const Icon(Icons.call_end_rounded),
                color: Colors.white,
                iconSize: 30,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFE5484D),
                  fixedSize: const Size.square(68),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.btn_cancel,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _status => switch (state) {
    CallState.ringing => 'Ringing',
    CallState.accepted || CallState.negotiating => 'Connecting',
    CallState.connected => 'Connected',
    CallState.reconnecting => 'Reconnecting',
    CallState.ending || CallState.ended => 'Ending',
    _ => 'Calling',
  };
}
