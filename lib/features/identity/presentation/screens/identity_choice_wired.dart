import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/identity/application/generate_identity_use_case.dart';
import 'package:flutter_app/features/identity/presentation/screens/identity_choice_screen.dart';
import 'package:flutter_app/features/identity/presentation/screens/mnemonic_input_wired.dart';
import 'package:flutter_app/features/identity/presentation/widgets/identity_loading_card.dart';

class IdentityChoiceWired extends StatefulWidget {
  final IdentityRepository repository;
  final Future<Map<String, dynamic>> Function() callIdentityGenerate;
  final Future<Map<String, dynamic>> Function(String mnemonic) callIdentityRestore;
  final Future<Map<String, dynamic>> Function() callMlKemKeygen;
  final VoidCallback onNavigateToMain;

  const IdentityChoiceWired({
    super.key,
    required this.repository,
    required this.callIdentityGenerate,
    required this.callIdentityRestore,
    required this.callMlKemKeygen,
    required this.onNavigateToMain,
  });

  @override
  State<IdentityChoiceWired> createState() => _IdentityChoiceWiredState();
}

class _IdentityChoiceWiredState extends State<IdentityChoiceWired> {
  String? _loadingStage;

  Future<void> _handleNewHere() async {
    if (_loadingStage != null) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'ID_BTN_GENERATE_CLICK',
      details: {},
    );

    setState(() {
      _loadingStage = 'generating_keys';
    });

    // Frame yield: let the loading UI paint before starting heavy crypto
    await Future<void>.delayed(Duration.zero);

    try {
      final result = await generateNewIdentity(
        callGenerate: widget.callIdentityGenerate,
        callMlKemKeygen: widget.callMlKemKeygen,
        repo: widget.repository,
        onProgress: (stage) {
          if (mounted) setState(() { _loadingStage = stage; });
        },
      );

      if (!mounted) return;

      if (result == GenerateIdentityResult.success) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ID_NAV_MAIN_AFTER_GENERATE',
          details: {},
        );
        widget.onNavigateToMain();
        return;
      }

      setState(() {
        _loadingStage = null;
      });

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
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingStage = null;
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
        builder: (routeContext) => MnemonicInputWired(
          repository: widget.repository,
          callIdentityRestore: widget.callIdentityRestore,
          callMlKemKeygen: widget.callMlKemKeygen,
          onNavigateToMain: () {
            // Pop back to this screen first, then navigate to main
            Navigator.of(routeContext).pop();
            widget.onNavigateToMain();
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
          onNewHere: _loadingStage != null ? () {} : _handleNewHere,
          onLoadMyKey: _loadingStage != null ? () {} : _handleLoadKey,
        ),
        if (_loadingStage != null)
          IdentityLoadingCard(stage: _loadingStage!),
      ],
    );
  }
}
