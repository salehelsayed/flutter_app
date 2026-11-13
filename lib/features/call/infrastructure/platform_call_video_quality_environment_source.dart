import 'package:flutter/services.dart';

import '../domain/call_video_quality_environment.dart';

/// RED scaffold for U3j-QN: compiles against the API but observes nothing.
final class PlatformCallVideoQualityEnvironmentSource
    implements CallVideoQualityEnvironmentSource {
  PlatformCallVideoQualityEnvironmentSource({
    this.videoEnabled = false,
    EventChannel channel = const EventChannel(eventChannelName),
  });

  static const eventChannelName = 'mknoon/call_video_quality/events';

  final bool videoEnabled;

  @override
  CallVideoQualityEnvironment get current => CallVideoQualityEnvironment.unknown;

  @override
  Stream<CallVideoQualityEnvironment> get changes => const Stream.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> close() async {}

  static CallVideoQualityEnvironment parseSnapshot(Object? event) =>
      CallVideoQualityEnvironment.unknown;
}
