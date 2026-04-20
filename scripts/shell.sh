#!/usr/bin/env bash
# Mapickii skill unified entry point
# Usage: bash shell.sh <command> [args...]

set -euo pipefail

# ── Constants ─────────────────────────────────────────
API_BASE="${MAPICKII_API_BASE:-https://api.mapick.ai/v1}"

# Mapickii install path (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${CONFIG_DIR}/CONFIG.md"

# Detect current CLI environment and set skill scan path
# Priority: CONFIG_DIR location > env vars > default OpenCode
_detect_skills_base() {
  # V1 scope: OpenClaw only (see plan/pr1/skill.md §1.3).
  echo "${HOME}/.openclaw/skills"
}

SKILLS_BASE_DIR="$(_detect_skills_base)"

MAPICKII_INIT_INTERVAL_MINUTES="${MAPICKII_INIT_INTERVAL_MINUTES:-30}"

# ── CONFIG.md read/write (YAML format) ────────────────
_ensure_config() {
  [[ -f "${CONFIG_FILE}" ]] || cat > "${CONFIG_FILE}" <<EOF
# Mapickii Configuration
# Auto-generated - do not delete manually

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
  local device_fp="${USER_ID:-}"

  # v2.0 auth: x-device-fp header (16-char lowercase hex)
  # Backend FpOrApiKeyGuard recognises this and derives userId server-side.
  local auth_args=()
  if [[ -n "${device_fp}" ]]; then
    auth_args+=(-H "x-device-fp: ${device_fp}")
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
    echo "{\"error\":\"service_unreachable\",\"code\":\"E_API_DOWN\",\"http\":\"${http_code}\",\"message\":\"Unable to connect to Mapickii backend\"}"
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
  # V1 first-install response. Lean JSON — no ASCII logo, no actions prompt,
  # no /recommend/feed call (lazy-loaded via 'recommend' command in PR-4).
  # AI is responsible for rendering in the user's conversation language.
  local device_fp="$(_config_get device_fp)"
  [[ -z "$device_fp" ]] && device_fp="$(_device_fp)"

  local scan_json skills_json skills_count
  scan_json="$(_scan_to_json)"
  if [[ -n "$scan_json" ]] && command -v jq >/dev/null 2>&1; then
    skills_json="$(echo "$scan_json" | jq -c '.skills // []' 2>/dev/null || echo '[]')"
    skills_count="$(echo "$scan_json" | jq '.skills // [] | length' 2>/dev/null || echo 0)"
  else
    skills_json="[]"
    skills_count=0
  fi

  DEVICE_FP="${device_fp}" \
  SKILLS_JSON="${skills_json}" \
  SKILLS_COUNT="${skills_count}" \
  python3 <<'PYEOF'
import os, json

try:
    skills = json.loads(os.environ.get("SKILLS_JSON", "[]"))
except Exception:
    skills = []

skill_names = [s.get("name", s.get("id", "?")) for s in skills[:5]]

data = {
    "status": "first_install",
    "data": {
        "deviceFingerprint": os.environ.get("DEVICE_FP", ""),
        "skillsCount": int(os.environ.get("SKILLS_COUNT", "0") or "0"),
        "skillNames": skill_names,
    },
    "privacy": "Anonymous by design. No registration. Run '/mapickii privacy status' to see what we track."
}
print(json.dumps(data, ensure_ascii=False))
PYEOF
}

# ── Scan helpers ──────────────────────────────────────
_scan_system() {
  # Output system info JSON (single line, no wrap)
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

  # Wrap as JSON (null literal without quotes, other values with quotes)
  local node_json py_json bash_json
  [[ "$node_ver" == "null" ]] && node_json="null" || node_json="\"${node_ver}\""
  [[ "$py_ver" == "null" ]] && py_json="null" || py_json="\"${py_ver}\""
  [[ "$bash_ver" == "null" ]] && bash_json="null" || bash_json="\"${bash_ver}\""

  printf '{"os":"%s","arch":"%s","hostname":"%s","home":"%s","node_version":%s,"python_version":%s,"bash_version":%s,"editors":{"claude_code":%s,"cursor":%s,"windsurf":%s}}' \
    "$os" "$arch" "$hostname" "$home" "$node_json" "$py_json" "$bash_json" "$cc" "$cursor" "$windsurf"
}

