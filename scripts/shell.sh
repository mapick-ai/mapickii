#!/usr/bin/env bash
# Mapickii skill unified entry point
# Usage: bash shell.sh <command> [args...]

set -euo pipefail

# ── 常量区 ────────────────────────────────────────────
API_BASE="${MAPICKII_API_BASE:-http://127.0.0.1:3010/api/v1}"

# Mapickii 安装路径（scripts/ 的父目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${CONFIG_DIR}/CONFIG.md"

# 检测当前 CLI 环境并设置技能扫描路径
# 优先级：CONFIG_DIR 所在位置 > 环境变量 > 默认 OpenCode
_detect_skills_base() {
  # 1. 根据安装路径判断
  if [[ "${CONFIG_DIR}" == "${HOME}/.openclaw/skills/mapickii" ]]; then
    echo "${HOME}/.openclaw/skills"
    return
  fi
  if [[ "${CONFIG_DIR}" == "${HOME}/.claude/skills/mapickii" ]]; then
    echo "${HOME}/.claude/skills"
    return
  fi
  
  # 2. 检查项目级安装
  if [[ -d "${CONFIG_DIR}/../../.openclaw/skills" ]]; then
    cd "${CONFIG_DIR}/../../.openclaw/skills" && pwd
    return
  fi
  if [[ -d "${CONFIG_DIR}/../../.claude/skills" ]]; then
    cd "${CONFIG_DIR}/../../.claude/skills" && pwd
    return
  fi
  
  # 3. 默认 OpenCode
  echo "${HOME}/.claude/skills"
}

SKILLS_BASE_DIR="$(_detect_skills_base)"

MAPICKII_INIT_INTERVAL_MINUTES="${MAPICKII_INIT_INTERVAL_MINUTES:-30}"

MAPICKII_API_KEY="${MAPICKII_API_KEY:-${MAPICK_API_KEY:-5c4b9615136a6b85e27b47ea6b1d13c4}}"
MAPICKII_API_SECRET="${MAPICKII_API_SECRET:-${MAPICK_API_SECRET:-65301d4e3193f7f3fc79700e97445070afbdd256ad314cc0b7e317a8585c89f8}}"

# ── CONFIG.md 读写（YAML 格式）────────────────────────────
_ensure_config() {
  [[ -f "${CONFIG_FILE}" ]] || cat > "${CONFIG_FILE}" <<EOF
# Mapickii Configuration
# Auto-generated — do not delete manually

EOF
}

_config_get() {
  local key="$1"
  if [[ -f "${CONFIG_FILE}" ]]; then
    grep -E "^${key}:" "${CONFIG_FILE}" 2>/dev/null | head -1 | sed "s/^${key}:[[:space:]]*//" || true
  fi
}

_config_set() {
  local key="$1" value="$2"
  _ensure_config
  if grep -qE "^${key}:" "${CONFIG_FILE}" 2>/dev/null; then
    if sed --version 2>/dev/null | grep -q GNU; then
      sed -i "s|^${key}:.*|${key}: ${value}|" "${CONFIG_FILE}"
    else
      sed -i '' "s|^${key}:.*|${key}: ${value}|" "${CONFIG_FILE}"
    fi
  else
    echo "${key}: ${value}" >> "${CONFIG_FILE}"
  fi
}

_config_del() {
  local key="$1"
  if [[ -f "${CONFIG_FILE}" ]] && grep -qE "^${key}:" "${CONFIG_FILE}" 2>/dev/null; then
    if sed --version 2>/dev/null | grep -q GNU; then
      sed -i "/^${key}:.*$/d" "${CONFIG_FILE}"
    else
      sed -i '' "/^${key}:.*$/d" "${CONFIG_FILE}"
    fi
  fi
}

CACHE_STATUS_TTL_MINUTES="${MAPICKII_STATUS_TTL:-5}"
CACHE_ZOMBIES_TTL_MINUTES="${MAPICKII_ZOMBIES_TTL:-60}"
CACHE_WORKFLOW_TTL_MINUTES="${MAPICKII_WORKFLOW_TTL:-60}"

_cache_write() {
  local key="$1"
  local data="$2"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  _config_set "${key}_cached_at" "$ts"
  
  data_clean="$(echo "$data" | sed 's/\\n/ /g' | tr -d '\n\r')"
  
  if grep -qE "^${key}_cache:" "${CONFIG_FILE}" 2>/dev/null; then
    python3 -c "
import sys
config_file = '${CONFIG_FILE}'
key = '${key}'
try:
    with open(config_file) as f:
        lines = f.readlines()
except:
    sys.exit(0)

result = []
in_cache = False
for line in lines:
    if line.startswith(f'{key}_cache:'):
        in_cache = True
    elif in_cache:
        if not (line.startswith('  ') or line.startswith('    ') or line.strip() == ''):
            in_cache = False
            result.append(line)
    else:
        result.append(line)

with open(config_file, 'w') as f:
    f.writelines(result)
"
  fi
  
  echo "${key}_cache: ${data_clean}" >> "${CONFIG_FILE}"
}

_cache_read() {
  local key="$1"
  local ttl_minutes="$2"
  
  if ! grep -qE "^${key}_cache:" "${CONFIG_FILE}" 2>/dev/null; then
    echo ""
    return
  fi
  
  local cached_at
  cached_at="$(_config_get "${key}_cached_at")"
  
  if [[ -z "$cached_at" ]]; then
    echo ""
    return
  fi
  
  local cached_epoch now_epoch diff
  if date -u -d "$cached_at" +%s >/dev/null 2>&1; then
    cached_epoch="$(date -u -d "$cached_at" +%s)"
  else
    cached_epoch="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$cached_at" +%s 2>/dev/null || echo 0)"
  fi
  [[ -z "$cached_epoch" ]] && cached_epoch=0
  now_epoch="$(date -u +%s)"
  diff=$(( (now_epoch - cached_epoch) / 60 ))
  
  if [[ $diff -ge $ttl_minutes ]]; then
    echo ""
    return
  fi
  
  grep "^${key}_cache:" "${CONFIG_FILE}" 2>/dev/null | sed "s/^${key}_cache:[[:space:]]*//" || true
}

_cache_valid() {
  local key="$1"
  local ttl_minutes="$2"
  
  local cached_at
  cached_at="$(_config_get "${key}_cached_at")"
  
  if [[ -z "$cached_at" ]]; then
    return 1
  fi
  
  local cached_epoch now_epoch diff
  if date -u -d "$cached_at" +%s >/dev/null 2>&1; then
    cached_epoch="$(date -u -d "$cached_at" +%s)"
  else
    cached_epoch="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$cached_at" +%s 2>/dev/null || echo 0)"
  fi
  [[ -z "$cached_epoch" ]] && return 1
  now_epoch="$(date -u +%s)"
  diff=$(( (now_epoch - cached_epoch) / 60 ))
  
  [[ $diff -lt $ttl_minutes ]]
}

RECOMMENDATION_TTL_HOURS="${MAPICKII_REC_TTL:-24}"

_save_recommendations() {
  local rec_json="$1"
  if [[ -z "$rec_json" ]] || [[ "$rec_json" == "[]" ]]; then
    return
  fi
  
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  if grep -qE "^recommendations:" "${CONFIG_FILE}" 2>/dev/null; then
    python3 -c "
import sys
config_file = '${CONFIG_FILE}'
try:
    with open(config_file) as f:
        lines = f.readlines()
except:
    sys.exit(0)

result = []
in_rec = False
for line in lines:
    if line.startswith('recommendations:'):
        in_rec = True
    elif in_rec:
        if not (line.startswith('  ') or line.startswith('    ') or line.strip() == ''):
            in_rec = False
            result.append(line)
    else:
        result.append(line)

with open(config_file, 'w') as f:
    f.writelines(result)
"
  fi
  
  python3 -c "
import json
rec_json = '''${rec_json}'''
ts = '${ts}'
config_file = '${CONFIG_FILE}'
try:
    items = json.loads(rec_json)
except:
    items = []

with open(config_file, 'a') as f:
    f.write('recommendations:\n')
    f.write(f'  cached_at: {ts}\n')
    f.write(f'  source: api\n')
    f.write('  items:\n')
    for item in items[:5]:
        f.write(f'    - skillId: {item.get(\"skillId\", \"?\")}\n')
        f.write(f'      skillName: {item.get(\"skillName\", \"?\")}\n')
        f.write(f'      reason: {item.get(\"reason\", \"\")}\n')
        f.write(f'      score: {item.get(\"score\", 0)}\n')
"
}

