PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

CREATE TABLE schema_migrations (
    version TEXT PRIMARY KEY NOT NULL,
    applied_at INTEGER NOT NULL CHECK (applied_at >= 0)
);

CREATE TABLE fields (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL UNIQUE CHECK (length(trim(name)) > 0),
    created_at INTEGER NOT NULL CHECK (created_at >= 0)
);

CREATE TABLE tags (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL UNIQUE CHECK (length(trim(name)) > 0),
    created_at INTEGER NOT NULL CHECK (created_at >= 0)
);

CREATE TABLE devices (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
    platform TEXT NOT NULL CHECK (length(trim(platform)) > 0),
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    last_seen_at INTEGER CHECK (last_seen_at IS NULL OR last_seen_at >= 0)
);

CREATE TABLE notes (
    id TEXT PRIMARY KEY NOT NULL,
    content TEXT NOT NULL,
    field_id TEXT,
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    updated_at INTEGER NOT NULL CHECK (updated_at >= created_at),
    archived_at INTEGER CHECK (archived_at IS NULL OR archived_at >= created_at),
    deleted_at INTEGER CHECK (deleted_at IS NULL OR deleted_at >= created_at),
    current_revision_id TEXT,
    FOREIGN KEY (field_id) REFERENCES fields(id) ON UPDATE CASCADE ON DELETE SET NULL
);

CREATE TABLE note_tags (
    note_id TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    PRIMARY KEY (note_id, tag_id),
    FOREIGN KEY (note_id) REFERENCES notes(id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES tags(id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE note_links (
    id TEXT PRIMARY KEY NOT NULL,
    source_note_id TEXT NOT NULL,
    target_note_id TEXT NOT NULL,
    anchor_text TEXT,
    position INTEGER CHECK (position IS NULL OR position >= 0),
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    CHECK (source_note_id <> target_note_id),
    FOREIGN KEY (source_note_id) REFERENCES notes(id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (target_note_id) REFERENCES notes(id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE attachments (
    id TEXT PRIMARY KEY NOT NULL,
    note_id TEXT NOT NULL,
    file_name TEXT NOT NULL CHECK (length(trim(file_name)) > 0),
    mime_type TEXT NOT NULL CHECK (length(trim(mime_type)) > 0),
    storage_path TEXT NOT NULL CHECK (length(trim(storage_path)) > 0),
    size_bytes INTEGER NOT NULL CHECK (size_bytes >= 0),
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    FOREIGN KEY (note_id) REFERENCES notes(id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE note_revisions (
    id TEXT PRIMARY KEY NOT NULL,
    note_id TEXT NOT NULL,
    content TEXT NOT NULL,
    title TEXT,
    device_id TEXT,
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    FOREIGN KEY (note_id) REFERENCES notes(id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (device_id) REFERENCES devices(id) ON UPDATE CASCADE ON DELETE SET NULL
);

CREATE INDEX idx_notes_field_id ON notes(field_id);
CREATE INDEX idx_notes_created_at ON notes(created_at);
CREATE INDEX idx_notes_updated_at ON notes(updated_at);
CREATE INDEX idx_notes_archived_at ON notes(archived_at);
CREATE INDEX idx_notes_deleted_at ON notes(deleted_at);
CREATE INDEX idx_note_tags_tag_id ON note_tags(tag_id);
CREATE INDEX idx_note_links_source_note_id ON note_links(source_note_id);
CREATE INDEX idx_note_links_target_note_id ON note_links(target_note_id);
CREATE INDEX idx_attachments_note_id ON attachments(note_id);
CREATE INDEX idx_note_revisions_note_id_created_at ON note_revisions(note_id, created_at);
CREATE INDEX idx_note_revisions_device_id ON note_revisions(device_id);

INSERT INTO schema_migrations (version, applied_at)
VALUES ('0.1.0', unixepoch());

COMMIT;