_scan_skills() {
  # Scan skill directories under ~/.claude/skills/ and $(pwd)/.claude/skills/
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
      # macOS stat compatible with Linux stat
      if stat -f '%B' "$d" >/dev/null 2>&1; then
        installed_at="$(date -u -r "$(stat -f '%B' "$d")" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
        last_modified="$(date -u -r "$(stat -f '%m' "$d")" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
      else
        installed_at="$(date -u -d "@$(stat -c '%W' "$d" 2>/dev/null || stat -c '%Y' "$d")" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
        last_modified="$(date -u -d "@$(stat -c '%Y' "$d")" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
      fi
      # Escape quotes in name
      local name_esc="${name//\"/\\\"}"
      items+=("{\"id\":\"${id}\",\"name\":\"${name_esc}\",\"path\":\"${path}\",\"installed_at\":\"${installed_at}\",\"enabled\":${enabled},\"last_modified\":\"${last_modified}\"}")
    done
  done

  # Build JSON array
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

  # Remove old scan block
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

  # Add new scan block, passing SKILLS_BASE_DIR
  SCAN_TS="$ts" SKILLS_BASE_DIR="${SKILLS_BASE_DIR}" python3 <<PYEOF >> "${CONFIG_FILE}"
import os
import subprocess
import json
from datetime import datetime, timezone

ts = os.environ.get("SCAN_TS", "")
skills_base = os.environ.get("SKILLS_BASE_DIR", os.path.expanduser("~/.openclaw/skills"))

# Scan skills (OpenClaw only — V1 scope decision)
skills = []
seen_ids = set()
skill_dirs = [
    os.path.expanduser("~/.openclaw/skills"),
    os.path.join(os.getcwd(), ".openclaw/skills"),
]

for root in skill_dirs:
    if not os.path.isdir(root):
        continue
    # Avoid scanning the same directory twice
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

        # Get timestamps
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

# Scan system
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

# Output YAML format
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

# ── C-02: Report scan diff as skill_install / skill_uninstall events ──
# This fixes the V1 root cause: _do_scan never told the backend what the user
# had installed. Result: skill_records table stayed empty, users saw
# "you have 0 skills" even after scanning 20. Fix: on every scan, compute the
# diff between old and new skill id sets, and POST one event per change.
#
# Args:
#   $1 = old_ids   (compact JSON array of strings, use "[]" for bootstrap)
#   $2 = new_ids   (compact JSON array of strings)
_report_scan_events() {
  local old_ids="${1:-[]}" new_ids="${2:-[]}"
  local added removed
  added="$(jq -cn --argjson o "$old_ids" --argjson n "$new_ids" '$n - $o' 2>/dev/null || echo '[]')"
  removed="$(jq -cn --argjson o "$old_ids" --argjson n "$new_ids" '$o - $n' 2>/dev/null || echo '[]')"

  # Report skill_install for each added skill
  echo "$added" | jq -r '.[]?' 2>/dev/null | while IFS= read -r skill_id; do
    [[ -z "$skill_id" ]] && continue
    local body="{\"action\":\"skill_install\",\"skillId\":\"${skill_id}\",\"userId\":\"${USER_ID}\",\"metadata\":{\"source\":\"scan\"}}"
    _http POST /event/track "$body" >/dev/null 2>&1 || true
  done

  # Report skill_uninstall for each removed skill (detected local deletion)
  echo "$removed" | jq -r '.[]?' 2>/dev/null | while IFS= read -r skill_id; do
    [[ -z "$skill_id" ]] && continue
    local body="{\"action\":\"skill_uninstall\",\"skillId\":\"${skill_id}\",\"userId\":\"${USER_ID}\",\"metadata\":{\"reason\":\"detected_removal\"}}"
    _http POST /event/track "$body" >/dev/null 2>&1 || true
  done
}

# ── Read scan data (parse YAML format from CONFIG.md) ──
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

# Parse YAML-format scan block
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

    # Non-indented line marks end of scan block
    if not line.startswith('  ') and line.strip():
        break

    # Parse scanned_at
    if line.strip().startswith('scanned_at:'):
        result['scanned_at'] = line.split(':', 1)[1].strip()
        continue

    # Parse skills
    if line.strip().startswith('skills:'):
        current_section = 'skills'
        continue

    # Parse system
    if line.strip().startswith('system:'):
        current_section = 'system'
        continue

    # Parse skill array item
    if current_section == 'skills' and line.strip().startswith('- id:'):
        current_skill = {'id': line.split(':', 1)[1].strip()}
        result['skills'].append(current_skill)
        continue

    # Parse skill attributes
    if current_section == 'skills' and current_skill:
        stripped = line.strip()
        if ':' in stripped:
            key, value = stripped.split(':', 1)
            key = key.strip()
            value = value.strip()
            # Handle boolean values
            if value == 'true':
                value = True
            elif value == 'false':
                value = False
            current_skill[key] = value

    # Parse system attributes
    if current_section == 'system':
        stripped = line.strip()
        if stripped.startswith('editors:'):
            current_section = 'editors'
            continue
        if ':' in stripped and not stripped.startswith('editors'):
            key, value = stripped.split(':', 1)
            result['system'][key.strip()] = value.strip()

    # Parse editors attributes
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

# ── Uninstall helpers ─────────────────────────────────
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
  # V1 scope: OpenClaw only.
  local id="$1"
  local user_path="${HOME}/.openclaw/skills/${id}"
  local project_path="$(pwd)/.openclaw/skills/${id}"
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

# ── First-use auto bootstrap ──────────────────────────
# V1 bootstrap triggers when either:
#   - CONFIG.md does not exist, OR
#   - device_fp is empty
# On first run: create device_fp + do one scan. Identity/mode fields are V1-sunset
# and no longer part of the bootstrap check.
COMMAND="${1:-}"

_need_bootstrap=0
if [[ ! -f "${CONFIG_FILE}" ]]; then
  _need_bootstrap=1
else
  [[ -z "$(_config_get device_fp)" ]] && _need_bootstrap=1
fi

if [[ ${_need_bootstrap} -eq 1 ]]; then
  _ensure_config
  [[ -z "$(_config_get device_fp)" ]] && _config_set device_fp "$(_device_fp)"
  [[ -z "$(_config_get created_at)" ]] && _config_set created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  _config_del last_init_at
  _do_scan
fi

# ── ISO to epoch timestamp conversion ─────────────────
_iso_to_epoch() {
  local ts="$1"
  if date -u -d "$ts" +%s >/dev/null 2>&1; then
    date -u -d "$ts" +%s
  else
    date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s 2>/dev/null || echo 0
  fi
}

# ── Command dispatch ──────────────────────────────────
USER_ID="$(_config_get device_fp)"
[[ -z "${USER_ID}" ]] && USER_ID="$(_device_fp)"

# ── Bundle recommendation functions ───────────────────
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

print('Bundle List')
print('===============')
print()

for b in bundles[:10]:
    bundle_id = b.get('bundleId', '?')
    name = b.get('name', '?')
    desc = b.get('description', '')[:50]
    skill_count = len(b.get('skillIds', []))
    print(f'{name}')
    print(f'  ID: {bundle_id}')
    print(f'  Contains {skill_count} Skills')
    print(f'  {desc}')
    print()

print('Reply \"bundle <ID>\" for details')
print('Reply \"bundle recommend\" for suggested bundles')
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

print(f'{name}')
print('===============')
print()
print(f'Bundle ID: {bundle_id}')
print(f'Description: {desc}')
print(f'Target Audience: {target}')
print()
print('Included Skills:')
print('===============')
for i, sid in enumerate(skill_ids[:10], 1):
    skill_name = sid.split(':')[-1] if ':' in sid else sid
    print(f'{i}. {skill_name}')
if len(skill_ids) > 10:
    print(f'  ... plus {len(skill_ids) - 10} more')

print()
print('Reply \"install bundle\" for one-click install')
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

    # Trigger condition: installed trigger skills OR installed 25%-75%
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
    print('No bundle recommendations')
    print()
    print('Reply \"bundle list\" to view all bundles')
else:
    matches.sort(key=lambda x: x['ratio'], reverse=True)
    m = matches[0]
    b = m['bundle']

    print(f'{b.get(\"name\", \"?\")}')
    print()
    print(f'You already installed {len(m[\"installed\"])}/{len(b.get(\"skillIds\", []))}')
    print('===============')

    for sid in m['installed'][:5]:
        name = sid.split(':')[-1] if ':' in sid else sid
        print(f'[installed] {name}')

    print()
    print('Recommended to complete:')
    print('===============')
    for i, sid in enumerate(m['missing'][:5], 1):
        name = sid.split(':')[-1] if ':' in sid else sid
        print(f'{i}. [missing] {name}')

    print()
    print(f'Reply \"install bundle {b.get(\"bundleId\", \"?\")}\" to complete')
" 2>/dev/null || echo '{"error":"parse_error"}'
}

