import 'package:flutter/material.dart';

/// Banner shown in place of ComposeArea when a contact is blocked.
///
/// Displays a block icon, explanatory text, and an "Unblock" button.
class BlockedBanner extends StatelessWidget {
  final VoidCallback? onUnblock;

  const BlockedBanner({super.key, this.onUnblock});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color.fromRGBO(255, 255, 255, 0.04),
        border: Border(
          top: BorderSide(
            color: Color.fromRGBO(255, 255, 255, 0.08),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.block,
                size: 16,
                color: Color.fromRGBO(255, 255, 255, 0.35),
              ),
              const SizedBox(width: 8),
              const Text(
                'You blocked this contact.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: Color.fromRGBO(255, 255, 255, 0.5),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onUnblock,
                child: const Text(
                  'Unblock',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF10B981),
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
