import 'package:flutter/material.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/home/presentation/widgets/editable_username_widget.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

/// Feed header showing the handle and connection status.
///
/// 206 — the top-right user avatar (the old Settings entry) was removed; the
/// only avatar-based Settings entry is now the Orbit center avatar. The
/// username editor and the connection status indicator are unchanged.
class FeedHeader extends StatelessWidget {
  final String username;
  final ValueChanged<String>? onUsernameChanged;
  final P2PService? p2pService;

  const FeedHeader({
    super.key,
    required this.username,
    this.onUsernameChanged,
    this.p2pService,
  });

  @override
  Widget build(BuildContext context) {
    final displayUsername = username.trim().isEmpty ? 'Username' : username;

    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: EditableUsernameWidget(
              username: displayUsername,
              onUsernameChanged: onUsernameChanged,
            ),
          ),
        ),
        if (p2pService != null) ...[
          const SizedBox(width: 10),
          ConnectionStatusIndicator(p2pService: p2pService!),
        ],
      ],
    );
  }
}
