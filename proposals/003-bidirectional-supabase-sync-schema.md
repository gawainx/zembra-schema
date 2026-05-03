# 003 双向 Supabase 同步基础设施 Schema Proposal

日期：2026-05-03

## 结论

本提案建议将 Zembra schema 从单机本地数据模型扩展为“多 workspace、本地优先、Supabase 云端协调”的双向同步模型。SQLite 继续作为 Mac 本地权威读写库，Supabase Postgres 作为跨设备同步中心。所有设备写入必须生成可重放的同步变更，远端和本地通过 `sync_changes` 交换变更，并通过确定性 revision 规则收敛到一致状态。

本提案只描述 schema 更新，不包含 backend 实现。

## 已确认决策

| 决策项 | 结论 |
| --- | --- |
| 同步隔离维度 | 预留多 workspace |
| 删除语义 | 不允许物理删除；业务对象使用软删除，变更日志保留 tombstone 语义 |
| note 内容冲突 | 保留所有 revision，`current_revision_id` 使用确定性规则自动收敛 |
| 当前版本选择规则 | 取最大 `(created_at, device_id, revision_id)` 的有效 revision |
| workspace ID | 使用 UUID 字符串，不使用固定短 ID |
| workspace 名称 | `workspace_name` 可为空；为空时展示名等于 `workspace_id` |
| Supabase 角色 | 云端同步协调层，不只是备份层 |
| 本地数据库角色 | 每台 Mac 继续保留 SQLite 本地读写能力 |

## 设计目标

| 目标 | 说明 |
| --- | --- |
| 支持两台 Mac 双向写入 | 任意设备离线写入后，恢复网络时能和其他设备收敛 |
| 支持多 workspace | 所有业务数据、设备、变更日志都归属 workspace |
| 不丢历史 | 同一 note 的并发编辑以 revision 形式保留 |
| 不物理删除 | 删除被表达为业务软删除或同步 tombstone，避免离线设备复活旧数据 |
| 适配 Supabase | schema 能映射到 Postgres、REST upsert、Realtime 和 RLS |
| 保持本地优先 | SQLite 查询模型仍然简单，业务 API 不直接依赖网络 |

## 范围

In Scope：

| 范围 | 内容 |
| --- | --- |
| Workspace 基础表 | 新增 workspace 隔离能力 |
| 业务表 workspace 化 | `notes`、`fields`、`tags`、`devices` 等表增加 `workspace_id` |
| 同步变更日志 | 新增 `sync_changes` 表记录可重放变更 |
| 同步游标 | 新增 `sync_state` 表记录每设备拉取和推送位置 |
| 同步冲突 | 新增 `sync_conflicts` 表记录需要用户处理的冲突 |
| 软删除约束 | 明确不引入物理删除同步语义 |
| JSON Schema | 新增同步对象 schema，并更新既有业务对象 schema |
| Supabase 映射 | 给出 Postgres/RLS/索引建议 |

Out of Scope：

| 范围 | 说明 |
| --- | --- |
| backend sync worker 实现 | 本提案不写 Rust 实现 |
| Supabase migration 文件 | 本提案只给设计，不落正式 DDL |
| 冲突 UI | 只设计冲突记录结构 |
| 端到端加密 | 后续单独设计 |
| 附件二进制同步 | 本提案只覆盖附件元数据同步 |

## 核心概念

### Workspace

`workspace` 是同步隔离边界。一个用户可以拥有多个 workspace；同一 workspace 下的设备、note、tag、field、revision、变更日志参与同一套同步。

第一版本地应用可以创建默认 workspace，但 schema 必须把 `workspace_id` 作为长期边界。`workspace_id` 必须使用 UUID 字符串，旧表迁移时由迁移流程生成一个默认 UUID，并回填到所有既有业务记录。

`workspace_name` 是可选显示名，不参与同步隔离和外键关系。读取 workspace 展示名时，应用层使用以下规则：

```text
display_name = workspace_name.trim().is_empty() ? workspace_id : workspace_name
```

SQLite 和 Postgres 约束不强制“为空时等于 workspace_id”，因为这是派生展示语义。数据库只负责允许 `workspace_name` 为空，并保证 `workspace_id` 稳定唯一。

