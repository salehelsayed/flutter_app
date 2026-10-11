/// Plain-Dart models for the SE-41 in-app update check.
///
/// This file and the rest of `domain/` must not import Flutter: the signing
/// CLI (`tool/sign_version_file.dart`) runs them with `dart run`.
library;

/// Why an update is offered or required. Unknown or missing codes map to
/// [general] (SE-41 O3). T1 only parses the code; the UI copy comes in T2.
enum UpdateReasonCode {
  general('general'),
  security('security'),
  protocolChange('protocol_change'),
  criticalFix('critical_fix');

  const UpdateReasonCode(this.wireName);

  final String wireName;

  static UpdateReasonCode parse(Object? raw) {
    for (final code in values) {
      if (code.wireName == raw) return code;
    }
    return general;
  }
}

/// The platform sections a version file carries.
enum UpdatePlatform {
  ios('ios'),
  android('android');

  const UpdatePlatform(this.wireName);

  final String wireName;
}

/// One platform section of the signed payload.
class UpdatePlatformPolicy {
  const UpdatePlatformPolicy({
    required this.latestBuild,
    required this.minBuild,
    required this.reasonCode,
  });

  final int latestBuild;
  final int minBuild;
  final UpdateReasonCode reasonCode;
}

/// The signed payload, parsed only after its signature was verified.
class VersionPayload {
  const VersionPayload({
    required this.sequence,
    required this.issuedAt,
    required this.platforms,
  });

  final int sequence;

  /// Unix seconds. Information only: never used to accept or reject a file.
  final int issuedAt;

  final Map<UpdatePlatform, UpdatePlatformPolicy> platforms;
}

/// What the caller (T2a/T2b) should show.
sealed class UpdateDecision {
  const UpdateDecision();
}

/// No banner and no block.
final class UpdateDecisionNone extends UpdateDecision {
  const UpdateDecisionNone();

  @override
  bool operator ==(Object other) => other is UpdateDecisionNone;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'UpdateDecision.none';
}

/// A newer build exists. The user may dismiss it with `dismissSoft`.
final class UpdateDecisionSoft extends UpdateDecision {
  const UpdateDecisionSoft({
    required this.latestBuild,
    required this.reasonCode,
  });

  final int latestBuild;
  final UpdateReasonCode reasonCode;

  @override
  bool operator ==(Object other) =>
      other is UpdateDecisionSoft &&
      other.latestBuild == latestBuild &&
      other.reasonCode == reasonCode;

  @override
  int get hashCode => Object.hash(latestBuild, reasonCode);

  @override
  String toString() =>
      'UpdateDecision.soft($latestBuild, ${reasonCode.wireName})';
}

/// The installed build is below `minBuild`. The app must block (T2a).
final class UpdateDecisionHard extends UpdateDecision {
  const UpdateDecisionHard({required this.minBuild, required this.reasonCode});

  final int minBuild;
  final UpdateReasonCode reasonCode;

  @override
  bool operator ==(Object other) =>
      other is UpdateDecisionHard &&
      other.minBuild == minBuild &&
      other.reasonCode == reasonCode;

  @override
  int get hashCode => Object.hash(minBuild, reasonCode);

  @override
  String toString() => 'UpdateDecision.hard($minBuild, ${reasonCode.wireName})';
}
