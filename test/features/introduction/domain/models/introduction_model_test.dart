import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IntroductionModel.deriveStatus', () {
    final freshCreatedAt = DateTime.now().toUtc().toIso8601String();

    test('returns mutualAccepted when both statuses are accepted', () {
      final result = IntroductionModel.deriveStatus(
        recipientStatus: IntroductionStatus.accepted,
        introducedStatus: IntroductionStatus.accepted,
        createdAt: freshCreatedAt,
      );
      expect(result, IntroductionOverallStatus.mutualAccepted);
    });

    test('returns passed when recipient passed', () {
      final result = IntroductionModel.deriveStatus(
        recipientStatus: IntroductionStatus.passed,
        introducedStatus: IntroductionStatus.pending,
        createdAt: freshCreatedAt,
      );
      expect(result, IntroductionOverallStatus.passed);
    });

    test('returns passed when introduced passed', () {
      final result = IntroductionModel.deriveStatus(
        recipientStatus: IntroductionStatus.pending,
        introducedStatus: IntroductionStatus.passed,
        createdAt: freshCreatedAt,
      );
      expect(result, IntroductionOverallStatus.passed);
    });

    test('returns expired when createdAt > 30 days ago', () {
      final oldDate =
          DateTime.now().toUtc().subtract(const Duration(days: 31));
      final result = IntroductionModel.deriveStatus(
        recipientStatus: IntroductionStatus.pending,
        introducedStatus: IntroductionStatus.pending,
        createdAt: oldDate.toIso8601String(),
      );
      expect(result, IntroductionOverallStatus.expired);
    });

    test('returns pending for fresh pending intro', () {
      final result = IntroductionModel.deriveStatus(
        recipientStatus: IntroductionStatus.pending,
        introducedStatus: IntroductionStatus.pending,
        createdAt: freshCreatedAt,
      );
      expect(result, IntroductionOverallStatus.pending);
    });
  });

  group('fromMap / toMap round-trip', () {
    final now = DateTime.now().toUtc().toIso8601String();

    final map = {
      'id': 'intro-123',
      'introducer_id': 'peer-A',
      'recipient_id': 'peer-B',
      'introduced_id': 'peer-C',
      'recipient_status': 'accepted',
      'introduced_status': 'pending',
      'status': 'pending',
      'created_at': now,
      'recipient_responded_at': now,
      'introduced_responded_at': null,
      'introducer_username': 'Alice',
      'recipient_username': 'Bob',
      'introduced_username': 'Charlie',
    };

    test('fromMap correctly deserializes all fields', () {
      final model = IntroductionModel.fromMap(map);

      expect(model.id, 'intro-123');
      expect(model.introducerId, 'peer-A');
      expect(model.recipientId, 'peer-B');
      expect(model.introducedId, 'peer-C');
      expect(model.recipientStatus, IntroductionStatus.accepted);
      expect(model.introducedStatus, IntroductionStatus.pending);
      expect(model.status, IntroductionOverallStatus.pending);
      expect(model.createdAt, now);
      expect(model.recipientRespondedAt, now);
      expect(model.introducedRespondedAt, isNull);
      expect(model.introducerUsername, 'Alice');
      expect(model.recipientUsername, 'Bob');
      expect(model.introducedUsername, 'Charlie');
    });

    test('toMap correctly serializes all fields', () {
      final model = IntroductionModel.fromMap(map);
      final serialized = model.toMap();

      expect(serialized['id'], 'intro-123');
      expect(serialized['introducer_id'], 'peer-A');
      expect(serialized['recipient_id'], 'peer-B');
      expect(serialized['introduced_id'], 'peer-C');
      expect(serialized['recipient_status'], 'accepted');
      expect(serialized['introduced_status'], 'pending');
      expect(serialized['status'], 'pending');
      expect(serialized['created_at'], now);
      expect(serialized['recipient_responded_at'], now);
      expect(serialized['introduced_responded_at'], isNull);
      expect(serialized['introducer_username'], 'Alice');
      expect(serialized['recipient_username'], 'Bob');
      expect(serialized['introduced_username'], 'Charlie');
    });
  });

  group('copyWith', () {
    test('returns modified copy with updated fields', () {
      final model = IntroductionModel(
        id: 'intro-1',
        introducerId: 'peer-A',
        recipientId: 'peer-B',
        introducedId: 'peer-C',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );

      final updated = model.copyWith(
        recipientStatus: IntroductionStatus.accepted,
        status: IntroductionOverallStatus.mutualAccepted,
        introducerUsername: 'Alice',
      );

      expect(updated.recipientStatus, IntroductionStatus.accepted);
      expect(updated.status, IntroductionOverallStatus.mutualAccepted);
      expect(updated.introducerUsername, 'Alice');
      // Unchanged fields preserved
      expect(updated.id, 'intro-1');
      expect(updated.introducerId, 'peer-A');
      expect(updated.introducedStatus, IntroductionStatus.pending);
    });
  });

  group('equality', () {
    test('two models with same id are equal', () {
      final now = DateTime.now().toUtc().toIso8601String();
      final a = IntroductionModel(
        id: 'same-id',
        introducerId: 'A',
        recipientId: 'B',
        introducedId: 'C',
        createdAt: now,
      );
      final b = IntroductionModel(
        id: 'same-id',
        introducerId: 'X',
        recipientId: 'Y',
        introducedId: 'Z',
        createdAt: now,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('two models with different id are not equal', () {
      final now = DateTime.now().toUtc().toIso8601String();
      final a = IntroductionModel(
        id: 'id-1',
        introducerId: 'A',
        recipientId: 'B',
        introducedId: 'C',
        createdAt: now,
      );
      final b = IntroductionModel(
        id: 'id-2',
        introducerId: 'A',
        recipientId: 'B',
        introducedId: 'C',
        createdAt: now,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('toDbString extensions', () {
    test('IntroductionStatus.toDbString works for all values', () {
      expect(IntroductionStatus.pending.toDbString(), 'pending');
      expect(IntroductionStatus.accepted.toDbString(), 'accepted');
      expect(IntroductionStatus.passed.toDbString(), 'passed');
    });

    test('IntroductionOverallStatus.toDbString works for all values', () {
      expect(IntroductionOverallStatus.pending.toDbString(), 'pending');
      expect(
          IntroductionOverallStatus.mutualAccepted.toDbString(),
          'mutual_accepted');
      expect(IntroductionOverallStatus.passed.toDbString(), 'passed');
      expect(IntroductionOverallStatus.expired.toDbString(), 'expired');
    });
  });
}
