import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/debug/ios_receiver_bootstrap_contract.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';

const String iosSenderProjectionRequestSchema =
    'mknoon.sims.ios-sender-projection-request.v1';
const String iosSenderProjectionBundleId = 'com.mknoon.app';
const String iosSenderProjectionSeedAction = 'seed_sender';
const String iosSenderProjectionCleanupAction = 'cleanup_sender';
const String iosSenderProjectionDigestField = 'simsFixtureDigest';

final class IosSenderProjectionRequest {
  const IosSenderProjectionRequest({
    required this.action,
    required this.captureNonce,
    required this.receiverDeviceId,
    required this.senderPeerId,
    required this.senderUsername,
    required this.apnsPayloadSha256,
    required this.createdAt,
    required this.expiresAt,
  });

  static IosSenderProjectionRequest? tryParse(
    Map<String, Object?> value, {
    required DateTime now,
  }) {
    const keys = <String>{
      'schema',
      'action',
      'captureNonce',
      'receiverDeviceId',
      'bundleId',
      'senderPeerId',
      'senderUsername',
      'apnsPayloadSha256',
      'createdAt',
      'expiresAt',
    };
    if (value.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(value.keys.toSet()).isNotEmpty ||
        value['schema'] != iosSenderProjectionRequestSchema ||
        value['bundleId'] != iosSenderProjectionBundleId) {
      return null;
    }
    final action = value['action'];
    final nonce = value['captureNonce'];
    final receiver = value['receiverDeviceId'];
    final sender = value['senderPeerId'];
    final username = value['senderUsername'];
    final payloadSha = value['apnsPayloadSha256'];
    final createdText = value['createdAt'];
    final expiresText = value['expiresAt'];
    if (action is! String ||
        (action != iosSenderProjectionSeedAction &&
            action != iosSenderProjectionCleanupAction) ||
        nonce is! String ||
        !RegExp(r'^[A-Za-z0-9._:-]{12,160}$').hasMatch(nonce) ||
        receiver is! String ||
        !RegExp(r'^[A-Za-z0-9._:-]{4,160}$').hasMatch(receiver) ||
        sender is! String ||
        !isIosReceiverBootstrapTransportPeerId(sender) ||
        username is! String ||
        username != username.trim() ||
        !RegExp(r'^[^\u0000-\u001f\u007f]{1,30}$').hasMatch(username) ||
        payloadSha is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(payloadSha) ||
        createdText is! String ||
        expiresText is! String ||
        !createdText.endsWith('Z') ||
        !expiresText.endsWith('Z')) {
      return null;
    }
    final createdAt = DateTime.tryParse(createdText)?.toUtc();
    final expiresAt = DateTime.tryParse(expiresText)?.toUtc();
    final utcNow = now.toUtc();
    if (createdAt == null ||
        expiresAt == null ||
        createdAt.isAfter(utcNow.add(const Duration(seconds: 15))) ||
        utcNow.difference(createdAt) > const Duration(minutes: 5) ||
        expiresAt.isBefore(utcNow) ||
        expiresAt.isAfter(utcNow.add(const Duration(minutes: 5))) ||
        expiresAt.isBefore(createdAt)) {
      return null;
    }
    return IosSenderProjectionRequest(
      action: action,
      captureNonce: nonce,
      receiverDeviceId: receiver,
      senderPeerId: sender,
      senderUsername: username,
      apnsPayloadSha256: payloadSha,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }

  final String action;
  final String captureNonce;
  final String receiverDeviceId;
  final String senderPeerId;
  final String senderUsername;
  final String apnsPayloadSha256;
  final DateTime createdAt;
  final DateTime expiresAt;

  String get fixtureDigest => sha256
      .convert(
        utf8.encode(
          jsonEncode(<String, String>{
            'schema': iosSenderProjectionRequestSchema,
            'captureNonce': captureNonce,
            'receiverDeviceId': receiverDeviceId,
            'bundleId': iosSenderProjectionBundleId,
            'senderPeerId': senderPeerId,
            'senderUsername': senderUsername,
            'apnsPayloadSha256': apnsPayloadSha256,
          }),
        ),
      )
      .toString();

  ContactModel get fixtureContact => ContactModel(
    peerId: senderPeerId,
    publicKey: 'mknoon-sims-projection-only',
    rendezvous: '/mknoon/sims/projection-only',
    username: senderUsername,
    signature: 'mknoon-sims-ios:$fixtureDigest',
    scannedAt: '1970-01-01T00:00:00.000Z',
  );
}

final class IosSenderProjectionFixtureStore {
  const IosSenderProjectionFixtureStore({
    required this.loadLocalAccountPeerId,
    required this.loadProjectionAccountPeerId,
    required this.loadContact,
    required this.insertContactIfAbsent,
    required this.deleteContactIfExact,
    required this.loadProjectedContact,
    required this.insertProjectedContactIfAbsent,
    required this.deleteProjectedContactIfExact,
  });

