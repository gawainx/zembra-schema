PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS workspaces (
    id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(id)) > 0),
    workspace_name TEXT CHECK (workspace_name IS NULL OR length(trim(workspace_name)) > 0),
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    updated_at INTEGER NOT NULL CHECK (updated_at >= created_at),
    archived_at INTEGER CHECK (archived_at IS NULL OR archived_at >= created_at),
    deleted_at INTEGER CHECK (deleted_at IS NULL OR deleted_at >= created_at)
);

CREATE TABLE IF NOT EXISTS fields (
    id TEXT PRIMARY KEY NOT NULL,
    workspace_id TEXT NOT NULL,
    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    UNIQUE (workspace_id, id),
    UNIQUE (workspace_id, name),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS tags (
    id TEXT PRIMARY KEY NOT NULL,
    workspace_id TEXT NOT NULL,
    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
    parent_tag_id TEXT,
    path TEXT NOT NULL CHECK (length(trim(path)) > 0),
    depth INTEGER NOT NULL DEFAULT 0 CHECK (depth >= 0),
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    UNIQUE (workspace_id, id),
    UNIQUE (workspace_id, path),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (workspace_id, parent_tag_id) REFERENCES tags(workspace_id, id) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS devices (
    id TEXT PRIMARY KEY NOT NULL,
    workspace_id TEXT NOT NULL,
    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
    platform TEXT NOT NULL CHECK (length(trim(platform)) > 0),
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    last_seen_at INTEGER CHECK (last_seen_at IS NULL OR last_seen_at >= 0),
    sync_enabled INTEGER NOT NULL DEFAULT 1 CHECK (sync_enabled IN (0, 1)),
    last_synced_at INTEGER CHECK (last_synced_at IS NULL OR last_synced_at >= 0),
    UNIQUE (workspace_id, id),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS notes (
    id TEXT PRIMARY KEY NOT NULL,
    workspace_id TEXT NOT NULL,
    content TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'Human' CHECK (role IN ('Human', 'Agent')),
    field_id TEXT,
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    updated_at INTEGER NOT NULL CHECK (updated_at >= created_at),
    archived_at INTEGER CHECK (archived_at IS NULL OR archived_at >= created_at),
    deleted_at INTEGER CHECK (deleted_at IS NULL OR deleted_at >= created_at),
    current_revision_id TEXT,
    last_change_id TEXT,
    conflict_status TEXT NOT NULL DEFAULT 'none' CHECK (conflict_status IN ('none', 'auto_resolved', 'needs_review')),
    UNIQUE (workspace_id, id),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (workspace_id, field_id) REFERENCES fields(workspace_id, id) ON UPDATE CASCADE ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS note_tags (
    workspace_id TEXT NOT NULL,
    note_id TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    PRIMARY KEY (workspace_id, note_id, tag_id),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (workspace_id, note_id) REFERENCES notes(workspace_id, id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (workspace_id, tag_id) REFERENCES tags(workspace_id, id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS note_links (
    id TEXT PRIMARY KEY NOT NULL,
    workspace_id TEXT NOT NULL,
    source_note_id TEXT NOT NULL,
    target_note_id TEXT NOT NULL,
    anchor_text TEXT,
    position INTEGER CHECK (position IS NULL OR position >= 0),
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    CHECK (source_note_id <> target_note_id),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (workspace_id, source_note_id) REFERENCES notes(workspace_id, id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (workspace_id, target_note_id) REFERENCES notes(workspace_id, id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS attachments (
    id TEXT PRIMARY KEY NOT NULL,
    workspace_id TEXT NOT NULL,
    note_id TEXT NOT NULL,
    file_name TEXT NOT NULL CHECK (length(trim(file_name)) > 0),
    mime_type TEXT NOT NULL CHECK (length(trim(mime_type)) > 0),
    storage_path TEXT NOT NULL CHECK (length(trim(storage_path)) > 0),
    size_bytes INTEGER NOT NULL CHECK (size_bytes >= 0),
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (workspace_id, note_id) REFERENCES notes(workspace_id, id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS note_revisions (
    id TEXT PRIMARY KEY NOT NULL,
    workspace_id TEXT NOT NULL,
    note_id TEXT NOT NULL,
    content TEXT NOT NULL,
    title TEXT,
    device_id TEXT,
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    base_revision_id TEXT,
    change_id TEXT,
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (workspace_id, note_id) REFERENCES notes(workspace_id, id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (workspace_id, device_id) REFERENCES devices(workspace_id, id) ON UPDATE CASCADE ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS sync_changes (
    id TEXT PRIMARY KEY NOT NULL,
    workspace_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    entity_type TEXT NOT NULL CHECK (entity_type IN ('workspace', 'device', 'field', 'tag', 'note', 'note_revision', 'note_tag', 'note_link', 'attachment')),
    entity_id TEXT NOT NULL CHECK (length(trim(entity_id)) > 0),
    operation TEXT NOT NULL CHECK (operation IN ('insert', 'update', 'delete', 'restore', 'attach', 'detach')),
    base_revision_id TEXT,
    new_revision_id TEXT,
    payload TEXT NOT NULL CHECK (json_valid(payload)),
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    applied_at INTEGER CHECK (applied_at IS NULL OR applied_at >= 0),
    supabase_committed_at INTEGER CHECK (supabase_committed_at IS NULL OR supabase_committed_at >= 0),
    UNIQUE (workspace_id, device_id, id),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (workspace_id, device_id) REFERENCES devices(workspace_id, id) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS sync_state (
    workspace_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    scope TEXT NOT NULL CHECK (scope IN ('push', 'pull')),
    last_change_created_at INTEGER NOT NULL CHECK (last_change_created_at >= 0),
    last_change_id TEXT NOT NULL CHECK (length(trim(last_change_id)) > 0),
    last_success_at INTEGER CHECK (last_success_at IS NULL OR last_success_at >= 0),
    last_error_at INTEGER CHECK (last_error_at IS NULL OR last_error_at >= 0),
    last_error_message TEXT,
    PRIMARY KEY (workspace_id, device_id, scope),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (workspace_id, device_id) REFERENCES devices(workspace_id, id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS sync_conflicts (
    id TEXT PRIMARY KEY NOT NULL,
    workspace_id TEXT NOT NULL,
    entity_type TEXT NOT NULL CHECK (entity_type IN ('workspace', 'device', 'field', 'tag', 'note', 'note_revision', 'note_tag', 'note_link', 'attachment')),
    entity_id TEXT NOT NULL CHECK (length(trim(entity_id)) > 0),
    conflict_type TEXT NOT NULL CHECK (conflict_type IN ('concurrent_note_edit', 'delete_vs_update', 'relation_attach_vs_detach', 'schema_incompatible')),
    local_change_id TEXT,
    remote_change_id TEXT,
    local_revision_id TEXT,
    remote_revision_id TEXT,
    winning_revision_id TEXT,
    status TEXT NOT NULL CHECK (status IN ('open', 'auto_resolved', 'resolved', 'ignored')),
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    resolved_at INTEGER CHECK (resolved_at IS NULL OR resolved_at >= created_at),
    resolution_note TEXT,
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_workspaces_updated_at ON workspaces(updated_at);
CREATE INDEX IF NOT EXISTS idx_workspaces_deleted_at ON workspaces(deleted_at);
CREATE INDEX IF NOT EXISTS idx_fields_workspace_name ON fields(workspace_id, name);
CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_root_name_unique ON tags(workspace_id, name) WHERE parent_tag_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_child_name_unique ON tags(workspace_id, parent_tag_id, name) WHERE parent_tag_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tags_workspace_parent ON tags(workspace_id, parent_tag_id);
CREATE INDEX IF NOT EXISTS idx_tags_workspace_path ON tags(workspace_id, path);
CREATE INDEX IF NOT EXISTS idx_notes_workspace_field_id ON notes(workspace_id, field_id);
CREATE INDEX IF NOT EXISTS idx_notes_workspace_created_at ON notes(workspace_id, created_at);
CREATE INDEX IF NOT EXISTS idx_notes_workspace_updated_at ON notes(workspace_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_notes_workspace_archived_at ON notes(workspace_id, archived_at);
CREATE INDEX IF NOT EXISTS idx_notes_workspace_deleted_at ON notes(workspace_id, deleted_at);
CREATE INDEX IF NOT EXISTS idx_note_tags_workspace_tag_id ON note_tags(workspace_id, tag_id);
CREATE INDEX IF NOT EXISTS idx_note_links_workspace_source_note_id ON note_links(workspace_id, source_note_id);
CREATE INDEX IF NOT EXISTS idx_note_links_workspace_target_note_id ON note_links(workspace_id, target_note_id);
CREATE INDEX IF NOT EXISTS idx_attachments_workspace_note_id ON attachments(workspace_id, note_id);
CREATE INDEX IF NOT EXISTS idx_note_revisions_workspace_note_id_created_at ON note_revisions(workspace_id, note_id, created_at);
CREATE INDEX IF NOT EXISTS idx_note_revisions_workspace_device_id ON note_revisions(workspace_id, device_id);
CREATE INDEX IF NOT EXISTS idx_sync_changes_workspace_created ON sync_changes(workspace_id, created_at, id);
CREATE INDEX IF NOT EXISTS idx_sync_changes_workspace_device_created ON sync_changes(workspace_id, device_id, created_at, id);
CREATE INDEX IF NOT EXISTS idx_sync_changes_entity ON sync_changes(workspace_id, entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_sync_changes_revision ON sync_changes(workspace_id, entity_type, new_revision_id);
CREATE INDEX IF NOT EXISTS idx_sync_conflicts_workspace_status ON sync_conflicts(workspace_id, status, created_at);
CREATE INDEX IF NOT EXISTS idx_sync_conflicts_entity ON sync_conflicts(workspace_id, entity_type, entity_id);
