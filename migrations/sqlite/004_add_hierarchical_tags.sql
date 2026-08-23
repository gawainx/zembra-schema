PRAGMA foreign_keys = OFF;

BEGIN TRANSACTION;

ALTER TABLE tags RENAME TO tags_flat;

CREATE TABLE tags (
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

WITH RECURSIVE
split_tags(original_id, workspace_id, full_path, created_at, rest, path, name, depth) AS (
    SELECT
        id,
        workspace_id,
        trim(name),
        created_at,
        trim(name) || '/',
        '',
        '',
        -1
    FROM tags_flat
    UNION ALL
    SELECT
        original_id,
        workspace_id,
        full_path,
        created_at,
        substr(rest, instr(rest, '/') + 1),
        CASE
            WHEN path = '' THEN substr(rest, 1, instr(rest, '/') - 1)
            ELSE path || '/' || substr(rest, 1, instr(rest, '/') - 1)
        END,
        substr(rest, 1, instr(rest, '/') - 1),
        depth + 1
    FROM split_tags
    WHERE rest <> ''
),
tag_nodes AS (
    SELECT
        workspace_id,
        path,
        name,
        depth,
        min(created_at) AS created_at
    FROM split_tags
    WHERE depth >= 0 AND length(trim(name)) > 0
    GROUP BY workspace_id, path, name, depth
),
tag_ids AS (
    SELECT
        tag_nodes.workspace_id,
        tag_nodes.path,
        coalesce(tags_flat.id, 'generated-parent:' || tag_nodes.workspace_id || ':' || tag_nodes.path) AS id
    FROM tag_nodes
    LEFT JOIN tags_flat
        ON tags_flat.workspace_id = tag_nodes.workspace_id
        AND trim(tags_flat.name) = tag_nodes.path
)
INSERT INTO tags (id, workspace_id, name, parent_tag_id, path, depth, created_at)
SELECT
    tag_ids.id,
    tag_nodes.workspace_id,
    tag_nodes.name,
    CASE
        WHEN tag_nodes.depth = 0 THEN NULL
        ELSE parent_ids.id
    END,
    tag_nodes.path,
    tag_nodes.depth,
    tag_nodes.created_at
FROM tag_nodes
JOIN tag_ids
    ON tag_ids.workspace_id = tag_nodes.workspace_id
    AND tag_ids.path = tag_nodes.path
LEFT JOIN tag_ids AS parent_ids
    ON parent_ids.workspace_id = tag_nodes.workspace_id
    AND parent_ids.path = substr(tag_nodes.path, 1, length(tag_nodes.path) - length(tag_nodes.name) - 1)
ORDER BY tag_nodes.depth, tag_nodes.path;

CREATE TABLE note_tags_new (
    workspace_id TEXT NOT NULL,
    note_id TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    created_at INTEGER NOT NULL CHECK (created_at >= 0),
    PRIMARY KEY (workspace_id, note_id, tag_id),
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (workspace_id, note_id) REFERENCES notes(workspace_id, id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (workspace_id, tag_id) REFERENCES tags(workspace_id, id) ON UPDATE CASCADE ON DELETE CASCADE
);

INSERT INTO note_tags_new (workspace_id, note_id, tag_id, created_at)
SELECT workspace_id, note_id, tag_id, created_at FROM note_tags;

DROP TABLE note_tags;
ALTER TABLE note_tags_new RENAME TO note_tags;

DROP TABLE tags_flat;

CREATE UNIQUE INDEX idx_tags_root_name_unique ON tags(workspace_id, name) WHERE parent_tag_id IS NULL;
CREATE UNIQUE INDEX idx_tags_child_name_unique ON tags(workspace_id, parent_tag_id, name) WHERE parent_tag_id IS NOT NULL;
CREATE INDEX idx_tags_workspace_parent ON tags(workspace_id, parent_tag_id);
CREATE INDEX idx_tags_workspace_path ON tags(workspace_id, path);
CREATE INDEX idx_note_tags_workspace_tag_id ON note_tags(workspace_id, tag_id);

INSERT INTO schema_migrations (version, applied_at)
VALUES ('0.4.0', unixepoch());

PRAGMA foreign_key_check;

COMMIT;

PRAGMA foreign_keys = ON;
