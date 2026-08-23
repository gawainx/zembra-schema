PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

ALTER TABLE notes
ADD COLUMN role TEXT NOT NULL DEFAULT 'Human' CHECK (role IN ('Human', 'Agent'));

INSERT INTO schema_migrations (version, applied_at)
VALUES ('0.2.0', unixepoch());

COMMIT;
