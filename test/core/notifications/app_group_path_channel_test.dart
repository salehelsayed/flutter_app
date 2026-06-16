import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/app_group_path_channel.dart';

void main() {
  test('returns the native container path', () async {
    final channel = AppGroupPathChannel(
      invoker: (method, arguments) async {
        expect(method, 'appGroupContainerPath');
        expect(arguments, isNull);
        return '/var/mobile/Containers/Shared/AppGroup/abc';
      },
    );
    expect(
      await channel.containerPath(),
      '/var/mobile/Containers/Shared/AppGroup/abc',
    );
  });

  test('returns null when the channel is unimplemented (off-iOS)', () async {
    final channel = AppGroupPathChannel(
      invoker: (method, arguments) async =>
          throw MissingPluginException('no impl'),
    );
    expect(await channel.containerPath(), isNull);
  });

  test('returns null on PlatformException (app_group_unavailable)', () async {
    final channel = AppGroupPathChannel(
      invoker: (method, arguments) async =>
          throw PlatformException(code: 'app_group_unavailable'),
    );
    expect(await channel.containerPath(), isNull);
  });

  test('returns null for an empty or non-string result', () async {
    expect(
      await AppGroupPathChannel(invoker: (m, a) async => '').containerPath(),
      isNull,
    );
    expect(
      await AppGroupPathChannel(invoker: (m, a) async => null).containerPath(),
      isNull,
    );
    expect(
      await AppGroupPathChannel(invoker: (m, a) async => 42).containerPath(),
      isNull,
    );
  });
}
