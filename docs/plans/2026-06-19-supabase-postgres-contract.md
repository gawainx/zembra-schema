# Supabase/Postgres 统一 Schema 契约实现计划

> **给 Claude：** 必需工作流：使用 superpowers:executing-plans 逐任务实现此计划。

**目标：** 让 zembra-schema 同时发布 SQLite 与 Supabase/Postgres 的统一数据契约，并共用同一个 schema version。

**相关设计文档：** `docs/request-clarify/supabase-postgres-contract/2026-06-19.md`

**架构：** SQLite 保持现有 DDL 和迁移链，新增 `0.5.0` 登记迁移表达统一远端契约版本。Postgres 侧新增完整 DDL 与同编号 bootstrap migration，backend 只消费 zembra-schema 发布的 SQL/JSON/文档产物。

**技术栈：** SQLite SQL、Postgres SQL、JSON Schema draft 2020-12、Markdown。

**范围 / 非范围：** 本计划纳入 Postgres DDL/migration、JSON Schema 补齐、版本文档和验证；不实现 backend worker、Supabase 部署、RLS/Auth 正式策略或附件二进制同步。

---

## Phase #1: 需求与版本边界落盘

### Task #1: 保存需求澄清文档

**状态：** Finished

**文件：**
- 创建：`docs/request-clarify/supabase-postgres-contract/2026-06-19.md`

- 功能：记录已确认的统一 source of truth、统一版本、目录拆分和范围边界。
- 实现说明：只写用户已确认决策，不写待决策问题。
- 预期验证结果：文档能说明 backend 不能独立演化 Postgres 业务 schema。

### Task #2: 保存执行计划

**状态：** Finished

**文件：**
- 创建：`docs/plans/2026-06-19-supabase-postgres-contract.md`

- 功能：把改造拆成可验证任务。
- 实现说明：按当前仓库 Markdown 计划风格组织。
- 预期验证结果：计划包含文件、实现说明和验证策略。

## Phase #2: SQL 契约产物

### Task #3: 新增 Postgres 当前完整 DDL

**状态：** Finished

**文件：**
- 创建：`postgres/001_initial_schema.sql`

- 功能：提供从空 Postgres 库创建当前 `0.5.0` schema 的完整 DDL。
- 实现说明：使用 Postgres 类型映射：UUID workspace、text 业务 ID、bigint timestamp、jsonb payload、boolean sync flag。
- 预期验证结果：Postgres SQL 能通过 `psql --no-psqlrc --set ON_ERROR_STOP=1 --single-transaction --file postgres/001_initial_schema.sql` 执行。

### Task #4: 新增强绑定 migration

**状态：** Finished

**文件：**
- 创建：`migrations/sqlite/005_register_unified_postgres_contract.sql`
- 创建：`migrations/supabase/005_add_unified_schema_contract.sql`

- 功能：让 SQLite 与 Postgres 在 `0.5.0` 上拥有相同业务版本口径。
- 实现说明：SQLite 侧只登记版本；Postgres 侧作为远端空库 bootstrap migration。
- 预期验证结果：SQLite 迁移链执行后 `schema_migrations` 包含 `0.5.0`；Postgres migration 语法可执行。

## Phase #3: JSON Schema 与文档

### Task #5: 补齐 JSON Schema 契约

**状态：** Finished

**文件：**
- 修改：`json/*.schema.json`
- 创建：`json/workspace.schema.json`
- 创建：`json/sync_change.schema.json`
- 创建：`json/sync_state.schema.json`
- 创建：`json/sync_conflict.schema.json`

- 功能：让 JSON Schema 覆盖当前 SQLite/Postgres 共享业务对象和同步对象。
- 实现说明：所有 workspace-scoped 对象补 `workspace_id`；同步表按 SQLite DDL 中枚举和字段表达。
- 预期验证结果：所有 JSON 文件能被 JSON parser 解析，导出 schema version 更新到 `0.5.0`。

### Task #6: 更新说明和 changelog

**状态：** Finished

**文件：**
- 修改：`note_schema.md`
- 修改：`CHANGELOG.md`
- 创建：`supabase/README.md`

- 功能：记录 zembra-schema 的统一 source of truth 职责和 Supabase 平台配置边界。
- 实现说明：明确 `postgres/` 与 `supabase/` 的职责差异，说明 backend 消费边界。
- 预期验证结果：文档中能查到统一版本规则、目录产物和非范围。

## Phase #4: 验证

### Task #7: 执行契约验证

**状态：** Finished

**文件：**
- 验证：`migrations/sqlite/current_schema.sql`
- 验证：`migrations/*.sql`
- 验证：`json/*.schema.json`
- 验证：`postgres/*.sql`

- 功能：确认新增契约产物基本可用。
- 实现说明：运行 SQLite fresh-create、SQLite migration chain、JSON parse、Postgres SQL 语法检查；如果本机无 Postgres 客户端则说明未执行项。
- 预期验证结果：可运行检查通过；本机未安装 `psql`，Postgres 执行级验证未运行。
