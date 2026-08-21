import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/debug/auto_setup_config.dart';
import 'package:flutter_app/core/debug/group_media_disposable_transport_start.dart';
import 'package:flutter_app/core/debug/group_media_ios_background_e2e.dart';
import 'package:flutter_app/core/debug/group_media_ios_background_e2e_main_actions.dart';
import 'package:flutter_app/core/debug/group_media_ios_background_e2e_overlay.dart';
import 'package:flutter_app/core/debug/group_media_ios_disposable_profile.dart';
import 'package:flutter_app/core/debug/group_media_ios_disposable_reset.dart';
import 'package:flutter_app/core/debug/group_media_reliability_e2e.dart';
import 'package:flutter_app/core/debug/group_media_reliability_e2e_main_actions.dart';
import 'package:flutter_app/core/debug/intro_e2e_runner.dart';
import 'package:flutter_app/core/debug/ios_receiver_bootstrap.dart';
import 'package:flutter_app/core/debug/ios_receiver_bootstrap_contract.dart';
import 'package:flutter_app/core/debug/ios_sender_projection_fixture.dart';
import 'package:flutter_app/core/debug/ios_sender_projection_fixture_contract.dart';
import 'package:flutter_app/core/debug/private_media_outbox_e2e.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/debug/wake_token_directionality_e2e.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/direct_reaction_notification_projection.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/debug/group_notification_projection_e2e_action.dart';
import 'package:flutter_app/debug/group_strict_notification_e2e_action.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
import 'package:flutter_app/features/contact_request/data/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contacts/application/add_contact_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/data/repositories/media_attachment_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/reaction_repository_impl.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/groups/application/accept_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_media_delete_for_me_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/retry_incomplete_group_downloads_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_app/features/groups/data/repositories/group_history_gap_repair_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_invite_delivery_attempt_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_message_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_reaction_replay_outbox_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/pending_group_invite_repository_impl.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/identity/application/generate_identity_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/p2p/application/start_node_use_case.dart';
import 'package:flutter_app/features/push/application/push_envelope_staging.dart';
import 'package:flutter_app/features/push/application/wake_token_wiring.dart';
import 'package:flutter_app/features/push/domain/received_wake_token_store.dart';
import 'package:flutter_app/features/push/domain/wake_token_store.dart';
import 'package:flutter_app/features/qr_code/application/build_qr_payload_use_case.dart';
import 'package:flutter_app/features/introduction/data/repositories/introduction_repository_impl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

typedef DebugE2EReliabilityControllerFactory =
    GroupMediaReliabilityE2EController Function(Directory stateDirectory);
typedef DebugE2EIosBackgroundControllerFactory =
    GroupMediaIosBackgroundE2EController Function(Directory stateDirectory);

final class DebugE2EGroupMediaDownloadHooks {
  DebugE2EGroupMediaDownloadHooks._({
    required GroupMediaReliabilityE2EController reliabilityController,
    required GroupMediaIosBackgroundE2EController iosBackgroundController,
    required Future<MediaAttachment?> Function(String) loadCurrentAttachment,
  }) : _reliabilityController = reliabilityController,
       _iosBackgroundController = iosBackgroundController,
       _loadCurrentAttachment = loadCurrentAttachment;

  final GroupMediaReliabilityE2EController _reliabilityController;
  final GroupMediaIosBackgroundE2EController _iosBackgroundController;
  final Future<MediaAttachment?> Function(String) _loadCurrentAttachment;

  Future<void> onAutomaticDownloadAttemptStarted(MediaAttachment attachment) =>
      _reliabilityController.onAutomaticDownloadAttemptStarted(
        attachment: attachment,
      );

  Future<void> onPostClaimPreCommit(MediaAttachment attachment) async {
    await _reliabilityController.onPostClaimPreCommit(
      attachment: attachment,
      loadCurrentAttachment: _loadCurrentAttachment,
    );
    await _iosBackgroundController.onPostClaimPreCommit(
      attachment: attachment,
      loadCurrentAttachment: _loadCurrentAttachment,
    );
  }
}

final class DebugE2EPollerDependencies {
  const DebugE2EPollerDependencies({
    required this.documentsDirectory,
    required this.navigatorKey,
    required this.p2pService,
    required this.bridge,
    required this.identityRepository,
    required this.contactRepository,
    required this.contactRequestRepository,
    required this.introductionRepository,
    required this.messageRepository,
    required this.pushEnvelopeStagingStore,
    required this.mediaAttachmentRepository,
    required this.mediaFileManager,
    required this.audioRecorderService,
    required this.database,
    required this.secureKeyStore,
    required this.wakeTokenStore,
    required this.receivedWakeTokenStore,
    required this.pendingGroupInviteRepository,
    required this.groupRepository,
    required this.groupMessageRepository,
    required this.reactionRepository,
    required this.groupMessageListener,
    required this.groupInviteDeliveryAttemptRepository,
    required this.pendingMessageRetrier,
    required this.groupMediaDownloadCoordinator,
    required this.groupConversationTracker,
    required this.conversationTracker,
    required this.groupMediaDeleteForMeCoordinator,
    required this.imageProcessor,
    required this.appShellController,
    required this.groupReactionReplayOutboxRepository,
    required this.groupHistoryGapRepairRepository,
    required this.chatMessageListener,
    required this.reactionListener,
    required this.transportMetrics,
    required this.allowsAccountRuntimeNetworkSideEffects,
    required this.wakeTokenResolver,
  });

