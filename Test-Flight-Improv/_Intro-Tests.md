  Fast intro regression:

  ./scripts/run_test_gates.sh intro

  Full host-side intro suite:

  flutter test --no-pub test/features/introduction

  Exact three-simulator UI/copy verification:

  INTRO_E2E_SCENARIO=copy ./smoke_test_friends.sh

  Full three-simulator intro matrix:

  INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh

  Available simulator scenarios:

  - happy
  - refresh
  - pass
  - repair
  - copy
  - all

  The notification popup bypass is automatic when you
  use reset_simulators.sh through
  smoke_test_friends.sh, because the app launches with
  E2E_TEST_MODE=true.

  If you specifically want to recheck the intro copy
  work only, this is the shortest useful set:

  flutter test --no-pub test/features/introduction/
  application/introduction_copy_test.dart test/
  features/introduction/integration/
  intro_wiring_smoke_test.dart
  INTRO_E2E_SCENARIO=copy ./smoke_test_friends.sh

  Screenshots from the device run are saved under
  build/intro_e2e.
