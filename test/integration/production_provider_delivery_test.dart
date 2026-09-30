import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/production_provider_delivery.dart';

void main() {
  const accepted = <String, Object?>{
    'ok': true,
    'stage': 'fcm',
    'operation': 'deliver',
    'validateOnly': false,
  };

  test('provider HTTP acceptance alone does not establish device ingress', () {
    expect(productionProviderSendAccepted(accepted, 0), isTrue);
    expect(productionProviderIngressObserved('', 'exact-digest'), isFalse);
    expect(
      productionProviderIngressObserved(
        'providerIngress=true probeSha256=other package=com.mknoon.app',
        'exact-digest',
      ),
      isFalse,
    );
    expect(
      productionProviderIngressObserved(
        'providerIngress=true probeSha256=exact-digest package=com.other.app',
        'exact-digest',
      ),
      isFalse,
    );
    expect(
      productionProviderIngressObserved(
        'providerIngress=true probeSha256=exact-digest package=com.mknoon.app',
        'exact-digest',
      ),
      isTrue,
    );
  });

  test('validation-only, rejected, and failed sends cannot pass', () {
    expect(productionProviderSendAccepted(accepted, 1), isFalse);
    expect(
      productionProviderSendAccepted({...accepted, 'validateOnly': true}, 0),
      isFalse,
    );
    expect(
      productionProviderSendAccepted({...accepted, 'ok': false}, 0),
      isFalse,
    );
    expect(
      productionProviderSendAccepted({...accepted, 'stage': 'oauth'}, 0),
      isFalse,
    );
  });

  test('provider rejection retains only the redacted stderr diagnosis', () {
    final diagnostic = productionProviderDiagnosticFromStreams(
      '',
      'build hook\n'
          '{"schema":"mknoon.fcm-provider-result.v1","ok":false,'
          '"stage":"fcm","httpStatus":404,"reason":"UNREGISTERED"}',
    );
    expect(diagnostic, isNotNull);
    expect(productionProviderSendAccepted(diagnostic!, 71), isFalse);
    expect(
      productionProviderFailureSummary(diagnostic),
      'stage=fcm httpStatus=404 reason=UNREGISTERED',
    );
    expect(
      productionProviderDiagnosticFromStreams('', 'unrelated stderr'),
      isNull,
    );
  });
}
