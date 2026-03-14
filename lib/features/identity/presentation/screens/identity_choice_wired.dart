import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/identity/application/generate_identity_use_case.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/identity/presentation/navigation/startup_route_transition.dart';
import 'package:flutter_app/features/identity/presentation/screens/identity_choice_screen.dart';
import 'package:flutter_app/features/identity/presentation/screens/identity_progress_screen.dart';
import 'package:flutter_app/features/identity/presentation/screens/mnemonic_input_wired.dart';

class IdentityChoiceWired extends StatefulWidget {
  final IdentityRepository repository;
  final Future<Map<String, dynamic>> Function() callIdentityGenerate;
  final Future<Map<String, dynamic>> Function(String mnemonic)
  callIdentityRestore;
  final Future<Map<String, dynamic>> Function() callMlKemKeygen;
  final Future<void> Function(BuildContext navigationContext) onNavigateToMain;
  final VoidCallback? onProgressRouteFirstFrame;

  const IdentityChoiceWired({
    super.key,
    required this.repository,
    required this.callIdentityGenerate,
    required this.callIdentityRestore,
    required this.callMlKemKeygen,
    required this.onNavigateToMain,
    this.onProgressRouteFirstFrame,
  });

  @override
  State<IdentityChoiceWired> createState() => _IdentityChoiceWiredState();
}

class _IdentityChoiceWiredState extends State<IdentityChoiceWired> {
  final ValueNotifier<String> _progressStage = ValueNotifier<String>(
    'generating_keys',
  );
  bool _isGeneratingIdentity = false;

  @override
  void dispose() {
    _progressStage.dispose();
    super.dispose();
  }

  Future<void> _handleNewHere() async {
    if (_isGeneratingIdentity) return;

    emitFlowEvent(layer: 'FL', event: 'ID_BTN_GENERATE_CLICK', details: {});

    setState(() => _isGeneratingIdentity = true);
    _progressStage.value = 'generating_keys';

    final progressRouteContext = Completer<BuildContext>();
    final progressRouteFuture = Navigator.of(context).push<void>(
      buildStartupReplacementRoute<void>(
        builder: (routeContext) {
          if (!progressRouteContext.isCompleted) {
            progressRouteContext.complete(routeContext);
          }
          return IdentityProgressScreen(
            stageListenable: _progressStage,
            onFirstFrameRendered: widget.onProgressRouteFirstFrame,
          );
        },
      ),
    );

    // Wait for the pushed progress route to finish a frame before starting
    // identity generation so the user sees the handoff immediately.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    try {
      final result = await generateNewIdentity(
        callGenerate: widget.callIdentityGenerate,
        callMlKemKeygen: widget.callMlKemKeygen,
        repo: widget.repository,
        onProgress: (stage) {
          _progressStage.value = stage;
        },
      );

      if (!mounted) return;
      final progressContext = await progressRouteContext.future;

      if (result == GenerateIdentityResult.success) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ID_NAV_MAIN_AFTER_GENERATE',
          details: {},
        );
        await widget.onNavigateToMain(progressContext);
        return;
      }

      final navigator = Navigator.of(progressContext);
      if (navigator.canPop()) {
        navigator.pop();
        await progressRouteFuture;
      }
      if (!mounted) return;
      setState(() => _isGeneratingIdentity = false);

      final errorMessage = result == GenerateIdentityResult.coreLibError
          ? 'Failed to generate identity'
          : 'Failed to save identity';
      emitFlowEvent(
        layer: 'FL',
        event: 'ID_GENERATE_ERROR_SHOWN',
        details: {'errorCode': result.name, 'errorMessage': errorMessage},
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;

      final progressContext = await progressRouteContext.future;
      final navigator = Navigator.of(progressContext);
      if (navigator.canPop()) {
        navigator.pop();
        await progressRouteFuture;
      }
      if (!mounted) return;
      setState(() => _isGeneratingIdentity = false);

      emitFlowEvent(
        layer: 'FL',
        event: 'ID_GENERATE_ERROR_SHOWN',
        details: {'errorCode': 'EXCEPTION', 'errorMessage': e.toString()},
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
    emitFlowEvent(layer: 'FL', event: 'ID_BTN_RESTORE_NAVIGATE', details: {});

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => MnemonicInputWired(
          repository: widget.repository,
          callIdentityRestore: widget.callIdentityRestore,
          callMlKemKeygen: widget.callMlKemKeygen,
          onNavigateToMain: () {
            // Pop back to this screen first, then navigate to main
            Navigator.of(routeContext).pop();
            unawaited(widget.onNavigateToMain(context));
          },
        ),
      ),
    );

    emitFlowEvent(layer: 'FL', event: 'ID_NAV_TO_MNEMONIC_SCREEN', details: {});
  }

  @override
  Widget build(BuildContext context) {
    return IdentityChoiceScreen(
      onNewHere: _isGeneratingIdentity ? null : _handleNewHere,
      onLoadMyKey: _isGeneratingIdentity ? null : _handleLoadKey,
    );
  }
}
