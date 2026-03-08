import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/identity/application/startup_decision.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/identity/presentation/navigation/startup_route_transition.dart';
import 'package:flutter_app/features/identity/presentation/screens/identity_choice_wired.dart';
import 'package:flutter_app/features/identity/presentation/widgets/startup_loading_gate.dart';
import 'package:flutter_app/features/home/presentation/screens/first_time_experience_wired.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/features/p2p/application/start_node_use_case.dart';
import 'package:flutter_app/features/push/application/request_push_permission_use_case.dart';
import 'package:flutter_app/features/push/application/register_push_token_use_case.dart';
import 'package:flutter_app/core/utils/startup_timing.dart';
import 'package:flutter_app/core/config/startup_config.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:flutter_app/features/share/presentation/screens/share_target_picker_wired.dart';
import 'package:flutter_app/main.dart';

/// Router widget that handles app startup navigation.
///
/// This widget is displayed at app startup and determines whether to
/// navigate to the main app (if an identity exists) or to the identity
/// onboarding flow (if no identity exists).
///
/// The widget shows a loading indicator while checking for an existing
/// identity, then uses pushReplacement to navigate to the appropriate
/// screen, ensuring a clean navigation stack.
class StartupRouter extends StatefulWidget {
  /// The repository used to check for existing identity.
  final IdentityRepository repository;

  /// The repository used to manage contacts.
  final ContactRepository contactRepository;

  /// The repository used to manage contact requests.
  final ContactRequestRepository contactRequestRepository;

  /// The listener for incoming contact requests.
  final ContactRequestListener contactRequestListener;

  /// The message repository for conversation persistence.
  final MessageRepository messageRepository;

  /// The media attachment repository for media metadata.
  final MediaAttachmentRepository mediaAttachmentRepository;

  /// The listener for incoming chat messages.
  final ChatMessageListener chatMessageListener;

  /// The bridge instance for identity operations.
  final Bridge bridge;

  /// The P2P service for networking operations.
  final P2PService p2pService;

  /// The media file manager for local file operations.
  final MediaFileManager mediaFileManager;

  /// The secure key store for preference storage.
  final SecureKeyStore secureKeyStore;

  /// The image processor for EXIF stripping and compression.
  final ImageProcessor imageProcessor;

  /// Tracks which conversation is currently open (for notification suppression).
  final ActiveConversationTracker? conversationTracker;

  /// The audio recorder service for voice messages.
  final AudioRecorderService? audioRecorderService;

  /// The reaction repository for emoji reactions.
  final ReactionRepository? reactionRepository;

  /// The reaction listener for incoming reactions.
  final ReactionListener? reactionListener;

  /// The group repository for group persistence.
  final GroupRepository? groupRepository;

  /// The group message repository for group message persistence.
  final GroupMessageRepository? groupMessageRepository;

  /// The group message listener for incoming group messages.
  final GroupMessageListener? groupMessageListener;

  /// The group invite listener for incoming group invites.
  final GroupInviteListener? groupInviteListener;

  /// Tracks which group conversation is currently open (for notification suppression).
  final ActiveConversationTracker? groupConversationTracker;

  /// The introduction repository for managing introductions.
  final IntroductionRepository? introductionRepository;

  /// The introduction listener for incoming introductions.
  final IntroductionListener? introductionListener;

  /// The share intent service for handling shared content from external apps.
  final ShareIntentService? shareIntentService;

  const StartupRouter({
    super.key,
    required this.repository,
    required this.contactRepository,
    required this.contactRequestRepository,
    required this.contactRequestListener,
    required this.messageRepository,
    required this.mediaAttachmentRepository,
    required this.chatMessageListener,
    required this.bridge,
    required this.p2pService,
    required this.mediaFileManager,
    required this.secureKeyStore,
    required this.imageProcessor,
    this.conversationTracker,
    this.audioRecorderService,
    this.reactionRepository,
    this.reactionListener,
    this.groupRepository,
    this.groupMessageRepository,
    this.groupMessageListener,
    this.groupInviteListener,
    this.groupConversationTracker,
    this.introductionRepository,
    this.introductionListener,
    this.shareIntentService,
  });

  @override
  State<StartupRouter> createState() => _StartupRouterState();
}

class _StartupRouterState extends State<StartupRouter> {
  bool _hasError = false;
  String _errorMessage = '';
  String _startupStage = startupStageCheckingIdentity;

  @override
  void initState() {
    super.initState();
    _routeBasedOnIdentity();
  }