_bundle_install() {
  # V2 flow: fetch installCommands from backend, return them to AI for execution.
  # AI runs each command, then calls bundle:track-installed to record success.
  local bundle_id="$1"
  [[ -z "$bundle_id" ]] && { echo '{"error":"missing_argument","message":"bundle install requires bundleId"}'; return; }

  local install_resp
  install_resp="$(_http GET "/bundle/${bundle_id}/install?platform=openclaw")"

  if echo "$install_resp" | grep -q '"error"'; then
    echo "$install_resp"
    return
  fi

  echo "$install_resp" | python3 - <<'PYEOF' 2>/dev/null || echo '{"error":"parse_failed","message":"bundle install response malformed"}'
import sys, json
try:
    data = json.loads(sys.stdin.read())
    cmds = data.get("installCommands", []) or []
    out = {
        "intent": "bundle:install",
        "bundleId": data.get("bundleId"),
        "skillIds": data.get("skillIds", []),
        "installCommands": cmds,
        "installed": False,
        "hint_for_ai": "Execute each installCommands[].command, then call 'bundle:track-installed <bundleId>'. See SKILL.md bundle section for failure handling."
    }
    print(json.dumps(out, ensure_ascii=False))
except Exception as e:
    print(json.dumps({"error": "parse_failed", "detail": str(e)}))
PYEOF
}

