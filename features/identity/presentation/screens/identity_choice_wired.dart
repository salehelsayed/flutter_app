import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/identity/application/generate_identity_use_case.dart';
import 'package:flutter_app/features/identity/presentation/screens/identity_choice_screen.dart';
import 'package:flutter_app/features/identity/presentation/screens/mnemonic_input_screen.dart';

class IdentityChoiceWired extends StatefulWidget {
  final IdentityRepository repository;
  final Future<Map<String, dynamic>> Function() callJsIdentityGenerate;
  final Future<Map<String, dynamic>> Function(String mnemonic) callJsIdentityRestore;
  final VoidCallback onNavigateToMain;

  const IdentityChoiceWired({
    super.key,
    required this.repository,
    required this.callJsIdentityGenerate,
    required this.callJsIdentityRestore,
    required this.onNavigateToMain,
  });

  @override
  State<IdentityChoiceWired> createState() => _IdentityChoiceWiredState();
}

class _IdentityChoiceWiredState extends State<IdentityChoiceWired> {
  bool _isLoading = false;

  Future<void> _handleNewHere() async {
    if (_isLoading) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'ID_BTN_GENERATE_CLICK',
      details: {},
    );

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await generateNewIdentity(
        callJsGenerate: widget.callJsIdentityGenerate,
        repo: widget.repository,
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      if (result == GenerateIdentityResult.success) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ID_NAV_MAIN_AFTER_GENERATE',
          details: {},
        );
        widget.onNavigateToMain();
      } else {
        final errorMessage = result == GenerateIdentityResult.coreLibError
            ? 'Failed to generate identity'
            : 'Failed to save identity';
        emitFlowEvent(
          layer: 'FL',
          event: 'ID_GENERATE_ERROR_SHOWN',
          details: {
            'errorCode': result.name,
            'errorMessage': errorMessage,
          },
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      emitFlowEvent(
        layer: 'FL',
        event: 'ID_GENERATE_ERROR_SHOWN',
        details: {
          'errorCode': 'EXCEPTION',
          'errorMessage': e.toString(),
        },
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleLoadKey() {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_BTN_RESTORE_NAVIGATE',
      details: {},
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MnemonicInputScreen(
          onRestorePressed: (mnemonic) async {
            // Restore logic will be handled by FL_XS_13
          },
        ),
      ),
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'ID_NAV_TO_MNEMONIC_SCREEN',
      details: {},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IdentityChoiceScreen(
          onNewHere: _isLoading ? () {} : _handleNewHere,
          onLoadMyKey: _isLoading ? () {} : _handleLoadKey,
        ),
        if (_isLoading)
          Container(
            color: Colors.black26,
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
      ],
    );
  }
}
