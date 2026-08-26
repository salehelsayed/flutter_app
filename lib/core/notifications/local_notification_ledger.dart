import 'dart:convert';

const int localNotificationLedgerSchemaVersion = 1;
const int localNotificationLedgerMaxSignedInt64 = 0x7fffffffffffffff;
const int localNotificationLedgerMaxNotificationId = 0x7fffffff;
const int localNotificationLedgerMaxRecords = 512;

final RegExp _localNotificationLowercaseDigest = RegExp(r'^[0-9a-f]{64}$');
final RegExp _localNotificationOpaqueBinding = RegExp(r'^v1:[0-9a-f]{64}$');
final RegExp _localNotificationContentGeneration = RegExp(
  r'^[A-Za-z0-9._:-]{1,512}$',
);
final RegExp _canonicalUtc = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3}|\.\d{6})Z$',
);
const Object _notProvided = Object();

enum LocalNotificationProducerKind {
  directMessage('direct_message'),
  directReaction('direct_reaction'),
  groupMessage('group_message'),
  groupReaction('group_reaction');

  const LocalNotificationProducerKind(this.wireName);

  final String wireName;

  static LocalNotificationProducerKind? tryParse(Object? value) =>
      _enumByWireName(values, value, (candidate) => candidate.wireName);
}

enum LocalNotificationSourceCustody {
  sqlReady('SQL_READY'),
  relayVerifiedUnacked('RELAY_VERIFIED_UNACKED');

  const LocalNotificationSourceCustody(this.wireName);

  final String wireName;

  static LocalNotificationSourceCustody? tryParse(Object? value) =>
      _enumByWireName(values, value, (candidate) => candidate.wireName);
}

enum LocalNotificationReadState {
  unread('UNREAD'),
  read('READ');

  const LocalNotificationReadState(this.wireName);

  final String wireName;

  static LocalNotificationReadState? tryParse(Object? value) =>
      _enumByWireName(values, value, (candidate) => candidate.wireName);
}

enum LocalNotificationPresentationState {
  notEvaluated('NOT_EVALUATED'),
  inChat('IN_CHAT'),
  osPosted('OS_POSTED'),
  suppressedPolicy('SUPPRESSED_POLICY'),
  cancelled('CANCELLED');

  const LocalNotificationPresentationState(this.wireName);

  final String wireName;

  static LocalNotificationPresentationState? tryParse(Object? value) =>
      _enumByWireName(values, value, (candidate) => candidate.wireName);
}

enum LocalNotificationPresentationOwner {
  mainApp('MAIN_APP'),
  iosNse('IOS_NSE'),
  androidPushService('ANDROID_PUSH_SERVICE'),
  inboxReconciler('INBOX_RECONCILER');

  const LocalNotificationPresentationOwner(this.wireName);

  final String wireName;

  static LocalNotificationPresentationOwner? tryParse(Object? value) =>
      _enumByWireName(values, value, (candidate) => candidate.wireName);
}

enum LocalNotificationEvaluatedLifecycle {
  foregroundActive('FOREGROUND_ACTIVE'),
  inactive('INACTIVE'),
  background('BACKGROUND'),
  unknown('UNKNOWN');

  const LocalNotificationEvaluatedLifecycle(this.wireName);

  final String wireName;

  static LocalNotificationEvaluatedLifecycle? tryParse(Object? value) =>
      _enumByWireName(values, value, (candidate) => candidate.wireName);
}

enum LocalNotificationEffectPhase {
  ready('READY'),
  claimed('CLAIMED'),
  publishing('PUBLISHING'),
  effectTerminal('EFFECT_TERMINAL'),
  settled('SETTLED');

  const LocalNotificationEffectPhase(this.wireName);

  final String wireName;

  static LocalNotificationEffectPhase? tryParse(Object? value) =>
      _enumByWireName(values, value, (candidate) => candidate.wireName);
}

enum LocalNotificationAttemptKind {
  postOrUpdate('POST_OR_UPDATE'),
  adoptExistingRemote('ADOPT_EXISTING_REMOTE'),
  cancelLocalForRemoteAdoption('CANCEL_LOCAL_FOR_REMOTE_ADOPTION'),
  cancel('CANCEL');

