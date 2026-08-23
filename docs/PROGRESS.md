# Progress

- (b7e9388) : 2026.08.23 为 Supabase `0.5.0` 既有数据增加 Auth 用户到 workspace 的正式成员关系，角色固定为 `manager`。采用先建成员表、由管理员回填各 workspace 成员、再启用 RLS 的两阶段迁移，保留原有数据。WebUI 可直接读写业务数据，只读同步表；workspace 创建与成员管理继续由受控管理操作负责。
