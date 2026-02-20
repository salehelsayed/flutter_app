import 'dart:ui';

import 'package:flutter/material.dart';

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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section label
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'RECOVERY PHRASE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.88,
                color: Color.fromRGBO(255, 255, 255, 0.4),
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
                  color: const Color.fromRGBO(255, 255, 255, 0.08),
                  border: Border.all(
                    color: const Color.fromRGBO(255, 255, 255, 0.12),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Warning text
                    const Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: Text(
                        'Never share this phrase with anyone. It grants full access to your account.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                          color: Color(0xFFF87171),
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
                                child: _buildWordGrid(),
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
                                      color: const Color.fromRGBO(
                                          10, 10, 15, 0.4),
                                    ),
                                    child: const Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.visibility,
                                          size: 24,
                                          color: Color.fromRGBO(
                                              255, 255, 255, 0.6),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'Tap to reveal',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Color.fromRGBO(
                                                255, 255, 255, 0.6),
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
                                    color: const Color.fromRGBO(
                                        255, 255, 255, 0.08),
                                    border: Border.all(
                                      color: const Color.fromRGBO(
                                          255, 255, 255, 0.12),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        child: Icon(
                                          isCopied
                                              ? Icons.check
                                              : Icons.copy,
                                          key: ValueKey(isCopied),
                                          size: 16,
                                          color: isCopied
                                              ? const Color(0xFF14B8A6)
                                              : const Color.fromRGBO(
                                                  255, 255, 255, 0.6),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        child: Text(
                                          isCopied
                                              ? 'Copied!'
                                              : 'Copy to clipboard',
                                          key: ValueKey(isCopied),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: Color.fromRGBO(
                                                255, 255, 255, 0.6),
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
                                  color: const Color.fromRGBO(
                                      255, 255, 255, 0.08),
                                  border: Border.all(
                                    color: const Color.fromRGBO(
                                        255, 255, 255, 0.12),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.visibility_off,
                                      size: 18,
                                      color:
                                          Color.fromRGBO(255, 255, 255, 0.6),
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Hide',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color:
                                            Color.fromRGBO(255, 255, 255, 0.6),
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

  Widget _buildWordGrid() {
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
                  color: const Color.fromRGBO(255, 255, 255, 0.04),
                  border: Border.all(
                    color: const Color.fromRGBO(255, 255, 255, 0.06),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color.fromRGBO(255, 255, 255, 0.4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        words[index],
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color.fromRGBO(255, 255, 255, 0.95),
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
