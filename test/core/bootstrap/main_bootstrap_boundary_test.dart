import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_app/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';

const _mainPath = 'lib/main.dart';
const _runnerPath = 'lib/app/bootstrap/application_bootstrap.dart';
const _productionPath =
    'lib/app/bootstrap/production_application_bootstrap.dart';
const _rootPath = 'lib/app/application_root.dart';

String _libraryPath(UriBasedDirective directive) {
  final uri = directive.uri.stringValue;
  if (uri == null) return '';
  if (uri.startsWith('package:flutter_app/')) {
    return 'lib/${uri.substring('package:flutter_app/'.length)}';
  }
  return 'lib/$uri';
}

int _occurrences(String source, String token) =>
    token.allMatches(source).length;

void main() {
  test(
    'DTR-14 main delegates bootstrap through stable application interfaces',
    () {
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

      // This is deliberately the first ownership assertion: at DTR-14 HEAD it
      // fails against the real 7k-line body, rather than because a future file
      // is absent.
      expect(
        block.statements,
        hasLength(1),
        reason: 'the supported main() must contain only its live delegation',
      );
      final bodySource = body.toSource();
      expect(_occurrences(bodySource, 'runApplicationBootstrap('), 1);
      expect(bodySource, contains('await runApplicationBootstrap('));
      expect(bodySource, contains('bootstrapFactory:'));
      expect(bodySource, contains('ProductionApplicationBootstrap'));
      expect(bodySource, contains('host:'));
      expect(bodySource, contains('FlutterApplicationHost'));

      expect(
        functions.map((declaration) => declaration.name.lexeme),
        orderedEquals(const ['main']),
        reason: 'delegation must not be hidden in an unused top-level helper',
      );
      expect(
        unit.declarations.whereType<TopLevelVariableDeclaration>(),
        isEmpty,
        reason:
            'main.dart must not eagerly construct executable bootstrap state',
      );

      final imports = unit.directives
          .whereType<ImportDirective>()
          .map(_libraryPath)
          .toSet();
      expect(
        imports,
        equals({_runnerPath, _productionPath}),
        reason: 'main.dart imports only the stable runner and concrete factory',
      );
      final exports = unit.directives
          .whereType<ExportDirective>()
          .map(_libraryPath)
          .toSet();
      expect(exports, equals({_rootPath, _productionPath}));

      for (final forbidden in const <String>[
        "package:flutter_app/core/",
        "package:flutter_app/features/",
        "package:flutter_app/debug/",
        'Firebase.initializeApp',
        'openEncryptedDatabase(',
        'P2PServiceImpl(',
        'DebugE2ECompositionRoot',
        'WidgetsFlutterBinding.ensureInitialized',
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
      for (final path in const [_runnerPath, _productionPath, _rootPath]) {
        expect(File(path).existsSync(), isTrue, reason: 'missing $path');
      }
      final production = File(_productionPath).readAsStringSync();
      final root = File(_rootPath).readAsStringSync();
      expect(
        production,
        isNot(contains("import 'package:flutter_app/main.dart'")),
      );
      expect(root, isNot(contains("import 'package:flutter_app/main.dart'")));
      expect(_occurrences(root, 'class MyApp '), 1);
      expect(_occurrences(root, 'class _MyAppState '), 1);
      expect(
        _occurrences(root, 'Future<void> openIntroNotificationOrbitRoute('),
        1,
      );
      expect(
        _occurrences(production, 'keychainMirrorBackfill'),
        greaterThan(0),
      );
      expect(source, isNot(contains('class MyApp ')));
      expect(source, isNot(contains('openIntroNotificationOrbitRoute(')));
    },
  );
}
