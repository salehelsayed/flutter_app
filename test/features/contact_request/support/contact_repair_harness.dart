import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/push/domain/received_wake_token_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/ed25519_contact_request_crypto.dart';

/// Shared Task 12b fixtures: a real production-schema account database, real
/// Ed25519 identities, and a test-side wire builder that is independent of
/// the production sender, so adversarial envelopes can be forged.

const repairRendezvous = '/dns4/relay.example/tcp/4001/p2p/relay';

Future<Database> openRepairTestDatabase([String path = inMemoryDatabasePath]) {
  sqfliteFfiInit();
  return databaseFactoryFfiNoIsolate.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: currentIdentityDatabaseVersion,
      singleInstance: false,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
    ),
  );
}

ContactRepositoryImpl databaseContactRepository(Database db) =>
    ContactRepositoryImpl(
      dbLoadAllContacts: () => dbLoadAllContacts(db),
      dbLoadContact: (peerId) => dbLoadContact(db, peerId),
      dbUpsertContact: (row) => dbUpsertContact(db, row),
      dbDeleteContact: (peerId) => dbDeleteContact(db, peerId),
      dbGetContactCount: () => dbGetContactCount(db),
      dbContactExists: (peerId) => dbContactExists(db, peerId),
      dbArchiveContact: (peerId) => dbArchiveContact(db, peerId),
      dbUnarchiveContact: (peerId) => dbUnarchiveContact(db, peerId),
      dbLoadActiveContacts: () => dbLoadActiveContacts(db),
      dbLoadArchivedContacts: () => dbLoadArchivedContacts(db),
      dbBlockContact: (peerId) => dbBlockContact(db, peerId),
      dbUnblockContact: (peerId) => dbUnblockContact(db, peerId),
      dbDismissIntroBanner: (peerId) => dbDismissIntroBanner(db, peerId),
      dbSetIntrosSentAt: (peerId, timestamp) =>
          dbSetIntrosSentAt(db, peerId, timestamp),
    );

ContactModel contactFor(
  TestEd25519Identity identity, {
  String? mlKem,
  String? publicKey,
  String scannedAt = '2026-01-01T00:00:00.000Z',
}) => ContactModel(
  peerId: identity.peerId,
  publicKey: publicKey ?? identity.publicKey,
  rendezvous: repairRendezvous,
  username: 'user',
  signature: 'qr-sig',
  scannedAt: scannedAt,
  mlKemPublicKey: mlKem,
);

final class InMemoryReceivedWakeTokens implements ReceivedWakeTokenStore {
  final Map<String, Map<String, String>> tokens =
      <String, Map<String, String>>{};

  @override
  Future<Map<String, String>?> readTokenFor(String peerId) async =>
      tokens[peerId] == null ? null : Map<String, String>.of(tokens[peerId]!);

  @override
  Future<void> writeTokenFor(String peerId, String token, String ts) async =>
      tokens[peerId] = <String, String>{'tok': token, 'ts': ts};

  @override
  Future<void> removeTokenFor(String peerId) async => tokens.remove(peerId);

  @override
  Future<void> clear() async => tokens.clear();
}

/// Builds one v2 contact-request message the way an (honest or forging)
/// sender would.
///
/// [signedControl] is signed; [deliveredControl] (default: the same) is what
/// the plaintext carries, so a test can strip or alter a signed marker.
Future<ChatMessage> buildRepairWire({
  required Ed25519ContactRequestCryptoBus bus,
  required TestEd25519Identity signer,
  required String recipientPublicKey,
  String? claimedPeerId,
  String? claimedPublicKey,
  Map<String, Object>? signedControl,
  Object? deliveredControl = _sameAsSigned,
  String? msgId,
  String? outerTs,
  String intent = 'new_request',
  String? mlKem,
  String? ts,
  String? wakeToken,
  CallWakeHandleGrant? callWakeHandle,
  String? callWakeReceiptChallenge,
  String? from,
  String? confirmNonce,
}) async {
  final unsigned = SplayTreeMap<String, dynamic>.from(<String, dynamic>{
    'mlkem': ?mlKem,
    'ns': claimedPeerId ?? signer.peerId,
    'pk': claimedPublicKey ?? signer.publicKey,
    'rv': repairRendezvous,
    'ts': ts ?? DateTime.now().toUtc().toIso8601String(),
    'un': 'user',
    if (callWakeHandle != null) 'cwh': callWakeHandle.toCanonicalMap(),
    'cwr': ?callWakeReceiptChallenge,
    'wt': ?wakeToken,
    if (signedControl != null)
      'cr': SplayTreeMap<String, Object>.from(signedControl),
  });
  final signature = signer.signBase64(jsonEncode(unsigned));
  final delivered = SplayTreeMap<String, dynamic>.from(unsigned)..remove('cr');
  final control = identical(deliveredControl, _sameAsSigned)
      ? signedControl
      : deliveredControl;
  if (control != null) delivered['cr'] = control;
  delivered['sig'] = signature;

  final id = msgId ?? (signedControl?['id'] as String?) ?? _nextOuterId();
  final outer = outerTs ?? DateTime.now().toUtc().toIso8601String();
  final sealing = Ed25519ContactRequestBridge(bus);
  final sealed =
      jsonDecode(
            await sealing.send(
              jsonEncode(<String, Object>{
                'cmd': 'contactrequest.encrypt',
                'payload': <String, Object>{
                  'recipientPublicKey': recipientPublicKey,
                  'plaintext': jsonEncode(delivered),
                  'msgId': id,
                  'ts': outer,
                },
              }),
            ),
          )
          as Map<String, dynamic>;
  return ChatMessage(
    from: from ?? claimedPeerId ?? signer.peerId,
    to: 'self',
    content: jsonEncode(<String, Object>{
      'type': 'contact_request',
      'version': '2',
      'intent': intent,
      'msgId': id,
      'ts': outer,
      'encrypted': <String, Object>{
        'ephemeralPublicKey': sealed['ephemeralPublicKey'] as String,
        'ciphertext': sealed['ciphertext'] as String,
        'nonce': sealed['nonce'] as String,
      },
    }),
    timestamp: outer,
    isIncoming: true,
    confirmNonce: confirmNonce,
  );
}

const Object _sameAsSigned = Object();

var _outerIds = 0;
String _nextOuterId() {
  final n = (_outerIds++).toRadixString(16).padLeft(12, '0');
  return 'aaaaaaaa-0000-4000-8000-$n';
}

var _controlIds = 0;

/// A fresh, valid UUID-v4 operation ID.
String nextControlId() {
  final n = (_controlIds++).toRadixString(16).padLeft(12, '0');
  return 'cccccccc-0000-4000-8000-$n';
}

Map<String, Object> newRequestControl({required String to, String? id}) =>
    <String, Object>{
      'v': 1,
      'kind': 'new_request',
      'id': id ?? nextControlId(),
      'to': to,
    };

Map<String, Object> repairReplyControl({
  required String to,
  required String replyTo,
  String? id,
}) => <String, Object>{
  'v': 1,
  'kind': 'repair_reply',
  'id': id ?? nextControlId(),
  'to': to,
  'replyTo': replyTo,
};