_load_recommendations() {
  local ttl="${RECOMMENDATION_TTL_HOURS}"
  [[ "$ttl" == "0" ]] && echo '[]' && return
  
  if ! grep -qE "^recommendations:" "${CONFIG_FILE}" 2>/dev/null; then
    echo '[]'
    return
  fi
  
  CONFIG_FILE="$CONFIG_FILE" TTL="$ttl" python3 <<PYEOF
import os, json, yaml
from datetime import datetime, timezone

config_file = os.environ.get("CONFIG_FILE", "")
ttl = int(os.environ.get("TTL", "24"))

try:
    with open(config_file) as f:
        content = f.read()
except:
    print('[]')
    exit(0)

lines = content.split('\n')
result = {'cached_at': '', 'items': []}
in_rec = False
current_item = None

for line in lines:
    if line.startswith('recommendations:'):
        in_rec = True
        continue
    if not in_rec:
        continue
    if not (line.startswith('  ') or line.startswith('    ')) and line.strip():
        break
    
    stripped = line.strip()
    if stripped.startswith('cached_at:'):
        result['cached_at'] = stripped.split(':', 1)[1].strip()
    elif stripped.startswith('items:'):
        continue
    elif stripped.startswith('- skillId:'):
        current_item = {'skillId': stripped.split(':', 1)[1].strip()}
        result['items'].append(current_item)
    elif current_item and ':' in stripped:
        key, value = stripped.split(':', 1)
        key = key.strip()
        value = value.strip()
        if key == 'score':
            value = float(value) if value else 0
        current_item[key] = value

cached_at = result.get('cached_at', '')
if cached_at:
    try:
        cached_dt = datetime.fromisoformat(cached_at.replace('Z', '+00:00'))
        now = datetime.now(timezone.utc)
        hours_elapsed = (now - cached_dt).total_seconds() / 3600
        if hours_elapsed > ttl:
            print('[]')
            exit(0)
    except:
        pass

print(json.dumps(result['items'], ensure_ascii=False))
PYEOF
}

_device_fp() {
  local seed
  seed="$(hostname 2>/dev/null || echo unknown)|$(uname -s)|$(uname -m)|${HOME}"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$seed" | shasum -a 256 | cut -c1-16
  else
    printf '%s' "$seed" | openssl dgst -sha256 | awk '{print $NF}' | cut -c1-16
  fi
}

_http() {
  # Usage: _http <METHOD> <PATH> [JSON_BODY]
  # Outputs: response JSON to stdout; on failure, outputs error JSON.
  local method="$1" path="$2" body="${3:-}"
  local url="${API_BASE}${path}"
  local tmp http_code

  # 组装鉴权头（若 API_KEY/API_SECRET 未设置则不添加）
  local auth_args=()
  if [[ -n "${MAPICKII_API_KEY}" ]]; then
    auth_args+=(-H "api-key: ${MAPICKII_API_KEY}")
  fi
  if [[ -n "${MAPICKII_API_SECRET}" ]]; then
    auth_args+=(-H "api-secret: ${MAPICKII_API_SECRET}")
  fi

  tmp="$(mktemp)"
  if [[ -n "$body" ]]; then
    http_code="$(curl -sS -o "$tmp" -w '%{http_code}' \
      --max-time 15 \
      -X "$method" \
      -H 'Content-Type: application/json' \
      ${auth_args[@]+"${auth_args[@]}"} \
      -d "$body" \
      "$url" 2>/dev/null)" || http_code="000"
  else
    http_code="$(curl -sS -o "$tmp" -w '%{http_code}' \
      --max-time 15 \
      -X "$method" \
      ${auth_args[@]+"${auth_args[@]}"} \
      "$url" 2>/dev/null)" || http_code="000"
  fi

  if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    # Pass through response body (must be single-line JSON)
    tr -d '\n' < "$tmp"
    echo
  else
    echo "{\"error\":\"service_unreachable\",\"code\":\"E_API_DOWN\",\"http\":\"${http_code}\",\"message\":\"无法连接到 Mapickii 后端\"}"
  fi
  rm -f "$tmp"
}

_inject_recommendations() {
  local json="$1"
  local use_local="${2:-true}"
  local rec_json
  
  json_clean="$(echo "$json" | sed 's/\\n/ /g')"
  
  rec_json="$(_load_recommendations)"
  
  if [[ -z "$rec_json" ]] || [[ "$rec_json" == "[]" ]]; then
    echo "$json_clean"
    return
  fi
  
  python3 -c "
import json
try:
    data = json.loads('''${json_clean}''')
except:
    data = {}
recs = json.loads('''${rec_json}''')
if recs:
    data['recommendations'] = recs[:3]
print(json.dumps(data, ensure_ascii=False))
"
}

_extract_and_save_recommendations() {
  local json="$1"
  
  local rec_json=""
  
  json_clean="$(echo "$json" | sed 's/\\n/ /g')"
  
  if echo "$json_clean" | grep -q '"top2Recommendations"' 2>/dev/null; then
    rec_json="$(echo "$json_clean" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    recs = d.get('top2Recommendations', d.get('data', {}).get('top2Recommendations', []))
    items = []
    for r in recs[:5]:
        skill = r.get('skill', {})
        items.append({
            'skillId': skill.get('skillId', r.get('skillId', '?')),
            'skillName': skill.get('skillName', r.get('skillName', '?')),
            'reason': r.get('reason', ''),
            'score': r.get('score', 0)
        })
    print(json.dumps(items, ensure_ascii=False))
except:
    print('[]')
" 2>/dev/null)"
  elif echo "$json_clean" | grep -q '"recommendations"' 2>/dev/null; then
    rec_json="$(echo "$json_clean" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    recs = d.get('recommendations', [])
    print(json.dumps(recs[:5], ensure_ascii=False))
except:
    print('[]')
" 2>/dev/null)"
  fi
  
  if [[ -n "$rec_json" ]] && [[ "$rec_json" != "[]" ]] && [[ "$rec_json" != "null" ]]; then
    _save_recommendations "$rec_json"
  fi
}

