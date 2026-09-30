"""iOS group media: keep the evidence that names the failing stage. (1) runner keeps the fixed StateError detail,
(2) the fixture's stderr stage line is saved beside its receipt, (3) the xcodebuild test output is saved in the run
dir before the exit check. No assertion or deadline changes. [roots...]"""
import pathlib, sys
E = [
 ('integration_test/scripts/group_media_reliability_runner_contract.dart',
  """  } on Object {
    return GroupMediaReliabilityRunnerResult.failed(
      'The group media scenario failed before a validated artifact existed.',
    );
  }""",
  """  } on StateError catch (error) {
    // Controller failures carry fixed, driver-authored stage details.
    return GroupMediaReliabilityRunnerResult.failed(
      'The group media scenario failed before a validated artifact existed: '
      '${error.message}',
    );
  } on Object {
    return GroupMediaReliabilityRunnerResult.failed(
      'The group media scenario failed before a validated artifact existed.',
    );
  }"""),
 ('integration_test/scripts/group_media_ios_background_recovery.dart',
  """      result = await _runFixtureCommand(action: action, command: command);
    } finally {
      _fixtureDriverCustody.verifyUnchanged();
    }
""",
  """      result = await _runFixtureCommand(action: action, command: command);
    } finally {
      _fixtureDriverCustody.verifyUnchanged();
    }
    // The fixture driver reports its failing stage as one JSON line on stderr.
    File('${output.path}.stderr.log').writeAsStringSync(result.stderr);
"""),
 ('integration_test/scripts/group_media_ios_background_recovery.dart',
  """    if (xctest.exitCode != 0) {
      await _cancelAndSettleFixtures(""",
  """    File('${_runDirectory.path}/xcodebuild-test.log').writeAsStringSync(
      '${xctest.stdout}\\n--- stderr ---\\n${xctest.stderr}',
    );
    if (xctest.exitCode != 0) {
      await _cancelAndSettleFixtures("""),
]
for root in (sys.argv[1:] or ['/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree']):
    for rel, old, new in E:
        p = pathlib.Path(root, rel); s = p.read_text()
        if new in s: continue
        assert s.count(old) == 1, (root, rel, old[:50]); p.write_text(s.replace(old, new))
    print('patched', root)
