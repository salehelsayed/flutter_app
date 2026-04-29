import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';

/// Glass card displaying the user's peer ID with a copy button.
class SettingsPeerIdCard extends StatelessWidget {
  final String peerId;
  final bool isCopied;
  final VoidCallback? onCopy;

  const SettingsPeerIdCard({
    super.key,
    required this.peerId,
    this.isCopied = false,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final copiedColor = readableColors.isLightSurface
        ? const Color(0xFF0F766E)
        : const Color(0xFF14B8A6);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section label
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'PEER ID',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.88,
                color: readableColors.textMuted,
              ),
            ),
          ),
          // Glass card
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: readableColors.glassSurface,
                  border: Border.all(color: readableColors.glassBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Peer ID row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: readableColors.surfaceSubtle,
                              border: Border.all(color: readableColors.border),
                            ),
                            child: Text(
                              peerId,
                              style: TextStyle(
                                fontFamily: 'SF Mono',
                                fontFamilyFallback: const [
                                  'Fira Code',
                                  'monospace',
                                ],
                                fontSize: 12,
                                height: 1.5,
                                color: readableColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Copy button
                        GestureDetector(
                          onTap: onCopy,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: readableColors.surfaceSubtle,
                              border: Border.all(
                                color: readableColors.glassBorder,
                              ),
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                isCopied ? Icons.check : Icons.copy,
                                key: ValueKey(isCopied),
                                size: 16,
                                color: isCopied
                                    ? copiedColor
                                    : readableColors.iconSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Helper text
                    Text(
                      'Your unique identifier on the network',
                      style: TextStyle(
                        fontSize: 12,
                        color: readableColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
