---
name: mapickii
description: Mapickii — Mapick 智能管家。M1 生命周期管理、M2 智能推荐、M3 套装推荐。Skill 状态总览、僵尸清理、套装推荐、日报周报、推荐码管理。
---

# Mapickii

Mapickii — Mapick 智能管家。

整合 M1/M2/M3/M4 三大模块，为用户提供完整的 Skill 生命周期管理、智能推荐和套装推荐体验。

## 核心能力

- **M1 生命周期管理**：状态总览、僵尸清理、工作流分析、日报、周报
- **M2 智能推荐**：每次交互返回推荐 Skill，24 小时缓存
- **M3 套装推荐**：套装列表、套装详情、套装补全推荐
- **M4 安全评分**：每个 Skill 的安全风险评估，帮助用户做出明智选择
- **身份管理**：注册、绑定已有身份、本地模式
- **推荐码系统**：查看推荐信息、绑定推荐码
- **推送策略**：日推 / 周推 / 静音，立即生效

## 生命周期模型

```
安装 ──→ 首次使用 ──→ 持续使用 ──→ 频率下降 ──→ 僵尸状态 ──→ 卸载
  ↑           ↑             ↑              ↑             ↑          ↑
 Mapickii    Mapickii       Mapickii       Mapickii      Mapickii     用户
  扫描        记录           记录           记录          标记      触发
```

| 阶段         | 触发条件        | Mapickii 行为               |
| ------------ | --------------- | --------------------------- |
| **安装**     | Skill 目录存在  | scan 记录安装时间、路径     |
| **首次使用** | 首次调用        | 识别激活延迟                |
| **激活超时** | 安装 7 天未调用 | 标记 `activation_timeout`   |
| **持续使用** | 7 日调用 ≥ 2 次 | 计算频率、识别序列          |
| **频率下降** | 本周 < 上周 50% | 内部标记                    |
| **僵尸状态** | 30 天无调用     | 标记 `zombie`，加入清理推荐 |
| **卸载**     | 用户主动        | 记录原因、备份到 trash/     |

## 自动触发（每次对话开始执行一次）

对话开始时**主动**跑一次 `init`：

```bash
R=$(bash scripts/shell.sh init 2>/dev/null); echo "$R"
```

**按 JSON 的 `status` 字段决定如何回复：**

| `status`                      | 条件                                   | Claude 该做什么                                                         |
| ----------------------------- | -------------------------------------- | ----------------------------------------------------------------------- |
| `first_install`               | config 不存在 / device_fp 空 / mode 空 | 直接输出 `welcome.render` 原文，追加「回复 **1**、**2** 或 **3** 开始」 |
| `initialized`                 | mode 已设置 + 首次跑完 init            | 展示简版身份卡                                                          |
| `rescanned` + `changed:true`  | 到期重扫 + 本地 skill 有变化           | 只提示「检测到环境变化」                                                |
| `rescanned` + `changed:false` | 到期重扫但无变化                       | 完全静默                                                                |
| `skip`                        | 距上次 init 不足 30 分钟               | 完全静默                                                                |

### 首次欢迎（`status: "first_install"`）

Shell 返回结构化 JSON，`welcome.render` 字段包含报纸风格的 Markdown：

```json
{
  "status": "first_install",
  "welcome": { "render": "..." },
  "data": { "deviceFingerprint": "...", "skillsCount": 3 },
  "actions": [
    { "key": "1", "label": "注册账号", "command": "register" },
    { "key": "2", "label": "绑定已有", "command": "login" },
    { "key": "3", "label": "立即使用", "command": "skip-onboard" }
  ]
}
```

Claude **直接输出 `welcome.render` 原文**，然后追加：

```
回复 **1**、**2** 或 **3** 开始。
```

等待用户回复：

- **1** → 执行 `register`（API 返回 mapickId → 写入 config → mode=registered）
- **2** → 追问「请输入你的 Mapick ID（MP-xxxxxxxx）」；收到后执行 `login <MP-ID>`
- **3** → 执行 `skip-onboard`（mode=local）

**重点：first_install 是幂等的** —— 用户不回复就关对话，下次还会收到 first_install（直到 mode 被设置）。

