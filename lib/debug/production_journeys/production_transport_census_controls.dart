import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import 'production_journey_controller.dart';

/// Production transport census (Wave 4): the original transport census
/// harness's sender loop on production-created services. Alice sends through
/// the production send use case with the production [TransportMetrics]; with
/// the cold lever on, each send first drops the connection to the receiver,
/// as the original does. Bob only reports what production stored.
void bindProductionTransportCensusControls({
  required ProductionJourneyController controller,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepository,
  required ContactRepository contactRepository,
  required MessageRepository messageRepository,
  required TransportMetrics? transportMetrics,
}) {
  if (controller.invocation.scenarioId != transportCensusJourney) return;
  String? condition;
  // The original census passes its own fresh TransportMetrics to every send;
  // so does this one, one per condition, leaving production's counters alone.
  var census = TransportMetrics();
  Map<String, int> nodeBaseline = const {};
  final usedConditions = <String>{};
  final usedIndexes = <int>{};

  Future<ContactModel> preparedContact(Object? peerId) async {
    if (peerId is! String || peerId.isEmpty) {
      throw const FormatException('missing peerId');
    }
    final contact = await contactRepository.getContact(peerId);
    if (contact == null ||
        contact.rendezvous !=
            '/mknoon/production-journey/${controller.invocation.runId}') {
      throw StateError('census peer is not prepared by this invocation');
    }
    return contact;
  }

  // Hole punching and relay upgrades are node events that production records
  // in its own metrics; the census reports their change during a condition.
  Map<String, int> nodeCounters() {
    final tm = transportMetrics;
    if (tm == null) throw StateError('production transport metrics absent');
    return {
      'holePunchAttempts': tm.holePunchAttempts,
      'holePunchSuccesses': tm.holePunchSuccesses,
      'holePunchFailures': tm.holePunchFailures,
      'relayToDirectUpgrades': tm.relayToDirectUpgrades,
    };
  }

  Map<String, Object?> report() {
    final now = nodeCounters();
    return {
      ...censusReport(census),
      for (final entry in now.entries)
        entry.key: entry.value - (nodeBaseline[entry.key] ?? 0),
    };
  }

  controller.bindAction('census_begin', (args) async {
    final name = args['condition'];
    if (controller.invocation.role != 'alice' ||
        name is! String ||
        name.isEmpty ||
        !usedConditions.add(name)) {
      throw StateError('census condition prerequisite rejected');
    }
    await preparedContact(args['peerId']);
    census = TransportMetrics();
    nodeBaseline = nodeCounters();
    condition = name;
    usedIndexes.clear();
    return {'condition': name, ...report()};
  });

  controller.bindAction('census_send', (args) async {
    final index = args['index'];
    final cold = args['cold'];
    final current = condition;
    if (current == null ||
        index is! int ||
        index < 1 ||
        cold is! bool ||
        !usedIndexes.add(index)) {
      throw StateError('census send prerequisite rejected');
    }
    final contact = await preparedContact(args['peerId']);
    if (cold) {
      // Tear down the warm connection so the reuse fast path cannot
      // short-circuit; the original then waits 300 ms before sending.
      try {
        await callP2PPeerDisconnect(bridge, peerId: contact.peerId);
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    final identity = await identityRepository.loadIdentity();
    if (identity == null) throw StateError('production identity missing');
    final timer = Stopwatch()..start();
    final (result, message) = await sendChatMessage(
      p2pService: p2pService,
      messageRepo: messageRepository,
      targetPeerId: contact.peerId,
      text: censusText(controller.invocation.runId, current, index),
      senderPeerId: identity.peerId,
      senderUsername: identity.username,
      bridge: bridge,
      recipientMlKemPublicKey: contact.mlKemPublicKey,
      transportMetrics: census,
    );
    return {
      'condition': current,
      'index': index,
      'cold': cold,
      'result': result.name,
      'messageId': message?.id,
      'transport': message?.transport,
      'elapsedMs': timer.elapsedMilliseconds,
    };
  });

  controller.bindAction('census_report', (_) async {
    if (condition == null) throw StateError('census not begun');
    return {'condition': condition, ...report()};
  });

  controller.bindAction('census_received', (args) async {
    final contact = await preparedContact(args['peerId']);
    final rows = await messageRepository.getMessagesForContact(contact.peerId);
    return {
      'texts': [
        for (final row in rows)
          if (row.isIncoming) row.text,
      ],
    };
  });
}

/// The exact text of census send [index] in [condition] for one run.
String censusText(String runId, String condition, int index) =>
    'census-$runId-$condition-$index';

/// The original harness's sender-vantage census dump of the send-path
/// counters (node counters are added by the caller).
Map<String, Object?> censusReport(TransportMetrics tm) {
  final attempts = tm.attemptCounts();
  final failures = tm.attemptFailureCounts();
  return {
    'totalTransportSamples': tm.totalTransportSamples,
    'transportMix': tm.transportMix(),
    'rungDistribution': tm.rungDistribution(),
    'attemptCounts': attempts,
    'attemptFailureCounts': failures,
    'attemptDelivered': {
      for (final leg in kSendAttemptLegs)
        leg: (attempts[leg] ?? 0) - (failures[leg] ?? 0),
    },
    'latencyByTransport': {
      for (final entry in tm.latencyByTransport().entries)
        entry.key: {
          'n': entry.value.sampleCount,
          'medianMs': entry.value.medianMs,
          'p95Ms': entry.value.p95Ms,
        },
    },
  };
}
