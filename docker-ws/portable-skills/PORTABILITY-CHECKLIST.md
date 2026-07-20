# Handoff checklist

Run these checks from the bundle root before installing it elsewhere.

## Package integrity

- Copy each complete skill directory, including `agents/` and `references/`.
- Confirm every file referenced by a `SKILL.md` exists inside that same skill.
- Confirm both `agents/openai.yaml` files set
  `allow_implicit_invocation: false`.
- Confirm both `SKILL.md` files contain a current-message explicit-invocation
  guard and piqube's `AGENTS.md` preserves that policy.
- Confirm piqube's `$graphify` skill is separately installed and its invocation
  policy is understood.

## Project adaptation

- Plan root resolves from the discovered repository root to
  `~/piqube/docs/tdd`, even when Codex starts in a nested directory.
- Test commands, working directories, tiers, tags, suites, CI jobs, and fixture
  rules come from piqube source and instructions.
- When Graphify is authorized, its commands come from piqube's Graphify skill;
  otherwise the runtime skills record the not-used disposition and use
  targeted source discovery. They do not assume a helper, graph directory,
  profile, or budget.
- A graph result is used for navigation only; source, tests, manifests, and
  gate definitions prove load-bearing claims.
- Broad suites supplement focused causality and follow piqube's own cadence.
- Real-boundary proof is required only when the behavior depends on that
  boundary and uses targets or fixtures available under piqube's policy.

## Mechanical audit

The runtime skill directories should contain no source-project vocabulary or
absolute developer paths:

```bash
rg -ni \
  '\b(mknoon|flutter|dart|widgettester|integration_test|test-flight-improv|libp2p|relay|android|iphone|ios|FLUTTER_DEVICE_ID|sqlcipher|ml-kem|ed25519|go bridge|graphify-arch|host-all|classify_path|dart-define)\b|tdd_context\.py|run_.*test_gates|/Users/|/home/|[A-Za-z]:\\Users\\' \
  tdd-plan tdd-review
```

Expected result: no unreviewed matches.

Also verify that neither skill names an execution, simulator, or orchestration
skill that is not installed in piqube.