### Device

`device` 是变更来源。每台 Mac 首次启动时生成稳定 `device_id`，后续所有 revision 和 sync change 都带上该设备 ID。

### Sync Change

`sync_changes` 是双向同步的事实来源。业务表保存当前查询状态，`sync_changes` 保存“发生过什么”。设备之间不直接比较整库快照，而是按同步游标交换 change。

### Tombstone

不允许物理删除。业务对象删除时写入 `deleted_at`，同时生成 `operation = 'delete'` 的 sync change。关联关系删除也通过 `detach` 或 `delete` change 表达。

## 新增表

### `workspaces`

记录同步工作区。

| 字段名 | SQLite 类型 | Postgres 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| `id` | `TEXT` | `uuid` | 是 | workspace 唯一 ID，使用 UUID 字符串 |
| `workspace_name` | `TEXT` | `text` | 否 | workspace 可选显示名；为空时展示为 `id` |
| `created_at` | `INTEGER` | `bigint` | 是 | 创建时间，Unix timestamp |
| `updated_at` | `INTEGER` | `bigint` | 是 | 最近更新时间 |
| `archived_at` | `INTEGER` | `bigint` | 否 | workspace 归档时间 |
| `deleted_at` | `INTEGER` | `bigint` | 否 | workspace 软删除时间 |

约束：

| 约束 | 说明 |
| --- | --- |
| `PRIMARY KEY(id)` | workspace ID 创建后不可变 |
| `CHECK(length(trim(id)) > 0)` | ID 不能为空 |
| UUID 格式校验 | SQLite 可用应用层校验；Postgres 使用 `uuid` 类型直接约束 |
| `CHECK(workspace_name IS NULL OR length(trim(workspace_name)) > 0)` | 名称为空时存 `NULL`，不存空白字符串 |
| `CHECK(created_at >= 0)` | 时间戳非负 |
| `CHECK(updated_at >= created_at)` | 更新时间不能早于创建时间 |
| `CHECK(archived_at IS NULL OR archived_at >= created_at)` | 归档时间合法 |
| `CHECK(deleted_at IS NULL OR deleted_at >= created_at)` | 删除时间合法 |

索引：

| 索引 | 说明 |
| --- | --- |
| `idx_workspaces_updated_at` | 支持 workspace 元数据同步 |
| `idx_workspaces_deleted_at` | 支持过滤软删除 workspace |

说明：

| 规则 | 说明 |
| --- | --- |
| 不新增 `name` 字段 | 使用明确的 `workspace_name`，避免和 `fields.name`、`tags.name` 混淆 |
| 不在业务表冗余 `workspace_name` | 业务表只保存 `workspace_id`；workspace 改名只改 `workspaces.workspace_name` |
| 默认显示名 | `workspace_name IS NULL` 时，应用层展示 `workspace_id` |

### `sync_changes`

记录本地和远端可交换、可重放的业务变更。

| 字段名 | SQLite 类型 | Postgres 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| `id` | `TEXT` | `text` | 是 | change 唯一 ID，推荐 ULID |
| `workspace_id` | `TEXT` | `uuid` | 是 | 变更所属 workspace |
| `device_id` | `TEXT` | `text` | 是 | 产生变更的设备 |
| `entity_type` | `TEXT` | `text` | 是 | 业务对象类型 |
| `entity_id` | `TEXT` | `text` | 是 | 业务对象 ID |
| `operation` | `TEXT` | `text` | 是 | 变更操作 |
| `base_revision_id` | `TEXT` | `text` | 否 | 内容修改基于的 revision |
| `new_revision_id` | `TEXT` | `text` | 否 | 内容修改产生的 revision |
| `payload` | `TEXT` | `jsonb` | 是 | 业务对象快照或关联变更载荷 |
| `created_at` | `INTEGER` | `bigint` | 是 | 来源设备生成 change 的时间 |
| `applied_at` | `INTEGER` | `bigint` | 否 | 当前库应用该 change 的时间 |
| `supabase_committed_at` | `INTEGER` | `bigint` | 否 | 云端接收该 change 的时间；本地可为空 |