## 执行方式

所有命令通过 `scripts/shell.sh` 调用：

```bash
R=$(bash scripts/shell.sh <command> [args...] 2>/dev/null); echo "$R"
```

收到 JSON 后按下方模板格式化输出。用户不应看到 Bash 命令或原始 JSON。

## 命令参考

### 生命周期

| 用户输入               | 执行         | 说明           |
| ---------------------- | ------------ | -------------- |
| `/mapickii`            | status       | Skill 状态总览 |
| `/mapickii status`     | status       | 详细状态       |
| `/mapickii clean`      | clean        | 僵尸列表       |
| `/mapickii workflow`   | workflow     | 工作流分析     |
| `/mapickii daily`      | daily        | 日报           |
| `/mapickii weekly`     | weekly       | 周报           |
| `/mapickii scan`       | scan         | 本地扫描       |
| `/mapickii chat <msg>` | chat "<msg>" | 自然语言兜底   |

### 身份管理

| 用户输入                  | 执行          | 说明               |
| ------------------------- | ------------- | ------------------ |
| `/mapickii register`      | register      | 注册新 Mapick 身份 |
| `/mapickii id`            | id            | 查看当前身份       |
| `/mapickii login <MP-ID>` | login <MP-ID> | 绑定已有 Mapick ID |

### 推荐码

| 用户输入               | 执行       | 说明         |
| ---------------------- | ---------- | ------------ |
| `/mapickii ref`        | ref        | 查看推荐信息 |
| `/mapickii ref <code>` | ref <code> | 绑定推荐码   |

**推荐码规则：**

- 注册时自动生成 6 位推荐码（如 `TBSHAG`）
- 推荐码只能绑定一次，绑定后不可修改
- 不能绑定自己的推荐码
- 绑定成功后推荐人 `referralCount += 1`

### 套装推荐（M3）

套装推荐解决「单点推荐」的局限，用户不只需要一个 Skill，需要完成完整工作流的一套工具。

| 用户输入                        | 执行                | 说明                       |
| ------------------------------- | ------------------- | -------------------------- |
| `/mapickii bundle`              | bundle              | 套装列表                   |
| `/mapickii bundle <id>`         | bundle <id>         | 套装详情                   |
| `/mapickii bundle recommend`    | bundle:recommend    | 推荐套装（基于已装 Skill） |
| `/mapickii bundle install <id>` | bundle:install <id> | 安装套装                   |

**套装触发条件：**

1. 用户装了套装中的触发 Skill → 立即推荐
2. 用户装了套装中 25%-75% 的 Skill → 推荐补全
3. 用户通过 Onboarding 选择场景 → 推荐对应套装

**套装数据结构：**

```json
{
  "bundleId": "fullstack-dev",
  "name": "全栈开发者套装",
  "skillIds": ["github-ops", "docker-compose", "api-testing"],
  "triggerSkillIds": ["github-ops"],
  "targetAudience": "全栈开发者"
}
```

**套装渲染模板：**

```
🗂️ 全栈开发者套装

你已经装了 2/4 个
✅ GitHub Ops
✅ Docker 管理

推荐补全:
1. ⬜ CI/CD Pipeline
2. ⬜ AI 代码审查

💡 回复「安装套装」一键补全
```

### 推送频率

| 用户输入                | 执行        | 说明     |
| ----------------------- | ----------- | -------- |
| `/mapickii push daily`  | push:daily  | 每日推送 |
| `/mapickii push weekly` | push:weekly | 每周推送 |
| `/mapickii push off`    | push:off    | 静音     |

### 卸载 / 删除

| 用户输入                                    | 执行                          | 说明                        |
| ------------------------------------------- | ----------------------------- | --------------------------- | ----------------- | ---------------------- |
| `/mapickii uninstall <skillId>`             | uninstall <skillId>           | Dry-run，返回将要删除的路径 |
| `/mapickii uninstall <skillId> --confirm`   | uninstall <skillId> --confirm | 确认删除（备份 + rm -rf）   |
| `/mapickii uninstall <skillId> --scope user | project                       | both --confirm`             | 按 scope 过滤删除 | 用户级 / 项目级 / 全部 |

