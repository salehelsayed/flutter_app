# Codex TDD skills for piqube

This bundle contains project-adapted versions of `$tdd-plan` and `$tdd-review`.
They preserve the causal planning and counterexample-review method from the
source skills without carrying over that unrelated project's framework,
database, networking, mobile-device, gate-name, or layout assumptions. This
handoff deliberately sets piqube's plan root to `docs/tdd/`.

The intended destination is `~/piqube`. Plans default to:

```text
~/piqube/docs/tdd/
```

Graphify is not bundled. When its use is authorized, each skill reads piqube's
own repository instructions and installed `$graphify` skill, then uses that
project's query command, profiles, graph locations, and freshness policy. When
it is not authorized or available, the skills use targeted source discovery
and record that limitation.

## Install

Run the following from this bundle root (the directory containing this
`README.md`, `tdd-plan/`, and `tdd-review/`). It first verifies the target
checkout exists and neither skill is already installed, then fails closed
instead of merging two skill versions:

```bash
test -d ~/piqube || { echo 'Missing target repository: ~/piqube' >&2; exit 1; }
test ! -e ~/piqube/.agents/skills/tdd-plan || { echo 'tdd-plan already exists' >&2; exit 1; }
test ! -e ~/piqube/.agents/skills/tdd-review || { echo 'tdd-review already exists' >&2; exit 1; }
mkdir -p ~/piqube/.agents/skills
mkdir -p ~/piqube/docs/tdd
cp -R tdd-plan tdd-review ~/piqube/.agents/skills/
```

If that Codex installation uses `~/.codex/skills/` instead of repository-local
`.agents/skills/`, perform the same existence checks and copy the two complete
directories there. Move aside an older version deliberately before copying;
do not merge versions. Start a fresh Codex session if the skill catalog is only
loaded at session start.

## Invoke

Both skills are explicit-only:

```text
Use $tdd-plan to plan <bug, feature, or modification>.
Use $tdd-review to audit docs/tdd/<plan-file>.md.
```

If piqube's policy allows Graphify to be selected implicitly for codebase work,
those prompts are sufficient. If Graphify also requires explicit permission:

```text
Use $tdd-plan and $graphify to plan <request>.
Use $tdd-review and $graphify to audit docs/tdd/<plan-file>.md.
```

Invoking one TDD skill never invokes the other. Planning offers review at
handoff; review runs only when the user names `$tdd-review`.

## Recommended repository policy

Keep the invocation boundary explicit in piqube's `AGENTS.md`:

```markdown
- Graphify may be selected implicitly for codebase, architecture, impact, test
  discovery, TDD-planning, and TDD-review work.
- Invoke `$tdd-plan` and `$tdd-review` only when the current user message
  affirmatively names that skill. Task similarity, a stored plan, a prior
  recommendation, or invocation of the other skill is not permission.
- Resolve TDD artifacts from the repository root under `docs/tdd/` unless the
  user explicitly requests another output path.
```

## Runtime behavior

- Plans are written under `<repository-root>/docs/tdd/` unless the user
  explicitly requests a different output path. This is independent of the
  shell's current subdirectory.
- Existing issue/spec identifiers and documented naming conventions win. With
  no convention, the fallback is
  `docs/tdd/YYYY-MM-DD-<slug>-tdd-plan.md`; collisions receive `-2`, `-3`, and
  so on.
- An index is updated only when piqube already defines one or its instructions
  require one.
- Every plan records the repository conventions actually used. It records
  Graphify anchors when Graphify ran, or a not-used/limitation disposition when
  it did not. No command, test tier, fixture, or CI registration is guessed
  from the source project.
- `$tdd-review` is chat-only and read-only by default. It writes a fix-list or
  revises a plan only when explicitly asked.

See [PORTABILITY-CHECKLIST.md](PORTABILITY-CHECKLIST.md) before copying.
