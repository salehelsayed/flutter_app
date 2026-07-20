import 'package:flutter/material.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

enum GroupExitPromotionUiResult { readyToLeave, pendingSync, failed }

enum _GroupExitSheetStage { choices, candidates, pendingSync, readyToLeave }

/// Presentation-only recovery guidance for a sole admin. All repository,
/// signing, retry, leave, and dissolve work stays behind the callbacks.
class GroupExitRecoverySheet extends StatefulWidget {
  const GroupExitRecoverySheet({
    super.key,
    required this.groupName,
    required this.candidates,
    required this.pendingRoleSync,
    required this.onPromote,
    required this.onRetryPendingSync,
    required this.onContinueLeave,
    required this.onDissolve,
  });

  final String groupName;
  final List<GroupMember> candidates;
  final bool pendingRoleSync;
  final Future<GroupExitPromotionUiResult> Function(GroupMember candidate)
  onPromote;
  final Future<bool> Function() onRetryPendingSync;
  final Future<bool> Function() onContinueLeave;
  final Future<bool> Function() onDissolve;

  @override
  State<GroupExitRecoverySheet> createState() => _GroupExitRecoverySheetState();
}

class _GroupExitRecoverySheetState extends State<GroupExitRecoverySheet> {
  late _GroupExitSheetStage _stage;
  GroupMember? _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _stage = widget.pendingRoleSync
        ? _GroupExitSheetStage.pendingSync
        : _GroupExitSheetStage.choices;
  }

  void _close() {
    if (_busy) return;
    Navigator.of(context).pop();
  }

  void _goBack() {
    if (_busy) return;
    if (_stage == _GroupExitSheetStage.candidates) {
      setState(() => _stage = _GroupExitSheetStage.choices);
      return;
    }
    _close();
  }

  Future<void> _promote() async {
    final selected = _selected;
    if (_busy || selected == null) return;
    setState(() => _busy = true);
    GroupExitPromotionUiResult result;
    try {
      result = await widget.onPromote(selected);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _stage = switch (result) {
        GroupExitPromotionUiResult.readyToLeave =>
          _GroupExitSheetStage.readyToLeave,
        GroupExitPromotionUiResult.pendingSync =>
          _GroupExitSheetStage.pendingSync,
        GroupExitPromotionUiResult.failed => _GroupExitSheetStage.candidates,
      };
    });
  }

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    bool ready;
    try {
      ready = await widget.onRetryPendingSync();
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ready) _stage = _GroupExitSheetStage.readyToLeave;
    });
  }

  Future<void> _continueLeave() async {
    if (_busy) return;
    setState(() => _busy = true);
    bool closed;
    try {
      closed = await widget.onContinueLeave();
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    if (closed) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = false);
  }

  Future<void> _dissolve() async {
    if (_busy) return;
    setState(() => _busy = true);
    bool closed;
    try {
      closed = await widget.onDissolve();
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    if (closed) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final canPop = !_busy && _stage != _GroupExitSheetStage.candidates;
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _goBack();
      },
      child: SafeArea(
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: IconButton(
                    key: const ValueKey('group-exit-close'),
                    tooltip: AppLocalizations.of(
                      context,
                    )!.group_exit_keep_and_close_semantics,
                    onPressed: _busy ? null : _close,
                    icon: const Icon(Icons.close),
                  ),
                ),
                ..._buildStage(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (_stage) {
      case _GroupExitSheetStage.choices:
        return [
          Text(
            l10n.group_exit_only_admin_title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(l10n.group_exit_only_admin_body(widget.groupName)),
          const SizedBox(height: 24),
          if (widget.candidates.isNotEmpty) ...[
            OutlinedButton.icon(
              key: const ValueKey('group-exit-choose-admin'),
              onPressed: _busy
                  ? null
                  : () => setState(
                      () => _stage = _GroupExitSheetStage.candidates,
                    ),
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: Text(l10n.group_exit_choose_admin),
            ),
            const SizedBox(height: 8),
            Text(l10n.group_exit_choose_admin_body),
          ] else
            Text(
              l10n.group_exit_no_eligible_successor,
              key: const ValueKey('group-exit-no-candidate'),
            ),
          const SizedBox(height: 20),
          FilledButton.tonalIcon(
            key: const ValueKey('group-exit-dissolve'),
            onPressed: _busy ? null : _dissolve,
            icon: const Icon(Icons.group_off_outlined),
            label: Text(l10n.group_exit_dissolve_for_everyone),
          ),
          TextButton(
            key: const ValueKey('group-exit-keep'),
            onPressed: _busy ? null : _close,
            child: Text(l10n.group_exit_keep_group),
          ),
        ];
      case _GroupExitSheetStage.candidates:
        return [
          Text(
            l10n.group_exit_choose_member,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          RadioGroup<String>(
            groupValue: _selected?.peerId,
            onChanged: (peerId) {
              if (_busy || peerId == null) return;
              final selected = widget.candidates.firstWhere(
                (candidate) => candidate.peerId == peerId,
              );
              setState(() => _selected = selected);
            },
            child: Column(
              children: [
                for (final candidate in widget.candidates)
                  RadioListTile<String>(
                    key: ValueKey('group-exit-candidate-${candidate.peerId}'),
                    value: candidate.peerId,
                    enabled: !_busy,
                    title: Text(
                      candidate.username?.trim().isNotEmpty == true
                          ? candidate.username!.trim()
                          : candidate.peerId,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('group-exit-promote'),
            onPressed: _busy || _selected == null ? null : _promote,
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.group_info_make_admin_action),
          ),
          TextButton(
            onPressed: _busy ? null : _goBack,
            child: Text(l10n.btn_cancel),
          ),
        ];
      case _GroupExitSheetStage.pendingSync:
        return [
          Text(
            l10n.group_exit_admin_sync_pending_title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(l10n.group_exit_admin_sync_pending_body),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const ValueKey('group-exit-retry-sync'),
            onPressed: _busy ? null : _retry,
            icon: const Icon(Icons.sync),
            label: Text(l10n.btn_retry),
          ),
          TextButton(
            onPressed: _busy ? null : _close,
            child: Text(l10n.group_exit_stay_in_group),
          ),
        ];
      case _GroupExitSheetStage.readyToLeave:
        return [
          Text(
            l10n.group_exit_choose_admin,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(l10n.group_exit_choose_admin_body),
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('group-exit-continue'),
            onPressed: _busy ? null : _continueLeave,
            child: Text(l10n.group_exit_continue_to_leave),
          ),
          TextButton(
            key: const ValueKey('group-exit-stay'),
            onPressed: _busy ? null : _close,
            child: Text(l10n.group_exit_stay_in_group),
          ),
        ];
    }
  }
}