**受保护 Skill**：mapickii / mapick / tasa 无法删除

## 自动触发规则

以下自然语言模式自动调用对应命令（无需 `/mapickii`）。

### 状态查询 → `status`

中文：状态、状况、怎么样、Skill 库、总览、报表、我装了多少、看看 Skill
英文：status、overview、dashboard、my skills、skill stats

### 僵尸清理 → `clean`

中文：清理、僵尸、没用的、垃圾、瘦身、删掉没用的
英文：clean、cleanup、zombies、dead skills、unused、prune

### 工作流 → `workflow`

中文：工作流、流程、常用组合、Skill 搭配、流水线
英文：workflow、routine、pipeline、skill chain

### 日报 → `daily`

中文：日报、今天怎么样、昨天、今日摘要
英文：daily、today、yesterday、daily report

### 周报 → `weekly`

中文：周报、本周、一周总结、上周怎么样
英文：weekly、this week、weekly report

### 推送关停 → `push:off`

中文：别推了、静音、关推送、勿扰、太吵了
英文：mute、silence、stop pushing、do not disturb

### 推送降频 → `push:weekly`

中文：改周推、一周一次、少推点
英文：weekly push、once a week

### 推送开启 → `push:daily`

中文：开推送、每天推、恢复推送
英文：enable push、daily push、resume push

### 清理对话流回复 → `clean:track`

上一条消息是 `clean` 列表时：

- 数字：`1` / `2 4` → 按索引取出 skillId，执行 `clean:track <skillId>`
- `全部` / `all` → 对全部僵尸执行 `clean:track`
- `跳过` / `skip` → 结束清理

卸载原因询问（每个 skill 逐个）：1. 功能重复 2. 太复杂 3. 不如预期 4. 临时用的 5. 其他

### 套装推荐 → `bundle:recommend`

中文：套装、套装推荐、推荐套装、套装列表、我要套装
英文：bundle、bundles、bundle recommend

### 兜底 → `chat <msg>`

不匹配以上规则 → 原文传给 `chat`，后端自然语言路由。

## 智能推荐

每次交互都会返回推荐 Skill，基于以下逻辑：

| 命令                              | 推荐来源   | 说明                  |
| --------------------------------- | ---------- | --------------------- |
| init/status/workflow/daily/weekly | API → 缓存 | 基于用户画像推荐      |
| clean                             | 本地缓存   | 无 API 推荐，读取缓存 |
| scan/ref/push:\*                  | 本地缓存   | 无 API 推荐，读取缓存 |

### 推荐数据结构

返回 JSON 中包含 `recommendations` 字段：

```json
{
  "intent": "status",
  "message": "...",
  "data": { ... },
  "recommendations": [
    { "skillId": "azure-ai", "skillName": "Azure AI", "reason": "热门 Skill", "score": 0.85 }
  ]
}
```

### CONFIG.md 存储

推荐数据缓存到 CONFIG.md：

```yaml
recommendations:
  cached_at: 2026-04-18T...
  source: api
  items:
    - skillId: azure-ai
      skillName: Azure AI
      reason: 热门 Skill
      score: 0.85
```

缓存有效期：24 小时

### 响应缓存

为减少网络请求，以下数据会缓存到 CONFIG.md：

| 数据     | 缓存键         | TTL   | 说明            |
| -------- | -------------- | ----- | --------------- |
| status   | status_cache   | 5分钟 | Skill 库状态    |
| zombies  | zombies_cache  | 1小时 | 僵尸 Skill 列表 |
| workflow | workflow_cache | 1小时 | 工作流分析      |

缓存逻辑：

- 第一次请求 → 请求 API + 保存缓存
- TTL 内再次请求 → 直接读取缓存，不请求 API
- TTL 过期 → 重新请求 API + 更新缓存

环境变量控制 TTL：

```bash
STAGE_STATUS_TTL=5    # status 缓存分钟数
STAGE_ZOMBIES_TTL=60  # zombies 缓存分钟数
STAGE_WORKFLOW_TTL=60 # workflow 缓存分钟数
```

