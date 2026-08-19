-- project-memory schema (plan 381 + plan 382's session-memory pass).
--
-- The 3-table shape (entities / relations / aliases), alias-seeded lookup and
-- recursive-CTE traversal are a PATTERN adapted from
-- github.com/Glitch-Cat-Club/graph-memory-starter (MIT licence). No code from
-- that repository is imported or vendored here; only the data model idea.
--
-- Ontology note (project-memory/QUESTIONS.md, "REQUIRED FIELDS ON EVERY FACT"):
-- every entity row must carry status + source_doc + source_commit + a date.
-- Those columns are therefore NOT NULL with no default: a fact that cannot say
-- where it came from is not allowed into the graph.
--
-- `updated_date` (plan 382) is the SOURCE's own last-modified date, which only
-- the memory pass can supply: a plan doc's date is its commit, already carried
-- by source_commit + built_at. The column is therefore nullable at the SQL
-- level so plan rows stay valid untouched, and "non-null for every MEMORY row"
-- is asserted in the contract suite (TC-382-01) instead. graph.db is
-- regenerable, so the schema evolves by rebuild -- there is no migration path
-- to keep working.

CREATE TABLE entities (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  etype         TEXT NOT NULL,
  status        TEXT NOT NULL,
  status_raw    TEXT NOT NULL,
  source_doc    TEXT NOT NULL,
  source_line   INTEGER NOT NULL,
  source_commit TEXT NOT NULL,
  updated_date  TEXT,
  built_at      TEXT NOT NULL
);

CREATE TABLE relations (
  src_id      TEXT NOT NULL,
  dst_id      TEXT NOT NULL,
  rtype       TEXT NOT NULL,
  source_doc  TEXT NOT NULL,
  source_line INTEGER NOT NULL,
  PRIMARY KEY (src_id, dst_id, rtype, source_doc, source_line)
);

CREATE TABLE aliases (
  alias     TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  PRIMARY KEY (alias, entity_id)
);

CREATE INDEX idx_aliases_alias ON aliases (alias);
CREATE INDEX idx_relations_src ON relations (src_id);
CREATE INDEX idx_relations_dst ON relations (dst_id);
CREATE INDEX idx_entities_etype ON entities (etype);
