# AGENTS.md

## Agent skills

### Issue tracker

Issues and specs live as local markdown files under `.scratch/<feature-slug>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical roles with default strings: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — one `CONTEXT.md` at the repo root, ADRs in `docs/adr/`. See `docs/agents/domain.md`.

## 本仓库约定

- 语言：所有注释、文档、提交信息与回复用**中文**。
- 引擎：Godot **4.7.2-stable** + 纯 GDScript，不引入 .NET（ADR-0001）。
- 结构：场景（`.tscn`）/ 不依赖节点树的纯逻辑类 / Autoload 设置单例，三层分离（ADR-0009）。
- 测试：GUT，只在纯逻辑缝上做行为测试，命令为
  `godot --headless -s addons/gut/gut_cmdln.gd`（配置见 `.gutconfig.json`）。
- 移动参数是 Apex 实测值，不是推导值：任何「看起来更合理」的调整都算有意偏离，必须先记一条 ADR（`docs/adr/`）。