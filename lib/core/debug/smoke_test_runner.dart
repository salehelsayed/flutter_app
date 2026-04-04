// Debug-only smoke test runner for cross-device automation.
// Reads Documents/smoke_test_config.json and executes actions like adding
// contacts, sending introductions, and auto-accepting.
// Guarded by kDebugMode — dead-code eliminated in release builds.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/application/add_contact_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/introduction/application/accept_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/send_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

const _kConfigFile = 'smoke_test_config.json';
const _kExportFile = 'auto_setup_export.json';

/// Exports identity info (signed QR payload + ML-KEM key) to Documents.
/// Called during auto-setup so the smoke test script can read it.
Future<void> exportIdentityForSmokeTest({
  required String signedQrPayloadJson,
  required String? mlKemPublicKey,
}) async {
  if (!kDebugMode) return;
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$_kExportFile');
  await file.writeAsString(jsonEncode({
    'qrPayload': signedQrPayloadJson,
    'mlKemPublicKey': mlKemPublicKey,
  }));
  if (kDebugMode) print('[SMOKE] Exported identity to $_kExportFile');
}

/// Phase 1: Add contacts to DB BEFORE runApp() so StartupRouter sees them
/// and routes to Feed instead of FTE.
/// Returns true if a config was processed (caller should NOT delete the file —
/// phase 2 still needs it).
Future<bool> prePopulateContactsFromSmokeConfig({
  required ContactRepository contactRepo,
}) async {
  if (!kDebugMode) return false;

  final dir = await getApplicationDocumentsDirectory();
  final configFile = File('${dir.path}/$_kConfigFile');
  if (!await configFile.exists()) return false;

  final config =
      jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;

  if (!config.containsKey('add_friends')) return false;

  final friends = config['add_friends'] as List<dynamic>;
  for (final friendData in friends) {
    final qrJson = friendData['qrPayload'] as String;
    final mlKemPk = friendData['mlKemPublicKey'] as String?;

    final qrMap = jsonDecode(qrJson) as Map<String, dynamic>;
    if (mlKemPk != null) qrMap['mlkem'] = mlKemPk;

    final contact = ContactModel.fromQRPayload(qrMap);
    final result = await addContact(repository: contactRepo, contact: contact);
    if (kDebugMode) {
      print('[SMOKE] Pre-populated contact ${contact.username}: $result');
    }
  }

  return true;
}

/// Phase 2: After P2P starts, send contact requests, introductions,
/// and handle auto-accept. Called via Timer after runApp().
Future<void> runSmokeTestP2PActions({
  required P2PService p2pService,
  required Bridge bridge,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required ContactRequestRepository contactRequestRepo,
  required IntroductionRepository introRepo,
  required MessageRepository messageRepo,
}) async {
  if (!kDebugMode) return;

  final dir = await getApplicationDocumentsDirectory();
  final configFile = File('${dir.path}/$_kConfigFile');
  if (!await configFile.exists()) return;

  if (kDebugMode) print('[SMOKE] Phase 2: waiting for P2P node...');

  // Wait for P2P node to start (up to 90s)
  for (var i = 0; i < 90; i++) {
    if (p2pService.currentState.isStarted) break;
    await Future.delayed(const Duration(seconds: 1));
  }
  if (!p2pService.currentState.isStarted) {
    if (kDebugMode) print('[SMOKE] P2P not started after 90s, aborting');
    return;
  }
  // Extra settle time for relay connection
  await Future.delayed(const Duration(seconds: 3));
  if (kDebugMode) print('[SMOKE] P2P ready, executing actions...');

  final config =
      jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;

  // ── Send contact requests for pre-populated contacts ──
  if (config.containsKey('add_friends')) {
    final friends = config['add_friends'] as List<dynamic>;
    for (final friendData in friends) {
      final qrJson = friendData['qrPayload'] as String;
      final qrMap = jsonDecode(qrJson) as Map<String, dynamic>;
      final peerId = qrMap['ns'] as String;
      final publicKey = qrMap['pk'] as String;
      final username = qrMap['un'] as String? ?? 'unknown';

      final sendResult = await sendContactRequest(
        p2pService: p2pService,
        identityRepo: identityRepo,
        bridge: bridge,
        targetPeerId: peerId,
        recipientPublicKey: publicKey,
      );
      if (kDebugMode) {
        print('[SMOKE] Sent contact request to $username: $sendResult');
      }
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  // ── Send introductions ──
  if (config['introduce_all'] == true) {
    // Wait a bit for contact requests to be delivered/accepted
    if (kDebugMode) print('[SMOKE] Waiting 10s for contact requests to settle...');
    await Future.delayed(const Duration(seconds: 10));

    final identity = await identityRepo.loadIdentity();
    if (identity != null) {
      final allContacts = await contactRepo.getAllContacts();
      if (allContacts.length >= 2) {
        for (final recipient in allContacts) {
          final friends =
              allContacts.where((c) => c.peerId != recipient.peerId).toList();
          if (kDebugMode) {
            print('[SMOKE] Introducing ${friends.length} friend(s) to ${recipient.username}');
          }
          await sendIntroductions(
            contactRepo: contactRepo,
            introRepo: introRepo,
            p2pService: p2pService,
            bridge: bridge,
            introducerPeerId: identity.peerId,
            introducerUsername: identity.username,
            recipientPeerId: recipient.peerId,
            recipientUsername: recipient.username,
            recipientMlKemPublicKey: recipient.mlKemPublicKey,
            friendsToIntroduce: friends,
          );
        }
        if (kDebugMode) print('[SMOKE] Introductions sent');
      }
    }
  }

  // ── Auto-accept (for devices b/c) ──
  if (config['auto_accept'] == true) {
    if (kDebugMode) print('[SMOKE] Auto-accept mode: polling...');
    final identity = await identityRepo.loadIdentity();
    if (identity == null) return;

    for (var tick = 0; tick < 40; tick++) {
      // Accept pending contact requests
      final pendingRequests = await contactRequestRepo.getPendingRequests();
      for (final req in pendingRequests) {
        final result = await acceptContactRequest(
          requestRepo: contactRequestRepo,
          contactRepo: contactRepo,
          peerId: req.peerId,
        );
        if (kDebugMode) {
          print('[SMOKE] Auto-accepted contact request from ${req.username}: $result');
        }
      }

      // Accept pending introductions
      final pendingIntros =
          await introRepo.getPendingIntroductionsForUser(identity.peerId);
      for (final intro in pendingIntros) {
        final isRecipient = intro.recipientId == identity.peerId;
        final myStatus =
            isRecipient ? intro.recipientStatus : intro.introducedStatus;
        if (myStatus == IntroductionStatus.pending) {
          final result = await acceptIntroduction(
            introRepo: introRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            bridge: bridge,
            introductionId: intro.id,
            ownPeerId: identity.peerId,
            ownUsername: identity.username,
            messageRepo: messageRepo,
          );
          if (kDebugMode) {
            print('[SMOKE] Auto-accepted introduction ${intro.id}: ${result?.status}');
          }
        }
      }

      await Future.delayed(const Duration(seconds: 3));
    }
    if (kDebugMode) print('[SMOKE] Auto-accept polling finished');
  }

  // Clean up config file
  await configFile.delete();
  if (kDebugMode) print('[SMOKE] Config executed and cleaned up');
}
