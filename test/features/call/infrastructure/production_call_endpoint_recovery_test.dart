import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/domain/received_call_wake_handle_store.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_app/features/call/infrastructure/production_call_endpoint_resolution.dart';
import 'package:flutter_test/flutter_test.dart';

const _now = 2000000;
const _account = 'remote-account';
const _device = 'remote-device';

void main() {
  for (final denial in [
    'not-accepted',
    'blocked',
    'no-device',
    'unlinked',
    'expired-wake',
    'wrong-wake-device',
    'wrong-wake-epoch',
  ]) {
    test('BL26-HA local $denial refuses before remote lookup', () async {
      final authority = _Authority();
      final roster = _Roster(denial);
      final wake = _WakeStore(denial);
      Object? failure;
      try {
        await resolveProductionCallEndpoint(
          contactAccountPeerId: _account,
          resolver: CallEndpointResolver(
            nowMs: () => _now,
            verifyEndpointSignature: (_, _) async => true,
          ),
          rosterProvider: roster,
          authorityClient: authority,
          receivedCallWakeHandleStore: wake,
        );
      } catch (error) {
        failure = error;
      }
      expect(failure, isA<CallEndpointResolutionException>());
      expect(
        authority.lookups,
        0,
        reason:
            'Local authority denial must precede any remote wait or fallback',
      );
    });
  }

  test(
    'BL26-HA valid local authority retains signed endpoint resolution',
    () async {
      final authority = _Authority();
      final endpoint = await resolveProductionCallEndpoint(
        contactAccountPeerId: _account,
        resolver: CallEndpointResolver(
          nowMs: () => _now,
          verifyEndpointSignature: (_, key) async => key == 'signing-key',
        ),
        rosterProvider: _Roster('valid'),
        authorityClient: authority,
        receivedCallWakeHandleStore: _WakeStore('valid'),
      );
      expect(authority.lookups, 1);
      expect(endpoint.accountPeerId, _account);
      expect(endpoint.devicePeerId, _device);
      expect(endpoint.deviceKeyEpoch, 1);
      expect(endpoint.capabilities, {'voice_call_v1', 'video_call_v2'});
    },
  );
}

final class _Roster implements CallTrustedRosterProvider {
  _Roster(this.denial);
  final String denial;

  @override
  Future<CallTrustedRosterSnapshot> loadForContact(String account) async =>
      CallTrustedRosterSnapshot(
        contactAccountPeerId: account,
        contactAccepted: denial != 'not-accepted',
        contactBlocked: denial == 'blocked',
        devices: denial == 'no-device'
            ? []
            : [
                TrustedCallDeviceAuthority(
                  accountPeerId: _account,
                  devicePeerId: _device,
                  linked: denial != 'unlinked',
                  deviceKeyEpoch: 1,
                  signingPublicKey: 'signing-key',
                  mlKemPublicKey: 'kem-key',
                  admissionAuthority: (
                    fingerprint: 'friend',
                    relationshipRevision: 1,
                  ),
                ),
              ],
      );

  @override
  Future<TrustedCallDeviceAuthority?> resolveAuthenticatedTransport(
    String peer,
  ) async => null;
}

final class _WakeStore implements ReceivedCallWakeHandleStore {
  _WakeStore(this.denial);
  final String denial;

  @override
  Future<CallWakeHandleGrant?> readForIssuer(String account) async =>
      CallWakeHandleGrant(
        handle: 'fedcba9876543210fedcba9876543210',
        recipientDevicePeerId: denial == 'wrong-wake-device'
            ? 'other-device'
            : _device,
        deviceKeyEpoch: denial == 'wrong-wake-epoch' ? 2 : 1,
        generation: 1,
        issuedAtMs: _now - 1000,
        expiresAtMs: denial == 'expired-wake' ? _now - 1 : _now + 60000,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Authority implements CallAuthorityClient {
  int lookups = 0;

  @override
  Future<SignedCallEndpointRecord?> getEndpoint(String account) async {
    lookups++;
    final record = CallEndpointRecord(
      accountPeerId: account,
      devicePeerId: _device,
      capabilities: const {'voice_call_v1', 'video_call_v2'},
      platform: CallEndpointPlatform.android,
      expiresAtMs: _now + 60000,
      preferenceEpoch: 1,
      deviceKeyEpoch: 1,
      routingHandle: '0123456789abcdef0123456789abcdef',
    );
    return SignedCallEndpointRecord(
      record: record,
      signature: 'c2ln',
      canonicalRecordBase64: 'e30=',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
