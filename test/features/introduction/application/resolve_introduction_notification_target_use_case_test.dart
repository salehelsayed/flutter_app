import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/application/resolve_introduction_notification_target_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';

void main() {
  late InMemoryIntroductionRepository introRepo;
  late InMemoryContactRepository contactRepo;

  setUp(() {
    introRepo = InMemoryIntroductionRepository();
    contactRepo = InMemoryContactRepository();
  });

  ContactModel makeContact({required String peerId, required String username}) {
    return ContactModel(
      peerId: peerId,
      publicKey: 'pk-$peerId',
      rendezvous: '/rv/$peerId',
      username: username,
      signature: 'sig-$peerId',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> seedIntro({
    String id = 'intro-route',
    String introducerId = 'own-peer',
    String recipientId = 'peer-B',
    String introducedId = 'peer-C',
    IntroductionOverallStatus status = IntroductionOverallStatus.pending,
  }) {
    return introRepo.saveIntroduction(
      IntroductionModel(
        id: id,
        introducerId: introducerId,
        recipientId: recipientId,
        introducedId: introducedId,
        status: status,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
  }

  Future<IntroductionNotificationTargetResolution> resolve({
    required NotificationRouteTarget target,
    String? ownPeerId = 'own-peer',
  }) {
    return resolveIntroductionNotificationTarget(
      routeTarget: target,
      introRepo: introRepo,
      contactRepo: contactRepo,
      loadOwnPeerId: () async => ownPeerId,
    );
  }

  group('resolveIntroductionNotificationTarget', () {
    test(
      'introducer accept routes to recipient thread for either responder',
      () async {
        await seedIntro();
        contactRepo.addTestContact(
          makeContact(peerId: 'peer-B', username: 'Lina'),
        );

        // Same introduction, two different responders: B's own accept and
        // C's accept must BOTH land in the recipient (B) thread. This kills
        // the tempting-but-wrong "open the responder" implementation.
        for (final responder in const ['peer-B', 'peer-C']) {
          final resolution = await resolve(
            target: NotificationRouteTarget.intros(
              messageId: 'intro-route::accept::$responder',
            ),
          );

          expect(
            resolution.target.kind,
            NotificationRouteTargetKind.conversation,
            reason: 'responder $responder',
          );
          expect(
            resolution.target.peerId,
            'peer-B',
            reason: 'responder $responder',
          );
          expect(resolution.contact, isNotNull, reason: 'responder $responder');
          expect(
            resolution.contact!.peerId,
            'peer-B',
            reason: 'responder $responder',
          );
        }
      },
    );

    test(
      'introducer accept resolution carries a machine-readable status context',
      () async {
        await seedIntro(status: IntroductionOverallStatus.pending);
        contactRepo.addTestContact(
          makeContact(peerId: 'peer-B', username: 'Lina'),
        );

        final firstAccept = await resolve(
          target: const NotificationRouteTarget.intros(
            messageId: 'intro-route::accept::peer-B',
          ),
        );
        expect(firstAccept.statusContext, 'b_accept_recorded');

        await seedIntro(status: IntroductionOverallStatus.mutualAccepted);
        final mutualAccept = await resolve(
          target: const NotificationRouteTarget.intros(
            messageId: 'intro-route::accept::peer-C',
          ),
        );
        expect(mutualAccept.statusContext, 'bc_connected');
      },
    );

    test(
      'non-introducer and unresolved response targets fail closed to intros',
      () async {
        await seedIntro();
        contactRepo.addTestContact(
          makeContact(peerId: 'peer-B', username: 'Lina'),
        );

        final failClosedCases = <String, Future<IntroductionNotificationTargetResolution>>{
          // Participant (not the introducer of this intro).
          'participant': resolve(
            target: const NotificationRouteTarget.intros(
              messageId: 'intro-route::accept::peer-C',
            ),
            ownPeerId: 'peer-B',
          ),
          // Missing local identity.
          'missing identity': resolve(
            target: const NotificationRouteTarget.intros(
              messageId: 'intro-route::accept::peer-C',
            ),
            ownPeerId: null,
          ),
          // send / pass actions never open a conversation.
          'send action': resolve(
            target: const NotificationRouteTarget.intros(
              messageId: 'intro-route::send::own-peer',
            ),
          ),
          'pass action': resolve(
            target: const NotificationRouteTarget.intros(
              messageId: 'intro-route::pass::peer-C',
            ),
          ),
          // Intro row missing after drain.
          'missing intro': resolve(
            target: const NotificationRouteTarget.intros(
              messageId: 'intro-unknown::accept::peer-C',
            ),
          ),
          // Unanchored generic intros.
          'unanchored': resolve(
            target: const NotificationRouteTarget.intros(),
          ),
          // Malformed anchor.
          'malformed': resolve(
            target: const NotificationRouteTarget.intros(
              messageId: 'intro-legacy',
            ),
          ),
        };

        for (final entry in failClosedCases.entries) {
          final resolution = await entry.value;
          expect(
            resolution.target.kind,
            NotificationRouteTargetKind.intros,
            reason: entry.key,
          );
          expect(resolution.contact, isNull, reason: entry.key);
        }

        // Missing recipient contact: same intro, introducer identity, but B
        // no longer resolves as a contact -> visible Intros fallback rather
        // than a dead conversation route.
        await seedIntro(id: 'intro-no-contact', recipientId: 'peer-gone');
        final missingContact = await resolve(
          target: const NotificationRouteTarget.intros(
            messageId: 'intro-no-contact::accept::peer-C',
          ),
        );
        expect(
          missingContact.target.kind,
          NotificationRouteTargetKind.intros,
        );
        expect(missingContact.contact, isNull);
      },
    );
  });
}
