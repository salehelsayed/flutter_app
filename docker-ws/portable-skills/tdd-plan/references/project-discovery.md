# Project And Graphify Discovery

Read this in Step 0 before grounding a plan. The destination repository is the
authority; this bundle supplies a method, not project facts.

## Instruction And Convention Order

1. Resolve the repository root, then read every applicable instruction file
   from that root down to the files in scope.
2. If authorized Graphify instructions require a graph-first query, run the
   Graphify Adapter before raw source/test browsing.
3. Read relevant project documentation, build manifests, task-runner files, CI
   workflows, test configuration, and a small sample of current tests.
4. Reuse documented conventions. Infer a convention only when several current
   files consistently support it; one historical example is not a project
   contract.
5. In a monorepo, record the package/module and working directory for every
   literal command.

Determine from current evidence:

- language, framework, build system, and test runners;
- test levels and directory/naming conventions;
- exact syntax for one test, one file/target, the nearest affected suite, and
  any broad suite required by policy;
- automatic discovery, excludes, tags, manifests, suite lists, build targets,
  CI matrices, and scenario registries;
- lint, type-check, format, generated-code, packaging, or other quality gates;
- realistic fixtures for persistence, browsers, processes, containers,
  external services, devices, hardware, compatibility, or performance;
- selected plan root, defaulting to `<repository-root>/docs/tdd/`, plus naming
  and index rules.

Do not write a separate harness map unless the user or repository instructions
ask for one. Persist the compact convention snapshot in the plan instead.

## Graphify Adapter

Graphify is a separate skill. Use it only when the current request or the
destination repository's invocation policy authorizes it.

When authorized:

1. Read the destination's selected `$graphify` `SKILL.md` completely.
2. Use its documented query mechanism, graph choice, profiles, budgets, and
   freshness rules. It may expose a repository helper, CLI, or tool; do not
   invent a command from another project.
3. Follow its query discipline. When it defines no stricter rule, ask one
   focused question containing the behavior plus exact symbols, filenames,
   tests, gates, or identifiers when known and refine once only for an
   explicitly broad/ambiguous result or a missing required anchor.
4. Treat graph results as navigation candidates. Verify every load-bearing
   claim in current source, tests, manifests, or gate definitions.
5. Record the exact operation, graph identity/freshness information exposed by
   the tool, anchors, surfaced files, and gaps.

If Graphify is unauthorized, unavailable, stale, or insufficient, continue
with targeted source discovery and report the limitation. Do not silently
refresh, build, or mutate a graph.

## Snapshot Shape

Persist both compact snapshots in the plan:

```markdown
## Project Convention Snapshot

- Instructions consulted:
- Repository root / revision / working-tree state:
- Stack / package scope:
- Test levels and discovery:
- Focused selector:
- Affected-suite gate:
- Broad-suite owner/cadence:
- Static-quality commands:
- Boundary fixtures:
- Plan path / identifier rule:
- Unresolved conventions:

## Graph Grounding Snapshot

- Graph / freshness: <identity, or N/A - unauthorized/unavailable>.
- Query or tool operation: <exact operation, or N/A plus source fallback>.
- Exact anchors: <anchors, or N/A>.
- Surfaced production, test, and gate files: <files, or targeted-source files>.
- Graph gaps: <gaps or not-used reason>.
- Verification rule: graph anchors are navigation; current source and commands
  remain authoritative.
```

An unresolved convention that changes the causal proof, registration, closure
boundary, or literal gate leaves the plan `evidence-gated`.
