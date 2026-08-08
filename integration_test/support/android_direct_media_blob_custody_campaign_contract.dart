import 'dart:io';

/// Inputs owned by the host campaign. Build and fixture ownership remain
/// outside the in-app device action.
final class AndroidDirectMediaBlobCustodyCampaignContext {
  const AndroidDirectMediaBlobCustodyCampaignContext({
    required this.physicalDeviceId,
    required this.emulatorDeviceId,
    required this.artifact,
    required this.artifactSha256,
    required this.relayMultiaddr,
    required this.fixtureProbeUrl,
    required this.fixtureIdentitySha256,
  });

  final String physicalDeviceId;
  final String emulatorDeviceId;
  final File artifact;
  final String artifactSha256;
  final String relayMultiaddr;
  final String fixtureProbeUrl;
  final String fixtureIdentitySha256;
}

typedef AndroidDirectMediaBlobCustodyDeviceDriver =
    Future<Map<String, Object?>> Function(
      AndroidDirectMediaBlobCustodyCampaignContext context,
    );

/// A typed prerequisite outcome from the concrete or injected device driver.
final class AndroidDirectMediaBlobCustodyCampaignBlocked implements Exception {
  const AndroidDirectMediaBlobCustodyCampaignBlocked(this.blocker, this.detail);

  final String blocker;
  final String detail;
}
