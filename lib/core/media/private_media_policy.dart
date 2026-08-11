/// Versioned, UI-independent policy vocabulary for private media.
///
/// The policy is permitted only inside an encrypted message payload. Database
/// mapping uses the same wire values so future direct/group consumers can
/// share fail-closed parsing without importing presentation code.
enum PrivateMediaMode {
  ordinary('ordinary'),
  protected('protected'),
  viewOnce('view_once'),
  disappearing('disappearing'),
  unsupported('unsupported');

  const PrivateMediaMode(this.wireValue);

  final String wireValue;

  static PrivateMediaMode fromWireValue(Object? value) {
    for (final mode in values) {
      if (mode.wireValue == value) return mode;
    }
    return PrivateMediaMode.unsupported;
  }
}

enum PrivateMediaLifecycleState {
  none('none'),
  available('available'),
  opening('opening'),
  viewing('viewing'),
  consumed('consumed'),
  expired('expired'),
  unsupported('unsupported');

  const PrivateMediaLifecycleState(this.wireValue);

  final String wireValue;

  static PrivateMediaLifecycleState fromWireValue(Object? value) {
    for (final state in values) {
      if (state.wireValue == value) return state;
    }
    return PrivateMediaLifecycleState.unsupported;
  }

  bool get isTerminal =>
      this == PrivateMediaLifecycleState.consumed ||
      this == PrivateMediaLifecycleState.expired ||
      this == PrivateMediaLifecycleState.unsupported;
}

enum PrivateMediaAttachmentKind { image, gif, video, audio, file, unknown }

/// Typed input shape used to decide whether a private policy is eligible.
///
/// This describes domain facts only. Composer widgets and attachment models
/// adapt their state to this value at their own boundary.
class PrivateMediaEligibility {
  const PrivateMediaEligibility({
    required this.attachmentCount,
    required this.attachmentKind,
    this.hasTextOrCaption = false,
    this.isEdit = false,
    this.isForward = false,
  });

  final int attachmentCount;
  final PrivateMediaAttachmentKind attachmentKind;
  final bool hasTextOrCaption;
  final bool isEdit;
  final bool isForward;

  bool get allowsPrivateMedia {
    final allowedKind =
        attachmentKind == PrivateMediaAttachmentKind.image ||
        attachmentKind == PrivateMediaAttachmentKind.gif ||
        attachmentKind == PrivateMediaAttachmentKind.video;
    return attachmentCount == 1 &&
        allowedKind &&
        !hasTextOrCaption &&
        !isEdit &&
        !isForward;
  }

  bool get allowsNewPrivateMedia {
    final allowedKind =
        attachmentKind == PrivateMediaAttachmentKind.image ||
        attachmentKind == PrivateMediaAttachmentKind.video;
    return attachmentCount == 1 &&
        allowedKind &&
        !hasTextOrCaption &&
        !isEdit &&
        !isForward;
  }

  @override
  bool operator ==(Object other) =>
      other is PrivateMediaEligibility &&
      other.attachmentCount == attachmentCount &&
      other.attachmentKind == attachmentKind &&
      other.hasTextOrCaption == hasTextOrCaption &&
      other.isEdit == isEdit &&
      other.isForward == isForward;

  @override
  int get hashCode => Object.hash(
    attachmentCount,
    attachmentKind,
    hasTextOrCaption,
    isEdit,
    isForward,
  );
}

class PrivateMediaPolicy {
  const PrivateMediaPolicy._({
    required this.version,
    required this.mode,
    this.durationSeconds,
  });

  const PrivateMediaPolicy.ordinary()
    : version = 0,
      mode = PrivateMediaMode.ordinary,
      durationSeconds = null;

  const PrivateMediaPolicy.unsupported({int sourceVersion = 0})
    : version = sourceVersion,
      mode = PrivateMediaMode.unsupported,
      durationSeconds = null;

  const PrivateMediaPolicy.protected()
    : version = 1,
      mode = PrivateMediaMode.protected,
      durationSeconds = null;

  const PrivateMediaPolicy.viewOnce()
    : version = 1,
      mode = PrivateMediaMode.viewOnce,
      durationSeconds = null;

