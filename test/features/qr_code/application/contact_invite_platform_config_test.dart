import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

const _androidNamespace = 'http://schemas.android.com/apk/res/android';
const _inviteHost = 'invite.mknoon.xyz';

void main() {
  test('iOS Runner claims the invite domain and preserves ShareMedia', () {
    final info = _readXml('ios/Runner/Info.plist').getElement('dict')!;
    final urlTypes = _plistValue(info, 'CFBundleURLTypes');
    expect(urlTypes?.localName, 'array');
    final registrations = urlTypes!
        .findElements('dict')
        .map((entry) => _plistStrings(_plistValue(entry, 'CFBundleURLSchemes')))
        .toList();
    expect(
      registrations.expand((schemes) => schemes),
      contains(r'ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)'),
      reason: 'Runner must still register the share extension callback',
    );

    final entitlements = _readXml('ios/Runner/Runner.entitlements')
        .getElement('dict')!;
    expect(
      _plistStrings(
        _plistValue(entitlements, 'com.apple.developer.associated-domains'),
      ),
      contains('applinks:$_inviteHost'),
      reason: 'the invite domain must be a Runner Associated Domains value',
    );
    expect(
      registrations.where((schemes) => schemes.contains('mknoon')).toList(),
      [
        ['mknoon'],
      ],
      reason: 'mknoon must have a separate URL type from ShareMedia',
    );
    expect(
      _plistValue(info, 'FlutterDeepLinkingEnabled')?.localName,
      'false',
      reason: 'Runner must turn off the Flutter engine URL handler',
    );
  });

  test('Android MainActivity claims distinct invite and fallback filters', () {
    final manifest = _readXml('android/app/src/main/AndroidManifest.xml');
    final activity = manifest
        .getElement('application')!
        .findElements('activity')
        .singleWhere(
          (activity) => [
            '.MainActivity',
            'com.mknoon.app.MainActivity',
          ].contains(_android(activity, 'name')),
        );
    expect(_android(activity, 'exported'), 'true');
    final filters = activity.findElements('intent-filter');
    expect(
      filters.any(
        (filter) =>
            _declaredNames(
              filter,
              'action',
            ).contains('android.intent.action.SEND') &&
            _declaredNames(
              filter,
              'category',
            ).contains('android.intent.category.DEFAULT') &&
            filter
                .findElements('data')
                .any((data) => _android(data, 'mimeType') == 'text/plain'),
      ),
      isTrue,
      reason: 'MainActivity must preserve its text share filter',
    );

    final invite = filters.where(
      (filter) => filter
          .findElements('data')
          .any((data) => _android(data, 'host') == _inviteHost),
    );
    expect(
      invite,
      hasLength(1),
      reason: 'MainActivity must claim the invite host',
    );
    expect(_android(invite.single, 'autoVerify'), 'true');
    _expectOpenFilter(invite.single, {
      'scheme': 'https',
      'host': _inviteHost,
      'path': '/i/v1',
    });

    final fallback = filters.where(
      (filter) => filter
          .findElements('data')
          .any((data) => _android(data, 'scheme') == 'mknoon'),
    );
    expect(
      fallback,
      hasLength(1),
      reason: 'declare a separate mknoon://invite filter',
    );
    expect(fallback.single, isNot(same(invite.single)));
    expect(_android(fallback.single, 'autoVerify'), anyOf(isNull, 'false'));
    _expectOpenFilter(fallback.single, {'scheme': 'mknoon', 'host': 'invite'});

    final optOut = activity
        .findElements('meta-data')
        .where(
          (entry) => _android(entry, 'name') == 'flutter_deeplinking_enabled',
        );
    expect(optOut.map((entry) => _android(entry, 'value')).toList(), ['false']);
  });
}

XmlElement _readXml(String path) =>
    XmlDocument.parse(File(path).readAsStringSync()).rootElement;

XmlElement? _plistValue(XmlElement dict, String key) {
  final elements = dict.childElements.toList();
  for (var index = 0; index + 1 < elements.length; index += 2) {
    final element = elements[index];
    if (element.localName == 'key' && element.innerText == key) {
      return elements[index + 1];
    }
  }
  return null;
}

List<String> _plistStrings(XmlElement? element) => element?.localName == 'array'
    ? element!.findElements('string').map((entry) => entry.innerText).toList()
    : const [];

String? _android(XmlElement element, String name) =>
    element.getAttribute(name, namespace: _androidNamespace);

Iterable<String?> _declaredNames(XmlElement element, String type) =>
    element.findElements(type).map((entry) => _android(entry, 'name'));

void _expectOpenFilter(XmlElement filter, Map<String, String> match) {
  expect(
    filter.childElements.map((element) => element.localName),
    everyElement(isIn(['action', 'category', 'data'])),
  );
  expect(_declaredNames(filter, 'action'), ['android.intent.action.VIEW']);
  expect(
    _declaredNames(filter, 'category'),
    unorderedEquals([
      'android.intent.category.DEFAULT',
      'android.intent.category.BROWSABLE',
    ]),
  );
  final attributes = filter
      .findElements('data')
      .expand((data) => data.attributes)
      .where((attribute) => attribute.namespaceUri == _androidNamespace);
  expect(attributes, hasLength(match.length));
  expect({
    for (final attribute in attributes) attribute.localName: attribute.value,
  }, match);
}
