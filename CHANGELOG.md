# Changelog

## 0.2.0 - 2026-04-26

- Added immutable note creation role with `Human` and `Agent` enum values.
- Added migration `002_add_note_role.sql` to backfill existing notes as `Human`.
- Updated note JSON Schema and export schema version to `0.2.0`.

## 0.1.0 - 2026-04-26

- Added initial note schema design for notes, fields, tags, note tag links, note links, attachments, note revisions, and devices.
- Added SQLite DDL in `sqlite/001_initial_schema.sql`.
- Added initial migration script in `migrations/001_initial_schema.sql`.
- Added JSON Schema contracts in `json/*.schema.json`.
