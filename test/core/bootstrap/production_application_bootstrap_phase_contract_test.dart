import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_app/app/bootstrap/application_bootstrap.dart';
import 'package:flutter_app/app/bootstrap/production_application_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

const _productionPath =
    'lib/app/bootstrap/production_application_bootstrap.dart';
const _handlerPath =
    'lib/features/push/application/background_message_handler.dart';

ClassDeclaration _productionClass(String source) {
  final unit = parseString(content: source, path: _productionPath).unit;
  return unit.declarations.whereType<ClassDeclaration>().singleWhere(
    (declaration) =>
        declaration.name.lexeme == 'ProductionApplicationBootstrap',
  );
}

MethodDeclaration _method(ClassDeclaration declaration, String name) {
  return declaration.members.whereType<MethodDeclaration>().singleWhere(
    (method) => method.name.lexeme == name,
  );
}

Map<String, String> _localFunctionBodies(MethodDeclaration method) {
  final body = method.body;
  expect(body, isA<BlockFunctionBody>());
  final block = (body as BlockFunctionBody).block;
  return <String, String>{
    for (final statement
        in block.statements.whereType<FunctionDeclarationStatement>())
      statement.functionDeclaration.name.lexeme: statement
          .functionDeclaration
          .functionExpression
          .body
          .toSource(),
  };
}

final class _SentinelPrepared implements PreparedApplication {
  const _SentinelPrepared();

  @override
  Future<Widget> buildRootWidget() async => const Placeholder();

  @override
  void afterRunApp() {}
}

