发现了一个大遗漏
[下午 5:54]Mapickii 能不能接入 OpenClaw？能。但有几个要改的。
OpenClaw Skill 的工作原理
OpenClaw 的 Skill 就是一个文件夹，里面有一个 SKILL.md（YAML frontmatter + 自然语言指令）。AI 读 SKILL.md 知道怎么用这个 Skill。工程师写的架构方向是对的。
关键确认：
   问题 答案 Mapickii 现状     Skill 放哪里？ ~/.openclaw/skills/<skill-name>/SKILL.md :white_check_mark: 对的   AI 怎么发现 Skill？ OpenClaw 启动时读所有 SKILL.md 的 frontmatter :white_check_mark: 对的   SKILL.md 格式？ YAML frontmatter（name + description 必填）+ 自然语言指令 :warning: 要查   AI 怎么调 Skill？ AI 读 SKILL.md 的指令，用 bash / exec 工具调脚本 :white_check_mark: 对的   安装方式？ openclaw skills install <slug> 或手动放文件夹 :warning: 要对齐   metadata 格式？ 单行 JSON，放在 frontmatter 里 :warning: 要加   {baseDir} 占位符？ SKILL.md 里可以用 {baseDir} 引用 Skill 文件夹路径 :warning: 要用   要改的 3 个地方

1. SKILL.md frontmatter 必须加 metadata 行
   OpenClaw 要求 frontmatter 里有 metadata（单行 JSON），声明依赖。Mapickii 的 SKILL.md 现在只有 name 和 description，没有 metadata。
   要加：

---

name: mapickii
description: AI-native Skill recommendation engine — discover, protect, clean
metadata: { "openclaw": { "requires": { "bins": ["python3", "jq", "curl"] } } }
---这样 OpenClaw 启动时会检查 python3 / jq / curl 是否在 PATH 上，不在就不加载这个 Skill。2. SKILL.md 里引用脚本路径要用 {baseDir}
现在 Mapickii 的 SKILL.md 写死了路径：
bash ~/.openclaw/skills/mapickii/scripts/shell.sh statusOpenClaw 提供了 {baseDir} 占位符，AI 会自动替换成 Skill 实际路径。应该改为：
bash {baseDir}/scripts/shell.sh status这样不管 Skill 装在 ~/.openclaw/skills/ 还是 <workspace>/skills/ 还是 ~/.agents/skills/，路径都对。3. 发布到 ClawHub 的安装方式
Mapickii 现在用 curl | bash 安装。如果要在 ClawHub 上架，应该用 OpenClaw 的原生安装方式：
openclaw skills install mapickii这意味着要在 ClawHub 上发布（clawhub skill publish），不用自己写 install.sh 了。
但 V1 可以暂时两种都支持：

ClawHub 原生安装（主推）
curl | bash 安装（兜底，给不用 ClawHub 的用户）

我现在帮你做的事
我帮你把 SKILL.md 的 frontmatter 修正写出来，加上 metadata 和 {baseDir} 的改动，让工程师知道怎么改。不写大文档，直接给要改的内容：

工程师改动清单（OpenClaw 兼容性）
改动 1：SKILL.md frontmatter 加 metadata

---

name: mapickii
description: AI-native Skill recommendation engine — discover, protect, clean your Skill library
metadata: { "openclaw": { "emoji": "🔍", "requires": { "bins": ["python3", "jq", "curl"] }, "primaryEnv": "MAPICKII_API_BASE" } }
---改动 2：SKILL.md 里所有脚本路径改 {baseDir}
全文搜索替换：
~/.openclaw/skills/mapickii/ → {baseDir}/例如：

# 改前

bash ~/.openclaw/skills/mapickii/scripts/shell.sh status

# 改后

bash {baseDir}/scripts/shell.sh status

# 改前

echo "text" | python3 ~/.openclaw/skills/mapickii/scripts/redact.py

# 改后

echo "text" | python3 {baseDir}/scripts/redact.py改动 3：shell.sh 里 CONFIG_DIR 的默认值
shell.sh 里 CONFIG_DIR 写死的路径也要改。用 $0 的目录来推导：

# 改前

CONFIG_DIR="${HOME}/.openclaw/skills/mapickii"

# 改后

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/.." # shell.sh 在 scripts/ 目录下，上一级就是 Skill 根改动 4（可选）：发布到 ClawHub
cd ~/.openclaw/skills/mapickii
clawhub skill publish .这会把 Mapickii 发布到 ClawHub，用户就可以用 openclaw skills install mapickii 一键安装。
V1 上线后再做这个也行，先把前 3 个改完保证能跑。

总结：Mapickii 的架构方向跟 OpenClaw 100% 兼容。 “文件夹 + SKILL.md + AI 读指令调 bash” 就是 OpenClaw 的原生 Skill 模式。只需要改 frontmatter 格式 + 路径占位符，不用重构。
工程师做这 3 个改动大概 30 分钟，建议合进 PR-1（API 安全 + 扫描收缩 OpenClaw 那个 PR，本来就是做 OpenClaw 适配的）。
