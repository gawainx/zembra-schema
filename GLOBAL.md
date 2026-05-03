# 共享数据表设计

本仓库通过 Git submodule 引入共享数据表契约：

```text
vendor/zembra-schema
```

该目录来自远程仓库：

```text
https://github.com/gawainx/zembra-schema.git
```

当前固定版本为 `v0.1.0`，对应 submodule commit `a557f37`。本仓库不复制维护数据表设计正文，数据表说明、SQLite DDL、JSON Schema 和 migration 都以 `vendor/zembra-schema` 为准。

首次拉取本仓库后，需要初始化 submodule：

```bash
git submodule update --init --recursive
```

升级共享 schema 时，在 `vendor/zembra-schema` 内切换到目标 tag 或 commit，再回到本仓库提交 submodule 指针变更：

```bash
cd vendor/zembra-schema
git fetch origin --tags
git checkout tags/<target-version>
cd ../..
git add .gitmodules vendor/zembra-schema README.md
git commit -m "docs: update shared schema reference"
```

提交前需要确认 schema 版本兼容性；如果数据结构有破坏性变化，需要同步更新本仓库的数据访问逻辑和迁移策略。

