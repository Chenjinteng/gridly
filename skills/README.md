# gridly skills

可独立分发的 gridly 配套 AI skills。每个 skill 是一个独立目录,里面只有 AI 执行所需的文件。

| Skill | 用途 | 分发形态 |
| ----- | ---- | -------- |
| [`gridly-migrate/`](gridly-migrate/) | 把其它记账 App 的旧数据(CSV / Excel)迁移进 gridly,产出可导入的 `gridly-migrated.sqlite` + 未迁移数据报告 | `gridly-migrate-skill.zip` |

## 安装

解压到 skill 目录即可,无需任何配置(纯 Python 标准库,不需要 pandas / openpyxl):

```bash
# macOS / Linux
unzip gridly-migrate-skill.zip -d ~/.minimax/skills/
```

Windows 用 PowerShell:

```powershell
Expand-Archive -Path gridly-migrate-skill.zip -DestinationPath "$env:USERPROFILE\.minimax\skills\"
```

## gridly-migrate 用法

安装后直接对 AI 说:

> 帮我把这个微信账单导进 gridly,文件在 xxx.csv,最后给我一个能直接导入 app 的 gridly-migrated.sqlite

AI 会自动:
1. 读表头判断源数据格式(支付宝 / 微信 / 通用 CSV / Excel)
2. 映射分类、账户、收支方向
3. 产出 `gridly-migrated.sqlite`(gridly schemaVersion 9)+ `migration-report.md`
4. 报告哪些数据没迁成功、需要人工确认

**导入 app**:gridly → 我的 → 数据 → 备份还原 → 还原 → 选 `gridly-migrated.sqlite`
(还原会覆盖现有数据,建议先在 app 内备份一次)

## 目标 schema

skill 对齐 `release/1.0` 分支的 gridly schema **version 9**,结构说明见
[`docs/SCHEMA.md`](../docs/SCHEMA.md)。schema 升级后需同步更新
`gridly-migrate/references/target-schema.md` 和 `gridly-migrate/references/seed_data.json`。
