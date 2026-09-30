import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

final class _GraphConstructionVisitor extends RecursiveAstVisitor<void> {
  final errors = <String>[];
  bool forbidden(String type) =>
      type.endsWith('RepositoryImpl') ||
      type.endsWith('MessageListener') ||
      {
        'FakeNotificationService',
        'FlutterNotificationService',
        'GoBridgeClient',
        'RecordingGoBridgeClient',
        'P2PServiceImpl',
        'MyApp',
        'ProviderScope',
        'ActiveConversationTracker',
        'TrackerBackedAppVisibility',
        'IncomingMessageRouter',
        'DeliveryReceiptListener',
        'GroupKeyUpdateListener',
        'GroupMembershipUpdateListener',
        'GroupInviteListener',
        'GroupMultiDeviceTestStack',
        'InMemoryPendingGroupInviteRepository',
        'setupGroupMultiDeviceStack',
      }.contains(type);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.name.lexeme;
    if (forbidden(type)) errors.add(type);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Parsing without type resolution can represent an implicit constructor
    // as an invocation. Cover prefixed calls and named factories as well.
    final target = node.target;
    for (final name in [
      node.methodName.name,
      if (target is SimpleIdentifier) target.name,
      if (target is PrefixedIdentifier) target.identifier.name,
    ]) {
      if (forbidden(name)) errors.add(name);
    }
    super.visitMethodInvocation(node);
  }
}

void main() {
  test('ordinary startup retains the production invitation delivery owner', () {
    final source = File('lib/app/application_root.dart').readAsStringSync();
    final startup = source.substring(source.indexOf('home: StartupRouter('));
    // The named edge is required on the ordinary home route, not merely on
    // notification routes. The device probe exposed missing SQL persistence
    // and an unknown invite status when this edge was absent.
    expect(
      startup,
      contains(
        'groupInviteDeliveryAttemptRepository:\n'
        '              widget.groupInviteDeliveryAttemptRepository,',
      ),
    );
  });

  test(
    'replacement controls do not recreate production graphs or import legacy test stacks',
    () {
      final manifest =
          jsonDecode(
                File('tool/sims/critical_features.json').readAsStringSync(),
              )
              as Map;
      final paths = <String>{
        for (final file
            in Directory('lib/debug/production_journeys')
                .listSync(recursive: true)
                .whereType<File>()
                .where((file) => file.path.endsWith('.dart')))
          file.path,
        for (final capability in manifest['capabilities'] as List)
          if ((capability['id'] as String).startsWith('production.'))
            for (final argument in capability['command'] as List)
              if (argument is String && argument.endsWith('.dart')) argument,
        'integration_test/support/production_android_journey.dart',
        'integration_test/support/production_journey_peer.dart',
        'integration_test/support/production_shared_xctest.dart',
      };
      for (final path in paths) {
        final file = File(path);
        final unit = parseString(content: file.readAsStringSync()).unit;
        final visitor = _GraphConstructionVisitor();
        unit.accept(visitor);
        expect(visitor.errors, isEmpty, reason: file.path);
        for (final directive
            in unit.directives.whereType<UriBasedDirective>()) {
          final uri = directive.uri.stringValue!;
          if (path.startsWith('lib/')) {
            expect(uri, isNot(contains('integration_test')), reason: file.path);
          }
          expect(uri, isNot(contains('/test/')), reason: file.path);
          expect(
            uri,
            isNot(contains('group_multi_device_real_harness')),
            reason: file.path,
          );
        }
      }
    },
  );

  for (final source in [
    'final value = GroupMessageListener();',
    'final value = new P2PServiceImpl();',
    'final value = legacy.setupGroupMultiDeviceStack();',
    'final value = GroupRepositoryImpl.fromDatabase(db);',
    'final value = legacy.IncomingMessageRouter();',
    'final value = legacy.GroupRepositoryImpl.fromDatabase(db);',
  ]) {
    test('graph guard rejects $source', () {
      final visitor = _GraphConstructionVisitor();
      parseString(content: source).unit.accept(visitor);
      expect(visitor.errors, isNotEmpty);
    });
  }

  test(
    'application-safe protocol preserves the unchanged legacy wire contract',
    () {
      final original = File(
        'integration_test/support/sims_runtime_protocol.dart',
      ).readAsStringSync();
      final replacement = File(
        'lib/debug/production_journeys/sims_runtime_protocol.dart',
      ).readAsStringSync();
      expect(
        replacement.substring(replacement.indexOf("import 'dart:convert';")),
        original,
      );
    },
  );
}
