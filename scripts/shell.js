#!/usr/bin/env node
/**
 * Mapickii skill unified entry point (Node.js)
 * Usage: node shell.js <command> [args...]
 */

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const https = require("https");
const os = require("os");
const { execSync } = require("child_process");

const CONFIG_DIR = path.dirname(__dirname);
const CONFIG_FILE = path.join(CONFIG_DIR, "CONFIG.md");
const TRASH_DIR = path.join(CONFIG_DIR, "trash");
const REDACTJS_PATH = path.join(CONFIG_DIR, "redact.js");
const API_BASE = process.env.MAPICKII_API_BASE || "https://api.mapick.ai/api/v1";
// 探测 skills 安装目录：openclaw / claude / codex 各平台路径不同。
// 优先级：env override → ~/.openclaw → ~/.claude → ~/.codex；都不存在则用 .openclaw
// 默认候选（首次安装会创建）。
function detectSkillsBase() {
  const home = os.homedir();
  const candidates = [
    process.env.SKILLS_BASE,
    process.env.MAPICKII_SKILLS_BASE,
    path.join(home, ".openclaw", "skills"),
    path.join(home, ".claude", "skills"),
    path.join(home, ".codex", "skills"),
  ].filter(Boolean);
  for (const dir of candidates) {
    if (fs.existsSync(dir)) return dir;
  }
  return candidates[0] || path.join(home, ".openclaw", "skills");
}
const SKILLS_BASE = detectSkillsBase();
const CACHE_DIR = path.join(os.homedir(), ".mapickii", "cache");

const VALID_TRACK_ACTIONS = [
  "shown",
  "click",
  "install",
  "installed",
  "ignore",
  "not_interested",
];
const VALID_EVENT_ACTIONS = [
  "skill_install",
  "skill_invoke",
  "skill_idle",
  "skill_uninstall",
  "rec_shown",
  "rec_click",
  "rec_ignore",
  "rec_installed",
  "sequence_pattern",
];
const PROTECTED_SKILLS = ["mapickii", "mapick", "tasa"];
const REMOTE_COMMANDS = new Set([
  "recommend",
  "recommend:track",
  "search",
  "workflow",
  "daily",
  "weekly",
  "report",
  "security",
  "security:report",
  "clean",
  "clean:track",
  "share",
]);

function deviceFp() {
  const config = readConfig();
  if (config.device_fp) return config.device_fp;
  const fp = crypto
    .createHash("sha256")
    .update(`${os.hostname()}|${os.platform()}|${os.homedir()}`)
    .digest("hex")
    .slice(0, 16);
  writeConfig("device_fp", fp);
  return fp;
}

function readConfig() {
  if (!fs.existsSync(CONFIG_FILE)) return {};
  const content = fs.readFileSync(CONFIG_FILE, "utf8");
  const config = {};
  content.split("\n").forEach((line) => {
    const match = line.match(/^(\w+):\s*(.+)$/);
    if (match) config[match[1]] = match[2];
  });
  return config;
}

function writeConfig(key, value) {
  const config = readConfig();
  config[key] = value;
  writeFullConfig(config);
}

function writeFullConfig(config) {
  const lines = [
    "# Mapickii Configuration",
    "# Auto-generated - do not delete manually",
    "",
  ];
  Object.entries(config).forEach(([k, v]) => lines.push(`${k}: ${v}`));
  fs.writeFileSync(CONFIG_FILE, lines.join("\n"));
}

function deleteConfig(key) {
  const config = readConfig();
  delete config[key];
  writeFullConfig(config);
}

function readCache(key) {
  const cacheFile = path.join(CACHE_DIR, `${key}.json`);
  if (!fs.existsSync(cacheFile)) return null;
  try {
    const data = JSON.parse(fs.readFileSync(cacheFile, "utf8"));
    const age = Date.now() - new Date(data.cached_at).getTime();
    const ttl = data.ttl_hours ? data.ttl_hours * 3600000 : 86400000;
    if (age > ttl) return null;
    return data;
  } catch {
    return null;
  }
}

