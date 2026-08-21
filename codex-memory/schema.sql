PRAGMA journal_mode = DELETE;
PRAGMA synchronous = FULL;

CREATE TABLE metadata (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE entities (
  id             TEXT PRIMARY KEY,
  name           TEXT NOT NULL,
  etype          TEXT NOT NULL,
  status         TEXT NOT NULL,
  status_raw     TEXT NOT NULL,
  body           TEXT NOT NULL,
  source_doc     TEXT NOT NULL,
  source_line    INTEGER NOT NULL,
  source_end_line INTEGER NOT NULL,
  source_commit  TEXT NOT NULL,
  source_sha256  TEXT NOT NULL,
  source_name    TEXT NOT NULL,
  priority       INTEGER NOT NULL,
  updated_date   TEXT,
  built_at       TEXT NOT NULL
);

CREATE TABLE relations (
  src_id         TEXT NOT NULL,
  dst_id         TEXT NOT NULL,
  rtype          TEXT NOT NULL,
  source_doc     TEXT NOT NULL,
  source_line    INTEGER NOT NULL,
  source_commit  TEXT NOT NULL,
  PRIMARY KEY (src_id, dst_id, rtype, source_doc, source_line)
);

CREATE TABLE aliases (
  alias     TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  weight    INTEGER NOT NULL,
  PRIMARY KEY (alias, entity_id)
);

CREATE VIRTUAL TABLE entity_fts USING fts5(
  entity_id UNINDEXED,
  name,
  body,
  source_doc,
  tokenize = 'unicode61 remove_diacritics 2'
);

CREATE INDEX idx_aliases_alias ON aliases (alias);
CREATE INDEX idx_relations_src ON relations (src_id);
CREATE INDEX idx_relations_dst ON relations (dst_id);
CREATE INDEX idx_entities_etype ON entities (etype);
CREATE INDEX idx_entities_source_doc ON entities (source_doc);
CREATE INDEX idx_entities_source_name ON entities (source_name);