`entity_type` 枚举：

| 值 | 说明 |
| --- | --- |
| `workspace` | workspace 元数据 |
| `device` | device 元数据 |
| `field` | field 元数据 |
| `tag` | tag 元数据 |
| `note` | note 主记录 |
| `note_revision` | note revision |
| `note_tag` | note/tag 关联 |
| `note_link` | note link |
| `attachment` | attachment 元数据 |

`operation` 枚举：

| 值 | 说明 |
| --- | --- |
| `insert` | 新增对象 |
| `update` | 更新对象 |
| `delete` | 软删除对象或写入 tombstone |
| `restore` | 恢复软删除对象 |
| `attach` | 新增关联关系 |
| `detach` | 移除关联关系 |

约束：

| 约束 | 说明 |
| --- | --- |
| `PRIMARY KEY(id)` | change 只能应用一次 |
| `FOREIGN KEY(workspace_id) REFERENCES workspaces(id)` | change 必须归属 workspace |
| `FOREIGN KEY(device_id) REFERENCES devices(id)` | change 必须有来源设备 |
| `CHECK(length(trim(entity_type)) > 0)` | 类型不能为空 |
| `CHECK(length(trim(entity_id)) > 0)` | 对象 ID 不能为空 |
| `CHECK(operation IN (...))` | 操作类型固定 |
| `CHECK(created_at >= 0)` | 生成时间非负 |
| `CHECK(applied_at IS NULL OR applied_at >= 0)` | 应用时间合法 |
| `CHECK(supabase_committed_at IS NULL OR supabase_committed_at >= 0)` | 云端提交时间合法 |
| `UNIQUE(workspace_id, device_id, id)` | 防止同设备 change 重复 |

索引：

| 索引 | 说明 |
| --- | --- |
| `idx_sync_changes_workspace_created` on `(workspace_id, created_at, id)` | 增量拉取主索引 |
| `idx_sync_changes_workspace_device_created` on `(workspace_id, device_id, created_at, id)` | 排除自身变更 |
| `idx_sync_changes_entity` on `(workspace_id, entity_type, entity_id)` | 查询对象变更历史 |
| `idx_sync_changes_revision` on `(workspace_id, entity_type, new_revision_id)` | note revision 冲突分析 |

### `sync_state`

记录每台设备在每个 workspace 的同步游标。

| 字段名 | SQLite 类型 | Postgres 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| `workspace_id` | `TEXT` | `uuid` | 是 | workspace ID |
| `device_id` | `TEXT` | `text` | 是 | 本地设备 ID |
| `scope` | `TEXT` | `text` | 是 | 游标范围 |
| `last_change_created_at` | `INTEGER` | `bigint` | 是 | 已处理的最后 change 时间 |
| `last_change_id` | `TEXT` | `text` | 是 | 同时间戳下的最后 change ID |
| `last_success_at` | `INTEGER` | `bigint` | 否 | 最近一次成功同步时间 |
| `last_error_at` | `INTEGER` | `bigint` | 否 | 最近一次失败时间 |
| `last_error_message` | `TEXT` | `text` | 否 | 最近一次失败摘要 |

`scope` 枚举：

| 值 | 说明 |
| --- | --- |
| `push` | 本地推送到 Supabase 的进度 |
| `pull` | 从 Supabase 拉取远端 change 的进度 |

约束：

| 约束 | 说明 |
| --- | --- |
| `PRIMARY KEY(workspace_id, device_id, scope)` | 每设备每 workspace 每方向一条状态 |
| `FOREIGN KEY(workspace_id) REFERENCES workspaces(id)` | 状态归属 workspace |
| `FOREIGN KEY(device_id) REFERENCES devices(id)` | 状态归属设备 |
| `CHECK(scope IN ('push', 'pull'))` | 游标方向固定 |
| `CHECK(last_change_created_at >= 0)` | 游标时间非负 |
| `CHECK(length(trim(last_change_id)) > 0)` | 游标 ID 不能为空 |

### `sync_conflicts`

记录无法完全自动处理、需要 UI 或用户选择的冲突。

