# Project And Graphify Discovery

Read this in Step 0 before auditing a plan. The destination repository is the
authority; this bundle supplies a method, not project facts.

## Instruction And Convention Order

1. Resolve and record the repository root/revision/working-tree state, then
   read every applicable instruction file from that root down to the files in
   scope.
2. If authorized Graphify instructions require graph-first navigation, run the
   Graphify Adapter before raw source/test browsing.
3. Read relevant project documentation, build manifests, task-runner files, CI
   workflows, test configuration, and a small sample of current tests.
4. Reuse documented conventions. Infer a convention only when several current
   files consistently support it; one historical example is not a project
   contract.
5. In a monorepo, record the package/module and working directory for every
   literal command.

Verify the plan against the repository's actual:

- language, framework, build system, and test runners;
- test levels, directories, naming, selectors, tags, and exclusions;
- automatic discovery versus manifests, suite lists, build targets, CI
  matrices, or scenario registration;
- focused, affected-suite, broad-suite, static-quality, and packaging gates;
- realistic fixtures for persistence, browsers, processes, containers,
  external services, devices, hardware, compatibility, or performance;
- selected plan root, defaulting to `<repository-root>/docs/tdd/`, plus plan
  naming and fix-list conventions.

## Graphify Adapter

Graphify is a separate skill. Use it only when the current request or the
destination repository's invocation policy authorizes it.

When authorized:

1. Read the destination's selected `$graphify` `SKILL.md` completely.
2. Use its documented query mechanism, graph choice, profiles, budgets, and
   freshness rules. Do not copy a helper or graph path from another project.
3. Follow its query discipline. When it defines no stricter rule, query once
   with the plan's exact symbols, files, tests, gate names, or node identifiers
   and refine once only for an explicitly broad/ambiguous result or a missing
   required anchor. A genuinely multi-seam plan may need one anchored query per
   independent seam when the destination skill permits it.
4. Reuse a plan's Graph Grounding Snapshot only as search anchors, never as
   inherited conclusions.
5. Verify every load-bearing conclusion in current source, tests, manifests,
   or gate definitions.
6. Report graph identity/freshness, the exact operation, anchors, surfaced
   files, and gaps when available.
7. Review is read-only: do not refresh, build, or mutate Graphify output without
   explicit authorization.

If Graphify is unauthorized, unavailable, or insufficient, use targeted source
inspection and report the limitation. Default review statically inspects test
and gate definitions; it does not execute them without live-proof permission.

Line numbers drift. Pair `path:line` evidence with durable symbol, test, gate,
or manifest names. Detect material revision/working-tree drift before emitting
the verdict.