  final Future<String?> Function() loadLocalAccountPeerId;
  final Future<String?> Function() loadProjectionAccountPeerId;
  final Future<ContactModel?> Function(String peerId) loadContact;
  final Future<bool> Function(ContactModel contact) insertContactIfAbsent;
  final Future<bool> Function(ContactModel contact) deleteContactIfExact;
  final Future<Map<String, Object?>?> Function(String peerId)
  loadProjectedContact;
  final Future<bool> Function(IosSenderProjectionRequest request)
  insertProjectedContactIfAbsent;
  final Future<bool> Function(IosSenderProjectionRequest request)
  deleteProjectedContactIfExact;
}

final class IosSenderProjectionMutationResult {
  const IosSenderProjectionMutationResult(this.status, this.resultCode);

  final String status;
  final String resultCode;
}

final class IosSenderProjectionFixtureCoordinator {
  const IosSenderProjectionFixtureCoordinator(this.store);

  final IosSenderProjectionFixtureStore store;

  Future<IosSenderProjectionMutationResult> execute(
    IosSenderProjectionRequest request,
  ) => request.action == iosSenderProjectionSeedAction
      ? _seed(request)
      : _cleanup(request);

  Future<IosSenderProjectionMutationResult> _seed(
    IosSenderProjectionRequest request,
  ) async {
    var insertedProjection = false;
    var insertedContact = false;
    try {
      if (!await _ownsCurrentAccount(request)) {
        return const IosSenderProjectionMutationResult(
          'rejected',
          'projection_owner_mismatch',
        );
      }
      final expectedContact = request.fixtureContact;
      final currentContact = await store.loadContact(request.senderPeerId);
      final currentProjection = await store.loadProjectedContact(
        request.senderPeerId,
      );
      if ((currentContact != null &&
              !_isExactContact(currentContact, expectedContact)) ||
          (currentProjection != null &&
              !_isExactProjection(currentProjection, request))) {
        return const IosSenderProjectionMutationResult(
          'rejected',
          'sender_state_collision',
        );
      }
      if (currentProjection == null) {
        insertedProjection = await store.insertProjectedContactIfAbsent(
          request,
        );
        if (!insertedProjection) {
          return const IosSenderProjectionMutationResult(
            'rejected',
            'sender_state_collision',
          );
        }
      }
      if (currentContact == null) {
        insertedContact = await store.insertContactIfAbsent(expectedContact);
        if (!insertedContact) {
          final rolledBack =
              !insertedProjection ||
              await store.deleteProjectedContactIfExact(request);
          return IosSenderProjectionMutationResult(
            'rejected',
            rolledBack ? 'sender_state_collision' : 'rollback_incomplete',
          );
        }
      }
      final verifiedContact = await store.loadContact(request.senderPeerId);
      final verifiedProjection = await store.loadProjectedContact(
        request.senderPeerId,
      );
      if (!_isExactContact(verifiedContact, expectedContact) ||
          !_isExactProjection(verifiedProjection, request)) {
        final rolledBack = await _rollbackNewSeed(
          request,
          expectedContact,
          insertedContact: insertedContact,
          insertedProjection: insertedProjection,
        );
        return IosSenderProjectionMutationResult(
          'rejected',
          rolledBack ? 'seed_verification_failed' : 'rollback_incomplete',
        );
      }
      return IosSenderProjectionMutationResult(
        'seeded',
        insertedContact || insertedProjection ? 'ok' : 'idempotent',
      );
    } on Object {
      final rolledBack = await _rollbackNewSeed(
        request,
        request.fixtureContact,
        insertedContact: insertedContact,
        insertedProjection: insertedProjection,
      );
      return IosSenderProjectionMutationResult(
        'rejected',
        rolledBack ? 'mutation_failed' : 'rollback_incomplete',
      );
    }
  }

