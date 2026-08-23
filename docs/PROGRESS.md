# Progress

- (b7e9388) : 2026.08.23 为 Supabase `0.5.0` 既有数据增加 Auth 用户到 workspace 的正式成员关系，角色固定为 `manager`。采用先建成员表、由管理员回填各 workspace 成员、再启用 RLS 的两阶段迁移，保留原有数据。WebUI 可直接读写业务数据，只读同步表；workspace 创建与成员管理继续由受控管理操作负责。
- (0330e55) : 2026.08.23 将 SQLite 与 Supabase 的迁移统一收拢到 `migrations/sqlite/` 和 `migrations/supabase/`，保留通用 Postgres 当前 DDL。迁移说明明确 Supabase 只执行对应目录的 SQL，避免把 SQLite 的 `unixepoch()` 版本登记脚本提交给 Postgres。
