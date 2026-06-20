import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/theme/glassmorphism.dart';

/// A glassmorphic choice card with icon, title, description, and arrow.
///
/// Set [secondary] to render a quieter, same-width variant (outlined icon
/// frame, smaller title, muted description clamped to two lines, muted
/// chevron). Width is identical to the primary so both cards share one
/// alignment edge with each other, the brand header, and the footer —
/// hierarchy is carried by weight and tone, never by width.
class ChoiceCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  /// When true, renders the subordinate variant described above.
  final bool secondary;

  const ChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.secondary = false,
  });

  @override
  State<ChoiceCard> createState() => _ChoiceCardState();
}

class _ChoiceCardState extends State<ChoiceCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _scaleController.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _scaleController.reverse();
    widget.onTap?.call();
  }

  void _onTapCancel() {
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final isDisabled = widget.onTap == null;
    return GestureDetector(
      onTapDown: isDisabled ? null : _onTapDown,
      onTapUp: isDisabled ? null : _onTapUp,
      onTapCancel: isDisabled ? null : _onTapCancel,
      child: Opacity(
        key: ValueKey('choice-card-opacity-${widget.title}'),
        opacity: isDisabled ? 0.5 : 1.0,
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(scale: _scaleAnimation.value, child: child);
          },
          child: GlassmorphicContainer(
            padding: EdgeInsets.all(widget.secondary ? 16 : 20),
            child: Row(
              children: [
                // Icon — filled tint for primary, outlined frame for secondary.
                Container(
                  width: widget.secondary ? 40 : 48,
                  height: widget.secondary ? 40 : 48,
                  decoration: BoxDecoration(
                    color: widget.secondary
                        ? Colors.transparent
                        : AppColors.primaryAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(
                      widget.secondary ? 10 : 12,
                    ),
                    border: widget.secondary
                        ? Border.all(color: readableColors.border, width: 1)
                        : null,
                  ),
                  child: Icon(
                    widget.icon,
                    color: AppColors.primaryAccent,
                    size: widget.secondary ? 20 : 24,
                  ),
                ),
                SizedBox(width: widget.secondary ? 14 : 16),
                // Title and description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          color: readableColors.textPrimary,
                          fontSize: widget.secondary ? 16 : 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: widget.secondary ? 2 : 4),
                      Text(
                        widget.description,
                        style: TextStyle(
                          color: widget.secondary
                              ? readableColors.textMuted
                              : readableColors.textSecondary,
                          fontSize: widget.secondary ? 13 : 14,
                        ),
                        maxLines: widget.secondary ? 2 : null,
                        overflow: widget.secondary
                            ? TextOverflow.ellipsis
                            : null,
                      ),
                    ],
                  ),
                ),
                // Arrow
                Icon(
                  Icons.arrow_forward_ios,
                  color: widget.secondary
                      ? readableColors.iconMuted
                      : readableColors.iconSecondary,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
