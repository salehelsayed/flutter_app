import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/key_exchange_retrier.dart';
import 'package:flutter_app/features/contact_request/application/key_exchange_retry_coordinator.dart';
import 'package:flutter_app/features/contact_request/application/mlkem_reannounce_marker.dart';
import 'package:flutter_app/features/contact_request/application/retry_incomplete_key_exchanges_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_screen.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_wired.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../presentation/support/contact_request_sql_fixture.dart';
import '../support/contact_repair_harness.dart';

// Drives the real scanner callback, SQL repositories, reconnect owner and peer
// listener. Camera optics, real transports and native secure storage are outside
// this host proof; no scanner/send/retry business logic is reimplemented here.
final _bus = Ed25519ContactRequestCryptoBus();
final _alice = TestEd25519Identity.fromSeedByte(0xA1);
final _bob = TestEd25519Identity.fromSeedByte(0xA2);
final _blocked = TestEd25519Identity.fromSeedByte(0xA3);
final _complete = TestEd25519Identity.fromSeedByte(0xA4);

enum _RecoveryState { ready, missingOwnKey }

final class _RecoveryKeyStore implements SecureKeyStore {
  _RecoveryKeyStore(this.directory);
  final Directory directory;
  File _file(String key) =>
      File('${directory.path}/${Uri.encodeComponent(key)}');
  @override
  Future<String?> read(String key) async {
    final file = _file(key);
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> write(String key, String value) async {
    await directory.create(recursive: true);
    await _file(key).writeAsString(value, flush: true);
  }

  @override
  Future<void> delete(String key) async {
    final file = _file(key);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<bool> containsKey(String key) => _file(key).exists();
}

final class _ReconnectService extends FakeP2PService {
  _ReconnectService({required super.peerId, required super.network});
  final _states = StreamController<NodeState>.broadcast();
  NodeState? _state;
  @override
  NodeState get currentState => _state ?? super.currentState;
  @override
  Stream<NodeState> get stateStream => _states.stream;
  void reconnect() {
    _state = NodeState(
      isStarted: true,
      peerId: peerId,
      circuitAddresses: const ['/dns4/host-fixture/p2p-circuit'],
    );
    _states.add(_state!);
  }

  @override
  void dispose() {
    _states.close();
    super.dispose();
  }
}

// Camera transport is outside this host journey. Reuse the platform seam from
// qr_camera_permission_journey_test without opening native event channels.
final class _HostScannerPlatform extends MobileScannerPlatform {
  @override
  Stream<BarcodeCapture?> get barcodesStream => const Stream.empty();
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const SizedBox(width: 640, height: 480);
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async =>
      MobileScannerViewAttributes(
        cameraDirection: options.cameraDirection,
        currentTorchMode: TorchState.off,
        size: const Size(640, 480),
        numberOfCameras: 1,
      );
  @override
  Future<void> stop() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<void> updateScanWindow(Rect? window) async {}
}

String _bobQr() {
  final payload = SplayTreeMap<String, dynamic>.from({
    'ns': _bob.peerId,
    'pk': _bob.publicKey,
    'rv': repairRendezvous,
    'ts': DateTime.now().toUtc().toIso8601String(),
    'un': 'Bob',
  });
  return jsonEncode({...payload, 'sig': _bob.signBase64(jsonEncode(payload))});
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 12}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() {
    _bus
      ..register(_alice)
      ..register(_bob)
      ..register(_blocked)
      ..register(_complete);
  });

