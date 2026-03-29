import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';

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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'DEBUG INTRODUCTIONS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.88,
                color: Color.fromRGBO(255, 255, 255, 0.4),
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
                  color: const Color.fromRGBO(255, 255, 255, 0.08),
                  border: Border.all(
                    color: const Color.fromRGBO(255, 255, 255, 0.12),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Local sent intro rows on this device. Deleting a pair makes it selectable again in the picker.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: Color.fromRGBO(255, 255, 255, 0.65),
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
                              color: const Color.fromRGBO(255, 255, 255, 0.08),
                              border: Border.all(
                                color: const Color.fromRGBO(
                                  255,
                                  255,
                                  255,
                                  0.12,
                                ),
                              ),
                            ),
                            child: const Icon(
                              Icons.refresh,
                              size: 16,
                              color: Color.fromRGBO(255, 255, 255, 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF14B8A6),
                          ),
                        ),
                      )
                    else if (errorText != null)
                      Text(
                        errorText!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFF87171),
                        ),
                      )
                    else if (introductions.isEmpty)
                      const Text(
                        'No local introduction rows for the current user.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color.fromRGBO(255, 255, 255, 0.5),
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
        color: const Color.fromRGBO(255, 255, 255, 0.04),
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$recipientLabel <-> $introducedLabel',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color.fromRGBO(255, 255, 255, 0.95),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'status=${intro.status.toDbString()}  recipient=${intro.recipientStatus.toDbString()}  introduced=${intro.introducedStatus.toDbString()}',
            style: const TextStyle(
              fontFamily: 'SF Mono',
              fontFamilyFallback: ['Fira Code', 'monospace'],
              fontSize: 11,
              color: Color.fromRGBO(255, 255, 255, 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'id=${intro.id}  created=${intro.createdAt}',
            style: const TextStyle(
              fontFamily: 'SF Mono',
              fontFamilyFallback: ['Fira Code', 'monospace'],
              fontSize: 11,
              color: Color.fromRGBO(255, 255, 255, 0.55),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DebugActionButton(
                key: ValueKey('settings-intro-delete-row-${intro.id}'),
                label: 'Delete Row',
                color: const Color(0xFFF87171),
                onTap: () => onDeleteIntroduction(intro.id),
              ),
              _DebugActionButton(
                key: ValueKey('settings-intro-delete-pair-${intro.id}'),
                label: 'Delete Pair',
                color: const Color(0xFFFB923C),
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
          color: color.withOpacity(0.16),
          border: Border.all(color: color.withOpacity(0.32)),
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