_welcome_json() {
  local device_fp="$(_config_get device_fp)"
  local scan_json skills_json skills_count scanned_at
  
  scan_json="$(_scan_to_json)"
  if [[ -n "$scan_json" ]] && command -v jq >/dev/null 2>&1; then
    skills_json="$(echo "$scan_json" | jq -c '.skills // []' 2>/dev/null || echo '[]')"
    skills_count="$(echo "$scan_json" | jq '.skills // [] | length' 2>/dev/null || echo 0)"
    scanned_at="$(echo "$scan_json" | jq -r '.scanned_at // ""' 2>/dev/null || echo "")"
  else
    skills_json="[]"
    skills_count=0
    scanned_at=""
  fi
  
  DEVICE_FP="${device_fp}" \
  SKILLS_JSON="${skills_json}" \
  SKILLS_COUNT="${skills_count}" \
  SCANNED_AT="${scanned_at}" \
  python3 <<'PYEOF'
import os, json

device_fp    = os.environ.get("DEVICE_FP", "")
skills_json  = os.environ.get("SKILLS_JSON", "[]")
skills_count = int(os.environ.get("SKILLS_COUNT", "0") or "0")

try:
    skills = json.loads(skills_json)
except Exception:
    skills = []

HR_LONG  = "━" * 40
HR_SHORT = "━" * 12

parts = []

# Logo
parts.append("███╗   ███╗ █████╗ ██████╗ ██╗ ██████╗██╗  ██╗")
parts.append("████╗ ████║██╔══██╗██╔══██╗██║██╔════╝██║ ██╔╝")
parts.append("██╔████╔██║███████║██████╔╝██║██║     █████╔╝")
parts.append("██║╚██╔╝██║██╔══██║██╔═══╝ ██║██║     ██╔═██╗")
parts.append("██║ ╚═╝ ██║██║  ██║██║     ██║╚██████╗██║  ██╗")
parts.append("╚═╝     ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝╚═╝  ╚═╝")
parts.append("")

# 标题栏
parts.append("📊 Mapickii · Mapick 智能管家")
parts.append(HR_LONG)
parts.append("状态查询 · 僵尸清理 · 工作流 · 日报周报")
parts.append("")

# 核心能力
parts.append("核心能力")
parts.append(HR_SHORT)
parts.append("📊 状态总览    看看你的 Skill 库健康度")
parts.append("🧹 僵尸清理    一键清理长期不用的 Skill")
parts.append("📈 工作流      识别你的高频 Skill 组合")
parts.append("📬 日报周报    掌握使用节奏")
parts.append("")

# Skill 库
parts.append("🖥 你的 Skill 库")
parts.append(HR_SHORT)
if skills_count == 0:
    parts.append("已安装   0 个")
    parts.append("空白画布，从这里开始 🎨")
else:
    names = [s.get("name", s.get("id", "?")) for s in skills[:5]]
    shown = "、".join(names)
    if len(skills) > 5:
        shown += f" … +{len(skills)-5}"
    parts.append(f"已安装   {skills_count} 个")
    parts.append(f"列表     {shown}")
parts.append("")

# 操作栏
parts.append("✨ 选一个开始")
parts.append(HR_LONG)
parts.append("")
parts.append("1. 🚀 注册账号")
parts.append("   跨设备同步 · 数据漫游 · 获取推荐码")
parts.append("")
parts.append("2. 🔗 绑定已有")
parts.append("   已有 Mapick ID 的用户")
parts.append("")
parts.append("3. ⚡ 立即使用")
parts.append("   本地身份 · 零配置开箱")
parts.append("")

# 隐私声明
parts.append(HR_LONG)
parts.append("🔒 对话内容永不离开本地")
parts.append("   只上传匿名行为数据 (skill_id + 时间戳)")

render = "\n".join(parts)
render_escaped = render.replace("\n", "\\n")

data = {
    "status": "first_install",
    "is_new": True,
    "welcome": {
        "render": render_escaped
    },
    "data": {
        "deviceFingerprint": device_fp,
        "skillsCount": skills_count,
        "scannedAt": os.environ.get("SCANNED_AT", "")
    },
    "actions": [
        {"key": "1", "icon": "🚀", "label": "注册账号", "hint": "跨设备同步 · 数据漫游", "command": "register"},
        {"key": "2", "icon": "🔗", "label": "绑定已有", "hint": "已有 Mapick ID 的用户", "command": "login"},
        {"key": "3", "icon": "⚡", "label": "立即使用", "hint": "本地身份 · 零配置开箱", "command": "skip-onboard"}
    ],
    "privacy": "对话内容永不离开本地，只上传匿名行为数据 (skill_id + 时间戳)"
}
print(json.dumps(data, ensure_ascii=False))
PYEOF
}

# ── 扫描辅助 ──────────────────────────────────────────
_scan_system() {
  # 输出系统信息 JSON（单行，不换行）
  local os arch hostname home node_ver py_ver bash_ver cc cursor windsurf
  os="$(uname -s 2>/dev/null || echo unknown)"
  arch="$(uname -m 2>/dev/null || echo unknown)"
  hostname="$(hostname 2>/dev/null || echo unknown)"
  home="${HOME}"
  node_ver="$(command -v node >/dev/null 2>&1 && node -v 2>/dev/null || echo null)"
  py_ver="$(command -v python3 >/dev/null 2>&1 && python3 --version 2>&1 | awk '{print $2}' || echo null)"
  bash_ver="${BASH_VERSION:-null}"
  cc="$([[ -d "${HOME}/.claude" ]] && echo true || echo false)"
  cursor="$([[ -d "${HOME}/.cursor" ]] && echo true || echo false)"
  windsurf="$([[ -d "${HOME}/.codeium/windsurf" ]] && echo true || echo false)"

  # 包装为 JSON（null 字面量不加引号，其它值加引号）
  local node_json py_json bash_json
  [[ "$node_ver" == "null" ]] && node_json="null" || node_json="\"${node_ver}\""
  [[ "$py_ver" == "null" ]] && py_json="null" || py_json="\"${py_ver}\""
  [[ "$bash_ver" == "null" ]] && bash_json="null" || bash_json="\"${bash_ver}\""

  printf '{"os":"%s","arch":"%s","hostname":"%s","home":"%s","node_version":%s,"python_version":%s,"bash_version":%s,"editors":{"claude_code":%s,"cursor":%s,"windsurf":%s}}' \
    "$os" "$arch" "$hostname" "$home" "$node_json" "$py_json" "$bash_json" "$cc" "$cursor" "$windsurf"
}

_scan_skills() {
  # 扫描 ~/.claude/skills/ 和 $(pwd)/.claude/skills/ 下的 skill 目录
  local dirs=( "${HOME}/.claude/skills" "$(pwd)/.claude/skills" )
  local items=()

  for root in "${dirs[@]}"; do
    [[ -d "$root" ]] || continue
    local d
    for d in "$root"/*/; do
      [[ -d "$d" ]] || continue
      local id name path installed_at enabled last_modified skill_md
      id="$(basename "$d")"
      path="${d%/}"
      skill_md="${path}/SKILL.md"
      if [[ -f "$skill_md" ]]; then
        enabled="true"
        name="$(awk '/^name:/ { sub(/^name:[[:space:]]*/,""); print; exit }' "$skill_md" 2>/dev/null)"
        [[ -z "$name" ]] && name="$id"
      else
        enabled="false"
        name="$id"
      fi
      # macOS stat 与 Linux stat 兼容
      if stat -f '%B' "$d" >/dev/null 2>&1; then
        installed_at="$(date -u -r "$(stat -f '%B' "$d")" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
        last_modified="$(date -u -r "$(stat -f '%m' "$d")" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
      else
        installed_at="$(date -u -d "@$(stat -c '%W' "$d" 2>/dev/null || stat -c '%Y' "$d")" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
        last_modified="$(date -u -d "@$(stat -c '%Y' "$d")" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
      fi
      # 转义 name 中的引号
      local name_esc="${name//\"/\\\"}"
      items+=("{\"id\":\"${id}\",\"name\":\"${name_esc}\",\"path\":\"${path}\",\"installed_at\":\"${installed_at}\",\"enabled\":${enabled},\"last_modified\":\"${last_modified}\"}")
    done
  done

  # 拼成 JSON 数组
  local out="["
  local first=1
  local item
  for item in "${items[@]}"; do
    if [[ $first -eq 1 ]]; then
      out+="${item}"
      first=0
    else
      out+=",${item}"
    fi
  done
  out+="]"
  echo "$out"
}

