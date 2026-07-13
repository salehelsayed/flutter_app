/// Message-scoped group private-media lifecycle vocabulary.
///
/// Wire values use camelCase while durable SQLite values use snake_case. The
/// unsupported value is local-only and is never emitted by [toWireExtras].
enum GroupMediaLifecycle {
  standard(wireValue: 'standard', databaseValue: 'standard'),
  viewOnce(wireValue: 'viewOnce', databaseValue: 'view_once'),
  disappearing(wireValue: 'disappearing', databaseValue: 'disappearing'),
  unsupported(wireValue: 'unsupported', databaseValue: 'unsupported');

  const GroupMediaLifecycle({
    required this.wireValue,
    required this.databaseValue,
  });

  final String wireValue;
  final String databaseValue;

  static GroupMediaLifecycle fromWireValue(Object? value) {
    for (final lifecycle in values) {
      if (lifecycle != GroupMediaLifecycle.unsupported &&
          lifecycle.wireValue == value) {
        return lifecycle;
      }
    }
    return GroupMediaLifecycle.unsupported;
  }

  static GroupMediaLifecycle fromDatabaseValue(Object? value) {
    for (final lifecycle in values) {
      if (lifecycle.databaseValue == value) return lifecycle;
    }
    return GroupMediaLifecycle.unsupported;
  }
}

enum GroupPrivateMediaAttachmentKind { image, video, gif, audio, file, unknown }

/// Message-shape facts used to validate a sender or received private policy.
class GroupPrivateMediaEligibility {
  const GroupPrivateMediaEligibility({
    required this.attachmentCount,
    required this.attachmentKind,
    this.hasTextOrCaption = false,
    this.hasQuote = false,
    this.isEdit = false,
    this.isForward = false,
  });

  final int attachmentCount;
  final GroupPrivateMediaAttachmentKind attachmentKind;
  final bool hasTextOrCaption;
  final bool hasQuote;
  final bool isEdit;
  final bool isForward;

  bool get allowsPrivateMedia {
    final isVisual =
        attachmentKind == GroupPrivateMediaAttachmentKind.image ||
        attachmentKind == GroupPrivateMediaAttachmentKind.video;
    return attachmentCount == 1 &&
        isVisual &&
        !hasTextOrCaption &&
        !hasQuote &&
        !isEdit &&
        !isForward;
  }

  @override
  bool operator ==(Object other) =>
      other is GroupPrivateMediaEligibility &&
      other.attachmentCount == attachmentCount &&
      other.attachmentKind == attachmentKind &&
      other.hasTextOrCaption == hasTextOrCaption &&
      other.hasQuote == hasQuote &&
      other.isEdit == isEdit &&
      other.isForward == isForward;

  @override
  int get hashCode => Object.hash(
    attachmentCount,
    attachmentKind,
    hasTextOrCaption,
    hasQuote,
    isEdit,
    isForward,
  );
}

/// Typed, fail-closed group private-media policy.
///
/// Absence of all four wire fields is legacy ordinary. Once any policy field
/// is present, all four must be present with exact Dart types; in particular,
/// explicit null duration is required for protected-only and View Once.
class GroupPrivateMediaPolicy {
  const GroupPrivateMediaPolicy._({
    required this.version,
    required this.lifecycle,
    required this.protected,
    this.durationSeconds,
  });

  const GroupPrivateMediaPolicy.ordinary()
    : version = 0,
      lifecycle = GroupMediaLifecycle.standard,
      durationSeconds = null,
      protected = false;

  const GroupPrivateMediaPolicy.unsupported({int sourceVersion = 0})
    : version = sourceVersion < 0 ? 0 : sourceVersion,
      lifecycle = GroupMediaLifecycle.unsupported,
      durationSeconds = null,
      protected = true;

  const GroupPrivateMediaPolicy.protected()
    : version = 1,
      lifecycle = GroupMediaLifecycle.standard,
      durationSeconds = null,
      protected = true;

  const GroupPrivateMediaPolicy.viewOnce()
    : version = 1,
      lifecycle = GroupMediaLifecycle.viewOnce,
      durationSeconds = null,
      protected = true;

  factory GroupPrivateMediaPolicy.disappearing(int durationSeconds) {
    if (!allowedDurationsSeconds.contains(durationSeconds)) {
      return const GroupPrivateMediaPolicy.unsupported(sourceVersion: 1);
    }
    return GroupPrivateMediaPolicy._(
      version: 1,
      lifecycle: GroupMediaLifecycle.disappearing,
      durationSeconds: durationSeconds,
      protected: true,
    );
  }

  static const allowedDurationsSeconds = <int>{3600, 86400, 604800};

  static const wireKeys = <String>{
    'mediaPolicyVersion',
    'mediaLifecycle',
    'mediaDurationSeconds',
    'mediaProtected',
  };

  final int version;
  final GroupMediaLifecycle lifecycle;
  final int? durationSeconds;
  final bool protected;