| 字段名 | SQLite 类型 | Postgres 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| `id` | `TEXT` | `text` | 是 | conflict 唯一 ID |
| `workspace_id` | `TEXT` | `uuid` | 是 | workspace ID |
| `entity_type` | `TEXT` | `text` | 是 | 冲突对象类型 |
| `entity_id` | `TEXT` | `text` | 是 | 冲突对象 ID |
| `conflict_type` | `TEXT` | `text` | 是 | 冲突类型 |
| `local_change_id` | `TEXT` | `text` | 否 | 本地相关 change |
| `remote_change_id` | `TEXT` | `text` | 否 | 远端相关 change |
| `local_revision_id` | `TEXT` | `text` | 否 | 本地 revision |
| `remote_revision_id` | `TEXT` | `text` | 否 | 远端 revision |
| `winning_revision_id` | `TEXT` | `text` | 否 | 自动选择或用户选择的 revision |
| `status` | `TEXT` | `text` | 是 | 冲突处理状态 |
| `created_at` | `INTEGER` | `bigint` | 是 | 冲突发现时间 |
| `resolved_at` | `INTEGER` | `bigint` | 否 | 冲突解决时间 |
| `resolution_note` | `TEXT` | `text` | 否 | 解决说明 |

`conflict_type` 枚举：

| 值 | 说明 |
| --- | --- |
| `concurrent_note_edit` | 同一 note 基于不同 revision 被并发编辑 |
| `delete_vs_update` | 一端删除对象，另一端更新对象 |
| `relation_attach_vs_detach` | 关联关系一端添加，一端移除 |
| `schema_incompatible` | 本地无法理解远端 payload |

`status` 枚举：

| 值 | 说明 |
| --- | --- |
| `open` | 待处理 |
| `auto_resolved` | 已按确定性规则自动处理 |
| `resolved` | 用户或应用已处理 |
| `ignored` | 明确忽略 |

约束：

| 约束 | 说明 |
| --- | --- |
| `PRIMARY KEY(id)` | conflict ID 唯一 |
| `FOREIGN KEY(workspace_id) REFERENCES workspaces(id)` | 冲突归属 workspace |
| `CHECK(status IN (...))` | 状态固定 |
| `CHECK(conflict_type IN (...))` | 冲突类型固定 |
| `CHECK(created_at >= 0)` | 发现时间合法 |
| `CHECK(resolved_at IS NULL OR resolved_at >= created_at)` | 解决时间合法 |

索引：

| 索引 | 说明 |
| --- | --- |
| `idx_sync_conflicts_workspace_status` on `(workspace_id, status, created_at)` | 查询待处理冲突 |
| `idx_sync_conflicts_entity` on `(workspace_id, entity_type, entity_id)` | 查询对象冲突历史 |

## 既有表更新

### 所有业务表增加 `workspace_id`

以下表必须增加 `workspace_id`：

| 表 | 变更 |
| --- | --- |
| `fields` | 新增 `workspace_id` |
| `tags` | 新增 `workspace_id` |
| `devices` | 新增 `workspace_id` |
| `notes` | 新增 `workspace_id` |
| `note_tags` | 新增 `workspace_id` |
| `note_links` | 新增 `workspace_id` |
| `attachments` | 新增 `workspace_id` |
| `note_revisions` | 新增 `workspace_id` |

字段定义：

| 字段名 | SQLite 类型 | Postgres 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| `workspace_id` | `TEXT` | `uuid` | 是 | 记录所属 workspace，值来自 `workspaces.id` |

约束：

| 约束 | 说明 |
| --- | --- |
| `FOREIGN KEY(workspace_id) REFERENCES workspaces(id)` | 业务记录必须归属 workspace |

### 唯一约束调整

为了支持多 workspace，同名对象唯一性需要限定在 workspace 内。

| 表 | 当前约束 | 新约束 |
| --- | --- | --- |
| `fields` | `UNIQUE(name)` | `UNIQUE(workspace_id, name)` |
| `tags` | `UNIQUE(name)` | `UNIQUE(workspace_id, name)` |
| `note_tags` | `PRIMARY KEY(note_id, tag_id)` | `PRIMARY KEY(workspace_id, note_id, tag_id)` |

### 外键调整

