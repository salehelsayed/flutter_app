import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/accept_and_reciprocate_use_case.dart';
import 'package:flutter_app/features/settings/application/upload_profile_picture_use_case.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/decline_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contact_request/presentation/widgets/contact_request_dialog.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/qr_code/application/build_qr_payload_use_case.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_wired.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/feed/presentation/navigation/feed_route_transition.dart';
import 'package:flutter_app/core/utils/startup_timing.dart';
import 'first_time_experience_screen.dart';

/// Wired widget that connects FirstTimeExperienceScreen to business logic.
class FirstTimeExperienceWired extends StatefulWidget {
  final IdentityRepository repository;
  final ContactRepository contactRepository;
  final ContactRequestRepository contactRequestRepository;
  final ContactRequestListener contactRequestListener;
  final MessageRepository messageRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final ChatMessageListener chatMessageListener;
  final Bridge bridge;
  final P2PService p2pService;
  final MediaFileManager mediaFileManager;
  final ImageProcessor imageProcessor;
  final SecureKeyStore secureKeyStore;
  final ActiveConversationTracker? conversationTracker;
  final AudioRecorderService? audioRecorderService;
  final ReactionRepository? reactionRepository;
  final ReactionListener? reactionListener;
  final GroupRepository? groupRepository;
  final GroupMessageRepository? groupMessageRepository;
  final GroupMessageListener? groupMessageListener;
  final GroupInviteListener? groupInviteListener;
  final ActiveConversationTracker? groupConversationTracker;
  final IntroductionRepository? introductionRepository;
  final IntroductionListener? introductionListener;

  const FirstTimeExperienceWired({
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
    required this.imageProcessor,
    required this.secureKeyStore,
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
  });

  @override
  State<FirstTimeExperienceWired> createState() =>
      _FirstTimeExperienceWiredState();
}

class _FirstTimeExperienceWiredState extends State<FirstTimeExperienceWired> {
  String? _qrData;
  String _username = 'Username';
  Uint8List? _avatarBytes;
  IdentityModel? _identity;
  StreamSubscription<ContactRequestModel>? _requestSubscription;

