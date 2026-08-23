BEGIN;

CREATE TABLE public.workspace_members (
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role text NOT NULL DEFAULT 'manager' CHECK (role = 'manager'),
    created_at bigint NOT NULL DEFAULT extract(epoch from now())::bigint CHECK (created_at >= 0),
    PRIMARY KEY (workspace_id, user_id),
    FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON UPDATE CASCADE ON DELETE CASCADE
);

COMMENT ON TABLE public.workspace_members IS 'Supabase Auth users authorized to access a workspace.';
COMMENT ON COLUMN public.workspace_members.workspace_id IS 'The workspace this membership authorizes.';
COMMENT ON COLUMN public.workspace_members.user_id IS 'The Supabase Auth user receiving workspace access.';
COMMENT ON COLUMN public.workspace_members.role IS 'The membership role. Version 0.6.0 permits manager only.';
COMMENT ON COLUMN public.workspace_members.created_at IS 'Unix timestamp in seconds when the membership was created.';

CREATE INDEX idx_workspace_members_user_workspace ON public.workspace_members(user_id, workspace_id);

ALTER TABLE public.workspace_members ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.workspace_members FROM anon, authenticated;

COMMIT;
