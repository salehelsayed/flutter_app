import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';

class AccountMigrationBlockedScreen extends StatefulWidget {
  final Future<void> Function()? onEraseAccount;

  const AccountMigrationBlockedScreen({super.key, this.onEraseAccount});

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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        title: const Text(
          'Erase this device?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'This only clears local account data on this phone after the account has moved. It will not move anything back.',
          style: TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('account-migration-erase-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('Erase local data'),
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
        const SnackBar(content: Text('Local account data erased')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not erase local account data: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isErasing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                const Text(
                  'Account moved to another phone',
                  key: ValueKey('account-migration-blocked-title'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'This phone is blocked from opening the account after migration. Erase the local copy only when you are sure the new phone works.',
                  key: ValueKey('account-migration-blocked-message'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
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
                  label: Text(_isErasing ? 'Erasing...' : 'Erase local data'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryAccent,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(46),
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
