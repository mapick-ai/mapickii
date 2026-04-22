# Mapickii 技能 - OpenClaw 兼容性改进文档

**日期**: 2026-04-21  
**版本**: V1  
**状态**: ✅ 已完成

---

## 1. 概述

Mapickii 技能是一款 AI-native 技能推荐引擎，用于发现、保护和清理用户的 Skill 库。本次改进主要针对 OpenClaw 兼容性，确保技能能够正确加载和运行。

### 1.1 改进目标

- ✅ 添加 OpenClaw 所需的 metadata 字段
- ✅ 确保脚本路径引用正确
- ✅ 确保 CONFIG_DIR 动态推导

### 1.2 OpenClaw Skill 工作原理

OpenClaw 的 Skill 是一个文件夹结构，包含：
- `SKILL.md` - YAML frontmatter + 自然语言指令
- `scripts/` - 执行脚本目录

AI 启动时读取所有 SKILL.md 的 frontmatter，根据指令调用脚本。

---

## 2. 改进详情

### 2.1 改进 1：添加 metadata 到 frontmatter ✅

**问题**: SKILL.md 缺少 OpenClaw 所需的 metadata 字段

**改进前**:
```yaml
---
name: mapickii
description: Mapickii — Skill recommendation & privacy protection for OpenClaw...
---
```

**改进后**:
```yaml
---
name: mapickii
description: Mapickii — Skill recommendation & privacy protection for OpenClaw. Scans your local skills, suggests what you're missing, and keeps other skills from seeing your secrets.
metadata: { "openclaw": { "emoji": "🔍", "requires": { "bins": ["python3", "jq", "curl"] }, "primaryEnv": "MAPICKII_API_BASE" } }
---
```

**metadata 字段说明**:
- `emoji`: 技能图标，显示在 UI 中 (🔍)
- `requires.bins`: 依赖检查列表 (python3, jq, curl)
- `primaryEnv`: 主要环境变量名称 (MAPICKII_API_BASE)

**影响**: OpenClaw 启动时会检查依赖是否可用，如果不可用则不加载此技能。

---

### 2.2 改进 2：脚本路径引用检查 ✅

**检查结果**: SKILL.md 使用相对路径，无需修改

**当前实现**:
```bash
bash shell.sh recommend [limit]
bash shell.sh search <keyword> [limit]
bash shell.sh init
bash shell.sh status
```

**说明**: 
- 已经使用相对路径 `shell.sh`，正确
- OpenClaw 会自动在 Skill 目录下执行脚本
- 无需使用 `{baseDir}` 占位符（当前实现已经正确）

---

### 2.3 改进 3：shell.sh CONFIG_DIR 检查 ✅

**检查结果**: shell.sh 使用动态推导，无需修改

