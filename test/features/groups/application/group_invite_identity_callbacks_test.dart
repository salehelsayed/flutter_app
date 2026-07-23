import 'package:flutter_app/features/groups/application/group_invite_identity_callbacks.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/services/fake_p2p_service.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';

class _CountingP2PService extends FakeP2PService {
  int currentStateReadCount = 0;

  _CountingP2PService({required super.initialState});

  @override
  NodeState get currentState {
    currentStateReadCount++;
    return super.currentState;
  }
}

void main() {
  group('buildGroupIdentityCallbacks', () {
    test(
      'cold-start: returns device identity from identity DB even when P2P node has not started yet '
      '(regression: production previously read from p2pService.currentState.peerId which is null '
      'until startNode completes, causing GROUP_INVITE_HANDLE_RECIPIENT_MISMATCH and silent invite drops)',
      () async {
        final identityRepo = FakeIdentityRepository();
        identityRepo.seed(
          FakeIdentityRepository.makeIdentity(
            peerId: '12D3KooWBob',
            mlKemPublicKey: 'bobMlKem64',
            mlKemSecretKey: 'bobSecretKey',
          ),
        );
        final p2pService = FakeP2PService();
        // Sanity: cold-start state has no peerId yet.
        expect(
          p2pService.currentState.peerId,
          anyOf(isNull, isEmpty),
          reason:
              'FakeP2PService default state mirrors NodeState.stopped where '
              'peerId is null until startNode completes',
        );

        final callbacks = buildGroupIdentityCallbacks(
          identityRepo: identityRepo,
          p2pService: p2pService,
        );

        expect(await callbacks.getOwnPeerId(), '12D3KooWBob');
        expect(
          await callbacks.getOwnDeviceId(),
          '12D3KooWBob',
          reason:
              'device id MUST come from identity DB, not from P2P state, '
              'so cold-start invites are not rejected during the startup race',
        );
        expect(await callbacks.getOwnTransportPeerId(), '12D3KooWBob');
        expect(await callbacks.getOwnMlKemPublicKey(), 'bobMlKem64');
        expect(await callbacks.getOwnMlKemSecretKey(), 'bobSecretKey');
        expect(
          await callbacks.getOwnKeyPackageId(),
          defaultGroupWelcomeKeyPackageIdForDevice('12D3KooWBob'),
        );
        expect(await callbacks.getOwnKeyPackagePublicMaterial(), 'bobMlKem64');
      },
    );

    test(
      'returns null device identity when identity is not loaded yet',
      () async {
        final identityRepo = FakeIdentityRepository();
        // No identity seeded.
        final p2pService = FakeP2PService();

        final callbacks = buildGroupIdentityCallbacks(
          identityRepo: identityRepo,
          p2pService: p2pService,
        );

        expect(await callbacks.getOwnPeerId(), isNull);
        expect(await callbacks.getOwnDeviceId(), isNull);
        expect(await callbacks.getOwnTransportPeerId(), isNull);
        expect(await callbacks.getOwnMlKemPublicKey(), isNull);
        expect(await callbacks.getOwnMlKemSecretKey(), isNull);
        expect(await callbacks.getOwnKeyPackageId(), isNull);
        expect(await callbacks.getOwnKeyPackagePublicMaterial(), isNull);
      },
    );

    test(
      'P269 live transport callbacks keep the account identity distinct',
      () async {
        final identityRepo = FakeIdentityRepository();
        identityRepo.seed(
          FakeIdentityRepository.makeIdentity(
            peerId: '12D3KooWAccountBob',
            mlKemPublicKey: 'bobMlKem64',
            mlKemSecretKey: 'bobSecretKey',
          ),
        );
        const liveTransportPeerId = '12D3KooWTransportBobPhone';
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            peerId: liveTransportPeerId,
            isStarted: true,
          ),
        );

        final callbacks = buildGroupIdentityCallbacks(
          identityRepo: identityRepo,
          p2pService: p2pService,
        );

        expect(await callbacks.getOwnPeerId(), '12D3KooWAccountBob');
        expect(await callbacks.getOwnDeviceId(), liveTransportPeerId);
        expect(await callbacks.getOwnTransportPeerId(), liveTransportPeerId);
        expect(
          await callbacks.getOwnKeyPackageId(),
          defaultGroupWelcomeKeyPackageIdForDevice(liveTransportPeerId),
        );
        expect(await callbacks.getOwnKeyPackagePublicMaterial(), 'bobMlKem64');
        expect(
          await callbacks.getOwnPeerId(),
          isNot(await callbacks.getOwnTransportPeerId()),
        );
      },
    );

    test(
      'P269 atomic snapshot reads identity and live node state once with account distinct from transport',
      () async {
        final identityRepo = FakeIdentityRepository()
          ..seed(
            FakeIdentityRepository.makeIdentity(
              peerId: '12D3KooWAccountBob',
              mlKemPublicKey: 'bobMlKem64',
              mlKemSecretKey: 'bobSecretKey',
            ),
          );
        const liveTransportPeerId = '12D3KooWTransportBobPhone';
        final p2pService = _CountingP2PService(
          initialState: const NodeState(
            peerId: liveTransportPeerId,
            isStarted: true,
          ),
        );
        final callbacks = buildGroupIdentityCallbacks(
          identityRepo: identityRepo,
          p2pService: p2pService,
        );

        final snapshot = await callbacks.loadOwnInviteIdentity();

        expect(identityRepo.loadIdentityCallCount, 1);
        expect(p2pService.currentStateReadCount, 1);
        expect(snapshot.accountPeerId, '12D3KooWAccountBob');
        expect(snapshot.deviceId, liveTransportPeerId);
        expect(snapshot.transportPeerId, liveTransportPeerId);
        expect(snapshot.mlKemPublicKey, 'bobMlKem64');
        expect(snapshot.mlKemSecretKey, 'bobSecretKey');
        expect(
          snapshot.keyPackageId,
          defaultGroupWelcomeKeyPackageIdForDevice(liveTransportPeerId),
        );
        expect(snapshot.keyPackagePublicMaterial, 'bobMlKem64');
      },
    );

    test(
      'P269 atomic snapshot ignores a stopped stale node peer and falls back to the account identity',
      () async {
        final identityRepo = FakeIdentityRepository()
          ..seed(
            FakeIdentityRepository.makeIdentity(
              peerId: '12D3KooWAccountBob',
              mlKemPublicKey: 'bobMlKem64',
              mlKemSecretKey: 'bobSecretKey',
            ),
          );
        final p2pService = _CountingP2PService(
          initialState: const NodeState(
            peerId: '12D3KooWStaleStoppedTransport',
            isStarted: false,
          ),
        );
        final callbacks = buildGroupIdentityCallbacks(
          identityRepo: identityRepo,
          p2pService: p2pService,
        );

        final snapshot = await callbacks.loadOwnInviteIdentity();

        expect(identityRepo.loadIdentityCallCount, 1);
        expect(p2pService.currentStateReadCount, 1);
        expect(snapshot.accountPeerId, '12D3KooWAccountBob');
        expect(snapshot.deviceId, '12D3KooWAccountBob');
        expect(snapshot.transportPeerId, '12D3KooWAccountBob');
        expect(
          snapshot.keyPackageId,
          defaultGroupWelcomeKeyPackageIdForDevice('12D3KooWAccountBob'),
        );
      },
    );
  });
}
