INSERT INTO schema_migrations (version, applied_at)
VALUES ('0.6.0', extract(epoch from now())::bigint);