  const LocalNotificationAttemptKind(this.wireName);

  final String wireName;

  static LocalNotificationAttemptKind? tryParse(Object? value) =>
      _enumByWireName(values, value, (candidate) => candidate.wireName);
}

/// Identifier-only v1 authority for one authenticated producer event.
final class LocalNotificationRecordV1 {
  const LocalNotificationRecordV1({
    required this.eventCorrelation,
    required this.conversationDigest,
    required this.producerKind,
    required this.sourceCustody,
    required this.readState,
    required this.presentationState,
    required this.presentationOwner,
    required this.notificationId,
    required this.contentGeneration,
    required this.lastEvaluatedLifecycle,
    required this.visibilityRevision,
    required this.lifecycleGeneration,
    required this.effectPhase,
    required this.attemptKind,
    required this.effectToken,
    required this.revision,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.terminalAtUtc,
    required this.settledAtUtc,
  });

  static const Set<String> _keys = <String>{
    'eventCorrelation',
    'conversationDigest',
    'producerKind',
    'sourceCustody',
    'readState',
    'presentationState',
    'presentationOwner',
    'notificationId',
    'contentGeneration',
    'lastEvaluatedLifecycle',
    'visibilityRevision',
    'lifecycleGeneration',
    'effectPhase',
    'attemptKind',
    'effectToken',
    'revision',
    'createdAtUtc',
    'updatedAtUtc',
    'terminalAtUtc',
    'settledAtUtc',
  };

  final String eventCorrelation;
  final String conversationDigest;
  final LocalNotificationProducerKind producerKind;
  final LocalNotificationSourceCustody sourceCustody;
  final LocalNotificationReadState readState;
  final LocalNotificationPresentationState presentationState;
  final LocalNotificationPresentationOwner presentationOwner;
  final int? notificationId;
  final String? contentGeneration;
  final LocalNotificationEvaluatedLifecycle lastEvaluatedLifecycle;
  final int? visibilityRevision;
  final int? lifecycleGeneration;
  final LocalNotificationEffectPhase effectPhase;
  final LocalNotificationAttemptKind? attemptKind;
  final String? effectToken;
  final int revision;
  final String createdAtUtc;
  final String updatedAtUtc;
  final String? terminalAtUtc;
  final String? settledAtUtc;

  bool get isValid {
    if (!_isDigest(eventCorrelation) ||
        !_isDigest(conversationDigest) ||
        !_isPositiveInt64(revision) ||
        !_isNullablePositiveInt64(visibilityRevision) ||
        !_isNullablePositiveInt64(lifecycleGeneration) ||
        !_isNotificationId(notificationId) ||
        !_isContentGeneration(contentGeneration) ||
        !_isCanonicalUtc(createdAtUtc) ||
        !_isCanonicalUtc(updatedAtUtc) ||
        _utc(updatedAtUtc)!.isBefore(_utc(createdAtUtc)!)) {
      return false;
    }

    final attemptRequired =
        effectPhase == LocalNotificationEffectPhase.claimed ||
        effectPhase == LocalNotificationEffectPhase.publishing;
    if (attemptRequired != (attemptKind != null) ||
        attemptRequired != (effectToken != null) ||
        (effectToken != null && !_isDigest(effectToken!))) {
      return false;
    }

    switch (effectPhase) {
      case LocalNotificationEffectPhase.ready:
      case LocalNotificationEffectPhase.claimed:
      case LocalNotificationEffectPhase.publishing:
        if (terminalAtUtc != null || settledAtUtc != null) return false;
      case LocalNotificationEffectPhase.effectTerminal:
        if (!_validTerminalTimestamp() || settledAtUtc != null) return false;
      case LocalNotificationEffectPhase.settled:
        if (!_validTerminalTimestamp() ||
            !_isCanonicalUtc(settledAtUtc) ||
            _utc(settledAtUtc!)!.isBefore(_utc(terminalAtUtc!)!) ||
            _utc(settledAtUtc!)!.isAfter(_utc(updatedAtUtc)!)) {
          return false;
        }
    }
    if ((effectPhase == LocalNotificationEffectPhase.effectTerminal ||
            effectPhase == LocalNotificationEffectPhase.settled) &&
        presentationState == LocalNotificationPresentationState.notEvaluated) {
      return false;
    }
    if (sourceCustody == LocalNotificationSourceCustody.relayVerifiedUnacked &&
        effectPhase == LocalNotificationEffectPhase.settled) {
      return false;
    }
    return true;
  }

