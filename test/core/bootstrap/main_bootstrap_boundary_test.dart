import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_app/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';

const _mainPath = 'lib/main.dart';
const _runnerPath = 'lib/app/bootstrap/application_bootstrap.dart';
const _productionPath =
    'lib/app/bootstrap/production_application_bootstrap.dart';
const _diagnosticsPath = 'lib/app/bootstrap/production_app_diagnostics.dart';
const _productionHeadlessPath =
    'lib/app/bootstrap/production_headless_canonical_recovery.dart';
const _productionHeadlessCallPath =
    'lib/app/bootstrap/production_headless_call_admission.dart';
const _rootPath = 'lib/app/application_root.dart';
const _h0ProbePath = 'lib/core/debug/android_canonical_runtime_h0_probe.dart';
const _plan374FixturePath =
    'lib/core/debug/android_headless_recovery_374_fixture.dart';
const _headlessRecoveryPath =
    'lib/core/notifications/headless_canonical_recovery_entrypoint.dart';
const _debugE2eCompositionRootPath =
    'lib/debug/debug_e2e_composition_root.dart';
const _flutterWidgetsPath = 'package:flutter/widgets.dart';

String _libraryPath(UriBasedDirective directive) {
  final uri = directive.uri.stringValue;
  if (uri == null) return '';
  if (uri.startsWith('package:flutter_app/')) {
    return 'lib/${uri.substring('package:flutter_app/'.length)}';
  }
  if (uri.startsWith('package:')) return uri;
  return 'lib/$uri';
}

int _occurrences(String source, String token) =>
    token.allMatches(source).length;

