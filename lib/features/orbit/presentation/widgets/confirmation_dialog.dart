import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

/// Shows a confirmation dialog with a title, description, and danger action.
///
/// Returns `true` if confirmed, `false` if cancelled (including overlay tap).
Future<bool> showConfirmationDialog({
  required BuildContext context,
  required String title,
  required String description,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) => _ConfirmationDialog(
      title: title,
      description: description,
      confirmLabel: confirmLabel,
    ),
  );
  return result ?? false;
}

class _ConfirmationDialog extends StatelessWidget {
  final String title;
  final String description;
  final String confirmLabel;

  const _ConfirmationDialog({
    required this.title,
    required this.description,
    required this.confirmLabel,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = min(340.0, screenWidth - 48.0);

    return Stack(
      children: [
        // Overlay — tapping dismisses with false
        GestureDetector(
          onTap: () => Navigator.of(context).pop(false),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: Container(
              color: const Color(0x9E05080E),
            ),
          ),
        ),

        // Dialog card — centered
        Center(
          child: GestureDetector(
            onTap: () {}, // Prevent dismiss when tapping card
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                width: cardWidth,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color.fromRGBO(255, 255, 255, 0.14),
                  ),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.fromRGBO(18, 20, 28, 0.98),
                      Color.fromRGBO(11, 13, 20, 0.98),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color.fromRGBO(255, 255, 255, 0.96),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: Color.fromRGBO(255, 255, 255, 0.62),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        // Cancel button
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).pop(false),
                            child: Container(
                              height: 38,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: const Color.fromRGBO(
                                  255, 255, 255, 0.07),
                                border: Border.all(
                                  color: const Color.fromRGBO(
                                    255, 255, 255, 0.16),
                                ),
                              ),
                              child: const Center(
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color.fromRGBO(
                                      255, 255, 255, 0.7),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Danger confirm button
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).pop(true),
                            child: Container(
                              height: 38,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFEF4444),
                                    Color(0xFFDC2626),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  confirmLabel,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