  factory GroupPrivateMediaPolicy.fromWireExtras(
    Map<String, Object?> extras, {
    GroupPrivateMediaEligibility? eligibility,
  }) {
    final hasAnyPolicyField = wireKeys.any(extras.containsKey);
    if (!hasAnyPolicyField) return const GroupPrivateMediaPolicy.ordinary();
    final rawVersion = extras['mediaPolicyVersion'];
    final sourceVersion = rawVersion is int && rawVersion >= 0 ? rawVersion : 0;
    if (!wireKeys.every(extras.containsKey)) {
      return GroupPrivateMediaPolicy.unsupported(sourceVersion: sourceVersion);
    }

    if (rawVersion is! int || rawVersion != 1) {
      return GroupPrivateMediaPolicy.unsupported(sourceVersion: sourceVersion);
    }

    final rawProtected = extras['mediaProtected'];
    if (rawProtected is! bool || !rawProtected) {
      return const GroupPrivateMediaPolicy.unsupported(sourceVersion: 1);
    }
    final lifecycle = GroupMediaLifecycle.fromWireValue(
      extras['mediaLifecycle'],
    );
    final rawDuration = extras['mediaDurationSeconds'];
    switch (lifecycle) {
      case GroupMediaLifecycle.standard:
        final parsed = rawDuration == null
            ? const GroupPrivateMediaPolicy.protected()
            : const GroupPrivateMediaPolicy.unsupported(sourceVersion: 1);
        return eligibility == null ? parsed : parsed.validatedFor(eligibility);
      case GroupMediaLifecycle.viewOnce:
        final parsed = rawDuration == null
            ? const GroupPrivateMediaPolicy.viewOnce()
            : const GroupPrivateMediaPolicy.unsupported(sourceVersion: 1);
        return eligibility == null ? parsed : parsed.validatedFor(eligibility);
      case GroupMediaLifecycle.disappearing:
        if (rawDuration is! int ||
            !allowedDurationsSeconds.contains(rawDuration)) {
          return const GroupPrivateMediaPolicy.unsupported(sourceVersion: 1);
        }
        final parsed = GroupPrivateMediaPolicy.disappearing(rawDuration);
        return eligibility == null ? parsed : parsed.validatedFor(eligibility);
      case GroupMediaLifecycle.unsupported:
        return const GroupPrivateMediaPolicy.unsupported(sourceVersion: 1);
    }
  }

  /// Parses the constrained durable policy columns.
  ///
  /// Missing columns identify a pre-v101 legacy row. Every explicit malformed
  /// or internally inconsistent tuple normalizes to durable unsupported.
  factory GroupPrivateMediaPolicy.fromDatabase({
    required Object? version,
    required Object? lifecycle,
    required Object? durationSeconds,
    required Object? protected,
  }) {
    if (version == null &&
        lifecycle == null &&
        durationSeconds == null &&
        protected == null) {
      return const GroupPrivateMediaPolicy.ordinary();
    }
    final sourceVersion = version is int && version >= 0 ? version : 0;
    if (version == 0 &&
        lifecycle == GroupMediaLifecycle.standard.databaseValue &&
        durationSeconds == null &&
        protected == 0) {
      return const GroupPrivateMediaPolicy.ordinary();
    }
    if (lifecycle == GroupMediaLifecycle.unsupported.databaseValue) {
      return GroupPrivateMediaPolicy.unsupported(sourceVersion: sourceVersion);
    }
    if (version is! int || version != 1 || protected != 1) {
      return GroupPrivateMediaPolicy.unsupported(sourceVersion: sourceVersion);
    }

    switch (GroupMediaLifecycle.fromDatabaseValue(lifecycle)) {
      case GroupMediaLifecycle.standard:
        return durationSeconds == null
            ? const GroupPrivateMediaPolicy.protected()
            : const GroupPrivateMediaPolicy.unsupported(sourceVersion: 1);
      case GroupMediaLifecycle.viewOnce:
        return durationSeconds == null
            ? const GroupPrivateMediaPolicy.viewOnce()
            : const GroupPrivateMediaPolicy.unsupported(sourceVersion: 1);
      case GroupMediaLifecycle.disappearing:
        if (durationSeconds is! int ||
            !allowedDurationsSeconds.contains(durationSeconds)) {
          return const GroupPrivateMediaPolicy.unsupported(sourceVersion: 1);
        }
        return GroupPrivateMediaPolicy.disappearing(durationSeconds);
      case GroupMediaLifecycle.unsupported:
        return const GroupPrivateMediaPolicy.unsupported(sourceVersion: 1);
    }
  }

  bool get isOrdinary => version == 0 && !protected && !isUnsupported;

  bool get isPrivate => version == 1 && protected && !isUnsupported;

  bool get isUnsupported => lifecycle == GroupMediaLifecycle.unsupported;

  bool get requiresRedaction => isPrivate || isUnsupported;

  GroupPrivateMediaPolicy validatedFor(
    GroupPrivateMediaEligibility eligibility,
  ) {
    if (!isPrivate || isUnsupported) return this;
    if (eligibility.allowsPrivateMedia) return this;
    return GroupPrivateMediaPolicy.unsupported(sourceVersion: version);
  }

  /// Returns exactly the four encrypted-inner sender fields.
  ///
  /// Ordinary legacy and local unsupported state are never emitted.
  Map<String, Object?>? toWireExtras() {
    if (!isPrivate) return null;
    return <String, Object?>{
      'mediaPolicyVersion': version,
      'mediaLifecycle': lifecycle.wireValue,
      'mediaDurationSeconds': durationSeconds,
      'mediaProtected': protected,
    };
  }

  Map<String, Object?> toDatabaseMap() => <String, Object?>{
    'media_policy_version': version,
    'media_lifecycle': lifecycle.databaseValue,
    'media_duration_seconds': durationSeconds,
    'media_protected': protected ? 1 : 0,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is GroupPrivateMediaPolicy &&
            other.version == version &&
            other.lifecycle == lifecycle &&
            other.durationSeconds == durationSeconds &&
            other.protected == protected;
  }

  @override
  int get hashCode =>
      Object.hash(version, lifecycle, durationSeconds, protected);

  @override
  String toString() =>
      'GroupPrivateMediaPolicy(version: $version, '
      'lifecycle: ${lifecycle.databaseValue}, '
      'durationSeconds: $durationSeconds, protected: $protected)';
}
