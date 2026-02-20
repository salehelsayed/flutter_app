import 'dart:ui';

import 'package:flutter/material.dart';

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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section label
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'PEER ID',
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
                              color: const Color.fromRGBO(255, 255, 255, 0.03),
                              border: Border.all(
                                color:
                                    const Color.fromRGBO(255, 255, 255, 0.05),
                              ),
                            ),
                            child: Text(
                              peerId,
                              style: const TextStyle(
                                fontFamily: 'SF Mono',
                                fontFamilyFallback: ['Fira Code', 'monospace'],
                                fontSize: 12,
                                height: 1.5,
                                color: Color.fromRGBO(255, 255, 255, 0.95),
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
                              color: const Color.fromRGBO(255, 255, 255, 0.08),
                              border: Border.all(
                                color:
                                    const Color.fromRGBO(255, 255, 255, 0.12),
                              ),
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                isCopied ? Icons.check : Icons.copy,
                                key: ValueKey(isCopied),
                                size: 16,
                                color: isCopied
                                    ? const Color(0xFF14B8A6)
                                    : const Color.fromRGBO(255, 255, 255, 0.6),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Helper text
                    const Text(
                      'Your unique identifier on the network',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color.fromRGBO(255, 255, 255, 0.4),
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
