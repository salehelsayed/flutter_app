import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../domain/update_check_models.dart';
import 'update_copy.dart';
import 'update_required_gate.dart';
import 'update_store_launcher.dart';

/// The SE-41 soft banner (T2b, O6): a dismissible floating card at the top of
/// the home screen (Orbit, or the first-time screen while the circle is empty).
///
/// It shows only for a soft decision. A dismissal holds for that latestBuild
/// and the banner returns for a higher one. The child keeps the same place in
/// the tree whether or not the banner shows, so Orbit keeps its state.
class UpdateAvailableBannerHost extends StatelessWidget {
  const UpdateAvailableBannerHost({
    super.key,
    required this.child,
    this.launchStore = launchUpdateStore,
  });

  final Widget child;
  final UpdateStoreLauncher launchStore;

  @override
  Widget build(BuildContext context) {
    final controller = UpdateCheckScope.maybeOf(context);
    final decision = controller?.value;
    final soft = decision is UpdateDecisionSoft ? decision : null;
    return Column(
      children: <Widget>[
        if (controller != null && soft != null)
          UpdateAvailableBanner(
            decision: soft,
            onUpdate: () => unawaited(
              launchStore(updateStoreUrlForPlatform(controller.platform)),
            ),
            onDismiss: () => unawaited(controller.dismissSoft()),
          ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            // The banner already sits below the status bar.
            removeTop: soft != null,
            child: child,
          ),
        ),
      ],
    );
  }
}

class UpdateAvailableBanner extends StatelessWidget {
  const UpdateAvailableBanner({
    super.key,
    required this.decision,
    required this.onUpdate,
    required this.onDismiss,
  });

  final UpdateDecisionSoft decision;
  final VoidCallback onUpdate;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // A floating card in the Orbit pill style: a dark translucent surface with
    // a thin green border. White text on it, and black on the green Update
    // pill, both pass WCAG AA (white on primaryAccent would not).
    return SafeArea(
      key: const ValueKey('update-available-banner'),
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: DecoratedBox(
          key: const ValueKey('update-available-banner-card'),
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primaryAccent.withValues(alpha: 0.7),
              width: 0.8,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 4, 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    updateAvailableMessage(l10n, decision.reasonCode),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('update-available-banner-update'),
                  onPressed: onUpdate,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryAccent,
                    foregroundColor: AppColors.background,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.padded,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(l10n.update_available_action),
                ),
                IconButton(
                  key: const ValueKey('update-available-banner-dismiss'),
                  tooltip: l10n.update_available_dismiss,
                  visualDensity: VisualDensity.compact,
                  onPressed: onDismiss,
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
