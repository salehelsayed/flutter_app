import 'package:flutter/material.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/press_feedback.dart';

const _actionLabelStyle = TextStyle(
  color: Colors.white,
  fontSize: 13,
  fontWeight: FontWeight.w600,
);

class BlockActionButton extends StatelessWidget {
  const BlockActionButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _SwipeActionButton(
    label: AppLocalizations.of(context)!.orbit_block_action,
    icon: Icons.block,
    color: const Color(0xFF4B5563),
    onTap: onTap,
  );
}

class UnblockActionButton extends StatelessWidget {
  const UnblockActionButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _SwipeActionButton(
    label: AppLocalizations.of(context)!.orbit_unblock_action,
    icon: Icons.replay,
    color: const Color(0xFF0F766E),
    onTap: onTap,
  );
}

class DeleteActionButton extends StatelessWidget {
  const DeleteActionButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _SwipeActionButton(
    label: AppLocalizations.of(context)!.orbit_delete_action,
    icon: Icons.delete_outline,
    color: const Color(0xFFB91C1C),
    onTap: onTap,
  );
}

/// The confirmation for leaving an active group differs from deleting it.
class LeaveActionButton extends StatelessWidget {
  const LeaveActionButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _SwipeActionButton(
    label: AppLocalizations.of(context)!.orbit_leave_action,
    icon: Icons.logout,
    color: const Color(0xFFB91C1C),
    onTap: onTap,
  );
}

class ArchiveActionButton extends StatelessWidget {
  const ArchiveActionButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _SwipeActionButton(
    label: AppLocalizations.of(context)!.orbit_archive_action,
    icon: Icons.archive_outlined,
    color: const Color(0xFF92400E),
    onTap: onTap,
  );
}

class _SwipeActionButton extends StatelessWidget {
  const _SwipeActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(height: 2),
                Flexible(
                  child: ExcludeSemantics(
                    child: Text(
                      label,
                      style: _actionLabelStyle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).withPressFeedback(),
  );
}

class UnarchiveActionButton extends StatelessWidget {
  const UnarchiveActionButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: const Color(0xFF0F766E),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.unarchive_outlined, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                AppLocalizations.of(context)!.orbit_unarchive_action,
                style: _actionLabelStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ).withPressFeedback();
  }
}
