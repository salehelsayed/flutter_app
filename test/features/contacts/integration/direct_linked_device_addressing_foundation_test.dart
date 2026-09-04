import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/config/direct_linked_devices_flag.dart';
import 'package:flutter_app/core/config/direct_linked_event_fanout_flag.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/direct_event_fanout_contract.dart';
import 'package:flutter_app/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/incoming_ordinary_text_mutation.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/features/conversation/application/direct_event_fanout_coordinator.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_contact_device_bindings_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/112_direct_linked_device_addressing.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/utils/key_conversion.dart';
import 'package:flutter_app/features/contacts/application/direct_contact_device_trust.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/linked_group_bootstrap_service.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/models/pending_sibling_device.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/linked_group_bootstrap_repository.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/qr_code/application/direct_linked_device_qr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// One Ed25519 identity whose peer ID is derived by the REAL production helper.
///
/// Only the signature primitive is faked (see [_FakeSigner]); every peer
/// binding this test exercises is a genuine derivation, so a QR that claims a
/// peer its key does not produce fails here exactly as it would on a device.
class _Identity {
  _Identity(this.label, int seed)
    : publicKey = base64Encode(_deterministicKeyBytes(seed)),
      privateKey = 'priv-$label-$seed';

  final String label;
  final String publicKey;
  final String privateKey;

  String get peerId => ed25519PublicKeyToPeerId(publicKey);
}

Uint8List _deterministicKeyBytes(int seed) {
  // A 32-byte key derived from the seed. Content is irrelevant to the
  // derivation contract; only length and stability matter.
  final digest = sha256.convert(utf8.encode('tc360-key-$seed')).bytes;
  return Uint8List.fromList(digest);
}

/// Models Ed25519 signature semantics without a bridge.
///
/// The invariant that matters is preserved exactly: a signature verifies under
/// a public key IFF it was produced by that key's private half over those exact
/// bytes. Tampering with the body, swapping the two signatures, or omitting one
/// therefore fails here for the same reason it fails on a device.
class _FakeSigner {
  final Map<String, String> _publicKeyForPrivate = <String, String>{};

  void register(_Identity identity) {
    _publicKeyForPrivate[identity.privateKey] = identity.publicKey;
  }

  Future<Map<String, dynamic>> sign(String data, String privateKey) async {
    final publicKey = _publicKeyForPrivate[privateKey];
    if (publicKey == null) {
      return <String, dynamic>{'ok': false, 'errorCode': 'UNKNOWN_KEY'};
    }
    return <String, dynamic>{'ok': true, 'signature': _mac(publicKey, data)};
  }

  Future<bool> verify({
    required String publicKey,
    required String data,
    required String signature,
  }) async => signature == _mac(publicKey, data);

  static String _mac(String publicKey, String data) =>
      'sig:${sha256.convert(utf8.encode('$publicKey\u0000$data'))}';
}

const _now = '2026-08-11T12:00:00.000Z';

DateTime _clock() => DateTime.parse(_now);

Future<Database> _openV112Database() async {
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 112,
      singleInstance: false,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
    ),
  );
}

ContactModel _contact(
  _Identity identity, {
  String username = 'Alice',
  String? mlKemPublicKey = 'legacy-mlkem',
  bool isBlocked = false,
}) {
  return ContactModel(
    peerId: identity.peerId,
    publicKey: identity.publicKey,
    rendezvous: '/dns4/relay.example.com/tcp/443/wss/p2p/relay-id',
    username: username,
    signature: 'sig-${identity.label}',
    scannedAt: _now,
    mlKemPublicKey: mlKemPublicKey,
    isBlocked: isBlocked,
    blockedAt: isBlocked ? _now : null,
  );
}

/// Builds a real dual-signed document through the production builder.
Future<String> _buildDocument({
  required _FakeSigner signer,
  required _Identity account,
  required _Identity transport,
  required String deviceId,
  String mlKem = 'device-mlkem',
  DateTime Function()? now,
}) async {
  final (result, document) = await buildDirectLinkedDeviceQr(
    linkedAuthority: LinkedInstallationAuthoritySnapshot(
      disposition: LinkedInstallationDisposition.active,
      credential: LinkedTransportCredential(
        state: LinkedTransportCredentialState.active,
        accountPeerId: account.peerId,
        accountPublicKey: account.publicKey,
        deviceId: deviceId,
        transportPeerId: transport.peerId,
        transportPublicKey: transport.publicKey,
        transportPrivateKey: transport.privateKey,
        createdAt: _now,
        activatedAt: _now,
      ),
      failClosedReason: null,
    ),
    accountPeerId: account.peerId,
    accountPublicKey: account.publicKey,
    accountPrivateKey: account.privateKey,
    deviceMlKemPublicKey: mlKem,
    callSign: signer.sign,
    selector: const DirectLinkedDeviceSelector.enabled(),
    now: now ?? _clock,
  );
  expect(result, BuildDirectLinkedDeviceQrResult.success);
  return document!;
}

/// Rewrites one signed body field, leaving both signatures untouched.
String _tamperBody(String document, String field, Object? value) {
  final decoded = jsonDecode(document) as Map<String, dynamic>;
  final envelope = Map<String, dynamic>.from(
    decoded['mknoon'] as Map<String, dynamic>,
  );
  final body = Map<String, dynamic>.from(
    envelope['body'] as Map<String, dynamic>,
  );
  body[field] = value;
  envelope['body'] = body;
  return jsonEncode(<String, dynamic>{'mknoon': envelope});
}

String _rewriteEnvelope(
  String document,
  Map<String, Object?> Function(Map<String, dynamic>) rewrite,
) {
  final decoded = jsonDecode(document) as Map<String, dynamic>;
  final envelope = Map<String, dynamic>.from(
    decoded['mknoon'] as Map<String, dynamic>,
  );
  return jsonEncode(<String, dynamic>{'mknoon': rewrite(envelope)});
}