  final Directory documentsDirectory;
  final GlobalKey<NavigatorState> navigatorKey;
  final P2PServiceImpl p2pService;
  final Bridge bridge;
  final IdentityRepositoryImpl identityRepository;
  final ContactRepositoryImpl contactRepository;
  final ContactRequestRepositoryImpl contactRequestRepository;
  final IntroductionRepositoryImpl introductionRepository;
  final MessageRepositoryImpl messageRepository;
  final PushEnvelopeStagingStore pushEnvelopeStagingStore;
  final MediaAttachmentRepositoryImpl mediaAttachmentRepository;
  final MediaFileManager mediaFileManager;
  final AudioRecorderService audioRecorderService;
  final sqlcipher.Database database;
  final SecureKeyStore secureKeyStore;
  final WakeTokenStore wakeTokenStore;
  final ReceivedWakeTokenStore receivedWakeTokenStore;
  final PendingGroupInviteRepositoryImpl pendingGroupInviteRepository;
  final GroupRepositoryImpl groupRepository;
  final GroupMessageRepositoryImpl groupMessageRepository;
  final ReactionRepositoryImpl reactionRepository;
  final GroupMessageListener groupMessageListener;
  final GroupInviteDeliveryAttemptRepositoryImpl
  groupInviteDeliveryAttemptRepository;
  final PendingMessageRetrier pendingMessageRetrier;
  final GroupMediaDownloadCoordinator? groupMediaDownloadCoordinator;
  final ActiveConversationTracker groupConversationTracker;
  final ActiveConversationTracker conversationTracker;
  final GroupMediaDeleteForMeCoordinator groupMediaDeleteForMeCoordinator;
  final ImageProcessor imageProcessor;
  final AppShellController appShellController;
  final GroupReactionReplayOutboxRepositoryImpl
  groupReactionReplayOutboxRepository;
  final GroupHistoryGapRepairRepositoryImpl groupHistoryGapRepairRepository;
  final ChatMessageListener chatMessageListener;
  final ReactionListener reactionListener;
  final TransportMetrics? transportMetrics;
  final Future<bool> Function(String operation)
  allowsAccountRuntimeNetworkSideEffects;
  final ResolveWakeTokenForIntroE2EFn wakeTokenResolver;
}

/// Pure compile-time activation policy for the debug/E2E composition module.
///
/// Keeping this value separate from the root makes the production exclusion
/// branch directly testable: [DebugE2ECompositionRoot.tryCreate] evaluates
/// this policy before it constructs any controller or callback bundle.
@immutable
final class DebugE2EActivation {
  const DebugE2EActivation({
    required this.isDebugMode,
    required this.e2eTestMode,
    required this.directTextProofMode,
    required this.installedSimsProfile,
  });

  final bool isDebugMode;
  final bool e2eTestMode;
  final bool directTextProofMode;
  final String installedSimsProfile;

  bool get isAndroidDisposableProfile =>
      installedSimsProfile == groupMediaAndroidDisposableBuildProfile;

  bool get isIosDisposableProfile =>
      installedSimsProfile == groupMediaIosDisposableBuildProfile;

  bool get isIosProductionProofProfile =>
      installedSimsProfile == iosReceiverBootstrapBuildProfile;

  bool get constructsControllerRoot =>
      (isDebugMode && (e2eTestMode || directTextProofMode)) ||
      (e2eTestMode && isIosDisposableProfile) ||
      isIosProductionProofProfile;

  bool get constructsPrivateMediaController => constructsControllerRoot;
  bool get constructsWakeTokenObserver => constructsControllerRoot;
  bool get startsIntroPoller =>
      (isDebugMode && (e2eTestMode || directTextProofMode)) ||
      (e2eTestMode && isIosDisposableProfile);
  bool get startsIosSenderProjection => isIosProductionProofProfile;
  bool get publishesIosReceiverBootstrap => isIosProductionProofProfile;
  bool get decoratesIosGroupMediaProof => isIosDisposableProfile;
  bool get suppliesDisposableNodeStart =>
      isAndroidDisposableProfile || isIosDisposableProfile;
}

/// Owns the debug/E2E-only objects composed around the production application.
///
/// The object is created at most once from [main]. Ordinary empty-profile
/// production launches receive `null`, so no harness controller, observer,
/// scheduler, dependency bundle, or callback closure is retained.
final class DebugE2ECompositionRoot {
  DebugE2ECompositionRoot._({
    required this.activation,
    required GroupMediaReliabilityE2EController
    groupMediaReliabilityE2EController,
    required GroupMediaIosBackgroundE2EController
    groupMediaIosBackgroundE2EController,
  }) : _groupMediaReliabilityE2EController = groupMediaReliabilityE2EController,
       _groupMediaIosBackgroundE2EController =
           groupMediaIosBackgroundE2EController;

  final DebugE2EActivation activation;
  final GroupMediaReliabilityE2EController _groupMediaReliabilityE2EController;
  final GroupMediaIosBackgroundE2EController
  _groupMediaIosBackgroundE2EController;

  PrivateMediaOutboxE2EController? _privateMediaOutboxE2EController;
  WakeTokenAcceptedAttachmentObserver? _wakeTokenAttachmentObserver;

  static const bool isInstalledIosDisposableProfile =
      String.fromEnvironment('SIMS_BUILD_PROFILE_ID') ==
      groupMediaIosDisposableBuildProfile;
  static const bool isInstalledDisposableProfile =
      String.fromEnvironment('SIMS_BUILD_PROFILE_ID') ==
          groupMediaAndroidDisposableBuildProfile ||
      isInstalledIosDisposableProfile;

  bool get startsIntroPoller => activation.startsIntroPoller;

