import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/settings/application/image_quality_preference_use_cases.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/settings/application/upload_profile_picture_use_case.dart';
import 'settings_screen.dart';

/// Wired widget connecting SettingsScreen to business logic.
///
/// Loads identity, manages mnemonic reveal/hide state and copy timers.
class SettingsWired extends StatefulWidget {
  final IdentityRepository identityRepo;
  final Bridge bridge;
  final ContactRepository contactRepo;
  final P2PService p2pService;
  final SecureKeyStore secureKeyStore;
  final ImageProcessor imageProcessor;

  const SettingsWired({
    super.key,
    required this.identityRepo,
    required this.bridge,
    required this.contactRepo,
    required this.p2pService,
    required this.secureKeyStore,
    required this.imageProcessor,
  });

  @override
  State<SettingsWired> createState() => _SettingsWiredState();
}

class _SettingsWiredState extends State<SettingsWired> {
  IdentityModel? _identity;
  bool _isMnemonicRevealed = false;
  bool _isPeerIdCopied = false;
  bool _isMnemonicCopied = false;
  Uint8List? _pickedAvatarBytes;
  Timer? _peerIdCopyTimer;
  Timer? _mnemonicCopyTimer;
  ImageQualityPreference _currentQuality = ImageQualityPreference.compressed;
  ImageQualityPreference _currentVideoQuality = ImageQualityPreference.compressed;

  @override
  void initState() {
    super.initState();
    emitFlowEvent(
      layer: 'FL',
      event: 'SETTINGS_FL_SCREEN_INIT',
      details: {},
    );
    _loadIdentity();
    _loadQualityPreference();
    _loadVideoQualityPreference();
  }

  Future<void> _loadIdentity() async {
    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity == null || !mounted) return;

      // Load saved avatar from disk if avatarVersion is set
      Uint8List? savedAvatar;
      if (identity.avatarVersion != null) {
        try {
          final appDir = await getApplicationDocumentsDirectory();
          final avatarFile = File(
            p.join(appDir.path, 'media', 'avatars', '${identity.peerId}.jpg'),
          );
          if (avatarFile.existsSync()) {
            savedAvatar = await avatarFile.readAsBytes();
          }
        } catch (_) {}
      }

      if (!mounted) return;