class _BootstrapAuthoringRepository
    implements GroupRepository, LinkedGroupBootstrapRepository {
  _BootstrapAuthoringRepository({
    required this.group,
    required this.members,
    required this.key,
  });

  final GroupModel group;
  final List<GroupMember> members;
  final GroupKeyInfo key;

  GroupMember? committedSelf;
  PendingSiblingDevice? committedIntent;
  GroupPendingBroadcast? committedOutbox;

  @override
  Future<GroupModel?> getGroup(String groupId) async =>
      groupId == group.id ? group : null;

  @override
  Future<List<GroupMember>> getMembers(String groupId) async =>
      groupId == group.id ? List<GroupMember>.of(members) : <GroupMember>[];

  @override
  Future<GroupKeyInfo?> getLatestKey(String groupId) async =>
      groupId == group.id ? key : null;

  @override
  Future<LinkedGroupBootstrapAuthorCommitOutcome>
  commitLinkedGroupBootstrapAuthoring({
    required GroupModel expectedGroup,
    required List<GroupMember> expectedMembers,
    required GroupMember expectedSelfMember,
    required GroupKeyInfo expectedLatestKey,
    required GroupMember updatedSelfMember,
    required PendingSiblingDevice pendingDevice,
    required GroupPendingBroadcast pendingBroadcast,
    required LinkedGroupBootstrapAuthorityGenesis authorityGenesis,
  }) async {
    if (expectedGroup != group ||
        expectedMembers.length != members.length ||
        expectedSelfMember.peerId != members.first.peerId ||
        expectedLatestKey != key) {
      return LinkedGroupBootstrapAuthorCommitOutcome.refusedStateChanged;
    }
    committedSelf = updatedSelfMember;
    committedIntent = pendingDevice;
    committedOutbox = pendingBroadcast;
    return LinkedGroupBootstrapAuthorCommitOutcome.committed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected repository call: $invocation');
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late _FakeSigner signer;
  late _Identity contactAccount;
  late _Identity contactTransport;
  late _Identity ownAccount;

  setUp(() async {
    db = await _openV112Database();
    signer = _FakeSigner();
    contactAccount = _Identity('alice', 1);
    contactTransport = _Identity('alice-device', 2);
    ownAccount = _Identity('self', 3);
    for (final identity in <_Identity>[
      contactAccount,
      contactTransport,
      ownAccount,
    ]) {
      signer.register(identity);
    }
    await dbUpsertContact(db, _contact(contactAccount).toMap());
  });

  tearDown(() async {
    if (db.isOpen) await db.close();
  });

  /// Runs the production parser exactly as the scanner does.
  Future<(ParseDirectLinkedDeviceQrResult, DirectLinkedDeviceQrDocument?)> scan(
    String document, {
    DirectLinkedDeviceSelector selector =
        const DirectLinkedDeviceSelector.enabled(),
    DateTime Function()? now,
  }) {
    return parseDirectLinkedDeviceQr(
      qrString: document,
      ownAccountPeerId: ownAccount.peerId,
      lookupContact: (peerId) async {
        final row = await dbLoadContact(db, peerId);
        return row == null ? null : ContactModel.fromMap(row);
      },
      callVerify: signer.verify,
      selector: selector,
      now: now ?? _clock,
    );
  }

  /// Stages a successfully scanned document through the real repository.
  Future<DirectContactDeviceBindingStageOutcome> stage(
    DirectLinkedDeviceQrDocument document,
  ) {
    return dbStageDirectContactDeviceBinding(
      db,
      contactAccountPeerId: document.accountPeerId,
      accountSigningPublicKey: document.accountPublicKey,
      deviceId: document.deviceId,
      transportPeerId: document.transportPeerId,
      transportPublicKey: document.transportPublicKey,
      deviceMlKemPublicKey: document.deviceMlKemPublicKey,
      stagedAt: _now,
    );
  }

  test(
    'TC-360-02a dual-signed linked-device QR stages only exact known-contact '
    'pending authority',
    () async {
      final contactsBefore = await db.query('contacts');

      // ── Happy path: builder -> scanner -> real repository. ──
      final document = await _buildDocument(
        signer: signer,
        account: contactAccount,
        transport: contactTransport,
        deviceId: 'device-alpha',
      );

      // The document is a NESTED, versioned, purpose-tagged envelope, and the
      // legacy contact parser's required flat fields are absent — so an old
      // parser rejects it outright instead of half-reading it.
      final decoded = jsonDecode(document) as Map<String, dynamic>;
      expect(decoded.keys, <String>['mknoon']);
      final envelope = decoded['mknoon'] as Map<String, dynamic>;
      expect(envelope['purpose'], directLinkedDeviceQrPurpose);
      expect(envelope['version'], directLinkedDeviceQrVersion);
      expect(
        envelope['accountSignature'],
        isNot(envelope['transportSignature']),
      );
      for (final legacyField in const <String>['pk', 'ns', 'rv', 'ts', 'sig']) {
        expect(decoded.containsKey(legacyField), isFalse);
      }
      expect(
        utf8.encode(document).length,
        lessThanOrEqualTo(directLinkedDeviceQrMaxBytes),
      );
      expect(isDirectLinkedDeviceQrDocument(document), isTrue);

      final (result, parsed) = await scan(document);
      expect(result, ParseDirectLinkedDeviceQrResult.success);
      expect(parsed!.deviceId, 'device-alpha');
      expect(parsed.accountPeerId, contactAccount.peerId);
      expect(parsed.transportPeerId, contactTransport.peerId);
      // Both peers are genuinely derived from their carried keys.
      expect(
        ed25519PublicKeyToPeerId(parsed.accountPublicKey),
        parsed.accountPeerId,
      );
      expect(
        ed25519PublicKeyToPeerId(parsed.transportPublicKey),
        parsed.transportPeerId,
      );

      expect(
        await stage(parsed),
        DirectContactDeviceBindingStageOutcome.staged,
      );
      var roster = await dbLoadDirectContactDeviceRoster(
        db,
        contactAccount.peerId,
      );
      expect(roster.pendingBindings, hasLength(1));
      expect(
        roster.activeBindings,
        isEmpty,
        reason: 'a valid scan stages PENDING authority only; it never admits',
      );
      expect(
        roster.metadata.rosterInitialized,
        isFalse,
        reason: 'staging is not a trust decision',
      );

      // Zero contact/ML-KEM mutation from the whole scan+stage path.
      expect(await db.query('contacts'), contactsBefore);

      // ── Fresh-timestamp idempotency: a re-issued QR replays. ──
      final reissued = await _buildDocument(
        signer: signer,
        account: contactAccount,
        transport: contactTransport,
        deviceId: 'device-alpha',
        now: () => DateTime.parse(_now).add(const Duration(hours: 1)),
      );
      expect(reissued, isNot(document));
      final (reissuedResult, reissuedParsed) = await scan(
        reissued,
        now: () => DateTime.parse(_now).add(const Duration(hours: 1)),
      );
      expect(reissuedResult, ParseDirectLinkedDeviceQrResult.success);
      expect(
        await stage(reissuedParsed!),
        DirectContactDeviceBindingStageOutcome.replayed,
        reason:
            'issued-at and both signatures are excluded from the immutable '
            'fingerprint, so a fresh QR is idempotent rather than a second '
            'contradictory binding',
      );
      roster = await dbLoadDirectContactDeviceRoster(db, contactAccount.peerId);
      expect(roster.bindings, hasLength(1));

      // ── One compact refusal matrix. Every case must be ALL-ZERO. ──
      final rosterBefore = await db.query('direct_contact_device_bindings');
      final metadataBefore = await db.query(
        'direct_contact_device_roster_metadata',
      );

      final unknownAccount = _Identity('mallory', 9)..let(signer.register);
      final unknownTransport = _Identity('mallory-device', 10)
        ..let(signer.register);
      final crossedTransport = _Identity('crossed-device', 11)
        ..let(signer.register);

      final refusals = <String, (String, ParseDirectLinkedDeviceQrResult)>{
        'tampered device id': (
          _tamperBody(document, 'deviceId', 'device-forged'),
          ParseDirectLinkedDeviceQrResult.invalidSignature,
        ),
        'tampered transport peer': (
          _tamperBody(document, 'transportPeerId', unknownTransport.peerId),
          ParseDirectLinkedDeviceQrResult.peerDerivationMismatch,
        ),
        'tampered ml-kem key': (
          _tamperBody(document, 'deviceMlKemPublicKey', 'swapped-mlkem'),
          ParseDirectLinkedDeviceQrResult.invalidSignature,
        ),
        'single-signed (account signature duplicated)': (
          _rewriteEnvelope(document, (envelope) {
            return <String, Object?>{
              ...envelope,
              'transportSignature': envelope['accountSignature'],
            };
          }),
          ParseDirectLinkedDeviceQrResult.invalidSignature,
        ),
        // Account signature VALID, transport signature forged. This is the
        // trust-laundering case the dual signature exists for: an account
        // vouching for "some device" proves nothing about which device.
        'account-signed only (transport signature forged)': (
          _rewriteEnvelope(document, (envelope) {
            return <String, Object?>{
              ...envelope,
              'transportSignature': 'sig:forged-transport-half',
            };
          }),
          ParseDirectLinkedDeviceQrResult.invalidSignature,
        ),
        // ...and the mirror: a real device replayed under a forged account.
        'transport-signed only (account signature forged)': (
          _rewriteEnvelope(document, (envelope) {
            return <String, Object?>{
              ...envelope,
              'accountSignature': 'sig:forged-account-half',
            };
          }),
          ParseDirectLinkedDeviceQrResult.invalidSignature,
        ),
        'swapped signatures': (
          _rewriteEnvelope(document, (envelope) {
            return <String, Object?>{
              ...envelope,
              'accountSignature': envelope['transportSignature'],
              'transportSignature': envelope['accountSignature'],
            };
          }),
          ParseDirectLinkedDeviceQrResult.invalidSignature,
        ),
        'unexpected extra body field': (
          _tamperBody(document, 'unexpected', 'value'),
          ParseDirectLinkedDeviceQrResult.malformed,
        ),
        'wrong purpose': (
          _rewriteEnvelope(document, (envelope) {
            return <String, Object?>{...envelope, 'purpose': 'contact_qr'};
          }),
          ParseDirectLinkedDeviceQrResult.malformed,
        ),
        'wrong version': (
          _rewriteEnvelope(document, (envelope) {
            return <String, Object?>{...envelope, 'version': 99};
          }),
          ParseDirectLinkedDeviceQrResult.malformed,
        ),
        'legacy contact QR': (
          jsonEncode(<String, Object?>{
            'ns': contactAccount.peerId,
            'pk': contactAccount.publicKey,
            'rv': '/dns4/relay/tcp/443/p2p/relay',
            'ts': _now,
            'sig': 'legacy-sig',
          }),
          ParseDirectLinkedDeviceQrResult.malformed,
        ),
        'not json': (
          'definitely-not-json',
          ParseDirectLinkedDeviceQrResult.malformed,
        ),
        'oversized': (
          jsonEncode(<String, Object?>{
            'mknoon': <String, Object?>{'padding': 'x' * 5000},
          }),
          ParseDirectLinkedDeviceQrResult.malformed,
        ),
      };

      for (final entry in refusals.entries) {
        final (input, expected) = entry.value;
        final (refusedResult, refusedDocument) = await scan(input);
        expect(refusedResult, expected, reason: entry.key);
        expect(refusedDocument, isNull, reason: entry.key);
      }

      // Unknown contact.
      final unknownDocument = await _buildDocument(
        signer: signer,
        account: unknownAccount,
        transport: unknownTransport,
        deviceId: 'device-unknown',
      );
      expect(
        (await scan(unknownDocument)).$1,
        ParseDirectLinkedDeviceQrResult.unknownContact,
      );

      // Self scan.
      final selfDocument = await _buildDocument(
        signer: signer,
        account: ownAccount,
        transport: crossedTransport,
        deviceId: 'device-self',
      );
      expect(
        (await scan(selfDocument)).$1,
        ParseDirectLinkedDeviceQrResult.selfScan,
      );

      // Selector off.
      expect(
        (await scan(
          document,
          selector: const DirectLinkedDeviceSelector.disabled(),
        )).$1,
        ParseDirectLinkedDeviceQrResult.selectorDisabled,
      );

      // Canonical UTC / injected clock: expiry, future skew, non-UTC.
      expect(
        (await scan(
          document,
          now: () => DateTime.parse(
            _now,
          ).add(directLinkedDeviceQrMaxAge).add(const Duration(minutes: 1)),
        )).$1,
        ParseDirectLinkedDeviceQrResult.expired,
      );
      expect(
        (await scan(
          document,
          now: () => DateTime.parse(_now).subtract(
            directLinkedDeviceQrMaxFutureSkew + const Duration(minutes: 1),
          ),
        )).$1,
        ParseDirectLinkedDeviceQrResult.futureSkew,
      );
      expect(
        (await scan(
          _tamperBody(document, 'issuedAt', '2026-08-11T12:00:00.000+02:00'),
        )).$1,
        ParseDirectLinkedDeviceQrResult.invalidTimestamp,
        reason:
            'the legacy parser\'s permissive timestamp fallback must NOT be '
            'inherited: an unparseable issued-at would otherwise bypass expiry',
      );
      expect(
        (await scan(_tamperBody(document, 'issuedAt', 'not-a-timestamp'))).$1,
        ParseDirectLinkedDeviceQrResult.invalidTimestamp,
      );

      // Blocked contact.
      await dbUpsertContact(
        db,
        _contact(contactAccount, isBlocked: true).toMap(),
      );
      expect(
        (await scan(document)).$1,
        ParseDirectLinkedDeviceQrResult.blockedContact,
      );
      await dbUpsertContact(db, _contact(contactAccount).toMap());

      // Contact account key drift (stale/cross-account document).
      final rotatedAccount = _Identity('alice-rotated', 12)
        ..let(signer.register);
      await dbUpsertContact(db, <String, Object?>{
        ..._contact(contactAccount).toMap(),
        'public_key': rotatedAccount.publicKey,
      });
      expect(
        (await scan(document)).$1,
        ParseDirectLinkedDeviceQrResult.contactKeyMismatch,
      );
      await dbUpsertContact(db, _contact(contactAccount).toMap());

      // Duplicate transport owner: a DIFFERENT device claiming the SAME
      // transport peer refuses at the repository.
      final duplicateTransportDocument = await _buildDocument(
        signer: signer,
        account: contactAccount,
        transport: contactTransport,
        deviceId: 'device-beta',
      );
      final (dupResult, dupParsed) = await scan(duplicateTransportDocument);
      expect(dupResult, ParseDirectLinkedDeviceQrResult.success);
      expect(
        await stage(dupParsed!),
        DirectContactDeviceBindingStageOutcome.refused,
      );

      // Same device, CHANGED immutable material refuses rather than replaces.
      final rotatedDeviceTransport = _Identity('alice-device-2', 13)
        ..let(signer.register);
      final mutatedDocument = await _buildDocument(
        signer: signer,
        account: contactAccount,
        transport: rotatedDeviceTransport,
        deviceId: 'device-alpha',
      );
      final (mutatedResult, mutatedParsed) = await scan(mutatedDocument);
      expect(mutatedResult, ParseDirectLinkedDeviceQrResult.success);
      expect(
        await stage(mutatedParsed!),
        DirectContactDeviceBindingStageOutcome.refused,
      );

      // ── TOCTOU: blocked BETWEEN a successful parse and the stage write. ──
      //
      // The scanner necessarily checks `isBlocked` before it can authenticate a
      // document at all, so that check alone cannot protect the write. Blocking
      // is exactly the signal that the user wants no further authority from
      // this person, so the staging transaction re-reads it.
      final toctouTransport = _Identity('alice-device-toctou', 41)
        ..let(signer.register);
      final toctouDocument = await _buildDocument(
        signer: signer,
        account: contactAccount,
        transport: toctouTransport,
        deviceId: 'device-toctou',
      );
      final (toctouParse, toctouParsed) = await scan(toctouDocument);
      expect(toctouParse, ParseDirectLinkedDeviceQrResult.success);
      // The contact is blocked AFTER the parse succeeded and BEFORE the stage.
      await dbUpsertContact(
        db,
        _contact(contactAccount, isBlocked: true).toMap(),
      );
      expect(
        await stage(toctouParsed!),
        DirectContactDeviceBindingStageOutcome.refused,
        reason:
            'a contact blocked between parse and stage must not acquire a '
            'pending binding',
      );
      await dbUpsertContact(db, _contact(contactAccount).toMap());

      // Every refusal above wrote nothing at all.
      expect(await db.query('direct_contact_device_bindings'), rosterBefore);
      expect(
        await db.query('direct_contact_device_roster_metadata'),
        metadataBefore,
      );
      expect(await db.query('contacts'), contactsBefore);
    },
  );

  test('TC-360-03a direct-device trust owns exact admission revocation and '
      'legacy resolution', () async {
    final authorityChanges = <String>[];
    final trust = DatabaseDirectContactDeviceTrust(
      database: db,
      now: _clock,
      onAuthorityChanged: (contactAccountPeerId) async {
        authorityChanges.add(contactAccountPeerId);
      },
    );

    // Before initialization, resolution is EXACTLY the unchanged legacy
    // ContactModel target.
    var targets = await dbResolveDirectContactDeviceTargets(
      db,
      contactAccountPeerId: contactAccount.peerId,
      legacyMlKemPublicKey: 'legacy-mlkem',
    );
    expect(targets, hasLength(1));
    expect(targets.single.isLegacyAccountTarget, isTrue);
    expect(targets.single.peerId, contactAccount.peerId);

    // Missing legacy ML-KEM is NONDELIVERABLE.
    expect(
      await dbResolveDirectContactDeviceTargets(
        db,
        contactAccountPeerId: contactAccount.peerId,
        legacyMlKemPublicKey: null,
      ),
      isEmpty,
    );

    // Stage one device.
    final document = await _buildDocument(
      signer: signer,
      account: contactAccount,
      transport: contactTransport,
      deviceId: 'device-alpha',
    );
    final (_, parsed) = await scan(document);
    expect(await stage(parsed!), DirectContactDeviceBindingStageOutcome.staged);

    final fingerprint = computeDirectContactDeviceBindingFingerprint(
      contactAccountPeerId: parsed.accountPeerId,
      accountSigningPublicKey: parsed.accountPublicKey,
      deviceId: parsed.deviceId,
      transportPeerId: parsed.transportPeerId,
      transportPublicKey: parsed.transportPublicKey,
      deviceMlKemPublicKey: parsed.deviceMlKemPublicKey,
    );

    // ── Exact-CAS: every wrong belief fails closed. ──
    expect(
      await trust.verifyDevice(
        contactAccountPeerId: contactAccount.peerId,
        deviceId: 'device-alpha',
        expectedFingerprint: 'f' * 64,
        expectedAccountSigningPublicKey: contactAccount.publicKey,
      ),
      isFalse,
      reason: 'stale UI holding the wrong fingerprint cannot decide',
    );
    expect(
      await trust.verifyDevice(
        contactAccountPeerId: contactAccount.peerId,
        deviceId: 'device-alpha',
        expectedFingerprint: fingerprint,
        expectedAccountSigningPublicKey: ownAccount.publicKey,
      ),
      isFalse,
      reason: 'a caller believing the wrong account key cannot decide',
    );
    expect(
      await trust.revokeDevice(
        contactAccountPeerId: contactAccount.peerId,
        deviceId: 'device-alpha',
        expectedFingerprint: fingerprint,
        expectedAccountSigningPublicKey: contactAccount.publicKey,
      ),
      isFalse,
      reason: 'revoke requires an ACTIVE row; pending is not revocable',
    );

    // Contact key drift between render and decision fails closed.
    final rotatedAccount = _Identity('alice-rotated', 21)..let(signer.register);
    await dbUpsertContact(db, <String, Object?>{
      ..._contact(contactAccount).toMap(),
      'public_key': rotatedAccount.publicKey,
    });
    expect(
      await trust.verifyDevice(
        contactAccountPeerId: contactAccount.peerId,
        deviceId: 'device-alpha',
        expectedFingerprint: fingerprint,
        expectedAccountSigningPublicKey: rotatedAccount.publicKey,
      ),
      isFalse,
      reason:
          'the row\'s recorded verified key must still equal the contact\'s '
          'current key, so a rotated account cannot inherit old authority',
    );
    await dbUpsertContact(db, _contact(contactAccount).toMap());

    // ── Verify activates exactly one device and initializes metadata with
    // the legacy target still ACTIVE. ──
    expect(
      await trust.verifyDevice(
        contactAccountPeerId: contactAccount.peerId,
        deviceId: 'device-alpha',
        expectedFingerprint: fingerprint,
        expectedAccountSigningPublicKey: contactAccount.publicKey,
      ),
      isTrue,
    );
    var roster = await trust.loadRoster(contactAccount.peerId);
    expect(roster.activeBindings, hasLength(1));
    expect(roster.metadata.rosterInitialized, isTrue);
    expect(roster.metadata.legacyTargetRevoked, isFalse);
    expect(authorityChanges, <String>[contactAccount.peerId]);

    // A racing second verify against the now-stale `pending` belief loses.
    expect(
      await trust.verifyDevice(
        contactAccountPeerId: contactAccount.peerId,
        deviceId: 'device-alpha',
        expectedFingerprint: fingerprint,
        expectedAccountSigningPublicKey: contactAccount.publicKey,
      ),
      isFalse,
    );

    targets = await dbResolveDirectContactDeviceTargets(
      db,
      contactAccountPeerId: contactAccount.peerId,
      legacyMlKemPublicKey: 'legacy-mlkem',
    );
    expect(targets, hasLength(2));
    expect(targets.where((t) => t.isLegacyAccountTarget), hasLength(1));
    expect(
      targets.singleWhere((t) => !t.isLegacyAccountTarget).peerId,
      contactTransport.peerId,
    );

    // ── Reject records exact inactive authority and initializes too. ──
    final rejectedTransport = _Identity('alice-device-rejected', 22)
      ..let(signer.register);
    final rejectDocument = await _buildDocument(
      signer: signer,
      account: contactAccount,
      transport: rejectedTransport,
      deviceId: 'device-rejected',
    );
    final (_, rejectParsed) = await scan(rejectDocument);
    expect(
      await stage(rejectParsed!),
      DirectContactDeviceBindingStageOutcome.staged,
    );
    final rejectFingerprint = computeDirectContactDeviceBindingFingerprint(
      contactAccountPeerId: rejectParsed.accountPeerId,
      accountSigningPublicKey: rejectParsed.accountPublicKey,
      deviceId: rejectParsed.deviceId,
      transportPeerId: rejectParsed.transportPeerId,
      transportPublicKey: rejectParsed.transportPublicKey,
      deviceMlKemPublicKey: rejectParsed.deviceMlKemPublicKey,
    );
    expect(
      await trust.rejectDevice(
        contactAccountPeerId: contactAccount.peerId,
        deviceId: 'device-rejected',
        expectedFingerprint: rejectFingerprint,
        expectedAccountSigningPublicKey: contactAccount.publicKey,
      ),
      isTrue,
    );
    expect(authorityChanges, <String>[
      contactAccount.peerId,
      contactAccount.peerId,
    ]);
    // A rejected device replays as idempotent rather than re-prompting.
    expect(
      await stage(rejectParsed),
      DirectContactDeviceBindingStageOutcome.replayed,
    );
    // ...and is not a delivery target.
    targets = await dbResolveDirectContactDeviceTargets(
      db,
      contactAccountPeerId: contactAccount.peerId,
      legacyMlKemPublicKey: 'legacy-mlkem',
    );
    expect(targets, hasLength(2));

    // ── Exact legacy revoke makes "initialized + all revoked" reachable. ──
    expect(
      await trust.revokeLegacyTarget(
        contactAccountPeerId: contactAccount.peerId,
        expectedAccountSigningPublicKey: contactAccount.publicKey,
        expectedLegacyPeerId: contactAccount.peerId,
        expectedLegacyMlKemPublicKey: 'wrong-mlkem',
      ),
      isFalse,
      reason: 'a stale legacy fingerprint cannot cut off the legacy target',
    );
    expect(
      await trust.revokeLegacyTarget(
        contactAccountPeerId: contactAccount.peerId,
        expectedAccountSigningPublicKey: contactAccount.publicKey,
        expectedLegacyPeerId: contactAccount.peerId,
        expectedLegacyMlKemPublicKey: 'legacy-mlkem',
      ),
      isTrue,
    );
    expect(authorityChanges, <String>[
      contactAccount.peerId,
      contactAccount.peerId,
      contactAccount.peerId,
    ]);
    targets = await dbResolveDirectContactDeviceTargets(
      db,
      contactAccountPeerId: contactAccount.peerId,
      legacyMlKemPublicKey: 'legacy-mlkem',
    );
    expect(targets, hasLength(1));
    expect(targets.single.isLegacyAccountTarget, isFalse);

    // Revoking the last active device yields ZERO targets and never
    // resurrects the legacy fallback.
    expect(
      await trust.revokeDevice(
        contactAccountPeerId: contactAccount.peerId,
        deviceId: 'device-alpha',
        expectedFingerprint: fingerprint,
        expectedAccountSigningPublicKey: contactAccount.publicKey,
      ),
      isTrue,
    );
    expect(authorityChanges, <String>[
      contactAccount.peerId,
      contactAccount.peerId,
      contactAccount.peerId,
      contactAccount.peerId,
    ]);
    expect(
      await dbResolveDirectContactDeviceTargets(
        db,
        contactAccountPeerId: contactAccount.peerId,
        legacyMlKemPublicKey: 'legacy-mlkem',
      ),
      isEmpty,
    );
    // No decision auto-reactivates.
    expect(
      await trust.verifyDevice(
        contactAccountPeerId: contactAccount.peerId,
        deviceId: 'device-alpha',
        expectedFingerprint: fingerprint,
        expectedAccountSigningPublicKey: contactAccount.publicKey,
      ),
      isFalse,
    );

    // ── Capacity is bounded, and exact replay wins BEFORE the bound. ──
    for (var index = 0; index < directContactDeviceBindingCapacity; index++) {
      final transport = _Identity('bulk-$index', 100 + index)
        ..let(signer.register);
      final bulkDocument = await _buildDocument(
        signer: signer,
        account: contactAccount,
        transport: transport,
        deviceId: 'bulk-device-$index',
      );
      final (_, bulkParsed) = await scan(bulkDocument);
      final outcome = await stage(bulkParsed!);
      // Two rows already exist (device-alpha, device-rejected), so the
      // capacity bound is reached partway through this loop.
      expect(
        outcome,
        index < directContactDeviceBindingCapacity - 2
            ? DirectContactDeviceBindingStageOutcome.staged
            : DirectContactDeviceBindingStageOutcome.refused,
        reason: 'bulk index $index',
      );
    }
    roster = await trust.loadRoster(contactAccount.peerId);
    expect(roster.bindings, hasLength(directContactDeviceBindingCapacity));
    // At capacity, an exact replay still wins.
    final (_, replayAtCapacity) = await scan(document);
    expect(
      await stage(replayAtCapacity!),
      DirectContactDeviceBindingStageOutcome.replayed,
    );

    // ── Ordinary contact upsert PRESERVES the roster (no FK cascade). ──
    final rosterBeforeUpsert = await db.query(
      'direct_contact_device_bindings',
      orderBy: 'device_id',
    );
    await dbUpsertContact(db, <String, Object?>{
      ..._contact(contactAccount).toMap(),
      'ml_kem_public_key': 'reannounced-mlkem',
    });
    expect(
      await db.query('direct_contact_device_bindings', orderBy: 'device_id'),
      rosterBeforeUpsert,
      reason:
          'contact upsert uses REPLACE semantics; a cascade here would '
          'destroy verified device authority on a routine key re-announce',
    );
    expect(
      (await db.query('direct_contact_device_roster_metadata')),
      hasLength(1),
    );

    // ── Exact contact deletion removes ONLY that contact's roster. ──
    final otherAccount = _Identity('bob', 31)..let(signer.register);
    final otherTransport = _Identity('bob-device', 32)..let(signer.register);
    await dbUpsertContact(db, _contact(otherAccount, username: 'Bob').toMap());
    final otherDocument = await _buildDocument(
      signer: signer,
      account: otherAccount,
      transport: otherTransport,
      deviceId: 'bob-device-alpha',
    );
    final (_, otherParsed) = await scan(otherDocument);
    expect(
      await stage(otherParsed!),
      DirectContactDeviceBindingStageOutcome.staged,
    );

    await dbDeleteContact(db, contactAccount.peerId);
    expect(
      await db.query(
        'direct_contact_device_bindings',
        where: 'contact_account_peer_id = ?',
        whereArgs: <Object?>[contactAccount.peerId],
      ),
      isEmpty,
    );
    expect(
      await db.query(
        'direct_contact_device_roster_metadata',
        where: 'contact_account_peer_id = ?',
        whereArgs: <Object?>[contactAccount.peerId],
      ),
      isEmpty,
    );
    expect(
      await db.query(
        'direct_contact_device_bindings',
        where: 'contact_account_peer_id = ?',
        whereArgs: <Object?>[otherAccount.peerId],
      ),
      hasLength(1),
      reason: 'deleting one contact must not touch another contact\'s roster',
    );
  });

  test('TC-361-02a linked blob-free event authoring stages the exact target '
      'batch before transport', () async {
    final current = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    addTearDown(current.close);

    const selfTransport = 'peer-self-transport';
    await dbUpsertContact(current, _contact(contactAccount).toMap());

    var snapshotReads = 0;
    var encrypts = 0;
    DirectEventFanoutAuthoring authoring({
      required bool selectorOn,
      bool linkedOrigin = false,
    }) => DirectEventFanoutAuthoring(
      selector: selectorOn
          ? const DirectLinkedEventFanoutSelector.enabled()
          : const DirectLinkedEventFanoutSelector.disabled(),
      linkedOrigin: linkedOrigin,
      senderTransportPeerId: selfTransport,
      readSnapshot: (contact) {
        snapshotReads++;
        return dbReadDirectContactFanoutSnapshot(
          current,
          contactAccountPeerId: contact,
        );
      },
      encrypt: ({required recipientMlKemPublicKey, required plaintext}) async {
        encrypts++;
        return (
          kem: 'kem',
          ciphertext: 'ct-for-$recipientMlKemPublicKey',
          nonce: 'nonce',
        );
      },
      loadTextSiblings: (messageId) =>
          dbLoadDirectInboxCustodyOutboxRowsForMessageId(
            current,
            messageId: messageId,
          ),
      stageTextFanout:
          ({
            required stagedRow,
            required messageId,
            required contactAccountPeerId,
            required senderTransportPeerId,
            required expectedSnapshot,
            required candidates,
          }) => dbStageOutgoingDirectTextFanoutInboxCustody(
            current,
            stagedRow: stagedRow,
            messageId: messageId,
            contactAccountPeerId: contactAccountPeerId,
            senderTransportPeerId: senderTransportPeerId,
            expectedSnapshot: expectedSnapshot,
            candidates: candidates,
          ),
      loadEventSiblings: (eventId) =>
          dbLoadDirectReactionInboxCustodyOutboxRowsForEventId(
            current,
            eventId: eventId,
          ),
      stageMutationFanout:
          ({
            required expectedRow,
            required stagedRow,
            required kind,
            required eventId,
            required parentMessageId,
            required contactAccountPeerId,
            required senderTransportPeerId,
            required expectedSnapshot,
            required candidates,
          }) => dbStageOutgoingDirectTextMutationFanoutInboxCustody(
            current,
            expectedRow: expectedRow,
            stagedRow: stagedRow,
            kind: kind,
            eventId: eventId,
            parentMessageId: parentMessageId,
            contactAccountPeerId: contactAccountPeerId,
            senderTransportPeerId: senderTransportPeerId,
            expectedSnapshot: expectedSnapshot,
            candidates: candidates,
          ),
      stageReactionFanout:
          ({
            required reactionRow,
            required action,
            required parentMessageId,
            required contactAccountPeerId,
            required senderTransportPeerId,
            required expectedSnapshot,
            required candidates,
          }) => dbStageOutgoingDirectReactionFanoutInboxCustody(
            current,
            reactionRow: reactionRow,
            action: action,
            parentMessageId: parentMessageId,
            contactAccountPeerId: contactAccountPeerId,
            senderTransportPeerId: senderTransportPeerId,
            expectedSnapshot: expectedSnapshot,
            candidates: candidates,
          ),
    );

    // 1. Primary + UNINITIALIZED roster is exactly the incumbent legacy
    //    route, selector ON or OFF.
    for (final selectorOn in const <bool>[false, true]) {
      final routing = await authoring(
        selectorOn: selectorOn,
      ).decideRoute(contactAccount.peerId);
      expect(routing.route, DirectEventFanoutRoute.incumbentLegacy);
    }
    // 2. Linked-origin authoring ALWAYS requires the selector, even while the
    //    resolver yields only the dynamic legacy target.
    expect(
      (await authoring(
        selectorOn: false,
        linkedOrigin: true,
      ).decideRoute(contactAccount.peerId)).route,
      DirectEventFanoutRoute.refusedSelectorOff,
    );
    expect(encrypts, 0, reason: 'refusal happens before any target crypto');

    // Initialize the roster with two active linked devices.
    await current.insert('direct_contact_device_roster_metadata', {
      'contact_account_peer_id': contactAccount.peerId,
      'roster_initialized': 1,
      'legacy_target_state': 'revoked',
      'initialized_at': _now,
      'legacy_revoked_at': _now,
      'updated_at': _now,
    });
    for (final device in const <(String, String, String)>[
      ('device-a', 'peer-fanout-transport-a', 'a'),
      ('device-b', 'peer-fanout-transport-b', 'b'),
    ]) {
      await current.insert('direct_contact_device_bindings', {
        'contact_account_peer_id': contactAccount.peerId,
        'device_id': device.$1,
        'verified_account_signing_public_key': contactAccount.publicKey,
        'transport_peer_id': device.$2,
        'transport_public_key': 'transport-key-${device.$1}',
        'device_ml_kem_public_key': 'mlkem-${device.$1}',
        'binding_fingerprint': device.$3 * 64,
        'state': 'active',
        'staged_at': _now,
        'decided_at': _now,
      });
    }

    // 3. OFF + initialized refuses BEFORE crypto and never demotes to legacy.
    expect(
      (await authoring(
        selectorOn: false,
      ).decideRoute(contactAccount.peerId)).route,
      DirectEventFanoutRoute.refusedSelectorOff,
    );
    // 4. A removed contact refuses rather than reinterpreting the caller's
    //    stale target as an uninitialized legacy contact.
    expect(
      (await authoring(selectorOn: true).decideRoute('peer-removed')).route,
      DirectEventFanoutRoute.refusedUnavailable,
    );
    expect(encrypts, 0);

    // 5. ON encrypts ONE logical event independently per target and commits
    //    every sibling before any network work exists at all.
    final active = authoring(selectorOn: true);
    final routing = await active.decideRoute(contactAccount.peerId);
    expect(routing.route, DirectEventFanoutRoute.fanout);
    final snapshot = routing.snapshot!;
    expect(snapshot.targets, hasLength(2));
    const messageId = 'tc361-02a-fresh';
    final candidates = (await active.buildCandidates(
      snapshot: snapshot,
      innerPayloadJson: '{"probe":"inner"}',
      buildEnvelope: ({required kem, required ciphertext, required nonce}) =>
          '{"type":"chat_message","version":"2","id":"$messageId",'
          '"senderPeerId":"$selfTransport",'
          '"encrypted":{"kem":"$kem","ciphertext":"$ciphertext",'
          '"nonce":"$nonce"}}',
    ))!;
    expect(encrypts, 2, reason: 'one independent encryption per target');
    expect(
      candidates.map((candidate) => candidate.wireEnvelope).toSet(),
      hasLength(2),
      reason: 'each target owns its own exact ciphertext envelope',
    );
    final fanoutStagedRow = <String, Object?>{
      'id': messageId,
      'contact_peer_id': contactAccount.peerId,
      'sender_peer_id': selfTransport,
      'text': 'fanout text',
      'timestamp': _now,
      'status': 'sending',
      'is_incoming': 0,
      'created_at': _now,
      'wire_envelope': candidates.first.wireEnvelope,
      'dedup_key': messageId,
      'private_media_policy_version': 0,
      'private_media_mode': 'ordinary',
      'private_media_state': 'none',
      'direct_event_fanout_generation_id': messageId,
    };
    final staged = await active.stageTextFanout(
      stagedRow: fanoutStagedRow,
      messageId: messageId,
      contactAccountPeerId: contactAccount.peerId,
      senderTransportPeerId: selfTransport,
      expectedSnapshot: snapshot,
      candidates: candidates,
    );
    expect(staged.outcome, DirectEventFanoutStageOutcome.applied);
    expect(staged.rows, hasLength(2));

    // 6. Survivor-first: with survivors present, the pending set is exactly
    //    those rows — no roster re-resolution, no re-encryption.
    final resolverReadsBefore = snapshotReads;
    final encryptsBefore = encrypts;
    final survivors = await active.loadTextSiblings(messageId);
    expect(survivors, hasLength(2));
    final replay = await active.stageTextFanout(
      stagedRow: fanoutStagedRow,
      messageId: messageId,
      contactAccountPeerId: contactAccount.peerId,
      senderTransportPeerId: selfTransport,
      expectedSnapshot: snapshot,
      candidates: candidates,
    );
    expect(replay.outcome, DirectEventFanoutStageOutcome.survivorReplay);
    expect(snapshotReads, resolverReadsBefore);
    expect(encrypts, encryptsBefore);

    // 7. Revoke-first excludes the target from NEW batches; the already
    //    staged sibling batch keeps its immutable obligation.
    expect(
      await dbRevokeDirectContactDeviceBinding(
        current,
        contactAccountPeerId: contactAccount.peerId,
        deviceId: 'device-b',
        expectedFingerprint: 'b' * 64,
        expectedAccountSigningPublicKey: contactAccount.publicKey,
        decidedAt: _now,
      ),
      isTrue,
    );
    final revokedRouting = await active.decideRoute(contactAccount.peerId);
    expect(
      revokedRouting.snapshot!.targets.map((target) => target.peerId).toList(),
      const <String>['peer-fanout-transport-a'],
      reason: 'revoke-first excludes the target from new batches',
    );
    expect(
      await active.loadTextSiblings(messageId),
      hasLength(2),
      reason: 'stage-first retains the immutable sibling obligation',
    );
  });

  test('TC-361-03a linked physical transport maps to one logical event '
      'authority', () async {
    final current = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    addTearDown(current.close);

    const linkedTransport = 'peer-linked-device-transport';
    await dbUpsertContact(current, _contact(contactAccount).toMap());
    await current.insert('direct_contact_device_roster_metadata', {
      'contact_account_peer_id': contactAccount.peerId,
      'roster_initialized': 1,
      'legacy_target_state': 'active',
      'initialized_at': _now,
      'legacy_revoked_at': null,
      'updated_at': _now,
    });
    await current.insert('direct_contact_device_bindings', {
      'contact_account_peer_id': contactAccount.peerId,
      'device_id': 'linked-device',
      'verified_account_signing_public_key': contactAccount.publicKey,
      'transport_peer_id': linkedTransport,
      'transport_public_key': 'linked-transport-key',
      'device_ml_kem_public_key': 'linked-mlkem',
      'binding_fingerprint': 'd' * 64,
      'state': 'active',
      'staged_at': _now,
      'decided_at': _now,
    });

    Future<DirectTransportAuthorityResolution> resolve(String transport) =>
        dbResolveDirectTransportToLogicalContact(
          current,
          transportPeerId: transport,
        );

    // Legacy transport IS its own logical account.
    final legacy = await resolve(contactAccount.peerId);
    expect(legacy.kind, DirectTransportAuthorityKind.legacy);
    expect(legacy.contactAccountPeerId, contactAccount.peerId);

    // The active linked transport maps to exactly one current account.
    final linked = await resolve(linkedTransport);
    expect(linked.kind, DirectTransportAuthorityKind.linked);
    expect(linked.contactAccountPeerId, contactAccount.peerId);

    // Refusal matrix: unknown / pending / rejected / revoked / key drift /
    // blocked / removed / revoked-legacy.
    expect((await resolve('peer-nobody')).authorized, isFalse);
    for (final state in const <String>['pending', 'rejected', 'revoked']) {
      await current.update(
        'direct_contact_device_bindings',
        <String, Object?>{
          'state': state,
          'decided_at': state == 'pending' ? null : _now,
        },
        where: 'device_id = ?',
        whereArgs: const <Object?>['linked-device'],
      );
      final refused = await resolve(linkedTransport);
      expect(
        refused.authorized,
        isFalse,
        reason: 'a $state binding never authorizes receive traffic',
      );
    }
    await current.update(
      'direct_contact_device_bindings',
      <String, Object?>{'state': 'active', 'decided_at': _now},
      where: 'device_id = ?',
      whereArgs: const <Object?>['linked-device'],
    );
    await current.update(
      'contacts',
      const <String, Object?>{'public_key': 'rotated-away-key'},
      where: 'peer_id = ?',
      whereArgs: <Object?>[contactAccount.peerId],
    );
    expect(
      (await resolve(linkedTransport)).authorized,
      isFalse,
      reason: 'account-key drift invalidates recorded device authority',
    );
    await current.update(
      'contacts',
      <String, Object?>{'public_key': contactAccount.publicKey},
      where: 'peer_id = ?',
      whereArgs: <Object?>[contactAccount.peerId],
    );
    await current.update(
      'contacts',
      const <String, Object?>{'is_blocked': 1, 'blocked_at': _now},
      where: 'peer_id = ?',
      whereArgs: <Object?>[contactAccount.peerId],
    );
    expect(
      (await resolve(linkedTransport)).authorized,
      isFalse,
      reason: 'a blocked contact grants no linked receive authority',
    );
    await current.update(
      'contacts',
      const <String, Object?>{'is_blocked': 0, 'blocked_at': null},
      where: 'peer_id = ?',
      whereArgs: <Object?>[contactAccount.peerId],
    );
    await current.update(
      'direct_contact_device_roster_metadata',
      const <String, Object?>{
        'legacy_target_state': 'revoked',
        'legacy_revoked_at': _now,
      },
      where: 'contact_account_peer_id = ?',
      whereArgs: <Object?>[contactAccount.peerId],
    );
    expect(
      (await resolve(contactAccount.peerId)).authorized,
      isFalse,
      reason: 'a revoked legacy target refuses its own transport',
    );
    await current.update(
      'direct_contact_device_roster_metadata',
      const <String, Object?>{
        'legacy_target_state': 'active',
        'legacy_revoked_at': null,
      },
      where: 'contact_account_peer_id = ?',
      whereArgs: <Object?>[contactAccount.peerId],
    );

    // Durable apply re-authorizes INSIDE its own transaction: apply-first
    // commits exactly once; revoke-first has zero durable effect.
    Map<String, Object?> incomingRow(String id) => <String, Object?>{
      'id': id,
      'contact_peer_id': contactAccount.peerId,
      'sender_peer_id': contactAccount.peerId,
      'text': 'linked text $id',
      'timestamp': _now,
      'status': 'delivered',
      'is_incoming': 1,
      'created_at': _now,
    };
    final applied = await dbApplyIncomingOrdinaryTextMutation(
      current,
      incomingRow: incomingRow('linked-apply-first'),
      kind: IncomingOrdinaryTextMutationKind.initial,
      authenticatedTransportPeerId: linkedTransport,
    );
    expect(applied.outcome, IncomingOrdinaryTextMutationOutcome.inserted);

    expect(
      await dbRevokeDirectContactDeviceBinding(
        current,
        contactAccountPeerId: contactAccount.peerId,
        deviceId: 'linked-device',
        expectedFingerprint: 'd' * 64,
        expectedAccountSigningPublicKey: contactAccount.publicKey,
        decidedAt: _now,
      ),
      isTrue,
    );
    final afterRevoke = await dbApplyIncomingOrdinaryTextMutation(
      current,
      incomingRow: incomingRow('linked-revoke-first'),
      kind: IncomingOrdinaryTextMutationKind.initial,
      authenticatedTransportPeerId: linkedTransport,
    );
    expect(
      afterRevoke.outcome,
      IncomingOrdinaryTextMutationOutcome.unauthorized,
      reason: 'revoke-first has zero durable effect',
    );
    expect(
      await current.query(
        'messages',
        where: 'id = ?',
        whereArgs: const <Object?>['linked-revoke-first'],
      ),
      isEmpty,
    );
    expect(
      (await current.query(
        'messages',
        where: 'id = ?',
        whereArgs: const <Object?>['linked-apply-first'],
      )).single['text'],
      'linked text linked-apply-first',
      reason: 'apply-first stays committed exactly once',
    );

    // Receipt settlement re-authorizes the origin transport and settles only
    // the exact current generation while sibling rows survive untouched.
    await current.update(
      'direct_contact_device_bindings',
      <String, Object?>{'state': 'active', 'decided_at': _now},
      where: 'device_id = ?',
      whereArgs: const <Object?>['linked-device'],
    );
    const receiptMessageId = 'linked-receipt-target';
    const witness =
        '{"type":"chat_message","version":"2","id":"linked-receipt-target",'
        '"senderPeerId":"peer-self","encrypted":{"kem":"k",'
        '"ciphertext":"c","nonce":"n"}}';
    await current.insert('messages', <String, Object?>{
      'id': receiptMessageId,
      'contact_peer_id': contactAccount.peerId,
      'sender_peer_id': 'peer-self',
      'text': 'receipt target',
      'timestamp': _now,
      'status': 'inboxed',
      'is_incoming': 0,
      'created_at': _now,
      'transport': 'inbox',
      'wire_envelope': witness,
      'direct_event_fanout_generation_id': receiptMessageId,
    });
    await current.insert('direct_inbox_custody_outbox', const <String, Object?>{
      'recipient_peer_id': 'peer-some-other-device',
      'message_id': 'unrelated-sibling-anchor',
      'incarnation_id': '99999999999999999999999999999999',
      'wire_envelope': '{"probe":"sibling"}',
      'retry_count': 0,
      'created_at': _now,
      'updated_at': _now,
      'contact_account_peer_id': 'peer-some-other-account',
    });
    expect(
      await dbSettleOutgoingOrdinaryTransport(
        current,
        messageId: receiptMessageId,
        expectedContactPeerId: contactAccount.peerId,
        expectedEnvelope: witness,
        status: 'delivered',
        transport: 'inbox',
        relayExpiresAt: null,
        mode: OutgoingOrdinarySettlementMode.receipt,
        expectedDirectEventFanoutGenerationId: receiptMessageId,
        authenticatedTransportPeerId: 'peer-nobody',
      ),
      OutgoingOrdinaryMutationOutcome.refused,
      reason: 'an unresolvable receipt origin transport is zero-effect',
    );
    expect(
      await dbSettleOutgoingOrdinaryTransport(
        current,
        messageId: receiptMessageId,
        expectedContactPeerId: contactAccount.peerId,
        expectedEnvelope: witness,
        status: 'delivered',
        transport: 'inbox',
        relayExpiresAt: null,
        mode: OutgoingOrdinarySettlementMode.receipt,
        expectedDirectEventFanoutGenerationId: receiptMessageId,
        authenticatedTransportPeerId: linkedTransport,
      ),
      OutgoingOrdinaryMutationOutcome.applied,
      reason: 'a linked origin settles the logical contact row exactly once',
    );
    final settledRow = (await current.query(
      'messages',
      where: 'id = ?',
      whereArgs: const <Object?>[receiptMessageId],
    )).single;
    expect(settledRow['status'], 'delivered');
    expect(settledRow['wire_envelope'], isNull);
    expect(settledRow['direct_event_fanout_generation_id'], receiptMessageId);
    expect(
      await current.query(
        'direct_inbox_custody_outbox',
        where: 'message_id = ?',
        whereArgs: const <Object?>['unrelated-sibling-anchor'],
      ),
      hasLength(1),
      reason: 'receipts never retire or cancel sibling custody rows',
    );
  });

  test(
    'TC-363-01a group-scoped self bootstrap atomically owns exact roster and protected intent',
    () async {
      final document = await _buildDocument(
        signer: signer,
        account: ownAccount,
        transport: contactTransport,
        deviceId: 'linked-self-device',
        mlKem: 'linked-self-mlkem',
      );

      // The ordinary contact route keeps its Plan-360 self-scan boundary and
      // never consults a contact or stages a direct binding.
      final ordinary = await scan(document);
      expect(ordinary.$1, ParseDirectLinkedDeviceQrResult.selfScan);
      expect(ordinary.$2, isNull);

      final selectedGroup = await parseLinkedGroupBootstrapQr(
        qrString: document,
        ownAccountPeerId: ownAccount.peerId,
        ownAccountPublicKey: ownAccount.publicKey,
        isOrdinaryPrimary: true,
        callVerify: signer.verify,
        selector: const DirectLinkedDeviceSelector.enabled(),
        multiDeviceSyncEnabled: true,
        now: _clock,
      );
      expect(selectedGroup.$1, ParseLinkedGroupBootstrapQrResult.success);
      expect(selectedGroup.$2?.deviceId, 'linked-self-device');
      expect(selectedGroup.$2?.deviceMlKemPublicKey, 'linked-self-mlkem');

      final group = GroupModel(
        id: 'group-363-bootstrap',
        name: 'Bootstrap group',
        type: GroupType.chat,
        topicName: '/mknoon/groups/group-363-bootstrap',
        createdAt: _clock(),
        createdBy: ownAccount.peerId,
        myRole: GroupRole.admin,
      );
      final self = GroupMember(
        groupId: group.id,
        peerId: ownAccount.peerId,
        username: 'Self',
        role: MemberRole.admin,
        publicKey: ownAccount.publicKey,
        mlKemPublicKey: 'primary-mlkem',
        joinedAt: _clock(),
      );
      final key = GroupKeyInfo(
        groupId: group.id,
        keyGeneration: 7,
        encryptedKey: 'current-group-key',
        createdAt: _clock(),
      );
      final bootstrapRepository = _BootstrapAuthoringRepository(
        group: group,
        members: <GroupMember>[self],
        key: key,
      );
      String? encryptedPlaintext;
      final authored = await authorLinkedGroupBootstrap(
        groupRepository: bootstrapRepository,
        groupId: group.id,
        ownAccountPeerId: ownAccount.peerId,
        ownAccountPublicKey: ownAccount.publicKey,
        ownAccountPrivateKey: ownAccount.privateKey,
        verifiedTarget: selectedGroup.$2!,
        isOrdinaryPrimary: true,
        callSign: signer.sign,
        callEncrypt:
            ({required recipientMlKemPublicKey, required plaintext}) async {
              expect(recipientMlKemPublicKey, 'linked-self-mlkem');
              encryptedPlaintext = plaintext;
              return <String, dynamic>{
                'ok': true,
                'kem': 'kem-linked-self',
                'ciphertext': 'ciphertext-linked-self',
                'nonce': 'nonce-linked-self',
              };
            },
        selector: const DirectLinkedDeviceSelector.enabled(),
        multiDeviceSyncEnabled: true,
        bootstrapIdOverride: 'bootstrap-363-exact',
        now: _clock,
      );
      expect(authored, AuthorLinkedGroupBootstrapResult.committed);
      expect(
        bootstrapRepository.committedSelf?.devices.map(
          (device) => device.deviceId,
        ),
        <String>[ownAccount.peerId, 'linked-self-device'],
        reason:
            'the first explicit roster must retain the incumbent legacy '
            'primary before adding the linked physical device',
      );
      expect(bootstrapRepository.committedSelf?.role, MemberRole.admin);
      expect(
        bootstrapRepository.committedIntent?.toMap().containsKey(
          'key_package_public_material',
        ),
        isFalse,
        reason: 'derivable QR key material is not duplicated in v85 intent',
      );
      expect(bootstrapRepository.committedIntent?.keyPackageId, isNotEmpty);
      expect(bootstrapRepository.committedOutbox?.recipientPeerIds, <String>[
        contactTransport.peerId,
      ]);
      expect(
        bootstrapRepository.committedOutbox?.sourceMessageId,
        'bootstrap-363-exact',
      );
      final signedSnapshot = LinkedGroupBootstrapPayload.tryParse(
        encryptedPlaintext!,
      );
      expect(signedSnapshot?.group.myRole, GroupRole.admin);
      expect(signedSnapshot?.members.single.devices, hasLength(2));

      final tampered = await parseLinkedGroupBootstrapQr(
        qrString: _tamperBody(document, 'deviceId', 'crossed-device'),
        ownAccountPeerId: ownAccount.peerId,
        ownAccountPublicKey: ownAccount.publicKey,
        isOrdinaryPrimary: true,
        callVerify: signer.verify,
        selector: const DirectLinkedDeviceSelector.enabled(),
        multiDeviceSyncEnabled: true,
        now: _clock,
      );
      expect(tampered.$1, ParseLinkedGroupBootstrapQrResult.invalidSignature);

      final expiredDocument = await _buildDocument(
        signer: signer,
        account: ownAccount,
        transport: contactTransport,
        deviceId: 'expired-linked-device',
        now: () => _clock().subtract(const Duration(days: 2)),
      );
      final expired = await parseLinkedGroupBootstrapQr(
        qrString: expiredDocument,
        ownAccountPeerId: ownAccount.peerId,
        ownAccountPublicKey: ownAccount.publicKey,
        isOrdinaryPrimary: true,
        callVerify: signer.verify,
        selector: const DirectLinkedDeviceSelector.enabled(),
        multiDeviceSyncEnabled: true,
        now: _clock,
      );
      expect(expired.$1, ParseLinkedGroupBootstrapQrResult.expired);

      final linkedScanner = await parseLinkedGroupBootstrapQr(
        qrString: document,
        ownAccountPeerId: ownAccount.peerId,
        ownAccountPublicKey: ownAccount.publicKey,
        isOrdinaryPrimary: false,
        callVerify: signer.verify,
        selector: const DirectLinkedDeviceSelector.enabled(),
        multiDeviceSyncEnabled: true,
        now: _clock,
      );
      expect(
        linkedScanner.$1,
        ParseLinkedGroupBootstrapQrResult.linkedScannerRefused,
      );
      expect(
        (await dbLoadDirectContactDeviceRoster(db, ownAccount.peerId)).bindings,
        isEmpty,
      );
    },
  );
}

extension _Let<T> on T {
  void let(void Function(T value) action) => action(this);
}