  factory PrivateMediaPolicy.disappearing(int durationSeconds) {
    if (!allowedDurationsSeconds.contains(durationSeconds)) {
      return const PrivateMediaPolicy.unsupported(sourceVersion: 1);
    }
    return PrivateMediaPolicy._(
      version: 1,
      mode: PrivateMediaMode.disappearing,
      durationSeconds: durationSeconds,
    );
  }

  static const allowedDurationsSeconds = <int>{3600, 86400, 604800};

  final int version;
  final PrivateMediaMode mode;
  final int? durationSeconds;

  factory PrivateMediaPolicy.fromJson(
    Object? raw, {
    PrivateMediaEligibility? eligibility,
  }) {
    if (raw == null) return const PrivateMediaPolicy.ordinary();
    if (raw is! Map) return const PrivateMediaPolicy.unsupported();

    final rawVersion = raw['version'];
    final sourceVersion = rawVersion is int && rawVersion >= 0 ? rawVersion : 0;
    if (rawVersion is! int || rawVersion != 1) {
      return PrivateMediaPolicy.unsupported(sourceVersion: sourceVersion);
    }

    final mode = PrivateMediaMode.fromWireValue(raw['mode']);
    if (mode == PrivateMediaMode.unsupported) {
      return const PrivateMediaPolicy.unsupported(sourceVersion: 1);
    }

    final rawDuration = raw['durationSeconds'];
    final int? duration;
    if (mode == PrivateMediaMode.disappearing) {
      if (rawDuration is! int ||
          !allowedDurationsSeconds.contains(rawDuration)) {
        return const PrivateMediaPolicy.unsupported(sourceVersion: 1);
      }
      duration = rawDuration;
    } else {
      if (rawDuration != null) {
        return const PrivateMediaPolicy.unsupported(sourceVersion: 1);
      }
      duration = null;
    }

    final parsed = PrivateMediaPolicy._(
      version: 1,
      mode: mode,
      durationSeconds: duration,
    );
    return eligibility == null ? parsed : parsed.validatedFor(eligibility);
  }

  /// Parses the constrained durable columns. Missing columns are a legacy
  /// ordinary row; unknown or internally inconsistent values fail closed.
  factory PrivateMediaPolicy.fromDatabase({
    required Object? version,
    required Object? mode,
    required Object? durationSeconds,
  }) {
    if (version == null && mode == null && durationSeconds == null) {
      return const PrivateMediaPolicy.ordinary();
    }
    final parsedVersion = version is num ? version.toInt() : 0;
    if (parsedVersion == 0 &&
        (mode == null || mode == PrivateMediaMode.ordinary.wireValue) &&
        durationSeconds == null) {
      return const PrivateMediaPolicy.ordinary();
    }
    if (mode == PrivateMediaMode.unsupported.wireValue) {
      return PrivateMediaPolicy.unsupported(
        sourceVersion: parsedVersion < 0 ? 0 : parsedVersion,
      );
    }
    final json = <String, Object?>{'version': parsedVersion, 'mode': mode};
    if (durationSeconds != null) {
      json['durationSeconds'] = durationSeconds;
    }
    return PrivateMediaPolicy.fromJson(json);
  }

  bool get isPrivate =>
      mode == PrivateMediaMode.protected ||
      mode == PrivateMediaMode.viewOnce ||
      mode == PrivateMediaMode.disappearing;

  bool get isUnsupported => mode == PrivateMediaMode.unsupported;

  bool get requiresRedaction => isPrivate || isUnsupported;

  bool allowsExplicitDownload(PrivateMediaLifecycleState state) {
    if (isUnsupported) return false;
    if (!isPrivate) return true;
    return state == PrivateMediaLifecycleState.available;
  }

  bool get allowsAutomaticDownload => !requiresRedaction;

  PrivateMediaLifecycleState get initialState {
    if (isUnsupported) return PrivateMediaLifecycleState.unsupported;
    if (isPrivate) return PrivateMediaLifecycleState.available;
    return PrivateMediaLifecycleState.none;
  }

  PrivateMediaPolicy validatedFor(PrivateMediaEligibility eligibility) {
    if (isUnsupported || !isPrivate) return this;
    if (eligibility.allowsPrivateMedia) return this;
    return PrivateMediaPolicy.unsupported(sourceVersion: version);
  }

