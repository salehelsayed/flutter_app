import 'package:flutter/material.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/application/add_contact_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/settings/application/download_profile_picture_use_case.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/presentation/navigation/feed_route_transition.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/posts_privacy_settings_repository.dart';
import 'package:flutter_app/features/share/application/settle_share_intent_flow.dart';
import 'package:flutter_app/features/share/presentation/navigation/share_target_picker_route.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/qr_code/application/parse_qr_payload_use_case.dart';
import 'qr_scanner_screen.dart';

/// Wired widget that connects QR scanner to business logic.
///
/// Handles the full flow:
/// 1. Opens scanner screen
/// 2. Parses scanned QR code
/// 3. Validates signature
/// 4. Adds contact to database
/// 5. Sends contact request via P2P (for bidirectional exchange)
/// 6. Shows success/error feedback
class QRScannerWired extends StatelessWidget {
  final Bridge bridge;
  final ContactRepository contactRepository;
  final ContactRequestRepository contactRequestRepository;
  final ContactRequestListener contactRequestListener;
  final MessageRepository messageRepository;
  final PostRepository? postRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final ChatMessageListener chatMessageListener;
  final IdentityRepository identityRepository;
  final P2PService p2pService;
  final MediaFileManager mediaFileManager;
  final SecureKeyStore secureKeyStore;
  final ImageProcessor imageProcessor;
  final String ownPeerId;
  final ActiveConversationTracker? conversationTracker;
  final AudioRecorderService? audioRecorderService;
  final ReactionRepository? reactionRepository;
  final ReactionListener? reactionListener;
  final GroupRepository? groupRepository;
  final GroupMessageRepository? groupMessageRepository;
  final GroupReactionReplayOutboxRepository?
  groupReactionReplayOutboxRepository;
  final GroupMessageListener? groupMessageListener;
  final GroupInviteListener? groupInviteListener;
  final ActiveConversationTracker? groupConversationTracker;
  final DownloadProfilePictureFn? downloadProfilePictureFn;
  final IntroductionRepository? introductionRepository;
  final IntroductionListener? introductionListener;
  final ShareIntentService? shareIntentService;
  final AppShellController? appShellController;
  final PendingPostTargetStore? pendingPostTargetStore;
  final PostsPrivacySettingsRepository? postsPrivacySettingsRepository;

  const QRScannerWired({
    super.key,
    required this.bridge,
    required this.contactRepository,
    required this.contactRequestRepository,
    required this.contactRequestListener,
    required this.messageRepository,
    this.postRepository,
    required this.mediaAttachmentRepository,
    required this.chatMessageListener,
    required this.identityRepository,
    required this.p2pService,
    required this.mediaFileManager,
    required this.secureKeyStore,
    required this.imageProcessor,
    required this.ownPeerId,
    this.conversationTracker,
    this.audioRecorderService,
    this.reactionRepository,
    this.reactionListener,
    this.groupRepository,
    this.groupMessageRepository,
    this.groupReactionReplayOutboxRepository,
    this.groupMessageListener,
    this.groupInviteListener,
    this.groupConversationTracker,
    this.downloadProfilePictureFn,
    this.introductionRepository,
    this.introductionListener,
    this.shareIntentService,
    this.appShellController,
    this.pendingPostTargetStore,
    this.postsPrivacySettingsRepository,
  });

  @override
  Widget build(BuildContext context) {
    return QRScannerScreen(
      onScanned: (qrData) => _handleScanned(context, qrData),
    );
  }

