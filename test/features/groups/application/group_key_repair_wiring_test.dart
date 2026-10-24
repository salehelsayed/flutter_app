import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Slice-2 UDM-G — source-text wiring lock (mirrors plan 120 §G1, see
/// `test/core/lifecycle/main_replay_disposition_wiring_test.dart`).
///
/// UDM-G threads a SENDER-CAPABLE key-repair request closure
/// (`requestGroupKeyRepairViaSender`) into every foreground group listener /
/// use-case site so an undecryptable group message can trigger a real
/// `group_key_repair_request` send back to the author. The shared route-target
/// helper also serves foreground notification opens; its optional log-only
/// fallback is covered by behavioral route-target tests.
///
/// Every behavioral UDM-G test injects its OWN spy closure into the listeners,
/// so the production-bootstrap wiring is never exercised. A future
/// "partial swap" regression — e.g. flipping ONE of the ~6 production sites to
/// the log-only `emitGroupKeyRepairRequest`, or dropping the `MyApp(...)`
/// thread — would leave the whole behavioral suite green. This lock reads the
/// production source as a STRING (no app boot) and asserts the wiring tokens.
///
/// Resilience: assert on the labelled `requestGroupKeyRepair:` argument token,
/// NOT exact line numbers/whitespace (those drift). An intentional rename
/// requires updating this lock.
void main() {
  Future<String> readSource(String path) => File(path).readAsString();

  const productionPath =
      'lib/app/bootstrap/production_application_bootstrap.dart';
  const routerPath = 'lib/core/services/incoming_message_router.dart';

  // The production sender-capable closure that every FOREGROUND site must wire.
  const senderToken = 'requestGroupKeyRepair: requestGroupKeyRepairViaSender';
  // Legacy log-only fallback; production foreground bootstrap uses the sender.
  const logOnlyToken = 'requestGroupKeyRepair: emitGroupKeyRepairRequest';

  test('production defines the sender-capable key-repair closure', () async {
    final source = await readSource(productionPath);
    expect(
      source,
      contains('Future<void> requestGroupKeyRepairViaSender('),
      reason:
          'the UDM-G sender-capable key-repair closure must remain defined in '
          'the production bootstrap; foreground listeners are wired to it.',
    );
  });

  test(
    'production wires requestGroupKeyRepairViaSender at all 7 foreground sites',
    () async {
      final source = await readSource(productionPath);

      // 6 listener/use-case wiring sites + 1 MyApp(...) thread = 7 occurrences
      // of the sender-capable token. The listed sites are:
      //   - GroupMessageListener
      //   - GroupKeyUpdateListener
      //   - GroupMembershipUpdateListener
      //   - drainGroupOfflineInbox (dispatcher-overflow recovery)
      //   - drainGroupOfflineInbox (pending-retrier drain)
      //   - drainGroupOfflineInbox (dropped-push full recovery)
      //   - MyApp(...) DI thread
      final count = senderToken.allMatches(source).length;
      expect(
        count,
        7,
        reason:
            'expected exactly 7 sender-capable "$senderToken" wiring sites in '
            'the production bootstrap (6 listener/use-case sites + the MyApp '
            'DI thread). Got $count. A partial swap to the log-only '
            'emitGroupKeyRepairRequest, or an added/removed site, would change '
            'this count — update the lock ONLY for an intentional wiring change.',
      );

      // NONE of the foreground sites may degrade to the log-only closure: the
      // log-only variant belongs to the NSE/background path, not production.
      expect(
        source,
        isNot(contains(logOnlyToken)),
        reason:
            'production foreground wiring must use the sender-capable '
            'requestGroupKeyRepairViaSender; the log-only '
            'emitGroupKeyRepairRequest belongs to the NSE/background path only. '
            'Finding it here is the partial-swap regression UDM-G guards.',
      );
    },
  );

  test(
    'production threads requestGroupKeyRepairViaSender into MyApp(...)',
    () async {
      final source = await readSource(productionPath);
      final myAppStart = source.indexOf('MyApp(');
      expect(
        myAppStart,
        isNonNegative,
        reason: 'expected the production MyApp(...) constructor call',
      );
      // Slice from the MyApp( call to end-of-file and assert the thread is
      // present inside the constructor argument list.
      final myAppBlock = source.substring(myAppStart);
      expect(
        myAppBlock,
        contains(senderToken),
        reason:
            'MyApp(...) must receive requestGroupKeyRepair: '
            'requestGroupKeyRepairViaSender so the widget-tree group flows '
            'inherit the sender-capable key-repair closure.',
      );
    },
  );

  // The shared route-target helper serves foreground MyApp/StartupRouter.
  // Its active sender and legacy log-only fallback are exercised with actual
  // missing-key inbox replays in prepare_notification_route_target_use_case_test.

  test(
    'incoming_message_router routes the group_key_repair_request type',
    () async {
      final source = await readSource(routerPath);
      expect(
        source,
        contains("case 'group_key_repair_request':"),
        reason:
            'incoming_message_router.dart must route the '
            "'group_key_repair_request' wire type so a peer's repair request "
            'reaches the responder; without this case the UDM-G round-trip '
            'is silently dropped.',
      );
    },
  );
}
