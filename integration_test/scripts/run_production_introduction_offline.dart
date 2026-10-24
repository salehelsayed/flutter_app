import 'run_production_introduction_mutual.dart'
    show runProductionIntroductionJourney;

Future<void> main(List<String> arguments) =>
    runProductionIntroductionJourney(arguments, offlineOutbox: true);
