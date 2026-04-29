import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
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
    final readableColors = context.backgroundReadableColors;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: BoxDecoration(
        color: readableColors.glassSurface,
        border: Border(top: BorderSide(color: readableColors.glassBorder)),
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
                    color: readableColors.inputFill,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: readableColors.inputBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        size: 18,
                        color: readableColors.iconMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          onChanged: onChanged,
                          style: TextStyle(
                            fontSize: 15,
                            color: readableColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: AppLocalizations.of(
                              context,
                            )!.orbit_search,
                            hintStyle: TextStyle(
                              fontSize: 15,
                              color: readableColors.placeholderText,
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
                              color: readableColors.disabledSurface,
                            ),
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: readableColors.iconMuted,
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
                    color: readableColors.surfaceRaised,
                    border: Border.all(color: readableColors.border),
                  ),
                  child: Icon(
                    Icons.close,
                    size: 15,
                    color: readableColors.iconSecondary,
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
