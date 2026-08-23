BEGIN;

CREATE TABLE schema_migrations (
    version text PRIMARY KEY NOT NULL,
    applied_at bigint NOT NULL
);

CREATE TABLE workspaces (
    id uuid PRIMARY KEY NOT NULL,
    workspace_name text CHECK (workspace_name IS NULL OR length(btrim(workspace_name)) > 0),
    created_at bigint NOT NULL CHECK (created_at >= 0),
    updated_at bigint NOT NULL CHECK (updated_at >= created_at),
    archived_at bigint CHECK (archived_at IS NULL OR archived_at >= created_at),
    deleted_at bigint CHECK (deleted_at IS NULL OR deleted_at >= created_at)
);

CREATE TABLE fields (
    id text PRIMARY KEY NOT NULL,
    workspace_id uuid NOT NULL,
    name text NOT NULL CHECK (length(btrim(name)) > 0),
    created_at bigint NOT NULL CHECK (created_at >= 0),
    UNIQUE (workspace_id, id),
    UNIQUE (workspace_id, name),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE tags (
    id text PRIMARY KEY NOT NULL,
    workspace_id uuid NOT NULL,
    name text NOT NULL CHECK (length(btrim(name)) > 0),
    parent_tag_id text,
    path text NOT NULL CHECK (length(btrim(path)) > 0),
    depth integer NOT NULL DEFAULT 0 CHECK (depth >= 0),
    created_at bigint NOT NULL CHECK (created_at >= 0),
    UNIQUE (workspace_id, id),
    UNIQUE (workspace_id, path),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (workspace_id, parent_tag_id) REFERENCES tags(workspace_id, id) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE devices (
    id text PRIMARY KEY NOT NULL,
    workspace_id uuid NOT NULL,
    name text NOT NULL CHECK (length(btrim(name)) > 0),
    platform text NOT NULL CHECK (length(btrim(platform)) > 0),
    created_at bigint NOT NULL CHECK (created_at >= 0),
    last_seen_at bigint CHECK (last_seen_at IS NULL OR last_seen_at >= 0),
    sync_enabled boolean NOT NULL DEFAULT true,
    last_synced_at bigint CHECK (last_synced_at IS NULL OR last_synced_at >= 0),
    UNIQUE (workspace_id, id),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE notes (
    id text PRIMARY KEY NOT NULL,
    workspace_id uuid NOT NULL,
    content text NOT NULL,
    role text NOT NULL DEFAULT 'Human' CHECK (role IN ('Human', 'Agent')),
    field_id text,
    created_at bigint NOT NULL CHECK (created_at >= 0),
    updated_at bigint NOT NULL CHECK (updated_at >= created_at),
    archived_at bigint CHECK (archived_at IS NULL OR archived_at >= created_at),
    deleted_at bigint CHECK (deleted_at IS NULL OR deleted_at >= created_at),
    current_revision_id text,
    last_change_id text,
    conflict_status text NOT NULL DEFAULT 'none' CHECK (conflict_status IN ('none', 'auto_resolved', 'needs_review')),
    UNIQUE (workspace_id, id),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (workspace_id, field_id) REFERENCES fields(workspace_id, id) ON UPDATE CASCADE ON DELETE SET NULL
);

CREATE TABLE note_tags (
    workspace_id uuid NOT NULL,
    note_id text NOT NULL,
    tag_id text NOT NULL,
    created_at bigint NOT NULL CHECK (created_at >= 0),
    PRIMARY KEY (workspace_id, note_id, tag_id),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (workspace_id, note_id) REFERENCES notes(workspace_id, id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (workspace_id, tag_id) REFERENCES tags(workspace_id, id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE note_links (
    id text PRIMARY KEY NOT NULL,
    workspace_id uuid NOT NULL,
    source_note_id text NOT NULL,
    target_note_id text NOT NULL,
    anchor_text text,
    position integer CHECK (position IS NULL OR position >= 0),
    created_at bigint NOT NULL CHECK (created_at >= 0),
    CHECK (source_note_id <> target_note_id),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (workspace_id, source_note_id) REFERENCES notes(workspace_id, id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (workspace_id, target_note_id) REFERENCES notes(workspace_id, id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE attachments (
    id text PRIMARY KEY NOT NULL,
    workspace_id uuid NOT NULL,
    note_id text NOT NULL,
    file_name text NOT NULL CHECK (length(btrim(file_name)) > 0),
    mime_type text NOT NULL CHECK (length(btrim(mime_type)) > 0),
    storage_path text NOT NULL CHECK (length(btrim(storage_path)) > 0),
    size_bytes bigint NOT NULL CHECK (size_bytes >= 0),
    created_at bigint NOT NULL CHECK (created_at >= 0),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (workspace_id, note_id) REFERENCES notes(workspace_id, id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE note_revisions (
    id text PRIMARY KEY NOT NULL,
    workspace_id uuid NOT NULL,
    note_id text NOT NULL,
    content text NOT NULL,
    title text,
    device_id text,
    created_at bigint NOT NULL CHECK (created_at >= 0),
    base_revision_id text,
    change_id text,
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (workspace_id, note_id) REFERENCES notes(workspace_id, id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (workspace_id, device_id) REFERENCES devices(workspace_id, id) ON UPDATE CASCADE ON DELETE SET NULL
);

CREATE TABLE sync_changes (
    id text PRIMARY KEY NOT NULL,
    workspace_id uuid NOT NULL,
    device_id text NOT NULL,
    entity_type text NOT NULL CHECK (entity_type IN ('workspace', 'device', 'field', 'tag', 'note', 'note_revision', 'note_tag', 'note_link', 'attachment')),
    entity_id text NOT NULL CHECK (length(btrim(entity_id)) > 0),
    operation text NOT NULL CHECK (operation IN ('insert', 'update', 'delete', 'restore', 'attach', 'detach')),
    base_revision_id text,
    new_revision_id text,
    payload jsonb NOT NULL,
    created_at bigint NOT NULL CHECK (created_at >= 0),
    applied_at bigint CHECK (applied_at IS NULL OR applied_at >= 0),
    supabase_committed_at bigint CHECK (supabase_committed_at IS NULL OR supabase_committed_at >= 0),
    UNIQUE (workspace_id, device_id, id),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (workspace_id, device_id) REFERENCES devices(workspace_id, id) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE sync_state (
    workspace_id uuid NOT NULL,
    device_id text NOT NULL,
    scope text NOT NULL CHECK (scope IN ('push', 'pull')),
    last_change_created_at bigint NOT NULL CHECK (last_change_created_at >= 0),
    last_change_id text NOT NULL CHECK (length(btrim(last_change_id)) > 0),
    last_success_at bigint CHECK (last_success_at IS NULL OR last_success_at >= 0),
    last_error_at bigint CHECK (last_error_at IS NULL OR last_error_at >= 0),
    last_error_message text,
    PRIMARY KEY (workspace_id, device_id, scope),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (workspace_id, device_id) REFERENCES devices(workspace_id, id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE sync_conflicts (
    id text PRIMARY KEY NOT NULL,
    workspace_id uuid NOT NULL,
    entity_type text NOT NULL CHECK (entity_type IN ('workspace', 'device', 'field', 'tag', 'note', 'note_revision', 'note_tag', 'note_link', 'attachment')),
    entity_id text NOT NULL CHECK (length(btrim(entity_id)) > 0),
    conflict_type text NOT NULL CHECK (conflict_type IN ('concurrent_note_edit', 'delete_vs_update', 'relation_attach_vs_detach', 'schema_incompatible')),
    local_change_id text,
    remote_change_id text,
    local_revision_id text,
    remote_revision_id text,
    winning_revision_id text,
    status text NOT NULL CHECK (status IN ('open', 'auto_resolved', 'resolved', 'ignored')),
    created_at bigint NOT NULL CHECK (created_at >= 0),
    resolved_at bigint CHECK (resolved_at IS NULL OR resolved_at >= created_at),
    resolution_note text,
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE INDEX idx_workspaces_updated_at ON workspaces(updated_at);
CREATE INDEX idx_workspaces_deleted_at ON workspaces(deleted_at);
CREATE INDEX idx_fields_workspace_name ON fields(workspace_id, name);
CREATE UNIQUE INDEX idx_tags_root_name_unique ON tags(workspace_id, name) WHERE parent_tag_id IS NULL;
CREATE UNIQUE INDEX idx_tags_child_name_unique ON tags(workspace_id, parent_tag_id, name) WHERE parent_tag_id IS NOT NULL;
CREATE INDEX idx_tags_workspace_parent ON tags(workspace_id, parent_tag_id);
CREATE INDEX idx_tags_workspace_path ON tags(workspace_id, path);
CREATE INDEX idx_notes_workspace_field_id ON notes(workspace_id, field_id);
CREATE INDEX idx_notes_workspace_created_at ON notes(workspace_id, created_at);
CREATE INDEX idx_notes_workspace_updated_at ON notes(workspace_id, updated_at);
CREATE INDEX idx_notes_workspace_archived_at ON notes(workspace_id, archived_at);
CREATE INDEX idx_notes_workspace_deleted_at ON notes(workspace_id, deleted_at);
CREATE INDEX idx_note_tags_workspace_tag_id ON note_tags(workspace_id, tag_id);
CREATE INDEX idx_note_links_workspace_source_note_id ON note_links(workspace_id, source_note_id);
CREATE INDEX idx_note_links_workspace_target_note_id ON note_links(workspace_id, target_note_id);
CREATE INDEX idx_attachments_workspace_note_id ON attachments(workspace_id, note_id);
CREATE INDEX idx_note_revisions_workspace_note_id_created_at ON note_revisions(workspace_id, note_id, created_at);
CREATE INDEX idx_note_revisions_workspace_device_id ON note_revisions(workspace_id, device_id);
CREATE INDEX idx_sync_changes_workspace_created ON sync_changes(workspace_id, created_at, id);
CREATE INDEX idx_sync_changes_workspace_device_created ON sync_changes(workspace_id, device_id, created_at, id);
CREATE INDEX idx_sync_changes_entity ON sync_changes(workspace_id, entity_type, entity_id);
CREATE INDEX idx_sync_changes_revision ON sync_changes(workspace_id, entity_type, new_revision_id);
CREATE INDEX idx_sync_conflicts_workspace_status ON sync_conflicts(workspace_id, status, created_at);
CREATE INDEX idx_sync_conflicts_entity ON sync_conflicts(workspace_id, entity_type, entity_id);

INSERT INTO schema_migrations (version, applied_at)
VALUES ('0.6.0', extract(epoch from now())::bigint);

COMMIT;
