# Supabase Platform Boundary

`migrations/supabase/` contains Supabase-specific migrations and bootstrap notes, including Auth-backed membership tables, RLS policies, Realtime settings, and storage policies.

Shared business schema belongs in `postgres/` and must use the same schema version as SQLite. Supabase platform configuration must not introduce business tables, fields, enum values, or version semantics that are independent from zembra-schema.

Version `0.6.0` defines `workspace_members` as the Supabase Auth relationship to `workspaces` and versions the RLS policies that depend on it. The only current role is `manager`.

## Upgrade an existing 0.5.0 database

Run only the SQL files in `migrations/supabase/` against Supabase. Files in `migrations/sqlite/` are SQLite migrations and use SQLite functions such as `unixepoch()`.

1. Apply `006_create_workspace_members.sql`. It immediately enables RLS on the membership table and reserves membership changes for the administrator.
2. Insert one or more manager rows for every existing workspace using the matching `auth.users.id` values.
3. Apply `007_enable_workspace_rls.sql`. Its preflight check stops the migration when a workspace has no manager.

Use an administrative SQL session for step 2:

```sql
SELECT id, email
FROM auth.users;

INSERT INTO public.workspace_members (workspace_id, user_id)
VALUES ('<existing-workspace-uuid>', '<manager-auth-user-uuid>');
```

Repeat the `INSERT` for every existing workspace. The `created_at` value and `manager` role use their schema defaults.

WebUI receives `SELECT` permission for the three sync tables and receives no write permission for them. Workspace creation and membership administration remain administrative operations outside WebUI.