所有业务外键应确保不会跨 workspace 关联。SQLite 无法用普通单列外键完整表达所有跨 workspace 禁止关系时，应用层必须校验；Postgres 可通过复合外键或触发器增强。

业务表不新增 `workspace_name`。workspace 名称属于 `workspaces` 元数据；如果把名称冗余到每张业务表，workspace 改名会变成全表级同步变更，容易产生无意义冲突和数据不一致。

推荐复合外键方向：

| 表 | 外键 |
| --- | --- |
| `notes` | `(workspace_id, field_id) -> fields(workspace_id, id)` |
| `note_tags` | `(workspace_id, note_id) -> notes(workspace_id, id)` |
| `note_tags` | `(workspace_id, tag_id) -> tags(workspace_id, id)` |
| `note_links` | `(workspace_id, source_note_id) -> notes(workspace_id, id)` |
| `note_links` | `(workspace_id, target_note_id) -> notes(workspace_id, id)` |
| `attachments` | `(workspace_id, note_id) -> notes(workspace_id, id)` |
| `note_revisions` | `(workspace_id, note_id) -> notes(workspace_id, id)` |
| `note_revisions` | `(workspace_id, device_id) -> devices(workspace_id, id)` |

为支持这些复合外键，相关表需要补充唯一索引：

| 表 | 唯一索引 |
| --- | --- |
| `fields` | `UNIQUE(workspace_id, id)` |
| `tags` | `UNIQUE(workspace_id, id)` |
| `devices` | `UNIQUE(workspace_id, id)` |
| `notes` | `UNIQUE(workspace_id, id)` |

### `notes` 表新增同步辅助字段

| 字段名 | SQLite 类型 | Postgres 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| `last_change_id` | `TEXT` | `text` | 否 | 最近一次影响 note 当前状态的 change |
| `conflict_status` | `TEXT` | `text` | 是 | note 当前冲突状态 |

`conflict_status` 枚举：

| 值 | 说明 |
| --- | --- |
| `none` | 无冲突 |
| `auto_resolved` | 有并发 revision，已自动收敛 |
| `needs_review` | 需要用户处理 |

默认值：

| 字段 | 默认值 |
| --- | --- |
| `conflict_status` | `none` |

约束：

| 约束 | 说明 |
| --- | --- |
| `CHECK(conflict_status IN ('none', 'auto_resolved', 'needs_review'))` | 状态固定 |

### `note_revisions` 表新增同步字段

| 字段名 | SQLite 类型 | Postgres 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| `base_revision_id` | `TEXT` | `text` | 否 | 当前 revision 基于哪个 revision 编辑 |
| `change_id` | `TEXT` | `text` | 否 | 产生该 revision 的 sync change |

说明：

| 字段 | 设计原因 |
| --- | --- |
| `base_revision_id` | 判断两台设备是否基于同一版本并发编辑 |
| `change_id` | 从 revision 追溯到同步变更，方便冲突诊断 |

### `devices` 表新增同步字段

| 字段名 | SQLite 类型 | Postgres 类型 | 必填 | 说明 |
| --- | --- | --- | --- | --- |
| `sync_enabled` | `INTEGER` | `boolean` | 是 | 当前设备是否参与同步 |
| `last_synced_at` | `INTEGER` | `bigint` | 否 | 设备最近成功同步时间 |

SQLite 中 `sync_enabled` 使用 `0/1`：

| 值 | 说明 |
| --- | --- |
| `0` | 不参与同步 |
| `1` | 参与同步 |

## 同步收敛规则

### Change 应用幂等性

每个库应用远端 change 前必须检查 `sync_changes.id` 是否已存在。已存在则跳过业务应用，只更新必要状态。

### Pull 游标

远端拉取使用 `(created_at, id)` 作为稳定游标：

```text
WHERE workspace_id = ?
  AND device_id <> local_device_id
  AND (created_at, id) > (last_change_created_at, last_change_id)
ORDER BY created_at ASC, id ASC
```

原因：

| 点 | 说明 |
| --- | --- |
| 秒级 timestamp 不够唯一 | 同一秒内可能有多条 change |
| ID 作为 tie-breaker | 保证顺序稳定 |
| 排除 local device | 避免拉回自己刚推送的 change |