  bool _validTerminalTimestamp() =>
      _isCanonicalUtc(terminalAtUtc) &&
      !_utc(terminalAtUtc!)!.isBefore(_utc(createdAtUtc)!) &&
      !_utc(terminalAtUtc!)!.isAfter(_utc(updatedAtUtc)!);

  static LocalNotificationRecordV1? tryFromJson(Object? value) {
    final map = _exactStringMap(value, _keys);
    if (map == null) return null;
    final producerKind = LocalNotificationProducerKind.tryParse(
      map['producerKind'],
    );
    final sourceCustody = LocalNotificationSourceCustody.tryParse(
      map['sourceCustody'],
    );
    final readState = LocalNotificationReadState.tryParse(map['readState']);
    final presentationState = LocalNotificationPresentationState.tryParse(
      map['presentationState'],
    );
    final presentationOwner = LocalNotificationPresentationOwner.tryParse(
      map['presentationOwner'],
    );
    final lifecycle = LocalNotificationEvaluatedLifecycle.tryParse(
      map['lastEvaluatedLifecycle'],
    );
    final effectPhase = LocalNotificationEffectPhase.tryParse(
      map['effectPhase'],
    );
    final rawAttemptKind = map['attemptKind'];
    final attemptKind = rawAttemptKind == null
        ? null
        : LocalNotificationAttemptKind.tryParse(rawAttemptKind);
    if (map['eventCorrelation'] is! String ||
        map['conversationDigest'] is! String ||
        producerKind == null ||
        sourceCustody == null ||
        readState == null ||
        presentationState == null ||
        presentationOwner == null ||
        (map['notificationId'] != null && map['notificationId'] is! int) ||
        (map['contentGeneration'] != null &&
            map['contentGeneration'] is! String) ||
        lifecycle == null ||
        (map['visibilityRevision'] != null &&
            map['visibilityRevision'] is! int) ||
        (map['lifecycleGeneration'] != null &&
            map['lifecycleGeneration'] is! int) ||
        effectPhase == null ||
        (rawAttemptKind != null && attemptKind == null) ||
        (map['effectToken'] != null && map['effectToken'] is! String) ||
        map['revision'] is! int ||
        map['createdAtUtc'] is! String ||
        map['updatedAtUtc'] is! String ||
        (map['terminalAtUtc'] != null && map['terminalAtUtc'] is! String) ||
        (map['settledAtUtc'] != null && map['settledAtUtc'] is! String)) {
      return null;
    }
    final record = LocalNotificationRecordV1(
      eventCorrelation: map['eventCorrelation']! as String,
      conversationDigest: map['conversationDigest']! as String,
      producerKind: producerKind,
      sourceCustody: sourceCustody,
      readState: readState,
      presentationState: presentationState,
      presentationOwner: presentationOwner,
      notificationId: map['notificationId'] as int?,
      contentGeneration: map['contentGeneration'] as String?,
      lastEvaluatedLifecycle: lifecycle,
      visibilityRevision: map['visibilityRevision'] as int?,
      lifecycleGeneration: map['lifecycleGeneration'] as int?,
      effectPhase: effectPhase,
      attemptKind: attemptKind,
      effectToken: map['effectToken'] as String?,
      revision: map['revision']! as int,
      createdAtUtc: map['createdAtUtc']! as String,
      updatedAtUtc: map['updatedAtUtc']! as String,
      terminalAtUtc: map['terminalAtUtc'] as String?,
      settledAtUtc: map['settledAtUtc'] as String?,
    );
    return record.isValid ? record : null;
  }

