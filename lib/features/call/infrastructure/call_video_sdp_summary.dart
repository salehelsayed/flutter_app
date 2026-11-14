/// CAM-DIAG (defect 4): fixed-field summary of the video m-sections in an SDP
/// string the session already holds. Never returns raw SDP, ids or addresses:
/// only counts, direction words and two presence flags.
String callVideoSdpSummary(String sdp) {
  var sections = 0;
  var rejected = 0;
  var msid = false;
  var ssrc = false;
  final directions = <String>[];
  var inVideo = false;
  String? direction;
  void closeSection() {
    if (inVideo) directions.add(direction ?? 'sendrecv');
  }

  for (final raw in sdp.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('m=')) {
      closeSection();
      final parts = line.substring(2).split(' ');
      inVideo = parts.first == 'video';
      direction = null;
      if (inVideo) {
        sections += 1;
        if (parts.length > 1 && parts[1] == '0') rejected += 1;
      }
      continue;
    }
    if (!inVideo) continue;
    switch (line) {
      case 'a=sendrecv' || 'a=sendonly' || 'a=recvonly' || 'a=inactive':
        direction = line.substring(2);
      default:
        if (line.startsWith('a=msid:')) msid = true;
        if (line.startsWith('a=ssrc:')) ssrc = true;
    }
  }
  closeSection();
  return 'videoSections=$sections rejectedVideo=$rejected '
      'directions=${directions.isEmpty ? '-' : directions.join(',')} '
      'hasVideoMsid=$msid hasVideoSsrc=$ssrc';
}
