import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/application/accept_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/pass_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_outbox_delivery.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';

const _writeFailure = 'fixture outbound persistence unavailable';

/// A repository-write failure before outbound rows can commit. Individual
/// status writes still have the existing fake's real observable commit
/// behavior; the combined response/outbox transaction fails without a commit.
final class _UnavailableOutboxRepository
    extends InMemoryIntroductionRepository {
  @override
  Future<void> saveOutboxDelivery(IntroductionOutboxDelivery delivery) async {
    throw StateError(_writeFailure);
  }

  @override
  Future<bool> saveIntroductionResponseWithOutboxDeliveries({
    required String introductionId,
    required bool isRecipient,
    required IntroductionStatus responseStatus,
    required IntroductionOverallStatus overallStatus,
    required String respondedAt,
    required List<IntroductionOutboxDelivery> deliveries,
  }) async {
    throw StateError(_writeFailure);
  }
}

Future<Map<String, Object?>> _attempt({required bool accept}) async {
  final network = FakeP2PNetwork();
  final p2p = FakeP2PService(peerId: 'fixture-bob', network: network);
  final repository = _UnavailableOutboxRepository();
  final contacts = InMemoryContactRepository();
  final now = DateTime.now().toUtc().toIso8601String();
  contacts.addTestContact(
    ContactModel(
      peerId: 'fixture-alice',
      publicKey: 'fixture-alice-public',
      rendezvous: 'fixture-relay',
      username: 'Fixture Alice',
      signature: 'fixture-signature',
      scannedAt: now,
      mlKemPublicKey: 'fixture-alice-mlkem-public',
    ),
  );
  await repository.saveIntroduction(
    IntroductionModel(
      id: 'fixture-introduction',
      introducerId: 'fixture-alice',
      recipientId: 'fixture-bob',
      introducedId: 'fixture-charlie',
      introducedMlKemPublicKey: 'fixture-charlie-mlkem-public',
      createdAt: now,
    ),
  );
  final bridge = PassthroughCryptoBridge();
  final operation = accept
      ? acceptIntroduction(
          introRepo: repository,
          contactRepo: contacts,
          p2pService: p2p,
          bridge: bridge,
          introductionId: 'fixture-introduction',
          ownPeerId: 'fixture-bob',
          ownUsername: 'Fixture Bob',
        )
      : passIntroduction(
          introRepo: repository,
          contactRepo: contacts,
          p2pService: p2p,
          bridge: bridge,
          introductionId: 'fixture-introduction',
          ownPeerId: 'fixture-bob',
          ownUsername: 'Fixture Bob',
        );
  await expectLater(
    operation,
    throwsA(
      isA<StateError>().having(
        (error) => error.message,
        'injected repository error',
        _writeFailure,
      ),
    ),
  );
  final persisted = await repository.getIntroduction('fixture-introduction');
  final outbound = await repository.loadOutboxDeliveriesForIntroduction(
    'fixture-introduction',
  );
  return {
    'recipientStatus': persisted!.recipientStatus.name,
    'introducedStatus': persisted.introducedStatus.name,
    'overallStatus': persisted.status.name,
    'outboundCarriers': outbound.length,
    'networkDeliveries': network.deliverCallCount,
    'inboxStores': network.storeInInboxCallCount,
  };
}

const _uncommittedResponse = {
  'recipientStatus': 'pending',
  'introducedStatus': 'pending',
  'overallStatus': 'pending',
  'outboundCarriers': 0,
  'networkDeliveries': 0,
  'inboxStores': 0,
};

void main() {
  test(
    'control: accept cannot commit when response outbox persistence fails',
    () async {
      expect(await _attempt(accept: true), _uncommittedResponse);
    },
  );
  test(
    'pass cannot leave a committed consent response without outbound custody',
    () async {
      expect(await _attempt(accept: false), _uncommittedResponse);
    },
  );
}
