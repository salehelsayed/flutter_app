import 'package:flutter_app/features/introduction/application/load_introductions_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/in_memory_introduction_repository.dart';

void main() {
  late InMemoryIntroductionRepository introRepo;
  final now = DateTime.now().toUtc().toIso8601String();

  setUp(() {
    introRepo = InMemoryIntroductionRepository();
  });

  group('loadIntroductionsForUser', () {
    test('returns only pending intros for user', () async {
      await introRepo.saveIntroduction(
        IntroductionModel(
          id: 'i1',
          introducerId: 'peer-A',
          recipientId: 'peer-B',
          introducedId: 'peer-C',
          createdAt: now,
        ),
      );
      await introRepo.saveIntroduction(
        IntroductionModel(
          id: 'i2',
          introducerId: 'peer-A',
          recipientId: 'peer-B',
          introducedId: 'peer-D',
          createdAt: now,
          status: IntroductionOverallStatus.passed,
        ),
      );

      final result = await loadIntroductionsForUser(
        introRepo: introRepo,
        peerId: 'peer-B',
      );

      expect(result, hasLength(1));
      expect(result.first.id, 'i1');
    });

    test('returns intros where user is introduced party', () async {
      await introRepo.saveIntroduction(
        IntroductionModel(
          id: 'i1',
          introducerId: 'peer-A',
          recipientId: 'peer-B',
          introducedId: 'peer-C',
          createdAt: now,
        ),
      );

      final result = await loadIntroductionsForUser(
        introRepo: introRepo,
        peerId: 'peer-C',
      );

      expect(result, hasLength(1));
      expect(result.first.id, 'i1');
    });

    test('returns empty list when no intros exist', () async {
      final result = await loadIntroductionsForUser(
        introRepo: introRepo,
        peerId: 'peer-X',
      );

      expect(result, isEmpty);
    });
  });

  group('groupByIntroducer', () {
    test('groups correctly by introducer ID', () {
      final intros = [
        IntroductionModel(
          id: 'i1',
          introducerId: 'peer-A',
          recipientId: 'peer-B',
          introducedId: 'peer-C',
          createdAt: now,
        ),
        IntroductionModel(
          id: 'i2',
          introducerId: 'peer-A',
          recipientId: 'peer-B',
          introducedId: 'peer-D',
          createdAt: now,
        ),
        IntroductionModel(
          id: 'i3',
          introducerId: 'peer-X',
          recipientId: 'peer-B',
          introducedId: 'peer-E',
          createdAt: now,
        ),
      ];

      final grouped = groupByIntroducer(intros);

      expect(grouped.keys, hasLength(2));
      expect(grouped['peer-A'], hasLength(2));
      expect(grouped['peer-X'], hasLength(1));
    });

    test('empty list returns empty map', () {
      final grouped = groupByIntroducer([]);
      expect(grouped, isEmpty);
    });
  });

  group('foldIntroductionsForReview', () {
    const ownPeerId = 'peer-me';
    const targetPeerId = 'peer-target';

    test(
      'folds two pending rows from different introducers to the same target',
      () {
        final intros = [
          _intro(
            id: 'intro-noor',
            introducerId: 'peer-noor',
            recipientId: ownPeerId,
            introducedId: targetPeerId,
            createdAt: '2026-05-06T10:00:00.000Z',
            introducerUsername: 'Noor',
            introducedUsername: 'Sarah',
          ),
          _intro(
            id: 'intro-layla',
            introducerId: 'peer-layla',
            recipientId: ownPeerId,
            introducedId: targetPeerId,
            createdAt: '2026-05-06T11:00:00.000Z',
            introducerUsername: 'Layla',
            introducedUsername: 'Sarah',
          ),
        ];

        final folded = foldIntroductionsForReview(
          introductions: intros,
          ownPeerId: ownPeerId,
        );

        expect(folded, hasLength(1));
        final item = folded.single;
        expect(item.targetPeerId, targetPeerId);
        expect(
          item.introductionIds,
          unorderedEquals(['intro-noor', 'intro-layla']),
        );
        expect(item.introductions, unorderedEquals(intros));
        expect(
          item.introducerAttributions.map((a) => a.introducerId),
          unorderedEquals(['peer-noor', 'peer-layla']),
        );
        expect(
          item.introducerAttributions.map((a) => a.displayName),
          unorderedEquals(['Noor', 'Layla']),
        );
        expect(
          item.pendingCurrentViewerDecisionIntroIds,
          unorderedEquals(['intro-noor', 'intro-layla']),
        );
        expect(item.hasPendingCurrentViewerDecision, isTrue);
        expect(item.hasCurrentViewerResponded, isFalse);
      },
    );

    test('keeps different target peers separate', () {
      final folded = foldIntroductionsForReview(
        introductions: [
          _intro(
            id: 'intro-sarah',
            introducerId: 'peer-noor',
            recipientId: ownPeerId,
            introducedId: 'peer-sarah',
            createdAt: '2026-05-06T10:00:00.000Z',
            introducedUsername: 'Sarah',
          ),
          _intro(
            id: 'intro-dana',
            introducerId: 'peer-noor',
            recipientId: ownPeerId,
            introducedId: 'peer-dana',
            createdAt: '2026-05-06T11:00:00.000Z',
            introducedUsername: 'Dana',
          ),
        ],
        ownPeerId: ownPeerId,
      );

      expect(
        folded.map((item) => item.targetPeerId),
        unorderedEquals(['peer-sarah', 'peer-dana']),
      );
      final byTarget = {
        for (final item in folded) item.targetPeerId: item.introductionIds,
      };
      expect(byTarget['peer-sarah'], ['intro-sarah']);
      expect(byTarget['peer-dana'], ['intro-dana']);
    });

    test('resolves target from introduced id for recipient viewer', () {
      final folded = foldIntroductionsForReview(
        introductions: [
          _intro(
            id: 'intro-recipient-view',
            introducerId: 'peer-noor',
            recipientId: ownPeerId,
            introducedId: 'peer-sarah',
            createdAt: '2026-05-06T10:00:00.000Z',
            introducedUsername: 'Sarah',
          ),
        ],
        ownPeerId: ownPeerId,
      );

      expect(folded.single.targetPeerId, 'peer-sarah');
      expect(folded.single.targetPeerName, 'Sarah');
    });

    test('resolves target from recipient id for introduced viewer', () {
      final folded = foldIntroductionsForReview(
        introductions: [
          _intro(
            id: 'intro-introduced-view',
            introducerId: 'peer-noor',
            recipientId: 'peer-basma',
            introducedId: ownPeerId,
            createdAt: '2026-05-06T10:00:00.000Z',
            recipientUsername: 'Basma',
          ),
        ],
        ownPeerId: ownPeerId,
      );

      expect(folded.single.targetPeerId, 'peer-basma');
      expect(folded.single.targetPeerName, 'Basma');
    });

    test('newest row drives display fallback without dropping older rows', () {
      final folded = foldIntroductionsForReview(
        introductions: [
          _intro(
            id: 'older-intro',
            introducerId: 'peer-noor',
            recipientId: ownPeerId,
            introducedId: targetPeerId,
            createdAt: '2026-05-06T10:00:00.000Z',
            introducedUsername: 'Older Sarah',
          ),
          _intro(
            id: 'newest-intro',
            introducerId: 'peer-layla',
            recipientId: ownPeerId,
            introducedId: targetPeerId,
            createdAt: '2026-05-06T12:00:00.000Z',
            introducedUsername: '   ',
          ),
        ],
        ownPeerId: ownPeerId,
      );

      final item = folded.single;
      expect(item.introductionIds, ['newest-intro', 'older-intro']);
      expect(item.displaySourceIntroductionId, 'newest-intro');
      expect(item.targetPeerName, isNull);
      expect(item.targetDisplayName, targetPeerId);
    });

    test('preserves factual current-viewer action state ids', () {
      final folded = foldIntroductionsForReview(
        introductions: [
          _intro(
            id: 'pending-intro',
            introducerId: 'peer-noor',
            recipientId: ownPeerId,
            introducedId: targetPeerId,
            createdAt: '2026-05-06T10:00:00.000Z',
          ),
          _intro(
            id: 'accepted-intro',
            introducerId: 'peer-layla',
            recipientId: ownPeerId,
            introducedId: targetPeerId,
            createdAt: '2026-05-06T11:00:00.000Z',
            recipientStatus: IntroductionStatus.accepted,
          ),
          _intro(
            id: 'passed-intro',
            introducerId: 'peer-yara',
            recipientId: ownPeerId,
            introducedId: targetPeerId,
            createdAt: '2026-05-06T12:00:00.000Z',
            recipientStatus: IntroductionStatus.passed,
            status: IntroductionOverallStatus.alreadyConnected,
          ),
        ],
        ownPeerId: ownPeerId,
      );

      final item = folded.single;
      expect(item.pendingCurrentViewerDecisionIntroIds, ['pending-intro']);
      expect(item.acceptedCurrentViewerDecisionIntroIds, ['accepted-intro']);
      expect(item.passedCurrentViewerDecisionIntroIds, ['passed-intro']);
      expect(item.hasPendingCurrentViewerDecision, isTrue);
      expect(item.hasCurrentViewerResponded, isTrue);
    });

    test('projects deserialized persisted rows without mutating raw maps', () {
      final rawRows = [
        IntroductionModel.fromMap(
          _introRow(
            id: 'persisted-1',
            introducerId: 'peer-noor',
            recipientId: ownPeerId,
            introducedId: targetPeerId,
            createdAt: '2026-05-06T10:00:00.000Z',
            introducerUsername: 'Noor',
            introducedUsername: 'Sarah',
          ),
        ),
        IntroductionModel.fromMap(
          _introRow(
            id: 'persisted-2',
            introducerId: 'peer-layla',
            recipientId: ownPeerId,
            introducedId: targetPeerId,
            recipientStatus: 'accepted',
            createdAt: '2026-05-06T11:00:00.000Z',
            introducerUsername: 'Layla',
            introducedUsername: 'Sarah',
          ),
        ),
      ];
      final snapshots = rawRows
          .map((intro) => Map<String, dynamic>.from(intro.toMap()))
          .toList(growable: false);

      final folded = foldIntroductionsForReview(
        introductions: rawRows,
        ownPeerId: ownPeerId,
      );

      expect(rawRows.map((intro) => intro.toMap()).toList(), snapshots);
      expect(folded, hasLength(1));
      expect(
        folded.single.introductionIds,
        unorderedEquals(['persisted-1', 'persisted-2']),
      );
      expect(
        folded.single.introducerAttributions.map((a) => a.displayName),
        unorderedEquals(['Noor', 'Layla']),
      );
      expect(folded.single.pendingCurrentViewerDecisionIntroIds, [
        'persisted-1',
      ]);
      expect(folded.single.acceptedCurrentViewerDecisionIntroIds, [
        'persisted-2',
      ]);
    });
  });

  group('countFoldedPendingIntroductionTargets', () {
    const ownPeerId = 'peer-me';

    test('folds duplicate pending recipient-side targets', () {
      final count = countFoldedPendingIntroductionTargets(
        introductions: [
          _intro(
            id: 'intro-noor',
            introducerId: 'peer-noor',
            recipientId: ownPeerId,
            introducedId: 'peer-sarah',
            createdAt: '2026-05-06T10:00:00.000Z',
          ),
          _intro(
            id: 'intro-layla',
            introducerId: 'peer-layla',
            recipientId: ownPeerId,
            introducedId: 'peer-sarah',
            createdAt: '2026-05-06T11:00:00.000Z',
          ),
        ],
        ownPeerId: ownPeerId,
      );

      expect(count, 1);
    });

    test('folds duplicate pending introduced-side targets', () {
      final count = countFoldedPendingIntroductionTargets(
        introductions: [
          _intro(
            id: 'intro-noor',
            introducerId: 'peer-noor',
            recipientId: 'peer-basma',
            introducedId: ownPeerId,
            createdAt: '2026-05-06T10:00:00.000Z',
          ),
          _intro(
            id: 'intro-layla',
            introducerId: 'peer-layla',
            recipientId: 'peer-basma',
            introducedId: ownPeerId,
            createdAt: '2026-05-06T11:00:00.000Z',
          ),
        ],
        ownPeerId: ownPeerId,
      );

      expect(count, 1);
    });

    test('counts distinct pending counterparties separately', () {
      final count = countFoldedPendingIntroductionTargets(
        introductions: [
          _intro(
            id: 'intro-sarah-noor',
            introducerId: 'peer-noor',
            recipientId: ownPeerId,
            introducedId: 'peer-sarah',
            createdAt: '2026-05-06T10:00:00.000Z',
          ),
          _intro(
            id: 'intro-sarah-layla',
            introducerId: 'peer-layla',
            recipientId: ownPeerId,
            introducedId: 'peer-sarah',
            createdAt: '2026-05-06T11:00:00.000Z',
          ),
          _intro(
            id: 'intro-dana',
            introducerId: 'peer-yara',
            recipientId: ownPeerId,
            introducedId: 'peer-dana',
            createdAt: '2026-05-06T12:00:00.000Z',
          ),
        ],
        ownPeerId: ownPeerId,
      );

      expect(count, 2);
    });

    test(
      'filters non-pending rows while counting one-sided accepted pending rows',
      () {
        final count = countFoldedPendingIntroductionTargets(
          introductions: [
            _intro(
              id: 'intro-accepted-current-viewer',
              introducerId: 'peer-noor',
              recipientId: ownPeerId,
              introducedId: 'peer-accepted',
              recipientStatus: IntroductionStatus.accepted,
              status: IntroductionOverallStatus.pending,
              createdAt: '2026-05-06T10:00:00.000Z',
            ),
            _intro(
              id: 'intro-already-connected',
              introducerId: 'peer-layla',
              recipientId: ownPeerId,
              introducedId: 'peer-already-connected',
              status: IntroductionOverallStatus.alreadyConnected,
              createdAt: '2026-05-06T11:00:00.000Z',
            ),
            _intro(
              id: 'intro-passed',
              introducerId: 'peer-yara',
              recipientId: ownPeerId,
              introducedId: 'peer-passed',
              status: IntroductionOverallStatus.passed,
              createdAt: '2026-05-06T12:00:00.000Z',
            ),
            _intro(
              id: 'intro-expired',
              introducerId: 'peer-maya',
              recipientId: ownPeerId,
              introducedId: 'peer-expired',
              status: IntroductionOverallStatus.expired,
              createdAt: '2026-05-06T13:00:00.000Z',
            ),
            _intro(
              id: 'intro-mutual',
              introducerId: 'peer-rana',
              recipientId: ownPeerId,
              introducedId: 'peer-mutual',
              status: IntroductionOverallStatus.mutualAccepted,
              createdAt: '2026-05-06T14:00:00.000Z',
            ),
          ],
          ownPeerId: ownPeerId,
        );

        expect(count, 1);
      },
    );
  });
}

