import 'package:flutter/material.dart';

/// Onboarding screen presenting two identity initialization options.
/// 
/// This is a pure layout widget with no business logic.
/// All actions are delegated to the provided callbacks.
class IdentityChoiceScreen extends StatelessWidget {
  /// Callback invoked when user chooses to create a new identity.
  final VoidCallback onNewHere;

  /// Callback invoked when user chooses to restore from mnemonic.
  final VoidCallback onLoadMyKey;

  const IdentityChoiceScreen({
    super.key,
    required this.onNewHere,
    required this.onLoadMyKey,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Text(
                'Welcome',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Generate a new identity or\nrestore from recovery phrase',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 2),
              FilledButton(
                onPressed: onNewHere,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: const Text("I'm new here"),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onLoadMyKey,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: const Text('Load my key'),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}