_do_scan() {
  _ensure_config
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  # 删除旧的 scan 块
  if grep -qE "^scan:" "${CONFIG_FILE}" 2>/dev/null; then
    python3 <<PYEOF_DEL
import os

config_file = os.environ.get("CONFIG_FILE", "${CONFIG_FILE}")
try:
    with open(config_file) as f:
        lines = f.readlines()
except:
    exit(0)

result = []
in_scan = False
for line in lines:
    if line.startswith("scan:"):
        in_scan = True
    elif in_scan:
        if not (line.startswith("  ") or line.startswith("    ") or line.startswith("      ") or line.strip() == ""):
            in_scan = False
            result.append(line)
    else:
        result.append(line)

with open(config_file, "w") as f:
    f.writelines(result)
PYEOF_DEL
  fi
  
  # 添加新的 scan 块，传入 SKILLS_BASE_DIR
  SCAN_TS="$ts" SKILLS_BASE_DIR="${SKILLS_BASE_DIR}" python3 <<PYEOF >> "${CONFIG_FILE}"
import os
import subprocess
import json
from datetime import datetime, timezone

ts = os.environ.get("SCAN_TS", "")
skills_base = os.environ.get("SKILLS_BASE_DIR", os.path.expanduser("~/.claude/skills"))

# 扫描 skills（去重）
skills = []
seen_ids = set()
skill_dirs = [
    skills_base,
    os.path.join(os.getcwd(), ".claude/skills"),
    os.path.join(os.getcwd(), ".openclaw/skills")
]

for root in skill_dirs:
    if not os.path.isdir(root):
        continue
    # 避免重复扫描同一目录
    root_norm = os.path.normpath(root)
    if root_norm in [os.path.normpath(d) for d in skill_dirs[:skill_dirs.index(root)]]:
        continue
    
    for entry in os.listdir(root):
        if entry in seen_ids:
            continue
        path = os.path.join(root, entry)
        if not os.path.isdir(path):
            continue
        seen_ids.add(entry)
        path = os.path.join(root, entry)
        if not os.path.isdir(path):
            continue
        
        skill_md = os.path.join(path, "SKILL.md")
        if os.path.isfile(skill_md):
            enabled = "true"
            name = entry
            try:
                with open(skill_md) as f:
                    for line in f:
                        if line.startswith("name:"):
                            name = line.split(":", 1)[1].strip()
                            break
            except:
                pass
        else:
            enabled = "false"
            name = entry
        
        # 获取时间戳
        import stat
        st = os.stat(path)
        try:
            installed_ts = st.st_birthtime if hasattr(st, 'st_birthtime') else st.st_ctime
            modified_ts = st.st_mtime
            from datetime import datetime, timezone
            installed_at = datetime.fromtimestamp(installed_ts, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            last_modified = datetime.fromtimestamp(modified_ts, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        except:
            installed_at = ""
            last_modified = ""
        
        skills.append({
            "id": entry,
            "name": name,
            "path": path,
            "installed_at": installed_at,
            "enabled": enabled == "true",
            "last_modified": last_modified
        })

# 扫描 system
system = {
    "os": os.uname().sysname if hasattr(os, 'uname') else "unknown",
    "arch": os.uname().machine if hasattr(os, 'uname') else "unknown",
    "hostname": os.uname().nodename if hasattr(os, 'uname') else "unknown",
    "home": os.environ.get("HOME", ""),
    "node_version": subprocess.run(["node", "-v"], capture_output=True, text=True).stdout.strip() or None,
    "python_version": subprocess.run(["python3", "--version"], capture_output=True, text=True).stdout.split()[1] if subprocess.run(["python3", "--version"], capture_output=True).returncode == 0 else None,
    "bash_version": os.environ.get("BASH_VERSION"),
    "editors": {
        "claude_code": os.path.isdir(os.path.expanduser("~/.claude")),
        "cursor": os.path.isdir(os.path.expanduser("~/.cursor")),
        "windsurf": os.path.isdir(os.path.expanduser("~/.codeium/windsurf")),
    }
}

# 输出 YAML 格式
def bool_str(val):
    return "true" if val else "false"

print("scan:")
print(f"  scanned_at: {ts}")
print("  skills:")
for s in skills:
    print(f"    - id: {s['id']}")
    print(f"      name: {s['name']}")
    print(f"      path: {s['path']}")
    print(f"      installed_at: {s['installed_at']}")
    print(f"      enabled: {bool_str(s['enabled'])}")
    print(f"      last_modified: {s['last_modified']}")
print("  system:")
print(f"    os: {system['os']}")
print(f"    arch: {system['arch']}")
print(f"    hostname: {system['hostname']}")
print(f"    home: {system['home']}")
if system['node_version']:
    print(f"    node_version: {system['node_version']}")
if system['python_version']:
    print(f"    python_version: {system['python_version']}")
if system['bash_version']:
    print(f"    bash_version: {system['bash_version']}")
print("    editors:")
print(f"      claude_code: {bool_str(system['editors']['claude_code'])}")
print(f"      cursor: {bool_str(system['editors']['cursor'])}")
print(f"      windsurf: {bool_str(system['editors']['windsurf'])}")
PYEOF
}

# ── scan 数据读取（从 CONFIG.md 的 YAML 格式解析）────────────────
_scan_to_json() {
  CONFIG_FILE="$CONFIG_FILE" python3 <<PYEOF
import re
import json
import os

config_file = os.environ.get("CONFIG_FILE", "")
if not config_file:
    print('{}')
    exit(0)

try:
    with open(config_file) as f:
        content = f.read()
except:
    print('{}')
    exit(0)

# 解析 YAML 格式的 scan 块
lines = content.split('\n')
result = {'scanned_at': '', 'skills': [], 'system': {}}
in_scan = False
current_section = None
current_skill = None

for i, line in enumerate(lines):
    if line.startswith('scan:'):
        in_scan = True
        continue
    
    if not in_scan:
        continue
    
    # 非缩进行表示 scan 块结束
    if not line.startswith('  ') and line.strip():
        break
    
    # 解析 scanned_at
    if line.strip().startswith('scanned_at:'):
        result['scanned_at'] = line.split(':', 1)[1].strip()
        continue
    
    # 解析 skills
    if line.strip().startswith('skills:'):
        current_section = 'skills'
        continue
    
    # 解析 system
    if line.strip().startswith('system:'):
        current_section = 'system'
        continue
    
    # 解析 skill 数组项
    if current_section == 'skills' and line.strip().startswith('- id:'):
        current_skill = {'id': line.split(':', 1)[1].strip()}
        result['skills'].append(current_skill)
        continue
    
    # 解析 skill 属性
    if current_section == 'skills' and current_skill:
        stripped = line.strip()
        if ':' in stripped:
            key, value = stripped.split(':', 1)
            key = key.strip()
            value = value.strip()
            # 处理布尔值
            if value == 'true':
                value = True
            elif value == 'false':
                value = False
            current_skill[key] = value
    
    # 解析 system 属性
    if current_section == 'system':
        stripped = line.strip()
        if stripped.startswith('editors:'):
            current_section = 'editors'
            continue
        if ':' in stripped and not stripped.startswith('editors'):
            key, value = stripped.split(':', 1)
            result['system'][key.strip()] = value.strip()
    
    # 解析 editors 属性
    if current_section == 'editors':
        stripped = line.strip()
        if ':' in stripped:
            key, value = stripped.split(':', 1)
            val = value.strip()
            result['system']['editors'] = result['system'].get('editors', {})
            result['system']['editors'][key.strip()] = val == 'true'

print(json.dumps(result))
PYEOF
}

_scan_needed() {
  local ttl="${MAPICKII_SCAN_TTL_HOURS:-24}"
  [[ "$ttl" == "0" ]] && return 1

  local scan_json last
  scan_json="$(_scan_to_json)"
  if [[ -n "$scan_json" ]]; then
    last="$(echo "$scan_json" | jq -r '.scanned_at // empty' 2>/dev/null)"
  fi
  [[ -z "$last" ]] && return 0

  local last_epoch now_epoch diff
  if date -u -d "$last" +%s >/dev/null 2>&1; then
    last_epoch="$(date -u -d "$last" +%s)"
  else
    last_epoch="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$last" +%s 2>/dev/null)"
  fi
  [[ -z "$last_epoch" ]] && return 0
  now_epoch="$(date -u +%s)"
  diff=$(( (now_epoch - last_epoch) / 3600 ))
  [[ $diff -ge $ttl ]]
}

# ── 卸载辅助 ──────────────────────────────────────────
MAPICKII_TRASH_DIR="${CONFIG_DIR}/trash"
MAPICKII_PROTECTED_SKILLS=(mapickii mapick tasa)

_is_protected() {
  local id="$1"
  local p
  for p in "${MAPICKII_PROTECTED_SKILLS[@]}"; do
    [[ "$id" == "$p" ]] && return 0
  done
  return 1
}

_scan_find_paths() {
  # Usage: _scan_find_paths <skillId>
  # Outputs one "scope:path" per line (scopes: user|project)
  local id="$1"
  local user_path="${HOME}/.claude/skills/${id}"
  local project_path="$(pwd)/.claude/skills/${id}"
  [[ -d "$user_path" ]] && echo "user:${user_path}"
  [[ -d "$project_path" ]] && echo "project:${project_path}"
  return 0
}

_backup_skill() {
  # Usage: _backup_skill <path> <skillId>
  # Outputs backup path on success; exits non-zero on failure.
  local src="$1" id="$2"
  local ts="$(date -u +%Y%m%d%H%M%S)"
  local dst="${MAPICKII_TRASH_DIR}/${id}-${ts}"
  mkdir -p "${MAPICKII_TRASH_DIR}" || return 1
  cp -R "$src" "$dst" || return 1
  echo "$dst"
}

# ── 次使用自动 bootstrap ────────────────────────────
# 首次判定条件（任一满足即触发）：
#   - config.json 不存在
#   - device_fp 为空
#   - mapick_id 为空
#   - mode 为空（未完成 onboarding）
# 首次时：建立 device_fp + 做一次扫描；不自动设 mode（留给 onboarding 决定）
COMMAND="${1:-}"

_need_bootstrap=0
if [[ ! -f "${CONFIG_FILE}" ]]; then
  _need_bootstrap=1
else
  [[ -z "$(_config_get device_fp)" ]] && _need_bootstrap=1
  [[ -z "$(_config_get mode)" ]] && _need_bootstrap=1
fi

if [[ ${_need_bootstrap} -eq 1 ]]; then
  _ensure_config
  [[ -z "$(_config_get device_fp)" ]] && _config_set device_fp "$(_device_fp)"
  [[ -z "$(_config_get created_at)" ]] && _config_set created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  _config_del last_init_at
  _do_scan
fi

# ── ISO → epoch 时间戳转换 ────────────────────────────
_iso_to_epoch() {
  local ts="$1"
  if date -u -d "$ts" +%s >/dev/null 2>&1; then
    date -u -d "$ts" +%s
  else
    date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s 2>/dev/null || echo 0
  fi
}

# ── 命令分发 ──────────────────────────────────────────
USER_ID="$(_config_get device_fp)"
[[ -z "${USER_ID}" ]] && USER_ID="$(_device_fp)"

# ── 套装推荐函数 ──────────────────────────────────────────
_bundle_list() {
  resp="$(_http GET "/bundle")"
  if echo "$resp" | grep -q '"error"'; then
    echo "$resp"
    return
  fi
  
  echo "$resp" | sed 's/\\n/ /g' | python3 -c "
import sys, json
try:
    bundles = json.load(sys.stdin)
except:
    bundles = []

print('🗂️ 套装列表')
print('━━━━━━━━━━━━━━━')
print()

for b in bundles[:10]:
    bundle_id = b.get('bundleId', '?')
    name = b.get('name', '?')
    desc = b.get('description', '')[:50]
    skill_count = len(b.get('skillIds', []))
    print(f'{name}')
    print(f'  ID: {bundle_id}')
    print(f'  包含 {skill_count} 个 Skill')
    print(f'  {desc}')
    print()

print('💡 回复「套装 <ID>」看详情')
print('💡 回复「套装推荐」看适合你的套装')
"
}

_bundle_detail() {
  local bundle_id="$1"
  resp="$(_http GET "/bundle/${bundle_id}")"
  if echo "$resp" | grep -q '"error"'; then
    echo "$resp"
    return
  fi
  
  echo "$resp" | sed 's/\\n/ /g' | python3 -c "
import sys, json
try:
    b = json.load(sys.stdin)
except:
    b = {}

bundle_id = b.get('bundleId', '?')
name = b.get('name', '?')
desc = b.get('description', '')
target = b.get('targetAudience', '')
skill_ids = b.get('skillIds', [])

print(f'🗂️ {name}')
print('━━━━━━━━━━━━━━━')
print()
print(f'套装 ID: {bundle_id}')
print(f'描述: {desc}')
print(f'目标用户: {target}')
print()
print('包含 Skill:')
print('━━━━━━━━━━━━━━━')
for i, sid in enumerate(skill_ids[:10], 1):
    skill_name = sid.split(':')[-1] if ':' in sid else sid
    print(f'{i}. {skill_name}')
if len(skill_ids) > 10:
    print(f'  ... 还有 {len(skill_ids) - 10} 个')

print()
print('💡 回复「安装套装」一键安装')
"
}

_bundle_recommend() {
  resp="$(_http GET "/bundle")"
  scan_json="$(_scan_to_json)"
  
  installed_skills=""
  if [[ -n "$scan_json" ]] && command -v jq >/dev/null 2>&1; then
    installed_skills="$(echo "$scan_json" | jq -c '[.skills // [] | .[].id]' 2>/dev/null || echo '[]')"
  fi
  
  if echo "$resp" | grep -q '"error"'; then
    echo "$resp"
    return
  fi
  
  BUNDLES="$resp" INSTALLED="$installed_skills" python3 -c "
import sys, json, os
try:
    bundles = json.loads(os.environ.get('BUNDLES', '[]'))
except:
    bundles = []
try:
    installed = json.loads(os.environ.get('INSTALLED', '[]'))
except:
    installed = []

matches = []
for b in bundles:
    skill_ids = b.get('skillIds', [])
    trigger_ids = b.get('triggerSkillIds', [])
    
    installed_in_bundle = [s for s in skill_ids if s in installed or s.split(':')[-1] in installed]
    missing_in_bundle = [s for s in skill_ids if s not in installed and s.split(':')[-1] not in installed]
    
    # 触发条件：装了触发 Skill 或装了 25%-75%
    triggered = False
    if any(s in installed or s.split(':')[-1] in installed for s in trigger_ids):
        triggered = True
    ratio = len(installed_in_bundle) / len(skill_ids) if skill_ids else 0
    if 0.25 <= ratio < 1.0:
        triggered = True
    
    if triggered and missing_in_bundle:
        matches.append({
            'bundle': b,
            'installed': installed_in_bundle,
            'missing': missing_in_bundle,
            'ratio': ratio
        })

if not matches:
    print('💡 暂无套装推荐')
    print()
    print('回复「套装列表」查看所有套装')
else:
    matches.sort(key=lambda x: x['ratio'], reverse=True)
    m = matches[0]
    b = m['bundle']
    
    print(f'🗂️ {b.get(\"name\", \"?\")}')
    print()
    print(f'你已经装了 {len(m[\"installed\"])}/{len(b.get(\"skillIds\", []))} 个')
    print('━━━━━━━━━━━━━━━')
    
    for sid in m['installed'][:5]:
        name = sid.split(':')[-1] if ':' in sid else sid
        print(f'✅ {name}')
    
    print()
    print('推荐补全:')
    print('━━━━━━━━━━━━━━━')
    for i, sid in enumerate(m['missing'][:5], 1):
        name = sid.split(':')[-1] if ':' in sid else sid
        print(f'{i}. ⬜ {name}')
    
    print()
    print(f'💡 回复「安装套装 {b.get(\"bundleId\", \"?\")}」补全')
" 2>/dev/null || echo '{"error":"parse_error"}'
}

_bundle_install() {
  local bundle_id="$1"
  local skill_ids="${2:-}"
  
  resp="$(_http GET "/bundle/${bundle_id}")"
  if echo "$resp" | grep -q '"error"'; then
    echo "$resp"
    return
  fi
  
  bundle_skills="$(echo "$resp" | jq -c '.skillIds // []' 2>/dev/null || echo '[]')"
  
  body="{\"userId\":\"${USER_ID}\",\"bundleId\":\"${bundle_id}\",\"skillIds\":${bundle_skills},\"installedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
  track_resp="$(_http POST /event/track "$body")"
  
  echo "{\"intent\":\"bundle:install\",\"bundleId\":\"${bundle_id}\",\"skillIds\":${bundle_skills},\"track\":${track_resp}}"
}

shift || true

# 自动扫描刷新（β+γ）：对需要联网或本地数据展示的命令做 TTL 检查
case "${COMMAND}" in
  status|clean|workflow|daily|weekly|chat)
    if _scan_needed; then _do_scan; fi
    ;;