  /// Returns the encrypted-inner representation. Legacy ordinary and
  /// unsupported local states are never emitted onto the wire.
  Map<String, Object?>? toJson() {
    if (version != 1 || isUnsupported) return null;
    final json = <String, Object?>{'version': version, 'mode': mode.wireValue};
    final duration = durationSeconds;
    if (duration != null) json['durationSeconds'] = duration;
    return json;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PrivateMediaPolicy &&
            other.version == version &&
            other.mode == mode &&
            other.durationSeconds == durationSeconds;
  }

  @override
  int get hashCode => Object.hash(version, mode, durationSeconds);

  @override
  String toString() =>
      'PrivateMediaPolicy(version: $version, mode: ${mode.wireValue}, '
      'durationSeconds: $durationSeconds)';
}

PrivateMediaPolicy normalizePrivateMediaComposerPolicy({
  required PrivateMediaPolicy selectedPolicy,
  required PrivateMediaEligibility eligibility,
  required bool eligibleAttachmentIdentityChanged,
}) {
  if (!selectedPolicy.isPrivate) return const PrivateMediaPolicy.ordinary();
  if (!isPrivateMediaComposerPolicyEligible(
        selectedPolicy: selectedPolicy,
        eligibility: eligibility,
      ) ||
      eligibleAttachmentIdentityChanged) {
    return const PrivateMediaPolicy.ordinary();
  }
  return selectedPolicy;
}

bool isPrivateMediaComposerPolicyEligible({
  required PrivateMediaPolicy selectedPolicy,
  required PrivateMediaEligibility eligibility,
}) {
  if (!selectedPolicy.isPrivate) return true;
  if (!eligibility.allowsNewPrivateMedia) return false;
  return selectedPolicy.mode != PrivateMediaMode.viewOnce ||
      eligibility.attachmentKind == PrivateMediaAttachmentKind.image;
}

/// Classifies one attachment's durable media identity for the private producer
/// matrix. GIF is deliberately separated from image even though both persist
/// `media_type = 'image'`.
///
/// The transport MIME and the persisted media type are two independent
/// descriptions of the same bytes, so they must AGREE. Reading whichever side
/// happened to match first would admit a crossed pair such as `video/mp4` plus
/// `media_type = 'image'` as an image, letting a View-Once video through the
/// image-only matrix. A disagreement is therefore unknown and fails closed.
PrivateMediaAttachmentKind privateMediaAttachmentKindForMediaIdentity({
  required String mime,
  required String mediaType,
}) {
  final fromMime = _privateMediaKindFromMime(mime.toLowerCase());
  final fromMediaType = _privateMediaKindFromMediaType(mediaType.toLowerCase());
  if (fromMime == fromMediaType) return fromMime;
  // The single intentional divergence: this app's own convention persists
  // `media_type = 'image'` for an animated GIF, and GIF must stay separable so
  // the producer matrix keeps refusing it.
  if (fromMime == PrivateMediaAttachmentKind.gif &&
      fromMediaType == PrivateMediaAttachmentKind.image) {
    return PrivateMediaAttachmentKind.gif;
  }
  return PrivateMediaAttachmentKind.unknown;
}

PrivateMediaAttachmentKind _privateMediaKindFromMime(String normalizedMime) {
  if (normalizedMime == 'image/gif') return PrivateMediaAttachmentKind.gif;
  if (normalizedMime.startsWith('image/')) {
    return PrivateMediaAttachmentKind.image;
  }
  if (normalizedMime.startsWith('video/')) {
    return PrivateMediaAttachmentKind.video;
  }
  if (normalizedMime.startsWith('audio/')) {
    return PrivateMediaAttachmentKind.audio;
  }
  if (normalizedMime.isNotEmpty) return PrivateMediaAttachmentKind.file;
  return PrivateMediaAttachmentKind.unknown;
}

PrivateMediaAttachmentKind _privateMediaKindFromMediaType(
  String normalizedMediaType,
) => switch (normalizedMediaType) {
  'gif' => PrivateMediaAttachmentKind.gif,
  'image' => PrivateMediaAttachmentKind.image,
  'video' => PrivateMediaAttachmentKind.video,
  'audio' => PrivateMediaAttachmentKind.audio,
  'file' => PrivateMediaAttachmentKind.file,
  _ => PrivateMediaAttachmentKind.unknown,
};

