# Zembra Note Schema

本包定义 Zembra 笔记软件的统一数据契约。当前版本为 `0.6.0`，目标是覆盖面向人类和 Agent 的个人笔记应用核心对象，并让本地 SQLite 与 Supabase/Postgres 远端同步协调层共用同一个业务语义、schema version 和迁移演化路径。

## 设计原则

- 笔记正文使用轻量 Markdown 文本，正文中可以包含 `@field`、`#tag` 和双链文本。
- 一条笔记最多归属一个 Field，可以拥有多个 Tag。
- 双链关系独立存储，正文保留原始文本，关系表用于查询和跳转。
- 删除和归档使用时间戳表达，保留本地恢复和同步扩展空间。
- 版本历史先存完整快照，避免第一版引入 diff 复杂度。
- 所有业务表通过 `workspace_id` 归属 workspace，跨 workspace 允许同名 field 和 tag。
- 双向同步通过 `sync_changes` 交换可重放变更，通过 `sync_state` 记录游标，通过 `sync_conflicts` 记录需要处理的冲突。
- 时间统一使用 Unix timestamp，单位由应用层保持一致。
- ID 使用 `TEXT`，推荐 ULID 或 UUID，创建后不可变。
- SQLite 与 Supabase/Postgres 共用同一个 schema version；数据库类型差异只能表达存储实现差异，不能表达独立业务语义。
- backend 仓库只能消费本仓库发布的 schema 产物，不能独立维护 Postgres 业务 schema 或独立版本体系。

## 目录产物

- `note_schema.md`：人读的统一数据契约说明。
- `sqlite/001_initial_schema.sql`：SQLite 当前完整 DDL。
- `migrations/001_initial_schema.sql`：v0.1.0 初始迁移脚本。
- `migrations/002_add_note_role.sql`：v0.2.0 role 迁移脚本。
- `migrations/003_add_bidirectional_sync.sql`：v0.3.0 workspace 和同步迁移脚本。
- `migrations/004_add_hierarchical_tags.sql`：v0.4.0 层级标签迁移脚本。
- `migrations/005_register_unified_postgres_contract.sql`：v0.5.0 统一 Postgres 契约版本登记脚本。
- `postgres/001_initial_schema.sql`：Postgres 当前完整 DDL。
- `postgres/migrations/005_add_unified_schema_contract.sql`：v0.5.0 Postgres bootstrap migration。
- `migrations/006_register_workspace_members_rls_contract.sql`：v0.6.0 SQLite 契约版本登记脚本。
- `postgres/migrations/006_register_workspace_members_rls_contract.sql`：v0.6.0 Postgres 契约版本登记脚本。
- `supabase/migrations/006_create_workspace_members.sql`：v0.6.0 Supabase Auth 成员关系迁移。
- `supabase/migrations/007_enable_workspace_rls.sql`：v0.6.0 RLS、权限和策略迁移。
- `supabase/README.md`：Supabase 平台配置边界说明。
- `CHANGELOG.md`：schema 变更记录。

## 统一版本规则

SQLite、Postgres、JSON Schema 和人读文档共用同一个 schema version。当前版本 `0.6.0` 表示：

| 产物 | 版本口径 |
| --- | --- |
| SQLite | `schema_migrations.version = '0.6.0'` |
| Postgres | `schema_migrations.version = '0.6.0'` |
| JSON Schema export | `schema_version = '0.6.0'` |
| 文档 | 本文件和 `CHANGELOG.md` 的 `0.6.0` 条目 |

SQLite 与 Postgres migration 编号强绑定。某个版本只要改变共享业务契约，就必须同时评估两端产物是否需要同编号 migration。若一端没有结构变化，也要用登记迁移或文档记录说明该端版本如何进入同一口径。

仓库根目录的 `migrations/` 只用于 SQLite，不能在 Supabase SQL Editor 执行。Supabase 项目只执行 `supabase/migrations/` 中的 SQL；通用 Postgres 版本登记使用 `postgres/migrations/`。

## SQLite 与 Postgres 映射

