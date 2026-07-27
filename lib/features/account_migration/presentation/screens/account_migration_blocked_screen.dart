import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

class AccountMigrationBlockedScreen extends StatefulWidget {
  final AccountMigrationAuthorityRecord? record;
  final Future<void> Function()? onEraseAccount;

  const AccountMigrationBlockedScreen({
    super.key,
    this.record,
    this.onEraseAccount,
  });

  @override
  State<AccountMigrationBlockedScreen> createState() =>
      _AccountMigrationBlockedScreenState();
}

class _AccountMigrationBlockedScreenState
    extends State<AccountMigrationBlockedScreen> {
  bool _isErasing = false;

  Future<void> _confirmErase() async {
    final erase = widget.onEraseAccount;
    if (erase == null || _isErasing) return;

    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        title: Text(
          l10n.account_migration_erase_confirm_title,
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          l10n.account_migration_erase_confirm_body,
          style: const TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.account_migration_cancel),
          ),
          FilledButton(
            key: const ValueKey('account-migration-erase-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryAccent,
              foregroundColor: Colors.black,
            ),
            child: Text(l10n.account_migration_erase_local_data),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isErasing = true);
    try {
      await erase();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.account_migration_erased_snackbar)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.account_migration_erase_failed(e.toString())),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isErasing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final record = widget.record;
    final (title, message) = switch (record) {
      final authority when authority?.isFailClosed == true => (
        l10n.account_migration_blocked_title,
        l10n.account_migration_blocked_message,
      ),
      final authority
          when authority?.state ==
              AccountMigrationAuthorityState
                  .migrationVerifiedWaitingForCutover =>
        (
          l10n.account_migration_unfinished_move_title,
          l10n.account_migration_unfinished_move_message,
        ),
      _ => (
        l10n.account_migration_blocked_title,
        l10n.account_migration_blocked_message,
      ),
    };
    final showEraseAction =
        record != null &&
        !record.isFailClosed &&
        !record.allowsNormalStartup &&
        record.state !=
            AccountMigrationAuthorityState.migrationVerifiedWaitingForCutover;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.phonelink_lock_outlined,
                  size: 56,
                  color: AppColors.primaryAccent,
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  key: const ValueKey('account-migration-blocked-title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  key: const ValueKey('account-migration-blocked-message'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
                if (showEraseAction) ...[
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const ValueKey('account-migration-erase-action'),
                    onPressed: widget.onEraseAccount == null || _isErasing
                        ? null
                        : _confirmErase,
                    icon: _isErasing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline, size: 18),
                    label: Text(l10n.account_migration_erase_local_data),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryAccent,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(46),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
