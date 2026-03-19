import 'package:flutter/material.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Bottom-docked search input panel that slides up from the bottom.
///
/// Contains a TextField in a glass input wrapper, clear button, and close button.
/// Uses native keyboard (not simulated).
class OrbitSearchDock extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final void Function(String) onChanged;
  final VoidCallback onClear;
  final VoidCallback onClose;
  final String query;

  const OrbitSearchDock({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
    required this.onClose,
    required this.query,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: const BoxDecoration(
        color: Color(0xFA121216), // rgba(18,18,22,0.98)
        border: Border(
          top: BorderSide(
            color: Color(0x14FFFFFF), // rgba(255,255,255,0.08)
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              // Input wrapper
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0x0FFFFFFF), // rgba(255,255,255,0.06)
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0x1AFFFFFF), // rgba(255,255,255,0.1)
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        size: 18,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          onChanged: onChanged,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.white,
                          ),
                          decoration: InputDecoration(
                            hintText: AppLocalizations.of(context)!.orbit_search,
                            hintStyle: TextStyle(
                              fontSize: 15,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      // Clear button (only when query is non-empty)
                      if (query.isNotEmpty)
                        GestureDetector(
                          onTap: onClear,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Close button
              GestureDetector(
                onTap: onClose,
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
            ],
          ),
        ),
      ),
    );
  }
}
