import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../features/conversation/domain/repositories/fake_message_repository.dart';
import '../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../bridge/fake_bridge.dart';
import 'fake_p2p_service.dart';

void main() {
  for (final owner in ['full', 'resume', 'group', 'startup']) {
    test('BL-12 retains key arrival through $owner recovery', () {
      fakeAsync((async) {
        final keys = StreamController<void>.broadcast();
        final service = FakeP2PService();
        final held = Completer<int>();
        var externalRecovery = owner == 'resume';
        var attempts = 0;
        var active = 0;
        var maxActive = 0;
        var unacked = 0;
        final retrier = PendingMessageRetrier(
          p2pService: service,
          messageRepo: FakeMessageRepository(),
          identityRepo: FakeIdentityRepository(),
          contactRepo: FakeContactRepository(),
          bridge: FakeBridge(),
          contactKeyUpdatedSignal: keys.stream,
          retryDebounce: const Duration(milliseconds: 1),
          isExternalRecoveryInProgressFn: () =>
              externalRecovery || groupRecoveryGate.isActive,
          retryFailedMessagesOverride: () async {
            attempts++;
            active++;
            if (active > maxActive) maxActive = active;
            if (owner == 'full' && attempts == 1) await held.future;
            active--;
            return 0;
          },
          retryUnackedMessagesOverride: () async {
            unacked++;
            return 0;
          },
        );
        if (owner != 'startup') retrier.start();
        if (owner == 'full') {
          service.emitState(
            const NodeState(
              isStarted: true,
              peerId: 'self',
              circuitAddresses: ['/relay'],
            ),
          );
          async.elapse(const Duration(milliseconds: 2));
          expect(attempts, 1);
        }
        if (owner == 'group') groupRecoveryGate.begin();
        keys.add(null);
        keys.add(null);
        async.flushMicrotasks();
        expect(attempts, owner == 'full' ? 1 : 0);
        switch (owner) {
          case 'full':
            held.complete(0);
          case 'resume':
            externalRecovery = false;
            retrier.retryPendingContactKeyUpdates();
          case 'group':
            groupRecoveryGate.end();
          case 'startup':
            retrier.start();
        }
        async.flushMicrotasks();
        expect(attempts, owner == 'full' ? 2 : 1);
        expect(maxActive, 1);
        expect(unacked, owner == 'full' ? 1 : 0);
        retrier.dispose();
        keys.add(null);
        async.flushMicrotasks();
        expect(attempts, owner == 'full' ? 2 : 1);
        unawaited(keys.close());
        service.dispose();
        groupRecoveryGate.resetForTest();
        async.flushMicrotasks();
      });
    });
  }
}
