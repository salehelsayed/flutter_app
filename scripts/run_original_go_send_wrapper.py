"""Execute the retained Go wrapper in this candidate and verify its completion.

The wrapper retains its original Send selector and final fifteen output lines.
The full Go module owner supplies individual test receipts; this owner verifies
the original wrapper itself, including its candidate binding and failure exit.
"""
from pathlib import Path
import os
import re
import subprocess


PACKAGE = 'github.com/mknoon/go-mknoon/node'
MARKER = 'ORIGINAL_GO_SEND_WRAPPER_PASS'


def verify_completion(listing, output, returncode):
    names = [line for line in listing.splitlines()
             if re.fullmatch(r'Test[A-Za-z0-9_]+', line) and 'Send' in line]
    if not names or len(set(names)) != len(names):
        raise ValueError('Send must resolve to a nonempty unique test catalog')
    summaries = re.findall(r'^ok\s+' + re.escape(PACKAGE) +
                           r'\s+[0-9]+(?:\.[0-9]+)?s\s*$', output, re.M)
    if (returncode != 0 or len(summaries) != 1 or
            re.search(r'\bFAIL\b|\[no tests to run\]|\[no test files\]|\(cached\)', output)):
        raise ValueError('Original Go wrapper did not complete this invocation')
    return names


def main():
    root = Path(__file__).resolve().parents[1]
    env = dict(os.environ, GOTOOLCHAIN='go1.25.0')
    listing = subprocess.run(
        ['go', 'test', './node/', '-list', 'Send'],
        cwd=root / 'go-mknoon', env=env, capture_output=True,
        text=True, timeout=600, check=True,
    )
    # This exact original route remains executable; it is not redirected to a
    # substitute Go command. Its separately approved path fix pins this root.
    result = subprocess.run(
        ['bash', 'docker-ws/alltests_go_test.sh'], cwd=root, env=env,
        capture_output=True, text=True, timeout=600,
    )
    print(result.stdout, end='')
    print(result.stderr, end='')
    names = verify_completion(listing.stdout, result.stdout, result.returncode)
    print(f'{MARKER} matched_tests={len(names)}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