      setState(() {
        _identity = identity;
        if (savedAvatar != null) {
          _pickedAvatarBytes = savedAvatar;
        }
      });
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'SETTINGS_FL_LOAD_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _onBack() {
    Navigator.of(context).pop();
  }

  void _onCopyPeerId() {
    final peerId = _identity?.peerId;
    if (peerId == null) return;

    Clipboard.setData(ClipboardData(text: peerId));

    _peerIdCopyTimer?.cancel();
    setState(() => _isPeerIdCopied = true);

    _peerIdCopyTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isPeerIdCopied = false);
    });
  }

  void _onToggleMnemonic() {
    setState(() => _isMnemonicRevealed = true);
  }

  void _onCopyMnemonic() {
    final mnemonic = _identity?.mnemonic12;
    if (mnemonic == null) return;

    Clipboard.setData(ClipboardData(text: mnemonic));

    _mnemonicCopyTimer?.cancel();
    setState(() => _isMnemonicCopied = true);

    _mnemonicCopyTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isMnemonicCopied = false);
    });
  }

  void _onHideMnemonic() {
    setState(() {
      _isMnemonicRevealed = false;
      _isMnemonicCopied = false;
    });
    _mnemonicCopyTimer?.cancel();
  }

  Future<void> _loadQualityPreference() async {
    final pref = await loadImageQualityPreference(
      secureKeyStore: widget.secureKeyStore,
    );
    if (mounted) {
      setState(() => _currentQuality = pref);
    }
  }

  Future<void> _onQualityChanged(ImageQualityPreference newQuality) async {
    setState(() => _currentQuality = newQuality);
    await saveImageQualityPreference(
      secureKeyStore: widget.secureKeyStore,
      preference: newQuality,
    );
  }

  Future<void> _loadVideoQualityPreference() async {
    final pref = await loadVideoQualityPreference(
      secureKeyStore: widget.secureKeyStore,
    );
    if (mounted) {
      setState(() => _currentVideoQuality = pref);
    }
  }

  Future<void> _onVideoQualityChanged(ImageQualityPreference newQuality) async {
    setState(() => _currentVideoQuality = newQuality);
    await saveVideoQualityPreference(
      secureKeyStore: widget.secureKeyStore,
      preference: newQuality,
    );
  }

  Future<void> _onUsernameChanged(String newUsername) async {
    final identity = _identity;
    if (identity == null) return;

    final updated = IdentityModel(
      peerId: identity.peerId,
      publicKey: identity.publicKey,
      privateKey: identity.privateKey,
      mnemonic12: identity.mnemonic12,
      mlKemPublicKey: identity.mlKemPublicKey,
      mlKemSecretKey: identity.mlKemSecretKey,
      username: newUsername,
      avatarBlob: identity.avatarBlob,
      avatarVersion: identity.avatarVersion,
      createdAt: identity.createdAt,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );

    try {
      await widget.identityRepo.saveIdentity(updated);
      if (!mounted) return;

      setState(() => _identity = updated);

      emitFlowEvent(
        layer: 'FL',
        event: 'SETTINGS_FL_USERNAME_UPDATED',
        details: {'username': newUsername},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'SETTINGS_FL_USERNAME_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onPickAvatar() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
      );
      if (picked == null || !mounted) return;

      // Process avatar: strip EXIF, compress to 512x512
      final processedPath = await widget.imageProcessor.processAvatar(
        inputPath: picked.path,
      );
      final bytes = await File(processedPath).readAsBytes();
      if (!mounted) return;

      // Show preview immediately
      final previousBytes = _pickedAvatarBytes;
      setState(() => _pickedAvatarBytes = bytes);

      // Upload to relay and notify contacts
      final success = await uploadProfilePicture(
        bridge: widget.bridge,
        identityRepo: widget.identityRepo,
        contactRepo: widget.contactRepo,
        p2pService: widget.p2pService,
        filePath: picked.path,
        mime: 'image/jpeg',
      );

      if (!mounted) return;

      if (success) {
        // Reload identity to get updated avatarVersion
        final updated = await widget.identityRepo.loadIdentity();
        if (updated != null && mounted) {
          setState(() => _identity = updated);
        }
      } else {
        // Revert preview on failure
        setState(() => _pickedAvatarBytes = previousBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload profile picture')),
          );
        }
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'SETTINGS_FL_PICK_AVATAR_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _onSwitchView(String tab) {
    // Pop back to Feed first, then let Feed handle navigation
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _peerIdCopyTimer?.cancel();
    _mnemonicCopyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final identity = _identity;

    return Scaffold(
      body: SettingsScreen(
        username: identity?.username ?? 'Username',
        peerId: identity?.peerId,
        avatarBytes: _pickedAvatarBytes ?? identity?.avatarBlob,
        mnemonic: identity?.mnemonic12,
        isMnemonicRevealed: _isMnemonicRevealed,
        isPeerIdCopied: _isPeerIdCopied,
        isMnemonicCopied: _isMnemonicCopied,
        onBack: _onBack,
        onPickAvatar: _onPickAvatar,
        onUsernameChanged: _onUsernameChanged,
        onCopyPeerId: _onCopyPeerId,
        onToggleMnemonic: _onToggleMnemonic,
        onCopyMnemonic: _onCopyMnemonic,
        onHideMnemonic: _onHideMnemonic,
        currentQuality: _currentQuality,
        onQualityChanged: _onQualityChanged,
        currentVideoQuality: _currentVideoQuality,
        onVideoQualityChanged: _onVideoQualityChanged,
        onSwitchView: _onSwitchView,
        activeTab: 'feed',
      ),
    );
  }
}