IntroductionModel _intro({
  required String id,
  required String introducerId,
  required String recipientId,
  required String introducedId,
  required String createdAt,
  IntroductionStatus recipientStatus = IntroductionStatus.pending,
  IntroductionStatus introducedStatus = IntroductionStatus.pending,
  IntroductionOverallStatus status = IntroductionOverallStatus.pending,
  String? introducerUsername,
  String? recipientUsername,
  String? introducedUsername,
}) {
  return IntroductionModel(
    id: id,
    introducerId: introducerId,
    recipientId: recipientId,
    introducedId: introducedId,
    recipientStatus: recipientStatus,
    introducedStatus: introducedStatus,
    status: status,
    createdAt: createdAt,
    introducerUsername: introducerUsername,
    recipientUsername: recipientUsername,
    introducedUsername: introducedUsername,
  );
}

Map<String, dynamic> _introRow({
  required String id,
  required String introducerId,
  required String recipientId,
  required String introducedId,
  required String createdAt,
  String recipientStatus = 'pending',
  String introducedStatus = 'pending',
  String status = 'pending',
  String? introducerUsername,
  String? recipientUsername,
  String? introducedUsername,
}) {
  return {
    'id': id,
    'introducer_id': introducerId,
    'recipient_id': recipientId,
    'introduced_id': introducedId,
    'recipient_status': recipientStatus,
    'introduced_status': introducedStatus,
    'status': status,
    'created_at': createdAt,
    'recipient_responded_at': null,
    'introduced_responded_at': null,
    'introducer_username': introducerUsername,
    'recipient_username': recipientUsername,
    'introduced_username': introducedUsername,
    'introduced_public_key': null,
    'introduced_ml_kem_public_key': null,
    'recipient_public_key': null,
    'recipient_ml_kem_public_key': null,
  };
}
