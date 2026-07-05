import 'package:flutter/material.dart';
import 'package:flutter_app/features/home/presentation/widgets/editable_username_widget.dart';

/// Feed header showing the handle.
///
/// 211 — the connection dot migrated to the Orbit top-right chrome (next to
/// the "+"); the 206 locks (no avatar — the Settings entry is the Orbit
/// center avatar — and the username editor) are unchanged.
class FeedHeader extends StatelessWidget {
  final String username;
  final ValueChanged<String>? onUsernameChanged;

  const FeedHeader({
    super.key,
    required this.username,
    this.onUsernameChanged,
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
      ],
    );
  }
}
