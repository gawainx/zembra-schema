# Hierarchical Tags 实现计划

> **给 Claude：** 必需工作流：使用 superpowers:executing-plans 逐任务实现此计划。

**目标：** 将 `tags` 从平铺标签升级为支持父子关系、路径和层级深度的结构化层级标签。

**相关设计文档：** 当前需求直接来自用户确认的结构性升级方向；同步背景参考 `note_schema.md` 和 `proposals/003-bidirectional-supabase-sync-schema.md`。

**架构：** 在 `tags` 表内使用邻接表模型，通过 `parent_tag_id` 表达父标签，通过 `path` 和 `depth` 支持唯一路径和快速展示。`note_tags` 继续关联叶子或任意层级标签的 `tag_id`，不改变笔记和标签的多对多关系。

**技术栈：** SQLite DDL/migration、JSON Schema draft 2020-12、Markdown schema 文档。

**范围 / 非范围：** 本次更新数据库 schema、迁移脚本、JSON Schema、导出版本、文档、CHANGELOG，并创建发布 commit/tag。不实现应用层 UI、标签解析器或同步客户端逻辑。

---

## Phase #1: Schema Contract

### Task #1: 更新当前 SQLite DDL

**状态：** Finished

**文件：**
- 修改：`sqlite/001_initial_schema.sql`

- 功能：为 `tags` 增加 `parent_tag_id`、`path`、`depth` 和层级唯一约束。
- 实现说明：保留 `tags.id` 主键与 `note_tags` 关系；新增复合自引用外键；新增根标签同名唯一、同父标签同名唯一、路径唯一索引。
- 预期验证结果：SQLite 能执行完整 DDL，`tags` 支持根标签和子标签插入。

### Task #2: 新增 v0.4.0 迁移

**状态：** Finished

**文件：**
- 创建：`migrations/004_add_hierarchical_tags.sql`

- 功能：把已有平铺标签迁移成层级标签。
- 实现说明：重建 `tags`；旧标签默认作为根标签迁移；若旧 `name` 包含 `/`，保留原 tag id 作为叶子节点，并按路径创建缺失父节点；插入 `schema_migrations` 版本 `0.4.0`。
- 预期验证结果：迁移后旧 `note_tags.tag_id` 仍指向原 tag id，根标签与拆分出的父标签满足唯一约束。

## Phase #2: JSON Schema And Docs

### Task #3: 更新 JSON Schema

**状态：** Finished

**文件：**
- 修改：`json/tag.schema.json`
- 修改：`json/zembra_note_export.schema.json`

- 功能：导出结构包含层级标签字段，并将导出版本升级到 `0.4.0`。
- 实现说明：`parent_tag_id` 可为 `string|null`；`path` 为非空字符串；`depth` 为非负整数。
- 预期验证结果：JSON Schema 能被解析，必填字段覆盖层级标签契约。

### Task #4: 更新文档和变更记录

**状态：** Finished

**文件：**
- 修改：`note_schema.md`
- 修改：`CHANGELOG.md`

- 功能：说明层级标签模型、迁移行为和版本变化。
- 实现说明：移除“第一版不做层级标签”的过期描述；记录 `migrations/004_add_hierarchical_tags.sql`。
- 预期验证结果：文档版本、目录产物和 tags 表说明一致。

## Phase #3: Verification And Release

### Task #5: 验证并发布

**状态：** Finished

**文件：**
- 验证：SQLite schema 和 migration
- 验证：JSON Schema 解析
- 发布：Git commit 和 tag

- 功能：确认 schema 可执行，迁移兼容，并发布版本。
- 实现说明：用临时 SQLite 数据库执行旧 schema、插入平铺标签和斜杠标签，再执行 002、003、004 迁移；用可用工具解析 JSON 文件；commit message 使用 `feat: add hierarchical tag schema`。
- 预期验证结果：命令 exit 0；创建 `v0.4.0` tag。
