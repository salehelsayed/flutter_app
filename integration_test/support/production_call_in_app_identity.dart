import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

String _digest(String value) => sha256.convert(utf8.encode(value)).toString();
bool _hash(Object? value) =>
    value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : {};

/// Read-only UI projection. Names and peer IDs never leave this parser.
/// The caller must join it to current-call observations before and after the
/// existing campaign's owned UI read; an XML dump alone is not a call proof.
Map<String, Object?> productionCallInAppIdentitySnapshot(
  String xml, {
  required String packageName,
  required String expectedName,
  required List<String> peerIds,
  required String phase,
}) {
  if (!{'incoming', 'connected'}.contains(phase) ||
      packageName.isEmpty ||
      expectedName.isEmpty ||
      peerIds.length != 2 ||
      peerIds.toSet().length != 2 ||
      peerIds.any((p) => p.isEmpty) ||
      peerIds.contains(expectedName)) {
    throw ArgumentError(
      'exact owned call phase/name and two authenticated peers required',
    );
  }
  if (utf8.encode(xml).length > 4 * 1024 * 1024 ||
      RegExp(
        r'DUMP TIMEOUT|Error dumping service|FAILED BINDER TRANSACTION',
        caseSensitive: false,
      ).hasMatch(xml)) {
    throw const FormatException(
      'in-app call UI read incomplete or over capacity',
    );
  }
  final document = XmlDocument.parse(xml);
  if (document.rootElement.name.local != 'hierarchy') {
    throw const FormatException('complete UI hierarchy required');
  }
  bool visible(XmlElement node) {
    XmlNode? ancestor = node;
    while (ancestor != null) {
      if (ancestor is XmlElement &&
          ancestor.getAttribute('visible-to-user') == 'false') {
        return false;
      }
      ancestor = ancestor.parent;
    }
    return true;
  }

  final nodes = document.descendants
      .whereType<XmlElement>()
      .where(
        (n) =>
            n.name.local == 'node' &&
            n.getAttribute('package') == packageName &&
            visible(n),
      )
      .toList();
  Set<String> labels(XmlElement node) =>
      {node.getAttribute('text') ?? '', node.getAttribute('content-desc') ?? ''}
        ..remove('');
  final statusNodes = nodes
      .where(
        (n) => RegExp(
          r'(?:^|[/:])call_status$',
        ).hasMatch(n.getAttribute('resource-id') ?? ''),
      )
      .toList();
  // Both shipped call widgets give name/status separate child semantics under
  // one profile container. A contact name in the underlying chat is not proof.
  final nameNodes = nodes
      .where(
        (n) =>
            labels(n).contains(expectedName) &&
            statusNodes.length == 1 &&
            identical(n.parent, statusNodes.single.parent),
      )
      .toList();
  final status = phase == 'incoming' ? 'Incoming call' : 'Connected';
  final peers = peerIds.map(_digest).toList()..sort();
  return {
    'phase': phase,
    'packageSha256': _digest(packageName),
    'sourceUiSha256': _digest(xml),
    'expectedNameSha256': _digest(expectedName),
    'peerSha256s': peers,
    'nameNodeCount': nameNodes.length,
    'ownedStatusNodeCount': statusNodes.length,
    'statusMatches':
        statusNodes.length == 1 && labels(statusNodes.single).contains(status),
    'peerIdVisible': nodes.any(
      (n) => labels(n).any((s) => peerIds.any(s.contains)),
    ),
  };
}

/// Conjunctive addition to the existing authenticated native-card oracle for
/// kx0016/17. It does not replace the baseline, card or restoration predicates.
List<String> validateProductionCallInAppIdentity(
  Map<String, Object?> proof, {
  required String actorIdentity,
  required String otherIdentity,
}) {
  final failures = <String>[];
  void require(bool value, String message) {
    if (!value) failures.add(message);
  }

  final id = proof['caseId'];
  require(
    {'kx0016', 'kx0017'}.contains(id) &&
        _hash(actorIdentity) &&
        _hash(otherIdentity) &&
        actorIdentity != otherIdentity,
    'exact authenticated in-app call case and two peers required',
  );
  final expected = id == 'kx0017'
      ? _digest('Unknown contact')
      : _map(proof['contactName'])['displayNameSha256'];
  require(
    _hash(expected) &&
        proof['expectedInAppNameSha256'] == expected &&
        _hash(proof['inAppPackageSha256']),
    'in-app name must match authenticated contact or actual safe Flutter fallback',
  );
  final observations = _map(proof['observations']);
  final uiHashes = <Object?>{};
  for (final phase in ['incoming', 'connected']) {
    final observation = _map(observations[phase]);
    final current = _map(observation['current']),
        value = _map(observation['inAppIdentity']);
    final peers = value['peerSha256s'];
    require(
      value['phase'] == phase &&
          value['packageSha256'] == proof['inAppPackageSha256'] &&
          _hash(value['sourceUiSha256']) &&
          uiHashes.add(value['sourceUiSha256']) &&
          value['expectedNameSha256'] == expected &&
          current['state'] == (phase == 'incoming' ? 'ringing' : 'connected') &&
          value['nameNodeCount'] == 1 &&
          value['ownedStatusNodeCount'] == 1 &&
          value['statusMatches'] == true &&
          value['peerIdVisible'] == false &&
          peers is List &&
          peers.length == 2 &&
          peers.toSet().containsAll({actorIdentity, otherIdentity}),
      '$phase: actual owned readable in-app name/status without either peer ID required',
    );
    for (final side in ['before', 'after']) {
      final bound = _map(value[side]);
      require(
        bound['sourceBound'] == true &&
            bound['connectionReadSucceeded'] == true &&
            bound['inCall'] == true &&
            _hash(bound['callSha256']) &&
            bound['callSha256'] == current['callSha256'] &&
            bound['contactSha256'] == otherIdentity &&
            bound['direction'] == 'incoming' &&
            bound['state'] == (phase == 'incoming' ? 'ringing' : 'connected'),
        '$phase/$side: UI read must remain inside the same actual authenticated incoming call',
      );
    }
  }
  return failures;
}