  LocalNotificationRecordV1 copyWith({
    String? eventCorrelation,
    String? conversationDigest,
    LocalNotificationProducerKind? producerKind,
    LocalNotificationSourceCustody? sourceCustody,
    LocalNotificationReadState? readState,
    LocalNotificationPresentationState? presentationState,
    LocalNotificationPresentationOwner? presentationOwner,
    Object? notificationId = _notProvided,
    Object? contentGeneration = _notProvided,
    LocalNotificationEvaluatedLifecycle? lastEvaluatedLifecycle,
    Object? visibilityRevision = _notProvided,
    Object? lifecycleGeneration = _notProvided,
    LocalNotificationEffectPhase? effectPhase,
    Object? attemptKind = _notProvided,
    Object? effectToken = _notProvided,
    int? revision,
    String? createdAtUtc,
    String? updatedAtUtc,
    Object? terminalAtUtc = _notProvided,
    Object? settledAtUtc = _notProvided,
  }) {
    return LocalNotificationRecordV1(
      eventCorrelation: eventCorrelation ?? this.eventCorrelation,
      conversationDigest: conversationDigest ?? this.conversationDigest,
      producerKind: producerKind ?? this.producerKind,
      sourceCustody: sourceCustody ?? this.sourceCustody,
      readState: readState ?? this.readState,
      presentationState: presentationState ?? this.presentationState,
      presentationOwner: presentationOwner ?? this.presentationOwner,
      notificationId: identical(notificationId, _notProvided)
          ? this.notificationId
          : notificationId as int?,
      contentGeneration: identical(contentGeneration, _notProvided)
          ? this.contentGeneration
          : contentGeneration as String?,
      lastEvaluatedLifecycle:
          lastEvaluatedLifecycle ?? this.lastEvaluatedLifecycle,
      visibilityRevision: identical(visibilityRevision, _notProvided)
          ? this.visibilityRevision
          : visibilityRevision as int?,
      lifecycleGeneration: identical(lifecycleGeneration, _notProvided)
          ? this.lifecycleGeneration
          : lifecycleGeneration as int?,
      effectPhase: effectPhase ?? this.effectPhase,
      attemptKind: identical(attemptKind, _notProvided)
          ? this.attemptKind
          : attemptKind as LocalNotificationAttemptKind?,
      effectToken: identical(effectToken, _notProvided)
          ? this.effectToken
          : effectToken as String?,
      revision: revision ?? this.revision,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      terminalAtUtc: identical(terminalAtUtc, _notProvided)
          ? this.terminalAtUtc
          : terminalAtUtc as String?,
      settledAtUtc: identical(settledAtUtc, _notProvided)
          ? this.settledAtUtc
          : settledAtUtc as String?,
    );
  }

  Map<String, Object?> toJson() {
    if (!isValid) {
      throw const FormatException('invalid local notification record v1');
    }
    return <String, Object?>{
      'eventCorrelation': eventCorrelation,
      'conversationDigest': conversationDigest,
      'producerKind': producerKind.wireName,
      'sourceCustody': sourceCustody.wireName,
      'readState': readState.wireName,
      'presentationState': presentationState.wireName,
      'presentationOwner': presentationOwner.wireName,
      'notificationId': notificationId,
      'contentGeneration': contentGeneration,
      'lastEvaluatedLifecycle': lastEvaluatedLifecycle.wireName,
      'visibilityRevision': visibilityRevision,
      'lifecycleGeneration': lifecycleGeneration,
      'effectPhase': effectPhase.wireName,
      'attemptKind': attemptKind?.wireName,
      'effectToken': effectToken,
      'revision': revision,
      'createdAtUtc': createdAtUtc,
      'updatedAtUtc': updatedAtUtc,
      'terminalAtUtc': terminalAtUtc,
      'settledAtUtc': settledAtUtc,
    };
  }
}

final class LocalNotificationLedgerEnvelopeV1 {
  const LocalNotificationLedgerEnvelopeV1({
    required this.storeRevision,
    required this.opaqueBinding,
    required this.claimsSuspended,
    required this.records,
  });

  static const int schemaVersion = localNotificationLedgerSchemaVersion;
  static const Set<String> _keys = <String>{
    'schemaVersion',
    'storeRevision',
    'opaqueBinding',
    'claimsSuspended',
    'records',
  };

  final int storeRevision;
  final String opaqueBinding;
  final bool claimsSuspended;
  final Map<String, LocalNotificationRecordV1> records;

