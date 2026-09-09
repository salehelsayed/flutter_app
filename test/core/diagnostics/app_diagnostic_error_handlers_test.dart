import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostic_error_handlers.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'framework and engine observers preserve previous error policy and redact evidence',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'app-error-test-',
      );
      final previousFlutter = FlutterError.onError;
      final previousPlatform = PlatformDispatcher.instance.onError;
      final observed = <Object>[];
      final diagnostics = await AppDiagnostics.installForTesting(
        directory: directory,
      );
      addTearDown(() async {
        FlutterError.onError = previousFlutter;
        PlatformDispatcher.instance.onError = previousPlatform;
        await diagnostics.dispose();
        await directory.delete(recursive: true);
      });
      FlutterError.onError = (details) => observed.add(details.exception);
      PlatformDispatcher.instance.onError = (error, stack) {
        observed.add(error);
        return false;
      };
      installAppDiagnosticErrorHandlers();
      final flutterError = StateError('SECRET_WIDGET_CONTENT');
      FlutterError.onError!(FlutterErrorDetails(exception: flutterError));
      final asyncError = FormatException('SECRET_PAYLOAD');
      expect(
        PlatformDispatcher.instance.onError!(asyncError, StackTrace.current),
        false,
      );
      expect(observed, [flutterError, asyncError]);
      final events = await diagnostics.eventsForTesting();
      expect(events.map((e) => e['reason']), [
        'flutter_error',
        'unhandled_error',
      ]);
      expect(
        events.every((e) => e['stage'] == 'process'),
        true,
        reason: 'An error callback alone does not prove an OS-confirmed crash.',
      );
      expect(await diagnostics.exportPreview(), isNot(contains('SECRET')));
    },
  );
}
