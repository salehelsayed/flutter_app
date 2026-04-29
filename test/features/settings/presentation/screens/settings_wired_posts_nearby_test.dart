import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/posts/domain/models/posts_privacy_settings.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_wired.dart';

import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

class _FakeBridge implements Bridge {
  @override
  Future<String> send(String message) async {
    return jsonEncode({'ok': true});
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  bool get isInitialized => true;

  @override
  void Function(ChatMessage)? onMessageReceived;

  @override
  void Function(p2p.ConnectionState)? onPeerConnected;

  @override
  void Function(p2p.ConnectionState)? onPeerDisconnected;

  @override
  void Function(List<String> listenAddresses, List<String> circuitAddresses)?
  onAddressesUpdated;

  @override
  void Function(Map<String, dynamic>)? onRelayStateChanged;

  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;

  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;
}

class _FakeP2PService implements P2PService {
  @override
  NodeState get currentState => const NodeState(isStarted: true);

  @override
  Stream<NodeState> get stateStream => const Stream.empty();

  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      false;

  @override
  Future<void> warmBackground() async {}

  @override
  Future<bool> stopNode() async => true;

  @override
  Future<bool> sendMessage(String peerId, String message) async => true;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async => const SendMessageResult(sent: true);

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async =>
      null;

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  }) async => true;

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async => false;

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async =>
      [];

  @override
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  bool isLocalPeer(String peerId) => false;

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async => false;

  @override
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
  }) async => false;

  @override
  String? get lastRecoveryMethod => null;

  @override
  void dispose() {}
}

class _FakeNearbyLocationService implements NearbyLocationService {
  int loadComposeAvailabilityCallCount = 0;
  int refreshSilentlyOnStartupCallCount = 0;
  int refreshSilentlyOnResumeCallCount = 0;
  int refreshSilentlyOnPostsOpenCallCount = 0;
  int refreshInteractivelyFromSettingsCallCount = 0;
  int refreshInteractivelyFromComposeCallCount = 0;
  int handleSharingDisabledCallCount = 0;

  @override
  Future<NearbyComposeAvailability> loadComposeAvailability() async {
    loadComposeAvailabilityCallCount++;
    return const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.sharingOff,
    );
  }

  @override
  Future<NearbyComposeAvailability> refreshInteractivelyFromCompose() async {
    refreshInteractivelyFromComposeCallCount++;
    return const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.ready,
    );
  }

  @override
  Future<NearbyComposeAvailability> refreshInteractivelyFromSettings() async {
    refreshInteractivelyFromSettingsCallCount++;
    return const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.ready,
    );
  }

  @override
  Future<NearbyComposeAvailability> refreshSilentlyOnPostsOpen() async {
    refreshSilentlyOnPostsOpenCallCount++;
    return const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.stale,
    );
  }

  @override
  Future<NearbyComposeAvailability> refreshSilentlyOnResume() async {
    refreshSilentlyOnResumeCallCount++;
    return const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.stale,
    );
  }

  @override
  Future<NearbyComposeAvailability> refreshSilentlyOnStartup() async {
    refreshSilentlyOnStartupCallCount++;
    return const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.stale,
    );
  }

  @override
  Future<void> handleSharingDisabled() async {
    handleSharingDisabledCallCount++;
  }

  @override
  Future<bool> openAppSettings() async => true;
}

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeIdentityRepository identityRepo,
    required InMemoryPostsPrivacySettingsRepository privacyRepository,
    NearbyLocationService? nearbyLocationService,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsWired(
          identityRepo: identityRepo,
          bridge: _FakeBridge(),
          contactRepo: FakeContactRepository(),
          p2pService: _FakeP2PService(),
          secureKeyStore: FakeSecureKeyStore(),
          imageProcessor: ImageProcessor(),
          appShellController: AppShellController(),
          postsPrivacySettingsRepository: privacyRepository,
          nearbyLocationService: nearbyLocationService,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('toggle writes nearby sharing state through the repository', (
    tester,
  ) async {
    final identityRepository = FakeIdentityRepository()
      ..seed(
        IdentityModel(
          peerId: 'peer-self',
          publicKey: 'pk-self',
          privateKey: 'sk-self',
          mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
          username: 'Alice',
          createdAt: '2026-03-15T10:00:00.000Z',
          updatedAt: '2026-03-15T10:00:00.000Z',
        ),
      );
    final privacyRepository = InMemoryPostsPrivacySettingsRepository(
      initialSettings: const PostsPrivacySettings(sharingEnabled: false),
    );

    await pumpScreen(
      tester,
      identityRepo: identityRepository,
      privacyRepository: privacyRepository,
    );

    expect(find.text('Share People Nearby'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(
      find.text(
        'Shares only an approximate location with direct friends. No live maps, and never strangers.',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byType(Switch).first);
    await tester.pump();
    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 100));

    final settings = await privacyRepository.load();
    expect(settings.sharingEnabled, isTrue);
    expect(find.text('On'), findsOneWidget);
  });

  testWidgets('enabling nearby sharing triggers interactive refresh', (
    tester,
  ) async {
    final identityRepository = FakeIdentityRepository()
      ..seed(
        IdentityModel(
          peerId: 'peer-self',
          publicKey: 'pk-self',
          privateKey: 'sk-self',
          mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
          username: 'Alice',
          createdAt: '2026-03-15T10:00:00.000Z',
          updatedAt: '2026-03-15T10:00:00.000Z',
        ),
      );
    final privacyRepository = InMemoryPostsPrivacySettingsRepository(
      initialSettings: const PostsPrivacySettings(sharingEnabled: false),
    );
    final nearbyLocationService = _FakeNearbyLocationService();

    await pumpScreen(
      tester,
      identityRepo: identityRepository,
      privacyRepository: privacyRepository,
      nearbyLocationService: nearbyLocationService,
    );

    await tester.ensureVisible(find.byType(Switch).first);
    await tester.pump();
    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 100));

    expect(nearbyLocationService.refreshInteractivelyFromSettingsCallCount, 1);
  });

  testWidgets('disabling nearby sharing publishes inactive before clearing', (
    tester,
  ) async {
    final identityRepository = FakeIdentityRepository()
      ..seed(
        IdentityModel(
          peerId: 'peer-self',
          publicKey: 'pk-self',
          privateKey: 'sk-self',
          mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
          username: 'Alice',
          createdAt: '2026-03-15T10:00:00.000Z',
          updatedAt: '2026-03-15T10:00:00.000Z',
        ),
      );
    final privacyRepository = InMemoryPostsPrivacySettingsRepository(
      initialSettings: const PostsPrivacySettings(
        sharingEnabled: true,
        permissionState: PostsLocationPermissionState.granted,
        lastLocalLatE3: 52520,
        lastLocalLngE3: 13405,
        lastLocalCapturedAt: '2026-03-15T10:00:00.000Z',
        lastLocalAccuracyM: 120,
      ),
    );
    final nearbyLocationService = _FakeNearbyLocationService();

    await pumpScreen(
      tester,
      identityRepo: identityRepository,
      privacyRepository: privacyRepository,
      nearbyLocationService: nearbyLocationService,
    );

    await tester.ensureVisible(find.byType(Switch).first);
    await tester.pump();
    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 100));

    final settings = await privacyRepository.load();
    expect(settings.sharingEnabled, isFalse);
    expect(settings.lastLocalCapturedAt, isNull);
    expect(nearbyLocationService.handleSharingDisabledCallCount, 1);
  });
}
