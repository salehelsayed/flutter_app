import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BL16-U1 initial media agreement', () {
    test('v1 remains audio with the video gate off', () {
      final agreement = CallMediaAgreement.initial(
        wireVersion: CallWireVersion.v1,
        requestedMedia: CallMediaKind.audio,
        acceptedMedia: CallMediaKind.audio,
        localCameraConsent: true,
        cameraPermissionGranted: true,
      );
      expect(agreement.wireVersion, CallWireVersion.v1);
      expect(agreement.requestedMedia, CallMediaKind.audio);
      expect(agreement.acceptedMedia, CallMediaKind.audio);
      expect(agreement.localCamera, CallCameraState.off);
      expect(agreement.mediaRevision, 0);
    });

    test('v2 is disabled unless explicitly enabled', () {
      expect(
        () => CallMediaAgreement.initial(
          wireVersion: CallWireVersion.v2,
          requestedMedia: CallMediaKind.audio,
          acceptedMedia: CallMediaKind.audio,
        ),
        throwsFormatException,
      );
    });

    test('the v1 contract cannot carry video even with the gate on', () {
      for (final requested in CallMediaKind.values) {
        for (final accepted in CallMediaKind.values) {
          if (requested == CallMediaKind.audio &&
              accepted == CallMediaKind.audio) {
            continue;
          }
          expect(
            () => CallMediaAgreement.initial(
              wireVersion: CallWireVersion.v1,
              requestedMedia: requested,
              acceptedMedia: accepted,
              videoEnabled: true,
            ),
            throwsFormatException,
          );
        }
      }
    });

    test('audio-only answer preserves the video request as history', () {
      final agreement = CallMediaAgreement.initial(
        wireVersion: CallWireVersion.v2,
        requestedMedia: CallMediaKind.video,
        acceptedMedia: CallMediaKind.audio,
        videoEnabled: true,
        localCameraConsent: true,
        cameraPermissionGranted: true,
      );
      expect(agreement.wireVersion, CallWireVersion.v2);
      expect(agreement.requestedMedia, CallMediaKind.video);
      expect(agreement.acceptedMedia, CallMediaKind.audio);
      expect(agreement.localCamera, CallCameraState.off);
      expect(agreement.mediaRevision, 0);
    });

    test('an audio invite cannot be accepted as video', () {
      expect(
        () => CallMediaAgreement.initial(
          wireVersion: CallWireVersion.v2,
          requestedMedia: CallMediaKind.audio,
          acceptedMedia: CallMediaKind.video,
          videoEnabled: true,
          localCameraConsent: true,
          cameraPermissionGranted: true,
        ),
        throwsFormatException,
      );
    });

    for (final consent in [false, true]) {
      for (final permission in [false, true]) {
        test('video camera consent=$consent permission=$permission', () {
          final agreement = CallMediaAgreement.initial(
            wireVersion: CallWireVersion.v2,
            requestedMedia: CallMediaKind.video,
            acceptedMedia: CallMediaKind.video,
            videoEnabled: true,
            localCameraConsent: consent,
            cameraPermissionGranted: permission,
          );
          // Denial does not end the call or silently change the agreement.
          expect(agreement.requestedMedia, CallMediaKind.video);
          expect(agreement.acceptedMedia, CallMediaKind.video);
          expect(
            agreement.localCamera,
            consent && permission ? CallCameraState.on : CallCameraState.off,
          );
          expect(agreement.mediaRevision, 0);
        });
      }
    }

    test('explicit v2 audio remains audio without camera consent', () {
      final agreement = CallMediaAgreement.initial(
        wireVersion: CallWireVersion.v2,
        requestedMedia: CallMediaKind.audio,
        acceptedMedia: CallMediaKind.audio,
        videoEnabled: true,
      );
      expect(agreement.acceptedMedia, CallMediaKind.audio);
      expect(agreement.localCamera, CallCameraState.off);
    });
  });
}