  Future<IosSenderProjectionMutationResult> _cleanup(
    IosSenderProjectionRequest request,
  ) async {
    try {
      if (!await _ownsCurrentAccount(request)) {
        return const IosSenderProjectionMutationResult(
          'rejected',
          'projection_owner_mismatch',
        );
      }
      final expectedContact = request.fixtureContact;
      final currentContact = await store.loadContact(request.senderPeerId);
      final currentProjection = await store.loadProjectedContact(
        request.senderPeerId,
      );
      if ((currentContact != null &&
              !_isExactContact(currentContact, expectedContact)) ||
          (currentProjection != null &&
              !_isExactProjection(currentProjection, request))) {
        return const IosSenderProjectionMutationResult(
          'rejected',
          'cleanup_state_mismatch',
        );
      }
      if (currentContact != null &&
          !await store.deleteContactIfExact(expectedContact)) {
        return const IosSenderProjectionMutationResult(
          'rejected',
          'mutation_failed',
        );
      }
      // Delete the authoritative DB row first. The projection mutation also
      // installs a process-local generation tombstone, so a launch backfill
      // that loaded the old row before this delete cannot recreate an orphan
      // projection after cleanup.
      if (!await store.deleteProjectedContactIfExact(request)) {
        return const IosSenderProjectionMutationResult(
          'rejected',
          'mutation_failed',
        );
      }
      return IosSenderProjectionMutationResult(
        'cleaned',
        currentContact == null && currentProjection == null
            ? 'idempotent'
            : 'ok',
      );
    } on Object {
      return const IosSenderProjectionMutationResult(
        'rejected',
        'mutation_failed',
      );
    }
  }

  Future<bool> _ownsCurrentAccount(IosSenderProjectionRequest request) async {
    final local = (await store.loadLocalAccountPeerId())?.trim();
    final projected = (await store.loadProjectionAccountPeerId())?.trim();
    return local != null &&
        local.isNotEmpty &&
        local == projected &&
        local != request.senderPeerId;
  }

  Future<bool> _rollbackNewSeed(
    IosSenderProjectionRequest request,
    ContactModel expectedContact, {
    required bool insertedContact,
    required bool insertedProjection,
  }) async {
    var complete = true;
    if (insertedContact) {
      try {
        complete =
            await store.deleteContactIfExact(expectedContact) && complete;
      } on Object {
        complete = false;
      }
    }
    if (insertedProjection) {
      try {
        complete =
            await store.deleteProjectedContactIfExact(request) && complete;
      } on Object {
        complete = false;
      }
    }
    return complete;
  }
}

bool _isExactContact(ContactModel? actual, ContactModel expected) {
  if (actual == null) return false;
  final actualMap = actual.toMap();
  final expectedMap = expected.toMap();
  return actualMap.length == expectedMap.length &&
      expectedMap.entries.every((entry) => actualMap[entry.key] == entry.value);
}

bool _isExactProjection(
  Map<String, Object?>? actual,
  IosSenderProjectionRequest request,
) =>
    actual != null &&
    actual.length == 5 &&
    actual['username'] == request.senderUsername &&
    actual['blocked'] == false &&
    actual['archived'] == false &&
    actual['authorizedTransportPeerIds'] is List<Object?> &&
    (actual['authorizedTransportPeerIds']! as List<Object?>).isEmpty &&
    actual[iosSenderProjectionDigestField] == request.fixtureDigest;
