package com.mknoon.app;

import androidx.test.rule.ActivityTestRule;
import dev.flutter.plugins.integration_test.FlutterTestRunner;
import org.junit.Rule;
import org.junit.runner.RunWith;

/** Runs the PB266 Dart integration target in the release application process. */
@RunWith(FlutterTestRunner.class)
public final class GroupExitReleaseDiagnosticsTest {
  @Rule
  public final ActivityTestRule<MainActivity> rule =
      new ActivityTestRule<>(MainActivity.class, true, false);
}
