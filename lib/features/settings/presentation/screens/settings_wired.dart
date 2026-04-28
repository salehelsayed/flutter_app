import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/settings/application/background_preference_use_cases.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/settings/application/image_quality_preference_use_cases.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/home/application/identity_avatar_resolver.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/posts/domain/models/posts_privacy_settings.dart';
import 'package:flutter_app/features/posts/domain/repositories/posts_privacy_settings_repository.dart';
import 'package:flutter_app/features/settings/application/helpers/avatar_normalization_helper.dart';
import 'package:flutter_app/features/settings/application/upload_profile_picture_use_case.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_introduction_debug_card.dart';
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
  final AppShellController appShellController;
  final PostsPrivacySettingsRepository postsPrivacySettingsRepository;
  final IntroductionRepository? introductionRepository;
  final NearbyLocationService? nearbyLocationService;
  final bool showNavigationBar;

  const SettingsWired({
    super.key,
    required this.identityRepo,
    required this.bridge,
    required this.contactRepo,
    required this.p2pService,
    required this.secureKeyStore,
    required this.imageProcessor,
    required this.appShellController,
    required this.postsPrivacySettingsRepository,
    this.introductionRepository,
    this.nearbyLocationService,
    this.showNavigationBar = true,
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
  BackgroundPreference _currentBackgroundPreference =
      BackgroundPreference.defaultBackground;
  String? _backgroundPreferenceError;
  ImageQualityPreference _currentQuality = ImageQualityPreference.compressed;
  ImageQualityPreference _currentVideoQuality =
      ImageQualityPreference.compressed;
  PostsPrivacySettings _postsPrivacySettings = const PostsPrivacySettings();
  List<IntroductionModel> _debugIntroductions = const [];
  bool _isLoadingDebugIntroductions = false;
  String? _debugIntroductionsError;

  @override
  void initState() {
    super.initState();
    emitFlowEvent(layer: 'FL', event: 'SETTINGS_FL_SCREEN_INIT', details: {});
    _loadIdentity();
    _loadBackgroundPreference();
    _loadQualityPreference();
    _loadVideoQualityPreference();
    _loadPostsPrivacySettings();
  }

  Future<void> _loadIdentity() async {
    try {
      final identity = await widget.identityRepo.loadIdentity();
      if (identity == null || !mounted) return;

      final savedAvatar = await IdentityAvatarResolver.resolve(identity);

      if (!mounted) return;

      setState(() {
        _identity = identity;
        if (savedAvatar != null) {
          _pickedAvatarBytes = savedAvatar;
        }
      });

      await _loadDebugIntroductions(identity: identity);
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

  Future<void> _loadBackgroundPreference() async {
    final pref = await loadBackgroundPreference(
      secureKeyStore: widget.secureKeyStore,
    );
    if (mounted) {
      setState(() => _currentBackgroundPreference = pref);
    }
  }

  Future<void> _onBackgroundPreferenceChanged(
    BackgroundPreference newPreference,
  ) async {
    final previousPreference = _currentBackgroundPreference;
    final storageValue = newPreference.toStorageString();

    emitFlowEvent(
      layer: 'FL',
      event: 'SETTINGS_FL_BACKGROUND_PREFERENCE_ATTEMPT',
      details: {'preference': storageValue},
    );

    setState(() {
      _currentBackgroundPreference = newPreference;
      _backgroundPreferenceError = null;
    });

    try {
      await saveBackgroundPreference(
        secureKeyStore: widget.secureKeyStore,
        preference: newPreference,
      );
      if (!mounted) return;

      emitFlowEvent(
        layer: 'FL',
        event: 'SETTINGS_FL_BACKGROUND_PREFERENCE_SAVED',
        details: {'preference': storageValue, 'outcome': 'success'},
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _currentBackgroundPreference = previousPreference;
        _backgroundPreferenceError = AppLocalizations.of(
          context,
        )!.settings_background_save_fail;
      });

      emitFlowEvent(
        layer: 'FL',
        event: 'SETTINGS_FL_BACKGROUND_PREFERENCE_SAVE_ERROR',
        details: {
          'preference': storageValue,
          'outcome': 'failure',
          'error': e.toString(),
        },
      );

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_backgroundPreferenceError!)));
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

  Future<void> _loadPostsPrivacySettings() async {
    final settings = await widget.postsPrivacySettingsRepository.load();
    if (!mounted) {
      return;
    }
    setState(() => _postsPrivacySettings = settings);
  }

  Future<void> _onNearbySharingChanged(bool enabled) async {
    if (enabled) {
      final updated = _postsPrivacySettings.copyWith(sharingEnabled: true);
      setState(() => _postsPrivacySettings = updated);
      await widget.postsPrivacySettingsRepository.save(updated);
      await widget.nearbyLocationService?.refreshInteractivelyFromSettings();
      await _loadPostsPrivacySettings();
      return;
    }
    await widget.nearbyLocationService?.handleSharingDisabled();
    final updated = _postsPrivacySettings.copyWith(
      sharingEnabled: false,
      clearSnapshot: true,
    );
    setState(() => _postsPrivacySettings = updated);
    await widget.postsPrivacySettingsRepository.save(updated);
  }

  Future<void> _loadDebugIntroductions({IdentityModel? identity}) async {
    final introRepo = widget.introductionRepository;
    final currentIdentity = identity ?? _identity;
    if (!kDebugMode || introRepo == null || currentIdentity == null) {
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingDebugIntroductions = true;
        _debugIntroductionsError = null;
      });
    }

    try {
      final introductions = await introRepo.getIntroductionsByIntroducer(
        currentIdentity.peerId,
      );
      introductions.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!mounted) return;
      setState(() {
        _debugIntroductions = introductions;
        _isLoadingDebugIntroductions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _debugIntroductionsError = e.toString();
        _isLoadingDebugIntroductions = false;
      });
    }
  }

  Future<void> _deleteDebugIntroduction(String id) async {
    final introRepo = widget.introductionRepository;
    if (introRepo == null) return;

    await introRepo.deleteIntroduction(id);
    if (!mounted) return;

    setState(() {
      _debugIntroductions = _debugIntroductions
          .where((intro) => intro.id != id)
          .toList();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Deleted local introduction row')),
    );
  }

  Future<void> _deleteDebugPair(IntroductionModel target) async {
    final introRepo = widget.introductionRepository;
    if (introRepo == null) return;

    final matching = _debugIntroductions.where((intro) {
      return (intro.recipientId == target.recipientId &&
              intro.introducedId == target.introducedId) ||
          (intro.recipientId == target.introducedId &&
              intro.introducedId == target.recipientId);
    }).toList();

    for (final intro in matching) {
      await introRepo.deleteIntroduction(intro.id);
    }

    if (!mounted) return;

    setState(() {
      final removedIds = matching.map((intro) => intro.id).toSet();
      _debugIntroductions = _debugIntroductions
          .where((intro) => !removedIds.contains(intro.id))
          .toList();
    });

    final pairLabel =
        '${target.recipientUsername ?? target.recipientId} <-> ${target.introducedUsername ?? target.introducedId}';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Deleted local pair $pairLabel')));
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
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;

      final avatarNormalizer = AvatarNormalizationHelper(
        imageProcessor: widget.imageProcessor,
      );
      final processedPath = await avatarNormalizer.prepareAvatar(
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
        filePath: processedPath,
        mime: 'image/jpeg',
        avatarNormalizer: avatarNormalizer,
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
            SnackBar(
              content: Text(AppLocalizations.of(context)!.settings_photo_fail),
            ),
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
    widget.appShellController.switchTo(tab);
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
        currentBackgroundPreference: _currentBackgroundPreference,
        onBackgroundPreferenceChanged: _onBackgroundPreferenceChanged,
        backgroundPreferenceErrorText: _backgroundPreferenceError,
        currentQuality: _currentQuality,
        onQualityChanged: _onQualityChanged,
        currentVideoQuality: _currentVideoQuality,
        onVideoQualityChanged: _onVideoQualityChanged,
        isNearbySharingEnabled: _postsPrivacySettings.sharingEnabled,
        onNearbySharingChanged: _onNearbySharingChanged,
        debugSection: kDebugMode && widget.introductionRepository != null
            ? SettingsIntroductionDebugCard(
                introductions: _debugIntroductions,
                isLoading: _isLoadingDebugIntroductions,
                errorText: _debugIntroductionsError,
                onRefresh: () => _loadDebugIntroductions(),
                onDeleteIntroduction: _deleteDebugIntroduction,
                onDeletePair: _deleteDebugPair,
              )
            : null,
        onSwitchView: _onSwitchView,
        activeTab: widget.appShellController.activeTab,
        showNavigationBar: widget.showNavigationBar,
      ),
    );
  }
}
