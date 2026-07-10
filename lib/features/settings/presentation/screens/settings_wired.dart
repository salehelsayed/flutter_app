import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/settings/application/background_preference_use_cases.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/settings/application/image_quality_preference_use_cases.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/migration_account_size_estimator.dart';
import 'package:flutter_app/features/account_migration/presentation/screens/account_migration_journey_wired.dart';
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
import 'package:flutter_app/features/settings/domain/models/media_download_preferences.dart';
import 'package:flutter_app/features/settings/application/media_download_preference_use_cases.dart';
import 'package:flutter_app/features/settings/presentation/navigation/settings_route_transition.dart';
import 'package:flutter_app/features/settings/presentation/widgets/background_choice_control.dart';
import 'package:flutter_app/features/settings/presentation/widgets/image_quality_toggle.dart';
import 'package:flutter_app/features/settings/presentation/widgets/media_download_matrix_control.dart';
import 'package:flutter_app/features/settings/presentation/widgets/media_storage_usage_section.dart';
import 'package:flutter_app/core/media/media_storage_manager.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_introduction_debug_card.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_recovery_phrase_card.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart';
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
  final TransportMetrics? transportMetrics;
  final WidgetBuilder? moveAccountRouteBuilder;
  final AccountMigrationTransferRunFn? accountMigrationRunTransfer;
  final AccountMigrationSizeGate? accountMigrationSizeGate;
  final bool showNavigationBar;

  /// 209 — host-built QR entries (the orbit host wraps its existing
  /// `_onMyQR`/`_onScanQR`; the returned Future completes when the pushed QR
  /// route pops, releasing the single-flight latch). The tiles render ONLY
  /// when BOTH are supplied (INV-209-1) — a host that cannot supply the
  /// scanner dependency bundle simply gets no tiles (spec §7.1).
  final Future<void> Function()? onMyQrRequested;
  final Future<void> Function()? onScanQrRequested;

  /// 229 — optional storage-management capability for the Media & storage
  /// sheet. The auto-download matrix always renders (it needs only
  /// [secureKeyStore]); the storage totals/actions section renders only when
  /// BOTH the manager and the scopes provider are supplied.
  final MediaStorageManager? mediaStorageManager;
  final Future<List<MediaStorageScopeOption>> Function()?
  mediaStorageScopesProvider;

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
    this.transportMetrics,
    this.moveAccountRouteBuilder,
    this.accountMigrationRunTransfer,
    this.accountMigrationSizeGate,
    this.showNavigationBar = true,
    this.onMyQrRequested,
    this.onScanQrRequested,
    this.mediaStorageManager,
    this.mediaStorageScopesProvider,
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
  MediaDownloadPreferences _mediaDownloadPreferences =
      const MediaDownloadPreferences.defaults();
  String? _mediaDownloadError;
  PostsPrivacySettings _postsPrivacySettings = const PostsPrivacySettings();
  List<IntroductionModel> _debugIntroductions = const [];
  bool _isLoadingDebugIntroductions = false;
  String? _debugIntroductionsError;

  // 209 — single-flight latch for the host-built QR entries (mirrors orbit's
  // `_settingsRouteActive`): held while the pushed QR route is up, released
  // when the host's Future completes (route pop / stack teardown).
  bool _qrRouteActive = false;

  // 209 TC-209-36 — single-flight latch for the move-account route.
  bool _moveRouteActive = false;

  // 209 — rebuilds the open recovery sheet when page-owned mnemonic state
  // changes outside a sheet gesture (the 2s copy-revert timer). Null when no
  // recovery sheet is open.
  VoidCallback? _recoverySheetTick;

  double _settingsSwipeBackDx = 0;

  @override
  void initState() {
    super.initState();
    emitFlowEvent(layer: 'FL', event: 'SETTINGS_FL_SCREEN_INIT', details: {});
    _loadIdentity();
    _loadBackgroundPreference();
    _loadQualityPreference();
    _loadVideoQualityPreference();
    _loadMediaDownloadPreferences();
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
      // 209: the card now lives inside a modal sheet whose StatefulBuilder
      // does not see page setState — poke it so "Copied!" reverts in place.
      _recoverySheetTick?.call();
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
      widget.appShellController.setBackgroundPreference(pref);
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
      widget.appShellController.setBackgroundPreference(newPreference);
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
    // 206: propagate so the Feed's next media send honors the new preference.
    widget.appShellController.notifyMediaQualityChanged();
  }

  Future<void> _loadVideoQualityPreference() async {
    final pref = await loadVideoQualityPreference(
      secureKeyStore: widget.secureKeyStore,
    );
    if (mounted) {
      setState(() => _currentVideoQuality = pref);
    }
  }

  Future<void> _loadMediaDownloadPreferences() async {
    final prefs = await loadMediaDownloadPreferences(
      secureKeyStore: widget.secureKeyStore,
    );
    if (mounted) {
      setState(() => _mediaDownloadPreferences = prefs);
    }
  }

  /// 229: optimistic persist-with-rollback (the background-preference
  /// pattern): a failed write restores the previous matrix and surfaces a
  /// visible error instead of a lying toggle.
  Future<void> _onMediaDownloadPreferencesChanged(
    MediaDownloadPreferences next,
  ) async {
    final previous = _mediaDownloadPreferences;
    setState(() {
      _mediaDownloadPreferences = next;
      _mediaDownloadError = null;
    });
    try {
      await saveMediaDownloadPreferences(
        secureKeyStore: widget.secureKeyStore,
        preferences: next,
      );
      if (!mounted) return;
      emitFlowEvent(
        layer: 'FL',
        event: 'SETTINGS_FL_MEDIA_DOWNLOAD_SAVED',
        details: {'outcome': 'success'},
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mediaDownloadPreferences = previous;
        _mediaDownloadError = AppLocalizations.of(
          context,
        )!.settings_media_save_fail;
      });
      emitFlowEvent(
        layer: 'FL',
        event: 'SETTINGS_FL_MEDIA_DOWNLOAD_SAVE_ERROR',
        details: {'outcome': 'failure', 'error': e.toString()},
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mediaDownloadError!)));
    }
  }

  Future<void> _openMediaStorageSheet() {
    final manager = widget.mediaStorageManager;
    final scopesProvider = widget.mediaStorageScopesProvider;
    return _showSettingsSheet(
      builder: (sheetContext, setSheetState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MediaDownloadMatrixControl(
            preferences: _mediaDownloadPreferences,
            errorText: _mediaDownloadError,
            onChanged: (next) async {
              await _onMediaDownloadPreferencesChanged(next);
              if (!mounted || !sheetContext.mounted) return;
              // The sheet stays open for further matrix edits; rebuild it
              // in place so the choice (or the rollback) is visible.
              setSheetState(() {});
            },
          ),
          if (manager != null && scopesProvider != null)
            MediaStorageUsageSection(
              manager: manager,
              loadScopes: scopesProvider,
            ),
        ],
      ),
    );
  }

  Future<void> _onVideoQualityChanged(ImageQualityPreference newQuality) async {
    setState(() => _currentVideoQuality = newQuality);
    await saveVideoQualityPreference(
      secureKeyStore: widget.secureKeyStore,
      preference: newQuality,
    );
    // 206: propagate so the Feed's next media send honors the new preference.
    widget.appShellController.notifyMediaQualityChanged();
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

    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.settings_intro_debug_deleted_row)),
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
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.settings_intro_debug_deleted_pair(pairLabel)),
      ),
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
      // 206: propagate the identity change to the Feed AND Orbit passively (the
      // shared AppShellController), replacing the removed Feed-header `.then`.
      widget.appShellController.notifyIdentityChanged();

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
        // 206: fire AFTER uploadProfilePicture's invalidatePeer broadcasts so
        // the resolver re-reads the fresh bytes when listeners reload identity.
        widget.appShellController.notifyIdentityChanged();
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

  void _onSettingsHorizontalDragStart(DragStartDetails details) {
    _settingsSwipeBackDx = 0;
  }

  void _onSettingsHorizontalDragUpdate(DragUpdateDetails details) {
    _settingsSwipeBackDx += details.delta.dx;
  }

  void _onSettingsHorizontalDragEnd(DragEndDetails details) {
    final totalDx = _settingsSwipeBackDx;
    _settingsSwipeBackDx = 0;
    final width = MediaQuery.sizeOf(context).width;
    final velocity = details.primaryVelocity ?? 0;
    final qualifies =
        totalDx > 0 && (totalDx >= width * 0.28 || velocity >= 900);
    if (!qualifies) return;
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;

    _onSwitchView(AppShellTab.orbit);
  }

  // 209 — funnels both QR tiles through the single-flight latch: a second tap
  // (same tile or the sibling) is swallowed while the pushed route is up.
  Future<void> _runQrEntry(Future<void> Function() entry) async {
    if (_qrRouteActive) return;
    _qrRouteActive = true;
    try {
      await entry();
    } finally {
      _qrRouteActive = false;
    }
  }

  /// 209 — shared modal-sheet shell for the row sub-surfaces: `surfaceBase`
  /// panel with a 16px top radius, re-providing the readable-tone Theme
  /// extension (a modal route does not inherit AmbientBackground's — the
  /// FriendPicker precedent).
  Future<void> _showSettingsSheet({
    required Widget Function(
      BuildContext sheetContext,
      StateSetter setSheetState,
    )
    builder,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      // The hosted controls (4-option background chooser, recovery card) are
      // taller than the default sheet cap — size to content, scroll past it.
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final theme = Theme.of(context);
          final readableColors = BackgroundReadableColors.resolve(
            _currentBackgroundPreference,
          );
          return Theme(
            data: theme.copyWith(
              extensions: [
                ...theme.extensions.values.where(
                  (extension) => extension is! BackgroundReadableColors,
                ),
                readableColors,
              ],
            ),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
              ),
              decoration: BoxDecoration(
                color: readableColors.surfaceBase,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                border: Border(top: BorderSide(color: readableColors.divider)),
              ),
              padding: const EdgeInsets.only(top: 16, bottom: 16),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  child: builder(sheetContext, setSheetState),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openBackgroundSheet() {
    return _showSettingsSheet(
      builder: (sheetContext, setSheetState) => BackgroundChoiceControl(
        value: _currentBackgroundPreference,
        errorText: _backgroundPreferenceError,
        onChanged: (newPreference) async {
          // The EXISTING handler is the single mechanism (persist + shell
          // propagation + failure revert + telemetry). On success the sheet
          // closes to the updated row; on failure it stays up with the error.
          await _onBackgroundPreferenceChanged(newPreference);
          if (!mounted || !sheetContext.mounted) return;
          if (_backgroundPreferenceError != null) {
            setSheetState(() {});
            return;
          }
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  Future<void> _openPhotoQualitySheet() {
    final l10n = AppLocalizations.of(context)!;
    return _showSettingsSheet(
      builder: (sheetContext, setSheetState) => ImageQualityToggle(
        value: _currentQuality,
        label: l10n.settings_photo_quality,
        onChanged: (newQuality) async {
          await _onQualityChanged(newQuality);
          if (!mounted || !sheetContext.mounted) return;
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  Future<void> _openVideoQualitySheet() {
    final l10n = AppLocalizations.of(context)!;
    return _showSettingsSheet(
      builder: (sheetContext, setSheetState) => ImageQualityToggle(
        value: _currentVideoQuality,
        label: l10n.settings_video_quality,
        icon: Icons.videocam,
        onChanged: (newQuality) async {
          await _onVideoQualityChanged(newQuality);
          if (!mounted || !sheetContext.mounted) return;
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  Future<void> _openRecoverySheet() {
    final words = _identity?.mnemonic12.split(' ') ?? const <String>[];
    if (words.length != 12) return Future.value();
    return _showSettingsSheet(
      builder: (sheetContext, setSheetState) {
        _recoverySheetTick = () => setSheetState(() {});
        return SettingsRecoveryPhraseCard(
          words: words,
          isRevealed: _isMnemonicRevealed,
          isCopied: _isMnemonicCopied,
          onToggleReveal: () {
            _onToggleMnemonic();
            setSheetState(() {});
          },
          onCopy: () {
            _onCopyMnemonic();
            setSheetState(() {});
          },
          onHide: () {
            _onHideMnemonic();
            setSheetState(() {});
          },
        );
      },
    ).whenComplete(() {
      _recoverySheetTick = null;
      // Session hygiene: re-blur for the next open — the phrase is NEVER
      // rendered on the One-Screen page itself (TC-209-29).
      if (mounted) _onHideMnemonic();
    });
  }

  void _onMoveAccountToNewPhone() {
    if (_moveRouteActive) return;
    _moveRouteActive = true;
    emitFlowEvent(
      layer: 'FL',
      event: 'SETTINGS_FL_MOVE_ACCOUNT_NAVIGATE',
      details: {
        'hasTransferRunner': widget.accountMigrationRunTransfer != null,
      },
    );

    Navigator.of(context)
        .push(
          buildSettingsSlideUpRoute<void>(
            builder:
                widget.moveAccountRouteBuilder ??
                (_) => AccountMigrationJourneyWired.oldPhone(
                  secureKeyStore: widget.secureKeyStore,
                  identityRepository: widget.identityRepo,
                  runTransfer: widget.accountMigrationRunTransfer,
                  sizeGate: widget.accountMigrationSizeGate,
                  backgroundPreference: _currentBackgroundPreference,
                ),
            settings: const RouteSettings(name: 'account-migration-old-phone'),
          ),
        )
        .whenComplete(() {
          _moveRouteActive = false;
        });
  }

  /// Builds the debug-only settings section. Only rendered in [kDebugMode].
  ///
  /// Composes the introduction debug card and the transport diagnostics card
  /// (whichever dependencies are available) into a single column so they can
  /// share the screen's single `debugSection` slot.
  Widget? _buildDebugSection() {
    if (!kDebugMode) {
      return null;
    }

    final cards = <Widget>[];

    if (widget.introductionRepository != null) {
      cards.add(
        SettingsIntroductionDebugCard(
          introductions: _debugIntroductions,
          isLoading: _isLoadingDebugIntroductions,
          errorText: _debugIntroductionsError,
          onRefresh: () => _loadDebugIntroductions(),
          onDeleteIntroduction: _deleteDebugIntroduction,
          onDeletePair: _deleteDebugPair,
        ),
      );
    }

    final transportMetrics = widget.transportMetrics;
    if (transportMetrics != null) {
      if (cards.isNotEmpty) {
        cards.add(const SizedBox(height: 16));
      }
      cards.add(SettingsTransportDiagnosticsCard(metrics: transportMetrics));
    }

    if (cards.isEmpty) {
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: cards,
    );
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
    // INV-209-1: the tiles are a capability PAIR — a host supplying only one
    // entry gets no tiles at all (no asymmetric single tile).
    final canHostQr =
        widget.onMyQrRequested != null && widget.onScanQrRequested != null;

    final screen = SettingsScreen(
      username: identity?.username ?? 'Username',
      peerId: identity?.peerId,
      avatarBytes: _pickedAvatarBytes ?? identity?.avatarBlob,
      mnemonic: identity?.mnemonic12,
      isPeerIdCopied: _isPeerIdCopied,
      onBack: _onBack,
      onPickAvatar: _onPickAvatar,
      onUsernameChanged: _onUsernameChanged,
      onCopyPeerId: _onCopyPeerId,
      onMyQr: canHostQr ? () => _runQrEntry(widget.onMyQrRequested!) : null,
      onScan: canHostQr ? () => _runQrEntry(widget.onScanQrRequested!) : null,
      onOpenBackgroundSheet: _openBackgroundSheet,
      onOpenPhotoQualitySheet: _openPhotoQualitySheet,
      onOpenVideoQualitySheet: _openVideoQualitySheet,
      onOpenMediaStorageSheet: _openMediaStorageSheet,
      onOpenRecoverySheet: _openRecoverySheet,
      currentBackgroundPreference: _currentBackgroundPreference,
      currentQuality: _currentQuality,
      currentVideoQuality: _currentVideoQuality,
      isNearbySharingEnabled: _postsPrivacySettings.sharingEnabled,
      onNearbySharingChanged: _onNearbySharingChanged,
      onMoveAccountToNewPhone: identity == null
          ? null
          : _onMoveAccountToNewPhone,
      debugSection: _buildDebugSection(),
      onSwitchView: _onSwitchView,
      activeTab: widget.appShellController.activeTab,
      showNavigationBar: widget.showNavigationBar,
    );
    final body = widget.showNavigationBar
        ? GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: _onSettingsHorizontalDragStart,
            onHorizontalDragUpdate: _onSettingsHorizontalDragUpdate,
            onHorizontalDragEnd: _onSettingsHorizontalDragEnd,
            child: screen,
          )
        : screen;

    return Scaffold(body: body);
  }
}