  for (final recoveryState in _RecoveryState.values) {
    testWidgets(
      'CR-012 scanner send failure survives reopen and reconnect '
      '${recoveryState.name} yields one pending request or an honest retained retry',
      (tester) async {
        // Keep SQL, stream listeners and their completion futures in the same
        // real async zone; fake-zone completions cannot settle runAsync waits.
        await tester.runAsync(() async {
          final previousScannerPlatform = MobileScannerPlatform.instance;
          MobileScannerPlatform.instance = _HostScannerPlatform();
          addTearDown(() {
            MobileScannerPlatform.instance = previousScannerPlatform;
          });
          late Directory directory;
          late String alicePath;
          late String bobPath;
          late Database aliceDb;
          late Database bobDb;
          late _RecoveryKeyStore keys;
          final network = FakeP2PNetwork()
            ..deliveryFails = true
            ..inboxDisabled = true;
          final initialSendFailed = Completer<void>();
          debugSetFlowEventSink((event) {
            if (event['event'] == 'CONTACT_REQUEST_SENT' &&
                (event['details'] as Map?)?['result'] == 'sendFailed' &&
                !initialSendFailed.isCompleted) {
              initialSendFailed.complete();
            }
          });
          addTearDown(() => debugSetFlowEventSink(null));
          directory = await Directory.systemTemp.createTemp(
            'scanner_reconnect_',
          );
          alicePath = '${directory.path}/alice.db';
          bobPath = '${directory.path}/bob.db';
          aliceDb = await openRepairTestDatabase(alicePath);
          bobDb = await openRepairTestDatabase(bobPath);
          keys = _RecoveryKeyStore(Directory('${directory.path}/alice-keys'));
          await buildWidgetIdentityRepository(aliceDb, keys).saveIdentity(
            testIdentityModel(
              _alice,
              username: 'Alice',
              mlKemPublicKey: 'alice-mlkem',
            ),
          );
          final bridge = Ed25519ContactRequestBridge(_bus);
          final bobBridge = Ed25519ContactRequestBridge(_bus);
          var aliceP2p = _ReconnectService(
            peerId: _alice.peerId,
            network: network,
          );
          final bobP2p = FakeP2PService(peerId: _bob.peerId, network: network);
          var aliceContacts = databaseContactRepository(aliceDb);
          var aliceRequests = buildWidgetRequestRepository(aliceDb);
          var aliceIdentity = buildWidgetIdentityRepository(aliceDb, keys);
          var bobContacts = databaseContactRepository(bobDb);
          var bobRequests = buildWidgetRequestRepository(bobDb);
          final messages = InMemoryMessageRepository();
          final media = InMemoryMediaAttachmentRepository();
          final chatListener = ChatMessageListener(
            chatMessageStream: const Stream.empty(),
            messageRepo: messages,
            contactRepo: aliceContacts,
            bridge: bridge,
            getOwnMlKemSecretKey: () async => null,
          );
          final scannerListener = ContactRequestListener(
            contactRequestStream: const Stream.empty(),
            requestRepo: aliceRequests,
            contactRepo: aliceContacts,
            bridge: bridge,
            getOwnPeerId: () => _alice.peerId,
          );
          KeyExchangeRetrier? retrier;
          ContactRequestListener? receiver;
          StreamSubscription<ContactRequestModel>? requestSubscription;
          try {
            await tester.pumpWidget(
              MaterialApp(
                locale: const Locale('en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: QRScannerWired(
                  bridge: bridge,
                  contactRepository: aliceContacts,
                  contactRequestRepository: aliceRequests,
                  contactRequestListener: scannerListener,
                  messageRepository: messages,
                  mediaAttachmentRepository: media,
                  chatMessageListener: chatListener,
                  identityRepository: aliceIdentity,
                  p2pService: aliceP2p,
                  mediaFileManager: FakeMediaFileManager(),
                  secureKeyStore: keys,
                  ownPeerId: _alice.peerId,
                  imageProcessor: ImageProcessor(
                    compressFile:
                        ({
                          required path,
                          required quality,
                          required keepExif,
                          minWidth = 1920,
                          minHeight = 1080,
                        }) async => null,
                  ),
                  shouldMarkContactRequest: (_) async => false,
                  downloadProfilePictureFn:
                      ({
                        required bridge,
                        required contactRepo,
                        required ownerPeerId,
                        required avatarVersion,
                        bool retryPendingRequest = false,
                      }) async => null,
                ),
              ),
            );
            await _pumpFrames(tester);
            final scanner = tester.widget<QRScannerScreen>(
              find.byType(QRScannerScreen),
            );
            scanner.onScanned(_bobQr());
            await initialSendFailed.future.timeout(const Duration(seconds: 5));
            expect(await readMlKemReannounceMarker(keys), [_bob.peerId]);
            expect(
              (await aliceContacts.getContact(_bob.peerId))?.mlKemPublicKey,
              isNull,
            );
            expect(await bobRequests.getPendingRequests(), isEmpty);
            expect(await bobContacts.getContactCount(), 0);
            await _pumpFrames(tester);
            expect(find.text('Added to your circle!'), findsOneWidget);
            expect(tester.takeException(), isNull);
            // Remove the entire scanner route before restarting repositories. The
            // continuation below cannot rescan or invoke that widget's callback.
            await tester.pumpWidget(const SizedBox.shrink());
            await _pumpFrames(tester, count: 2);
            final prompts = <ContactRequestModel>[];
            final firstPending = Completer<void>();
            final retryCompleted = Completer<int>();
            aliceP2p.dispose();
            await aliceDb.close();
            await bobDb.close();
            aliceDb = await openRepairTestDatabase(alicePath);
            bobDb = await openRepairTestDatabase(bobPath);
            keys = _RecoveryKeyStore(Directory('${directory.path}/alice-keys'));
            aliceContacts = databaseContactRepository(aliceDb);
            aliceRequests = buildWidgetRequestRepository(aliceDb);
            aliceIdentity = buildWidgetIdentityRepository(aliceDb, keys);
            bobContacts = databaseContactRepository(bobDb);
            bobRequests = buildWidgetRequestRepository(bobDb);
            expect(await readMlKemReannounceMarker(keys), [_bob.peerId]);
            expect(
              (await aliceContacts.getContact(_bob.peerId))?.mlKemPublicKey,
              isNull,
            );
            if (recoveryState == _RecoveryState.missingOwnKey) {
              await aliceIdentity.saveIdentity(
                testIdentityModel(_alice, username: 'Alice'),
              );
            }
            // These targets are never retried: one is revoked, one is complete.
            await aliceContacts.addContact(contactFor(_blocked));
            await aliceContacts.blockContact(_blocked.peerId);
            await aliceContacts.addContact(
              contactFor(_complete, mlKem: 'complete-key'),
            );
            final blockedBefore = (await aliceContacts.getContact(
              _blocked.peerId,
            ))!.toMap();
            final completeBefore = (await aliceContacts.getContact(
              _complete.peerId,
            ))!.toMap();
            network.resetCounters();
            aliceP2p = _ReconnectService(
              peerId: _alice.peerId,
              network: network,
            );
            receiver = ContactRequestListener(
              contactRequestStream: bobP2p.messageStream,
              requestRepo: bobRequests,
              contactRepo: bobContacts,
              bridge: bobBridge,
              getOwnPeerId: () => _bob.peerId,
              getOwnPrivateKey: () async => _bob.privateKey,
              downloadProfilePictureFn:
                  ({
                    required bridge,
                    required contactRepo,
                    required ownerPeerId,
                    required avatarVersion,
                    bool retryPendingRequest = false,
                  }) async => null,
            );
            requestSubscription = receiver.requestStream.listen((request) {
              prompts.add(request);
              if (!firstPending.isCompleted) firstPending.complete();
            });
            receiver.start();
            final coordinator = KeyExchangeRetryCoordinator(
              performRetry: () async {
                final count = await retryIncompleteKeyExchanges(
                  contactRepo: aliceContacts,
                  identityRepo: aliceIdentity,
                  p2pService: aliceP2p,
                  bridge: bridge,
                  secureKeyStore: keys,
                );
                if (!retryCompleted.isCompleted) retryCompleted.complete(count);
                return count;
              },
            );
            retrier = KeyExchangeRetrier(
              p2pService: aliceP2p,
              contactRepo: aliceContacts,
              identityRepo: aliceIdentity,
              bridge: bridge,
              coordinator: coordinator,
            );
            retrier.start();
            // This is the production state-stream/debounce/coordinator entry,
            // not a direct invocation of the retry function by the test.
            aliceP2p.reconnect();
            final count = await retryCompleted.future.timeout(
              const Duration(seconds: 10),
            );
            if (recoveryState == _RecoveryState.ready) {
              expect(count, 1);
              await firstPending.future.timeout(const Duration(seconds: 5));
              expect(network.deliverCallCount, 1);
              expect(network.storeInInboxCallCount, 0);
              expect(await readMlKemReannounceMarker(keys), isEmpty);
              expect(prompts, hasLength(1));
              expect(prompts.single.peerId, _alice.peerId);
              expect(prompts.single.mlKemPublicKey, 'alice-mlkem');
              expect(
                (await bobRequests.getPendingRequests()).single.peerId,
                _alice.peerId,
              );
              // A delivered request does not silently grant contact consent.
              expect(await bobContacts.getContactCount(), 0);
              expect(await retrier.retryNow(trigger: 'app_resumed'), 0);
              expect(network.deliverCallCount, 1);
            } else {
              expect(count, 0);
              expect(network.deliverCallCount, 0);
              expect(network.storeInInboxCallCount, 0);
              expect(await readMlKemReannounceMarker(keys), [_bob.peerId]);
              expect(prompts, isEmpty);
              expect(await bobRequests.getPendingRequests(), isEmpty);
              expect(await bobContacts.getContactCount(), 0);
            }
            expect(
              (await aliceContacts.getContact(_blocked.peerId))!.toMap(),
              blockedBefore,
            );
            expect(
              (await aliceContacts.getContact(_complete.peerId))!.toMap(),
              completeBefore,
            );
            retrier.dispose();
            receiver.dispose();
            await requestSubscription.cancel();
            requestSubscription = null;
            await bobDb.close();
            bobDb = await openRepairTestDatabase(bobPath);
            final persisted = await buildWidgetRequestRepository(
              bobDb,
            ).getPendingRequests();
            expect(
              persisted,
              hasLength(recoveryState == _RecoveryState.ready ? 1 : 0),
            );
            if (persisted.isNotEmpty) {
              expect(persisted.single.peerId, _alice.peerId);
              expect(persisted.single.status, ContactRequestStatus.pending);
              expect(persisted.single.mlKemPublicKey, 'alice-mlkem');
            }
            expect(await databaseContactRepository(bobDb).getContactCount(), 0);
            expect(find.byType(QRScannerScreen), findsNothing);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            debugSetFlowEventSink(null);
            retrier?.dispose();
            receiver?.dispose();
            await requestSubscription?.cancel();
            scannerListener.dispose();
            chatListener.dispose();
            aliceP2p.dispose();
            bobP2p.dispose();
            if (aliceDb.isOpen) await aliceDb.close();
            if (bobDb.isOpen) await bobDb.close();
            await directory.delete(recursive: true);
          }
        });
      },
    );
  }
}
