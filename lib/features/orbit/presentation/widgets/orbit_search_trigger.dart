import 'dart:ui';
import 'package:flutter/material.dart';

/// Floating glass pill at the bottom of the screen.
///
/// Contains a search button and a close button side by side.
class OrbitSearchTrigger extends StatelessWidget {
  final VoidCallback onSearchTap;
  final VoidCallback onCloseTap;

  const OrbitSearchTrigger({
    super.key,
    required this.onSearchTap,
    required this.onCloseTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: FractionallySizedBox(
          widthFactor: 0.75,
          child: Row(
            children: [
              // Search button
              Expanded(
                child: GestureDetector(
                  onTap: onSearchTap,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xD91E1E23), // rgba(30,30,35,0.85)
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: const Color(0x1AFFFFFF), // rgba(255,255,255,0.1)
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search,
                              size: 15,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Search friends...',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Close button
              GestureDetector(
                onTap: onCloseTap,
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xE61E1E23), // rgba(30,30,35,0.9)
                        border: Border.all(
                          color: const Color(0x24FFFFFF), // rgba(255,255,255,0.14)
                        ),
                      ),
                      child: Icon(
                        Icons.close,
                        size: 15,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
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
