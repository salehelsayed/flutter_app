
  ▎ Run flutter test and cd go-mknoon && go test ./... to execute all tests. For any failing test:

  ▎ 1. Read the failing test to understand what behavior it's asserting
  ▎ 2. Read the production code it's testing
  ▎ 3. Determine: did the code break (regression) or did the test become stale (test needs updating)?
  ▎ 4. If the code broke — fix the production code, not the test
  ▎ 5. If the test is stale because of an intentional design change — explain what changed and why the test needs updating, and
  ask me before modifying it

  ▎ Do NOT silently fix tests to match current code. The goal is to catch regressions, not to make tests green.