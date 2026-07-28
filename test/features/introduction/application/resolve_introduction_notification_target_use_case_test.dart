import 'dart:async';

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
    IntroductionStatus recipientStatus = IntroductionStatus.pending,
    IntroductionStatus introducedStatus = IntroductionStatus.pending,
    IntroductionOverallStatus status = IntroductionOverallStatus.pending,
  }) {
    return introRepo.saveIntroduction(
      IntroductionModel(
        id: id,
        introducerId: introducerId,
        recipientId: recipientId,
        introducedId: introducedId,
        recipientStatus: recipientStatus,
        introducedStatus: introducedStatus,
        status: status,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
  }

  Future<IntroductionNotificationTargetResolution> resolve({
    required NotificationRouteTarget target,
    String? ownPeerId = 'own-peer',
    Stream<IntroductionModel>? introStatusChanges,
    Duration statusConvergenceTimeout = const Duration(seconds: 45),
  }) {
    return resolveIntroductionNotificationTarget(
      routeTarget: target,
      introRepo: introRepo,
      contactRepo: contactRepo,
      loadOwnPeerId: () async => ownPeerId,
      introStatusChanges: introStatusChanges,
      statusConvergenceTimeout: statusConvergenceTimeout,
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

        await seedIntro(
          recipientStatus: IntroductionStatus.accepted,
          introducedStatus: IntroductionStatus.accepted,
          status: IntroductionOverallStatus.mutualAccepted,
        );
        final mutualAccept = await resolve(
          target: const NotificationRouteTarget.intros(
            messageId: 'intro-route::accept::peer-C',
          ),
        );
        expect(mutualAccept.statusContext, 'bc_connected');
      },
    );

    test(
      'exact C anchor waits only for C acceptance and converges to bc_connected',
      () async {
        final statusChanges = StreamController<IntroductionModel>.broadcast();
        addTearDown(statusChanges.close);
        await seedIntro(
          recipientStatus: IntroductionStatus.accepted,
          introducedStatus: IntroductionStatus.pending,
        );
        contactRepo.addTestContact(
          makeContact(peerId: 'peer-B', username: 'Lina'),
        );

        final resolution = await resolve(
          target: const NotificationRouteTarget.intros(
            messageId: 'intro-route::accept::peer-C',
          ),
          introStatusChanges: statusChanges.stream,
          statusConvergenceTimeout: const Duration(seconds: 1),
        );

        expect(resolution.statusContext, 'b_accept_recorded');
        expect(resolution.statusConvergence, isNotNull);

        var completed = false;
        final convergenceFuture = resolution.statusConvergence!.wait().then((
          result,
        ) {
          completed = true;
          return result;
        });

        statusChanges.add(
          IntroductionModel(
            id: 'unrelated-intro',
            introducerId: 'own-peer',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            recipientStatus: IntroductionStatus.accepted,
            introducedStatus: IntroductionStatus.accepted,
            status: IntroductionOverallStatus.mutualAccepted,
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
        statusChanges.add(
          IntroductionModel(
            id: 'intro-route',
            introducerId: 'own-peer',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            recipientStatus: IntroductionStatus.accepted,
            introducedStatus: IntroductionStatus.pending,
            status: IntroductionOverallStatus.pending,
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          completed,
          isFalse,
          reason: 'unrelated and B-only status events cannot satisfy C',
        );

        statusChanges.add(
          IntroductionModel(
            id: 'intro-route',
            introducerId: 'own-peer',
            recipientId: 'peer-B',
            introducedId: 'peer-C',
            recipientStatus: IntroductionStatus.accepted,
            introducedStatus: IntroductionStatus.accepted,
            status: IntroductionOverallStatus.mutualAccepted,
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        final convergence = await convergenceFuture;
        expect(convergence.converged, isTrue);
        expect(convergence.statusContext, 'bc_connected');
        expect(convergence.fallbackReason, isNull);
      },
    );

    test(
      'C-first acceptance is recorded but is not yet bc_connected',
      () async {
        final statusChanges = StreamController<IntroductionModel>.broadcast();
        addTearDown(statusChanges.close);
        await seedIntro(
          recipientStatus: IntroductionStatus.pending,
          introducedStatus: IntroductionStatus.accepted,
          status: IntroductionOverallStatus.pending,
        );
        contactRepo.addTestContact(
          makeContact(peerId: 'peer-B', username: 'Lina'),
        );

        final resolution = await resolve(
          target: const NotificationRouteTarget.intros(
            messageId: 'intro-route::accept::peer-C',
          ),
          introStatusChanges: statusChanges.stream,
        );

        expect(resolution.statusContext, 'b_accept_recorded');
        expect(
          resolution.statusConvergence,
          isNull,
          reason: 'the exact C response is already persisted',
        );
      },
    );

    test(
      'status subscription is armed before the repository re-read',
      () async {
        final statusChanges = StreamController<IntroductionModel>.broadcast(
          sync: true,
        );
        addTearDown(statusChanges.close);
        final pending = IntroductionModel(
          id: 'intro-route',
          introducerId: 'own-peer',
          recipientId: 'peer-B',
          introducedId: 'peer-C',
          recipientStatus: IntroductionStatus.accepted,
          introducedStatus: IntroductionStatus.pending,
          status: IntroductionOverallStatus.pending,
          createdAt: DateTime.now().toUtc().toIso8601String(),
        );
        introRepo = _EmittingIntroductionRepository(
          beforeGet: () {
            statusChanges.add(
              pending.copyWith(
                introducedStatus: IntroductionStatus.accepted,
                status: IntroductionOverallStatus.mutualAccepted,
              ),
            );
          },
        );
        await introRepo.saveIntroduction(pending);
        contactRepo.addTestContact(
          makeContact(peerId: 'peer-B', username: 'Lina'),
        );

        final resolution = await resolve(
          target: const NotificationRouteTarget.intros(
            messageId: 'intro-route::accept::peer-C',
          ),
          introStatusChanges: statusChanges.stream,
          statusConvergenceTimeout: const Duration(seconds: 1),
        );

        final convergence = await resolution.statusConvergence!.wait();
        expect(convergence.converged, isTrue);
        expect(convergence.statusContext, 'bc_connected');
      },
    );

    test(
      'non-introducer and unresolved response targets fail closed to intros',
      () async {
        await seedIntro();
        contactRepo.addTestContact(
          makeContact(peerId: 'peer-B', username: 'Lina'),
        );

        final failClosedCases =
            <String, Future<IntroductionNotificationTargetResolution>>{
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
        expect(missingContact.target.kind, NotificationRouteTargetKind.intros);
        expect(missingContact.contact, isNull);
      },
    );

    test('bare send pass and non-introducer routes never arm a wait', () async {
      final statusChanges = StreamController<IntroductionModel>.broadcast();
      addTearDown(statusChanges.close);
      await seedIntro(
        recipientStatus: IntroductionStatus.accepted,
        introducedStatus: IntroductionStatus.pending,
      );
      contactRepo.addTestContact(
        makeContact(peerId: 'peer-B', username: 'Lina'),
      );

      final cases = [
        await resolve(
          target: const NotificationRouteTarget.intros(),
          introStatusChanges: statusChanges.stream,
        ),
        await resolve(
          target: const NotificationRouteTarget.intros(
            messageId: 'intro-route::send::own-peer',
          ),
          introStatusChanges: statusChanges.stream,
        ),
        await resolve(
          target: const NotificationRouteTarget.intros(
            messageId: 'intro-route::pass::peer-C',
          ),
          introStatusChanges: statusChanges.stream,
        ),
        await resolve(
          target: const NotificationRouteTarget.intros(
            messageId: 'intro-route::accept::peer-C',
          ),
          ownPeerId: 'peer-B',
          introStatusChanges: statusChanges.stream,
        ),
      ];

      for (final resolution in cases) {
        expect(resolution.opensConversation, isFalse);
        expect(resolution.statusConvergence, isNull);
      }
    });
  });
}

class _EmittingIntroductionRepository extends InMemoryIntroductionRepository {
  _EmittingIntroductionRepository({required this.beforeGet});

  final void Function() beforeGet;

  @override
  Future<IntroductionModel?> getIntroduction(String id) {
    beforeGet();
    return super.getIntroduction(id);
  }
}
