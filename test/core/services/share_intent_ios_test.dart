import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

void main() {
  group('iOS share extension configuration', () {
    test(
      '4e: app group, URL scheme, and extension controller fallback are configured',
      () {
        final runnerInfo = File('ios/Runner/Info.plist').readAsStringSync();
        final extensionInfo = File(
          'ios/Share Extension/Info.plist',
        ).readAsStringSync();
        final podfile = File('ios/Podfile').readAsStringSync();
        final controller = File(
          'ios/Share Extension/ShareViewController.swift',
        ).readAsStringSync();
        final fallback = File(
          'ios/Share Extension/RSIShareFallback.swift',
        ).readAsStringSync();
        final storyboard = File(
          'ios/Share Extension/Base.lproj/MainInterface.storyboard',
        );
        final runnerEntitlements = File(
          'ios/Runner/Runner.entitlements',
        ).readAsStringSync();
        final extensionEntitlements = File(
          'ios/Share Extension/Share Extension.entitlements',
        ).readAsStringSync();
        final project = File(
          'ios/Runner.xcodeproj/project.pbxproj',
        ).readAsStringSync();

        expect(runnerInfo, contains('<key>AppGroupId</key>'));
        expect(
          runnerInfo,
          contains('ShareMedia-\$(PRODUCT_BUNDLE_IDENTIFIER)'),
        );
        expect(extensionInfo, contains('<key>AppGroupId</key>'));
        expect(extensionInfo, contains('NSExtensionActivationSupportsText'));
        expect(
          extensionInfo,
          contains('NSExtensionActivationSupportsWebURLWithMaxCount'),
        );
        expect(extensionInfo, contains('<key>NSExtensionPrincipalClass</key>'));
        expect(
          extensionInfo,
          contains(
            '<string>\$(PRODUCT_MODULE_NAME).ShareViewController</string>',
          ),
        );
        expect(extensionInfo, isNot(contains('NSExtensionMainStoryboard')));
        expect(podfile, isNot(contains("target 'Share Extension' do")));
        expect(controller, contains('canImport(receive_sharing_intent)'));
        expect(
          controller,
          contains('class ShareViewController: UIViewController'),
        );
        expect(controller, contains('configureLoadingView()'));
        expect(controller, contains('beginProcessingShare()'));
        expect(controller, contains('processIncomingItems()'));
        expect(controller, contains('loadInPlaceFileRepresentation'));
        expect(controller, contains('loadFileRepresentation'));
        expect(controller, contains('saveAndRedirect()'));
        expect(controller, isNot(contains('getVideoInfo(')));
        expect(controller, isNot(contains('RSIShareViewController')));
        expect(controller, isNot(contains('shouldAutoRedirect')));
        expect(fallback, contains('#if !canImport(receive_sharing_intent)'));
        expect(fallback, contains('open class RSIShareViewController'));
        expect(
          fallback,
          contains(
            'guard index == (content.attachments?.count ?? 0) - 1,\n'
            '              shouldAutoRedirect() else {',
          ),
        );
        expect(runnerEntitlements, contains('group.com.mknoon.app.share'));
        expect(extensionEntitlements, contains('group.com.mknoon.app.share'));
        expect(
          project,
          contains('CUSTOM_GROUP_ID = group.com.mknoon.app.share;'),
        );
        expect(
          project,
          contains('PRODUCT_BUNDLE_IDENTIFIER = com.mknoon.app;'),
        );
        expect(
          project,
          contains(
            'PRODUCT_BUNDLE_IDENTIFIER = com.mknoon.app.ShareExtension;',
          ),
        );
        expect(project, isNot(contains('com.example.makerGenerated')));
        expect(
          project,
          contains('Share Extension/Share Extension.entitlements'),
        );
        expect(storyboard.existsSync(), isFalse);
        expect(project, isNot(contains('MainInterface.storyboard')));
      },
    );
  });

  group('iOS share intent conversion', () {
    test('4a: parses shared URL from iOS extension', () async {
      final service = ShareIntentService(
        getInitialMedia: () async => [
          SharedMediaFile(
            path: 'https://mknoon.app',
            type: SharedMediaType.url,
          ),
        ],
        resetShareIntent: () {},
      );

      final intent = await service.getInitialIntent();

      expect(intent, isNotNull);
      expect(intent!.type, ShareIntentType.text);
      expect(intent.text, 'https://mknoon.app');
    });

    test('4b: parses shared image from iOS extension', () async {
      final service = ShareIntentService(
        getInitialMedia: () async => [
          SharedMediaFile(
            path: '/tmp/ios-photo.jpg',
            type: SharedMediaType.image,
            message: 'caption',
          ),
        ],
        resetShareIntent: () {},
      );

      final intent = await service.getInitialIntent();

      expect(intent, isNotNull);
      expect(intent!.type, ShareIntentType.mixed);
      expect(intent.text, 'caption');
      expect(intent.filePaths, ['/tmp/ios-photo.jpg']);
    });

    test('4c: parses shared video from iOS extension', () async {
      final service = ShareIntentService(
        getInitialMedia: () async => [
          SharedMediaFile(
            path: '/tmp/ios-video.mov',
            type: SharedMediaType.video,
          ),
        ],
        resetShareIntent: () {},
      );

      final intent = await service.getInitialIntent();

      expect(intent, isNotNull);
      expect(intent!.type, ShareIntentType.files);
      expect(intent.filePaths, ['/tmp/ios-video.mov']);
    });

    test('4d: parses multiple shared images', () async {
      final service = ShareIntentService(
        getInitialMedia: () async => [
          SharedMediaFile(path: '/tmp/ios-1.jpg', type: SharedMediaType.image),
          SharedMediaFile(path: '/tmp/ios-2.jpg', type: SharedMediaType.image),
        ],
        resetShareIntent: () {},
      );

      final intent = await service.getInitialIntent();

      expect(intent, isNotNull);
      expect(intent!.type, ShareIntentType.files);
      expect(intent.filePaths, ['/tmp/ios-1.jpg', '/tmp/ios-2.jpg']);
    });

    test(
      '4e: preserves bidi markers and trims captions while joining iOS share text',
      () async {
        final service = ShareIntentService(
          getInitialMedia: () async => [
            SharedMediaFile(path: 'First line', type: SharedMediaType.text),
            SharedMediaFile(
              path: '/tmp/ios-photo.jpg',
              type: SharedMediaType.image,
              message: '  مرحبا\u202E Hello\u200E  ',
            ),
            SharedMediaFile(path: 'Second line', type: SharedMediaType.text),
          ],
          resetShareIntent: () {},
        );

        final intent = await service.getInitialIntent();

        expect(intent, isNotNull);
        expect(intent!.type, ShareIntentType.mixed);
        expect(intent.text, 'First line\nمرحبا\u202E Hello\u200E\nSecond line');
        expect(intent.filePaths, ['/tmp/ios-photo.jpg']);
      },
    );
  });
}