### Note 当前 revision 选择

同一 note 有多个有效 revision 时，当前版本按以下元组取最大值：

```text
(note_revisions.created_at, note_revisions.device_id, note_revisions.id)
```

更新 `notes.current_revision_id` 后，同时把 `notes.content` 更新为该 revision 的 `content`。

### 并发编辑

如果远端 revision 的 `base_revision_id` 与本地当前 `current_revision_id` 不一致，且两者不是祖先/后继关系，则记录 `sync_conflicts`：

| 字段 | 值 |
| --- | --- |
| `conflict_type` | `concurrent_note_edit` |
| `status` | `auto_resolved` |
| `winning_revision_id` | 按确定性规则选出的 revision |

### 删除与更新冲突

如果对象本地已 `deleted_at IS NOT NULL`，远端又收到更新：

| 情况 | 处理 |
| --- | --- |
| note content update | 保留 revision，`notes.deleted_at` 不自动清空，记录 `delete_vs_update` |
| tag/field update | 保留元数据更新，软删除状态不自动清空 |
| relation attach | 如果 note 或 tag 已删除，记录冲突，不恢复关联 |

### 关联关系

`note_tags`、`note_links` 等关系表不物理删除业务历史。当前关系状态可通过业务表删除行表达，但必须有 `sync_changes.operation = 'detach'` 作为 tombstone。若需要完全审计关系历史，后续可以新增 relation tombstone 表。

## JSON Schema 产物建议

### 新增 JSON Schema

| 文件 | title | 用途 |
| --- | --- | --- |
| `json/workspace.schema.json` | `Zembra Workspace` | workspace 对象 |
| `json/sync_change.schema.json` | `Zembra Sync Change` | 同步变更 |
| `json/sync_state.schema.json` | `Zembra Sync State` | 同步游标 |
| `json/sync_conflict.schema.json` | `Zembra Sync Conflict` | 同步冲突 |

### 更新 JSON Schema

| 文件 | 更新 |
| --- | --- |
| `json/note.schema.json` | 增加 `workspace_id`、`last_change_id`、`conflict_status` |
| `json/note_revision.schema.json` | 增加 `workspace_id`、`base_revision_id`、`change_id` |
| `json/device.schema.json` | 增加 `workspace_id`、`sync_enabled`、`last_synced_at` |
| `json/field.schema.json` | 增加 `workspace_id` |
| `json/tag.schema.json` | 增加 `workspace_id` |
| `json/note_tag.schema.json` | 增加 `workspace_id` |
| `json/note_link.schema.json` | 增加 `workspace_id` |
| `json/attachment.schema.json` | 增加 `workspace_id` |
| `json/zembra_note_export.schema.json` | 增加 workspace 和 sync 版本信息 |

## SQLite migration 建议

建议新增 `migrations/003_add_bidirectional_sync.sql`。

迁移顺序：

1. 创建 `workspaces` 表。
2. 生成或接收一个默认 workspace UUID。
3. 插入默认 workspace，`id = 默认 workspace UUID`，`workspace_name = NULL`。
4. 为既有业务表增加 `workspace_id`，回填默认 workspace UUID。
5. 创建 `sync_changes`、`sync_state`、`sync_conflicts`。
6. 为 `notes` 增加 `last_change_id`、`conflict_status`。
7. 为 `note_revisions` 增加 `base_revision_id`、`change_id`。
8. 为 `devices` 增加 `sync_enabled`、`last_synced_at`。
9. 创建新增索引。
10. 写入 `schema_migrations` 版本。

SQLite 注意事项：

| 注意事项 | 说明 |
| --- | --- |
| 修改唯一约束需要重建表 | `fields.name`、`tags.name` 原唯一约束需要迁移到 `(workspace_id, name)` |
| 复合外键可能需要重建表 | 建议一次性重建受影响业务表 |
| 默认 workspace ID 必须是 UUID | 迁移不能使用 `default` 这类短 ID |
| 默认 workspace UUID 必须稳定 | 同一次迁移中所有旧记录必须回填同一个 UUID；迁移完成后不能重新生成 |
| `workspace_name` 默认值 | 旧库迁移时写入 `NULL`，应用层展示为 `workspace_id` |
| 不允许物理删除旧数据 | 迁移只能回填、重建、复制，不丢弃业务行 |

