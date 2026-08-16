import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

const _bootstrapPath =
    'lib/app/bootstrap/production_application_bootstrap.dart';
const _appRootPath = 'lib/app/application_root.dart';
const _startupRouterPath =
    'lib/features/identity/presentation/startup_router.dart';
const _showNotificationPath =
    'lib/features/push/application/show_notification_use_case.dart';
const _foregroundFallbackPath =
    'lib/features/push/application/background_push_notification_fallback.dart';
const _directMessagePath =
    'lib/features/conversation/application/chat_message_listener.dart';
const _directReactionPath =
    'lib/features/conversation/application/handle_incoming_reaction_use_case.dart';
const _groupReactionPath =
    'lib/features/groups/application/group_message_listener_reaction_ingress_processor.dart';
const _groupListenerPath =
    'lib/features/groups/application/group_message_listener.dart';

void main() {
  test(
    'TC-371-05a production has one suppression owner and no notification tracker lifecycle bypass',
    () {
      final calls = _discoverMaybeShowNotificationCalls();
      expect(calls, hasLength(14));
      expect(
        <String, List<String>>{
          for (final path in calls.map((call) => call.path).toSet())
            path:
                calls
                    .where((call) => call.path == path)
                    .map((call) => call.namedArguments['appVisibility']!)
                    .toList()
                  ..sort(),
        },
        <String, List<String>>{
          _bootstrapPath: <String>[
            'appVisibilityAuthority',
            'appVisibilityAuthority',
            'appVisibilityAuthority',
          ],
          _foregroundFallbackPath: <String>['visibility', 'visibility'],
          _directMessagePath: <String>['appVisibility!'],
          _directReactionPath: <String>['appVisibility'],
          _groupReactionPath: <String>['visibility'],
          _groupListenerPath: <String>[
            '_appVisibility',
            'visibility',
            'visibility',
            'visibility',
            'visibility',
            'visibility',
          ],
        },
      );
      for (final call in calls) {
        expect(
          call.namedArguments,
          contains('appVisibility'),
          reason: call.label,
        );
        expect(
          call.namedArguments,
          isNot(contains('conversationTracker')),
          reason: call.label,
        );
        expect(
          call.namedArguments,
          isNot(contains('getAppLifecycleState')),
          reason: call.label,
        );
      }

      final showUnit = _unit(_showNotificationPath);
      final showFunction = _function(showUnit, 'maybeShowNotification');
      final showParameters = showFunction.functionExpression.parameters!
          .toSource();
      expect(
        showParameters,
        contains('required AppVisibilitySuppressionReader appVisibility'),
      );
      expect(showParameters, isNot(contains('ActiveConversationTracker')));
      expect(showParameters, isNot(contains('getAppLifecycleState')));
      expect(_namedInvocations(showFunction, 'evaluate'), hasLength(1));
      expect(_namedInvocations(showFunction, 'isViewing'), isEmpty);

      final bootstrap = _unit(_bootstrapPath);
      final authorityCreations = _creationsNamed(
        bootstrap,
        'AppVisibilityAuthority',
      );
      expect(authorityCreations, hasLength(1));
      expect(
        authorityCreations.single.node.parent,
        isA<VariableDeclaration>().having(
          (declaration) => declaration.name.lexeme,
          'name',
          'appVisibilityAuthority',
        ),
      );
      final myApp = _creationsNamed(bootstrap, 'MyApp').single;
      expect(
        _namedArguments(myApp.arguments),
        containsPair('appVisibilityAuthority', 'appVisibilityAuthority'),
      );
      expect(
        _namedArguments(myApp.arguments),
        containsPair(
          'appVisibilityRouteRegistry',
          'appVisibilityRouteRegistry',
        ),
      );

      _expectRawPresentationDecisionsUseOnlyVisibilityAuthority();
    },
  );
}