esac

case "${COMMAND}" in
  # 身份管理
  register)
    resp="$(_http POST /user/identity "{\"deviceFingerprint\":\"${USER_ID}\"}")"
    # 保存返回的 mapick_id, referral_code, referredBy 到 config
    if command -v jq >/dev/null 2>&1; then
      mp_id="$(echo "$resp" | jq -r '.mapickId // empty' 2>/dev/null)"
      ref_code="$(echo "$resp" | jq -r '.referralCode // empty' 2>/dev/null)"
      referred_by="$(echo "$resp" | jq -r '.referredBy // empty' 2>/dev/null)"
      if [[ -n "$mp_id" ]]; then
        _config_set mapick_id "$mp_id"
        _config_set mode registered
      fi
      if [[ -n "$ref_code" ]]; then
        _config_set referral_code "$ref_code"
      fi
      if [[ -n "$referred_by" ]]; then
        _config_set referred_by "$referred_by"
      fi
    fi
    echo "$resp"
    ;;

identity|id)
    resp="$(_http GET "/user/identity/${USER_ID}")"
    echo "$resp"
    ;;

  identity:bind|login)
    mp="${1:-}"
    if [[ -z "$mp" ]]; then
      echo '{"error":"missing_argument","message":"login 需要 Mapick ID 参数"}'
      exit 0
    fi
    resp="$(_http POST /user/identity "{\"deviceFingerprint\":\"${USER_ID}\",\"mapickId\":\"${mp}\"}")"
    if echo "$resp" | grep -q '"statusCode"'; then
      echo "$resp"
      exit 0
    fi
    # 保存到 config
    mp_id="$(echo "$resp" | jq -r '.mapickId // empty')"
    ref_code="$(echo "$resp" | jq -r '.referralCode // empty')"
    referred="$(echo "$resp" | jq -r '.referredBy // empty')"
    if [[ -n "$mp_id" ]]; then
      _config_set mapick_id "$mp_id"
      _config_set mode bound
    fi
    if [[ -n "$ref_code" ]]; then
      _config_set referral_code "$ref_code"
    fi
    if [[ -n "$referred" ]]; then
      _config_set referred_by "$referred"
    fi
    echo "$resp"
    ;;

  identity:bind)
    mp_id="${1:-}"
    if [[ -z "$mp_id" ]]; then
      echo '{"error":"missing_argument","message":"identity:bind 需要 Mapick ID 参数"}'
      exit 0
    fi
    resp="$(_http POST /user/identity "{\"deviceFingerprint\":\"${USER_ID}\",\"mapickId\":\"${mp_id}\"}")"
    # 若成功（非 error），保存 mapick_id 到 config
    if ! echo "$resp" | grep -q '"error"'; then
      _config_set mapick_id "$mp_id"
      _config_set mode bound
    fi
    echo "$resp"
    ;;

  skip-onboard)
    _config_set mode local
    echo "{\"intent\":\"skip-onboard\",\"data\":{\"deviceFingerprint\":\"${USER_ID}\",\"mode\":\"local\"}}"
    ;;

  init)
    now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    current_mode="$(_config_get mode)"
    last_init_at="$(_config_get last_init_at)"

    if [[ -z "${current_mode}" ]]; then
      _welcome_json
      exit 0
    fi

    if [[ -z "${last_init_at}" ]]; then
      _config_set last_init_at "${now_utc}"
      scan_json="$(_scan_to_json)"
      skills_count="$(echo "$scan_json" | jq '.skills // [] | length' 2>/dev/null || echo 0)"
      scanned_at="$(echo "$scan_json" | jq -r '.scanned_at // ""' 2>/dev/null || echo "")"
      echo "{\"status\":\"initialized\",\"is_new\":true,\"data\":{\"mode\":\"${current_mode}\",\"mapickId\":$([[ -n "$(_config_get mapick_id)" ]] && echo "\"$(_config_get mapick_id)\"" || echo null),\"deviceFingerprint\":\"$(_config_get device_fp)\",\"skillsCount\":${skills_count},\"scannedAt\":\"${scanned_at}\"}}"
      exit 0
    fi

    last_epoch="$(_iso_to_epoch "$last_init_at")"
    now_epoch="$(date -u +%s)"
    minutes_elapsed=$(( (now_epoch - last_epoch) / 60 ))

    if [[ "${minutes_elapsed}" -lt "${MAPICKII_INIT_INTERVAL_MINUTES}" ]]; then
      echo "{\"status\":\"skip\",\"next_in_minutes\":$(( MAPICKII_INIT_INTERVAL_MINUTES - minutes_elapsed ))}"
      exit 0
    fi

    scan_json="$(_scan_to_json)"
    old_ids="$(echo "$scan_json" | jq -c '[.skills // [] | .[].id] | sort' 2>/dev/null || echo '[]')"

    _do_scan
    _config_set last_init_at "${now_utc}"

    scan_json="$(_scan_to_json)"
    new_ids="$(echo "$scan_json" | jq -c '[.skills // [] | .[].id] | sort' 2>/dev/null || echo '[]')"
    added="$(jq -cn --argjson o "$old_ids" --argjson n "$new_ids" '$n - $o')"
    removed="$(jq -cn --argjson o "$old_ids" --argjson n "$new_ids" '$o - $n')"
    changed_count="$(jq -n --argjson a "$added" --argjson r "$removed" '($a | length) + ($r | length)')"
    if [[ "$changed_count" -gt 0 ]]; then
      jq -cn --argjson a "$added" --argjson r "$removed" \
            '{status:"rescanned", changed:true, changes:{skills_added:$a, skills_removed:$r}}'
    else
      echo '{"status":"rescanned","changed":false}'
    fi
    ;;

  scan)
    start_ms="$(date +%s%3N 2>/dev/null || echo 0)"
    _do_scan
    end_ms="$(date +%s%3N 2>/dev/null || echo 0)"
    if [[ "$start_ms" =~ [^0-9] || "$end_ms" =~ [^0-9] ]]; then
      dur_ms=0
    else
      dur_ms=$(( end_ms - start_ms ))
    fi

    scan_json="$(_scan_to_json)"
    resp="$(jq -n -c --argjson dur "$dur_ms" --argjson data "$scan_json" '{intent: "scan", durationMs: $dur, data: $data}')"
    _inject_recommendations "$resp" "true"
    ;;

  uninstall)
    skill_id="${1:-}"
    if [[ -z "$skill_id" ]]; then
      echo '{"error":"missing_argument","message":"uninstall 需要 skillId 参数"}'
      exit 0
    fi
    shift || true

    # 解析 --scope 和 --confirm（参数缺失时友好降级）
    scope=""
    confirm=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --scope)
          scope="${2:-}"
          shift || true
          [[ $# -gt 0 ]] && shift || true
          ;;
        --confirm) confirm=1; shift || true ;;
        *) shift || true ;;
      esac
    done

    # 受保护检查（无论 confirm 与否）
    if _is_protected "$skill_id"; then
      echo "{\"error\":\"protected_skill\",\"skillId\":\"${skill_id}\",\"message\":\"${skill_id} 是受保护的 skill，禁止删除\"}"
      exit 0
    fi

    # 查找本地路径
    paths_raw="$(_scan_find_paths "$skill_id")"
    if [[ -z "$paths_raw" ]]; then
      # 本地没找到，只走 clean:track
      resp="$(_http POST /event/track "{\"action\":\"skill_uninstall\",\"skillId\":\"${skill_id}\",\"userId\":\"${USER_ID}\",\"metadata\":{\"reason\":\"manual-uninstall\"}}")"
      echo "{\"intent\":\"uninstall:no-local\",\"skillId\":\"${skill_id}\",\"message\":\"本地未找到该 skill，已记录卸载\",\"track\":${resp}}"
      exit 0
    fi

    # 构造 paths JSON 数组和并按 scope 过滤
    paths_json=""
    selected_paths=()
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      ps="${line%%:*}"
      pp="${line#*:}"
      if [[ -z "$scope" || "$scope" == "both" || "$scope" == "$ps" ]]; then
        selected_paths+=("${ps}:${pp}")
      fi
      [[ -n "$paths_json" ]] && paths_json+=","
      paths_json+="{\"scope\":\"${ps}\",\"path\":\"${pp}\"}"
    done <<< "$paths_raw"

    # scope 省略且找到两处 → ambiguous
    if [[ -z "$scope" ]]; then
      count="$(printf '%s\n' "$paths_raw" | grep -c .)"
      if [[ "$count" -gt 1 ]]; then
        echo "{\"error\":\"ambiguous_scope\",\"skillId\":\"${skill_id}\",\"paths\":[${paths_json}],\"message\":\"在用户级和项目级都找到了，请用 --scope 指定\"}"
        exit 0
      fi
    fi

    # Dry-run：未 --confirm
    if [[ $confirm -eq 0 ]]; then
      echo "{\"intent\":\"uninstall:dry-run\",\"skillId\":\"${skill_id}\",\"protected\":false,\"paths\":[${paths_json}],\"message\":\"尚未确认，回传 --confirm 执行删除\"}"
      exit 0
    fi

    # 执行备份 + 删除
    deleted_json=""
    for entry in "${selected_paths[@]}"; do
      ps="${entry%%:*}"
      pp="${entry#*:}"
      if ! backup_path="$(_backup_skill "$pp" "$skill_id")"; then
        echo "{\"error\":\"backup_failed\",\"path\":\"${pp}\",\"message\":\"备份失败（磁盘空间或权限）\"}"
        exit 0
      fi
      if ! rm -rf "$pp" 2>/dev/null; then
        echo "{\"error\":\"permission_denied\",\"path\":\"${pp}\",\"message\":\"删除失败（权限不足）\"}"
        exit 0
      fi
      [[ -n "$deleted_json" ]] && deleted_json+=","
      deleted_json+="{\"scope\":\"${ps}\",\"path\":\"${pp}\",\"backup\":\"${backup_path}\"}"
    done

    # 记录卸载事件
    track_resp="$(_http POST /event/track "{\"action\":\"skill_uninstall\",\"skillId\":\"${skill_id}\",\"userId\":\"${USER_ID}\",\"metadata\":{\"reason\":\"manual-uninstall\"}}")"
    # 刷新 scan，使 scan.skills 反映删除结果
    _do_scan
    echo "{\"intent\":\"uninstall\",\"skillId\":\"${skill_id}\",\"deleted\":[${deleted_json}],\"track\":${track_resp}}"
    ;;

