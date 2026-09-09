import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'settings_group.dart';

/// Consent and support export are independent of call availability.
class CallDiagnosticsSettingsSection extends StatelessWidget {
  const CallDiagnosticsSettingsSection({
    super.key,
    required this.enabled,
    required this.setEnabled,
    required this.exportPreview,
    required this.clear,
    this.status,
    this.title,
    this.switchLabel,
    this.summary,
    this.details,
    this.supportCodes = false,
  });

  final ValueListenable<bool> enabled;
  final Future<void> Function(bool) setEnabled;
  final Future<String> Function() exportPreview;
  final Future<void> Function() clear;
  final Future<Map<String, Object?>> Function()? status;
  final String? title;
  final String? switchLabel;
  final String? summary;
  final String? details;
  final bool supportCodes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ValueListenableBuilder<bool>(
      valueListenable: enabled,
      builder: (context, sharing, _) => SettingsGroupCard(
        label: l10n.settings_diagnostics_section,
        children: <Widget>[
          SettingsListRow(
            icon: Icons.support_agent_outlined,
            label: title ?? l10n.settings_call_diagnostics_title,
            value: sharing
                ? l10n.settings_diagnostics_sharing_on
                : l10n.settings_diagnostics_off,
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => _CallDiagnosticsSheet(
                enabled: enabled,
                setEnabled: setEnabled,
                exportPreview: exportPreview,
                clear: clear,
                status: status,
                title: title ?? l10n.settings_call_diagnostics_title,
                switchLabel:
                    switchLabel ?? l10n.settings_call_diagnostics_switch,
                summary: summary ?? l10n.settings_call_diagnostics_summary,
                details: details ?? l10n.settings_call_diagnostics_details,
                supportCodes: supportCodes,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _DiagnosticsMessage {
  statusUnavailable,
  updateFailed,
  supportCodeCopied,
  reportCopied,
  cleared,
}

class _CallDiagnosticsSheet extends StatefulWidget {
  const _CallDiagnosticsSheet({
    required this.enabled,
    required this.setEnabled,
    required this.exportPreview,
    required this.clear,
    required this.status,
    required this.title,
    required this.switchLabel,
    required this.summary,
    required this.details,
    required this.supportCodes,
  });
  final ValueListenable<bool> enabled;
  final Future<void> Function(bool) setEnabled;
  final Future<String> Function() exportPreview;
  final Future<void> Function() clear;
  final Future<Map<String, Object?>> Function()? status;
  final String title;
  final String switchLabel;
  final String summary;
  final String details;
  final bool supportCodes;

  @override
  State<_CallDiagnosticsSheet> createState() => _CallDiagnosticsSheetState();
}

class _CallDiagnosticsSheetState extends State<_CallDiagnosticsSheet> {
  bool _busy = false;
  String? _preview;
  _DiagnosticsMessage? _message;
  Map<String, Object?>? _status;
  Timer? _statusTimer;
  bool _readingStatus = false;

  @override
  void initState() {
    super.initState();
    if (widget.status != null) {
      unawaited(_refreshStatus());
      _statusTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_refreshStatus()),
      );
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    final read = widget.status;
    if (read == null || _readingStatus) return;
    _readingStatus = true;
    try {
      final value = await read();
      if (mounted) setState(() => _status = value);
    } catch (_) {
      if (mounted) {
        setState(() => _message = _DiagnosticsMessage.statusUnavailable);
      }
    } finally {
      _readingStatus = false;
    }
  }

  Widget _statusDetails(Map<String, Object?> status) {
    final l10n = AppLocalizations.of(context)!;
    final sharing = status['enabled'] == true;
    final pending = status['consentPending'] == true;
    final healthy = status['storageHealthy'] != false;
    final queued = status['queuedEvents'];
    final dropped = status['droppedEvents'];
    final uploadedAt = status['lastUploadAtMs'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          !healthy
              ? l10n.settings_diagnostics_storage_failed
              : pending
              ? sharing
                    ? l10n.settings_diagnostics_setup_pending
                    : l10n.settings_diagnostics_disable_pending
              : sharing
              ? l10n.settings_diagnostics_ready
              : l10n.settings_diagnostics_disabled,
        ),
        if (queued is int)
          Text(l10n.settings_diagnostics_queued_events(queued)),
        if (uploadedAt is int && uploadedAt > 0)
          Text(
            l10n.settings_diagnostics_last_upload(
              DateTime.fromMillisecondsSinceEpoch(uploadedAt).toLocal(),
              DateTime.fromMillisecondsSinceEpoch(uploadedAt).toLocal(),
            ),
          ),
        if (dropped is int && dropped > 0)
          Text(l10n.settings_diagnostics_dropped_events(dropped)),
        if (sharing &&
            !pending &&
            status['lastError'] is String &&
            status['lastError'] != 'none')
          Text(l10n.settings_diagnostics_retry_pending),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => _message = _DiagnosticsMessage.updateFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refreshStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(widget.summary),
              const SizedBox(height: 8),
              Text(widget.details),
              const SizedBox(height: 8),
              Text(l10n.settings_diagnostics_retention(7, 14)),
              ValueListenableBuilder<bool>(
                valueListenable: widget.enabled,
                builder: (_, value, _) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(widget.switchLabel),
                  value: value,
                  onChanged: _busy
                      ? null
                      : (next) => _run(() => widget.setEnabled(next)),
                ),
              ),
              if (_status case final status?) _statusDetails(status),
              if (widget.supportCodes && _status?['supportCode'] is String)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await Clipboard.setData(
                            ClipboardData(
                              text: _status!['supportCode']! as String,
                            ),
                          );
                          if (mounted) {
                            setState(
                              () => _message =
                                  _DiagnosticsMessage.supportCodeCopied,
                            );
                          }
                        }),
                  child: Text(l10n.settings_diagnostics_copy_support_code),
                ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        final preview = await widget.exportPreview();
                        if (mounted) setState(() => _preview = preview);
                      }),
                child: Text(l10n.settings_diagnostics_preview_report),
              ),
              if (_preview case final preview?) ...<Widget>[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: SingleChildScrollView(child: SelectableText(preview)),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await Clipboard.setData(ClipboardData(text: preview));
                          if (mounted) {
                            setState(
                              () => _message = _DiagnosticsMessage.reportCopied,
                            );
                          }
                        }),
                  child: Text(l10n.settings_diagnostics_copy_report),
                ),
              ],
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await widget.setEnabled(false);
                        await widget.clear();
                        if (mounted) {
                          setState(() {
                            _preview = null;
                            _message = _DiagnosticsMessage.cleared;
                          });
                        }
                      }),
                child: Text(l10n.settings_diagnostics_disable_and_clear),
              ),
              if (_message case final message?)
                Text(switch (message) {
                  _DiagnosticsMessage.statusUnavailable =>
                    l10n.settings_diagnostics_status_unavailable,
                  _DiagnosticsMessage.updateFailed =>
                    l10n.settings_diagnostics_update_failed,
                  _DiagnosticsMessage.supportCodeCopied =>
                    l10n.settings_diagnostics_support_code_copied,
                  _DiagnosticsMessage.reportCopied =>
                    l10n.settings_diagnostics_report_copied,
                  _DiagnosticsMessage.cleared =>
                    l10n.settings_diagnostics_cleared,
                }),
            ],
          ),
        ),
      ),
    );
  }
}
