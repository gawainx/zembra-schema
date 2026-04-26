# Zembra Note Schema

本包定义 Zembra 笔记软件的本地数据表和跨端数据结构契约。当前版本为 `0.1.0`，目标是覆盖第一版个人笔记应用所需的核心对象：笔记、领域、标签、双链、附件、版本历史和设备。

## 设计原则

- 笔记正文使用轻量 Markdown 文本，正文中可以包含 `@field`、`#tag` 和双链文本。
- 一条笔记最多归属一个 Field，可以拥有多个 Tag。
- 双链关系独立存储，正文保留原始文本，关系表用于查询和跳转。
- 删除和归档使用时间戳表达，保留本地恢复和同步扩展空间。
- 版本历史先存完整快照，避免第一版引入 diff 复杂度。
- 时间统一使用 Unix timestamp，单位由应用层保持一致。
- ID 使用 `TEXT`，推荐 ULID 或 UUID，创建后不可变。

## 目录产物

- `note_schema.md`：人读的设计说明。
- `sqlite/001_initial_schema.sql`：SQLite 初始 DDL。
- `json/*.schema.json`：跨端对象级 JSON Schema 契约。
- `migrations/001_initial_schema.sql`：v0.1.0 初始迁移脚本。
- `CHANGELOG.md`：schema 变更记录。

## `notes` 笔记表

`notes` 是中心表，保存笔记正文、领域归属、生命周期状态和当前版本引用。

| 字段名 | 类型 | 含义 | 约束信息 |
| --- | --- | --- | --- |
| `id` | `TEXT` | 笔记唯一 ID | 主键；必填；建议 ULID/UUID；创建后不可变 |
| `content` | `TEXT` | 笔记正文 | 必填；承载纯文本、轻 Markdown、`@field`、`#tag`、双链文本 |
| `field_id` | `TEXT` | 所属领域 ID | 可选；外键引用 `fields.id`；一条笔记最多一个 field |
| `created_at` | `INTEGER` | 创建时间 | 必填；Unix timestamp |
| `updated_at` | `INTEGER` | 最近更新时间 | 必填；Unix timestamp |
| `archived_at` | `INTEGER` | 归档时间 | 可为空；为空表示未归档 |
| `deleted_at` | `INTEGER` | 软删除时间 | 可为空；为空表示未删除 |
| `current_revision_id` | `TEXT` | 当前版本 ID | 可为空；逻辑引用 `note_revisions.id` |

## `fields` 领域表

`fields` 表达笔记可归属的领域单位，对应用户输入的 `@field`。

| 字段名 | 类型 | 含义 | 约束信息 |
| --- | --- | --- | --- |
| `id` | `TEXT` | field 唯一 ID | 主键；必填；创建后不可变 |
| `name` | `TEXT` | field 名称 | 必填；唯一 |
| `created_at` | `INTEGER` | 创建时间 | 必填；Unix timestamp |

## `tags` 标签表

`tags` 表达平铺标签，对应用户输入的 `#tag`。第一版不做层级标签。

| 字段名 | 类型 | 含义 | 约束信息 |
| --- | --- | --- | --- |
| `id` | `TEXT` | 标签唯一 ID | 主键；必填；创建后不可变 |
| `name` | `TEXT` | 标签名 | 必填；唯一 |
| `created_at` | `INTEGER` | 创建时间 | 必填；Unix timestamp |

## `note_tags` 笔记标签关联表

`note_tags` 只表达笔记和标签的多对多关系。标签名称变更时，只修改 `tags.name`，不用改笔记正文。

| 字段名 | 类型 | 含义 | 约束信息 |
| --- | --- | --- | --- |
| `note_id` | `TEXT` | 笔记 ID | 必填；外键引用 `notes.id` |
| `tag_id` | `TEXT` | 标签 ID | 必填；外键引用 `tags.id` |
| `created_at` | `INTEGER` | 关联创建时间 | 必填；Unix timestamp |

联合约束：`PRIMARY KEY(note_id, tag_id)`。

## `note_links` 双向链接表

`note_links` 记录正文中的笔记引用。关系查询时可以同时按 `source_note_id` 和 `target_note_id` 建索引实现正向链接和反向链接。

| 字段名 | 类型 | 含义 | 约束信息 |
| --- | --- | --- | --- |
| `id` | `TEXT` | 链接记录 ID | 主键；必填 |
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
| `note_id` | `TEXT` | 所属笔记 ID | 必填；外键引用 `notes.id` |
| `content` | `TEXT` | 该版本正文快照 | 必填 |
| `title` | `TEXT` | 该版本标题快照 | 可为空 |
| `device_id` | `TEXT` | 修改来源设备 | 可为空；外键引用 `devices.id` |
| `created_at` | `INTEGER` | 版本创建时间 | 必填；Unix timestamp |

## `devices` 设备表

`devices` 记录本地设备身份。即使第一版只做本地应用，也保留该表，方便版本历史和后续多端同步。

| 字段名 | 类型 | 含义 | 约束信息 |
| --- | --- | --- | --- |
| `id` | `TEXT` | 设备唯一 ID | 主键；必填；本地生成后保持稳定 |
| `name` | `TEXT` | 设备名称 | 必填，例如 `Jagd MacBook` |
| `platform` | `TEXT` | 设备平台 | 必填，例如 `macos`、`ios`、`windows` |
| `created_at` | `INTEGER` | 首次登记时间 | 必填；Unix timestamp |
| `last_seen_at` | `INTEGER` | 最近使用时间 | 可为空；Unix timestamp |

## 最小关系汇总

| 关系 | 表达方式 |
| --- | --- |
| 一条笔记最多属于一个领域 | `notes.field_id -> fields.id` |
| 一条笔记可以有多个标签 | `notes -> note_tags -> tags` |
| 一条笔记可以引用其他笔记 | `note_links.source_note_id / target_note_id` |
| 一条笔记可以有多个附件 | `attachments.note_id -> notes.id` |
| 一条笔记可以有多个历史版本 | `note_revisions.note_id -> notes.id` |
| 一个版本可以记录来源设备 | `note_revisions.device_id -> devices.id` |
