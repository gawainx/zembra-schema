# Workspace Members 与 Supabase RLS 实现计划

**目标：** 让已部署到 Vercel 的 WebUI 通过 Supabase Auth 和 RLS 直接安全地消费既有 workspace 数据。

**架构：** `workspace_members` 位于 Supabase 专属目录，成员关系关联 `auth.users` 和 `public.workspaces`。成员角色固定为 `manager`。`0.6.0` 采用两阶段升级：先创建成员表并由管理员回填已有 workspace 的 manager，再启用 RLS 与权限策略。

## 任务

1. 记录需求澄清与迁移手册。验证：明确已有数据回填顺序和 WebUI 权限范围。

2. 新增 Supabase members 与 RLS migration。验证：SQL 语法检查和 RLS 策略覆盖全部 workspace 范围表。

3. 更新版本契约、JSON export、变更记录。验证：SQLite 迁移链到达 `0.6.0`，JSON 可解析。

4. 提交、追加进度记录、创建 `v0.6.0` tag 并推送。验证：工作区干净，远端包含提交与 tag。
