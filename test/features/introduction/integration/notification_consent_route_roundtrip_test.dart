import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/features/introduction/application/resolve_introduction_notification_target_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/push/application/intro_accept_notification_open_flow.dart';
import 'package:flutter_app/features/push/application/prepare_notification_open_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/intro_test_user.dart';

Future<void> _until(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Introduction did not converge.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

class _Network extends FakeP2PNetwork {
  int sends = 0;
  @override
  Future<bool> deliver(
    String fromPeerId,
    String toPeerId,
    String content, {
    String transport = 'direct',
  }) {
    sends++;
    return super.deliver(fromPeerId, toPeerId, content, transport: transport);
  }
}

class _Fixture {
  _Fixture() {
    a = IntroTestUser.create(
      peerId: 'peer-A',
      username: 'Noor',
      network: network,
      notificationService: aNotifications,
    );
    b = IntroTestUser.create(
      peerId: 'peer-B',
      username: 'Lina',
      network: network,
      notificationService: bNotifications,
    );
    c = IntroTestUser.create(
      peerId: 'peer-C',
      username: 'Omar',
      network: network,
      notificationService: cNotifications,
    );
    a.addContact(b);
    a.addContact(c);
    b.addContact(a);
    c.addContact(a);
    a.start();
    b.start();
    c.start();
  }
  final network = _Network();
  final aNotifications = FakeNotificationService();
  final bNotifications = FakeNotificationService();
  final cNotifications = FakeNotificationService();
  late final IntroTestUser a, b, c;

  Future<String> offer() async {
    final bReceived = b.introListener.introReceivedStream.first;
    final cReceived = c.introListener.introReceivedStream.first;
    final intros = await a.sendIntroductions(
      recipientPeerId: b.peerId,
      friends: [(await a.contactRepo.getContact(c.peerId))!],
    );
    await Future.wait([
      bReceived,
      cReceived,
    ]).timeout(const Duration(seconds: 3));
    await _until(
      () async =>
          bNotifications.shownGeneric.isNotEmpty &&
          cNotifications.shownGeneric.isNotEmpty,
    );
    return intros.single.id;
  }

  void dispose() {
    a.dispose();
    b.dispose();
    c.dispose();
  }
}

Future<({List<String> conversations, int intros})> _tap(
  IntroTestUser user,
  String payload,
) async {
  final conversations = <String>[];
  var intros = 0;
  await routeNotificationPayload(
    payload: payload,
    onBeforeRouteTarget: (target) async {
      final prepared = await prepareNotificationOpen(
        routeTarget: target,
        drainOfflineInbox: user.p2pService.drainOfflineInbox,
        drainGroupOfflineInboxForGroup: (_) async =>
            fail('Unexpected group route'),
      );
      expect(prepared.ok, isTrue);
    },
    onRouteTarget: (target) => openIntroAcceptNotificationRoute(
      routeTarget: target,
      notificationTappedAt: DateTime.now(),
      resolveTarget: (route) => resolveIntroductionNotificationTarget(
        routeTarget: route,
        introRepo: user.introRepo,
        contactRepo: user.contactRepo,
        loadOwnPeerId: () async => user.peerId,
        introStatusChanges: user.introListener.introStatusChangedStream,
      ),
      isConversationAlreadyActive: (_) => false,
      openConversation: (contact, _) async => conversations.add(contact.peerId),
      openIntros: () async {
        intros++;
      },
    ),
  );
  return (conversations: conversations, intros: intros);
}

void main() {
  for (final passed in [false, true]) {
    test('IN-008 actual offer notification tap preserves '
        '${passed ? 'terminal Pass' : 'pending consent'}', () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      final id = await f.offer();
      final offerPayload = f.bNotifications.shownGeneric.single.payload!;
      if (passed) {
        await f.b.passIntro(id);
        await _until(
          () async =>
              (await f.c.introRepo.getIntroduction(id))?.status ==
              IntroductionOverallStatus.passed,
        );
      }
      final before = (await f.b.introRepo.getIntroduction(id))!;
      final sends = f.network.sends;
      final opened = await _tap(f.b, offerPayload);
      final after = (await f.b.introRepo.getIntroduction(id))!;
      expect(opened.intros, 1);
      expect(opened.conversations, isEmpty);
      expect(after.status, before.status);
      expect(after.recipientStatus, before.recipientStatus);
      expect(after.introducedStatus, before.introducedStatus);
      expect(
        after.recipientStatus,
        passed ? IntroductionStatus.passed : IntroductionStatus.pending,
      );
      expect(await f.b.contactRepo.contactExists(f.c.peerId), isFalse);
      expect(
        f.network.sends,
        sends,
        reason: 'A tap must send no consent response.',
      );
    });
  }

  test(
    'IN-001 actual acceptance notification routes introducer to recipient; '
    'IN-008 mutual notification keeps participant consent and destination',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      final id = await f.offer();
      final cSawFirstAccept = f.c.introListener.introStatusChangedStream.first;
      await f.b.acceptIntro(id);
      await cSawFirstAccept.timeout(const Duration(seconds: 3));
      final aAccepted = f.a.introListener.introStatusChangedStream.first;
      final bAccepted = f.b.introListener.introStatusChangedStream.first;
      await f.c.acceptIntro(id);
      await Future.wait([
        aAccepted,
        bAccepted,
      ]).timeout(const Duration(seconds: 3));
      await _until(
        () async =>
            f.aNotifications.shownGeneric.isNotEmpty &&
            f.bNotifications.shownGeneric.length == 2,
      );
      final aSends = f.network.sends;
      final introducer = await _tap(
        f.a,
        f.aNotifications.shownGeneric.last.payload!,
      );
      expect(
        introducer.conversations,
        [f.b.peerId],
        reason: 'Introducer destination is recipient B, not accepting peer C.',
      );
      expect(introducer.intros, 0);
      expect(f.network.sends, aSends);
      expect(
        (await f.b.introRepo.getIntroduction(id))?.recipientStatus,
        IntroductionStatus.accepted,
      );

      // Explicit consent creates the contact. The later notification tap must
      // not perform that mutation a second time or open the introducer's route.
      final before = (await f.b.introRepo.getIntroduction(id))!;
      expect(before.status, IntroductionOverallStatus.mutualAccepted);
      final sends = f.network.sends;
      final contacts = await f.b.contactRepo.getContactCount();
      final participant = await _tap(
        f.b,
        f.bNotifications.shownGeneric.last.payload!,
      );
      expect(participant.intros, 1);
      expect(participant.conversations, isEmpty);
      expect((await f.b.introRepo.getIntroduction(id))?.status, before.status);
      expect(await f.b.contactRepo.getContactCount(), contacts);
      expect(f.network.sends, sends);
    },
  );
}
