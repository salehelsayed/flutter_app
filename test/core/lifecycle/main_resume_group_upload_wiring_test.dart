import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart' as app;

void main() {
  test(
    'main.dart passes mediaFileManager into retryIncompleteGroupUploads on resume',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final mainSource = await File('lib/main.dart').readAsString();
      final start = mainSource.indexOf(
        'retryIncompleteGroupUploadsFn: () => retryIncompleteGroupUploads(',
      );

      expect(start, isNonNegative);

      final end = mainSource.indexOf('retryFailedGroupMessagesFn:', start);
      expect(end, greaterThan(start));

      final retryBlock = mainSource.substring(start, end);
      expect(
        retryBlock,
        contains('mediaFileManager: widget.mediaFileManager'),
        reason:
            'resume-time group upload retry must resolve persisted pending_uploads paths',
      );
    },
  );
}
