import 'package:flutter_app/features/introduction/application/introduction_copy.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  IntroductionModel buildIntroduction({
    required String recipientId,
    required String introducedId,
    String introducerUsername = 'Noor',
    String recipientUsername = 'Lina',
    String introducedUsername = 'Sarah',
    IntroductionOverallStatus status = IntroductionOverallStatus.pending,
  }) {
    return IntroductionModel(
      id: 'intro-1',
      introducerId: 'peer-A',
      introducerUsername: introducerUsername,
      recipientId: recipientId,
      recipientUsername: recipientUsername,
      introducedId: introducedId,
      introducedUsername: introducedUsername,
      status: status,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  group('formatIntroducerIntroductionSystemMessage', () {
    test('uses the introduced username for a single introduction', () {
      expect(
        formatIntroducerIntroductionSystemMessage(
          recipientUsername: 'Lina',
          introducedUsernames: const ['Sarah'],
        ),
        'You introduced Sarah to Lina',
      );
    });

    test('summarizes multiple introduced usernames', () {
      expect(
        formatIntroducerIntroductionSystemMessage(
          recipientUsername: 'Lina',
          introducedUsernames: const ['Sarah', 'Dana', 'Yara', 'Maya'],
        ),
        'You introduced Sarah, Dana, Yara, and 1 more to Lina',
      );
    });
  });

  group('formatIncomingIntroductionMessage', () {
    test('formats the recipient-side message', () {
      final intro = buildIntroduction(
        recipientId: 'peer-B',
        introducedId: 'peer-C',
      );

      expect(
        formatIncomingIntroductionMessage(
          introduction: intro,
          ownPeerId: 'peer-B',
        ),
        'Noor introduced Sarah to you',
      );
    });

    test('formats the introduced-side message', () {
      final intro = buildIntroduction(
        recipientId: 'peer-B',
        introducedId: 'peer-C',
      );

      expect(
        formatIncomingIntroductionMessage(
          introduction: intro,
          ownPeerId: 'peer-C',
        ),
        'Noor introduced you to Lina',
      );
    });

    test('includes the already connected suffix', () {
      final intro = buildIntroduction(
        recipientId: 'peer-B',
        introducedId: 'peer-C',
        status: IntroductionOverallStatus.alreadyConnected,
      );

      expect(
        formatIncomingIntroductionMessage(
          introduction: intro,
          ownPeerId: 'peer-C',
        ),
        'Noor introduced you to Lina — you\'re already connected',
      );
    });
  });

  test('formatMutualAcceptanceSystemMessage names the new contact clearly', () {
    expect(
      formatMutualAcceptanceSystemMessage(
        otherUsername: 'Sarah',
        introducerName: 'Noor',
      ),
      'You and Sarah are now connected — introduced by Noor',
    );
  });
}
