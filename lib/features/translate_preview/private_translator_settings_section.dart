import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_group.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/features/translate_preview/private_translator_sheet.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// The "Private translator" row in the Preferences card, plus the
/// "Download over mobile data" switch on phones that can run it.
class PrivateTranslatorSettingsSection extends StatelessWidget {
  const PrivateTranslatorSettingsSection({
    super.key,
    required this.controller,
    this.onFreeUpSpace,
  });

  final ModelDeliveryController controller;
  final VoidCallback? onFreeUpSpace;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<ModelDeliveryState>(
        valueListenable: controller.state,
        builder: (context, state, _) {
          final l10n = AppLocalizations.of(context)!;
          void openSheet() => unawaited(
            showPrivateTranslatorSheet(
              context,
              controller: controller,
              onFreeUpSpace: onFreeUpSpace,
            ),
          );
          final (String subtitle, _RowAction? action) = switch (state) {
            ModelUnsupported() => (l10n.translator_settings_unsupported, null),
            ModelNotDownloaded() => (
              l10n.translator_settings_not_downloaded,
              (l10n.translator_get, openSheet),
            ),
            ModelNotEnoughSpace(:final neededBytes) => (
              l10n.translator_sheet_needs(translatorSize(context, neededBytes)),
              (l10n.translator_get, openSheet),
            ),
            ModelDownloading(:final receivedBytes, :final totalBytes) => (
              l10n.translator_settings_downloading(
                translatorAmount(context, receivedBytes, totalBytes),
              ),
              (l10n.translator_pause, () => unawaited(controller.pause())),
            ),
            ModelWaitingForWifi() || ModelPaused() => (
              l10n.translator_settings_paused,
              (l10n.translator_resume, () => unawaited(controller.resume())),
            ),
            ModelFailed() => (
              l10n.translator_settings_failed,
              (l10n.translator_try_again, () => unawaited(controller.retry())),
            ),
            ModelReady(:final sizeBytes) => (
              l10n.translator_settings_ready,
              (
                l10n.translator_remove,
                () => unawaited(_confirmRemove(context, sizeBytes)),
              ),
            ),
          };
          final row = SettingsListRow(
            key: const ValueKey('settings-row-private-translator'),
            icon: Icons.translate,
            label: l10n.translator_settings_title,
            subtitle: subtitle,
            trailing: action == null
                ? null
                : TextButton(
                    onPressed: action.$2,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(action.$1),
                  ),
          );
          if (action == null) return Opacity(opacity: 0.45, child: row);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row,
              if (state is ModelDownloading)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(40, 0, 14, 10),
                  child: LinearProgressIndicator(value: state.percent / 100),
                ),
              Divider(
                height: 1,
                thickness: 1,
                color: context.backgroundReadableColors.divider,
              ),
              ValueListenableBuilder<bool>(
                valueListenable: controller.allowMobileData,
                builder: (context, allow, _) => SettingsListRow(
                  key: const ValueKey('settings-row-translator-mobile-data'),
                  icon: Icons.signal_cellular_alt,
                  label: l10n.translator_settings_mobile_data,
                  trailing: Switch.adaptive(
                    value: allow,
                    onChanged: (next) =>
                        unawaited(controller.setAllowMobileData(next)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          );
        },
      );

  Future<void> _confirmRemove(BuildContext context, int sizeBytes) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.translator_remove_title),
        content: Text(
          l10n.translator_remove_body(translatorSize(context, sizeBytes)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.btn_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.translator_remove),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.remove();
  }
}

typedef _RowAction = (String label, VoidCallback onPressed);