  static DebugE2ECompositionRoot? tryCreate({
    required Directory stateDirectory,
    DebugE2EActivation activation = const DebugE2EActivation(
      isDebugMode: kDebugMode,
      e2eTestMode: bool.fromEnvironment('E2E_TEST_MODE'),
      directTextProofMode: bool.fromEnvironment(
        'MKNOON_DIRECT_TEXT_RELAY_TOKEN_PROOF',
      ),
      installedSimsProfile: String.fromEnvironment('SIMS_BUILD_PROFILE_ID'),
    ),
    DebugE2EReliabilityControllerFactory? reliabilityControllerFactory,
    DebugE2EIosBackgroundControllerFactory? iosBackgroundControllerFactory,
  }) {
    if (!activation.constructsControllerRoot) return null;
    final createReliabilityController =
        reliabilityControllerFactory ??
        (directory) => GroupMediaReliabilityE2EController.forInstalledProfile(
          stateDirectory: directory,
          installedProfileId: activation.installedSimsProfile,
        );
    final createIosBackgroundController =
        iosBackgroundControllerFactory ??
        (directory) => GroupMediaIosBackgroundE2EController.forInstalledProfile(
          stateDirectory: directory,
          installedProfileId: activation.installedSimsProfile,
        );
    return DebugE2ECompositionRoot._(
      activation: activation,
      groupMediaReliabilityE2EController: createReliabilityController(
        stateDirectory,
      ),
      groupMediaIosBackgroundE2EController: createIosBackgroundController(
        stateDirectory,
      ),
    );
  }

  static Future<bool> runDisposableResetIfRequested() async {
    const installedSimsProfile = String.fromEnvironment(
      'SIMS_BUILD_PROFILE_ID',
    );
    final isGroupMediaIosDisposableProfile =
        installedSimsProfile == groupMediaIosDisposableBuildProfile;
    final isGroupMediaAndroidDisposableProfile =
        installedSimsProfile == groupMediaAndroidDisposableBuildProfile;
    if (!isGroupMediaIosDisposableProfile &&
        !isGroupMediaAndroidDisposableProfile) {
      return false;
    }
    if ((isGroupMediaIosDisposableProfile && !Platform.isIOS) ||
        (isGroupMediaAndroidDisposableProfile && !Platform.isAndroid)) {
      throw StateError('dedicated group-media reset platform rejected');
    }
    const configuredIosBundleId = String.fromEnvironment(
      'SIMS_IOS_DISPOSABLE_BUNDLE_ID',
    );
    const configuredAndroidPackageId = String.fromEnvironment(
      'SIMS_ANDROID_DISPOSABLE_PACKAGE_ID',
    );
    final expectedBundleId = isGroupMediaIosDisposableProfile
        ? groupMediaIosDisposableBundleId
        : groupMediaAndroidDisposablePackageId;
    final expectedProfileId = isGroupMediaIosDisposableProfile
        ? groupMediaIosDisposableBuildProfile
        : groupMediaAndroidDisposableBuildProfile;
    final configuredBundleId = isGroupMediaIosDisposableProfile
        ? configuredIosBundleId
        : configuredAndroidPackageId;
    if (configuredBundleId != expectedBundleId) {
      throw StateError('dedicated group-media reset bundle define rejected');
    }
    final resetPackageInfoProbe = PackageInfo.fromPlatform();
    final resetDocumentsDirectoryProbe = getApplicationDocumentsDirectory();
    final resetDatabasesPathProbe = sqlcipher.getDatabasesPath();
    final resetApplicationSupportDirectoryProbe =
        getApplicationSupportDirectory();
    await Future.wait<Object?>([
      resetPackageInfoProbe,
      resetDocumentsDirectoryProbe,
      resetDatabasesPathProbe,
      resetApplicationSupportDirectoryProbe,
    ]);
    final packageInfo = await resetPackageInfoProbe;
    final resetStore = FlutterSecureKeyStore();
    return runGroupMediaIosDisposableResetIfRequested(
      documentsDirectory: await resetDocumentsDirectoryProbe,
      databasesDirectory: Directory(await resetDatabasesPathProbe),
      applicationSupportDirectory: await resetApplicationSupportDirectoryProbe,
      installedProfileId: installedSimsProfile,
      installedBundleId: packageInfo.packageName,
      expectedProfileId: expectedProfileId,
      expectedBundleId: expectedBundleId,
      deleteDefaultSecureStorage: resetStore.deleteAll,
      readDefaultSecureStorage: resetStore.readAll,
    );
  }

  PrivateMediaOutboxE2EController initializePrivateMediaController() {
    return _privateMediaOutboxE2EController ??= PrivateMediaOutboxE2EController(
      enabled: activation.isDebugMode && activation.e2eTestMode,
    );
  }

  void Function({
    required String toPeerIdSha256,
    required String messageSha256,
    required String wakeTokenSha256,
  })?
  initializeWakeTokenObserver() {
    final observer = _wakeTokenAttachmentObserver ??=
        WakeTokenAcceptedAttachmentObserver();
    return activation.e2eTestMode ? observer.observeAccepted : null;
  }

  bool get holdsAutomaticGroupMediaRecovery =>
      _groupMediaReliabilityE2EController.holdsAutomaticRecovery ||
      _groupMediaIosBackgroundE2EController.holdsAutomaticRecovery;

  DebugE2EGroupMediaDownloadHooks bindGroupMediaDownloadHooks({
    required Future<MediaAttachment?> Function(String) loadCurrentAttachment,
  }) {
    return DebugE2EGroupMediaDownloadHooks._(
      reliabilityController: _groupMediaReliabilityE2EController,
      iosBackgroundController: _groupMediaIosBackgroundE2EController,
      loadCurrentAttachment: loadCurrentAttachment,
    );
  }

