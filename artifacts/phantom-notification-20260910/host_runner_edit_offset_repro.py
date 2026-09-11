#!/usr/bin/env python3
"""Isolate Bash's read-offset behavior; never modify the repository runner."""

import os
from pathlib import Path
import subprocess
import tempfile
import time


source = Path("scripts/run_host_test_gates.sh").read_bytes()
for mutate in (False, True):
    with tempfile.TemporaryDirectory(prefix="host-runner-offset-") as directory:
        root = Path(directory)
        for name in ("scripts", "bin", "tmp"):
            (root / name).mkdir()
        runner = root / "scripts/run_host_test_gates.sh"
        runner.write_bytes(source)
        stub = root / "bin/flutter"
        stub.write_text(
            '#!/bin/bash\n'
            'touch "$RUNNER_REPRO_READY"\n'
            'read -r token < "$RUNNER_REPRO_RELEASE"\n'
            'exit 0\n'
        )
        stub.chmod(0o755)
        mktemp = root / "bin/mktemp"
        mktemp.write_text('#!/bin/bash\nexec /usr/bin/mktemp "$RUNNER_REPRO_TMP/plan.XXXXXX"\n')
        mktemp.chmod(0o755)
        ready, release = root / "ready", root / "release"
        os.mkfifo(release)
        environment = os.environ.copy()
        environment.update(
            PATH=str(root / "bin") + ":" + environment["PATH"],
            TMPDIR=str(root / "tmp"),
            RUNNER_REPRO_READY=str(ready),
            RUNNER_REPRO_RELEASE=str(release),
            RUNNER_REPRO_TMP=str(root / "tmp"),
        )
        process = subprocess.Popen(
            ["/bin/bash", str(runner), "1to1", "--batch-flutter", "--only", "1"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env=environment,
            text=True,
        )
        deadline = time.monotonic() + 5
        while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
            time.sleep(0.01)
        if not ready.exists():
            process.kill()
            raise RuntimeError(process.communicate()[0])
        temporary_before = sorted(path.name for path in (root / "tmp").iterdir())
        assert len(temporary_before) == 4, temporary_before
        if mutate:
            # The whole batch conditional is already parsed. Bash resumes
            # reading at its old byte offset after the fake Flutter returns.
            # Move that offset into the old conditional's failure exit line.
            resume = source.index(b"failure_count=")
            target = source.rindex(b'        exit "$status"')
            delta = resume - target
            runner.write_bytes(b"#" + b"x" * (delta - 2) + b"\n" + source)
        with release.open("w") as stream:
            stream.write("continue\n")
        output = process.communicate(timeout=5)[0]
        temporary_after = list((root / "tmp").iterdir())
        assert process.returncode == 0, output
        assert not temporary_after, temporary_after
        if mutate:
            assert "status: unbound variable" in output, output
            assert "PASS: host tests completed" not in output, output
        else:
            assert "unbound variable" not in output, output
            assert "PASS: host tests completed" in output, output
        print(f'{"MUTATED COPY" if mutate else "INTACT COPY"}: exit={process.returncode}')
        print(f"Runner temporary files: before={len(temporary_before)}, after={len(temporary_after)}")
        print("\n".join(output.splitlines()[-7:]))