void main() {
  test('DTR-14 main delegates bootstrap through stable application interfaces', () {
    // Compile-time facade proof for every pre-extraction public symbol.
    expect(app.MyApp.navigatorKey, isNotNull);
    expect(app.openIntroNotificationOrbitRoute, isA<Function>());
    final Future<void>? retainedBackfill = app.keychainMirrorBackfill;
    expect(retainedBackfill, anyOf(isNull, isA<Future<void>>()));

    final source = File(_mainPath).readAsStringSync();
    final parsed = parseString(content: source, path: _mainPath);
    expect(parsed.errors, isEmpty);
    final unit = parsed.unit;
    final functions = unit.declarations.whereType<FunctionDeclaration>();
    final mains = functions
        .where((declaration) => declaration.name.lexeme == 'main')
        .toList(growable: false);
    expect(mains, hasLength(1));
    final entrypoint = mains.single;
    expect(entrypoint.returnType?.toSource(), 'void');
    expect(entrypoint.functionExpression.body.isAsynchronous, isTrue);
    final body = entrypoint.functionExpression.body;
    expect(body, isA<BlockFunctionBody>());
    final block = (body as BlockFunctionBody).block;

    // Framework initialization remains outside the observation boundary. The
    // one awaited wrapper contains only the original receipt preflight and
    // production delegation, in that order.
    expect(
      block.statements,
      hasLength(2),
      reason:
          'main() must contain only framework initialization and the awaited '
          'production diagnostics wrapper',
    );
    expect(
      block.statements[0].toSource(),
      'WidgetsFlutterBinding.ensureInitialized();',
    );
    expect(block.statements[1], isA<ExpressionStatement>());
    final wrapperExpression =
        (block.statements[1] as ExpressionStatement).expression;
    expect(wrapperExpression, isA<AwaitExpression>());
    final wrapperCall = (wrapperExpression as AwaitExpression).expression;
    expect(wrapperCall, isA<MethodInvocation>());
    final wrapper = wrapperCall as MethodInvocation;
    expect(wrapper.target, isNull);
    expect(wrapper.methodName.name, 'runWithProductionAppDiagnostics');
    expect(wrapper.typeArguments, isNull);
    expect(wrapper.argumentList.arguments, hasLength(1));
    final launch = wrapper.argumentList.arguments.single;
    expect(launch, isA<FunctionExpression>());
    final launchCallback = launch as FunctionExpression;
    expect(launchCallback.parameters?.parameters, isEmpty);
    expect(launchCallback.body, isA<BlockFunctionBody>());
    expect(launchCallback.body.isAsynchronous, isTrue);
    expect(launchCallback.body.isGenerator, isFalse);
    final launchStatements =
        (launchCallback.body as BlockFunctionBody).block.statements;
    expect(
      launchStatements,
      hasLength(2),
      reason:
          'the observation callback must preserve only receipt preflight and '
          'the single live bootstrap delegation',
    );
    expect(
      launchStatements[0].toSource(),
      'await DebugE2ECompositionRoot.'
      'acknowledgeGroupReactionNotificationIosDartMainEntryIfConfigured();',
    );
    expect(launchStatements[1], isA<ExpressionStatement>());
    final delegationExpression =
        (launchStatements[1] as ExpressionStatement).expression;
    expect(delegationExpression, isA<AwaitExpression>());
    final delegationCall = (delegationExpression as AwaitExpression).expression;
    expect(delegationCall, isA<MethodInvocation>());
    final delegation = delegationCall as MethodInvocation;
    expect(delegation.target, isNull);
    expect(delegation.methodName.name, 'runApplicationBootstrap');
    expect(delegation.typeArguments, isNull);
    final arguments = delegation.argumentList.arguments;
    expect(arguments, hasLength(2));
    expect(arguments, everyElement(isA<NamedExpression>()));
    expect(
      arguments.cast<NamedExpression>().map(
        (argument) => argument.name.label.name,
      ),
      orderedEquals(['bootstrapFactory', 'host']),
    );
    expect(
      (arguments[0] as NamedExpression).expression.toSource(),
      'ProductionApplicationBootstrap.new',
    );
    expect(
      (arguments[1] as NamedExpression).expression.toSource(),
      'const FlutterApplicationHost()',
    );
    final bodySource = body.toSource();
    expect(_occurrences(bodySource, 'runWithProductionAppDiagnostics('), 1);
    expect(_occurrences(bodySource, 'runApplicationBootstrap('), 1);
    expect(bodySource, contains('await runApplicationBootstrap('));
    expect(bodySource, contains('bootstrapFactory:'));
    expect(bodySource, contains('ProductionApplicationBootstrap'));
    expect(bodySource, contains('host:'));
    expect(bodySource, contains('FlutterApplicationHost'));

    expect(
      functions.map((declaration) => declaration.name.lexeme),
      orderedEquals(const [
        'main',
        'androidCanonicalRuntimeH0ProbeMain',
        'androidHeadlessRecovery374FixtureMain',
        'androidHeadlessCanonicalRecoveryMain',
        'androidHeadlessCallAdmissionMain',
      ]),
      reason:
          'main.dart may expose only main plus the four native AOT entrypoints',
    );
    for (final nativeEntrypoint in functions.where(
      (declaration) => declaration.name.lexeme != 'main',
    )) {
      expect(
        nativeEntrypoint.metadata.map((annotation) => annotation.toSource()),
        contains("@pragma('vm:entry-point')"),
        reason:
            '${nativeEntrypoint.name.lexeme} must stay AOT-visible for its native engine',
      );
    }
    expect(
      unit.declarations.whereType<TopLevelVariableDeclaration>(),
      isEmpty,
      reason: 'main.dart must not eagerly construct executable bootstrap state',
    );

    final imports = unit.directives
        .whereType<ImportDirective>()
        .map(_libraryPath)
        .toSet();
    expect(
      imports,
      equals({
        _runnerPath,
        _productionPath,
        _diagnosticsPath,
        _productionHeadlessPath,
        _productionHeadlessCallPath,
        _h0ProbePath,
        _plan374FixturePath,
        _headlessRecoveryPath,
        _debugE2eCompositionRootPath,
        _flutterWidgetsPath,
      }),
      reason:
          'main.dart imports only the stable app runner and exact entrypoint owners',
    );
    final exports = unit.directives
        .whereType<ExportDirective>()
        .map(_libraryPath)
        .toSet();
    expect(exports, equals({_rootPath, _productionPath}));

    for (final forbidden in const <String>[
      "package:flutter_app/features/",
      'Firebase.initializeApp',
      'openEncryptedDatabase(',
      'P2PServiceImpl(',
      'runApp(',
      'MyApp(',
      'class _MyAppState',
    ]) {
      expect(
        source,
        isNot(contains(forbidden)),
        reason: 'main.dart still owns concrete bootstrap fragment $forbidden',
      );
    }

    // Exact owner and cycle checks follow the live-entrypoint assertions.
    for (final path in const [
      _runnerPath,
      _productionPath,
      _diagnosticsPath,
      _rootPath,
    ]) {
      expect(File(path).existsSync(), isTrue, reason: 'missing $path');
    }
    final production = File(_productionPath).readAsStringSync();
    final diagnostics = File(_diagnosticsPath).readAsStringSync();
    final root = File(_rootPath).readAsStringSync();
    expect(
      production,
      isNot(contains("import 'package:flutter_app/main.dart'")),
    );
    expect(root, isNot(contains("import 'package:flutter_app/main.dart'")));
    expect(
      diagnostics,
      isNot(contains("import 'package:flutter_app/main.dart'")),
    );
    expect(_occurrences(root, 'class MyApp '), 1);
    expect(_occurrences(root, 'class _MyAppState '), 1);
    expect(
      _occurrences(root, 'Future<void> openIntroNotificationOrbitRoute('),
      1,
    );
    expect(_occurrences(production, 'keychainMirrorBackfill'), greaterThan(0));
    expect(source, isNot(contains('class MyApp ')));
    expect(source, isNot(contains('openIntroNotificationOrbitRoute(')));
  });

  test(
    'TC-374-07 production AOT recovery delegates one UI-neutral graph and same runner cleanup',
    () {
      final mainSource = File(_mainPath).readAsStringSync();
      expect(
        _occurrences(
          mainSource,
          'runRecovery: runProductionHeadlessCanonicalRecovery,',
        ),
        1,
      );
      expect(
        _occurrences(
          mainSource,
          'emergencyShutdown: cleanupProductionHeadlessCanonicalRecovery,',
        ),
        1,
      );
      expect(
        _occurrences(mainSource, 'runUnavailableHeadlessCanonicalRecovery'),
        0,
      );
      expect(
        _occurrences(mainSource, 'cleanupUnavailableHeadlessCanonicalRecovery'),
        0,
      );

      final recoveryFile = File(_productionHeadlessPath);
      expect(recoveryFile.existsSync(), isTrue);
      final recoverySource = recoveryFile.readAsStringSync();
      final parsed = parseString(
        content: recoverySource,
        path: _productionHeadlessPath,
      );
      expect(parsed.errors, isEmpty);
      final functions = parsed.unit.declarations
          .whereType<FunctionDeclaration>()
          .toList(growable: false);
      final run = functions.singleWhere(
        (declaration) =>
            declaration.name.lexeme == 'runProductionHeadlessCanonicalRecovery',
      );
      final cleanup = functions.singleWhere(
        (declaration) =>
            declaration.name.lexeme ==
            'cleanupProductionHeadlessCanonicalRecovery',
      );
      final runOwner = RegExp(
        r'([A-Za-z_$][A-Za-z0-9_$]*)\.run\(',
      ).firstMatch(run.functionExpression.body.toSource())?.group(1);
      final cleanupOwner = RegExp(
        r'([A-Za-z_$][A-Za-z0-9_$]*)\.emergencyCleanup\(',
      ).firstMatch(cleanup.functionExpression.body.toSource())?.group(1);
      expect(runOwner, isNotNull);
      expect(cleanupOwner, runOwner);
      expect(
        _occurrences(
          recoverySource,
          'ProductionHeadlessCanonicalRecoveryAcquisitionOwner',
        ),
        greaterThanOrEqualTo(1),
      );
      expect(
        _occurrences(
          recoverySource,
          'AndroidProductionHeadlessCanonicalRecoveryBackend()',
        ),
        1,
        reason: 'production owns one UI-neutral backend instance',
      );
      expect(recoverySource, contains('CanonicalRecoveryReason.deletedBatch'));
      expect(recoverySource, contains('CanonicalRecoveryReason.periodicSweep'));

      for (final forbidden in const <String>[
        'runApp(',
        'ApplicationRoot',
        'ProductionApplicationBootstrap(',
        'production_application_bootstrap.dart',
        'FirebaseMessaging.onMessage',
        'onMessageOpenedApp',
        'GeneratedPluginRegistrant',
        'Timer.periodic',
      ]) {
        expect(
          recoverySource,
          isNot(contains(forbidden)),
          reason: 'headless recovery must not compose $forbidden',
        );
      }
    },
  );
}