void _expectRawPresentationDecisionsUseOnlyVisibilityAuthority() {
  final appRoot = _unit(_appRootPath);
  final appRootState = _class(appRoot, '_MyAppState');
  final reactionResolver = _method(
    appRootState,
    '_resolveForegroundGroupReactionNotification',
  );
  expect(_namedInvocations(reactionResolver, 'isViewing'), isEmpty);
  expect(reactionResolver.toSource(), isNot(contains('getAppLifecycleState')));
  final fallbackCalls = _namedInvocations(
    appRootState,
    'showForegroundPushFallbackNotificationIfNeeded',
  );
  expect(fallbackCalls, hasLength(1));
  expect(
    _namedArguments(fallbackCalls.single.argumentList),
    containsPair('appVisibility', '_appVisibilityAuthority'),
  );

  final receiverActivation = _method(
    appRootState,
    '_handleAccountMigrationReceiverActivated',
  );
  expect(
    (receiverActivation.body as BlockFunctionBody).block.statements.first
        .toSource(),
    '_appVisibilityAuthority.invalidateSynchronously();',
    reason: 'account replacement must invalidate visibility before cleanup',
  );
  final startupRouter = _creationsNamed(appRootState, 'StartupRouter').single;
  expect(
    _namedArguments(startupRouter.arguments),
    containsPair(
      'invalidateAppVisibility',
      '_appVisibilityAuthority.invalidateSynchronously',
    ),
  );

  final startupUnit = _unit(_startupRouterPath);
  final startupState = _class(startupUnit, '_StartupRouterState');
  final accountErase = _method(startupState, '_eraseMigratedOutAccount');
  expect(
    (accountErase.body as BlockFunctionBody).block.statements.first.toSource(),
    'widget.invalidateAppVisibility?.call();',
    reason: 'account erase must invalidate visibility before native cleanup',
  );
  final restartedRouter = _creationsNamed(
    _method(startupState, '_buildRestartedStartupRouter'),
    'StartupRouter',
  ).single;
  expect(
    _namedArguments(restartedRouter.arguments),
    containsPair('invalidateAppVisibility', 'widget.invalidateAppVisibility'),
  );

  final fallback = _function(
    _unit(_foregroundFallbackPath),
    'showForegroundPushFallbackNotificationIfNeeded',
  );
  final fallbackEvaluations = _namedInvocations(fallback, 'evaluate');
  expect(fallbackEvaluations, hasLength(1));
  expect(fallbackEvaluations.single.target?.toSource(), 'visibility');
  expect(_namedInvocations(fallback, 'isViewing'), isEmpty);

  final groupUnit = _unit(_groupListenerPath);
  final groupListener = _class(groupUnit, 'GroupMessageListener');
  final canonicalView = _method(
    groupListener,
    '_isCurrentNotificationContentCanonical',
  );
  final canonicalReplacement = _method(
    groupListener,
    '_loadCanonicalNotificationReplacement',
  );
  final suppressionHelper = _method(
    groupListener,
    '_maySuppressGroupNotification',
  );
  expect(
    _namedInvocations(canonicalView, '_maySuppressGroupNotification'),
    hasLength(1),
  );
  expect(
    _namedInvocations(canonicalReplacement, '_maySuppressGroupNotification'),
    hasLength(1),
  );
  expect(_namedInvocations(suppressionHelper, 'evaluate'), hasLength(1));
  expect(_namedInvocations(groupListener, 'isViewing'), isEmpty);

  final protectedAdapter = groupUnit.declarations
      .whereType<ExtensionDeclaration>()
      .singleWhere(
        (declaration) =>
            declaration.name?.lexeme ==
            'GroupMessageListenerProtectedContentAdapter',
      );
  for (final methodName in <String>[
    'buildProtectedMessageDisplayReadyRow',
    'buildProtectedReactionDisplayReadyRow',
  ]) {
    final builder = protectedAdapter.members
        .whereType<MethodDeclaration>()
        .singleWhere((method) => method.name.lexeme == methodName);
    final source = builder.toSource();
    expect(source, isNot(contains('_appVisibility')), reason: methodName);
    expect(
      _namedInvocations(builder, '_maySuppressGroupNotification'),
      isEmpty,
      reason: methodName,
    );
    expect(
      _namedInvocations(builder, 'isViewing'),
      isEmpty,
      reason: methodName,
    );
  }
}

List<
  ({String path, int line, Map<String, String> namedArguments, String label})
>
_discoverMaybeShowNotificationCalls() {
  final calls =
      <
        ({
          String path,
          int line,
          Map<String, String> namedArguments,
          String label,
        })
      >[];
  final paths =
      Directory('lib')
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .map((file) => file.path.replaceAll('\\', '/'))
          .where((path) => path.endsWith('.dart'))
          .toList()
        ..sort();
  for (final path in paths) {
    final source = File(path).readAsStringSync();
    if (!source.contains('maybeShowNotification(')) continue;
    final parsed = parseString(
      content: source,
      path: path,
      throwIfDiagnostics: false,
    );
    for (final invocation in _namedInvocations(
      parsed.unit,
      'maybeShowNotification',
    )) {
      final line = parsed.lineInfo.getLocation(invocation.offset).lineNumber;
      calls.add((
        path: path,
        line: line,
        namedArguments: _namedArguments(invocation.argumentList),
        label: '$path:$line',
      ));
    }
  }
  return calls;
}

CompilationUnit _unit(String path) => parseString(
  content: File(path).readAsStringSync(),
  path: path,
  throwIfDiagnostics: false,
).unit;

FunctionDeclaration _function(CompilationUnit unit, String name) => unit
    .declarations
    .whereType<FunctionDeclaration>()
    .singleWhere((declaration) => declaration.name.lexeme == name);

ClassDeclaration _class(CompilationUnit unit, String name) => unit.declarations
    .whereType<ClassDeclaration>()
    .singleWhere((declaration) => declaration.name.lexeme == name);

MethodDeclaration _method(ClassDeclaration declaration, String name) =>
    declaration.members.whereType<MethodDeclaration>().singleWhere(
      (method) => method.name.lexeme == name,
    );

Map<String, String> _namedArguments(ArgumentList arguments) => <String, String>{
  for (final argument in arguments.arguments.whereType<NamedExpression>())
    argument.name.label.name: argument.expression.toSource(),
};

List<MethodInvocation> _namedInvocations(AstNode node, String name) {
  final collector = _NamedInvocationCollector(name);
  node.accept(collector);
  return collector.invocations;
}

List<({AstNode node, ArgumentList arguments})> _creationsNamed(
  AstNode node,
  String name,
) {
  final collector = _NamedCreationCollector(name);
  node.accept(collector);
  return collector.creations;
}

final class _NamedInvocationCollector extends RecursiveAstVisitor<void> {
  _NamedInvocationCollector(this.name);

  final String name;
  final List<MethodInvocation> invocations = <MethodInvocation>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == name) invocations.add(node);
    super.visitMethodInvocation(node);
  }
}

final class _NamedCreationCollector extends RecursiveAstVisitor<void> {
  _NamedCreationCollector(this.name);

  final String name;
  final List<({AstNode node, ArgumentList arguments})> creations =
      <({AstNode node, ArgumentList arguments})>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.toSource() == name) {
      creations.add((node: node, arguments: node.argumentList));
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null && node.methodName.name == name) {
      creations.add((node: node, arguments: node.argumentList));
    }
    super.visitMethodInvocation(node);
  }
}
