import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// 248 (TC-22) — structural/text colors read from [BackgroundReadableColors] so
/// this debug card is readable under Signal light (the old translucent-white
/// literals vanished on light). Success/error/destructive actions stay distinct
/// and readable. kDebugMode-only, so its dark chrome may differ slightly from
/// the prior literals (accepted; TC-25 preserves only release surfaces).
class SettingsIntroductionDebugCard extends StatelessWidget {
  final List<IntroductionModel> introductions;
  final bool isLoading;
  final String? errorText;
  final VoidCallback onRefresh;
  final ValueChanged<String> onDeleteIntroduction;
  final ValueChanged<IntroductionModel> onDeletePair;

  const SettingsIntroductionDebugCard({
    super.key,
    required this.introductions,
    required this.isLoading,
    required this.errorText,
    required this.onRefresh,
    required this.onDeleteIntroduction,
    required this.onDeletePair,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final readable = context.backgroundReadableColors;
    final isLight = readable.isLightSurface;
    final errorColor = isLight
        ? const Color(0xFFB4232F)
        : const Color(0xFFF87171);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              l10n.settings_intro_debug_heading,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.88,
                color: readable.textMuted,
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: readable.surfaceRaised,
                  border: Border.all(color: readable.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.settings_intro_debug_description,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: readable.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          key: const ValueKey('settings-intro-debug-refresh'),
                          onTap: onRefresh,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: readable.surfaceSubtle,
                              border: Border.all(color: readable.surfaceBorder),
                            ),
                            child: Icon(
                              Icons.refresh,
                              size: 16,
                              color: readable.iconSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (isLoading)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: readable.accent,
                          ),
                        ),
                      )
                    else if (errorText != null)
                      Text(
                        errorText!,
                        style: TextStyle(fontSize: 12, color: errorColor),
                      )
                    else if (introductions.isEmpty)
                      Text(
                        l10n.settings_intro_debug_empty,
                        style: TextStyle(
                          fontSize: 12,
                          color: readable.textMuted,
                        ),
                      )
                    else
                      Column(
                        children: introductions
                            .map(
                              (intro) => _IntroductionDebugRow(
                                intro: intro,
                                onDeleteIntroduction: onDeleteIntroduction,
                                onDeletePair: onDeletePair,
                              ),
                            )
                            .toList(),
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

class _IntroductionDebugRow extends StatelessWidget {
  final IntroductionModel intro;
  final ValueChanged<String> onDeleteIntroduction;
  final ValueChanged<IntroductionModel> onDeletePair;

  const _IntroductionDebugRow({
    required this.intro,
    required this.onDeleteIntroduction,
    required this.onDeletePair,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final readable = context.backgroundReadableColors;
    final isLight = readable.isLightSurface;
    // Distinct destructive (delete-row) vs warning (delete-pair) actions.
    final deleteRowColor = isLight
        ? const Color(0xFFB4232F)
        : const Color(0xFFF87171);
    final deletePairColor = isLight
        ? const Color(0xFF9A3412)
        : const Color(0xFFFB923C);
    final recipientLabel = _displayLabel(
      intro.recipientUsername,
      intro.recipientId,
    );
    final introducedLabel = _displayLabel(
      intro.introducedUsername,
      intro.introducedId,
    );

    return Container(
      key: ValueKey('settings-intro-debug-row-${intro.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: readable.surfaceSubtle,
        border: Border.all(color: readable.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$recipientLabel <-> $introducedLabel',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: readable.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.settings_intro_debug_status_line(
              intro.status.toDbString(),
              intro.recipientStatus.toDbString(),
              intro.introducedStatus.toDbString(),
            ),
            style: TextStyle(
              fontFamily: 'SF Mono',
              fontFamilyFallback: const ['Fira Code', 'monospace'],
              fontSize: 11,
              color: readable.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.settings_intro_debug_meta_line(
              intro.id,
              intro.createdAt.toString(),
            ),
            style: TextStyle(
              fontFamily: 'SF Mono',
              fontFamilyFallback: const ['Fira Code', 'monospace'],
              fontSize: 11,
              color: readable.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DebugActionButton(
                key: ValueKey('settings-intro-delete-row-${intro.id}'),
                label: l10n.settings_intro_debug_delete_row,
                color: deleteRowColor,
                onTap: () => onDeleteIntroduction(intro.id),
              ),
              _DebugActionButton(
                key: ValueKey('settings-intro-delete-pair-${intro.id}'),
                label: l10n.settings_intro_debug_delete_pair,
                color: deletePairColor,
                onTap: () => onDeletePair(intro),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _displayLabel(String? username, String peerId) {
    if (username != null && username.isNotEmpty) {
      return '@$username';
    }
    return peerId;
  }
}

class _DebugActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _DebugActionButton({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: color.withValues(alpha: 0.16),
          border: Border.all(color: color.withValues(alpha: 0.32)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}
