import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

const _bootstrap = 'lib/app/bootstrap/production_application_bootstrap.dart';
const _background =
    'lib/features/push/application/background_message_handler.dart';
const _directOwner =
    'lib/features/conversation/application/direct_notification_projection_owner.dart';
const _groupOwner =
    'lib/features/groups/application/group_message_listener.dart';
const _groupCanonicalReconciler =
    'lib/core/notifications/group_notification_canonical_reconciler.dart';
const _directCanonicalReconciler =
    'lib/core/notifications/direct_notification_canonical_reconciler.dart';
const _groupReadProjector =
    'lib/core/notifications/group_notification_read_projector.dart';

void main() {
  test(
    'TC-372-07a adopted direct group main background and reconciler effects have one gateway owner and correlation',
    () {
      final calls = _discoverProductionInvocations('maybeShowNotification');
      expect(calls, hasLength(14));

      final adopted = calls
          .where((call) => call.arguments.containsKey('durableEffectContext'))
          .toList(growable: false);
      expect(
        <String, int>{
          for (final path in adopted.map((call) => call.path).toSet())
            path: adopted.where((call) => call.path == path).length,
        },
        <String, int>{_bootstrap: 3, _groupOwner: 3},
      );
      for (final call in adopted) {
        expect(
          call.arguments['durableEffectContext'],
          isNot(anyOf('null', 'const null')),
          reason: call.label,
        );
        expect(call.arguments, contains('appVisibility'), reason: call.label);
        expect(
          call.arguments['notificationEventIdentity'],
          isNotNull,
          reason: call.label,
        );
      }

      final classifiedLegacy = calls
          .where((call) => !call.arguments.containsKey('durableEffectContext'))
          .toList(growable: false);
      expect(classifiedLegacy, hasLength(8));
      expect(
        <String, int>{
          for (final path in classifiedLegacy.map((call) => call.path).toSet())
            path: classifiedLegacy.where((call) => call.path == path).length,
        },
        <String, int>{
          'lib/features/conversation/application/chat_message_listener.dart': 1,
          'lib/features/conversation/application/handle_incoming_reaction_use_case.dart':
              1,
          'lib/features/groups/application/group_message_listener_reaction_ingress_processor.dart':
              1,
          _groupOwner: 3,
          'lib/features/push/application/background_push_notification_fallback.dart':
              2,
        },
        reason:
            'compatibility, unanchored and foreground-push fallbacks cannot synthesize ledger identity',
      );

      final bootstrapSource = File(_bootstrap).readAsStringSync();
      expect(
        _creations(_unit(_bootstrap), 'LocalNotificationLedgerStore'),
        hasLength(1),
      );
      expect(
        bootstrapSource,
        contains('directory: durableNotificationIdRegistry.directory'),
      );
      expect(
        bootstrapSource,
        contains('suspendLocalNotificationLedgerClaims:'),
      );
      expect(bootstrapSource, contains('rebindLocalNotificationLedger:'));
      expect(
        bootstrapSource,
        contains('LocalNotificationPresentationOwner.mainApp'),
      );

      final directSource = File(_directOwner).readAsStringSync();
      expect(
        directSource,
        contains('trySelectNotificationCompletedOutcomeEventKey('),
      );
      expect(
        directSource,
        contains('tryComputeNotificationCompletedOutcomeCorrelation('),
      );
      expect(
        directSource,
        contains("'reactionId': entry.reactionId"),
        reason: 'a bounded direct reaction eventId is never the raw key',
      );

      final groupSource = File(_groupOwner).readAsStringSync();
      expect(
        _creations(_unit(_groupOwner), 'DurableLocalNotificationEffectContext'),
        hasLength(3),
      );
      expect(
        RegExp(
          r'presentationOwner:\s*LocalNotificationPresentationOwner\.mainApp',
        ).allMatches(groupSource),
        hasLength(3),
      );
      expect(
        groupSource,
        contains('tryComputeNotificationCompletedOutcomeCorrelation('),
      );

      // Delivered-card cleanup does not reopen settled Plan-372 records. Keep
      // every approved N11 direct/group compatibility call literal and
      // enumerable so a new native cancel/replace surface fails this census.
      expect(
        <String, int>{
          _directCanonicalReconciler:
              _invocations(
                _unit(_directCanonicalReconciler),
                'cancelConversationNotificationGeneration',
              ).length +
              _invocations(
                _unit(_directCanonicalReconciler),
                'replaceConversationNotificationGeneration',
              ).length,
          _groupCanonicalReconciler:
              _invocations(
                _unit(_groupCanonicalReconciler),
                'cancelConversationNotificationGeneration',
              ).length +
              _invocations(
                _unit(_groupCanonicalReconciler),
                'replaceConversationNotificationGeneration',
              ).length,
          _groupReadProjector: _invocations(
            _unit(_groupReadProjector),
            'cancelConversationNotificationGeneration',
          ).length,
        },
        <String, int>{
          _directCanonicalReconciler: 2,
          _groupCanonicalReconciler: 2,
          _groupReadProjector: 1,
        },
      );
      expect(
        File(_groupCanonicalReconciler).readAsStringSync(),
        contains('approved N11 compatibility path'),
      );

      final backgroundSource = File(_background).readAsStringSync();
      expect(
        _creations(_unit(_background), 'DurableLocalNotificationEffectContext'),
        hasLength(1),
      );
      expect(
        backgroundSource,
        contains(
          'presentationOwner: '
          'LocalNotificationPresentationOwner.androidPushService',
        ),
      );
      expect(
        backgroundSource,
        contains('exact_sql_authority_unavailable'),
        reason: 'authenticated push without exact READY custody is deferred',
      );
      expect(
        backgroundSource,
        allOf(
          contains('expectedEntry: direct'),
          contains("message['sender_peer_id']"),
          contains("reaction?['timestamp']"),
        ),
        reason:
            'background final facts must consume the exact retained READY tuple',
      );
      expect(
        backgroundSource,
        contains('defaultTargetPlatform == TargetPlatform.android'),
        reason: 'IOS_NSE remains reserved for Plan 373',
      );

      final nativeGateways = <({String path, MethodInvocation call})>[
        ..._invocations(
          _unit(_background),
          'runFinalEffect',
        ).map((call) => (path: _background, call: call)),
        ..._invocations(
          _unit('lib/core/notifications/flutter_notification_service.dart'),
          'runFinalEffect',
        ).map(
          (call) => (
            path: 'lib/core/notifications/flutter_notification_service.dart',
            call: call,
          ),
        ),
      ];
      expect(nativeGateways, hasLength(2));
      for (final gateway in nativeGateways) {
        expect(
          _namedArguments(gateway.call.argumentList),
          contains('context'),
          reason: gateway.path,
        );
      }
    },
  );
}

