import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';

/// Frosted-glass sticky header for the conversation screen.
///
/// Shows back button, contact avatar, name, connection status, and overflow menu.
class ConversationHeader extends StatelessWidget {
  final String contactPeerId;
  final String contactUsername;
  final String connectionDate;
  final VoidCallback onBack;
  final VoidCallback? onOverflow;
  final VoidCallback? onCall;
  final bool showCallAction;
  final bool callActionEnabled;
  final bool callActionInFlight;
  final String callUnavailableMessage;

  /// Invoked when the avatar / name block is tapped (opens the contact profile).
  final VoidCallback? onAvatarTap;

  const ConversationHeader({
    super.key,
    required this.contactPeerId,
    required this.contactUsername,
    required this.connectionDate,
    required this.onBack,
    this.onOverflow,
    this.onAvatarTap,
    this.onCall,
    this.showCallAction = false,
    this.callActionEnabled = false,
    this.callActionInFlight = false,
    this.callUnavailableMessage =
        'Voice calling is unavailable for this device',
  });

  /// Stable route-level accessibility marker consumed by the iOS notification
  /// tap proof. Unlike matching an arbitrary descendant named after the actor,
  /// this identifier exists only while that conversation header is rendered.
  static String accessibilityIdentifierFor(String contactUsername) =>
      'mknoon.conversation.$contactUsername';

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Semantics(
      container: true,
      identifier: accessibilityIdentifierFor(contactUsername),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              right: 12,
              bottom: 12,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  readableColors.glassSurface,
                  readableColors.glassSurface.withValues(alpha: 0.85),
                  readableColors.glassSurface.withValues(alpha: 0),
                ],
                stops: [0.0, 0.8, 1.0],
              ),
            ),
            child: Row(
              children: [
                // Back button
                GestureDetector(
                  onTap: onBack,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Icon(
                        Icons.chevron_left,
                        size: 24,
                        color: readableColors.iconSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Avatar + name (tappable → contact profile)
                Expanded(
                  child: GestureDetector(
                    onTap: onAvatarTap,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: [
                        UserAvatar(peerId: contactPeerId, size: 36),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                contactUsername,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: readableColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                AppLocalizations.of(
                                  context,
                                )!.connected_date(connectionDate),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: readableColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (showCallAction)
                  _ConversationCallAction(
                    enabled: callActionEnabled && onCall != null,
                    inFlight: callActionInFlight,
                    unavailableMessage: callUnavailableMessage,
                    onCall: onCall,
                  ),
                // Overflow button
                GestureDetector(
                  onTap: onOverflow,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Icon(
                        Icons.more_vert,
                        size: 20,
                        color: readableColors.iconMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationCallAction extends StatelessWidget {
  const _ConversationCallAction({
    required this.enabled,
    required this.inFlight,
    required this.unavailableMessage,
    required this.onCall,
  });

  final bool enabled;
  final bool inFlight;
  final String unavailableMessage;
  final VoidCallback? onCall;

  String get _truthfulUnavailableMessage {
    final message = unavailableMessage.trim();
    return message.isEmpty
        ? 'Voice calling is unavailable for this device'
        : message;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.backgroundReadableColors;
    final tooltip = inFlight
        ? 'Starting voice call'
        : enabled
        ? 'Start voice call'
        : _truthfulUnavailableMessage;

    return Semantics(
      button: true,
      enabled: enabled,
      label: enabled ? 'Start voice call' : tooltip,
      onTap: enabled ? onCall : null,
      excludeSemantics: true,
      child: IconButton(
        tooltip: tooltip,
        onPressed: enabled
            ? onCall
            : inFlight
            ? null
            : () => _showUnavailable(context),
        icon: const Icon(Icons.call_outlined),
        iconSize: 22,
        color: enabled ? colors.iconSecondary : colors.disabledForeground,
        style: IconButton.styleFrom(
          backgroundColor: enabled
              ? Colors.transparent
              : colors.disabledSurface,
          fixedSize: const Size.square(44),
        ),
      ),
    );
  }

  void _showUnavailable(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(_truthfulUnavailableMessage)));
  }
}
