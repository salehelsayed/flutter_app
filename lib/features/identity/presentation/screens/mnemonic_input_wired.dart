import 'package:flutter/material.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/identity/application/restore_identity_use_case.dart';
import 'package:flutter_app/features/identity/presentation/screens/mnemonic_input_screen.dart';

class MnemonicInputWired extends StatelessWidget {
  final IdentityRepository repository;
  final Future<Map<String, dynamic>> Function(String mnemonic) callIdentityRestore;
  final Future<Map<String, dynamic>> Function() callMlKemKeygen;
  final VoidCallback onNavigateToMain;
  final SecureKeyStore? secureKeyStore;
  final ContactRepository? contactRepo;

  /// Optional — only used to surface the honest "no groups hydrated yet" notice
  /// after restore (A4 of the multi-device-honesty proposal). Absent in test
  /// harnesses, in which case the notice is simply skipped.
  final GroupRepository? groupRepo;

  const MnemonicInputWired({
    super.key,
    required this.repository,
    required this.callIdentityRestore,
    required this.callMlKemKeygen,
    required this.onNavigateToMain,
    this.secureKeyStore,
    this.contactRepo,
    this.groupRepo,
  });

  @override
  Widget build(BuildContext context) {
    return MnemonicInputScreen(
      onRestorePressed: (mnemonic) => _handleRestorePressed(context, mnemonic),
    );
  }

  Future<void> _handleRestorePressed(BuildContext context, String mnemonic) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_BTN_RESTORE_CLICK',
      details: {},
    );

    final result = await restoreIdentityFromMnemonic(
      input: mnemonic,
      callRestore: callIdentityRestore,
      callMlKemKeygen: callMlKemKeygen,
      repo: repository,
      secureKeyStore: secureKeyStore,
      contactRepo: contactRepo,
    );

    if (!context.mounted) return;

    switch (result) {
      case RestoreIdentityResult.success:
        emitFlowEvent(
          layer: 'FL',
          event: 'ID_NAV_MAIN_AFTER_RESTORE',
          details: {},
        );
        // A4 (multi-device honesty): restore hydrates only the identity row — it
        // does NOT pull this user's groups, rosters, or keys, and there is no
        // second-device group sync yet. If restore lands on a device with zero
        // local groups, say so once instead of showing a silent empty list.
        await _maybeShowGroupsDeviceLocalNotice(context);
        if (!context.mounted) return;
        onNavigateToMain();
        break;

      case RestoreIdentityResult.invalidMnemonicFormat:
        emitFlowEvent(
          layer: 'FL',
          event: 'ID_RESTORE_VALIDATION_MESSAGE_SHOWN',
          details: {'errorCode': 'invalidMnemonicFormat'},
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.mnemonic_error_12),
            backgroundColor: Colors.red,
          ),
        );
        break;

      case RestoreIdentityResult.invalidMnemonicCore:
        emitFlowEvent(
          layer: 'FL',
          event: 'ID_RESTORE_VALIDATION_MESSAGE_SHOWN',
          details: {'errorCode': 'invalidMnemonicCore'},
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.mnemonic_error_invalid),
            backgroundColor: Colors.red,
          ),
        );
        break;

      case RestoreIdentityResult.coreLibError:
      case RestoreIdentityResult.dbError:
        emitFlowEvent(
          layer: 'FL',
          event: 'ID_RESTORE_ERROR_SHOWN',
          details: {'errorCode': result.name},
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.mnemonic_error_generic),
            backgroundColor: Colors.red,
          ),
        );
        break;
    }
  }

  /// A4: surface a one-time, non-blocking notice when a freshly restored device
  /// has no local groups, so the user understands the empty group list is the
  /// (current) device-local reality rather than a bug. No-op when [groupRepo] is
  /// absent (test harnesses), when groups already exist locally, or if the
  /// lookup fails — this advisory must never block restore. Shown via the
  /// app-level [ScaffoldMessenger] so it survives [onNavigateToMain].
  Future<void> _maybeShowGroupsDeviceLocalNotice(BuildContext context) async {
    final repo = groupRepo;
    if (repo == null) return;
    final List<Object?> groups;
    try {
      groups = await repo.getAllGroups();
    } catch (_) {
      return;
    }
    if (groups.isNotEmpty) return;
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context);
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_RESTORE_GROUPS_DEVICE_LOCAL_NOTICE',
      details: {},
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n?.restore_groups_device_local_notice ??
              'Your groups will reappear when this device is re-admitted. '
                  "Group history from before this device existed can't be "
                  'recovered.',
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  }
}
