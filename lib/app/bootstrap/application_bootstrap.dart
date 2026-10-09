import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/theme/app_theme.dart';

typedef ApplicationBootstrapFactory = ApplicationBootstrap Function();

abstract interface class ApplicationBootstrap {
  Future<PreparedApplication> prepare();
}

/// A recoverable preparation pause continues the same bootstrap after Retry.
abstract interface class RecoverableApplicationBootstrap {
  Future<PreparedApplication> prepareWithRecovery({
    required Future<void> Function() waitForRetry,
  });
}

final class ApplicationBootstrapCancelled implements Exception {
  const ApplicationBootstrapCancelled();
}

abstract interface class PreparedApplication {
  Future<Widget> buildRootWidget();

  void afterRunApp();
}

abstract interface class ApplicationHost {
  void initializeBinding();

  void launch(Widget rootWidget);
}

/// O6 (beta 2026-10-08): Android draws nothing in MainActivity's window, not
/// even the native incoming-call surface, until Flutter's first frame. That
/// frame normally waits for [ApplicationBootstrap.prepare] (about 4 s on a
/// cold start), so a call launch showed only the splash. A host that knows the
/// launch was for a call draws a plain frame before preparing.
abstract interface class IncomingCallLaunchHost {
  Future<void> showIncomingCallLaunchFrame();
}

final class FlutterApplicationHost
    implements ApplicationHost, IncomingCallLaunchHost {
  const FlutterApplicationHost();

  static const _launchChannel = MethodChannel('mknoon/launch_intent');

  @override
  void initializeBinding() {
    WidgetsFlutterBinding.ensureInitialized();
  }

  @override
  void launch(Widget rootWidget) {
    runApp(rootWidget);
  }

  @override
  Future<void> showIncomingCallLaunchFrame() async {
    if (kIsWeb || !Platform.isAndroid) return;
    bool incomingCall;
    try {
      incomingCall =
          await _launchChannel.invokeMethod<bool>('isIncomingCallLaunch') ??
          false;
    } on Object {
      return;
    }
    if (incomingCall) launch(incomingCallLaunchFrame);
  }
}

/// Matches the native call surface's dark background beneath it.
const incomingCallLaunchFrame = ColoredBox(color: Color(0xFF0A0A0F));

Future<void> runApplicationBootstrap({
  required ApplicationBootstrapFactory bootstrapFactory,
  required ApplicationHost host,
}) async {
  host.initializeBinding();
  if (host is IncomingCallLaunchHost) {
    await (host as IncomingCallLaunchHost).showIncomingCallLaunchFrame();
  }
  final bootstrap = bootstrapFactory();
  late final PreparedApplication preparedApplication;
  try {
    preparedApplication = bootstrap is RecoverableApplicationBootstrap
        ? await (bootstrap as RecoverableApplicationBootstrap)
              .prepareWithRecovery(
                waitForRetry: () {
                  final retry = Completer<void>();
                  host.launch(
                    _StartupRecoveryApp(
                      key: UniqueKey(),
                      retry: () {
                        if (!retry.isCompleted) retry.complete();
                      },
                    ),
                  );
                  return retry.future;
                },
              )
        : await bootstrap.prepare();
  } on ApplicationBootstrapCancelled {
    return;
  }
  final rootWidget = await preparedApplication.buildRootWidget();
  host.launch(rootWidget);
  preparedApplication.afterRunApp();
}

class _StartupRecoveryApp extends StatefulWidget {
  const _StartupRecoveryApp({super.key, required this.retry});
  final VoidCallback retry;

  @override
  State<_StartupRecoveryApp> createState() => _StartupRecoveryAppState();
}

class _StartupRecoveryAppState extends State<_StartupRecoveryApp> {
  bool waiting = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      waiting
                          ? l10n.startup_checking
                          : l10n.startup_failed_title,
                    ),
                    const SizedBox(height: 16),
                    if (waiting) const CircularProgressIndicator(),
                    FilledButton(
                      onPressed: waiting
                          ? null
                          : () {
                              setState(() => waiting = true);
                              widget.retry();
                            },
                      child: Text(l10n.btn_retry),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