_bundle_track_installed() {
  # AI calls this after running all installCommands. shell records the event.
  local bundle_id="$1"
  [[ -z "$bundle_id" ]] && { echo '{"error":"missing_argument","message":"bundle:track-installed requires bundleId"}'; return; }

  local body="{\"action\":\"bundle_installed\",\"bundleId\":\"${bundle_id}\",\"userId\":\"${USER_ID}\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
  local track_resp
  track_resp="$(_http POST /event/track "$body")"
  echo "{\"intent\":\"bundle:track-installed\",\"bundleId\":\"${bundle_id}\",\"tracked\":true,\"backend\":${track_resp}}"
}

shift || true

# Auto scan refresh: TTL check for commands that need network or local data display
case "${COMMAND}" in
  status|clean|workflow|daily|weekly|chat)
    if _scan_needed; then _do_scan; fi
    ;;
esac

case "${COMMAND}" in
  # Identity (debug only) — returns local device_fp; no backend call.
  # V1 has no registration/login/mapick_id; device_fp is the only anonymous ID.
  identity|id)
    local_dfp="$(_config_get device_fp)"
    [[ -z "$local_dfp" ]] && local_dfp="$(_device_fp)"
    echo "{\"intent\":\"identity\",\"deviceFingerprint\":\"${local_dfp}\",\"mode\":\"local\"}"
    ;;

  init)
    # V1 init flow: two states (has last_init_at / not). No mode tracking.
    # C-02 integration: report skill_install/skill_uninstall events on every
    # scan diff so the backend's skill_records table stays in sync.
    now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    last_init_at="$(_config_get last_init_at)"

    # First install: bootstrap scan + report every scanned skill as install
    if [[ -z "${last_init_at}" ]]; then
      _do_scan
      scan_json="$(_scan_to_json)"
      new_ids_bootstrap="$(echo "$scan_json" | jq -c '[.skills // [] | .[].id]' 2>/dev/null || echo '[]')"
      # C-02: bootstrap reports everything as new install (old_ids = [])
      _report_scan_events '[]' "$new_ids_bootstrap"
      _config_set last_init_at "${now_utc}"
      _welcome_json
      exit 0
    fi

    # 30-minute idempotency window
    last_epoch="$(_iso_to_epoch "$last_init_at")"
    now_epoch="$(date -u +%s)"
    minutes_elapsed=$(( (now_epoch - last_epoch) / 60 ))

    if [[ "${minutes_elapsed}" -lt "${MAPICKII_INIT_INTERVAL_MINUTES}" ]]; then
      echo "{\"status\":\"skip\",\"next_in_minutes\":$(( MAPICKII_INIT_INTERVAL_MINUTES - minutes_elapsed ))}"
      exit 0
    fi

    # Re-scan + diff + C-02 event reporting
    scan_json="$(_scan_to_json)"
    old_ids="$(echo "$scan_json" | jq -c '[.skills // [] | .[].id] | sort' 2>/dev/null || echo '[]')"

    _do_scan
    _config_set last_init_at "${now_utc}"

    scan_json="$(_scan_to_json)"
    new_ids="$(echo "$scan_json" | jq -c '[.skills // [] | .[].id] | sort' 2>/dev/null || echo '[]')"

    # C-02: report diff events (added → skill_install, removed → skill_uninstall)
    _report_scan_events "$old_ids" "$new_ids"

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
      echo '{"error":"missing_argument","message":"uninstall requires skillId argument"}'
      exit 0
    fi
    shift || true

    # Parse --scope and --confirm (graceful fallback on missing args)
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

    # Protection check (regardless of confirm)
    if _is_protected "$skill_id"; then
      echo "{\"error\":\"protected_skill\",\"skillId\":\"${skill_id}\",\"message\":\"${skill_id} is a protected skill and cannot be deleted\"}"
      exit 0
    fi

    # Find local paths
    paths_raw="$(_scan_find_paths "$skill_id")"
    if [[ -z "$paths_raw" ]]; then
      # Not found locally, just run clean:track
      resp="$(_http POST /event/track "{\"action\":\"skill_uninstall\",\"skillId\":\"${skill_id}\",\"userId\":\"${USER_ID}\",\"metadata\":{\"reason\":\"manual-uninstall\"}}")"
      echo "{\"intent\":\"uninstall:no-local\",\"skillId\":\"${skill_id}\",\"message\":\"Skill not found locally, uninstall recorded\",\"track\":${resp}}"
      exit 0
    fi

    # Build paths JSON array and filter by scope
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

    # scope omitted and two found -> ambiguous
    if [[ -z "$scope" ]]; then
      count="$(printf '%s\n' "$paths_raw" | grep -c .)"
      if [[ "$count" -gt 1 ]]; then
        echo "{\"error\":\"ambiguous_scope\",\"skillId\":\"${skill_id}\",\"paths\":[${paths_json}],\"message\":\"Found in both user and project scope; use --scope to specify\"}"
        exit 0
      fi
    fi

    # Dry-run: no --confirm
    if [[ $confirm -eq 0 ]]; then
      echo "{\"intent\":\"uninstall:dry-run\",\"skillId\":\"${skill_id}\",\"protected\":false,\"paths\":[${paths_json}],\"message\":\"Not confirmed yet; pass --confirm to execute deletion\"}"
      exit 0
    fi

    # Perform backup + delete
    deleted_json=""
    for entry in "${selected_paths[@]}"; do
      ps="${entry%%:*}"
      pp="${entry#*:}"
      if ! backup_path="$(_backup_skill "$pp" "$skill_id")"; then
        echo "{\"error\":\"backup_failed\",\"path\":\"${pp}\",\"message\":\"Backup failed (disk space or permissions)\"}"
        exit 0
      fi
      if ! rm -rf "$pp" 2>/dev/null; then
        echo "{\"error\":\"permission_denied\",\"path\":\"${pp}\",\"message\":\"Delete failed (insufficient permissions)\"}"
        exit 0
      fi
      [[ -n "$deleted_json" ]] && deleted_json+=","
      deleted_json+="{\"scope\":\"${ps}\",\"path\":\"${pp}\",\"backup\":\"${backup_path}\"}"
    done

    # Record uninstall event
    track_resp="$(_http POST /event/track "{\"action\":\"skill_uninstall\",\"skillId\":\"${skill_id}\",\"userId\":\"${USER_ID}\",\"metadata\":{\"reason\":\"manual-uninstall\"}}")"
    # Refresh scan so scan.skills reflects deletion
    _do_scan
    echo "{\"intent\":\"uninstall\",\"skillId\":\"${skill_id}\",\"deleted\":[${deleted_json}],\"track\":${track_resp}}"
    ;;