  @override
  void initState() {
    super.initState();
    emitFlowEvent(layer: 'FL', event: 'FTE_FL_SCREEN_INIT', details: {});
    StartupTiming.instance.mark('fte_init_state');
    // Start listening immediately (lightweight — just subscribes to a stream)
    _startListeningForContactRequests();
    // Defer heavy async work (DB load + bridge call) to after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      StartupTiming.instance.mark('fte_first_frame');
      _loadIdentityAndBuildQR();
    });
  }

  void _startListeningForContactRequests() {
    _requestSubscription = widget.contactRequestListener.requestStream.listen(
      _onContactRequest,
      onError: (error) {
        emitFlowEvent(layer: 'FL', event: 'FTE_REQUEST_STREAM_ERROR', details: {'error': error.toString()});
      },
      onDone: () {
        emitFlowEvent(layer: 'FL', event: 'FTE_REQUEST_STREAM_DONE', details: {});
      },
    );
  }

  void _onContactRequest(ContactRequestModel request) {
    emitFlowEvent(
      layer: 'FL',
      event: 'FTE_FL_CONTACT_REQUEST_RECEIVED',
      details: {
        'peerId': request.peerId.substring(0, 10),
        'username': request.username,
      },
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ContactRequestDialog(
        request: request,
        onAccept: () => _acceptRequest(ctx, request),
        onDecline: () => _declineRequest(ctx, request),
      ),
    );
  }

  Future<void> _acceptRequest(
    BuildContext ctx,
    ContactRequestModel request,
  ) async {
    Navigator.pop(ctx);

    final result = await acceptAndReciprocateContactRequest(
      requestRepo: widget.contactRequestRepository,
      contactRepo: widget.contactRepository,
      peerId: request.peerId,
      p2pService: widget.p2pService,
      identityRepo: widget.repository,
      bridge: widget.bridge,
      onProfileDownloaded: widget.chatMessageListener.emitContactUpdate,
    );

    if (!mounted) return;

    // success or notPending (already accepted from a prior tap) both mean
    // the contact exists — navigate to feed.
    if (result == AcceptContactRequestResult.success ||
        result == AcceptContactRequestResult.notPending) {
      Navigator.of(context).pushReplacement(
        buildFeedSlideUpRoute(
          builder: (_) => FeedWired(
            repository: widget.repository,
            contactRepository: widget.contactRepository,
            contactRequestRepository: widget.contactRequestRepository,
            contactRequestListener: widget.contactRequestListener,
            messageRepository: widget.messageRepository,
            mediaAttachmentRepository: widget.mediaAttachmentRepository,
            chatMessageListener: widget.chatMessageListener,
            bridge: widget.bridge,
            p2pService: widget.p2pService,
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
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to add contact. Please try again.'),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _declineRequest(
    BuildContext ctx,
    ContactRequestModel request,
  ) async {
    Navigator.pop(ctx);

    await declineContactRequest(
      requestRepo: widget.contactRequestRepository,
      peerId: request.peerId,
    );
  }

  @override
  void dispose() {
    _requestSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadIdentityAndBuildQR() async {
    try {
      final identity = await widget.repository.loadIdentity();
      if (identity == null) {
        emitFlowEvent(layer: 'FL', event: 'FTE_FL_NO_IDENTITY', details: {});
        return;
      }

      _identity = identity;
      _username = identity.username;
      _avatarBytes = identity.avatarBlob;

      await _buildQRPayload();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FTE_FL_LOAD_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _buildQRPayload() async {
    try {
      Future<Map<String, dynamic>> jsSign(
        String dataToSign,
        String privateKey,
      ) {
        return callSignPayload(
          bridge: widget.bridge,
          dataToSign: dataToSign,
          privateKey: privateKey,
        );
      }

      final (result, qrString) = await buildQRPayload(
        repo: widget.repository,
        callSign: jsSign,
        cachedIdentity: _identity,
      );

      if (result == BuildQRPayloadResult.success && mounted) {
        setState(() {
          _qrData = qrString;
        });
        StartupTiming.instance.mark('fte_qr_ready');
        emitFlowEvent(layer: 'FL', event: 'FTE_FL_QR_GENERATED', details: {});
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FTE_FL_QR_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onUsernameChanged(String newUsername) async {
    if (_identity == null) return;

    final updatedIdentity = IdentityModel(
      peerId: _identity!.peerId,
      publicKey: _identity!.publicKey,
      privateKey: _identity!.privateKey,
      mnemonic12: _identity!.mnemonic12,
      mlKemPublicKey: _identity!.mlKemPublicKey,
      mlKemSecretKey: _identity!.mlKemSecretKey,
      username: newUsername,
      avatarBlob: _identity!.avatarBlob,
      createdAt: _identity!.createdAt,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );

    try {
      await widget.repository.saveIdentity(updatedIdentity);
      _identity = updatedIdentity;

      setState(() {
        _username = newUsername;
        _qrData = null; // Clear QR while regenerating
      });

      emitFlowEvent(
        layer: 'FL',
        event: 'FTE_FL_USERNAME_UPDATED',
        details: {'username': newUsername},
      );

      await _buildQRPayload();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FTE_FL_USERNAME_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onCameraPressed() async {
    if (_identity == null) return;

    // Show picker options dialog
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title: const Text(
                'Take Photo',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text(
                'Choose from Gallery',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      // Pick image
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
      );

      if (pickedFile == null) return;

      // Process avatar: strip EXIF, compress to 512x512
      final processedPath = await widget.imageProcessor.processAvatar(
        inputPath: pickedFile.path,
      );
      final bytes = await File(processedPath).readAsBytes();

      final updatedIdentity = IdentityModel(
        peerId: _identity!.peerId,
        publicKey: _identity!.publicKey,
        privateKey: _identity!.privateKey,
        mnemonic12: _identity!.mnemonic12,
        mlKemPublicKey: _identity!.mlKemPublicKey,
        mlKemSecretKey: _identity!.mlKemSecretKey,
        username: _identity!.username,
        avatarBlob: bytes,
        createdAt: _identity!.createdAt,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );

      await widget.repository.saveIdentity(updatedIdentity);
      _identity = updatedIdentity;

      // Upload to relay so contacts can download it after connecting
      uploadProfilePicture(
        bridge: widget.bridge,
        identityRepo: widget.repository,
        contactRepo: widget.contactRepository,
        p2pService: widget.p2pService,
        filePath: processedPath,
        mime: 'image/jpeg',
      );

      if (mounted) {
        setState(() {
          _avatarBytes = bytes;
        });
      }

      emitFlowEvent(layer: 'FL', event: 'FTE_FL_AVATAR_UPDATED', details: {});
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FTE_FL_AVATAR_ERROR',
        details: {'error': e.toString()},
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update photo: $e')));
      }
    }
  }

  void _onScanPressed() {
    if (_identity == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QRScannerWired(
          bridge: widget.bridge,
          contactRepository: widget.contactRepository,
          contactRequestRepository: widget.contactRequestRepository,
          contactRequestListener: widget.contactRequestListener,
          messageRepository: widget.messageRepository,
          mediaAttachmentRepository: widget.mediaAttachmentRepository,
          chatMessageListener: widget.chatMessageListener,
          identityRepository: widget.repository,
          p2pService: widget.p2pService,
          mediaFileManager: widget.mediaFileManager,
          secureKeyStore: widget.secureKeyStore,
          imageProcessor: widget.imageProcessor,
          ownPeerId: _identity!.peerId,
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FirstTimeExperienceScreen(
        qrData: _qrData,
        username: _username,
        avatarBytes: _avatarBytes,
        peerId: _identity?.peerId,
        onCameraPressed: _onCameraPressed,
        onUsernameChanged: _onUsernameChanged,
        onScanPressed: _onScanPressed,
        p2pService: widget.p2pService,
      ),
    );
  }
}