  Future<void> _handleScanned(BuildContext context, String qrData) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'QR_SCAN_RECEIVED',
      details: {'length': qrData.length},
    );

    // Parse and validate the QR payload
    final (result, contact) = await parseQRPayload(
      qrString: qrData,
      bridge: bridge,
      ownPeerId: ownPeerId,
    );

    if (!context.mounted) return;

    switch (result) {
      case ParseQRResult.success:
        await _handleValidContact(context, contact!);
        break;

      case ParseQRResult.invalidJson:
        _showError(
          context,
          'Invalid QR Code',
          'This doesn\'t look like a valid contact QR code.',
        );
        break;

      case ParseQRResult.missingFields:
        _showError(
          context,
          'Incomplete QR Code',
          'This QR code is missing required information.',
        );
        break;

      case ParseQRResult.invalidSignature:
        _showError(
          context,
          'Invalid Signature',
          'This QR code could not be verified.',
        );
        break;

      case ParseQRResult.expired:
        _showError(
          context,
          'Expired QR Code',
          'This QR code has expired. Ask your friend for a new one.',
        );
        break;

      case ParseQRResult.selfScan:
        _showError(
          context,
          'That\'s You!',
          'You can\'t add yourself as a contact.',
        );
        break;
    }
  }

  Future<void> _handleValidContact(
    BuildContext context,
    ContactModel contact,
  ) async {
    final addResult = await addContact(
      repository: contactRepository,
      contact: contact,
    );

    if (!context.mounted) return;

    switch (addResult) {
      case AddContactResult.success:
        _showSuccessDialog(context, contact);
        // Send contact request to the scanned peer (fire and forget)
        _sendContactRequestInBackground(contact.peerId, contact.publicKey);
        // Download profile picture (fire and forget)
        _downloadProfilePictureInBackground(contact.peerId);
        break;

      case AddContactResult.alreadyExists:
        _showAlreadyExistsDialog(context, contact);
        break;

      case AddContactResult.dbError:
        _showError(
          context,
          'Error',
          'Failed to add contact. Please try again.',
        );
        break;
    }
  }

  /// Sends a contact request to the peer in the background.
  ///
  /// This enables bidirectional contact exchange - when Bob scans Alice's QR,
  /// Bob automatically sends his info to Alice so she can add him back.
  void _sendContactRequestInBackground(
    String targetPeerId,
    String recipientPublicKey,
  ) async {
    final sendResult = await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepository,
      bridge: bridge,
      targetPeerId: targetPeerId,
      recipientPublicKey: recipientPublicKey,
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_REQUEST_SENT',
      details: {
        'result': sendResult.name,
        'targetPeerId': targetPeerId.length > 10
            ? targetPeerId.substring(0, 10)
            : targetPeerId,
      },
    );
  }

  /// Downloads the contact's profile picture in the background.
  ///
  /// On success, notifies the UI via [chatMessageListener.emitContactUpdate].
  void _downloadProfilePictureInBackground(String peerId) async {
    try {
      final updated =
          await (downloadProfilePictureFn ?? downloadProfilePicture)(
            bridge: bridge,
            contactRepo: contactRepository,
            ownerPeerId: peerId,
            avatarVersion: 'initial',
          );
      if (updated != null) chatMessageListener.emitContactUpdate(updated);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'INITIAL_PROFILE_DOWNLOAD_ERROR',
        details: {'peerId': peerId, 'error': e.toString()},
      );
    }
  }

  void _showError(BuildContext context, String title, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(message),
          ],
        ),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccessDialog(BuildContext context, ContactModel contact) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: AppColors.primaryAccent.withValues(alpha: 0.3),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            // Contact's ring avatar
            UserAvatar(peerId: contact.peerId, size: 80),
            const SizedBox(height: 16),
            // Username
            Text(
              contact.username,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            // Success message
            Text(
              'Added to your circle!',
              style: TextStyle(color: AppColors.primaryAccent, fontSize: 14),
            ),
            const SizedBox(height: 24),
            // OK button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final navigator = Navigator.of(ctx);
                  navigator.pushAndRemoveUntil(
                    buildFeedSlideUpRoute(
                      builder: (_) => FeedWired(
                        repository: identityRepository,
                        contactRepository: contactRepository,
                        contactRequestRepository: contactRequestRepository,
                        contactRequestListener: contactRequestListener,
                        messageRepository: messageRepository,
                        postRepository:
                            postRepository ?? _missingPostRepository(),
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
                        groupReactionReplayOutboxRepository:
                            groupReactionReplayOutboxRepository,
                        groupMessageListener: groupMessageListener,
                        groupInviteListener: groupInviteListener,
                        groupConversationTracker: groupConversationTracker,
                        introductionRepository: introductionRepository,
                        introductionListener: introductionListener,
                        appShellController:
                            appShellController ?? _missingAppShellController(),
                        pendingPostTargetStore:
                            pendingPostTargetStore ??
                            _missingPendingPostTargetStore(),
                        postsPrivacySettingsRepository:
                            postsPrivacySettingsRepository ??
                            _missingPostsPrivacySettingsRepository(),
                      ),
                    ),
                    (route) => false,
                  );
                  settleShareIntentFlow(
                    shareIntentService: shareIntentService,
                    navigator: navigator,
                    buildRoute: _buildPendingShareRoute,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAlreadyExistsDialog(BuildContext context, ContactModel contact) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.amber.withValues(alpha: 0.3)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            // Contact's ring avatar
            UserAvatar(peerId: contact.peerId, size: 80),
            const SizedBox(height: 16),
            // Username
            Text(
              contact.username,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            // Already exists message
            const Text(
              'Already in your circle!',
              style: TextStyle(color: Colors.amber, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'This contact was added previously',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 24),
            // OK button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Got it',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Route<void> _buildPendingShareRoute(ShareIntent intent) {
    return buildShareTargetPickerRoute(
      shareIntent: intent,
      identityRepo: identityRepository,
      contactRepository: contactRepository,
      messageRepository: messageRepository,
      mediaAttachmentRepository: mediaAttachmentRepository,
      chatMessageListener: chatMessageListener,
      bridge: bridge,
      p2pService: p2pService,
      mediaFileManager: mediaFileManager,
      imageProcessor: imageProcessor,
      secureKeyStore: secureKeyStore,
      conversationTracker: conversationTracker,
      audioRecorderService: audioRecorderService,
      reactionRepository: reactionRepository,
      reactionListener: reactionListener,
      groupRepository: groupRepository,
      groupMessageRepository: groupMessageRepository,
      groupMessageListener: groupMessageListener,
      groupConversationTracker: groupConversationTracker,
      introductionRepository: introductionRepository,
      appShellController: appShellController,
    );
  }

  Never _missingPostRepository() {
    throw StateError(
      'QRScannerWired requires postRepository before navigating to FeedWired.',
    );
  }

  Never _missingAppShellController() {
    throw StateError(
      'QRScannerWired requires appShellController before navigating to FeedWired.',
    );
  }

  Never _missingPendingPostTargetStore() {
    throw StateError(
      'QRScannerWired requires pendingPostTargetStore before navigating to FeedWired.',
    );
  }

  Never _missingPostsPrivacySettingsRepository() {
    throw StateError(
      'QRScannerWired requires postsPrivacySettingsRepository before navigating to FeedWired.',
    );
  }
}
