import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../domain/update_check_models.dart';
import 'update_copy.dart';
import 'update_required_gate.dart';
import 'update_store_launcher.dart';

/// The SE-41 soft banner (T2b, O6): a thin, dismissible strip at the top of
/// the Orbit screen.
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      key: const ValueKey('update-available-banner'),
      color: scheme.secondaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  updateAvailableMessage(l10n, decision.reasonCode),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('update-available-banner-update'),
                onPressed: onUpdate,
                child: Text(l10n.update_available_action),
              ),
              IconButton(
                key: const ValueKey('update-available-banner-dismiss'),
                tooltip: l10n.update_available_dismiss,
                visualDensity: VisualDensity.compact,
                onPressed: onDismiss,
                icon: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
