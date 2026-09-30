/// Preserves NEW_MEMBER_MEDIA on the production app: for the initial and the
/// reopened group screen, both media rows render with two video thumbnails and
/// two voice players showing 0:01, the first voice player enters its playing
/// state after a tap, and the first video opens in a VideoPlayer without the
/// load error. Seeded rows and original fixture files stay intact.
const productionMediaPasses = ['initial', 'reopened'];

List<String> validateProductionGroupMedia(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool condition, String reason) {
    if (!condition) failures.add(reason);
  }

  Map object(Object? value) => value is Map ? value : const {};
  List<Map> rows(Object? value) => value is List && value.every((v) => v is Map)
      ? value.cast<Map>()
      : const [];
  bool nonempty(Object? value) => value is String && value.isNotEmpty;

  final run = proof['runId'];
  final peers = object(proof['peers']);
  require(nonempty(run), 'run identity required');
  require(
    nonempty(peers['alice']) &&
        nonempty(peers['bob']) &&
        peers['alice'] != peers['bob'],
    'distinct exact peers required',
  );
  require(proof['groupId'] == 'report89-$run', 'run-owned media group');

  final passes = rows(proof['passes']);
  require(
    passes.length == 2 &&
        passes[0]['pass'] == 'initial' &&
        passes[1]['pass'] == 'reopened',
    'initial and reopened passes',
  );
  for (final pass in passes) {
    final name = pass['pass'];
    final snapshot = object(pass['rows']);
    require(
      snapshot['runId'] == run &&
          snapshot['role'] == 'bob' &&
          snapshot['groupPresent'] == true &&
          snapshot['lifecycle'] == 'resumed',
      '$name production binding',
    );
    final tree = object(snapshot['tree']);
    require(
      tree['scopedToConversation'] == 1,
      '$name observations scoped to the open group conversation',
    );
    require(
      tree['incomingText'] == 1 && tree['outgoingText'] == 1,
      '$name both message texts render once',
    );
    require(tree['videoThumbnailOverlays'] == 2, '$name two video thumbnails');
    require(tree['audioPlayerWidgets'] == 2, '$name two voice players');
    require(
      tree['durationLabels'] is int && (tree['durationLabels'] as int) >= 2,
      '$name voice durations 0:01',
    );
    final attachments = rows(snapshot['attachments']);
    require(
      attachments.length == 4 &&
          attachments.every(
            (a) => a['downloadStatus'] == 'done' && a['fileExists'] == true,
          ) &&
          attachments.where((a) => a['mediaType'] == 'video').length == 2 &&
          attachments.where((a) => a['mediaType'] == 'audio').length == 2,
      '$name four seeded attachments with files',
    );
    require(
      object(pass['voice'])['playingObserved'] == true,
      '$name voice tap enters playing state',
    );
    final viewer = object(object(pass['viewer'])['tree']);
    require(
      viewer['videoPlayers'] == 1 && viewer['videoLoadErrors'] == 0,
      '$name video opens without load error',
    );
  }
  final flows = proof['flows'];
  require(
    flows is List &&
        flows.join(',') ==
            [
              for (final p in productionMediaPasses) ...[
                '$p-open',
                '$p-play-voice',
                '$p-open-video',
                '$p-viewer-back',
              ],
            ].join(','),
    'exact ordered Maestro flows',
  );
  final cases = rows(proof['cases']);
  require(
    cases.length == 1 &&
        cases.single['id'] == 'NEW_MEMBER_MEDIA' &&
        cases.single['status'] == 'PASS',
    'exact NEW_MEMBER_MEDIA case',
  );
  return failures;
}