  bool get isValid {
    if (!_isPositiveInt64(storeRevision) ||
        !_localNotificationOpaqueBinding.hasMatch(opaqueBinding) ||
        records.length > localNotificationLedgerMaxRecords) {
      return false;
    }
    for (final entry in records.entries) {
      if (!_isDigest(entry.key) ||
          entry.key != entry.value.eventCorrelation ||
          !entry.value.isValid) {
        return false;
      }
    }
    return true;
  }

  static LocalNotificationLedgerEnvelopeV1? tryFromJson(Object? value) {
    final map = _exactStringMap(value, _keys);
    if (map == null ||
        map['schemaVersion'] != schemaVersion ||
        map['storeRevision'] is! int ||
        map['opaqueBinding'] is! String ||
        map['claimsSuspended'] is! bool ||
        map['records'] is! Map) {
      return null;
    }
    final rawRecords = map['records']! as Map;
    if (rawRecords.length > localNotificationLedgerMaxRecords) return null;
    final records = <String, LocalNotificationRecordV1>{};
    for (final entry in rawRecords.entries) {
      if (entry.key is! String) return null;
      final record = LocalNotificationRecordV1.tryFromJson(entry.value);
      if (record == null || record.eventCorrelation != entry.key) return null;
      records[entry.key! as String] = record;
    }
    final envelope = LocalNotificationLedgerEnvelopeV1(
      storeRevision: map['storeRevision']! as int,
      opaqueBinding: map['opaqueBinding']! as String,
      claimsSuspended: map['claimsSuspended']! as bool,
      records: Map<String, LocalNotificationRecordV1>.unmodifiable(records),
    );
    return envelope.isValid ? envelope : null;
  }

  LocalNotificationLedgerEnvelopeV1 copyWith({
    int? storeRevision,
    String? opaqueBinding,
    bool? claimsSuspended,
    Map<String, LocalNotificationRecordV1>? records,
  }) {
    return LocalNotificationLedgerEnvelopeV1(
      storeRevision: storeRevision ?? this.storeRevision,
      opaqueBinding: opaqueBinding ?? this.opaqueBinding,
      claimsSuspended: claimsSuspended ?? this.claimsSuspended,
      records: Map<String, LocalNotificationRecordV1>.unmodifiable(
        records ?? this.records,
      ),
    );
  }

  Map<String, Object?> toJson() {
    if (!isValid) {
      throw const FormatException('invalid local notification ledger v1');
    }
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'storeRevision': storeRevision,
      'opaqueBinding': opaqueBinding,
      'claimsSuspended': claimsSuspended,
      'records': records.map(
        (key, value) => MapEntry<String, Object?>(key, value.toJson()),
      ),
    };
  }
}

/// Exact-known-key codec shared by Dart and downstream native adapters.
abstract final class LocalNotificationLedgerCodecV1 {
  static LocalNotificationLedgerEnvelopeV1? tryDecode(String encoded) {
    try {
      return tryDecodePlatform(jsonDecode(encoded));
    } on Object {
      return null;
    }
  }

  static LocalNotificationLedgerEnvelopeV1? tryDecodePlatform(Object? value) =>
      LocalNotificationLedgerEnvelopeV1.tryFromJson(value);

  static String encode(LocalNotificationLedgerEnvelopeV1 envelope) =>
      jsonEncode(envelope.toJson());
}