| 语义 | SQLite | Postgres |
| --- | --- | --- |
| workspace ID | `TEXT` UUID 字符串 | `uuid` |
| 其他业务 ID | `TEXT` | `text` |
| Unix timestamp | `INTEGER` | `bigint` |
| JSON payload | `TEXT CHECK (json_valid(payload))` | `jsonb` |
| boolean | `INTEGER CHECK(value IN (0, 1))` | `boolean` |

类型映射不改变业务语义。字段名称、枚举值、必填性、软删除规则、workspace 隔离语义和同步收敛语义必须由本仓库统一定义。

## Supabase/Postgres 边界

`postgres/` 存放通用 Postgres DDL 和 migrations，是远端业务 schema 的正式契约来源。`supabase/` 存放依赖 Supabase Auth 的成员关系、RLS、Realtime、policy 和 project setting 等平台专属配置。

`workspace_members` 是 Supabase Auth 用户与 workspace 的正式关系。当前成员角色固定为 `manager`。WebUI 通过该关系读取和编辑 workspace 业务数据，且只读取同步表。RLS/Auth policy 自 `0.6.0` 起纳入统一 schema version。

## `workspaces` 工作区表

`workspaces` 是同步隔离边界。一套 workspace 内的 note、field、tag、device、revision 和同步日志共同收敛。

| 字段名 | 类型 | 含义 | 约束信息 |
| --- | --- | --- | --- |
| `id` | `TEXT` | workspace 唯一 ID | 主键；必填；使用 UUID 字符串 |
| `workspace_name` | `TEXT` | 可选显示名 | 可为空；为空时应用层展示 `id` |
| `created_at` | `INTEGER` | 创建时间 | 必填；Unix timestamp |
| `updated_at` | `INTEGER` | 更新时间 | 必填；不能早于 `created_at` |
| `archived_at` | `INTEGER` | 归档时间 | 可为空 |
| `deleted_at` | `INTEGER` | 软删除时间 | 可为空 |

## `notes` 笔记表

`notes` 是中心表，保存笔记正文、领域归属、生命周期状态和当前版本引用。

| 字段名 | 类型 | 含义 | 约束信息 |
| --- | --- | --- | --- |
| `id` | `TEXT` | 笔记唯一 ID | 主键；必填；建议 ULID/UUID；创建后不可变 |
| `workspace_id` | `TEXT` | 所属 workspace | 必填；外键引用 `workspaces.id` |
| `content` | `TEXT` | 笔记正文 | 必填；承载纯文本、轻 Markdown、`@field`、`#tag`、双链文本 |
| `role` | `TEXT` | 笔记创建角色 | 必填；固定为 `Human` 或 `Agent`；创建后不可变；旧数据默认 `Human` |
| `field_id` | `TEXT` | 所属领域 ID | 可选；外键引用 `fields.id`；一条笔记最多一个 field |
| `created_at` | `INTEGER` | 创建时间 | 必填；Unix timestamp |
| `updated_at` | `INTEGER` | 最近更新时间 | 必填；Unix timestamp |
| `archived_at` | `INTEGER` | 归档时间 | 可为空；为空表示未归档 |
| `deleted_at` | `INTEGER` | 软删除时间 | 可为空；为空表示未删除 |
| `current_revision_id` | `TEXT` | 当前版本 ID | 可为空；逻辑引用 `note_revisions.id` |
| `last_change_id` | `TEXT` | 最近一次影响当前状态的同步变更 | 可为空；逻辑引用 `sync_changes.id` |
| `conflict_status` | `TEXT` | 当前冲突状态 | 必填；固定为 `none`、`auto_resolved` 或 `needs_review` |

`role` 只记录笔记创建时的角色来源，不表达当前编辑者，也不随版本历史变化。应用层应将其视为创建后不可修改字段。

## `fields` 领域表

`fields` 表达笔记可归属的领域单位，对应用户输入的 `@field`。

