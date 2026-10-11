import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../domain/update_check_keys.dart';
import '../domain/update_check_models.dart';
import '../domain/update_check_policy.dart';
import '../domain/update_check_state.dart';
import '../domain/version_file_verifier.dart';
import '../infrastructure/update_check_state_store.dart';
import '../infrastructure/version_file_fetcher.dart';
import 'update_check_switch.dart';

/// The SE-41 in-app update check. T2a (hard overlay) and T2b (banner) call it.
///
/// Usage for T2a/T2b:
/// - Never call it on the startup path. Call [check] after the first frame,
///   without awaiting it before the UI shows. It never throws and never
///   blocks: any failure gives the stored, re-verified result or none.
/// - Call [check] again when [isCheckDue] is true (first call in a launch,
///   more than 6 h since the last check, or the clock went back).
/// - While the result is [UpdateDecisionHard], recheck on EVERY resume.
/// - When the user dismisses the banner, call [dismissSoft] with its
///   `latestBuild`. The banner returns for a higher `latestBuild`.
class UpdateCheckService {
  UpdateCheckService({
    UpdateCheckSwitch? updateSwitch,
    VersionFileVerifier? verifier,
    VersionFileFetcher? fetcher,
    UpdateCheckStateStore? store,
    Future<String> Function()? installedBuildNumber,
    UpdatePlatform? platform,
    Uri? versionFileUrl,
    DateTime Function()? clock,
  }) : _switch = updateSwitch ?? UpdateCheckSwitch.fromEnvironment(),
       _verifier = verifier ?? VersionFileVerifier(builtInVersionKeys()),
       _fetcher = fetcher ?? VersionFileFetcher(),
       _store = store ?? UpdateCheckStateStore(),
       _installedBuildNumber = installedBuildNumber ?? _packageBuildNumber,
       _platform = platform ?? _currentPlatform(),
       _url = versionFileUrl ?? Uri.parse(updateCheckVersionFileUrl),
       _clock = clock ?? DateTime.now;

  final UpdateCheckSwitch _switch;
  final VersionFileVerifier _verifier;
  final VersionFileFetcher _fetcher;
  final UpdateCheckStateStore _store;
  final Future<String> Function() _installedBuildNumber;
  final UpdatePlatform? _platform;
  final Uri _url;
  final DateTime Function() _clock;

  bool _checkedThisLaunch = false;
  Future<UpdateDecision>? _inFlight;

  bool get isEnabled => _switch.enabled && _platform != null;

  /// Downloads, verifies and stores the version file, then decides.
  /// Concurrent calls share one run.
  Future<UpdateDecision> check() =>
      _inFlight ??= _check().whenComplete(() => _inFlight = null);

  /// True at launch, after more than 6 h, or when the clock went back.
  /// Always false when the switch is off.
  Future<bool> isCheckDue(DateTime now) async {
    if (!isEnabled) return false;
    final state = await _store.load();
    return isUpdateCheckDue(
      now: now,
      lastCheckAt: state.lastCheckAt,
      checkedThisLaunch: _checkedThisLaunch,
    );
  }

  /// Hides the banner for this [latestBuild] only.
  Future<void> dismissSoft(int latestBuild) async {
    // Let a running check save first, so it cannot overwrite the dismissal.
    await _inFlight;
    final state = await _store.load();
    await _saveQuietly(state.copyWith(dismissedLatestBuild: latestBuild));
  }

  Future<UpdateDecision> _check() async {
    final platform = _platform;
    if (!isEnabled || platform == null) return const UpdateDecisionNone();
    try {
      final loaded = await _loadVerified(platform);
      var state = loaded.state;
      var current = loaded.file;

      final downloaded = await _fetcher.fetch(_url);
      if (downloaded != null) {
        final candidate = _verifier
            .verify(
              downloaded,
              highestAcceptedRank: state.highestAcceptedRank,
              requiredPlatforms: {platform},
            )
            .file;
        if (candidate != null &&
            decideVersionFileRatchet(
                  candidate: candidate,
                  highestAcceptedRank: state.highestAcceptedRank,
                  storedSequence: state.sequence,
                  storedPayloadBytes: current?.payloadBytes,
                ) ==
                VersionFileRatchet.accept) {
          // A rank rise replaces all lower-rank state.
          state = UpdateCheckState(
            lastEnvelope: candidate.envelopeBytes,
            highestAcceptedRank: candidate.rank,
            sequence: candidate.payload.sequence,
            lastCheckAt: state.lastCheckAt,
            dismissedLatestBuild: state.dismissedLatestBuild,
          );
          current = candidate;
        }
      }
      // Every attempt counts for the schedule, failed downloads included.
      await _saveQuietly(state.copyWith(lastCheckAt: _clock()));
      _checkedThisLaunch = true;

      return decideUpdate(
        installedBuildNumber: await _installedBuildNumber(),
        policy: current?.payload.platforms[platform],
        dismissedLatestBuild: state.dismissedLatestBuild,
      );
    } catch (_) {
      // Never block on our own failure.
      return const UpdateDecisionNone();
    }
  }

  /// Re-verifies the stored envelope against the CURRENT built-in keys and the
  /// rank rule. Anything that fails is discarded and saved, so it no longer
  /// blocks.
  Future<({UpdateCheckState state, VerifiedVersionFile? file})> _loadVerified(
    UpdatePlatform platform,
  ) async {
    final state = await _store.load();
    final hasVerifiedState =
        state.lastEnvelope != null ||
        state.highestAcceptedRank != 0 ||
        state.sequence != null;
    if (!hasVerifiedState) return (state: state, file: null);

    final envelope = state.lastEnvelope;
    final file = envelope == null
        ? null
        : _verifier
              .verify(
                envelope,
                highestAcceptedRank: 0,
                requiredPlatforms: {platform},
              )
              .file;
    if (file != null &&
        file.rank == state.highestAcceptedRank &&
        file.payload.sequence == state.sequence) {
      return (state: state, file: file);
    }
    final cleared = state.withoutVerifiedFile();
    await _saveQuietly(cleared);
    return (state: cleared, file: null);
  }

  Future<void> _saveQuietly(UpdateCheckState state) async {
    try {
      await _store.save(state);
    } catch (_) {
      // A failed write only loses the cache; the next check rebuilds it.
    }
  }

  static Future<String> _packageBuildNumber() async =>
      (await PackageInfo.fromPlatform()).buildNumber;

  static UpdatePlatform? _currentPlatform() {
    if (Platform.isIOS) return UpdatePlatform.ios;
    if (Platform.isAndroid) return UpdatePlatform.android;
    return null;
  }
}