# 生命周期查询
status)
    if _cache_valid "status" "${CACHE_STATUS_TTL_MINUTES}"; then
      cached="$(_cache_read "status" "${CACHE_STATUS_TTL_MINUTES}")"
      if [[ -n "$cached" ]]; then
        _inject_recommendations "$cached"
        exit 0
      fi
    fi
    resp="$(_http GET "/assistant/status/${USER_ID}")"
    _cache_write "status" "$resp"
    _extract_and_save_recommendations "$resp"
    _inject_recommendations "$resp"
    ;;

clean)
    if _cache_valid "zombies" "${CACHE_ZOMBIES_TTL_MINUTES}"; then
      cached="$(_cache_read "zombies" "${CACHE_ZOMBIES_TTL_MINUTES}")"
      if [[ -n "$cached" ]]; then
        _inject_recommendations "$cached"
        exit 0
      fi
    fi
    resp="$(_http GET "/user/${USER_ID}/zombies")"
    _cache_write "zombies" "$resp"
    _inject_recommendations "$resp"
    ;;

workflow)
    if _cache_valid "workflow" "${CACHE_WORKFLOW_TTL_MINUTES}"; then
      cached="$(_cache_read "workflow" "${CACHE_WORKFLOW_TTL_MINUTES}")"
      if [[ -n "$cached" ]]; then
        _inject_recommendations "$cached"
        exit 0
      fi
    fi
    resp="$(_http GET "/assistant/workflow/${USER_ID}")"
    _cache_write "workflow" "$resp"
    _extract_and_save_recommendations "$resp"
    _inject_recommendations "$resp"
    ;;

