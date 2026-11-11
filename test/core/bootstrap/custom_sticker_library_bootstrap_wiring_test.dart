import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

// Source wiring only. Real SQLite facade/factory tests own lifecycle, authority
// and filesystem behavior; this contract does not execute bootstrap or certify
// the UI-owned activation callback's implementation.
const _bootstrapPath =
    'lib/app/bootstrap/production_application_bootstrap.dart';
const _runtimePath =
    'lib/features/account_migration/application/account_migration_local_transfer_runtime.dart';

final class _Nodes<T extends AstNode> extends GeneralizingAstVisitor<void> {
  final values = <T>[];

  @override
  void visitNode(AstNode node) {
    if (node is T) values.add(node);
    super.visitNode(node);
  }
}

List<T> _nodes<T extends AstNode>(AstNode scope) {
  final visitor = _Nodes<T>();
  scope.accept(visitor);
  return visitor.values;
}

T _one<T>(Iterable<T> values, String reason) {
  final found = values.toList();
  expect(found, hasLength(1), reason: reason);
  return found.single;
}

String _code(AstNode node) => node.toSource().replaceAll(RegExp(r'\s+'), '');

typedef _Call = ({AstNode node, ArgumentList arguments});

List<_Call> _calls(AstNode scope, String qualifiedName) => [
  for (final node in _nodes<MethodInvocation>(scope))
    if ((node.target == null
            ? node.methodName.name
            : '${_code(node.target!)}.${node.methodName.name}') ==
        qualifiedName)
      (node: node, arguments: node.argumentList),
  // Unresolved implicit-new calls use MethodInvocation; explicit constructors
  // use InstanceCreationExpression. Match both, as the phase contract does.
  for (final node in _nodes<InstanceCreationExpression>(scope))
    if (node.constructorName.type.name.lexeme == qualifiedName)
      (node: node, arguments: node.argumentList),
  for (final node in _nodes<FunctionExpressionInvocation>(scope))
    if (_code(node.function) == qualifiedName)
      (node: node, arguments: node.argumentList),
];

_Call _call(AstNode scope, String name) => _one(
  _calls(scope, name),
  'Expected one $name call at this ownership boundary.',
);

Expression _argument(_Call call, String name) => _one(
  call.arguments.arguments.whereType<NamedExpression>().where(
    (argument) => argument.name.label.name == name,
  ),
  'The owning call must supply $name.',
).expression;

FunctionExpression _callback(Expression expression) {
  expect(
    expression,
    isA<FunctionExpression>(),
    reason:
        'This boundary needs an ordered callback, not an unguarded tearoff.',
  );
  return expression as FunctionExpression;
}

Block _block(FunctionBody body) {
  expect(body, isA<BlockFunctionBody>());
  return (body as BlockFunctionBody).block;
}

MethodDeclaration _method(CompilationUnit unit, String owner, String name) {
  final declaration = _one(
    unit.declarations.whereType<ClassDeclaration>().where(
      (declaration) => declaration.name.lexeme == owner,
    ),
    'Expected the existing $owner composition owner.',
  );
  return _one(
    declaration.members.whereType<MethodDeclaration>().where(
      (method) => method.name.lexeme == name,
    ),
    'Expected the existing $owner.$name boundary.',
  );
}

VariableDeclaration _local(Block block, String name) => _one(
  block.statements
      .whereType<VariableDeclarationStatement>()
      .expand((statement) => statement.variables.variables)
      .where((variable) => variable.name.lexeme == name),
  '$name must belong to the outer bootstrap scope, not a per-root callback.',
);

// Requiring a direct awaited statement excludes an unawaited call, an unused
// closure, a feature-flag branch, or a catch/finally path that allows replacement
// to continue without successfully draining the library.
AwaitExpression _directAwait(Block block, _Call call) {
  expect(
    call.node.parent,
    isA<AwaitExpression>(),
    reason: 'The ${call.node.toSource()} barrier must be awaited.',
  );
  final awaited = call.node.parent! as AwaitExpression;
  expect(awaited.parent, isA<ExpressionStatement>());
  expect(
    awaited.parent!.parent,
    same(block),
    reason: 'The barrier must execute on the callback success path.',
  );
  return awaited;
}

Statement _statement(Block block, AstNode node) {
  var current = node;
  while (!identical(current.parent, block)) {
    expect(
      current,
      isNot(isA<FunctionExpression>()),
      reason: 'An unused nested closure is not an executed boundary.',
    );
    expect(current.parent, isNotNull);
    current = current.parent!;
  }
  expect(current, isA<Statement>());
  return current as Statement;
}

void _keepsDefaultFlag(_Call call) {
  final enabled = call.arguments.arguments.whereType<NamedExpression>().where(
    (argument) => argument.name.label.name == 'enabled',
  );
  if (enabled.isNotEmpty) {
    expect(_code(enabled.single.expression), 'kCustomStickersEnabled');
  }
}

