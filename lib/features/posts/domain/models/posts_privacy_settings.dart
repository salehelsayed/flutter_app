enum PostsLocationPermissionState { unknown, denied, deniedForever, granted }

class PostsPrivacySettings {
  static const int singletonRowId = 1;

  final bool sharingEnabled;
  final PostsLocationPermissionState permissionState;
  final int? lastLocalLatE3;
  final int? lastLocalLngE3;
  final String? lastLocalCapturedAt;
  final double? lastLocalAccuracyM;
  final String? lastRefreshAttemptAt;

  const PostsPrivacySettings({
    this.sharingEnabled = false,
    this.permissionState = PostsLocationPermissionState.unknown,
    this.lastLocalLatE3,
    this.lastLocalLngE3,
    this.lastLocalCapturedAt,
    this.lastLocalAccuracyM,
    this.lastRefreshAttemptAt,
  });

  factory PostsPrivacySettings.fromMap(Map<String, Object?> row) {
    return PostsPrivacySettings(
      sharingEnabled: (row['sharing_enabled'] as int? ?? 0) != 0,
      permissionState: PostsLocationPermissionStateWireValue.fromWireValue(
        row['permission_state'] as String?,
      ),
      lastLocalLatE3: row['last_local_lat_e3'] as int?,
      lastLocalLngE3: row['last_local_lng_e3'] as int?,
      lastLocalCapturedAt: row['last_local_captured_at'] as String?,
      lastLocalAccuracyM: (row['last_local_accuracy_m'] as num?)?.toDouble(),
      lastRefreshAttemptAt: row['last_refresh_attempt_at'] as String?,
    );
  }

  PostsPrivacySettings copyWith({
    bool? sharingEnabled,
    PostsLocationPermissionState? permissionState,
    int? lastLocalLatE3,
    int? lastLocalLngE3,
    String? lastLocalCapturedAt,
    double? lastLocalAccuracyM,
    String? lastRefreshAttemptAt,
    bool clearSnapshot = false,
  }) {
    return PostsPrivacySettings(
      sharingEnabled: sharingEnabled ?? this.sharingEnabled,
      permissionState: permissionState ?? this.permissionState,
      lastLocalLatE3: clearSnapshot
          ? null
          : (lastLocalLatE3 ?? this.lastLocalLatE3),
      lastLocalLngE3: clearSnapshot
          ? null
          : (lastLocalLngE3 ?? this.lastLocalLngE3),
      lastLocalCapturedAt: clearSnapshot
          ? null
          : (lastLocalCapturedAt ?? this.lastLocalCapturedAt),
      lastLocalAccuracyM: clearSnapshot
          ? null
          : (lastLocalAccuracyM ?? this.lastLocalAccuracyM),
      lastRefreshAttemptAt: lastRefreshAttemptAt ?? this.lastRefreshAttemptAt,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': singletonRowId,
      'sharing_enabled': sharingEnabled ? 1 : 0,
      'permission_state': permissionState.toWireValue(),
      'last_local_lat_e3': lastLocalLatE3,
      'last_local_lng_e3': lastLocalLngE3,
      'last_local_captured_at': lastLocalCapturedAt,
      'last_local_accuracy_m': lastLocalAccuracyM,
      'last_refresh_attempt_at': lastRefreshAttemptAt,
    };
  }

  bool hasFreshSnapshotAt(DateTime now, {required Duration ttl}) {
    final capturedAt = DateTime.tryParse(lastLocalCapturedAt ?? '')?.toUtc();
    if (capturedAt == null || lastLocalLatE3 == null || lastLocalLngE3 == null) {
      return false;
    }
    return now.toUtc().difference(capturedAt) <= ttl;
  }
}

extension PostsLocationPermissionStateWireValue
    on PostsLocationPermissionState {
  String toWireValue() {
    return switch (this) {
      PostsLocationPermissionState.unknown => 'unknown',
      PostsLocationPermissionState.denied => 'denied',
      PostsLocationPermissionState.deniedForever => 'denied_forever',
      PostsLocationPermissionState.granted => 'granted',
    };
  }

  static PostsLocationPermissionState fromWireValue(String? value) {
    return switch (value) {
      'denied' => PostsLocationPermissionState.denied,
      'denied_forever' => PostsLocationPermissionState.deniedForever,
      'granted' => PostsLocationPermissionState.granted,
      _ => PostsLocationPermissionState.unknown,
    };
  }
}
