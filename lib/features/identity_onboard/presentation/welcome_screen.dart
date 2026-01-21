import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mknoon_chat/services/logging_service.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final telemetry = LoggingService.getLogger('IdentityFlow');
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Welcome to MKNoon', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text('Create a new identity or restore from seed phrase.',
                  style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  telemetry.logEvent('EV_WELCOME_CREATE_TAPPED', {
                    'timestamp': DateTime.now().toIso8601String(),
                  });
                  context.go('/identity/create', extra: {'onboarding': true});
                },
                child: const Text('Create New Identity'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.go('/identity/restore', extra: {'onboarding': true}),
                child: const Text('Restore Identity'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
