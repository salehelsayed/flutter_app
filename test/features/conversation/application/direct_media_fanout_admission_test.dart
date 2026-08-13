import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/direct_event_fanout_contract.dart';
import 'package:flutter_app/features/conversation/application/direct_media_fanout_admission.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

/// The shared 362 admission boundary every fresh direct blob producer consumes.
///
/// These run in the DEFAULT compilation with no `--dart-define`. That is the
/// whole point: the shipped bypass survived because every proof of the fanout
/// guards was compiled only under
/// `MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED`, and no gate script passes
/// a define to `flutter test`. The resolver below reads the repository, never a
/// selector, so its behaviour is identical in both compilations.
void main() {
  const contactPeerId = '12D3KooWContactAccountPeer';

  DirectContactFanoutSnapshot snapshot({
    required bool rosterInitialized,
    List<DirectContactFanoutTargetFact>? targets,
  }) {
    return DirectContactFanoutSnapshot(
      contactAccountPeerId: contactPeerId,
      contactAccountSigningPublicKey: 'account-signing-key',
      rosterInitialized: rosterInitialized,
      targets:
          targets ??
          const <DirectContactFanoutTargetFact>[
            DirectContactFanoutTargetFact(
              peerId: contactPeerId,
              mlKemPublicKey: 'legacy-ml-kem-key',
              isLegacyAccountTarget: true,
              fingerprint: 'legacy-fingerprint',
            ),
          ],
    );
  }

  group('TC-362-06a resolveDirectMediaFanoutAdmission', () {
    test('an INITIALIZED roster refuses a producer with no plural owner, and '
        'never reports the incumbent single-target route', () async {
      final repository = _FanoutCapableRepository(
        result: snapshot(rosterInitialized: true),
      );

      final admission = await resolveDirectMediaFanoutAdmission(
        mediaAttachmentRepository: repository,
        contactAccountPeerId: contactPeerId,
        canServeLinkedFanout: false,
      );

      expect(admission.refuses, isTrue);
      expect(admission.allowsIncumbentSingleTarget, isFalse);
      expect(admission.requiresLinkedFanout, isFalse);
      expect(admission.reason, 'linked_fanout_unavailable');
      expect(
        admission.snapshot,
        isNull,
        reason: 'a refusal carries no stage authority',
      );
      expect(repository.reads, 1, reason: 'the roster is resolved once');
    });

    test('an INITIALIZED roster routes a plural-capable producer to fanout and '
        'hands it the exact snapshot to stage against', () async {
      final live = snapshot(rosterInitialized: true);
      final repository = _FanoutCapableRepository(result: live);

      final admission = await resolveDirectMediaFanoutAdmission(
        mediaAttachmentRepository: repository,
        contactAccountPeerId: contactPeerId,
        canServeLinkedFanout: true,
      );

      expect(admission.requiresLinkedFanout, isTrue);
      expect(admission.refuses, isFalse);
      expect(
        identical(admission.snapshot, live),
        isTrue,
        reason:
            'the caller stages against THIS snapshot; resolving a second one '
            'would re-read the roster after the decision',
      );
    });

    test(
      'an UNINITIALIZED primary roster keeps the incumbent single-target path '
      'for every producer, plural-capable or not',
      () async {
        for (final canServe in const <bool>[false, true]) {
          final repository = _FanoutCapableRepository(
            result: snapshot(rosterInitialized: false),
          );

          final admission = await resolveDirectMediaFanoutAdmission(
            mediaAttachmentRepository: repository,
            contactAccountPeerId: contactPeerId,
            canServeLinkedFanout: canServe,
          );

          expect(
            admission.allowsIncumbentSingleTarget,
            isTrue,
            reason: 'canServeLinkedFanout=$canServe must not change this',
          );
          expect(admission.refuses, isFalse);
          expect(admission.reason, 'roster_uninitialized');
        }
      },
    );

    test('a repository WITHOUT the fanout capability keeps the incumbent path '
        'instead of failing closed', () async {
      final admission = await resolveDirectMediaFanoutAdmission(
        mediaAttachmentRepository: _CapabilityAbsentRepository(),
        contactAccountPeerId: contactPeerId,
        canServeLinkedFanout: false,
      );

      expect(admission.allowsIncumbentSingleTarget, isTrue);
      expect(admission.reason, 'fanout_capability_absent');
    });

    test(
      'a repository that does not implement the fanout interface at all keeps '
      'the incumbent path',
      () async {
        final admission = await resolveDirectMediaFanoutAdmission(
          mediaAttachmentRepository: Object(),
          contactAccountPeerId: contactPeerId,
          canServeLinkedFanout: false,
        );

        expect(admission.allowsIncumbentSingleTarget, isTrue);
        expect(admission.reason, 'fanout_capability_absent');
      },
    );

    test(
      'a null snapshot fails closed because missing blocked or keyless contact '
      'authority is never an uninitialized-roster fact',
      () async {
        final repository = _FanoutCapableRepository(result: null);

        final admission = await resolveDirectMediaFanoutAdmission(
          mediaAttachmentRepository: repository,
          contactAccountPeerId: contactPeerId,
          canServeLinkedFanout: false,
        );

        expect(admission.refuses, isTrue);
        expect(admission.allowsIncumbentSingleTarget, isFalse);
        expect(admission.reason, 'contact_snapshot_absent');
      },
    );

    test('an initialized roster with zero authorized targets refuses even when '
        'the producer has a plural owner', () async {
      final repository = _FanoutCapableRepository(
        result: snapshot(rosterInitialized: true, targets: const []),
      );

      final admission = await resolveDirectMediaFanoutAdmission(
        mediaAttachmentRepository: repository,
        contactAccountPeerId: contactPeerId,
        canServeLinkedFanout: true,
      );

      expect(admission.refuses, isTrue);
      expect(admission.requiresLinkedFanout, isFalse);
      expect(admission.reason, 'zero_authorized_targets');
      expect(admission.snapshot, isNull);
    });

    test('a THROWING snapshot read fails closed — this is the arm where an '
        'initialized roster genuinely could be hidden', () async {
      final repository = _FanoutCapableRepository.throwing();

      final admission = await resolveDirectMediaFanoutAdmission(
        mediaAttachmentRepository: repository,
        contactAccountPeerId: contactPeerId,
        canServeLinkedFanout: true,
      );

      expect(
        admission.refuses,
        isTrue,
        reason:
            'an unreadable roster must never be treated as uninitialized, '
            'even for a plural-capable caller',
      );
      expect(admission.reason, 'snapshot_read_error');
    });

    test('a blank or untrimmed contact peer id fails closed', () async {
      for (final peerId in const <String>['', '  ', ' $contactPeerId']) {
        final repository = _FanoutCapableRepository(
          result: snapshot(rosterInitialized: false),
        );

        final admission = await resolveDirectMediaFanoutAdmission(
          mediaAttachmentRepository: repository,
          contactAccountPeerId: peerId,
          canServeLinkedFanout: true,
        );

        expect(admission.refuses, isTrue, reason: 'peerId=<$peerId>');
        expect(admission.reason, 'contact_peer_id_invalid');
        expect(
          repository.reads,
          0,
          reason: 'an invalid target never reaches the roster read',
        );
      }
    });
  });
}

class _FanoutCapableRepository
    implements OutgoingDirectLinkedMediaBlobFanoutRepository {
  _FanoutCapableRepository({required this.result}) : shouldThrow = false;
  _FanoutCapableRepository.throwing() : result = null, shouldThrow = true;

  final DirectContactFanoutSnapshot? result;
  final bool shouldThrow;
  int reads = 0;

  @override
  bool get supportsDirectLinkedMediaBlobFanout => true;

  @override
  Future<DirectContactFanoutSnapshot?> readDirectContactFanoutSnapshotForMedia(
    String contactAccountPeerId,
  ) async {
    reads++;
    if (shouldThrow) throw StateError('roster unreadable');
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is out of scope');
}

class _CapabilityAbsentRepository
    implements OutgoingDirectLinkedMediaBlobFanoutRepository {
  @override
  bool get supportsDirectLinkedMediaBlobFanout => false;

  @override
  Future<DirectContactFanoutSnapshot?> readDirectContactFanoutSnapshotForMedia(
    String contactAccountPeerId,
  ) async {
    throw StateError('must not be read when the capability is absent');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is out of scope');
}