### 推荐渲染规则

每次输出末尾追加推荐（最多 3 条）：

```
💡 推荐安装
1. {skillName} — {reason}
2. {skillName} — {reason}
回复数字安装
```

## 输出渲染

### 视觉语言（报纸风）

- 段落标题：`emoji + 标题` 独占一行
- 重分割线：`━━━━━━━━━━━━━━━`（15 字符）
- 同行数据：用 `|` 连接
- 趋势箭头：`↑` / `↓` / `→`
- 提示行：💡 / 🧹 / ⚠️ / ✅ 放在段末
- **禁用**：`##`/`###` 标题、整段代码块、引用

### 状态总览（`status`）

```
📊 你的 Skill 状态

Skill 库
━━━━━━━━━━━━━━━
总计 {total} 个 | 活跃 {active} | 僵尸 {zombie} | 从未用过 {never}
活跃率 {activeRate}%

🔥 核心工作流
{workflow1} → {workflow2} → {workflow3}（每天 {freq} 次）

阶段分布
━━━━━━━━━━━━━━━
首次使用中 {firstUse} | 持续使用 {active} | 频率下降 {declining} | 僵尸 {zombie}

🧹 有 {zombieCount} 个僵尸 Skill，回复「清理」处理
💡 回复「工作流」看详情
```

### 僵尸清理列表（`clean`）

```
🧹 发现 {n} 个僵尸 Skill（30 天未使用）

1. {skill1} — {daysUnused} 天未用，共用过 {totalUse} 次
2. {skill2} — {daysUnused} 天未用，共用过 {totalUse} 次

回复数字卸载（如「1 2 4」）
回复「全部」一键卸载
回复「跳过」暂不处理
```

### 卸载原因询问

```
卸载 {skillName} — 为什么不用了？
1. 功能重复  2. 太复杂  3. 不如预期  4. 临时用的  5. 其他
```

### 工作流（`workflow`）

```
📈 你的工作流模式

发现 {n} 个核心工作流（每周 3 次以上）

1️⃣ {workflowName}
   {skill1} → {skill2} → {skill3}
   每周 {freq} 次

💡 有 {n} 个 Skill 可以补全工作流
```

### 日报（`daily`）

```
📬 你的 Mapickii 日报 · {date}

昨日
━━━━━━━━━━━━━━━
{invokes} 次调用 | 活跃 Skill {activeCount} 个
活跃：{topSkill1}、{topSkill2}、{topSkill3}

阶段变化
━━━━━━━━━━━━━━━
新增首用 {firstUseCount} | 进入僵尸 {newZombie} | 已卸载 {uninstalled}

💡 回复「周报」看完整汇总
```

### 周报（`weekly`）

```
📊 你的 Mapickii 周报（{startDate} - {endDate}）

Skill 库
━━━━━━━━━━━━━━━
活跃 {active}/{total} | 新增僵尸 {newZombies} | 清理了 {cleaned}

阶段流转
━━━━━━━━━━━━━━━
首用 → 持续 {toActive}
持续 → 下降 {toDeclining}
下降 → 僵尸 {toZombie}

🧹 有 {zombieCount} 个僵尸，回复「清理」
💡 推送频率：{pushMode}
```

### 本地扫描（`scan`）

```
🔍 本地环境已重新扫描

Skill
━━━━━━━━━━━━━━━
共 {n} 个 | 启用 {enabled} | 禁用 {disabled}
最近改动：{topModifiedSkill}（{mtime}）

系统
━━━━━━━━━━━━━━━
{os} {arch} | Node {nodeVersion} | Python {pythonVersion}
编辑器：{editorLabels}

扫描耗时 {durationMs}ms
```

### 推送频率切换

**off：**

```
✅ 推送已静音
再也不打扰你了。回复「开推送」恢复。
```

**weekly：**

```
✅ 推送频率已改为每周
下次推送：{nextPushDate}（周一早）
```

**daily：**

```
✅ 推送频率已改为每日
每日摘要会在早上推送。
```

### 卸载成功

```
✅ 已删除 {skillName}

删除路径：
  {path}

备份位置
━━━━━━━━━━━━━━━
~/.config/mapickii/trash/{skillId}-{ts}/
误删了？cp -r 回去即可
```

