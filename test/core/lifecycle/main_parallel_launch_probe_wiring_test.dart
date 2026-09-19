import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart' as app;

// 164 (cold-start-5): the share-intent probe and the documents-directory probe
// are independent and must overlap (Future.wait). The discriminator also guards
// against a "parallelize by hoisting Firebase back onto the critical path"
// anti-fix: Firebase must stay UNIFORMLY DEFERRED (no eager top-level
// ensureFirebaseReady() await re-introduced).
void main() {
  test(
    'TC-164-03 share-intent probe and docs-dir run concurrently (Future.wait); '
    'Firebase stays uniformly deferred',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final productionSource = await File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsString();

      // (i) the two probes overlap via Future.wait inside the share-launch-probe
      // window, and neither call is awaited inline before the join.
      final probeStart = productionSource.indexOf(
        "StartupTiming.instance.mark('share_launch_probe_begin')",
      );
      final probeEnd = productionSource.indexOf(
        "StartupTiming.instance.mark('share_launch_probe_complete')",
      );
      expect(probeStart, isNonNegative);
      expect(probeEnd, greaterThan(probeStart));
      final probeBlock = productionSource.substring(probeStart, probeEnd);
      expect(
        probeBlock,
        contains('Future.wait'),
        reason: 'the two independent launch probes must overlap',
      );

      final rootBuildIndex = productionSource.indexOf(
        'Future<Widget> _buildRootWidget() async {',
      );
      expect(rootBuildIndex, isNonNegative);
      final preRootBuild = productionSource.substring(0, rootBuildIndex);
      expect(
        preRootBuild,
        isNot(contains('await shareIntentService.captureInitialIntent()')),
        reason: 'the share-intent probe must not be awaited inline before join',
      );
      expect(
        preRootBuild,
        isNot(contains('await getApplicationDocumentsDirectory()')),
        reason: 'the docs-dir probe must not be awaited inline before join',
      );

      // (ii) Firebase stays off the initial critical path. Registration owns
      // one lazy readiness callback; awaiting inside that callback is required
      // for Retry after a failed Firebase initialization.
      final startLiveIndex = productionSource.indexOf(
        'Future<void> startLiveServices()',
      );
      expect(startLiveIndex, isNonNegative);
      final firebaseCalls = _FirebaseStartupCalls(startLiveIndex);
      parseString(content: productionSource).unit.accept(firebaseCalls);
      expect(firebaseCalls.registrationCallbacks, 1);
      expect(
        firebaseCalls.eagerCalls,
        isEmpty,
        reason: 'Firebase must not move onto the initial critical path',
      );

      // (iii) the StartupTiming marks survive.
      expect(
        productionSource,
        contains("StartupTiming.instance.mark('share_launch_probe_begin')"),
      );
      expect(
        productionSource,
        contains("StartupTiming.instance.mark('share_launch_probe_complete')"),
      );
      expect(
        productionSource,
        contains("StartupTiming.instance.mark('documents_dir_ready')"),
      );
    },
  );
  test(
    'TC-164-03 rejects an eager Firebase await adjacent to the lazy gate',
    () {
      const source = r"""
Future<void> prepare() async {
  final registration = PushRegistrationCoordinator(
    ensureReady: () async {
      await ensureFirebaseReady();
      return firebaseReadiness.isReady;
    },
  );
  await ensureFirebaseReady();
  Future<void> startLiveServices() async {}
}
""";
      final calls = _FirebaseStartupCalls(
        source.indexOf('Future<void> startLiveServices'),
      );
      parseString(content: source).unit.accept(calls);
      expect(calls.registrationCallbacks, 1);
      expect(calls.eagerCalls, hasLength(1));
    },
  );

  test('TC-164-03 rejects eagerly invoked or unrelated readiness closures', () {
    for (final callback in [
      'ensureReady: (() async { await ensureFirebaseReady(); return true; })()',
      'other: () async { await ensureFirebaseReady(); return true; }',
    ]) {
      final source =
          'Future<void> prepare() async { '
          'PushRegistrationCoordinator($callback); '
          'Future<void> startLiveServices() async {} }';
      final calls = _FirebaseStartupCalls(
        source.indexOf('Future<void> startLiveServices'),
      );
      parseString(content: source).unit.accept(calls);
      expect(calls.registrationCallbacks, 0);
      expect(calls.eagerCalls, hasLength(1));
    }
  });
}

final class _FirebaseStartupCalls extends RecursiveAstVisitor<void> {
  _FirebaseStartupCalls(this.startLiveOffset);
  final int startLiveOffset;
  final List<int> eagerCalls = <int>[];
  int registrationCallbacks = 0;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'ensureFirebaseReady' &&
        node.offset < startLiveOffset) {
      AstNode? parent = node.parent;
      while (parent != null && parent is! FunctionExpression) {
        parent = parent.parent;
      }
      final argument = parent?.parent;
      final arguments = argument?.parent;
      final constructor = arguments?.parent;
      final isRegistration =
          (constructor is MethodInvocation &&
              constructor.methodName.name == 'PushRegistrationCoordinator') ||
          (constructor is InstanceCreationExpression &&
              constructor.constructorName.toSource() ==
                  'PushRegistrationCoordinator');
      if (argument is NamedExpression &&
          argument.name.label.name == 'ensureReady' &&
          arguments is ArgumentList &&
          isRegistration) {
        registrationCallbacks += 1;
      } else {
        eagerCalls.add(node.offset);
      }
    }
    super.visitMethodInvocation(node);
  }
}