  static Future<void> runSimulatorAutoSetupIfConfigured({
    required String documentsPath,
    required IdentityRepositoryImpl identityRepository,
    required Bridge bridge,
  }) async {
    final autoSetupUsername = await resolveAutoSetupUsername(documentsPath);
    if (autoSetupUsername == null) return;

    final existing = await identityRepository.loadIdentity();
    if (existing == null) {
      final result = await generateNewIdentity(
        callGenerate: () => callIdentityGenerate(bridge),
        callMlKemKeygen: () => callMlKemKeygen(bridge),
        repo: identityRepository,
      );
      if (result != GenerateIdentityResult.success) return;
      final identity = await identityRepository.loadIdentity();
      if (identity == null) return;
      await identityRepository.saveIdentity(
        IdentityModel(
          peerId: identity.peerId,
          publicKey: identity.publicKey,
          privateKey: identity.privateKey,
          mnemonic12: identity.mnemonic12,
          mlKemPublicKey: identity.mlKemPublicKey,
          mlKemSecretKey: identity.mlKemSecretKey,
          username: autoSetupUsername,
          avatarBlob: identity.avatarBlob,
          avatarVersion: identity.avatarVersion,
          createdAt: identity.createdAt,
          updatedAt: identity.updatedAt,
        ),
      );
      if (kDebugMode) {
        print('[AUTO-SETUP] Identity created: $autoSetupUsername');
      }
      await _exportIdentity(identityRepository, bridge);
      return;
    }

    if (kDebugMode) {
      print('[AUTO-SETUP] Identity already exists, ensuring export');
    }
    await _exportIdentity(identityRepository, bridge, cachedIdentity: existing);
  }

  static Future<void> _exportIdentity(
    IdentityRepositoryImpl identityRepository,
    Bridge bridge, {
    IdentityModel? cachedIdentity,
  }) async {
    final (qrResult, qrJson) = await buildQRPayload(
      repo: identityRepository,
      callSign: (data, key) =>
          callSignPayload(bridge: bridge, dataToSign: data, privateKey: key),
      cachedIdentity: cachedIdentity ?? await identityRepository.loadIdentity(),
    );
    if (qrResult != BuildQRPayloadResult.success || qrJson == null) return;
    final loadedIdentity =
        cachedIdentity ?? await identityRepository.loadIdentity();
    await exportIdentityForIntroE2E(
      signedQrPayloadJson: qrJson,
      mlKemPublicKey: loadedIdentity?.mlKemPublicKey,
    );
  }

  Future<void> prepopulateContactsBeforeRunApp({
    required bool isShareLaunch,
    required ContactRepositoryImpl contactRepository,
  }) async {
    if (activation.isDebugMode && activation.e2eTestMode && !isShareLaunch) {
      await prePopulateContactsFromIntroE2EConfig(
        contactRepo: contactRepository,
      );
    }
  }

  Widget Function(Widget)? get overlayBuilder {
    if (!_groupMediaIosBackgroundE2EController.enabled) return null;
    return (child) => GroupMediaIosBackgroundE2EOverlay(
      labels: _groupMediaIosBackgroundE2EController.uiProofLabels,
      child: child,
    );
  }

  Future<StartNodeResult> Function()? buildDisposableNodeStart({
    required IdentityRepositoryImpl identityRepository,
    required SecureKeyStore secureKeyStore,
    required Bridge bridge,
    required P2PServiceImpl p2pService,
  }) {
    if (!activation.suppliesDisposableNodeStart) return null;
    return () {
      final migrationGate = AccountMigrationRuntimeNetworkGate(
        authorityRepository: SecureKeyStoreAccountMigrationAuthorityRepository(
          secureKeyStore: secureKeyStore,
        ),
      );
      return startGroupMediaDisposableTransportNode(
        identityRepository: identityRepository,
        secureKeyStore: secureKeyStore,
        generateIdentity: () => callIdentityGenerate(bridge),
        startNode: p2pService.startNode,
        currentTransportPeerId: () => p2pService.currentState.peerId,
        accountMigrationNetworkGate:
            migrationGate.allowsAccountNetworkSideEffects,
      );
    };
  }

  Future<void> Function()? buildReceiverPublication({
    required IdentityRepositoryImpl identityRepository,
    required P2PServiceImpl p2pService,
  }) {
    if (!activation.publishesIosReceiverBootstrap) return null;
    return () => publishIosReceiverBootstrapIdentityWhenReady(
      currentPeerId: () => p2pService.currentState.peerId,
      peerIds: p2pService.stateStream.map((state) => state.peerId),
      loadMlKemPublicKey: () async =>
          (await identityRepository.loadIdentity())?.mlKemPublicKey,
    );
  }

  void startIosSenderProjectionAfterRunApp({
    required DirectReactionNotificationProjection?
    directReactionNotificationProjection,
    required IdentityRepositoryImpl identityRepository,
    required ContactRepositoryImpl contactRepository,
    required sqlcipher.Database database,
  }) {
    if (!activation.startsIosSenderProjection ||
        directReactionNotificationProjection == null) {
      return;
    }
    final fixtureStore = IosSenderProjectionFixtureStore(
      loadLocalAccountPeerId: () async =>
          (await identityRepository.loadIdentity())?.peerId,
      loadProjectionAccountPeerId:
          directReactionNotificationProjection.readLocalAccountPeerId,
      loadContact: contactRepository.getContact,
      insertContactIfAbsent: (contact) =>
          dbSimsInsertContactIfAbsent(database, contact.toMap()),
      deleteContactIfExact: (contact) =>
          dbSimsDeleteContactIfExact(database, contact.toMap()),
      loadProjectedContact: (peerId) async =>
          (await directReactionNotificationProjection.readContacts())[peerId],
      insertProjectedContactIfAbsent: (request) =>
          directReactionNotificationProjection.insertSimsFixtureContactIfAbsent(
            peerId: request.senderPeerId,
            username: request.senderUsername,
            fixtureDigest: request.fixtureDigest,
          ),
      deleteProjectedContactIfExact: (request) =>
          directReactionNotificationProjection.removeSimsFixtureContactIfExact(
            peerId: request.senderPeerId,
            username: request.senderUsername,
            fixtureDigest: request.fixtureDigest,
          ),
    );
    unawaited(
      runIosSenderProjectionFixtureLoop(
        coordinator: IosSenderProjectionFixtureCoordinator(fixtureStore),
      ),
    );
  }