### 旧表迁移细节

旧表没有 workspace 概念，迁移时必须把整库视为一个默认 workspace。推荐流程：

1. backend 启动迁移前生成一个 UUID，例如 `550e8400-e29b-41d4-a716-446655440000`。
2. 在同一事务中插入 `workspaces` 行。
3. 重建需要变更唯一约束或外键的业务表。
4. 复制旧表数据时为每一行写入同一个 `workspace_id`。
5. 创建新索引和新外键。
6. 写入 schema migration 版本。

默认 workspace UUID 的来源：

| 来源 | 结论 |
| --- | --- |
| 应用层生成 | 推荐；SQLite migration 本身不依赖 UUID 扩展 |
| 固定常量 UUID | 仅适合测试，不适合真实用户数据库 |
| `default` 字符串 | 禁止；不符合 UUID 决策 |

旧数据迁移后，用户可以后续修改 `workspace_name`。修改名称只更新 `workspaces.workspace_name`，不触碰业务表。

## Supabase/Postgres 建议

### 类型映射

| 语义 | SQLite | Postgres |
| --- | --- | --- |
| workspace ID | `TEXT` UUID 字符串 | `uuid` |
| 其他 ID | `TEXT` | `text` |
| 时间戳 | `INTEGER` | `bigint` |
| JSON payload | `TEXT` | `jsonb` |
| boolean | `INTEGER CHECK(value IN (0, 1))` | `boolean` |

### RLS 预留

所有云端表必须包含 `workspace_id`，后续 RLS 可按 workspace membership 限制访问。

建议未来增加 Supabase 专用表：

| 表 | 用途 |
| --- | --- |
| `workspace_members` | 记录 Supabase Auth user 与 workspace 的关系 |

本提案不把 `workspace_members` 放入共享本地 schema，因为本地 SQLite 第一阶段不需要用户身份系统。

### Realtime

第一版可以按定时 pull/push 工作。后续接 Supabase Realtime 时，推荐订阅 `sync_changes`，而不是直接订阅所有业务表。

原因：

| 点 | 说明 |
| --- | --- |
| 事件模型统一 | 所有业务变更都在一张表 |
| 客户端逻辑简单 | 收到 change 后按协议应用 |
| 避免业务表乱序 | 业务表多表订阅容易遇到关联顺序问题 |

## 版本建议

建议 schema 版本升级为 `0.3.0`。

原因：

| 点 | 说明 |
| --- | --- |
| 新增多张同步基础表 | 属于功能性 schema 扩展 |
| 既有业务表新增必填 UUID `workspace_id` | 需要迁移回填 |
| 唯一约束变化 | 对查询和写入语义有影响 |
| 双向同步协议成型 | 值得独立版本标记 |

## 验收标准

| 验收项 | 预期 |
| --- | --- |
| 多 workspace | 不同 workspace 可以存在同名 field/tag |
| 默认 workspace 迁移 | 旧库迁移后所有旧记录归属同一个 UUID workspace |
| workspace 显示名 | `workspace_name` 为空时展示 `workspace_id` |
| 双向同步 | 两台设备基于 `sync_changes` 能交换变更 |
| 幂等应用 | 同一 change 重复应用不会重复写业务数据 |
| 并发 note 编辑 | 两个 revision 都保留，当前 revision 确定性一致 |
| 删除语义 | 删除只写 `deleted_at` 或 detach change，不物理删除业务对象 |
| Supabase 映射 | 所有表具备 `workspace_id`，可配置 RLS |
| 游标稳定 | 同一秒多条 change 不会漏拉 |

## 后续落地顺序

1. 审阅并确认本 proposal。
2. 编写 SQLite migration `003_add_bidirectional_sync.sql`。
3. 新增和更新 JSON Schema。
4. 更新 `note_schema.md` 和 `CHANGELOG.md`。
5. 在 backend 接入新 migration。
6. 实现本地 change log 写入。
7. 实现 Supabase push/pull worker。