/// Exact producer matrix for one newly authored v1 private-media INITIAL.
///
/// v1 Protected permits exactly one image or one video; v1 View Once permits
/// exactly one image. GIF, audio, file, unknown, disappearing and every other
/// policy shape are refused before encryption, durable strict publication and
/// network. Sender and receiver both consult this one predicate so a redacted
/// envelope cannot widen the matrix.
bool privateMediaInitialProducerMatrixAllows({
  required int policyVersion,
  required PrivateMediaMode mode,
  required String mime,
  required String mediaType,
}) {
  if (policyVersion != 1) return false;
  if (mode != PrivateMediaMode.protected && mode != PrivateMediaMode.viewOnce) {
    return false;
  }
  final kind = privateMediaAttachmentKindForMediaIdentity(
    mime: mime,
    mediaType: mediaType,
  );
  if (mode == PrivateMediaMode.viewOnce) {
    return kind == PrivateMediaAttachmentKind.image;
  }
  return kind == PrivateMediaAttachmentKind.image ||
      kind == PrivateMediaAttachmentKind.video;
}

/// Row-shaped form of [privateMediaInitialProducerMatrixAllows] for durable
/// database predicates. Callers supply the persisted parent policy columns.
bool privateMediaInitialProducerMatrixAllowsDatabaseIdentity({
  required Object? policyVersion,
  required Object? mode,
  required Object? durationSeconds,
  required Object? mime,
  required Object? mediaType,
}) {
  if (durationSeconds != null) return false;
  if (mime is! String || mediaType is! String) return false;
  final version = policyVersion is num ? policyVersion.toInt() : -1;
  return privateMediaInitialProducerMatrixAllows(
    policyVersion: version,
    mode: PrivateMediaMode.fromWireValue(mode),
    mime: mime,
    mediaType: mediaType,
  );
}

/// Exact producer matrix for one newly authored v1 `disappearing` INITIAL.
///
/// 358: disappearing permits exactly one coherent image or video and exactly
/// one of the three allowed durations. It is deliberately a SEPARATE predicate
/// from [privateMediaInitialProducerMatrixAllows]: Protected/View-Once own the
/// no-v110 private generation lane, while disappearing adopts the token-bearing
/// ordinary owners. Widening either predicate into the other would move a
/// modality between two different custody owners.
///
/// GIF stays refused for new authoring even though it remains
/// compatibility-decodable, and audio/file/unknown are never eligible.
bool disappearingMediaInitialProducerMatrixAllows({
  required int policyVersion,
  required PrivateMediaMode mode,
  required int? durationSeconds,
  required String mime,
  required String mediaType,
}) {
  if (policyVersion != 1) return false;
  if (mode != PrivateMediaMode.disappearing) return false;
  if (durationSeconds == null ||
      !PrivateMediaPolicy.allowedDurationsSeconds.contains(durationSeconds)) {
    return false;
  }
  final kind = privateMediaAttachmentKindForMediaIdentity(
    mime: mime,
    mediaType: mediaType,
  );
  return kind == PrivateMediaAttachmentKind.image ||
      kind == PrivateMediaAttachmentKind.video;
}

/// Row-shaped form of [disappearingMediaInitialProducerMatrixAllows] for
/// durable database predicates.
bool disappearingMediaInitialProducerMatrixAllowsDatabaseIdentity({
  required Object? policyVersion,
  required Object? mode,
  required Object? durationSeconds,
  required Object? mime,
  required Object? mediaType,
}) {
  if (mime is! String || mediaType is! String) return false;
  final version = policyVersion is num ? policyVersion.toInt() : -1;
  final duration = durationSeconds is num ? durationSeconds.toInt() : null;
  if (durationSeconds != null && duration == null) return false;
  return disappearingMediaInitialProducerMatrixAllows(
    policyVersion: version,
    mode: PrivateMediaMode.fromWireValue(mode),
    durationSeconds: duration,
    mime: mime,
    mediaType: mediaType,
  );
}
