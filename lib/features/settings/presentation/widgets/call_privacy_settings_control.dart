import 'package:flutter/material.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/settings/application/call_privacy_preference_use_cases.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'settings_group.dart';

class CallPrivacySettingsControl extends StatefulWidget {
  const CallPrivacySettingsControl({
    super.key,
    required this.secureKeyStore,
    required this.forceRelay,
  });

  final SecureKeyStore secureKeyStore;
  final bool forceRelay;

  @override
  State<CallPrivacySettingsControl> createState() =>
      _CallPrivacySettingsControlState();
}

class _CallPrivacySettingsControlState
    extends State<CallPrivacySettingsControl> {
  bool? _alwaysRelay;
  bool _busy = true;
  bool _loadFailed = false;
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final value = await loadAlwaysRelayCallsPreference(
        secureKeyStore: widget.secureKeyStore,
      );
      if (!mounted) return;
      setState(() {
        _alwaysRelay = value;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _alwaysRelay = null;
        _loadFailed = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(bool value) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _saveFailed = false;
    });
    try {
      await saveAlwaysRelayCallsPreference(
        secureKeyStore: widget.secureKeyStore,
        alwaysRelay: value,
      );
      if (mounted) setState(() => _alwaysRelay = value);
    } catch (_) {
      if (mounted) setState(() => _saveFailed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.backgroundReadableColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsListRow(
            icon: Icons.shield_outlined,
            label: l10n.settings_always_relay_calls,
            trailing: Switch.adaptive(
              key: const ValueKey('settings-always-relay-calls-switch'),
              value: _alwaysRelay ?? true,
              onChanged: _busy || _alwaysRelay == null ? null : _save,
            ),
          ),
          Text(
            l10n.settings_call_privacy_description,
            style: TextStyle(color: colors.textSecondary),
          ),
          if (widget.forceRelay) ...[
            const SizedBox(height: 12),
            Text(l10n.settings_call_privacy_rollout),
          ],
          if (_loadFailed) ...[
            const SizedBox(height: 12),
            Text(l10n.settings_call_privacy_load_failed),
            TextButton(
              onPressed: _busy ? null : _load,
              child: Text(l10n.btn_retry),
            ),
          ],
          if (_saveFailed) ...[
            const SizedBox(height: 12),
            Text(l10n.settings_call_privacy_save_failed),
          ],
        ],
      ),
    );
  }
}