| 字段名 | 类型 | 含义 | 约束信息 |
| --- | --- | --- | --- |
| `id` | `TEXT` | field 唯一 ID | 主键；必填；创建后不可变 |
| `workspace_id` | `TEXT` | 所属 workspace | 必填；外键引用 `workspaces.id` |
| `name` | `TEXT` | field 名称 | 必填；在同一 workspace 内唯一 |
| `created_at` | `INTEGER` | 创建时间 | 必填；Unix timestamp |

## `tags` 标签表

`tags` 表达结构化层级标签。根标签的 `parent_tag_id` 为空，子标签通过 `parent_tag_id` 指向父标签，`path` 保存完整标签路径，`depth` 保存从根标签开始的层级深度。

| 字段名 | 类型 | 含义 | 约束信息 |
| --- | --- | --- | --- |
| `id` | `TEXT` | 标签唯一 ID | 主键；必填；创建后不可变 |
| `workspace_id` | `TEXT` | 所属 workspace | 必填；外键引用 `workspaces.id` |
| `name` | `TEXT` | 当前层级内的标签名 | 必填；同一 workspace 的根标签内唯一；同一父标签下唯一 |
| `parent_tag_id` | `TEXT` | 父标签 ID | 可为空；为空表示根标签；外键引用 `tags.id` |
| `path` | `TEXT` | 完整标签路径 | 必填；在同一 workspace 内唯一，例如 `books/hands-on-python` |
| `depth` | `INTEGER` | 标签深度 | 必填；根标签为 `0`，子标签依次递增 |
| `created_at` | `INTEGER` | 创建时间 | 必填；Unix timestamp |

层级标签使用邻接表模型。`note_tags.tag_id` 可以关联任意层级的标签；如果业务只允许笔记关联叶子标签，该约束由应用层执行。标签重命名时需要同步更新自身和后代的 `path`。

## `note_tags` 笔记标签关联表

`note_tags` 只表达笔记和标签的多对多关系。标签名称变更时，只修改 `tags.name`，不用改笔记正文。

| 字段名 | 类型 | 含义 | 约束信息 |
| --- | --- | --- | --- |
| `workspace_id` | `TEXT` | 所属 workspace | 必填；参与联合主键 |
| `note_id` | `TEXT` | 笔记 ID | 必填；外键引用 `notes.id` |
| `tag_id` | `TEXT` | 标签 ID | 必填；外键引用 `tags.id` |
| `created_at` | `INTEGER` | 关联创建时间 | 必填；Unix timestamp |

联合约束：`PRIMARY KEY(workspace_id, note_id, tag_id)`。

## `note_links` 双向链接表

`note_links` 记录正文中的笔记引用。关系查询时可以同时按 `source_note_id` 和 `target_note_id` 建索引实现正向链接和反向链接。

| 字段名 | 类型 | 含义 | 约束信息 |
| --- | --- | --- | --- |
| `id` | `TEXT` | 链接记录 ID | 主键；必填 |
| `workspace_id` | `TEXT` | 所属 workspace | 必填；外键引用 `workspaces.id` |
| `source_note_id` | `TEXT` | 发起引用的笔记 | 必填；外键引用 `notes.id` |
| `target_note_id` | `TEXT` | 被引用的笔记 | 必填；外键引用 `notes.id` |
| `anchor_text` | `TEXT` | 正文中的链接文本 | 可为空 |
| `position` | `INTEGER` | 链接在正文中的位置 | 可为空；用于跳转定位 |
| `created_at` | `INTEGER` | 链接创建时间 | 必填；Unix timestamp |

约束：`source_note_id != target_note_id`。同一对笔记可以存在多次链接，所以不对 `(source_note_id, target_note_id)` 建唯一约束。

## `attachments` 附件表

`attachments` 记录笔记本地附件。第一版只保存本地路径，不做云端 URL、缩略图缓存和 OCR 文本字段。

