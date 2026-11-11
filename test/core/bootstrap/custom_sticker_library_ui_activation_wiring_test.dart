import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

// Source contract only: no MyApp pump, runtime bootstrap, or platform providers.
// The real facade/factory suites own account and filesystem behavior.
const _rootPath = 'lib/app/application_root.dart';

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

ClassDeclaration _class(CompilationUnit unit, String name) => _one(
  unit.declarations.whereType<ClassDeclaration>().where(
    (declaration) => declaration.name.lexeme == name,
  ),
  'Expected the existing $name owner.',
);

MethodInvocation _call(AstNode scope, String receiver, String method) => _one(
  _nodes<MethodInvocation>(scope).where(
    (call) =>
        call.methodName.name == method &&
        (call.target == null ? '' : _code(call.target!)) == receiver,
  ),
  'Expected one $receiver.$method call at this boundary.',
);

void main() {
  late CompilationUnit root;

  setUpAll(() {
    root = parseString(
      content: File(_rootPath).readAsStringSync(),
      path: _rootPath,
    ).unit;
  });

  test('MyApp accepts the optional stable sticker library and activation callback', () {
    final widget = _class(root, 'MyApp');
    final constructor = _one(
      widget.members.whereType<ConstructorDeclaration>().where(
        (constructor) => constructor.name == null,
      ),
      'The existing MyApp constructor must accept both optional dependencies.',
    );
    for (final entry in const {
      'customStickerLibrary': 'CustomStickerLibrary?',
      'onCustomStickerAccountActivated': 'Future<void>Function()?',
    }.entries) {
      final field = _one(
        widget.members.whereType<FieldDeclaration>().where(
          (field) => field.fields.variables.any(
            (variable) => variable.name.lexeme == entry.key,
          ),
        ),
        'MyApp must retain the optional ${entry.key} supplied by bootstrap.',
      );
      expect(field.isStatic, isFalse);
      expect(field.fields.isFinal, isTrue);
      expect(_code(field.fields.type!), entry.value);
      final parameter = _one(
        constructor.parameters.parameters.where(
          (parameter) => parameter.name?.lexeme == entry.key,
        ),
        'Existing MyApp callers must be able to omit ${entry.key}.',
      );
      expect(parameter.isOptionalNamed, isTrue);
      expect(parameter, isA<DefaultFormalParameter>());
      final optional = parameter as DefaultFormalParameter;
      expect(optional.parameter, isA<FieldFormalParameter>());
      expect(
        optional.defaultValue == null || optional.defaultValue is NullLiteral,
        isTrue,
      );
    }
  });

  test('sticker activation is awaited only after identity refresh and completed cutover cleanup', () {
    final state = _class(root, '_MyAppState');
    final method = _one(
      state.members.whereType<MethodDeclaration>().where(
        (method) =>
            method.name.lexeme == '_handleAccountMigrationReceiverActivated',
      ),
      'Use the existing successful receiver-activation boundary.',
    );
    expect(method.body, isA<BlockFunctionBody>());
    final body = (method.body as BlockFunctionBody).block;
    final hook = _call(body, 'widget.onCustomStickerAccountActivated', 'call');
    expect(hook.isNullAware, isTrue);
    expect(hook.parent, isA<AwaitExpression>());
    final awaited = hook.parent! as AwaitExpression;
    expect(awaited.parent, isA<ExpressionStatement>());
    final statement = awaited.parent! as ExpressionStatement;
    expect(
      statement.parent,
      same(body),
      reason: 'Activation must be outside catch/finally and nested callbacks.',
    );
    expect(body.statements.last, same(statement));

    final preceding = body.statements[body.statements.length - 2];
    expect(
      preceding,
      isA<TryStatement>(),
      reason: 'Complete the existing refresh try/finally before publishing the sticker generation.',
    );
    final refresh = preceding as TryStatement;
    expect(
      refresh.catchClauses,
      isEmpty,
      reason: 'Refresh failures must propagate past the activation hook.',
    );
    expect(refresh.finallyBlock, isNotNull);
    expect(refresh.end, lessThan(hook.offset));
    final notificationRefresh = _call(
      refresh.body,
      '',
      'activateAccountMigrationReceiverNotificationState',
    );
    expect(notificationRefresh.parent, isA<AwaitExpression>());
    final rebuild = _one(
      notificationRefresh.argumentList.arguments
          .whereType<NamedExpression>()
          .where(
            (argument) =>
                argument.name.label.name == 'rebuildRecipientProjection',
          ),
      'Preserve the identity/projection refresh that precedes activation.',
    ).expression;
    expect(rebuild, isA<FunctionExpression>());
    expect(
      _call(
        (rebuild as FunctionExpression).body,
        'widget.repository',
        'loadIdentity',
      ).parent,
      isA<AwaitExpression>(),
    );

    final cleanup = refresh.finallyBlock!;
    final cutover = _call(
      cleanup,
      'pushRegistration',
      'completeAccountBindingCutover',
    );
    expect(cutover.isNullAware, isTrue);
    expect(cutover.parent, isA<AwaitExpression>());
    expect(cutover.end, lessThan(hook.offset));
    expect(
      _nodes<FunctionExpression>(cleanup),
      isEmpty,
      reason: 'The awaited cutover must execute during cleanup, not in an unused closure.',
    );
    expect(
      _nodes<ReturnStatement>(cleanup),
      isEmpty,
      reason: 'Cleanup must not suppress an exception from identity/projection refresh.',
    );
    expect(
      _nodes<CatchClause>(cleanup),
      isEmpty,
      reason: 'Cutover errors must also leave sticker activation unreachable.',
    );
  });
}