# Lifecycle queries
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
      echo '{"error":"missing_argument","message":"clean:track requires skillId argument"}'
      exit 0
    fi

    # Build track request body (backend /event/track contract: action + skillId + userId + metadata)
    if [[ -n "$reason" ]]; then
      body="{\"action\":\"skill_uninstall\",\"skillId\":\"${skill_id}\",\"userId\":\"${USER_ID}\",\"metadata\":{\"reason\":\"${reason}\"}}"
    else
      body="{\"action\":\"skill_uninstall\",\"skillId\":\"${skill_id}\",\"userId\":\"${USER_ID}\",\"metadata\":{\"reason\":\"zombie_cleanup\"}}"
    fi
    track_resp="$(_http POST /event/track "$body")"

    # Protected skill: track only, don't delete
    if _is_protected "$skill_id"; then
      echo "{\"intent\":\"clean:track\",\"skillId\":\"${skill_id}\",\"deleted\":[],\"protected\":true,\"track\":${track_resp}}"
      exit 0
    fi

    # Check local paths; if found, backup+delete (zombie cleanup: user selected from list, treated as confirmed)
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
      echo '{"error":"missing_argument","message":"chat requires message argument"}'
      exit 0
    fi
    # JSON-escape quotes and backslashes in user message
    msg_escaped="${msg//\\/\\\\}"
    msg_escaped="${msg_escaped//\"/\\\"}"
    _http POST /assistant/chat "{\"userId\":\"${USER_ID}\",\"message\":\"${msg_escaped}\"}"
    ;;