  Future<void> _routeBasedOnIdentity() async {
    emitFlowEvent(layer: 'FL', event: 'ID_STARTUP_FLOW_BEGIN', details: {});

    try {
      _setStartupStage(startupStageCheckingIdentity);

      final decision = await decideStartupRoute(
        identityRepo: widget.repository,
        contactRepo: widget.contactRepository,
      );

      if (!mounted) return;

      // Capture locally to avoid widget reference issues after async gap
      final bridge = widget.bridge;
      final repository = widget.repository;
      final contactRepository = widget.contactRepository;
      final contactRequestRepository = widget.contactRequestRepository;
      final contactRequestListener = widget.contactRequestListener;
      final messageRepository = widget.messageRepository;
      final mediaAttachmentRepository = widget.mediaAttachmentRepository;
      final chatMessageListener = widget.chatMessageListener;
      final p2pService = widget.p2pService;

      switch (decision) {
        case StartupDecision.hasIdentityWithContacts:
          _setStartupStage(startupStageOpeningFeed);
          await _ensureMlKemKeys();
          final contactCount = await contactRepository.getContactCount();
          if (!mounted) return;

          emitFlowEvent(
            layer: 'FL',
            event: 'ID_STARTUP_ROUTE_FEED',
            details: {'contactCount': contactCount},
          );
          await _pushStartupReplacement(
            builder: (_) => FeedWired(
              repository: repository,
              contactRepository: contactRepository,
              contactRequestRepository: contactRequestRepository,
              contactRequestListener: contactRequestListener,
              messageRepository: messageRepository,
              mediaAttachmentRepository: mediaAttachmentRepository,
              chatMessageListener: chatMessageListener,
              bridge: bridge,
              p2pService: p2pService,
              mediaFileManager: widget.mediaFileManager,
              secureKeyStore: widget.secureKeyStore,
              imageProcessor: widget.imageProcessor,
              conversationTracker: widget.conversationTracker,
              audioRecorderService: widget.audioRecorderService,
              reactionRepository: widget.reactionRepository,
              reactionListener: widget.reactionListener,
              groupRepository: widget.groupRepository,
              groupMessageRepository: widget.groupMessageRepository,
              groupMessageListener: widget.groupMessageListener,
              groupInviteListener: widget.groupInviteListener,
              groupConversationTracker: widget.groupConversationTracker,
              introductionRepository: widget.introductionRepository,
              introductionListener: widget.introductionListener,
            ),
          );

          // Start P2P node in background after navigation
          _startP2PInBackground();

          // Mark settled and consume any buffered share intent
          widget.shareIntentService?.isSettled = true;
          _consumePendingShareIntent();
          break;

        case StartupDecision.hasIdentityNoContacts:
          _setStartupStage(startupStageOpeningSetup);
          await _ensureMlKemKeys();
          emitFlowEvent(
            layer: 'FL',
            event: 'ID_STARTUP_ROUTE_MAIN_NO_CONTACTS',
            details: {},
          );
          await _navigateToFirstTime(
            repository: repository,
            contactRepository: contactRepository,
            contactRequestRepository: contactRequestRepository,
            contactRequestListener: contactRequestListener,
            messageRepository: messageRepository,
            mediaAttachmentRepository: mediaAttachmentRepository,
            chatMessageListener: chatMessageListener,
            bridge: bridge,
            p2pService: p2pService,
            mediaFileManager: widget.mediaFileManager,
            secureKeyStore: widget.secureKeyStore,
            imageProcessor: widget.imageProcessor,
            conversationTracker: widget.conversationTracker,
            audioRecorderService: widget.audioRecorderService,
            reactionRepository: widget.reactionRepository,
            reactionListener: widget.reactionListener,
            groupRepository: widget.groupRepository,
            groupMessageRepository: widget.groupMessageRepository,
            groupMessageListener: widget.groupMessageListener,
            groupInviteListener: widget.groupInviteListener,
            groupConversationTracker: widget.groupConversationTracker,
            introductionRepository: widget.introductionRepository,
            introductionListener: widget.introductionListener,
          );
          break;

        case StartupDecision.needsIdentity:
          _setStartupStage(startupStageOpeningOnboarding);
          emitFlowEvent(
            layer: 'FL',
            event: 'ID_STARTUP_ROUTE_ONBOARDING',
            details: {},
          );
          await _pushStartupReplacement(
            builder: (routeContext) => IdentityChoiceWired(
              repository: repository,
              callIdentityGenerate: () => callIdentityGenerate(bridge),
              callIdentityRestore: (mnemonic) =>
                  callIdentityRestore(bridge, mnemonic),
              callMlKemKeygen: () => callMlKemKeygen(bridge),
              onNavigateToMain: () {
                // Navigate and start P2P
                Navigator.of(routeContext).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => FirstTimeExperienceWired(
                      repository: repository,
                      contactRepository: contactRepository,
                      contactRequestRepository: contactRequestRepository,
                      contactRequestListener: contactRequestListener,
                      messageRepository: messageRepository,
                      mediaAttachmentRepository: mediaAttachmentRepository,
                      chatMessageListener: chatMessageListener,
                      bridge: bridge,
                      p2pService: p2pService,
                      mediaFileManager: widget.mediaFileManager,
                      secureKeyStore: widget.secureKeyStore,
                      imageProcessor: widget.imageProcessor,
                      conversationTracker: widget.conversationTracker,
                      audioRecorderService: widget.audioRecorderService,
                      reactionRepository: widget.reactionRepository,
                      reactionListener: widget.reactionListener,
                      groupRepository: widget.groupRepository,
                      groupMessageRepository: widget.groupMessageRepository,
                      groupMessageListener: widget.groupMessageListener,
                      groupInviteListener: widget.groupInviteListener,
                      groupConversationTracker: widget.groupConversationTracker,
                      introductionRepository: widget.introductionRepository,
                      introductionListener: widget.introductionListener,
                    ),
                  ),
                );

                StartupTiming.instance.mark('route_pushed');

                // Start P2P node in background after identity creation
                _startP2PInBackground();
              },
            ),
          );
          break;
      }
    } catch (e) {
      if (!mounted) return;

      emitFlowEvent(
        layer: 'FL',
        event: 'ID_STARTUP_ROUTE_ERROR',
        details: {'error': e.toString()},
      );

      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  /// Start the P2P node in the background.
  ///
  /// This is called after navigating to the main screen, so failures
  /// don't block the user experience.
  Future<void> _startP2PInBackground() async {
    if (StartupConfig.deferredStartupMode) {
      // Defer P2P startup to next frame to avoid contending with UI rendering
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _doStartP2P();
      });
    } else {
      _doStartP2P();
    }
  }

  Future<void> _doStartP2P() async {
    StartupTiming.instance.mark('p2p_startup_begin');
    emitFlowEvent(layer: 'FL', event: 'P2P_STARTUP_BEGIN', details: {});

    final result = await startP2PNode(
      identityRepo: widget.repository,
      p2pService: widget.p2pService,
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_STARTUP_RESULT',
      details: {'result': result.name},
    );

    if (result == StartNodeResult.success) {
      StartupTiming.instance.mark('p2p_startup_complete');
      StartupTiming.instance.printSummary();
      _registerPushToken();

      // Now that the Go node is running (pubsub initialized), rejoin group
      // topics and drain offline inboxes. Fire-and-forget — errors are logged
      // inside each function and don't block startup.
      final groupRepo = widget.groupRepository;
      final groupMsgRepo = widget.groupMessageRepository;
      if (groupRepo != null) {
        rejoinGroupTopics(bridge: widget.bridge, groupRepo: groupRepo);
        if (groupMsgRepo != null) {
          drainGroupOfflineInbox(
            bridge: widget.bridge,
            groupRepo: groupRepo,
            msgRepo: groupMsgRepo,
            mediaAttachmentRepo: widget.mediaAttachmentRepository,
            reactionRepo: widget.reactionRepository,
          );
        }
      }
    }
  }

  /// Ensure the current identity has ML-KEM keys.
  ///
  /// Existing users created before ML-KEM support won't have keys.
  /// This generates and saves them. Non-fatal: if it fails, user
  /// continues with plaintext messaging.
  Future<void> _ensureMlKemKeys() async {
    try {
      final identity = await widget.repository.loadIdentity();
      if (identity == null || identity.mlKemPublicKey != null) return;

      emitFlowEvent(layer: 'FL', event: 'MLKEM_MIGRATION_START', details: {});

      final mlKemResponse = await callMlKemKeygen(widget.bridge);
      if (mlKemResponse['ok'] != true) {
        emitFlowEvent(
          layer: 'FL',
          event: 'MLKEM_MIGRATION_ERROR',
          details: {'errorCode': mlKemResponse['errorCode']},
        );
        return;
      }

      final enriched = IdentityModel(
        peerId: identity.peerId,
        publicKey: identity.publicKey,
        privateKey: identity.privateKey,
        mnemonic12: identity.mnemonic12,
        mlKemPublicKey: mlKemResponse['publicKey'] as String,
        mlKemSecretKey: mlKemResponse['secretKey'] as String,
        username: identity.username,
        avatarBlob: identity.avatarBlob,
        createdAt: identity.createdAt,
        updatedAt: identity.updatedAt,
      );

      await widget.repository.saveIdentity(enriched);

      emitFlowEvent(layer: 'FL', event: 'MLKEM_MIGRATION_OK', details: {});
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MLKEM_MIGRATION_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _registerPushToken() async {
    // Push notifications only available on mobile (iOS/Android)
    if (kIsWeb || Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return;
    }

    try {
      final granted = await requestPushPermission();
      if (!granted) return;

      await registerPushToken(p2pService: widget.p2pService);

      // Re-register when FCM token refreshes
      FirebaseMessaging.instance.onTokenRefresh.listen((_) {
        registerPushToken(p2pService: widget.p2pService);
      });
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_REGISTER_TOKEN_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _retry() async {
    setState(() {
      _hasError = false;
      _errorMessage = '';
      _startupStage = startupStageCheckingIdentity;
    });
    await _routeBasedOnIdentity();
  }

  Future<void> _navigateToFirstTime({
    required IdentityRepository repository,
    required ContactRepository contactRepository,
    required ContactRequestRepository contactRequestRepository,
    required ContactRequestListener contactRequestListener,
    required MessageRepository messageRepository,
    required MediaAttachmentRepository mediaAttachmentRepository,
    required ChatMessageListener chatMessageListener,
    required Bridge bridge,
    required P2PService p2pService,
    required MediaFileManager mediaFileManager,
    required SecureKeyStore secureKeyStore,
    required ImageProcessor imageProcessor,
    ActiveConversationTracker? conversationTracker,
    AudioRecorderService? audioRecorderService,
    ReactionRepository? reactionRepository,
    ReactionListener? reactionListener,
    GroupRepository? groupRepository,
    GroupMessageRepository? groupMessageRepository,
    GroupMessageListener? groupMessageListener,
    GroupInviteListener? groupInviteListener,
    ActiveConversationTracker? groupConversationTracker,
    IntroductionRepository? introductionRepository,
    IntroductionListener? introductionListener,
  }) async {
    await _pushStartupReplacement(
      builder: (_) => FirstTimeExperienceWired(
        repository: repository,
        contactRepository: contactRepository,
        contactRequestRepository: contactRequestRepository,
        contactRequestListener: contactRequestListener,
        messageRepository: messageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        chatMessageListener: chatMessageListener,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: mediaFileManager,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        conversationTracker: conversationTracker,
        audioRecorderService: audioRecorderService,
        reactionRepository: reactionRepository,
        reactionListener: reactionListener,
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
        groupMessageListener: groupMessageListener,
        groupInviteListener: groupInviteListener,
        groupConversationTracker: groupConversationTracker,
        introductionRepository: introductionRepository,
        introductionListener: introductionListener,
      ),
    );

    // Start P2P in background after navigation
    _startP2PInBackground();
  }

  void _setStartupStage(String stage) {
    if (!mounted || _startupStage == stage) return;
    setState(() => _startupStage = stage);
  }

  void _consumePendingShareIntent() {
    final shareService = widget.shareIntentService;
    if (shareService == null) return;
    final intent = shareService.consumePendingIntent();
    if (intent == null) return;
    shareService.reset();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = MyApp.navigatorKey.currentState;
      if (navigator == null) return;
      navigator.push(MaterialPageRoute(
        builder: (_) => ShareTargetPickerWired(
          shareIntent: intent,
          identityRepo: widget.repository,
          contactRepository: widget.contactRepository,
          messageRepository: widget.messageRepository,
          mediaAttachmentRepository: widget.mediaAttachmentRepository,
          chatMessageListener: widget.chatMessageListener,
          bridge: widget.bridge,
          p2pService: widget.p2pService,
          mediaFileManager: widget.mediaFileManager,
          imageProcessor: widget.imageProcessor,
          conversationTracker: widget.conversationTracker,
          audioRecorderService: widget.audioRecorderService,
          reactionRepository: widget.reactionRepository,
          reactionListener: widget.reactionListener,
          groupRepository: widget.groupRepository,
          groupMessageRepository: widget.groupMessageRepository,
          groupMessageListener: widget.groupMessageListener,
          groupConversationTracker: widget.groupConversationTracker,
          introductionRepository: widget.introductionRepository,
        ),
      ));
    });
  }

  Future<void> _pushStartupReplacement({required WidgetBuilder builder}) async {
    if (!mounted) return;

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    Navigator.of(
      context,
    ).pushReplacement(buildStartupReplacementRoute(builder: builder));
    StartupTiming.instance.mark('route_pushed');
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 24),
                const Text(
                  'Failed to initialize',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                ElevatedButton(onPressed: _retry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    return StartupLoadingGate(stage: _startupStage);
  }
}