typedef _InvocationRecord = ({
  String path,
  int line,
  Map<String, String> arguments,
  String label,
});

List<_InvocationRecord> _discoverProductionInvocations(String name) {
  final result = <_InvocationRecord>[];
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
    if (!source.contains('$name(')) continue;
    final parsed = parseString(
      content: source,
      path: path,
      throwIfDiagnostics: false,
    );
    for (final call in _invocations(parsed.unit, name)) {
      final line = parsed.lineInfo.getLocation(call.offset).lineNumber;
      result.add((
        path: path,
        line: line,
        arguments: _namedArguments(call.argumentList),
        label: '$path:$line',
      ));
    }
  }
  return result;
}

CompilationUnit _unit(String path) => parseString(
  content: File(path).readAsStringSync(),
  path: path,
  throwIfDiagnostics: false,
).unit;

Map<String, String> _namedArguments(ArgumentList arguments) => <String, String>{
  for (final argument in arguments.arguments.whereType<NamedExpression>())
    argument.name.label.name: argument.expression.toSource(),
};

List<MethodInvocation> _invocations(AstNode node, String name) {
  final visitor = _InvocationVisitor(name);
  node.accept(visitor);
  return visitor.calls;
}

List<AstNode> _creations(AstNode node, String name) {
  final visitor = _CreationVisitor(name);
  node.accept(visitor);
  return visitor.nodes;
}

final class _InvocationVisitor extends RecursiveAstVisitor<void> {
  _InvocationVisitor(this.name);

  final String name;
  final List<MethodInvocation> calls = <MethodInvocation>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == name) calls.add(node);
    super.visitMethodInvocation(node);
  }
}

final class _CreationVisitor extends RecursiveAstVisitor<void> {
  _CreationVisitor(this.name);

  final String name;
  final List<AstNode> nodes = <AstNode>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.toSource() == name) nodes.add(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null && node.methodName.name == name) nodes.add(node);
    super.visitMethodInvocation(node);
  }
}