| 字段名 | 类型 | 含义 | 约束信息 |
| --- | --- | --- | --- |
| `id` | `TEXT` | 附件唯一 ID | 主键；必填 |
| `workspace_id` | `TEXT` | 所属 workspace | 必填；外键引用 `workspaces.id` |
| `note_id` | `TEXT` | 所属笔记 ID | 必填；外键引用 `notes.id` |
| `file_name` | `TEXT` | 原始文件名 | 必填 |
| `mime_type` | `TEXT` | 文件类型 | 必填，例如 `image/png`、`application/pdf` |
| `storage_path` | `TEXT` | 本地存储路径 | 必填；相对路径优先 |
| `size_bytes` | `INTEGER` | 文件大小 | 必填；大于等于 0 |
| `created_at` | `INTEGER` | 添加时间 | 必填；Unix timestamp |

## `note_revisions` 笔记版本表

`note_revisions` 保存笔记正文完整快照，用于历史查看和恢复。

| 字段名 | 类型 | 含义 | 约束信息 |
| --- | --- | --- | --- |
| `id` | `TEXT` | 版本唯一 ID | 主键；必填 |
| `workspace_id` | `TEXT` | 所属 workspace | 必填；外键引用 `workspaces.id` |
| `note_id` | `TEXT` | 所属笔记 ID | 必填；外键引用 `notes.id` |
| `content` | `TEXT` | 该版本正文快照 | 必填 |
| `title` | `TEXT` | 该版本标题快照 | 可为空 |
| `device_id` | `TEXT` | 修改来源设备 | 可为空；外键引用 `devices.id` |
| `created_at` | `INTEGER` | 版本创建时间 | 必填；Unix timestamp |
| `base_revision_id` | `TEXT` | 当前版本基于的版本 | 可为空；用于并发编辑判断 |
| `change_id` | `TEXT` | 产生该版本的同步变更 | 可为空；逻辑引用 `sync_changes.id` |

## `devices` 设备表

`devices` 记录本地设备身份。即使第一版只做本地应用，也保留该表，方便版本历史和后续多端同步。

| 字段名 | 类型 | 含义 | 约束信息 |
| --- | --- | --- | --- |
| `id` | `TEXT` | 设备唯一 ID | 主键；必填；本地生成后保持稳定 |
| `workspace_id` | `TEXT` | 所属 workspace | 必填；外键引用 `workspaces.id` |
| `name` | `TEXT` | 设备名称 | 必填，例如 `Jagd MacBook` |
| `platform` | `TEXT` | 设备平台 | 必填，例如 `macos`、`ios`、`windows` |
| `created_at` | `INTEGER` | 首次登记时间 | 必填；Unix timestamp |
| `last_seen_at` | `INTEGER` | 最近使用时间 | 可为空；Unix timestamp |
| `sync_enabled` | `INTEGER` | 是否参与同步 | 必填；`0` 或 `1` |
| `last_synced_at` | `INTEGER` | 最近成功同步时间 | 可为空；Unix timestamp |

## 同步表

`sync_changes` 保存可重放变更，字段包括 `workspace_id`、`device_id`、`entity_type`、`entity_id`、`operation`、revision 引用、JSON 文本载荷和同步时间戳。

`sync_state` 以 `(workspace_id, device_id, scope)` 为主键保存 push/pull 游标，使用 `(last_change_created_at, last_change_id)` 避免同一秒多条 change 漏拉。

`sync_conflicts` 保存自动收敛或需要用户处理的冲突，覆盖并发 note 编辑、删除与更新冲突、关系 attach/detach 冲突和 schema 不兼容。

## 最小关系汇总

| 关系 | 表达方式 |
| --- | --- |
| 一条笔记最多属于一个领域 | `notes.field_id -> fields.id` |
| 一条笔记可以有多个标签 | `notes -> note_tags -> tags` |
| 一条笔记可以引用其他笔记 | `note_links.source_note_id / target_note_id` |
| 一条笔记可以有多个附件 | `attachments.note_id -> notes.id` |
| 一条笔记可以有多个历史版本 | `note_revisions.note_id -> notes.id` |
| 一个版本可以记录来源设备 | `note_revisions.device_id -> devices.id` |
| 所有业务对象归属 workspace | 各表 `workspace_id -> workspaces.id` |
| 同步变更按 workspace 交换 | `sync_changes.workspace_id -> workspaces.id` |