### 卸载 - 受保护

```
⚠️ {skillId} 是受保护的 skill，无法删除

受保护名单：mapickii / mapick / tasa
这些是 Mapick 生态的核心 skill。
```

### 初始化完成（`status: "initialized"`）

```
👋 Mapickii 已就绪

身份
━━━━━━━━━━━━━━━
模式       {mode：已注册/已绑定/本地}
Mapick ID  {mapickId 或 "本地身份"}
设备       {deviceFingerprint 前 8 位}
本地已装   {skillsCount} 个 Skill

💡 试试：/mapickii status / /mapickii clean / /mapickii workflow
```

### 环境变化通知（`status: "rescanned"` + `changed: true`）

- 仅新增：`🔍 检测到新装了 skill：{name1}、{name2}`
- 仅卸载：`🔍 检测到已卸载 skill：{name1}、{name2}`
- 同时有：`🔍 环境变化：新装 {newList}，卸载 {removedList}`

### 注册 / 绑定 / 跳过完成

```
✅ {已注册 / 已绑定 / 已进入本地模式}

身份
━━━━━━━━━━━━━━━
Mapick ID  {mapickId 或 "本地身份"}
设备       {deviceFingerprint 前 8 位}

💡 开始使用：/mapickii status / /mapickii clean / /mapickii workflow
```

### 推荐码查看（`ref`）

```
🎁 推荐码

Mapick ID   {mapickId}
推荐码      {referralCode}
已推荐      {referralCount} 人

{已绑定推荐人 → 显示推荐人推荐码}
{未绑定 → 💡 绑定推荐码获得奖励：ref <推荐码>}
```

## CONFIG.md 结构

Mapickii 使用 YAML 格式存储配置：

```yaml
# Mapickii Configuration
device_fp: c68a42c49e1f5abd
created_at: 2026-04-18T...
mapick_id: MP-dccf3c67
mode: registered # local / registered / bound
referral_code: TBSHAG
referred_by: QDRVVT
last_init_at: 2026-04-18T...

scan:
  scanned_at: 2026-04-18T...
  skills:
    - id: mapick
      name: mapick
      path: /Users/...
      installed_at: 2026-04-14T...
      enabled: true
  system:
    os: Darwin
    arch: arm64
    node_version: v22.22.0
```

**字段说明：**

| 字段            | 说明                                 |
| --------------- | ------------------------------------ |
| `device_fp`     | 设备指纹（16 位 hash）               |
| `mapick_id`     | Mapick ID（MP-xxxxxxxx）             |
| `mode`          | 身份模式：local / registered / bound |
| `referral_code` | 用户自己的推荐码                     |
| `referred_by`   | 绑定的推荐人推荐码                   |
| `scan.skills`   | 本地 Skill 列表                      |
| `scan.system`   | 系统环境信息                         |

## 错误处理

| error                 | 说明                             |
| --------------------- | -------------------------------- |
| `unknown_command`     | 命令不存在                       |
| `missing_argument`    | 参数缺失                         |
| `protected_skill`     | 受保护 Skill 禁止删除            |
| `service_unreachable` | API 不可达                       |
| `bind_failed`         | 推荐码绑定失败                   |
| `ambiguous_scope`     | 卸载时找到多处副本，需指定 scope |
| `backup_failed`       | 备份失败（磁盘空间不足）         |
| `permission_denied`   | 权限不足                         |

### 后端不可达

```
⚠️ 连不上 Mapickii 后端
请联系开发者。
```

### chat 超时

```
🤔 想了太久，换个更具体的说法？试试「状态」「清理」「工作流」。
```

## 关键规则

1. **不暴露原始 JSON**：所有输出按模板渲染
2. **隐私**：只采集匿名行为（skill_id + timestamp），对话内容不离开设备
3. **推送关停即时响应**：用户说「别推了」立即执行 `push:off`
4. **清理卸载逐个确认原因**：每个 skill 单独问一次 1-5 原因
5. **受保护 Skill**：mapickii / mapick / tasa 只记录不删除
