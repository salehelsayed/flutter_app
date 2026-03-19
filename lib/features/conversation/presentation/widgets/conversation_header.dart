import 'dart:ui';
import 'package:flutter/material.dart';
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

  const ConversationHeader({
    super.key,
    required this.contactPeerId,
    required this.contactUsername,
    required this.connectionDate,
    required this.onBack,
    this.onOverflow,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            bottom: 12,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.fromRGBO(10, 10, 15, 0.98),
                Color.fromRGBO(10, 10, 15, 0.85),
                Color.fromRGBO(10, 10, 15, 0),
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
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Icon(
                      Icons.chevron_left,
                      size: 24,
                      color: Color.fromRGBO(255, 255, 255, 0.6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Avatar
              UserAvatar(peerId: contactPeerId, size: 36),
              const SizedBox(width: 14),
              // Name and status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      contactUsername,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color.fromRGBO(255, 255, 255, 0.95),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      AppLocalizations.of(context)!.connected_date(connectionDate),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Color.fromRGBO(255, 255, 255, 0.4),
                      ),
                    ),
                  ],
                ),
              ),
              // Overflow button
              GestureDetector(
                onTap: onOverflow,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Icon(
                      Icons.more_vert,
                      size: 20,
                      color: Color.fromRGBO(255, 255, 255, 0.4),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
