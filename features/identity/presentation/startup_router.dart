import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/identity/application/startup_decision.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/identity/presentation/screens/identity_choice_wired.dart';

/// A simple placeholder for the main app screen.
///
/// This screen is displayed when an identity already exists in the database.
/// It serves as the entry point to the main application functionality.
class MainAppScreen extends StatelessWidget {
  const MainAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Main App'),
      ),
      body: const Center(
        child: Text('Welcome! Identity loaded.'),
      ),
    );
  }
}

/// Router widget that handles app startup navigation.
///
/// This widget is displayed at app startup and determines whether to
/// navigate to the main app (if an identity exists) or to the identity
/// onboarding flow (if no identity exists).
///
/// The widget shows a loading indicator while checking for an existing
/// identity, then uses pushReplacement to navigate to the appropriate
/// screen, ensuring a clean navigation stack.
class StartupRouter extends StatefulWidget {
  /// The repository used to check for existing identity.
  final IdentityRepository repository;

  /// The bridge instance for identity operations.
  final Bridge bridge;

  const StartupRouter({
    super.key,
    required this.repository,
    required this.bridge,
  });

  @override
  State<StartupRouter> createState() => _StartupRouterState();
}

class _StartupRouterState extends State<StartupRouter> {
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _routeBasedOnIdentity();
  }

  Future<void> _routeBasedOnIdentity() async {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_STARTUP_FLOW_BEGIN',
      details: {},
    );

    try {
      final decision = await decideStartupRoute(widget.repository);

      if (!mounted) return;

      switch (decision) {
        case StartupDecision.hasIdentity:
          emitFlowEvent(
            layer: 'FL',
            event: 'ID_STARTUP_ROUTE_MAIN',
            details: {},
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainAppScreen()),
          );
          break;
        case StartupDecision.needsIdentity:
          emitFlowEvent(
            layer: 'FL',
            event: 'ID_STARTUP_ROUTE_ONBOARDING',
            details: {},
          );
          // Capture bridge and repository locally to avoid widget reference issues
          final bridge = widget.bridge;
          final repository = widget.repository;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (routeContext) => IdentityChoiceWired(
                repository: repository,
                callIdentityGenerate: () => callIdentityGenerate(bridge),
                callIdentityRestore: (mnemonic) =>
                    callIdentityRestore(bridge, mnemonic),
                onNavigateToMain: () {
                  // Use the route's context for navigation
                  Navigator.of(routeContext).pushReplacement(
                    MaterialPageRoute(builder: (_) => const MainAppScreen()),
                  );
                },
              ),
            ),
          );
          break;
      }
    } catch (e) {
      if (!mounted) return;

      emitFlowEvent(
        layer: 'FL',
        event: 'ID_STARTUP_ROUTE_ERROR',
        details: {'error': e.toString()},
      );

      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _retry() async {
    setState(() {
      _hasError = false;
      _errorMessage = '';
    });
    await _routeBasedOnIdentity();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Failed to initialize',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _retry,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(
              Icons.lock,
              size: 64,
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading...'),
          ],
        ),
      ),
    );
  }
}