# Referral code management (unified entry: ref <code>)
  referral|ref)
    code="${1:-}"

    if [[ -n "$code" ]]; then
      resp="$(_http POST /user/referral/bind "{\"deviceFingerprint\":\"${USER_ID}\",\"referralCode\":\"${code}\"}")"
      _extract_and_save_recommendations "$resp"

      if echo "$resp" | grep -q '"statusCode"'; then
        message="$(echo "$resp" | jq -r '.message // "Bind failed"')"
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
      rec_msg="$(echo "$rec_json" | python3 -c "import sys,json; recs=json.load(sys.stdin)[:3]; msg='Recommended installs\\n'; [msg+=f'{i+1}. {r.get(\"skillName\",\"?\")} - {r.get(\"reason\",\"\")}\\n' for i,r in enumerate(recs)]; print(msg)" 2>/dev/null)"
    fi

    python3 <<PYEOF
referral_code = "${referral_code}"
referred_by = "${referred_by}"
referral_count = "${referral_count}"
can_bind = ${py_can_bind}
mapick_id = "${mapick_id}"
bind_success = ${success:-False}
rec_msg = """${rec_msg}"""

print("Referral Code")
print("===============")
print(f"Mapick ID   {mapick_id}")
print(f"Code        {referral_code}")
print(f"Referred    {referral_count} people")
print()
if bind_success:
    print("Referral code bound successfully")
    print()
if referred_by:
    print(f"Referrer    {referred_by}")
    print()
    print("Already bound to a referrer, cannot re-bind")
