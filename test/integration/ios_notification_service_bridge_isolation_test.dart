import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'iOS notification service links the bounded NSE bridge, not the app bridge',
    () {
      final podfile = File('ios/Podfile').readAsStringSync();
      final notificationTarget = RegExp(
        r"target 'NotificationService' do(?<body>[\s\S]*?)\nend",
      ).firstMatch(podfile)?.namedGroup('body');

      expect(notificationTarget, isNotNull);
      expect(notificationTarget, contains("pod 'GoMknoonNSE', :path => '.'"));
      expect(
        notificationTarget,
        isNot(contains("pod 'GoMknoon', :path => '.'")),
      );

      final makefile = File('go-mknoon/Makefile').readAsStringSync();
      expect(
        makefile,
        contains('gomobile bind -target=ios -tags=nse_lite -ldflags "-s -w"'),
      );

      final resolver = File(
        'ios/NotificationService/NotificationPreviewResolver.swift',
      ).readAsStringSync();
      expect(resolver, contains('#if canImport(GoMknoonNSE)'));
      expect(resolver, contains('import GoMknoonNSE'));

      final mailbox = File(
        'ios/NotificationService/NseMailboxWakeCoordinator.swift',
      ).readAsStringSync();
      expect(mailbox, contains('#if canImport(GoMknoonNSE)'));
      expect(mailbox, contains('import GoMknoonNSE'));

      final productionBootstrap = File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsStringSync();
      expect(
        productionBootstrap,
        contains('!isIosNseOpaqueInboxConsumerCompiledIn() ||'),
        reason:
            'iOS must not advertise opaque_wake_v1 while the lean bridge '
            'fails fixed mailbox wakes closed',
      );
    },
  );
}