daily)
    resp="$(_http GET "/assistant/daily-digest/${USER_ID}")"
    _extract_and_save_recommendations "$resp"
    _inject_recommendations "$resp"
    ;;

weekly)
    resp="$(_http GET "/assistant/weekly/${USER_ID}")"
    _extract_and_save_recommendations "$resp"
    _inject_recommendations "$resp"
    ;;

  clean:track)
    skill_id="${1:-}"
    reason="${2:-}"
    if [[ -z "$skill_id" ]]; then
      echo '{"error":"missing_argument","message":"clean:track 需要 skillId 参数"}'
      exit 0
    fi

    # 构造 track 请求体（后端 /event/track 契约：action + skillId + userId + metadata）
    if [[ -n "$reason" ]]; then
      body="{\"action\":\"skill_uninstall\",\"skillId\":\"${skill_id}\",\"userId\":\"${USER_ID}\",\"metadata\":{\"reason\":\"${reason}\"}}"
    else
      body="{\"action\":\"skill_uninstall\",\"skillId\":\"${skill_id}\",\"userId\":\"${USER_ID}\",\"metadata\":{\"reason\":\"zombie_cleanup\"}}"
    fi
    track_resp="$(_http POST /event/track "$body")"

    # 受保护 skill：只 track 不删
    if _is_protected "$skill_id"; then
      echo "{\"intent\":\"clean:track\",\"skillId\":\"${skill_id}\",\"deleted\":[],\"protected\":true,\"track\":${track_resp}}"
      exit 0
    fi

    # 查本地路径，有就备份+删除（僵尸清理场景：用户已在列表里选中，视为已确认）
    paths_raw="$(_scan_find_paths "$skill_id")"
    if [[ -z "$paths_raw" ]]; then
      echo "{\"intent\":\"clean:track\",\"skillId\":\"${skill_id}\",\"deleted\":[],\"track\":${track_resp}}"
      exit 0
    fi

    deleted_json=""
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      ps="${line%%:*}"
      pp="${line#*:}"
      if backup_path="$(_backup_skill "$pp" "$skill_id")"; then
        if rm -rf "$pp" 2>/dev/null; then
          [[ -n "$deleted_json" ]] && deleted_json+=","
          deleted_json+="{\"scope\":\"${ps}\",\"path\":\"${pp}\",\"backup\":\"${backup_path}\"}"
        fi
      fi
    done <<< "$paths_raw"

    _do_scan
    echo "{\"intent\":\"clean:track\",\"skillId\":\"${skill_id}\",\"deleted\":[${deleted_json}],\"track\":${track_resp}}"
    ;;

  chat)
    msg="${1:-}"
    if [[ -z "$msg" ]]; then
      echo '{"error":"missing_argument","message":"chat 需要 message 参数"}'
      exit 0
    fi
    # JSON-escape 用户消息中的引号和反斜杠
    msg_escaped="${msg//\\/\\\\}"
    msg_escaped="${msg_escaped//\"/\\\"}"
    _http POST /assistant/chat "{\"userId\":\"${USER_ID}\",\"message\":\"${msg_escaped}\"}"
    ;;

