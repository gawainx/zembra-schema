BEGIN;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.workspaces AS workspace
        WHERE NOT EXISTS (
            SELECT 1
            FROM public.workspace_members AS member
            WHERE member.workspace_id = workspace.id
              AND member.role = 'manager'
        )
    ) THEN
        RAISE EXCEPTION 'Every workspace requires a manager membership before RLS can be enabled.';
    END IF;
END;
$$;

CREATE SCHEMA IF NOT EXISTS private;

CREATE FUNCTION private.managed_workspace_ids()
RETURNS uuid[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT coalesce(array_agg(member.workspace_id), ARRAY[]::uuid[])
    FROM public.workspace_members AS member
    WHERE member.user_id = (SELECT auth.uid())
      AND member.role = 'manager';
$$;

COMMENT ON FUNCTION private.managed_workspace_ids() IS 'Returns the workspace IDs that the authenticated user may access as a manager.';

REVOKE ALL ON FUNCTION private.managed_workspace_ids() FROM PUBLIC;
GRANT USAGE ON SCHEMA private TO authenticated;
GRANT EXECUTE ON FUNCTION private.managed_workspace_ids() TO authenticated;

REVOKE ALL ON TABLE public.workspaces, public.workspace_members, public.fields, public.tags, public.devices, public.notes, public.note_tags, public.note_links, public.attachments, public.note_revisions, public.sync_changes, public.sync_state, public.sync_conflicts FROM anon, authenticated;

GRANT SELECT, UPDATE ON TABLE public.workspaces TO authenticated;
GRANT SELECT ON TABLE public.workspace_members TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.fields, public.tags, public.devices, public.notes, public.note_tags, public.note_links, public.attachments, public.note_revisions TO authenticated;
GRANT SELECT ON TABLE public.sync_changes, public.sync_state, public.sync_conflicts TO authenticated;

ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fields ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.note_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.note_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.note_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_changes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_conflicts ENABLE ROW LEVEL SECURITY;

CREATE POLICY workspace_members_can_select_own_memberships
ON public.workspace_members
FOR SELECT
TO authenticated
USING (user_id = (SELECT auth.uid()));

CREATE POLICY managers_can_select_workspaces
ON public.workspaces
FOR SELECT
TO authenticated
USING (id = ANY((SELECT private.managed_workspace_ids())::uuid[]));

CREATE POLICY managers_can_update_workspaces
ON public.workspaces
FOR UPDATE
TO authenticated
USING (id = ANY((SELECT private.managed_workspace_ids())::uuid[]))
WITH CHECK (id = ANY((SELECT private.managed_workspace_ids())::uuid[]));

DO $$
DECLARE
    business_table text;
BEGIN
    FOREACH business_table IN ARRAY ARRAY['fields', 'tags', 'devices', 'notes', 'note_tags', 'note_links', 'attachments', 'note_revisions']
    LOOP
        EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (workspace_id = ANY((SELECT private.managed_workspace_ids())::uuid[]))', 'managers_can_select_' || business_table, business_table);
        EXECUTE format('CREATE POLICY %I ON public.%I FOR INSERT TO authenticated WITH CHECK (workspace_id = ANY((SELECT private.managed_workspace_ids())::uuid[]))', 'managers_can_insert_' || business_table, business_table);
        EXECUTE format('CREATE POLICY %I ON public.%I FOR UPDATE TO authenticated USING (workspace_id = ANY((SELECT private.managed_workspace_ids())::uuid[])) WITH CHECK (workspace_id = ANY((SELECT private.managed_workspace_ids())::uuid[]))', 'managers_can_update_' || business_table, business_table);
        EXECUTE format('CREATE POLICY %I ON public.%I FOR DELETE TO authenticated USING (workspace_id = ANY((SELECT private.managed_workspace_ids())::uuid[]))', 'managers_can_delete_' || business_table, business_table);
    END LOOP;
END;
$$;

DO $$
DECLARE
    sync_table text;
BEGIN
    FOREACH sync_table IN ARRAY ARRAY['sync_changes', 'sync_state', 'sync_conflicts']
    LOOP
        EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (workspace_id = ANY((SELECT private.managed_workspace_ids())::uuid[]))', 'managers_can_select_' || sync_table, sync_table);
    END LOOP;
END;
$$;

INSERT INTO public.schema_migrations (version, applied_at)
VALUES ('0.6.0', extract(epoch from now())::bigint)
ON CONFLICT (version) DO NOTHING;

COMMIT;
