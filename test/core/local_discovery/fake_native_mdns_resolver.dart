import 'dart:async';

import 'package:flutter_app/core/local_discovery/native_mdns_resolver.dart';

/// Test fake for [NativeMdnsResolver]: drive resolved-peer events on command and
/// assert the start/stop lifecycle, without the native multicast socket. The
/// native Kotlin leg is covered only by the device-proof (TC-180-07).
class FakeNativeMdnsResolver implements NativeMdnsResolver {
  final _controller = StreamController<NativeResolvedPeer>.broadcast();

  int startCallCount = 0;
  int stopCallCount = 0;
  String? startedServiceType;

  @override
  Stream<NativeResolvedPeer> get resolvedPeers => _controller.stream;

  @override
  Future<void> start(String serviceType) async {
    startCallCount++;
    startedServiceType = serviceType;
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
  }

  /// Simulate the native resolver emitting a resolved peer.
  void emit(NativeResolvedPeer peer) => _controller.add(peer);

  void dispose() => _controller.close();
}