else:
    print("Bind a referral code to earn rewards")
    print()
    print("Bind command:")
    print("  ref <code>")
if rec_msg:
    print()
    print(rec_msg)
PYEOF
;;

  referral:bind|ref:bind)
    code="${1:-}"
    if [[ -z "$code" ]]; then
      echo '{"error":"missing_argument","message":"ref bind requires referral code argument"}'
      exit 0
    fi
    resp="$(_http POST /user/referral/bind "{\"deviceFingerprint\":\"${USER_ID}\",\"referralCode\":\"${code}\"}")"

    if echo "$resp" | grep -q '"statusCode"'; then
      # Error response
      message="$(echo "$resp" | jq -r '.message // "Bind failed"')"
      echo "{\"error\":\"bind_failed\",\"message\":\"${message}\"}"
      exit 0
    fi

    # Success response
    success="$(echo "$resp" | jq -r '.success')"
    if [[ "$success" == "true" ]]; then
      referral_code="$(echo "$resp" | jq -r '.referralCode')"
      referred_by="$(echo "$resp" | jq -r '.referredBy')"
      referrer_id="$(echo "$resp" | jq -r '.referrer.mapickId')"

      # Write to CONFIG.md
      _config_set referral_code "$referral_code"
      _config_set referred_by "$referred_by"

      python3 <<PYEOF
referral_code = "${referral_code}"
referred_by = "${referred_by}"
referrer_id = "${referrer_id}"

print("Referral code bound successfully")
print()
print("Referrer")
print("===============")
print(f"Mapick ID   {referrer_id}")
print(f"Code        {referred_by}")
print()
print("Your Referral Code")
print("===============")
print(f"Code        {referral_code}")
print()
print("Reward: unlocks referral feature")
print("   Invite friends to earn points")
PYEOF
    else
      echo "$resp"
    fi
;;

push:daily|push:weekly|push:off)
    frequency="${COMMAND#push:}"
    last="$(_config_get last_push_mode)"
    if [[ "$last" == "$frequency" ]]; then
      resp="{\"intent\":\"push:noop\",\"data\":{\"frequency\":\"${frequency}\",\"message\":\"Already in ${frequency} mode\"}}"
      _inject_recommendations "$resp" "true"
      exit 0
    fi
    case "$frequency" in
      off)    push_text="disable push" ;;
      weekly) push_text="switch to weekly push" ;;
      daily)  push_text="daily push" ;;
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
    if [[ -z "$bundle_id" ]]; then
      echo '{"error":"missing_argument","message":"bundle install requires bundle ID argument"}'
      exit 0
    fi
    _bundle_install "$bundle_id"
    ;;

  bundle:track-installed|bundle-track-installed)
    # Called by AI after executing every installCommand from _bundle_install.
    # Records bundle_installed event to backend.
    _bundle_track_installed "${1:-}"
    ;;

help|--help|-h)

cat >&2 <<'USAGE'
Mapickii - Mapick Smart Assistant (V1)

Usage: bash shell.sh <command> [args...]

Identity (debug only):
  id                        View local device fingerprint

Bundle recommendations (M3):
  bundle                    List bundles
  bundle <id>               Bundle details
  bundle:recommend          Recommend bundles
  bundle:install <id>       Fetch install commands (AI executes, then calls bundle:track-installed)
  bundle:track-installed <id>  Record successful bundle install to backend

Lifecycle (M1):
  scan                      Scan local environment
  status                    Skill status overview
  clean                     Zombie skill list
  clean:track <skillId> [reason]  Record uninstall event
  uninstall <skillId> [--scope user|project|both] [--confirm]  Uninstall and remove local skill
  workflow                  Workflow analysis
  daily                     Daily digest
  weekly                    Weekly report
  chat <message>            Natural language fallback

Push frequency:
  push:daily | push:weekly | push:off

Environment variables:
  MAPICKII_API_BASE    Backend API prefix (default https://api.mapick.ai/v1)
USAGE
    echo '{"error":"usage","message":"see stderr"}'
    ;;

  *)
    echo "{\"error\":\"unknown_command\",\"command\":\"${COMMAND}\"}"
    ;;
esac