void main() {
  test('handled production reset bypasses normal composition', () async {
    var resetCalls = 0;
    var normalPrepareCalls = 0;
    final bootstrap = ProductionApplicationBootstrap(
      disposableProfileOverride: () => true,
      disposableResetOverride: () async {
        resetCalls += 1;
        return true;
      },
      normalPrepareOverride: () async {
        normalPrepareCalls += 1;
        return const _SentinelPrepared();
      },
    );

    final prepared = await bootstrap.prepare();
    expect(resetCalls, 1);
    expect(normalPrepareCalls, 0);
    expect(await prepared.buildRootWidget(), isA<SizedBox>());
    prepared.afterRunApp();
    expect(normalPrepareCalls, 0);
  });

  test(
    'DTR-14 production bootstrap owns each reachable phase exactly once',
    () {
      final production = File(_productionPath).readAsStringSync();
      final handler = File(_handlerPath).readAsStringSync();
      final productionClass = _productionClass(production);
      final prepare = _method(productionClass, 'prepare').body.toSource();
      final normalMethod = _method(
        productionClass,
        '_prepareNormalApplication',
      );
      final normal = normalMethod.body.toSource();
      final localBodies = _localFunctionBodies(normalMethod);
      expect(
        localBodies.keys,
        containsAll(<String>['_buildRootWidget', '_afterRunApp']),
      );
      final root = localBodies['_buildRootWidget']!;
      final post = localBodies['_afterRunApp']!;

      final reset = prepare.indexOf('runDisposableResetIfRequested()');
      final inertReturn = prepare.indexOf(
        'return _CallbackPreparedApplication(',
      );
      final normalCall = prepare.lastIndexOf('_prepareNormalApplication()');
      expect(reset, greaterThanOrEqualTo(0));
      expect(inertReturn, greaterThan(reset));
      expect(normalCall, greaterThan(inertReturn));
      expect(prepare, contains('if (resetHandled)'));
      expect(prepare, contains('return prepareOverride();'));

      expect(normal, contains("StartupTiming.instance.mark('app_start')"));
      final firebase = normal.indexOf(
        'final firebaseReadiness = FirebaseReadiness(',
      );
      const backgroundRegistrationToken =
          'FirebaseMessaging.onBackgroundMessage(';
      final backgroundRegistration = normal.indexOf(
        backgroundRegistrationToken,
      );
      final initializerEnd = normal.indexOf(
        "StartupTiming.instance.mark('firebase_ready')",
      );
      expect(firebase, greaterThanOrEqualTo(0));
      expect(backgroundRegistration, greaterThan(firebase));
      expect(initializerEnd, greaterThan(backgroundRegistration));
      expect(
        backgroundRegistrationToken.allMatches(normal),
        hasLength(1),
        reason: 'the successful Firebase initializer registers FCM once',
      );
      expect(
        normal.substring(backgroundRegistration, initializerEnd),
        contains('firebaseMessagingBackgroundHandler'),
      );

      const awaitedPrepopulation =
          'await debugE2EComposition?.prepopulateContactsBeforeRunApp(';
      final prepopulation = root.indexOf(awaitedPrepopulation);
      final myApp = root.indexOf('return MyApp(');
      expect(prepopulation, greaterThanOrEqualTo(0));
      expect(myApp, greaterThan(prepopulation));
      for (final moveAccountBinding in const <String>[
        'accountMigrationRunTransfer:',
        'accountMigrationTransferRuntime.runOldPhoneTransfer',
        'accountMigrationSizeGate: accountMigrationSizeGate',
        'accountMigrationStartReceiver:',
        'accountMigrationTransferRuntime.startNewPhoneReceiver',
        'accountMigrationStopReceiver:',
        'accountMigrationTransferRuntime.stopNewPhoneReceiver',
        'accountMigrationReceiverEvents:',
        'accountMigrationTransferRuntime.receiverEvents',
        'accountMigrationRecoverExportPause:',
        'restoreActiveAfterExportInterrupted()',
      ]) {
        expect(
          moveAccountBinding.allMatches(root),
          hasLength(1),
          reason: 'reachable MyApp construction must bind $moveAccountBinding',
        );
      }

      final sender = post.indexOf('startIosSenderProjectionAfterRunApp(');
      final runAppCalled = post.indexOf(
        "StartupTiming.instance.mark('run_app_called')",
      );
      final recovery = post.indexOf('ensurePrivateMediaColdRecovery()');
      final postsSweep = post.indexOf('sweepExpiredPosts(');
      final invitesSweep = post.indexOf('sweepExpiredGroupInvites(');
      final deletionReconciliation = post.indexOf(
        'groupMediaDeletionReconciler.runBounded()',
      );
      final poller = post.indexOf('startIntroPollerAfterColdRecovery(');
      expect(sender, greaterThanOrEqualTo(0));
      expect(runAppCalled, greaterThan(sender));
      expect(recovery, greaterThan(runAppCalled));
      expect(postsSweep, greaterThan(runAppCalled));
      expect(invitesSweep, greaterThan(runAppCalled));
      expect(deletionReconciliation, greaterThan(runAppCalled));
      expect(poller, greaterThan(runAppCalled));
      for (final postLaunchPhase in const <String>[
        'startIosSenderProjectionAfterRunApp(',
        "StartupTiming.instance.mark('run_app_called')",
        'ensurePrivateMediaColdRecovery()',
        'sweepExpiredPosts(',
        'sweepExpiredGroupInvites(',
        'groupMediaDeletionReconciler.runBounded()',
        'startIntroPollerAfterColdRecovery(',
      ]) {
        expect(
          postLaunchPhase.allMatches(post),
          hasLength(1),
          reason:
              'post-launch phase must remain reachable exactly once: '
              '$postLaunchPhase',
        );
      }

      expect(
        normal,
        matches(
          RegExp(
            r'buildRootWidget:\s*_buildRootWidget,\s*'
            r'afterRunApp:\s*_afterRunApp',
          ),
        ),
      );
      expect(production, isNot(contains('runApp(')));

      expect(handler, contains("@pragma('vm:entry-point')"));
      expect(
        handler,
        contains('Future<void> firebaseMessagingBackgroundHandler('),
      );
      expect(handler, isNot(contains('application_bootstrap.dart')));
      expect(handler, isNot(contains('production_application_bootstrap.dart')));
      expect(
        handler,
        isNot(contains("import 'package:flutter_app/main.dart'")),
      );
    },
  );
}