function writeCache(key, data, ttlHours = 24) {
  if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR, { recursive: true });
  data.cached_at = new Date().toISOString();
  data.ttl_hours = ttlHours;
  fs.writeFileSync(path.join(CACHE_DIR, `${key}.json`), JSON.stringify(data));
}

async function httpCall(method, endpoint, body = null) {
  const base = API_BASE.replace(/\/$/, "") + "/";
  const url = new URL(endpoint.replace(/^\//, ""), base);
  const isHttps = url.protocol === "https:";
  const httpModule = isHttps ? https : require("http");
  const options = {
    hostname: url.hostname,
    port: url.port || (isHttps ? 443 : 80),
    path: url.pathname + url.search,
    method,
    headers: {
      "Content-Type": "application/json",
      "x-device-fp": deviceFp(),
    },
  };

  return new Promise((resolve, reject) => {
    const req = httpModule.request(options, (res) => {
      let data = "";
      res.on("data", (chunk) => (data += chunk));
      res.on("end", () => {
        if (res.statusCode === 401)
          resolve({ error: "unauthorized", statusCode: 401 });
        else if (res.statusCode === 404)
          resolve({ error: "not_found", statusCode: 404 });
        else if (res.statusCode === 429)
          resolve({ error: "rate_limit", statusCode: 429 });
        else if (res.statusCode >= 400)
          resolve({
            error: "http_error",
            statusCode: res.statusCode,
            body: data,
          });
        else {
          try {
            resolve(JSON.parse(data));
          } catch {
            resolve({ error: "parse_error", raw: data });
          }
        }
      });
    });
    req.on("error", (e) =>
      resolve({ error: "network_error", message: e.message }),
    );
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

// 轻量 frontmatter 解析：只取首块 ---...--- 的扁平 key:value（不支持嵌套）。
// 解析 boolean / 去引号；其他原样字符串。够用于读 enabled/disabled 这种简单字段。
function parseFrontmatter(content) {
  const m = content.match(/^---\s*\n([\s\S]*?)\n---/);
  if (!m) return {};
  const out = {};
  m[1].split("\n").forEach((line) => {
    const km = line.match(/^([a-z_][a-z0-9_]*)\s*:\s*(.+)$/i);
    if (!km) return;
    let v = km[2].trim();
    if (v === "true") v = true;
    else if (v === "false") v = false;
    else v = v.replace(/^["']|["']$/g, "");
    out[km[1]] = v;
  });
  return out;
}

function scanSkills() {
  const skills = [];
  if (!fs.existsSync(SKILLS_BASE)) return skills;
  const dirs = fs.readdirSync(SKILLS_BASE);
  dirs.forEach((dir) => {
    const skillPath = path.join(SKILLS_BASE, dir);
    const skillFile = path.join(skillPath, "SKILL.md");
    if (fs.statSync(skillPath).isDirectory() && fs.existsSync(skillFile)) {
      const content = fs.readFileSync(skillFile, "utf8");
      const fm = parseFrontmatter(content);
      skills.push({
        id: dir,
        name: typeof fm.name === "string" && fm.name ? fm.name : dir,
        path: skillPath,
        installed_at: fs.statSync(skillPath).birthtime.toISOString(),
        last_modified: fs.statSync(skillFile).mtime.toISOString(),
        // 默认启用；frontmatter 显式 disabled: true 才标 false
        enabled: fm.disabled !== true,
      });
    }
  });
  return skills;
}

function backupSkill(skillPath) {
  if (!fs.existsSync(TRASH_DIR)) fs.mkdirSync(TRASH_DIR, { recursive: true });
  const name = path.basename(skillPath);
  const backupPath = path.join(TRASH_DIR, `${name}_${Date.now()}`);
  fs.cpSync(skillPath, backupPath, { recursive: true });
  return backupPath;
}

function isProtected(skillId) {
  return PROTECTED_SKILLS.includes(skillId.toLowerCase());
}

function isoNow() {
  return new Date().toISOString();
}

// 统计 redact.js 中规则数（用于 summary 卡片"X rules active"提示）
// 简单算法：扫文件源里行首 `[/` 的 RULES 元组项数量。redact.js 改动后自动跟随。
// 候选路径：
//   - REDACTJS_PATH（CONFIG_DIR/redact.js）—— 历史路径，可能落在 mapickii/redact.js
//   - __dirname/redact.js —— 与 shell.js 同目录的 scripts/redact.js（实际位置）
function countRedactRules() {
  const candidates = [REDACTJS_PATH, path.join(__dirname, "redact.js")];
  for (const file of candidates) {
    if (!fs.existsSync(file)) continue;
    try {
      const content = fs.readFileSync(file, "utf8");
      const matches = content.match(/^\s*\[\//gm);
      if (matches && matches.length > 0) return matches.length;
    } catch {
      /* try next */
    }
  }
  return 0;
}

// 提取 profile 关键词：英文单词 + CJK 整词，去停用词去重，全部小写
// 用户输入 "Backend, Go + K8s, reading logs" → ["backend","go","k8s","reading","logs"]
// 用户输入 "后端开发，Go + K8s，看日志" → ["后端开发","go","k8s","看日志"]
function extractProfileTags(text) {
  if (!text) return [];
  const STOPWORDS = new Set([
    "and", "or", "the", "a", "an", "of", "in", "to", "for", "with", "i", "my",
    "is", "are", "do", "does", "doing", "use", "using", "uses",
    "和", "或", "的", "是", "在", "我", "你", "用", "做",
  ]);
  // 切分：空白 + 标点（中英），保留 CJK 整词
  const tokens = text
    .toLowerCase()
    .split(/[\s,，.。、；;:!?！？()（）{}\[\]【】"'`+]+/u)
    .map((t) => t.trim())
    .filter((t) => t.length >= 2 && !STOPWORDS.has(t));
  return [...new Set(tokens)];
}

// 聚合 summary：local skills + 可选 backend status（top_used/security counts）。
// backend 不可用（无 consent 或网络故障）时只返回 local 部分，has_backend=false。
async function aggregateSummary(skills, config) {
  const zombieDays = parseInt(process.env.MAPICKII_ZOMBIE_DAYS || "30", 10);
  const now = Date.now();
  const ageDays = (s) =>
    (now - new Date(s.last_modified).getTime()) / 86_400_000;

  const total = skills.length;
  const zombies = skills.filter((s) => ageDays(s) > zombieDays);
  const active = skills.filter(
    (s) => s.enabled !== false && ageDays(s) <= zombieDays,
  ).length;
  const neverUsed = skills.filter(
    (s) => s.installed_at && s.last_modified === s.installed_at,
  ).length;
  // context 占用估算：每个 zombie 约 2%，封顶 60%（V1 粗略，后端稳定后可换真实占比）
  const contextWastePct = Math.min(60, zombies.length * 2);

  const summary = {
    intent: "summary",
    privacy_rules: countRedactRules(),
    total,
    active,
    never_used: neverUsed,
    idle_30: zombies.length,
    activation_rate:
      total > 0 ? `${Math.round((active / total) * 100)}%` : "0%",
    zombie_count: zombies.length,
    context_waste_pct: contextWastePct,
    top_used: [],
    security: null,
    has_backend: false,
  };

  // backend 增强：top_used + security A/B/C 计数。未给 consent 直接跳。
  if (!hasConsent(config) || isConsentDeclined(config)) return summary;

  const fp = deviceFp();
  try {
    const status = await httpCall("GET", `/assistant/status/${fp}`);
    if (status && !status.error) {
      summary.has_backend = true;
      if (Array.isArray(status.top_used)) summary.top_used = status.top_used;
      if (status.security) summary.security = status.security;
    }
  } catch {
    /* graceful degrade — local 数据照常返回 */
  }
  return summary;
}

function isConsentDeclined(config) {
  return config.consent_declined === "true";
}

function hasConsent(config) {
  return Boolean(config.consent_version);
}

function isRemoteCommand(command, args) {
  if (REMOTE_COMMANDS.has(command)) return true;
  if (command === "bundle") return true;
  if (command === "privacy" && ["trust"].includes(args[0])) return true;
  return false;
}

function remoteAccessError(config) {
  if (isConsentDeclined(config)) {
    return {
      error: "disabled_in_local_mode",
      mode: "local_only",
      hint: "This command requires consent. Run: privacy consent-agree 1.0",
    };
  }

  return {
    error: "consent_required",
    hint: "This command requires consent. Run: privacy consent-agree 1.0",
  };
}

function redact(text) {
  if (!text) return text;
  const config = readConfig();
  if (config.redact_disabled === "true") return text;
  if (!fs.existsSync(REDACTJS_PATH)) return text;
  try {
    const result = execSync(`node "${REDACTJS_PATH}"`, {
      input: text,
      encoding: "utf8",
      timeout: 5000,
    });
    return result.trim();
  } catch {
    return text;
  }
}

const COMMAND = process.argv[2] || "status";
const ARGS = process.argv.slice(3);

async function main() {
  const config = readConfig();
  const fp = deviceFp();
  let result;

  if (isRemoteCommand(COMMAND, ARGS) && (!hasConsent(config) || isConsentDeclined(config))) {
    console.log(JSON.stringify(remoteAccessError(config)));
    return;
  }

  switch (COMMAND) {
    case "init":
    case "status":
      const lastInit = config.last_init_at
        ? new Date(config.last_init_at).getTime()
        : 0;
      const cooldown =
        parseInt(process.env.MAPICKII_INIT_INTERVAL_MINUTES || "30") * 60000;
      if (Date.now() - lastInit < cooldown) {
        result = { status: "skip", reason: "cooldown" };
        break;
      }
      writeConfig("last_init_at", isoNow());
      const skills = scanSkills();
      if (!config.device_fp) {
        writeConfig("created_at", isoNow());
        result = {
          status: "first_install",
          data: {
            skillsCount: skills.length,
            skillNames: skills.slice(0, 5).map((s) => s.name),
          },
          privacy: "Anonymous by design. No registration.",
        };
      } else {
        // 真实计算 zombie / activation_rate / never_used，替代之前的硬编码 0/二分。
        // 数据来源都是本地 mtime/frontmatter；后端的 invokeCount cron 是另一套精确数据。
        const zombieDays = parseInt(
          process.env.MAPICKII_ZOMBIE_DAYS || "30",
          10,
        );
        const now = Date.now();
        const ageDays = (s) =>
          (now - new Date(s.last_modified).getTime()) / 86_400_000;

        const zombies = skills.filter((s) => ageDays(s) > zombieDays);
        const total = skills.length;
        // active = 启用且非 zombie；既排除显式 disabled 也排除长期未动的
        const active = skills.filter(
          (s) => s.enabled && ageDays(s) <= zombieDays,
        ).length;

        result = {
          intent: "status",
          skills,
          activation_rate:
            total > 0 ? `${Math.round((active / total) * 100)}%` : "0%",
          zombie_count: zombies.length,
          // never_used 仍按 last_modified 做近似（本地拿不到真实调用次数）
          never_used: skills.filter((s) => !s.last_modified).length,
        };
      }
      break;

    case "scan":
      const scannedSkills = scanSkills();
      result = { intent: "scan", skills: scannedSkills, scanned_at: isoNow() };
      break;

    case "recommend": {
      // --with-profile：把 CONFIG.md 里 user_profile_tags 拼到 query 让后端 boost。
      const withProfile = ARGS.includes("--with-profile");
      const numericArgs = ARGS.filter((a) => !a.startsWith("--"));
      const limit = parseInt(numericArgs[0]) || 5;
      const cacheKey = `recommend_${fp}`;
      const cached = readCache(cacheKey);
      // 显式 limit 或 --with-profile 都强制走后端，绕过 24h 缓存
      const useCache = !withProfile && numericArgs.length === 0;
      if (useCache && cached) {
        result = { intent: "recommend", items: cached.items, cached: true };
      } else {
        let url = `/recommendations/feed?limit=${limit}`;
        if (withProfile) {
          const tagsRaw = config.user_profile_tags || "";
          // CONFIG 存的是 JSON 数组字符串，解析失败兜底为逗号分隔
          let tags = [];
          try {
            tags = JSON.parse(tagsRaw);
          } catch {
            tags = tagsRaw.split(",").filter(Boolean);
          }
          if (tags.length > 0) {
            url += `&profileTags=${encodeURIComponent(tags.join(","))}`;
          }
          url += `&withProfile=1`;
        }
        const resp = await httpCall("GET", url);
        if (resp.error) result = resp;
        else {
          result = {
            intent: "recommend",
            items: resp.items || resp.recommendations || [],
            withProfile,
          };
          writeCache(cacheKey, { items: result.items });
        }
      }
      break;
    }

    case "recommend:track":
      if (ARGS.length < 3) {
        result = {
          error: "missing_argument",
          hint: "Usage: recommend:track <recId> <skillId> <action>",
        };
        break;
      }
      const [recId, skillId, action] = ARGS;
      if (!VALID_TRACK_ACTIONS.includes(action)) {
        result = { error: "invalid_action", valid: VALID_TRACK_ACTIONS };
        break;
      }
      result = await httpCall("POST", "/recommendations/track", {
        recId,
        skillId,
        action,
        userId: fp,
      });
      result.intent = "recommend:track";
      break;

    case "search":
      const query = ARGS[0] || "";
      const searchLimit = Math.min(parseInt(ARGS[1]) || 10, 20);
      if (!query.trim()) {
        result = { intent: "search", items: [], total: 0, query: "" };
        break;
      }
      const searchResp = await httpCall(
        "GET",
        `/skills/live-search?query=${encodeURIComponent(query)}&limit=${searchLimit}`,
      );
      if (searchResp.error) result = searchResp;
      else {
        const items = searchResp.results || searchResp.items || [];
        result = {
          intent: "search",
          items,
          total: items.length,
          query,
          ...(items.length < 5
            ? { notice: "Few local matches. Try ClawHub for more results." }
            : {}),
        };
      }
      break;

    case "clean":
      const cleanResp = await httpCall("GET", `/users/${fp}/zombies`);
      result = {
        intent: "clean",
        zombies: cleanResp.zombies || cleanResp || [],
      };
      break;

    case "clean:track":
      if (ARGS.length < 1) {
        result = {
          error: "missing_argument",
          hint: "Usage: clean:track <skillId>",
        };
        break;
      }
      result = await httpCall("POST", "/events/track", {
        userId: fp,
        skillId: ARGS[0],
        action: "skill_uninstall",
        metadata: { reason: "zombie_cleanup" },
      });
      result.intent = "clean:track";
      break;

    case "uninstall":
      if (ARGS.length < 1) {
        result = {
          error: "missing_argument",
          hint: "Usage: uninstall <skillId> [--confirm]",
        };
        break;
      }
      const targetId = ARGS[0];
      if (!ARGS.includes("--confirm")) {
        result = {
          error: "confirm_required",
          hint: "Add --confirm to execute",
        };
        break;
      }
      if (isProtected(targetId)) {
        result = { error: "protected_skill", skillId: targetId };
        break;
      }
      const skillDir = path.join(SKILLS_BASE, targetId);
      if (!fs.existsSync(skillDir)) {
        result = { error: "not_found", skillId: targetId };
        break;
      }
      const backup = backupSkill(skillDir);
      fs.rmSync(skillDir, { recursive: true, force: true });
      result = {
        intent: "uninstall",
        skillId: targetId,
        backup_path: backup,
        uninstalled_at: isoNow(),
      };
      break;

    case "workflow":
      result = await httpCall("GET", `/assistant/workflow/${fp}`);
      result.intent = "workflow";
      break;

    case "daily":
      result = await httpCall("GET", `/assistant/daily-digest/${fp}`);
      result.intent = "daily";
      break;

    case "weekly":
      result = await httpCall("GET", `/assistant/weekly/${fp}`);
      result.intent = "weekly";
      break;

    case "bundle":
      if (ARGS[0] === "recommend") {
        result = await httpCall("GET", "/bundle/recommend/list");
        result.intent = "bundle:recommend";
      } else if (ARGS[0] === "install" && ARGS[1]) {
        result = await httpCall("GET", `/bundle/${ARGS[1]}/install`);
        result.intent = "bundle:install";
        result.bundleId = ARGS[1];
      } else if (ARGS[0] === "track-installed" && ARGS[1]) {
        result = await httpCall("POST", "/bundle/seed", {
          bundleId: ARGS[1],
          userId: fp,
        });
        result.intent = "bundle:track-installed";
      } else if (ARGS[0]) {
        result = await httpCall("GET", `/bundle/${ARGS[0]}`);
        result.intent = "bundle:detail";
      } else {
        result = await httpCall("GET", "/bundle");
        result.intent = "bundle";
      }
      break;

    case "report":
      const reportResp = await httpCall("GET", `/report/persona`);
      result = { intent: "report", ...reportResp };
      if (
        result.status === "brewing" ||
        result.primaryPersona?.id === "fresh_meat"
      ) {
        result.status = result.status || "brewing";
        result.messageEn =
          result.messageEn ||
          ":lock: Your persona is brewing. Use Mapick for a few more skill actions before generating a shareable report.";
      }
      break;

    case "share":
      if (ARGS.length < 2) {
        result = {
          error: "missing_argument",
          hint: "Usage: share <reportId> <htmlFile>",
        };
        break;
      }
      const [reportId, htmlFile] = ARGS;
      if (!fs.existsSync(htmlFile)) {
        result = { error: "file_not_found", file: htmlFile };
        break;
      }
      const htmlContent = redact(fs.readFileSync(htmlFile, "utf8"));
      result = await httpCall("POST", "/share/upload", {
        reportId,
        html: htmlContent,
        locale: ARGS[2] || "en",
      });
      result.intent = "share";
      break;

    case "security":
      if (ARGS.length < 1) {
        result = {
          error: "missing_argument",
          hint: "Usage: security <skillId>",
        };
        break;
      }
      result = await httpCall("GET", `/skill/${ARGS[0]}/security`);
      result.intent = "security";
      break;

    case "security:report":
      if (ARGS.length < 3) {
        result = {
          error: "missing_argument",
          hint: "Usage: security:report <skillId> <reason> <evidence>",
        };
        break;
      }
      result = await httpCall("POST", `/skill/${ARGS[0]}/report`, {
        reason: ARGS[1],
        evidenceEn: ARGS[2],
      });
      result.intent = "security:report";
      break;

    case "privacy":
      const subCmd = ARGS[0] || "status";
      switch (subCmd) {
        case "status":
          result = {
            intent: "privacy:status",
            consent_version: config.consent_version || null,
            consent_agreed_at: config.consent_agreed_at || null,
            consent_declined: config.consent_declined === "true",
            remote_access:
              config.consent_declined === "true"
                ? "local_only"
                : config.consent_version
                  ? "enabled"
                  : "consent_required",
            trusted_skills: config.trusted_skills
              ? config.trusted_skills.split(",")
              : [],
            redact_disabled: config.redact_disabled === "true",
          };
          break;

        case "trust":
          if (ARGS.length < 2) {
            result = {
              error: "missing_argument",
              hint: "Usage: privacy trust <skillId>",
            };
            break;
          }
          result = await httpCall("POST", "/users/trusted-skills", {
            userId: fp,
            skillId: ARGS[1],
            permission: "unredacted",
          });
          result.intent = "privacy:trust";
          const trusted = config.trusted_skills
            ? config.trusted_skills.split(",")
            : [];
          trusted.push(ARGS[1]);
          writeConfig("trusted_skills", trusted.join(","));
          break;

        case "untrust":
          if (ARGS.length < 2) {
            result = {
              error: "missing_argument",
              hint: "Usage: privacy untrust <skillId>",
            };
            break;
          }
          const untrusted = (
            config.trusted_skills ? config.trusted_skills.split(",") : []
          ).filter((s) => s !== ARGS[1]);
          writeConfig("trusted_skills", untrusted.join(","));
          result = { intent: "privacy:untrust", skillId: ARGS[1] };
          break;

        case "delete-all":
          if (!ARGS.includes("--confirm")) {
            result = {
              error: "confirm_required",
              destructive_scope:
                "local CONFIG.md + cache + trash + backend data (events, skill records, consents, trusted skills, recommendation feedback, share reports)",
            };
            break;
          }
          const deleteResp = await httpCall("DELETE", "/users/data");
          fs.rmSync(CONFIG_FILE, { force: true });
          fs.rmSync(CACHE_DIR, { recursive: true, force: true });
          fs.rmSync(TRASH_DIR, { recursive: true, force: true });
          const preservedFp = config.device_fp;
          fs.writeFileSync(
            CONFIG_FILE,
            `# Mapickii Configuration\n# Auto-generated\n\ndevice_fp: ${preservedFp}\n`,
          );
          result = {
            intent: "privacy:delete-all",
            localCleared: true,
            backendResponse: deleteResp,
          };
          break;

        case "consent-agree":
          const version = ARGS[1] || "1.0";
          const now = isoNow();
          await httpCall("POST", "/users/consent", {
            consentVersion: version,
            agreedAt: now,
          });
          writeConfig("consent_version", version);
          writeConfig("consent_agreed_at", now);
          deleteConfig("consent_declined");
          deleteConfig("consent_declined_at");
          result = { intent: "privacy:consent-agree", version, agreedAt: now };
          break;

        case "consent-decline":
          const declinedAt = isoNow();
          writeConfig("consent_declined", "true");
          writeConfig("consent_declined_at", declinedAt);
          result = {
            intent: "privacy:consent-decline",
            mode: "local_only",
            declinedAt,
          };
          break;

        case "disable-redact":
          writeConfig("redact_disabled", "true");
          writeConfig("redact_disabled_at", isoNow());
          result = {
            intent: "privacy:disable-redact",
            status: "disabled",
            warning: "Sensitive data will be passed AS-IS",
          };
          break;

        case "enable-redact":
          deleteConfig("redact_disabled");
          deleteConfig("redact_disabled_at");
          result = { intent: "privacy:enable-redact", status: "enabled" };
          break;

        default:
          result = {
            error: "unknown_subcommand",
            hint: "Available: status | trust | untrust | delete-all | consent-agree | consent-decline | disable-redact | enable-redact",
          };
      }
      break;

    case "event":
    case "event:track":
      if (ARGS.length < 2) {
        result = {
          error: "missing_argument",
          hint: "Usage: event:track <userId> <action> [skillId]",
        };
        break;
      }
      const [userId, actionType, metaSkillId] = ARGS;
      if (!VALID_EVENT_ACTIONS.includes(actionType)) {
        result = { error: "invalid_action", valid: VALID_EVENT_ACTIONS };
        break;
      }
      result = await httpCall("POST", "/events/track", {
        userId,
        action: actionType,
        skillId: metaSkillId || null,
      });
      result.intent = "event:track";
      break;

    // 首次安装诊断卡聚合：local skills + （可选）backend top_used / security counts
    case "summary": {
      const skills = scanSkills();
      result = await aggregateSummary(skills, config);
      break;
    }

    // 用户工作流自描述：profile set/get/clear。set 同时把抽取的 tags 异步上传后端（有 consent 时）。
    case "profile": {
      const subCmd = ARGS[0] || "get";
      switch (subCmd) {
        case "set": {
          const text = ARGS.slice(1).join(" ").trim();
          if (!text) {
            result = {
              error: "missing_argument",
              hint: "Usage: profile set \"<workflow text>\"",
            };
            break;
          }
          const tags = extractProfileTags(text);
          writeConfig("user_profile", text);
          writeConfig("user_profile_tags", JSON.stringify(tags));
          writeConfig("user_profile_set_at", isoNow());
          // 后端有 consent 时把 profile 上传，让推荐能 boost；失败不阻塞本地存储
          let uploaded = false;
          if (hasConsent(config) && !isConsentDeclined(config)) {
            const resp = await httpCall("POST", "/users/profile", {
              userId: fp,
              profile: text,
              tags,
            });
            uploaded = !resp.error;
          }
          result = { intent: "profile:set", profile: text, tags, uploaded };
          break;
        }
        case "get": {
          let tags = [];
          try {
            tags = JSON.parse(config.user_profile_tags || "[]");
          } catch {
            tags = [];
          }
          result = {
            intent: "profile:get",
            profile: config.user_profile || null,
            tags,
            set_at: config.user_profile_set_at || null,
          };
          break;
        }
        case "clear": {
          deleteConfig("user_profile");
          deleteConfig("user_profile_tags");
          deleteConfig("user_profile_set_at");
          // 清 profile 顺带清 first_run_complete，让下次 init 重新触发首次诊断卡
          deleteConfig("first_run_complete");
          deleteConfig("first_run_at");
          result = { intent: "profile:clear", cleared: true };
          break;
        }
        default:
          result = {
            error: "unknown_subcommand",
            hint: "Available: set | get | clear",
          };
      }
      break;
    }

    // 标记首次诊断流程完成（一次性 flag，避免每次启动都跑首次诊断卡）
    case "first-run-done":
      writeConfig("first_run_complete", "true");
      writeConfig("first_run_at", isoNow());
      result = { intent: "first-run-done", done: true };
      break;

    case "id":
      result = { intent: "id", debug_identifier: fp };
      break;

    case "help":
    case "--help":
    case "-h":
      console.error(`Mapickii - Node.js version

Usage: node shell.js <command> [args...]

Commands:
  init / status           Skill status overview
  scan                    Force re-scan
  recommend [limit]       Personalized recommendations (cached 24h)
  recommend:track <recId> <skillId> <action>  Track feedback
  search <query> [limit]  Search skills
  clean                   Zombie skill list
  clean:track <skillId>   Record zombie cleanup
  uninstall <skillId> [--confirm]  Uninstall skill (backup to trash)
  workflow                Workflow analysis
  daily                   Daily digest
  weekly                  Weekly report
  bundle                  List bundles
  bundle <id>             Bundle details
  bundle:install <id>     Fetch install commands
  bundle:track-installed <id>  Record bundle install
  report                  Persona report
  share <reportId> <html> [locale]  Upload share page
  security <skillId>      Security score
  privacy status          Show consent + trusted skills
  privacy trust <skillId>      Trust a skill
  privacy untrust <skillId>    Revoke trust
  privacy delete-all --confirm  GDPR erasure
  privacy consent-agree [version]  Record consent
  privacy consent-decline      Decline consent (local-only mode)
  event:track <userId> <action> [skillId]  Record event
  summary                 First-run diagnostic (local + optional backend)
  profile set "<text>"    Save user workflow self-description
  profile get             Read cached workflow profile
  profile clear           Reset profile + retrigger first-run summary
  first-run-done          Mark one-time first-run flag complete
  id                      Debug identifier (debug)`);
      result = { error: "usage" };
      break;

    default:
      result = {
        error: "unknown_command",
        command: COMMAND,
        hint: "Run help for usage",
      };
  }

  console.log(JSON.stringify(result));
}

main().catch((e) => console.log(JSON.stringify({ error: e.message })));
