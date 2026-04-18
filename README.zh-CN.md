<p align="center">
  <img src="assets/mapickii_banner.png" alt="Mapickii Banner" width="720" />
</p>

<h1 align="center">Mapickii</h1>

<p align="center">
  <strong>Mapick 智能管家 —— Skill 生命周期管理 · 智能推荐 · 套装推荐</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-3.0-blue?style=flat-square" alt="Version" />
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License" />
  <img src="https://img.shields.io/badge/modules-M1%20%7C%20M2%20%7C%20M3-orange?style=flat-square" alt="Modules" />
  <img src="https://img.shields.io/badge/platforms-6-purple?style=flat-square" alt="Platforms" />
</p>

<p align="center">
  <a href="https://mapick.ai">官网</a> &nbsp;|&nbsp;
  <a href="https://discord.gg/ju8rzvtm5">Discord</a> &nbsp;|&nbsp;
  <a href="#install">安装</a> &nbsp;|&nbsp;
  <a href="#commands">命令</a> &nbsp;|&nbsp;
  <a href="README.md">English</a>
</p>

---

## 什么是 Mapickii？

Mapickii 是 Mapick 生态的智能管家，整合 M1/M2/M3 三大模块，在你的 AI 编码工具里管理 Skill 的完整生命周期：从安装、使用、频率分析到僵尸清理，并基于你的使用习惯推荐单个 Skill 或完整套装。

**核心能力：**

- **M1 生命周期管理** —— 状态总览、僵尸检测与清理、工作流分析、日报/周报
- **M2 智能推荐** —— 每次交互返回推荐 Skill，24 小时本地缓存，零额外开销
- **M3 套装推荐** —— 预定义场景套装、已装覆盖率计算、一键补全
- **身份管理** —— 注册 Mapick ID、多设备绑定、本地模式
- **推荐码系统** —— 自动生成 6 位推荐码，绑定一次不可更改
- **推送频率** —— 日推 / 周推 / 静音，自然语言即可切换

## 支持的平台

| 平台        | 厂商      | 安装目录                       |
| ----------- | --------- | ------------------------------ |
| Claude Code | Anthropic | `~/.claude/skills/mapickii/`   |
| Codex CLI   | OpenAI    | `~/.codex/skills/mapickii/`    |
| Gemini CLI  | Google    | `~/.gemini/skills/mapickii/`   |
| OpenCode    | OpenCode  | `~/.opencode/skills/mapickii/` |
| QwenCode    | Alibaba   | `~/.qwencode/skills/mapickii/` |
| OpenClaw    | OpenClaw  | `~/.openclaw/skills/mapickii/` |

## <a name="install"></a>安装