/// Pure revisioned state machine. Returning null grants no effect authority.
abstract final class LocalNotificationLedgerStateMachineV1 {
  static LocalNotificationRecordV1? tryTransition({
    required LocalNotificationRecordV1 current,
    required int expectedRevision,
    required LocalNotificationRecordV1 next,
  }) {
    if (!current.isValid ||
        !next.isValid ||
        current.revision != expectedRevision ||
        !_isPositiveInt64(expectedRevision) ||
        expectedRevision == localNotificationLedgerMaxSignedInt64 ||
        next.revision != expectedRevision + 1 ||
        current.eventCorrelation != next.eventCorrelation ||
        current.conversationDigest != next.conversationDigest ||
        current.producerKind != next.producerKind ||
        (current.presentationOwner != next.presentationOwner &&
            !_isEstablishedRemoteOwnerTransfer(current, next)) ||
        current.notificationId != next.notificationId ||
        current.contentGeneration != next.contentGeneration ||
        current.createdAtUtc != next.createdAtUtc ||
        (current.readState == LocalNotificationReadState.read &&
            next.readState != LocalNotificationReadState.read) ||
        _utc(next.updatedAtUtc)!.isBefore(_utc(current.updatedAtUtc)!)) {
      return null;
    }

    if (current.sourceCustody != next.sourceCustody) {
      if (current.sourceCustody !=
              LocalNotificationSourceCustody.relayVerifiedUnacked ||
          next.sourceCustody != LocalNotificationSourceCustody.sqlReady ||
          !_isPhasePreservingCustodyUpgrade(current, next)) {
        return null;
      }
      return next;
    }

    final currentPhase = current.effectPhase.index;
    final nextPhase = next.effectPhase.index;
    if (nextPhase < currentPhase || nextPhase > currentPhase + 1) return null;
    if (next.effectPhase.index <=
            LocalNotificationEffectPhase.publishing.index &&
        current.presentationState != next.presentationState) {
      return null;
    }
    if (current.effectPhase == LocalNotificationEffectPhase.claimed &&
        next.effectPhase == LocalNotificationEffectPhase.publishing &&
        (current.attemptKind != next.attemptKind ||
            current.effectToken != next.effectToken)) {
      return null;
    }
    if (current.effectPhase == LocalNotificationEffectPhase.claimed &&
        next.effectPhase == LocalNotificationEffectPhase.claimed &&
        current.effectToken != next.effectToken) {
      return null;
    }
    if (current.effectPhase == LocalNotificationEffectPhase.claimed &&
        next.effectPhase == LocalNotificationEffectPhase.claimed &&
        current.attemptKind != next.attemptKind &&
        !(current.attemptKind == LocalNotificationAttemptKind.postOrUpdate &&
            next.attemptKind ==
                LocalNotificationAttemptKind.adoptExistingRemote)) {
      return null;
    }
    if (current.effectPhase == LocalNotificationEffectPhase.publishing &&
        next.effectPhase == LocalNotificationEffectPhase.effectTerminal &&
        (current.notificationId != next.notificationId ||
            current.contentGeneration != next.contentGeneration)) {
      return null;
    }
    if ((current.effectPhase == LocalNotificationEffectPhase.effectTerminal ||
            current.effectPhase == LocalNotificationEffectPhase.settled) &&
        next.effectPhase == current.effectPhase &&
        (!_preservesTerminalEffect(current, next) ||
            (current.effectPhase == LocalNotificationEffectPhase.settled &&
                current.settledAtUtc != next.settledAtUtc))) {
      return null;
    }
    if (current.effectPhase == LocalNotificationEffectPhase.publishing &&
        next.effectPhase == LocalNotificationEffectPhase.publishing &&
        (current.notificationId != next.notificationId ||
            current.contentGeneration != next.contentGeneration)) {
      return null;
    }
    if (current.effectPhase == LocalNotificationEffectPhase.publishing &&
        next.effectPhase == LocalNotificationEffectPhase.publishing) {
      final preservesAttempt =
          current.attemptKind == next.attemptKind &&
          current.effectToken == next.effectToken;
      final reconcilesEstablishedRemote =
          current.attemptKind == LocalNotificationAttemptKind.postOrUpdate &&
          next.attemptKind ==
              LocalNotificationAttemptKind.cancelLocalForRemoteAdoption &&
          next.effectToken == current.effectToken;
      final armsExactCancel =
          current.attemptKind == LocalNotificationAttemptKind.postOrUpdate &&
          next.attemptKind == LocalNotificationAttemptKind.cancel &&
          next.effectToken == current.effectToken;
      final resumesPostAfterActivation =
          current.attemptKind == LocalNotificationAttemptKind.cancel &&
          next.attemptKind == LocalNotificationAttemptKind.postOrUpdate &&
          next.effectToken == current.effectToken;
      if (!preservesAttempt &&
          !reconcilesEstablishedRemote &&
          !armsExactCancel &&
          !resumesPostAfterActivation) {
        return null;
      }
    }
    if (current.effectPhase == LocalNotificationEffectPhase.effectTerminal &&
        next.effectPhase == LocalNotificationEffectPhase.settled &&
        !_preservesTerminalEffect(current, next)) {
      return null;
    }
    return next;
  }
}

