import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/identity/application/restore_identity_use_case.dart';
import 'package:flutter_app/features/identity/presentation/screens/mnemonic_input_screen.dart';

class MnemonicInputWired extends StatelessWidget {
  final IdentityRepository repository;
  final Future<Map<String, dynamic>> Function(String mnemonic) callJsIdentityRestore;
  final VoidCallback onNavigateToMain;

  const MnemonicInputWired({
    super.key,
    required this.repository,
    required this.callJsIdentityRestore,
    required this.onNavigateToMain,
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
      callJsRestore: callJsIdentityRestore,
      repo: repository,
    );

    if (!context.mounted) return;

    switch (result) {
      case RestoreIdentityResult.success:
        emitFlowEvent(
          layer: 'FL',
          event: 'ID_NAV_MAIN_AFTER_RESTORE',
          details: {},
        );
        onNavigateToMain();
        break;

      case RestoreIdentityResult.invalidMnemonicFormat:
        emitFlowEvent(
          layer: 'FL',
          event: 'ID_RESTORE_VALIDATION_MESSAGE_SHOWN',
          details: {'errorCode': 'invalidMnemonicFormat'},
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter exactly 12 words'),
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
          const SnackBar(
            content: Text('Invalid recovery phrase'),
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
          const SnackBar(
            content: Text('An error occurred. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
        break;
    }
  }
}
