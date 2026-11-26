import '../../../tool/sims/live_device_resolver.dart';
import '../../../tool/sims/sims.dart';

Future<void> main(List<String> arguments) =>
    runSims(arguments, deviceDiscovery: SimsLiveDeviceDiscovery(isMacOS: true));