bool _isEstablishedRemoteOwnerTransfer(
  LocalNotificationRecordV1 current,
  LocalNotificationRecordV1 next,
) {
  if (current.producerKind != LocalNotificationProducerKind.groupMessage ||
      next.presentationOwner != LocalNotificationPresentationOwner.iosNse ||
      current.sourceCustody != next.sourceCustody) {
    return false;
  }
  final sameToken = current.effectToken == next.effectToken;
  final adoptsBeforePublication =
      ((current.effectPhase == LocalNotificationEffectPhase.ready &&
              current.attemptKind == null &&
              next.effectPhase == LocalNotificationEffectPhase.claimed) ||
          (current.effectPhase == LocalNotificationEffectPhase.claimed &&
              current.attemptKind ==
                  LocalNotificationAttemptKind.postOrUpdate &&
              next.effectPhase == LocalNotificationEffectPhase.claimed &&
              sameToken)) &&
      next.attemptKind == LocalNotificationAttemptKind.adoptExistingRemote;
  final reconcilesAmbiguousPublication =
      current.effectPhase == LocalNotificationEffectPhase.publishing &&
      current.attemptKind == LocalNotificationAttemptKind.postOrUpdate &&
      next.effectPhase == LocalNotificationEffectPhase.publishing &&
      next.attemptKind ==
          LocalNotificationAttemptKind.cancelLocalForRemoteAdoption &&
      sameToken;
  return adoptsBeforePublication || reconcilesAmbiguousPublication;
}

bool _isPhasePreservingCustodyUpgrade(
  LocalNotificationRecordV1 current,
  LocalNotificationRecordV1 next,
) {
  final currentJson = current.toJson()
    ..remove('sourceCustody')
    ..remove('revision')
    ..remove('updatedAtUtc');
  final nextJson = next.toJson()
    ..remove('sourceCustody')
    ..remove('revision')
    ..remove('updatedAtUtc');
  return jsonEncode(currentJson) == jsonEncode(nextJson);
}

bool _preservesTerminalEffect(
  LocalNotificationRecordV1 current,
  LocalNotificationRecordV1 next,
) =>
    current.presentationState == next.presentationState &&
    current.notificationId == next.notificationId &&
    current.contentGeneration == next.contentGeneration &&
    current.lastEvaluatedLifecycle == next.lastEvaluatedLifecycle &&
    current.visibilityRevision == next.visibilityRevision &&
    current.lifecycleGeneration == next.lifecycleGeneration &&
    current.terminalAtUtc == next.terminalAtUtc;

Map<String, Object?>? _exactStringMap(Object? value, Set<String> keys) {
  if (value is! Map || value.length != keys.length) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String || !keys.contains(entry.key)) return null;
    result[entry.key! as String] = entry.value;
  }
  return result;
}

T? _enumByWireName<T>(
  Iterable<T> values,
  Object? value,
  String Function(T candidate) wireName,
) {
  if (value is! String) return null;
  for (final candidate in values) {
    if (wireName(candidate) == value) return candidate;
  }
  return null;
}

bool _isDigest(String value) =>
    _localNotificationLowercaseDigest.hasMatch(value);

bool _isPositiveInt64(Object? value) =>
    value is int && value > 0 && value <= localNotificationLedgerMaxSignedInt64;

bool _isNullablePositiveInt64(int? value) =>
    value == null || _isPositiveInt64(value);

bool _isNotificationId(int? value) =>
    value == null ||
    (value >= 0 && value <= localNotificationLedgerMaxNotificationId);

bool _isContentGeneration(String? value) =>
    value == null || _localNotificationContentGeneration.hasMatch(value);

bool _isCanonicalUtc(Object? value) {
  if (value is! String || !_canonicalUtc.hasMatch(value)) return false;
  final parsed = _utc(value);
  return parsed != null && parsed.toIso8601String() == value;
}

DateTime? _utc(String value) {
  final parsed = DateTime.tryParse(value);
  return parsed != null && parsed.isUtc ? parsed : null;
}
