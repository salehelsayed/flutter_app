import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'production_journey_controller.dart';
import 'sims_runtime_protocol.dart';

/// Two synthetic contacts and terminal-history rows in the disposable app.
/// Deletion and dialog interactions stay in Maestro. The abort trigger is a
/// causal probe: failing the contact DELETE after its history DELETE must roll
/// both back. UI snapshots alone cannot establish that transaction boundary.
void bindProductionContactDeleteControls({
  required ProductionJourneyController controller,
  required GlobalKey<NavigatorState> navigatorKey,
  required ContactRepository contactRepository,
  required Database database,
}) {
  if (!productionContactDeleteJourneys.contains(
    controller.invocation.scenarioId,
  )) {
    return;
  }
  final run = controller.invocation.runId;
  final peerA = 'fixture-se47-a-$run';
  final peerB = 'fixture-se47-b-$run';
  const trigger = 'se47_fixture_contact_abort';
  final events = <Map<String, Object?>>[];
  var overflow = false;
  final lease = installScopedE2EFlowEventSink((event) {
    final name = event['event'];
    if (!{
      'DELETE_CONTACT_ERROR',
      'DELETE_CONTACT_FINAL_PURGE_COMMITTED',
    }.contains(name)) {
      return;
    }
    if (events.length == 64) {
      overflow = true;
      return;
    }
    final details = event['details'];
    events.add({
      'event': name,
      'fixtureAbort':
          name == 'DELETE_CONTACT_ERROR' &&
          details is Map &&
          '${details['error']}'.contains('se47_fixture_abort'),
    });
  });
  controller.bindDisposer(lease.release);
  controller.bindAction('se47.seed', (_) async {
    if (await contactRepository.getContact(peerA) != null ||
        await contactRepository.getContact(peerB) != null) {
      throw StateError('SE47 fixture must start without its owned contacts.');
    }
    final now = DateTime.now().toUtc();
    final started = now.subtract(const Duration(minutes: 2)).toIso8601String();
    final ended = now.subtract(const Duration(minutes: 1)).toIso8601String();
    for (final (index, peer, username) in [
      (1, peerA, 'FixtureAlpha'),
      (2, peerB, 'FixtureBeta'),
    ]) {
      await contactRepository.addContact(
        ContactModel(
          peerId: peer,
          publicKey: 'fixture-only',
          signature: 'fixture-only',
          rendezvous: '/mknoon/production-journey/$run',
          username: username,
          scannedAt: started,
        ),
      );
      await database.insert('call_history', {
        'call_id': '47000000-0000-4000-8000-00000000000$index',
        'contact_account_peer_id': peer,
        'direction': 'incoming',
        'terminal_reason': 'no_answer',
        'status': 'missed',
        'started_at': started,
        'ended_at': ended,
        'created_at': ended,
        'updated_at': ended,
      });
    }
    return {'peerA': peerA, 'peerB': peerB};
  });
  controller.bindAction('se47.abort_contact_delete', (arguments) async {
    final enabled = arguments['enabled'];
    if (enabled is! bool) {
      throw const FormatException('exact trigger state required');
    }
    await database.execute('DROP TRIGGER IF EXISTS $trigger');
    if (enabled) {
      // runId is a validated runtime token, not arbitrary SQL input.
      await database.execute(
        "CREATE TRIGGER $trigger BEFORE DELETE ON contacts "
        "WHEN OLD.peer_id = '$peerA' BEGIN SELECT RAISE(ABORT, 'se47_fixture_abort'); END",
      );
    }
    final present = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name = ?",
      [trigger],
    );
    if (present.isNotEmpty != enabled) {
      throw StateError('SE47 trigger transition failed');
    }
    return {'enabled': enabled};
  });
  controller.bindAction('se47.snapshot', (_) async {
    if (overflow) throw StateError('SE47 observation capacity exceeded');
    final dialog = <Map<String, Object?>>[];
    final context = navigatorKey.currentState?.context;
    if (context == null) throw StateError('production navigator is absent');
    void visit(Element element) {
      final widget = element.widget;
      if (widget is Text &&
          widget.data?.contains('FixtureAlpha') == true &&
          widget.data != 'FixtureAlpha' &&
          ModalRoute.of(element)?.isCurrent == true) {
        dialog.add({
          'text': widget.data,
          'direction': Directionality.of(element).name,
          'language': Localizations.localeOf(element).languageCode,
        });
      }
      element.visitChildElements(visit);
    }

    (context as Element).visitChildElements(visit);
    return {
      'peerA': peerA,
      'peerB': peerB,
      'contactA': await contactRepository.getContact(peerA) != null,
      'contactB': await contactRepository.getContact(peerB) != null,
      'historyA': await database.query(
        'call_history',
        where: 'contact_account_peer_id = ?',
        whereArgs: [peerA],
        orderBy: 'call_id',
      ),
      'historyB': await database.query(
        'call_history',
        where: 'contact_account_peer_id = ?',
        whereArgs: [peerB],
        orderBy: 'call_id',
      ),
      'events': List<Map<String, Object?>>.of(events),
      'dialog': dialog,
    };
  });
}
