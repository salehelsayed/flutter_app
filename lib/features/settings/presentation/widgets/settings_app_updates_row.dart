import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/update_check/application/update_check_controller.dart';
import 'package:flutter_app/features/update_check/domain/update_check_models.dart';
import 'package:flutter_app/features/update_check/presentation/update_required_gate.dart';
import 'package:flutter_app/features/update_check/presentation/update_store_launcher.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'settings_group.dart';

class SettingsAppUpdatesRow extends StatefulWidget {
  const SettingsAppUpdatesRow({
    super.key,
    this.launchStore = launchUpdateStore,
    this.loadPackageInfo = PackageInfo.fromPlatform,
  });

  final UpdateStoreLauncher launchStore;
  final Future<PackageInfo> Function() loadPackageInfo;

  @override
  State<SettingsAppUpdatesRow> createState() => _SettingsAppUpdatesRowState();
}

class _SettingsAppUpdatesRowState extends State<SettingsAppUpdatesRow> {
  UpdateCheckController? _controller;
  PackageInfo? _packageInfo;
  bool _openingStore = false;
  bool _storeLaunchFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPackageInfo());
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await widget.loadPackageInfo();
      if (mounted) setState(() => _packageInfo = info);
    } catch (_) {
      // Package metadata is optional; it must never hold Settings open.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = UpdateCheckScope.maybeOf(context);
    if (identical(controller, _controller)) return;
    _controller = controller;
    _storeLaunchFailed = false;
    if (controller == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(controller, _controller)) {
        unawaited(controller.refresh());
      }
    });
  }

  Future<void> _openStore() async {
    final controller = _controller;
    if (_openingStore ||
        controller == null ||
        controller.platform == null ||
        controller.availability != UpdateAvailability.available) {
      return;
    }
    setState(() {
      _openingStore = true;
      _storeLaunchFailed = false;
    });
    var opened = false;
    try {
      opened = await widget.launchStore(
        updateStoreUrlForPlatform(controller.platform),
      );
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    setState(() {
      _openingStore = false;
      _storeLaunchFailed = !opened;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.backgroundReadableColors;
    final controller = _controller;
    final availability = controller?.platform == null
        ? UpdateAvailability.unknown
        : controller!.availability;
    final checking = controller?.isChecking ?? false;
    final info = _packageInfo;
    final version =
        info != null &&
            info.version.trim().isNotEmpty &&
            info.buildNumber.trim().isNotEmpty
        ? l10n.update_required_installed_build(
            '${info.version} (${info.buildNumber})',
          )
        : null;
    final canUpdate = availability == UpdateAvailability.available;
    final status = switch (availability) {
      UpdateAvailability.current => l10n.settings_updates_current,
      UpdateAvailability.unknown =>
        checking
            ? l10n.settings_updates_checking
            : l10n.settings_updates_unknown,
      UpdateAvailability.available => null,
    };

    return Column(
      key: const ValueKey('settings-row-app-updates'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsListRow(
          icon: Icons.system_update_outlined,
          label: l10n.settings_app_updates,
          subtitle: version,
          subtitleMaxLines: null,
          trailing: checking
              ? Semantics(
                  label: l10n.settings_updates_checking,
                  child: const SizedBox.square(
                    dimension: 44,
                    child: Center(
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                )
              : IconButton(
                  key: const ValueKey('settings-updates-refresh'),
                  tooltip: l10n.transport_diagnostics_refresh,
                  color: colors.iconPrimary,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: controller == null
                      ? null
                      : () {
                          setState(() => _storeLaunchFailed = false);
                          unawaited(controller.refresh(force: true));
                        },
                  icon: const Icon(Icons.refresh, size: 20),
                ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 40,
            end: 14,
            bottom: 8,
          ),
          child: canUpdate
              ? TextButton(
                  key: const ValueKey('settings-updates-update'),
                  onPressed: _openingStore ? null : _openStore,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.accent,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  child: Text(l10n.update_required_button),
                )
              : Text(
                  status!,
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
        ),
        if (canUpdate && _storeLaunchFailed)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 40,
              end: 14,
              bottom: 8,
            ),
            child: Text(
              l10n.update_required_store_failed,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