**当前实现** (scripts/shell.sh):
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${CONFIG_DIR}/CONFIG.md"
```

**说明**:
- 使用 `$BASH_SOURCE[0]` 动态获取脚本位置
- 从脚本位置推导 CONFIG_DIR
- 比硬编码路径更灵活，支持多种安装位置

**影响**: 技能可以在任意位置安装，不需要修改配置。

---

## 3. 改进结果

| 检查项 | 改进前状态 | 改进后状态 | 说明 |
|-------|----------|----------|------|
| frontmatter metadata | ❌ 缺少 | ✅ 已添加 | 包含 emoji、requires、primaryEnv |
| 脚本路径引用 | ✅ 已正确 | ✅ 保持不变 | 使用相对路径 |
| CONFIG_DIR 设置 | ✅ 已正确 | ✅ 保持不变 | 使用动态推导 |
| OpenClaw 兼容性 | ⚠️ 部分 | ✅ 完全兼容 | 可以正常加载和运行 |

---

## 4. 测试验证

### 4.1 验证 metadata 已正确添加

```bash
# 查看 SKILL.md frontmatter
head -5 ~/.openclaw/skills/mapickii/SKILL.md
```

**预期输出**:
```yaml
---
name: mapickii
description: Mapickii — Skill recommendation & privacy protection for OpenClaw...
metadata: { "openclaw": { "emoji": "🔍", "requires": { "bins": ["python3", "jq", "curl"] }, "primaryEnv": "MAPICKII_API_BASE" } }
---
```

### 4.2 验证技能可正常执行

```bash
# 测试技能命令
cd ~/.openclaw/skills/mapickii/scripts && bash shell.sh status
```

**预期结果**: 返回 JSON 格式的状态信息

---

## 5. 使用方式

### 5.1 在 OpenClaw 中使用 Mapickii

```bash
/mapickii            # 查看状态
/mapickii recommend  # 获取推荐
/mapickii search <关键词> # 搜索技能
/mapickii clean      # 清理僵尸技能
/mapickii workflow   # 工作流分析
/mapickii daily      # 日报
/mapickii weekly     # 周报
```

### 5.2 推荐技能

用户可以问：
- "推荐一些技能"
- "有什么好的技能"
- "我应该安装什么"
- "搜索天气相关的技能"

AI 会自动调用 Mapickii 并返回推荐。

---

## 6. 后续工作（可选）

### 6.1 发布到 ClawHub

```bash
cd ~/.openclaw/skills/mapickii
clawhub skill publish .
```

发布后用户可以用：
```bash
openclaw skills install mapickii
```

### 6.2 双安装方式支持

**ClawHub 原生安装**（主推）:
```bash
openclaw skills install mapickii
```

**curl | bash 安装**（兜底）:
```bash
curl -fsSL https://raw.githubusercontent.com/.../install.sh | bash
```

---

## 7. 技术细节

### 7.1 metadata JSON 结构

```json
{
  "openclaw": {
    "emoji": "🔍",
    "requires": {
      "bins": ["python3", "jq", "curl"]
    },
    "primaryEnv": "MAPICKII_API_BASE"
  }
}
```

### 7.2 OpenClaw Skill 目录结构

```
~/.openclaw/skills/mapickii/
├── SKILL.md          # 技能定义文件
├── CONFIG.md         # 配置文件（自动生成）
├── scripts/
│   └── shell.sh      # 执行脚本
└── assets/           # 资源文件（可选）
```

### 7.3 依赖说明

| 依赖 | 版本要求 | 用途 |
|-----|---------|------|
| python3 | ≥ 3.9 | 数据处理和 API 调用 |
| jq | ≥ 1.6 | JSON 解析 |
| curl | ≥ 7.0 | HTTP 请求 |

---

## 8. 参考文档

- message.md - OpenClaw 兼容性分析
- SKILL.md - 技能定义文件
- scripts/shell.sh - 执行脚本
- OpenClaw 文档: https://docs.openclaw.ai

---

## 9. 联系方式

如有问题，请联系：
- GitHub: https://github.com/.../mapickii
- ClawHub: https://clawhub.ai/skills/mapickii

---

**文档结束**

---

## 10. Skill Refactor (2026-04-22)

### 10.1 改进目标

- ✅ 修正 description（CSO 合规）
- ✅ 拆分文件降低 token
- ✅ 添加决策流程图
- ✅ 添加 Red Flags 章节
- ✅ 添加 "When NOT to Use"
- ✅ 移除冗余章节

### 10.2 改进后结构

| 文件 | 行数 | 职责 |
|------|------|------|
| SKILL.md | 632 | 核心流程 + 流程图 |
| reference/api.md | 42 | 命令/API |
| reference/errors.md | 30 | 错误处理 |
| reference/lifecycle.md | 24 | 生命周期 |
| reference/intents.md | 43 | 意图触发词 |

### 10.3 验证

```bash
wc -l SKILL.md reference/*.md
# SKILL.md 632 行（超出 ~150 目标，详细 rendering instructions 未移除）
# reference 文件总计 139 行
```

### 10.4 后续可选优化

若需进一步压缩 SKILL.md 至 ~200 行，可移除：
- 各章节的 Rendering 详细说明 → `reference/rendering.md`
- Bundle install 详细流程 → `reference/bundle.md`

---

## 11. Skill Refactor V2 (2026-04-22)

### 11.1 Claude + Codex 评审改进点

- ✅ description 补 bundle/workflow/cost 触发词
- ✅ DOT 流程图 → Markdown 决策表（省 token，OpenClaw 可读）
- ✅ reference 外链保留一行摘要（不只写 "See reference"）
- ✅ CONFIG 示例无 hostname/home 等敏感字段
- ✅ 安全红线表格内联 SKILL.md（不过度外链）
- ✅ reference/errors.md 含安全红线

### 11.2 最终结构

| 文件 | 行数 | 词数 |
|------|------|------|
| SKILL.md | 569 | 3083 |
| reference/api.md | 20 | - |
| reference/errors.md | 28 | - |
| reference/lifecycle.md | 15 | - |
| reference/intents.md | 45 | - |
| reference/config-example.md | 22 | - |

### 11.3 验证

```bash
wc -l SKILL.md && wc -w SKILL.md
# 569 行 / 3083 词（无中文字符）
```

### 11.4 未解决的问题

- Rendering 详细说明仍占大量篇幅，可进一步压缩
- API 路由需同步修复（见 Phase B）