void main() {
  late CompilationUnit bootstrap;
  late CompilationUnit runtime;
  late Block normal;
  late _Call myApp;

  setUpAll(() {
    bootstrap = parseString(
      content: File(_bootstrapPath).readAsStringSync(),
      path: _bootstrapPath,
    ).unit;
    runtime = parseString(
      content: File(_runtimePath).readAsStringSync(),
      path: _runtimePath,
    ).unit;
    normal = _block(
      _method(
        bootstrap,
        'ProductionApplicationBootstrap',
        '_prepareNormalApplication',
      ).body,
    );
    final rootBuilder = _one(
      normal.statements.whereType<FunctionDeclarationStatement>().where(
        (statement) =>
            statement.functionDeclaration.name.lexeme == '_buildRootWidget',
      ),
      'Expected the existing per-root build callback.',
    ).functionDeclaration.functionExpression;
    myApp = _call(rootBuilder.body, 'MyApp');
  });

  test(
    'one outer sticker facade owns a lazy factory with passive account inputs',
    () {
      final facade = _call(normal, 'AccountCustomStickerLibrary');
      final owner = _local(normal, 'customStickerLibrary');
      expect(owner.initializer, same(facade.node));
      _keepsDefaultFlag(facade);
      final create = _callback(_argument(facade, 'createLibrary'));
      final factory = _call(create.body, 'createBoundCustomStickerLibrary');
      expect(_calls(normal, 'createBoundCustomStickerLibrary'), hasLength(1));
      expect(_code(_argument(factory, 'db')), 'db');
      expect(_code(_argument(factory, 'documentsDirectory')), 'appDocDir');
      expect(
        _code(_argument(factory, 'readAuthority')),
        'accountMigrationAuthorityRepository.loadAuthority',
      );
      expect(
        _code(_argument(factory, 'readAccountBinding')),
        'canonicalRuntimeBindingCoordinator?.readCurrentAccountBinding',
      );
      final parameter = _one(
        create.parameters!.parameters,
        'Factory creation must receive the facade generation predicate.',
      );
      expect(_code(_argument(factory, 'isCurrent')), parameter.name!.lexeme);
      expect(
        _nodes<MethodInvocation>(create.body)
            .where((call) => call.methodName.name == 'loadIdentity'),
        isEmpty,
        reason: 'Identity loading may republish account authority and is not a passive factory check.',
      );
      final temporary = _argument(factory, 'temporaryDirectory');
      if (temporary is FunctionExpression) {
        _call(temporary.body, 'getTemporaryDirectory');
        expect(_calls(create.body, 'getTemporaryDirectory'), hasLength(1));
      } else {
        expect(_code(temporary), 'getTemporaryDirectory');
        expect(_calls(create.body, 'getTemporaryDirectory'), isEmpty);
      }
      _keepsDefaultFlag(factory);
    },
  );

  test(
    'each MyApp receives the stable facade and its explicit activation hook',
    () {
      expect(
        _code(_argument(myApp, 'customStickerLibrary')),
        'customStickerLibrary',
      );
      expect(
        _code(_argument(myApp, 'onCustomStickerAccountActivated')),
        'customStickerLibrary.activate',
      );
    },
  );

  test(
    'export pauses authority then drains the library before source snapshot',
    () {
      final run = _method(
        runtime,
        'AccountMigrationLocalTransferRuntime',
        'runOldPhoneTransfer',
      );
      final pause = _call(run.body, '_pauseOldPhoneNetworkForExport');
      final handoff = _call(run.body, '_runOldPhoneExportAndHandoff');
      expect(pause.node.parent, isA<AwaitExpression>());
      expect(handoff.node.parent, isA<AwaitExpression>());
      expect(pause.node.end, lessThan(handoff.node.offset));
      final pauseFailure = _one(
        _nodes<IfStatement>(run.body).where(
          (statement) =>
              _code(statement.expression) == 'exportPauseFailure!=null',
        ),
        'A failed authority pause must return before the export callback.',
      );
      expect(pause.node.end, lessThan(pauseFailure.offset));
      expect(pauseFailure.end, lessThan(handoff.node.offset));
      expect(
        _code(
          _one(
            _nodes<ReturnStatement>(pauseFailure.thenStatement),
            'Return the pause failure.',
          ).expression!,
        ),
        'exportPauseFailure',
      );
      expect(_code(_argument(handoff, 'source')), 'source');
      final source = _one(
        _nodes<VariableDeclaration>(run.body)
            .where((value) => value.name.lexeme == 'source'),
        'The export must use the injected bundle source.',
      );
      expect(_code(source.initializer!), 'bundleSource');
      final pauseBody = _method(
        runtime,
        'AccountMigrationLocalTransferRuntime',
        '_pauseOldPhoneNetworkForExport',
      ).body;
      expect(
        _call(pauseBody, 'coordinator.markExportingNetworkPaused').node.parent,
        isA<AwaitExpression>(),
      );
      final exportBody = _method(
        runtime,
        'AccountMigrationLocalTransferRuntime',
        '_runOldPhoneExportAndHandoff',
      ).body;
      expect(_call(exportBody, 'source').node.parent, isA<AwaitExpression>());

      final transfer = _call(normal, 'AccountMigrationLocalTransferRuntime');
      final callback = _callback(_argument(transfer, 'bundleSource'));
      final block = _block(callback.body);
      final drained = _directAwait(
        block,
        _call(block, 'customStickerLibrary.drainForExport'),
      );
      final snapshot = _one(
        [
          ..._calls(block, 'accountMigrationBundleSource.call'),
          ..._calls(block, 'accountMigrationBundleSource'),
        ],
        'The drained callback must invoke the actual production bundle source.',
      );
      expect(_statement(block, snapshot.node), isA<ReturnStatement>());
      expect(drained.end, lessThan(snapshot.node.offset));
      expect(
        _code(snapshot.arguments.arguments.single),
        callback.parameters!.parameters.single.name!.lexeme,
      );
    },
  );

  test('receiver refusal precedes retirement and retirement precedes receiver start', () {
    final callback = _callback(
      _argument(myApp, 'accountMigrationStartReceiver'),
    );
    final block = _block(callback.body);
    final refusal = _one(
      block.statements.whereType<IfStatement>().where(
        (statement) => _code(statement.expression) == 'precondition.status==AccountMigrationImportPreconditionStatus.linkedSecondaryInstallation',
      ),
      'Preserve the linked-installation refusal before disturbing the current library.',
    );
    expect(_nodes<ReturnStatement>(refusal.thenStatement), isNotEmpty);
    final retired = _directAwait(
      block,
      _call(block, 'customStickerLibrary.retire'),
    );
    final receiver = _call(
      block,
      'accountMigrationTransferRuntime.startNewPhoneReceiver',
    );
    expect(_statement(block, receiver.node), isA<ReturnStatement>());
    expect(refusal.end, lessThan(retired.offset));
    expect(retired.end, lessThan(receiver.node.offset));
  });

  test(
    'account erase retires the library before owned media and SQL deletion',
    () {
      final block = _block(
        _callback(_argument(myApp, 'eraseLocalAccountDatabase')).body,
      );
      final retired = _directAwait(
        block,
        _call(block, 'customStickerLibrary.retire'),
      );
      final media = _call(block, 'eraseAccountMedia');
      final database = _call(block, 'eraseEncryptedDatabase');
      _directAwait(block, media);
      _directAwait(block, database);
      expect(retired.end, lessThan(media.node.offset));
      expect(retired.end, lessThan(database.node.offset));
      expect(_code(_argument(media, 'documentsDirectory')), 'appDocDir');
      expect(_code(database.arguments.arguments.single), 'db');
    },
  );

  test('canonical shutdown awaits the late-bound facade retirement before database shutdown', () {
    final hook = _local(normal, 'retireCustomStickerLibrary');
    expect(
      hook.initializer,
      isNull,
      reason: 'Early shutdown must not initialize account providers.',
    );
    final declaration = hook.parent! as VariableDeclarationList;
    expect(_code(declaration.type!), 'Future<void>Function()?');
    expect(
      declaration.isLate,
      isFalse,
      reason: 'Before binding, early shutdown must observe null, not an uninitialized late variable.',
    );
    final owner = _call(normal, 'CanonicalRuntimeShutdownSequence');
    expect(hook.offset, lessThan(owner.node.offset));
    final binding = _one(
      _nodes<AssignmentExpression>(normal).where(
        (assignment) =>
            _code(assignment.leftHandSide) == 'retireCustomStickerLibrary',
      ),
      'Bind the early shutdown hook once to the stable facade, outside root rebuilds.',
    );
    expect(_code(binding.rightHandSide), 'customStickerLibrary.retire');
    expect(binding.parent!.parent, same(normal));
    expect(
      _local(normal, 'customStickerLibrary').end,
      lessThan(binding.offset),
    );
    final block = _block(_callback(_argument(owner, 'shutdownRuntime')).body);
    final retirementCall = _call(block, 'retireCustomStickerLibrary.call');
    expect(retirementCall.node, isA<MethodInvocation>());
    expect((retirementCall.node as MethodInvocation).isNullAware, isTrue);
    final retired = _directAwait(block, retirementCall);
    final shutdown = _call(block, 'canonicalWritableRuntimeSession.shutdown');
    expect(_statement(block, shutdown.node), isA<ReturnStatement>());
    expect(retired.end, lessThan(shutdown.node.offset));
  });
}