  void startIntroPollerAfterColdRecovery(
    DebugE2EPollerDependencies dependencies,
  ) {
    if (!activation.startsIntroPoller) return;
    final wakeTokenAttachmentObserver = _wakeTokenAttachmentObserver;
    final privateMediaOutboxE2EController = _privateMediaOutboxE2EController;
    if (wakeTokenAttachmentObserver == null ||
        privateMediaOutboxE2EController == null) {
      throw StateError('debug E2E controller phases were not initialized');
    }

    Future<void> awaitGroupMediaProofEndpointReady(
      String operation, {
      GroupMediaIosProofReadiness requirement =
          GroupMediaIosProofReadiness.fullRelayCustody,
    }) async {
      final deadline = DateTime.now().add(const Duration(seconds: 120));
      while (DateTime.now().isBefore(deadline)) {
        final state = dependencies.p2pService.currentState;
        if (groupMediaIosProofEndpointReady(state, requirement: requirement) &&
            await dependencies.allowsAccountRuntimeNetworkSideEffects(
              operation,
            )) {
          return;
        }
        try {
          await dependencies.p2pService.performImmediateHealthCheck();
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      throw StateError(
        'group-media reliability endpoint did not reach gated readiness',
      );
    }

    Future<Map<String, Object?>?> acceptGroupMediaProofInvite(
      String groupId,
    ) async {
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (DateTime.now().isBefore(deadline) &&
          await dependencies.pendingGroupInviteRepository.getPendingInvite(
                groupId,
              ) ==
              null) {
        await dependencies.p2pService.performImmediateHealthCheck();
        await dependencies.p2pService.drainOfflineInbox();
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (await dependencies.pendingGroupInviteRepository.getPendingInvite(
            groupId,
          ) ==
          null) {
        return null;
      }
      final identity = await dependencies.identityRepository.loadIdentity();
      final transportPeerId = dependencies.p2pService.currentState.peerId
          ?.trim();
      if (identity == null ||
          transportPeerId == null ||
          transportPeerId.isEmpty ||
          identity.peerId == transportPeerId) {
        return null;
      }
      final accepted = await acceptPendingGroupInvite(
        pendingInviteRepo: dependencies.pendingGroupInviteRepository,
        groupRepo: dependencies.groupRepository,
        contactRepo: dependencies.contactRepository,
        msgRepo: dependencies.groupMessageRepository,
        bridge: dependencies.bridge,
        groupId: groupId,
        mediaAttachmentRepo: dependencies.mediaAttachmentRepository,
        reactionRepo: dependencies.reactionRepository,
        groupMessageListener: dependencies.groupMessageListener,
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        senderUsername: identity.username,
        ownDeviceId: transportPeerId,
        ownTransportPeerId: transportPeerId,
        ownMlKemPublicKey: identity.mlKemPublicKey,
        ownKeyPackageId: defaultGroupWelcomeKeyPackageIdForDevice(
          transportPeerId,
        ),
        ownKeyPackagePublicMaterial: identity.mlKemPublicKey,
      );
      if (accepted.$1 != AcceptPendingGroupInviteResult.success ||
          accepted.$2?.id != groupId) {
        return null;
      }
      return <String, Object?>{
        'accountPeerId': identity.peerId,
        'transportPeerId': transportPeerId,
      };
    }

    startIntroE2EPoller(
      p2pService: dependencies.p2pService,
      bridge: dependencies.bridge,
      identityRepo: dependencies.identityRepository,
      contactRepo: dependencies.contactRepository,
      contactRequestRepo: dependencies.contactRequestRepository,
      introRepo: dependencies.introductionRepository,
      messageRepo: dependencies.messageRepository,
      pushEnvelopeStagingStore: dependencies.pushEnvelopeStagingStore,
      mediaAttachmentRepo: dependencies.mediaAttachmentRepository,
      mediaFileManager: dependencies.mediaFileManager,
      audioRecorderService: dependencies.audioRecorderService,
      groupReactionProbeDatabase: dependencies.database,
      groupReactionProbeSecureKeyStore: dependencies.secureKeyStore,
      wakeTokenStore: dependencies.wakeTokenStore,
      receivedWakeTokenStore: dependencies.receivedWakeTokenStore,
      registerWakeTokens: (tokens) =>
          registerWakeTokensViaBridge(dependencies.bridge, tokens),
      detailedInboxStore: dependencies.p2pService,
      wakeTokenAttachmentObserver: wakeTokenAttachmentObserver,
      privateMediaOutboxE2EController: privateMediaOutboxE2EController,
      runGroupStrictNotificationE2E: (config) =>
          runGroupStrictNotificationE2EAction(
            config: config,
            database: dependencies.database,
            bridge: dependencies.bridge,
            p2pService: dependencies.p2pService,
            inboxStore: dependencies.p2pService,
            identityRepository: dependencies.identityRepository,
            groupRepository: dependencies.groupRepository,
          ),
      runGroupNotificationProjectionE2E: (config) =>
          runGroupNotificationProjectionE2EAction(
            config: config,
            fixtureDirectory: Directory(
              '${dependencies.documentsDirectory.path}'
              '/plan330-group-notification-fixtures',
            ),
            bridge: dependencies.bridge,
            p2pService: dependencies.p2pService,
            identityRepository: dependencies.identityRepository,
            groupRepository: dependencies.groupRepository,
            groupMessageRepository: dependencies.groupMessageRepository,
            mediaAttachmentRepository: dependencies.mediaAttachmentRepository,
            audioRecorderService: dependencies.audioRecorderService,
            mediaFileManager: dependencies.mediaFileManager,
            reactionRepository: dependencies.reactionRepository,
            groupReactionReplayOutboxRepository:
                dependencies.groupReactionReplayOutboxRepository,
            inviteDeliveryAttemptRepository:
                dependencies.groupInviteDeliveryAttemptRepository,
          ),
      runGroupMediaReliabilityE2E: (config) async {
        final request = GroupMediaReliabilityE2ERequest.fromConfig(config);
        await awaitGroupMediaProofEndpointReady(
          'p269_group_media_endpoint_ready',
        );

        return runGroupMediaReliabilityE2EAction(
          config: config,
          controller: _groupMediaReliabilityE2EController,
          loadAttachment:
              dependencies.mediaAttachmentRepository.getAttachmentById,
          probeIdentity: (role) async {
            final identity = await dependencies.identityRepository
                .loadIdentity();
            final transportPeerId = dependencies.p2pService.currentState.peerId
                ?.trim();
            if (identity == null ||
                transportPeerId == null ||
                transportPeerId.isEmpty ||
                transportPeerId == identity.peerId) {
              throw StateError(
                'group-media disposable identity authority did not settle',
              );
            }
            return <String, Object?>{
              'accountPeerId': identity.peerId,
              'transportPeerId': transportPeerId,
            };
          },
          setupSender: (receiverAccountPeerId, receiverTransportPeerId) =>
              setupGroupMediaReliabilitySender(
                receiverAccountPeerId: receiverAccountPeerId,
                receiverTransportPeerId: receiverTransportPeerId,
                bridge: dependencies.bridge,
                p2pService: dependencies.p2pService,
                identityRepository: dependencies.identityRepository,
                contactRepository: dependencies.contactRepository,
                groupRepository: dependencies.groupRepository,
                inviteDeliveryAttemptRepository:
                    dependencies.groupInviteDeliveryAttemptRepository,
              ),
          acceptReceiver: acceptGroupMediaProofInvite,
          sendMedia:
              (
                groupId,
                messageIds,
                attachmentIds,
                receiverAccountPeerId,
                receiverTransportPeerId,
              ) => sendGroupMediaReliabilityFixtures(
                runId: request.runId,
                groupId: groupId,
                messageIds: messageIds,
                attachmentIds: attachmentIds,
                receiverAccountPeerId: receiverAccountPeerId,
                receiverTransportPeerId: receiverTransportPeerId,
                fixtureDirectory: Directory(
                  '${dependencies.documentsDirectory.path}'
                  '/p269-group-media-fixtures',
                ),
                bridge: dependencies.bridge,
                p2pService: dependencies.p2pService,
                identityRepository: dependencies.identityRepository,
                groupRepository: dependencies.groupRepository,
                groupConfigBuilder: buildGroupConfigPayload,
                groupMessageRepository: dependencies.groupMessageRepository,
                mediaAttachmentRepository:
                    dependencies.mediaAttachmentRepository,
                mediaFileManager: dependencies.mediaFileManager,
                audioRecorderService: dependencies.audioRecorderService,
                inviteDeliveryAttemptRepository:
                    dependencies.groupInviteDeliveryAttemptRepository,
              ),
          probeRole: (role, messageIds, attachmentIds) => (() {
            final transportPeerId = dependencies.p2pService.currentState.peerId
                ?.trim();
            if (transportPeerId == null || transportPeerId.isEmpty) {
              throw StateError(
                'group-media role database lacks transport authority',
              );
            }
            return probeGroupMediaReliabilityRoleDatabase(
              role: role,
              runId: request.runId,
              transportPeerId: transportPeerId,
              messageIds: messageIds,
              attachmentIds: attachmentIds,
              database: dependencies.database,
              mediaAttachmentRepository: dependencies.mediaAttachmentRepository,
            );
          })(),
          retryUploads: () {
            final retry = dependencies
                .pendingMessageRetrier
                .retryIncompleteGroupUploadsPeriodicFn;
            if (retry == null) {
              throw StateError('periodic group upload retry is not wired');
            }
            return retry();
          },
          retryDownloads: () {
            final retry = dependencies
                .pendingMessageRetrier
                .retryIncompleteGroupDownloadsPeriodicFn;
            if (retry == null) {
              throw StateError('periodic group download retry is not wired');
            }
            return retry();
          },
          renderReceiver: (groupId, messageIds, attachmentIds) async {
            if (messageIds.keys.toSet().length != 3 ||
                attachmentIds.keys.toSet().length != 3 ||
                !messageIds.keys.toSet().containsAll(
                  groupMediaReliabilityRenderLabelsByKind.keys,
                ) ||
                !attachmentIds.keys.toSet().containsAll(
                  groupMediaReliabilityRenderLabelsByKind.keys,
                )) {
              throw StateError('group-media render tuple is incomplete');
            }
            final group = await dependencies.groupRepository.getGroup(groupId);
            if (group == null || group.id != groupId) {
              throw StateError('group-media render group is unavailable');
            }
            NavigatorState? navigator;
            for (var attempt = 0; attempt < 40; attempt++) {
              navigator = dependencies.navigatorKey.currentState;
              if (navigator != null) break;
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            if (navigator == null) {
              throw StateError('group-media render navigator is unavailable');
            }
            final labelsByAttachment = <String, String>{
              for (final kind in groupMediaReliabilityRenderLabelsByKind.keys)
                attachmentIds[kind]!:
                    groupMediaReliabilityRenderLabelsByKind[kind]!,
            };
            final routeBuilt = Completer<void>();
            navigator.popUntil((route) => route.isFirst);
            unawaited(
              navigator.push(
                MaterialPageRoute<void>(
                  builder: (_) {
                    if (!routeBuilt.isCompleted) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!routeBuilt.isCompleted) routeBuilt.complete();
                      });
                    }
                    return GroupConversationWired(
                      group: group,
                      groupRepo: dependencies.groupRepository,
                      msgRepo: dependencies.groupMessageRepository,
                      uploadRetryProjectionRepo:
                          dependencies.groupMessageRepository,
                      groupMessageListener: dependencies.groupMessageListener,
                      groupMediaDownloadCoordinator:
                          dependencies.groupMediaDownloadCoordinator,
                      inviteDeliveryAttemptRepo:
                          dependencies.groupInviteDeliveryAttemptRepository,
                      bridge: dependencies.bridge,
                      identityRepo: dependencies.identityRepository,
                      contactRepo: dependencies.contactRepository,
                      p2pService: dependencies.p2pService,
                      groupConversationTracker:
                          dependencies.groupConversationTracker,
                      openAnnouncementSenderConversation: null,
                      initialHighlightedMessageId: messageIds['jpeg'],
                      mediaAttachmentRepo:
                          dependencies.mediaAttachmentRepository,
                      mediaDeleteForMeCoordinator:
                          dependencies.groupMediaDeleteForMeCoordinator,
                      mediaFileManager: dependencies.mediaFileManager,
                      imageProcessor: dependencies.imageProcessor,
                      audioRecorderService: dependencies.audioRecorderService,
                      reactionRepo: dependencies.reactionRepository,
                      groupReactionReplayOutboxRepository:
                          dependencies.groupReactionReplayOutboxRepository,
                      historyGapRepairRepo:
                          dependencies.groupHistoryGapRepairRepository,
                      backgroundPreference:
                          dependencies.appShellController.backgroundPreference,
                      forwardMessageRepository: dependencies.messageRepository,
                      forwardChatMessageListener:
                          dependencies.chatMessageListener,
                      mediaRenderedSemanticsLabels: labelsByAttachment,
                    );
                  },
                ),
              ),
            );
            await routeBuilt.future.timeout(const Duration(seconds: 10));
            return <String, Object?>{'renderProbeArmed': true};
          },
        );
      },
      runGroupMediaIosBackgroundE2E:
          (
            config, {
            onReceiverObservationAccepted,
            onReceiverObservationComplete,
          }) async {
            final request = GroupMediaIosBackgroundE2ERequest.fromConfig(
              config,
            );
            final readiness = switch (request.phase) {
              groupMediaIosIdentityPhase =>
                GroupMediaIosProofReadiness.identity,
              groupMediaIosReceiverRecoverPhase =>
                GroupMediaIosProofReadiness.receiveRecovery,
              _ => GroupMediaIosProofReadiness.fullRelayCustody,
            };
            await awaitGroupMediaProofEndpointReady(
              'p269_group_media_ios_endpoint_ready',
              requirement: readiness,
            );
            return runGroupMediaIosBackgroundE2EAction(
              config: config,
              controller: _groupMediaIosBackgroundE2EController,
              loadAttachment:
                  dependencies.mediaAttachmentRepository.getAttachmentById,
              exportIdentity: () async {
                final identity = await dependencies.identityRepository
                    .loadIdentity();
                final transportPeerId = dependencies
                    .p2pService
                    .currentState
                    .peerId
                    ?.trim();
                if (identity == null ||
                    transportPeerId == null ||
                    transportPeerId.isEmpty ||
                    identity.peerId == transportPeerId ||
                    identity.mlKemPublicKey?.trim().isNotEmpty != true) {
                  throw StateError(
                    'physical-iOS proof identity authority is unavailable',
                  );
                }
                final (result, qrPayload) = await buildQRPayload(
                  repo: dependencies.identityRepository,
                  callSign: (data, key) => callSignPayload(
                    bridge: dependencies.bridge,
                    dataToSign: data,
                    privateKey: key,
                  ),
                  cachedIdentity: identity,
                );
                if (result != BuildQRPayloadResult.success ||
                    qrPayload == null) {
                  throw StateError(
                    'physical-iOS signed identity export failed',
                  );
                }
                return <String, Object?>{
                  'accountPeerId': identity.peerId,
                  'transportPeerId': transportPeerId,
                  'qrPayload': qrPayload,
                  'mlKemPublicKey': identity.mlKemPublicKey!,
                };
              },
              addContact: (qrPayload, mlKemPublicKey) async {
                final decoded = jsonDecode(qrPayload);
                if (decoded is! Map<String, dynamic>) {
                  throw const FormatException(
                    'physical-iOS signed contact payload rejected',
                  );
                }
                if (mlKemPublicKey != null) {
                  decoded['mlkem'] = mlKemPublicKey;
                }
                final contact = ContactModel.fromQRPayload(decoded);
                final result = await addContact(
                  repository: dependencies.contactRepository,
                  contact: contact,
                );
                if (result != AddContactResult.success &&
                    result != AddContactResult.alreadyExists) {
                  throw StateError('physical-iOS contact persistence failed');
                }
                final stored = await dependencies.contactRepository.getContact(
                  contact.peerId,
                );
                if (stored == null ||
                    stored.publicKey != contact.publicKey ||
                    stored.mlKemPublicKey?.trim().isNotEmpty != true) {
                  throw StateError(
                    'physical-iOS contact authority did not settle',
                  );
                }
              },
              setupSender:
                  (receiverAccountPeerId, receiverTransportPeerId, groupName) =>
                      setupGroupMediaIosBackgroundSender(
                        receiverAccountPeerId: receiverAccountPeerId,
                        receiverTransportPeerId: receiverTransportPeerId,
                        groupName: groupName,
                        bridge: dependencies.bridge,
                        p2pService: dependencies.p2pService,
                        identityRepository: dependencies.identityRepository,
                        contactRepository: dependencies.contactRepository,
                        groupRepository: dependencies.groupRepository,
                        inviteDeliveryAttemptRepository:
                            dependencies.groupInviteDeliveryAttemptRepository,
                      ),
              acceptReceiver: acceptGroupMediaProofInvite,
              sendFixture:
                  (
                    phase,
                    groupId,
                    messageId,
                    attachmentId,
                    marker,
                    receiverAccountPeerId,
                    receiverTransportPeerId,
                  ) => sendGroupMediaIosBackgroundFixture(
                    runId: request.runId,
                    phase: phase,
                    groupId: groupId,
                    messageId: messageId,
                    attachmentId: attachmentId,
                    marker: marker,
                    receiverAccountPeerId: receiverAccountPeerId,
                    receiverTransportPeerId: receiverTransportPeerId,
                    fixtureDirectory: Directory(
                      '${dependencies.documentsDirectory.path}'
                      '/p269-group-media-ios-fixtures',
                    ),
                    bridge: dependencies.bridge,
                    p2pService: dependencies.p2pService,
                    identityRepository: dependencies.identityRepository,
                    groupRepository: dependencies.groupRepository,
                    groupMessageRepository: dependencies.groupMessageRepository,
                    mediaAttachmentRepository:
                        dependencies.mediaAttachmentRepository,
                    mediaFileManager: dependencies.mediaFileManager,
                    inviteDeliveryAttemptRepository:
                        dependencies.groupInviteDeliveryAttemptRepository,
                  ),
              probeDatabase: (phase, messageId, attachmentId) =>
                  reopenGroupMediaIosBackgroundDatabase(
                    runId: request.runId,
                    phase: phase,
                    messageId: messageId,
                    attachmentId: attachmentId,
                    expectedParentMarker: groupMediaIosBackgroundParentMarker(
                      request.runId,
                      phase,
                    ),
                    liveDatabase: dependencies.database,
                    secureKeyStore: dependencies.secureKeyStore,
                  ),
              drainGroupInbox: () async {
                final drain =
                    dependencies.pendingMessageRetrier.drainGroupOfflineInboxFn;
                if (drain == null) {
                  throw StateError('group offline inbox drain is not wired');
                }
                await drain();
              },
              retryDownloads: () {
                final retry = dependencies
                    .pendingMessageRetrier
                    .retryIncompleteGroupDownloadsPeriodicFn;
                if (retry == null) {
                  throw StateError(
                    'periodic group download retry is not wired',
                  );
                }
                return retry();
              },
              reserveReceiveCriticalTask: () async {
                final reservation = await dependencies.groupMessageListener
                    .reserveGroupMediaReceiveCriticalTaskForForegroundHandoff();
                return reservation.release;
              },
              onReceiverObservationAccepted: onReceiverObservationAccepted,
              onReceiverObservationComplete: onReceiverObservationComplete,
            );
          },
      resolveWakeToken: dependencies.wakeTokenResolver,
      openConversationByPeerId: (peerId) async {
        for (var attempt = 0; attempt < 30; attempt++) {
          final navigator = dependencies.navigatorKey.currentState;
          final contact = await dependencies.contactRepository.getContact(
            peerId,
          );
          if (navigator != null && contact != null) {
            navigator.popUntil((route) => route.isFirst);
            unawaited(
              navigator.push(
                buildConversationRoute(
                  // 362: deliberately NOT threaded with a
                  // DirectConversationRouteAuthority. This debug composition
                  // never builds a linked fanout owner, device-trust
                  // capability or linked runtime role, so there is no
                  // authority to carry; the admission boundary inside the
                  // composer still fails closed on an initialized roster
                  // because it reads the repository, not this widget. The
                  // registered reliability-sim pair scenario — not this root —
                  // is the device evidence for linked fanout.
                  builder: (_) => ConversationWired(
                    contact: contact,
                    identityRepo: dependencies.identityRepository,
                    messageRepo: dependencies.messageRepository,
                    uploadRetryProjectionRepo: dependencies.messageRepository,
                    chatMessageListener: dependencies.chatMessageListener,
                    p2pService: dependencies.p2pService,
                    bridge: dependencies.bridge,
                    contactRepo: dependencies.contactRepository,
                    mediaAttachmentRepo: dependencies.mediaAttachmentRepository,
                    mediaFileManager: dependencies.mediaFileManager,
                    imageProcessor: dependencies.imageProcessor,
                    conversationTracker: dependencies.conversationTracker,
                    audioRecorderService: dependencies.audioRecorderService,
                    reactionRepo: dependencies.reactionRepository,
                    reactionListener: dependencies.reactionListener,
                    introductionRepository: dependencies.introductionRepository,
                    forwardGroupRepository: dependencies.groupRepository,
                    forwardGroupMessageRepository:
                        dependencies.groupMessageRepository,
                    forwardGroupInviteDeliveryAttemptRepository:
                        dependencies.groupInviteDeliveryAttemptRepository,
                    forwardGroupMessageListener:
                        dependencies.groupMessageListener,
                    forwardGroupConversationTracker:
                        dependencies.groupConversationTracker,
                    appShellController: dependencies.appShellController,
                    transportMetrics: dependencies.transportMetrics,
                    privateMediaOutboxE2EController:
                        privateMediaOutboxE2EController,
                  ),
                ),
              ),
            );
            return true;
          }
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        return false;
      },
    );
  }
}
