# Supabase Platform Boundary

`supabase/` is reserved for Supabase-specific platform configuration such as RLS policies, Realtime settings, storage policies, and project bootstrap notes.

Shared business schema belongs in `postgres/` and must use the same schema version as SQLite. Supabase platform configuration must not introduce business tables, fields, enum values, or version semantics that are independent from zembra-schema.

Current version `0.5.0` does not version RLS/Auth policies as part of the shared schema contract. If those policies become part of Zembra business semantics, they must be added through a future zembra-schema version.