# 推荐码管理（统一入口：ref <code>）
  referral|ref)
    code="${1:-}"
    
    if [[ -n "$code" ]]; then
      resp="$(_http POST /user/referral/bind "{\"deviceFingerprint\":\"${USER_ID}\",\"referralCode\":\"${code}\"}")"
      _extract_and_save_recommendations "$resp"
      
      if echo "$resp" | grep -q '"statusCode"'; then
        message="$(echo "$resp" | jq -r '.message // "绑定失败"')"
        echo "{\"error\":\"bind_failed\",\"message\":\"${message}\"}"
        exit 0
      fi
      
      success="$(echo "$resp" | jq -r '.success')"
      if [[ "$success" == "true" ]]; then
        referral_code="$(echo "$resp" | jq -r '.referralCode')"
        referred_by="$(echo "$resp" | jq -r '.referredBy')"
        _config_set referral_code "$referral_code"
        _config_set referred_by "$referred_by"
      fi
    else
      resp="$(_http GET "/user/referral/${USER_ID}")"
      _extract_and_save_recommendations "$resp"
      if echo "$resp" | grep -q '"statusCode"'; then
        echo "$resp"
        exit 0
      fi
    fi
    
    referral_code="$(echo "$resp" | jq -r '.referralCode // ""')"
    referred_by="$(echo "$resp" | jq -r '.referredBy // ""')"
    referral_count="$(echo "$resp" | jq -r '.referralCount // 0')"
    can_bind="$(echo "$resp" | jq -r '.canBind // false')"
    mapick_id="$(echo "$resp" | jq -r '.mapickId // ""')"
    
    if [[ "$can_bind" == "true" ]]; then
      py_can_bind="True"
    else
      py_can_bind="False"
    fi
    
    local rec_json rec_msg
    rec_json="$(_load_recommendations)"
    rec_msg=""
    if [[ -n "$rec_json" ]] && [[ "$rec_json" != "[]" ]]; then
      rec_msg="$(echo "$rec_json" | python3 -c "import sys,json; recs=json.load(sys.stdin)[:3]; msg='💡 推荐安装\\n'; [msg+=f'{i+1}. {r.get(\"skillName\",\"?\")} — {r.get(\"reason\",\"\")}\\n' for i,r in enumerate(recs)]; print(msg)" 2>/dev/null)"
    fi
    
    python3 <<PYEOF
referral_code = "${referral_code}"
referred_by = "${referred_by}"
referral_count = "${referral_count}"
can_bind = ${py_can_bind}
mapick_id = "${mapick_id}"
bind_success = ${success:-False}
rec_msg = """${rec_msg}"""

print("🎁 推荐码")
print("━━━━━━━━━━━━━━━")
print(f"Mapick ID   {mapick_id}")
print(f"推荐码      {referral_code}")
print(f"已推荐      {referral_count} 人")
print()
if bind_success:
    print("✅ 推荐码绑定成功")
    print()
if referred_by:
    print(f"推荐人      {referred_by}")
    print()
    print("🔒 已绑定推荐人，不可重复绑定")
else:
    print("💡 绑定推荐码获得奖励")
    print()
    print("绑定命令：")
    print("  ref <推荐码>")
if rec_msg:
    print()
    print(rec_msg)
PYEOF
;;

  referral:bind|ref:bind)
    code="${1:-}"
    if [[ -z "$code" ]]; then
      echo '{"error":"missing_argument","message":"ref bind 需要推荐码参数"}'
      exit 0
    fi
    resp="$(_http POST /user/referral/bind "{\"deviceFingerprint\":\"${USER_ID}\",\"referralCode\":\"${code}\"}")"
    
    if echo "$resp" | grep -q '"statusCode"'; then
      # 错误响应
      message="$(echo "$resp" | jq -r '.message // "绑定失败"')"
      echo "{\"error\":\"bind_failed\",\"message\":\"${message}\"}"
      exit 0
    fi
    
    # 成功响应
    success="$(echo "$resp" | jq -r '.success')"
    if [[ "$success" == "true" ]]; then
      referral_code="$(echo "$resp" | jq -r '.referralCode')"
      referred_by="$(echo "$resp" | jq -r '.referredBy')"
      referrer_id="$(echo "$resp" | jq -r '.referrer.mapickId')"
      
      # 写入 CONFIG.md
      _config_set referral_code "$referral_code"
      _config_set referred_by "$referred_by"
      
      python3 <<PYEOF
referral_code = "${referral_code}"
referred_by = "${referred_by}"
referrer_id = "${referrer_id}"

print("✅ 推荐码绑定成功")
print()
print("推荐人")
print("━━━━━━━━━━━━━━━")
print(f"Mapick ID   {referrer_id}")
print(f"推荐码      {referred_by}")
print()
print("你的推荐码")
print("━━━━━━━━━━━━━━━")
print(f"推荐码      {referral_code}")
print()
print("🎁 奖励：解锁推荐功能")
print("   邀请好友获得积分")
PYEOF
    else
      echo "$resp"
    fi
;;

push:daily|push:weekly|push:off)
    frequency="${COMMAND#push:}"
    last="$(_config_get last_push_mode)"
    if [[ "$last" == "$frequency" ]]; then
      resp="{\"intent\":\"push:noop\",\"data\":{\"frequency\":\"${frequency}\",\"message\":\"已经是 ${frequency} 模式了\"}}"
      _inject_recommendations "$resp" "true"
      exit 0
    fi
    case "$frequency" in
      off)    push_text="关闭推送" ;;
      weekly) push_text="改成每周推送" ;;
      daily)  push_text="每日推送" ;;
    esac
    resp="$(_http POST /assistant/dialogue "{\"userId\":\"${USER_ID}\",\"text\":\"${push_text}\",\"platform\":\"plain\"}")"
    _extract_and_save_recommendations "$resp"
    if ! echo "$resp" | grep -q '"error"'; then
      _config_set last_push_mode "$frequency"
    fi
    _inject_recommendations "$resp"
    ;;

 "")

resp="$(_http GET "/assistant/status/${USER_ID}")"
    _extract_and_save_recommendations "$resp"
    _inject_recommendations "$resp"
    ;;

  bundle|bundles)
    bundle_id="${1:-}"
    if [[ -z "$bundle_id" ]]; then
      _bundle_list
    else
      _bundle_detail "$bundle_id"
    fi
    ;;

  bundle:recommend|bundle-recommend)
    _bundle_recommend
    ;;

  bundle:install|bundle-install)
    bundle_id="${1:-}"
    skill_ids="${2:-}"
    if [[ -z "$bundle_id" ]]; then
      echo '{"error":"missing_argument","message":"bundle install 需要套装 ID 参数"}'
      exit 0
    fi
    _bundle_install "$bundle_id" "$skill_ids"
    ;;

help|--help|-h)

cat >&2 <<'USAGE'
Mapickii — Mapick 智能管家（M1+M2+M3）

用法: bash shell.sh <command> [args...]

身份管理:
  register              注册新身份
  id                    查看当前身份
  login <MP-ID>         绑定已有 Mapick ID
  skip-onboard          跳过注册，使用本地模式

推荐码:
  ref                   查看推荐信息
  ref <code>             绑定推荐码（只能绑定一次）

套装推荐（M3）:
  bundle                    套装列表
  bundle <id>               套装详情
  bundle:recommend          推荐套装
  bundle:install <id>       安装套装

生命周期（M1）:
  scan                      本地环境扫描
  status                    Skill 状态总览
  clean                     僵尸 Skill 列表
  clean:track <skillId> [reason]  记录卸载事件
  uninstall <skillId> [--scope user|project|both] [--confirm]  卸载并删除本地 skill
  workflow                  工作流分析
  daily                     日报
  weekly                    周报
  chat <message>            自然语言兜底

推送频率:
  push:daily | push:weekly | push:off

环境变量:
  MAPICKII_API_BASE    后端 API 前缀（默认 http://127.0.0.1:3010/api/v1）
USAGE
    echo '{"error":"usage","message":"见 stderr"}'
    ;;

  *)
    echo "{\"error\":\"unknown_command\",\"command\":\"${COMMAND}\"}"
    ;;
esac
