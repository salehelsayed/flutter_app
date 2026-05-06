# Audit Ledger

One row per flow. The auditor reads this on entry, decides what to
audit / re-audit / skip, and writes back when done.

**Status values:**
- `not-yet-audited` — never audited (or you reset the row)
- `clean` — last audit found no breaks
- `open` — last audit found at least one finding still in `open` or
  `triaged` state
- `regressed` — agent confirmed a previously-fixed break is back
- `stale` — code changed since last audit; agent will re-audit on next run

| Flow                      | Last audited (SHA) | Last audited (date) | Status        | Findings file                                                            |
|---------------------------|--------------------|---------------------|---------------|--------------------------------------------------------------------------|
| notification-tap-to-route | 5fec83b3           | 2026-05-05          | open          | findings/notification-tap-to-route-2026-05-05.md (force re-audited 2026-05-05; SHA unchanged; fix in working tree, not committed) |
| post-photo-upload-to-feed | 5fec83b3           | 2026-05-05          | open          | findings/post-photo-upload-to-feed-2026-05-05.md (skipped — unchanged)   |
| deep-link-share-receive   | 5fec83b3           | 2026-05-05          | open          | findings/deep-link-share-receive-2026-05-05.md (skipped — unchanged)     |
