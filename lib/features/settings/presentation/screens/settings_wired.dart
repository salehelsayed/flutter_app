import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'settings_screen.dart';

/// Wired widget connecting SettingsScreen to business logic.
///
/// Loads identity, manages mnemonic reveal/hide state and copy timers.
class SettingsWired extends StatefulWidget {
  final IdentityRepository identityRepo;

  const SettingsWired({
    super.key,
    required this.identityRepo,
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

  @override
  void initState() {
    super.initState();
    emitFlowEvent(
      layer: 'FL',
      event: 'SETTINGS_FL_SCREEN_INIT',
      details: {},
    );
    _loadIdentity();
  }

  Future<void> _loadIdentity() async {
    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity == null || !mounted) return;

      setState(() {
        _identity = identity;
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
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;

      setState(() => _pickedAvatarBytes = bytes);
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
        onSwitchView: _onSwitchView,
        activeTab: 'feed',
      ),
    );
  }
}
