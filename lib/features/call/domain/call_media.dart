/// The wire version and requested media are fixed for the lifetime of a call.
enum CallWireVersion { v1, v2 }

enum CallMediaKind { audio, video }

enum CallCameraState { off, on, paused }

/// The initial agreement never grants permission to start camera capture.
final class CallMediaAgreement {
  const CallMediaAgreement._({
    required this.wireVersion,
    required this.requestedMedia,
    required this.acceptedMedia,
    required this.localCamera,
  });

  final CallWireVersion wireVersion;
  final CallMediaKind requestedMedia;
  final CallMediaKind acceptedMedia;
  final CallCameraState localCamera;
  int get mediaRevision => 0;

  factory CallMediaAgreement.initial({
    required CallWireVersion wireVersion,
    required CallMediaKind requestedMedia,
    required CallMediaKind acceptedMedia,
    bool videoEnabled = false,
    bool localCameraConsent = false,
    bool cameraPermissionGranted = false,
  }) {
    if (wireVersion == CallWireVersion.v2 && !videoEnabled) {
      throw const FormatException('call signal v2 is disabled');
    }
    if (wireVersion == CallWireVersion.v1 &&
        (requestedMedia != CallMediaKind.audio ||
            acceptedMedia != CallMediaKind.audio)) {
      throw const FormatException('v1 calls require audio');
    }
    if (requestedMedia == CallMediaKind.audio &&
        acceptedMedia == CallMediaKind.video) {
      throw const FormatException('audio invite cannot accept video');
    }
    return CallMediaAgreement._(
      wireVersion: wireVersion,
      requestedMedia: requestedMedia,
      acceptedMedia: acceptedMedia,
      localCamera:
          acceptedMedia == CallMediaKind.video &&
              localCameraConsent &&
              cameraPermissionGranted
          ? CallCameraState.on
          : CallCameraState.off,
    );
  }
}
