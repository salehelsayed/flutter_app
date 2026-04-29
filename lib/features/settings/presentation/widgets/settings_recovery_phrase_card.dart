import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Glass card displaying the user's 12-word recovery phrase with blur-to-reveal.
class SettingsRecoveryPhraseCard extends StatelessWidget {
  final List<String> words;
  final bool isRevealed;
  final bool isCopied;
  final VoidCallback? onToggleReveal;
  final VoidCallback? onCopy;
  final VoidCallback? onHide;

  const SettingsRecoveryPhraseCard({
    super.key,
    required this.words,
    this.isRevealed = false,
    this.isCopied = false,
    this.onToggleReveal,
    this.onCopy,
    this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final warningColor = readableColors.isLightSurface
        ? const Color(0xFFB91C1C)
        : const Color(0xFFF87171);
    final successColor = readableColors.isLightSurface
        ? const Color(0xFF0F766E)
        : const Color(0xFF14B8A6);
    const overlayForeground = Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section label
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              AppLocalizations.of(context)!.settings_recovery_title,
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
                    // Warning text
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        AppLocalizations.of(context)!.settings_recovery_warning,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                          color: warningColor,
                        ),
                      ),
                    ),
                    // Word grid with optional blur overlay
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: Stack(
                          children: [
                            // Word grid
                            ImageFiltered(
                              imageFilter: isRevealed
                                  ? ImageFilter.blur()
                                  : ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: IgnorePointer(
                                ignoring: !isRevealed,
                                child: _buildWordGrid(readableColors),
                              ),
                            ),
                            // Reveal overlay (only when hidden)
                            if (!isRevealed)
                              Positioned.fill(
                                child: GestureDetector(
                                  onTap: onToggleReveal,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: readableColors.overlayScrim,
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.visibility,
                                          size: 24,
                                          color: overlayForeground,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          AppLocalizations.of(
                                            context,
                                          )!.settings_recovery_tap,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: overlayForeground,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Action buttons (only when revealed)
                    if (isRevealed)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Row(
                          children: [
                            // Copy button
                            Expanded(
                              child: GestureDetector(
                                onTap: onCopy,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: readableColors.surfaceSubtle,
                                    border: Border.all(
                                      color: readableColors.glassBorder,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 200,
                                        ),
                                        child: Icon(
                                          isCopied ? Icons.check : Icons.copy,
                                          key: ValueKey(isCopied),
                                          size: 16,
                                          color: isCopied
                                              ? successColor
                                              : readableColors.iconSecondary,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 200,
                                        ),
                                        child: Text(
                                          isCopied
                                              ? AppLocalizations.of(
                                                  context,
                                                )!.settings_recovery_copied
                                              : AppLocalizations.of(
                                                  context,
                                                )!.settings_recovery_copy,
                                          key: ValueKey(isCopied),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: readableColors.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Hide button
                            GestureDetector(
                              onTap: onHide,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: readableColors.surfaceSubtle,
                                  border: Border.all(
                                    color: readableColors.glassBorder,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.visibility_off,
                                      size: 18,
                                      color: readableColors.iconSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.settings_recovery_hide,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: readableColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
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

  Widget _buildWordGrid(BackgroundReadableColors readableColors) {
    final rows = <Widget>[];
    for (var row = 0; row < 4; row++) {
      final cells = <Widget>[];
      for (var col = 0; col < 3; col++) {
        final index = row * 3 + col;
        if (index < words.length) {
          cells.add(
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: readableColors.surfaceSubtle,
                  border: Border.all(color: readableColors.border),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: readableColors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        words[index],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: readableColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          if (col < 2) cells.add(const SizedBox(width: 8));
        }
      }
      rows.add(Row(children: cells));
      if (row < 3) rows.add(const SizedBox(height: 8));
    }
    return Column(children: rows);
  }
}