### 一键安装（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/mapick-ai/mapickii/v1.0.1/install.sh | bash
```

或使用 wget：

```bash
wget -qO- https://raw.githubusercontent.com/mapick-ai/mapickii/v1.0.1/install.sh | bash
```

仅安装到当前项目：

```bash
MAPICKII_LOCAL=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/mapick-ai/mapickii/v1.0.1/install.sh)"
```

指定版本：

```bash
MAPICKII_VERSION=v1.0.0 bash -c "$(curl -fsSL https://raw.githubusercontent.com/mapick-ai/mapickii/main/install.sh)"
```

### 本地安装（开发者）

```bash
# 在 mapick 仓库根目录
bash .shell/mapickii.sh            # 安装到 ~/.claude/skills/mapickii/
bash .shell/mapickii.sh openclaw   # 安装到 ~/.openclaw/skills/mapickii/
bash .shell/mapickii.sh project    # 安装到 <project>/.claude/skills/mapickii/
```

### 手动安装

```bash
git clone https://github.com/mapick-ai/mapickii.git
bash mapickii/install.sh
```

## <a name="commands"></a>命令

安装后在 AI 工具中使用 `/mapickii <command>`：

### M1 · 生命周期

| 命令                   | 说明                                      |
| ---------------------- | ----------------------------------------- |
| `/mapickii`            | 状态总览                                  |
| `/mapickii status`     | 详细状态（活跃 / 低频 / 僵尸 / 从未调用） |
| `/mapickii clean`      | 列出僵尸 Skill，选择卸载                  |
| `/mapickii workflow`   | 高频使用序列与套装匹配                    |
| `/mapickii daily`      | 日报（昨日产出 + 今日推荐）               |
| `/mapickii weekly`     | 周报（本周总结 + 趋势）                   |
| `/mapickii scan`       | 本地 Skill 扫描                           |
| `/mapickii chat <msg>` | 自然语言兜底                              |

### M3 · 套装推荐

| 命令                            | 说明                             |
| ------------------------------- | -------------------------------- |
| `/mapickii bundle`              | 套装列表                         |
| `/mapickii bundle <id>`         | 套装详情（已装 / 缺失 + 配对率） |
| `/mapickii bundle recommend`    | 基于已装 Skill 推荐套装          |
| `/mapickii bundle install <id>` | 一键补全缺失 Skill               |

### 身份与推荐码

| 命令                      | 说明                           |
| ------------------------- | ------------------------------ |
| `/mapickii register`      | 注册新 Mapick 身份             |
| `/mapickii id`            | 查看当前身份                   |
| `/mapickii login <MP-ID>` | 绑定已有 Mapick ID             |
| `/mapickii ref`           | 查看推荐码与推荐人数           |
| `/mapickii ref <code>`    | 绑定推荐码（一次性，不可更改） |

### 卸载

| 命令                                                                  | 说明                        |
| --------------------------------------------------------------------- | --------------------------- |
| `/mapickii uninstall <skillId>`                                       | Dry-run，返回将要删除的路径 |
| `/mapickii uninstall <skillId> --confirm`                             | 确认删除（备份 + rm -rf）   |
| `/mapickii uninstall <skillId> --scope user\|project\|both --confirm` | 按范围删除                  |

受保护 Skill：`mapickii` / `mapick` / `tasa` 不可删除。

### 推送频率

| 命令                    | 说明     |
| ----------------------- | -------- |
| `/mapickii push daily`  | 每日推送 |
| `/mapickii push weekly` | 每周推送 |
| `/mapickii push off`    | 静音     |

## 自然语言触发

无需 `/mapickii` 前缀，以下自然语言直接命中：

- **「状态」「怎么样」「Skill 库」** → `status`
- **「清理」「僵尸」「没用的」** → `clean`
- **「工作流」「常用组合」** → `workflow`
- **「日报」「今天怎么样」** → `daily`
- **「周报」「本周」** → `weekly`
- **「套装」「套装推荐」** → `bundle:recommend`
- **「别推了」「静音」「勿扰」** → `push:off`
- **「改周推」「少推点」** → `push:weekly`
- **「开推送」「恢复推送」** → `push:daily`

## 生命周期模型

```
安装 ──→ 首次使用 ──→ 持续使用 ──→ 频率下降 ──→ 僵尸状态 ──→ 卸载
   ↑           ↑             ↑              ↑             ↑          ↑
Mapickii    Mapickii       Mapickii       Mapickii      Mapickii    用户
   扫描        记录           记录           记录          标记      触发
```

| 阶段     | 触发条件        | 行为                        |
| -------- | --------------- | --------------------------- |
| 安装     | Skill 目录存在  | 记录安装时间、路径          |
| 首次使用 | 首次调用        | 识别激活延迟                |
| 激活超时 | 安装 7 天未调用 | 标记 `activation_timeout`   |
| 持续使用 | 7 日调用 ≥ 2 次 | 计算频率、识别序列          |
| 频率下降 | 本周 < 上周 50% | 内部标记                    |
| 僵尸状态 | 30 天无调用     | 标记 `zombie`，加入清理推荐 |
| 卸载     | 用户主动        | 记录原因、备份到 `trash/`   |

## 隐私

- 对话与代码**永不离开设备**
- 仅收集匿名行为信号：`skill_id`、`timestamp`、`task_classification`
- 身份配置本地存储（`CONFIG.md`）
- 无云端社交数据存储

## 目录结构

```
mapickii/
├── README.md          # 英文版（默认）
├── README.zh-CN.md    # 本文档（中文版）
├── SKILL.md           # Skill 指导文档（AI 读取）
├── CONFIG.md          # 用户身份配置（升级时保留）
├── install.sh         # 远程一键安装脚本
├── scripts/
│   └── shell.sh       # 命令执行脚本
├── v1/                # v1 备份
└── v2.1/              # v2.1 备份
```

## 版本历史

| 版本 | 日期       | 变更                       |
| ---- | ---------- | -------------------------- |
| v3.0 | 2026-04-18 | 新增 M3 套装推荐           |
| v2.1 | 2026-04-18 | 智能推荐 + 缓存机制        |
| v2.0 | 2026-04-18 | 同步文档规范、生命周期模型 |
| v1.0 | 2026-04-17 | 基础功能实现               |

## License

[MIT](LICENSE) © 2026 Mapick.AI
