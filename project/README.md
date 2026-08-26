# Mknoon project evidence model

This directory is the authored product contract. It describes what Mknoon is
expected to do and what evidence is required. It never contains a manually
maintained implementation flag.

The model keeps these authorities separate:

| Layer | Authority |
|---|---|
| Product contract | Intent, stable behavior IDs, trace anchors and proof policy |
| Repository source | The code artifacts that actually exist |
| Graphify | A revisioned index of implementation evidence candidates |
| Test declarations | The scenarios the project claims to exercise |
| Test run records | What passed, failed or was unavailable at an exact revision and target |
| Dashboard data | A generated reconciliation view; never an authored truth |

Graphify matches are reported as candidates, partial evidence or not evidenced.
A match is not automatically upgraded to “implemented,” and a miss is not
automatically called an implementation gap.

Each feature contract owns descriptive metadata, behaviors, explicit proof
mappings, revisioned test runs, optional implementation reviews and unresolved
product questions. Generated dashboard data may be deleted and rebuilt at any
time.

The project tool's built-in help lists the build, consistency-check and
test-result recording commands. Serve the repository with any local static
server and open the dashboard directory to inspect the generated view.
