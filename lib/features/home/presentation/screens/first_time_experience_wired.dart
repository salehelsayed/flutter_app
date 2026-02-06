import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_app/core/bridge/js_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/decline_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contact_request/presentation/widgets/contact_request_dialog.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/qr_code/application/build_qr_payload_use_case.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_wired.dart';
import 'first_time_experience_screen.dart';

/// Wired widget that connects FirstTimeExperienceScreen to business logic.
class FirstTimeExperienceWired extends StatefulWidget {
  final IdentityRepository repository;
  final ContactRepository contactRepository;
  final ContactRequestRepository contactRequestRepository;
  final ContactRequestListener contactRequestListener;
  final JsBridge bridge;
  final P2PService p2pService;

  const FirstTimeExperienceWired({
    super.key,
    required this.repository,
    required this.contactRepository,
    required this.contactRequestRepository,
    required this.contactRequestListener,
    required this.bridge,
    required this.p2pService,
  });

  @override
  State<FirstTimeExperienceWired> createState() =>
      _FirstTimeExperienceWiredState();
}

class _FirstTimeExperienceWiredState extends State<FirstTimeExperienceWired> {
  String? _qrData;
  String _username = 'Username';
  String? _avatarPath;
  IdentityModel? _identity;
  StreamSubscription<ContactRequestModel>? _requestSubscription;

  @override
  void initState() {
    super.initState();
    emitFlowEvent(
      layer: 'FL',
      event: 'FTE_FL_SCREEN_INIT',
      details: {},
    );
    _loadIdentityAndBuildQR();
    _startListeningForContactRequests();
  }

  void _startListeningForContactRequests() {
    _requestSubscription = widget.contactRequestListener.requestStream.listen(
      _onContactRequest,
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

    final result = await acceptContactRequest(
      requestRepo: widget.contactRequestRepository,
      contactRepo: widget.contactRepository,
      peerId: request.peerId,
    );

    if (!mounted) return;

    if (result == AcceptContactRequestResult.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${request.username} added to your circle!'),
          backgroundColor: AppColors.primaryAccent,
          behavior: SnackBarBehavior.floating,
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
        emitFlowEvent(
          layer: 'FL',
          event: 'FTE_FL_NO_IDENTITY',
          details: {},
        );
        return;
      }

      _identity = identity;
      _username = identity.username;
      _avatarPath = identity.avatarPath;

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
          String dataToSign, String privateKey) {
        return callJsSignPayload(
          bridge: widget.bridge,
          dataToSign: dataToSign,
          privateKey: privateKey,
        );
      }

      final (result, qrString) = await buildQRPayload(
        repo: widget.repository,
        callJsSign: jsSign,
      );

      if (result == BuildQRPayloadResult.success && mounted) {
        setState(() {
          _qrData = qrString;
        });
        emitFlowEvent(
          layer: 'FL',
          event: 'FTE_FL_QR_GENERATED',
          details: {},
        );
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
      username: newUsername,
      avatarPath: _identity!.avatarPath,
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
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      // Copy to app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final avatarsDir = Directory('${appDir.path}/avatars');
      if (!await avatarsDir.exists()) {
        await avatarsDir.create(recursive: true);
      }

      final fileName = 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = '${avatarsDir.path}/$fileName';
      await File(pickedFile.path).copy(savedPath);

      // Update identity with new avatar path
      final updatedIdentity = IdentityModel(
        peerId: _identity!.peerId,
        publicKey: _identity!.publicKey,
        privateKey: _identity!.privateKey,
        mnemonic12: _identity!.mnemonic12,
        username: _identity!.username,
        avatarPath: savedPath,
        createdAt: _identity!.createdAt,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );

      await widget.repository.saveIdentity(updatedIdentity);
      _identity = updatedIdentity;

      if (mounted) {
        setState(() {
          _avatarPath = savedPath;
        });
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'FTE_FL_AVATAR_UPDATED',
        details: {},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'FTE_FL_AVATAR_ERROR',
        details: {'error': e.toString()},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update photo: $e')),
        );
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
          identityRepository: widget.repository,
          p2pService: widget.p2pService,
          ownPeerId: _identity!.peerId,
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
        avatarPath: _avatarPath,
        peerId: _identity?.peerId,
        onCameraPressed: _onCameraPressed,
        onUsernameChanged: _onUsernameChanged,
        onScanPressed: _onScanPressed,
        p2pService: widget.p2pService,
      ),
    );
  }
}
