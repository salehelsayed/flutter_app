import 'package:flutter_app/features/call/infrastructure/call_video_sdp_summary.dart';
import 'package:flutter_test/flutter_test.dart';

const _offer =
    'v=0\r\n'
    'o=- 4611731400430051336 2 IN IP4 127.0.0.1\r\n'
    's=-\r\n'
    't=0 0\r\n'
    'a=group:BUNDLE 0 1\r\n'
    'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
    'c=IN IP4 0.0.0.0\r\n'
    'a=mid:0\r\n'
    'a=sendrecv\r\n'
    'a=msid:stream-a audio-track\r\n'
    'a=ssrc:111 cname:audio\r\n'
    'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
    'c=IN IP4 0.0.0.0\r\n'
    'a=mid:1\r\n'
    'a=sendrecv\r\n'
    'a=msid:stream-v video-track\r\n'
    'a=ssrc:222 cname:video\r\n';

void main() {
  test('DEFECT4 summary counts video sections, directions, msid and ssrc', () {
    expect(
      callVideoSdpSummary(_offer),
      'videoSections=1 rejectedVideo=0 directions=sendrecv '
      'hasVideoMsid=true hasVideoSsrc=true',
    );
  });

  test('DEFECT4 a rejected or receive-only video section is visible', () {
    const answer =
        'v=0\r\n'
        'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=sendrecv\r\n'
        'a=ssrc:111 cname:audio\r\n'
        'm=video 0 UDP/TLS/RTP/SAVPF 96\r\na=inactive\r\n'
        'm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=recvonly\r\n';
    expect(
      callVideoSdpSummary(answer),
      'videoSections=2 rejectedVideo=1 directions=inactive,recvonly '
      'hasVideoMsid=false hasVideoSsrc=false',
    );
  });

  test('DEFECT4 audio-only SDP has no video section and leaks nothing', () {
    const audioOnly =
        'v=0\r\no=- 1 2 IN IP4 10.0.0.7\r\n'
        'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=sendrecv\r\n';
    final summary = callVideoSdpSummary(audioOnly);
    expect(
      summary,
      'videoSections=0 rejectedVideo=0 directions=- '
      'hasVideoMsid=false hasVideoSsrc=false',
    );
    expect(summary, isNot(contains('IN IP4')));
    expect(callVideoSdpSummary(_offer), isNot(contains('video-track')));
  });
}
