#!/usr/bin/env node
/**
 * Mapickii skill unified entry point (Node.js)
 * Usage: node shell.js <command> [args...]
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const https = require('https');
const os = require('os');
const { execSync } = require('child_process');

const CONFIG_DIR = path.dirname(__dirname);
const CONFIG_FILE = path.join(CONFIG_DIR, 'CONFIG.md');
const TRASH_DIR = path.join(CONFIG_DIR, 'trash');
const REDACTJS_PATH = path.join(CONFIG_DIR, 'redact.js');
const API_BASE = process.env.MAPICKII_API_BASE || 'https://api.mapick.ai/v1';
const SKILLS_BASE = process.env.SKILLS_BASE || path.join(os.homedir(), '.openclaw', 'skills');
const CACHE_DIR = path.join(os.homedir(), '.mapickii', 'cache');

const VALID_TRACK_ACTIONS = ['shown', 'click', 'install', 'installed', 'ignore', 'not_interested'];
const VALID_EVENT_ACTIONS = ['skill_install', 'skill_invoke', 'skill_idle', 'skill_uninstall', 'rec_shown', 'rec_click', 'rec_ignore', 'rec_installed', 'sequence_pattern'];
const PROTECTED_SKILLS = ['mapickii', 'mapick', 'tasa'];

function deviceFp() {
  const config = readConfig();
  if (config.device_fp) return config.device_fp;
  const fp = crypto.createHash('sha256')
    .update(`${os.hostname()}|${os.platform()}|${os.homedir()}`)
    .digest('hex').slice(0, 16);
  writeConfig('device_fp', fp);
  return fp;
}

function readConfig() {
  if (!fs.existsSync(CONFIG_FILE)) return {};
  const content = fs.readFileSync(CONFIG_FILE, 'utf8');
  const config = {};
  content.split('\n').forEach(line => {
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
  const lines = ['# Mapickii Configuration', '# Auto-generated - do not delete manually', ''];
  Object.entries(config).forEach(([k, v]) => lines.push(`${k}: ${v}`));
  fs.writeFileSync(CONFIG_FILE, lines.join('\n'));
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
    const data = JSON.parse(fs.readFileSync(cacheFile, 'utf8'));
    const age = Date.now() - new Date(data.cached_at).getTime();
    const ttl = data.ttl_hours ? data.ttl_hours * 3600000 : 86400000;
    if (age > ttl) return null;
    return data;
  } catch { return null; }
}

function writeCache(key, data, ttlHours = 24) {
  if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR, { recursive: true });
  data.cached_at = new Date().toISOString();
  data.ttl_hours = ttlHours;
  fs.writeFileSync(path.join(CACHE_DIR, `${key}.json`), JSON.stringify(data));
}

async function httpCall(method, endpoint, body = null) {
  const url = new URL(endpoint, API_BASE);
  const options = {
    hostname: url.hostname,
    port: url.port || 443,
    path: url.pathname + url.search,
    method,
    headers: {
      'Content-Type': 'application/json',
      'x-device-fp': deviceFp()
    }
  };
  
  return new Promise((resolve, reject) => {
    const req = https.request(options, res => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode === 401) resolve({ error: 'unauthorized', statusCode: 401 });
        else if (res.statusCode === 404) resolve({ error: 'not_found', statusCode: 404 });
        else if (res.statusCode === 429) resolve({ error: 'rate_limit', statusCode: 429 });
        else if (res.statusCode >= 400) resolve({ error: 'http_error', statusCode: res.statusCode, body: data });
        else {
          try { resolve(JSON.parse(data)); }
          catch { resolve({ error: 'parse_error', raw: data }); }
        }
      });
    });
    req.on('error', e => resolve({ error: 'network_error', message: e.message }));
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

function scanSkills() {
  const skills = [];
  if (!fs.existsSync(SKILLS_BASE)) return skills;
  const dirs = fs.readdirSync(SKILLS_BASE);
  dirs.forEach(dir => {
    const skillPath = path.join(SKILLS_BASE, dir);
    const skillFile = path.join(skillPath, 'SKILL.md');
    if (fs.statSync(skillPath).isDirectory() && fs.existsSync(skillFile)) {
      const content = fs.readFileSync(skillFile, 'utf8');
      const nameMatch = content.match(/^---[\s\S]*?name:\s*(.+)[\s\S]*?---/);
      skills.push({
        id: dir,
        name: nameMatch ? nameMatch[1].trim() : dir,
        path: skillPath,
        installed_at: fs.statSync(skillPath).birthtime.toISOString(),
        last_modified: fs.statSync(skillFile).mtime.toISOString(),
        enabled: true
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

function redact(text) {
  if (!text) return text;
  const config = readConfig();
  if (config.redact_disabled === 'true') return text;
  if (!fs.existsSync(REDACTJS_PATH)) return text;
  try {
    const result = execSync(`node "${REDACTJS_PATH}"`, {
      input: text,
      encoding: 'utf8',
      timeout: 5000
    });
    return result.trim();
  } catch {
    return text;
  }
}

const COMMAND = process.argv[2] || 'status';
const ARGS = process.argv.slice(3);

async function main() {
  const config = readConfig();
  const fp = deviceFp();
  let result;

  switch (COMMAND) {
    case 'init':
    case 'status':
      const lastInit = config.last_init_at ? new Date(config.last_init_at).getTime() : 0;
      const cooldown = parseInt(process.env.MAPICKII_INIT_INTERVAL_MINUTES || '30') * 60000;
      if (Date.now() - lastInit < cooldown) {
        result = { status: 'skip', reason: 'cooldown' };
        break;
      }
      writeConfig('last_init_at', isoNow());
      const skills = scanSkills();
      if (!config.device_fp) {
        writeConfig('created_at', isoNow());
        result = {
          status: 'first_install',
          data: { deviceFingerprint: fp, skillsCount: skills.length, skillNames: skills.slice(0, 5).map(s => s.name) },
          privacy: 'Anonymous by design. No registration.'
        };
      } else {
        result = {
          intent: 'status',
          device_fp: fp,
          skills,
          activation_rate: skills.filter(s => s.enabled).length > 0 ? '100%' : '0%',
          zombie_count: 0,
          never_used: skills.filter(s => !s.last_modified).length
        };
      }
      break;

    case 'scan':
      const scannedSkills = scanSkills();
      result = { intent: 'scan', skills: scannedSkills, scanned_at: isoNow() };
      break;

    case 'recommend':
      const limit = parseInt(ARGS[0]) || 5;
      const cacheKey = `recommend_${fp}`;
      const cached = readCache(cacheKey);
      if (cached && ARGS.length === 0) {
        result = { intent: 'recommend', items: cached.items, cached: true };
      } else {
        const resp = await httpCall('GET', `/recommendations/feed?limit=${limit}`);
        if (resp.error) result = resp;
        else {
          result = { intent: 'recommend', items: resp.items || resp.recommendations || [], device_fp: fp };
          writeCache(cacheKey, { items: result.items });
        }
      }
      break;

    case 'recommend:track':
      if (ARGS.length < 3) {
        result = { error: 'missing_argument', hint: 'Usage: recommend:track <recId> <skillId> <action>' };
        break;
      }
      const [recId, skillId, action] = ARGS;
      if (!VALID_TRACK_ACTIONS.includes(action)) {
        result = { error: 'invalid_action', valid: VALID_TRACK_ACTIONS };
        break;
      }
      result = await httpCall('POST', '/recommendations/track', { recId, skillId, action, userId: fp });
      result.intent = 'recommend:track';
      break;

    case 'search':
      const query = ARGS[0] || '';
      const searchLimit = Math.min(parseInt(ARGS[1]) || 10, 20);
      if (!query.trim()) {
        result = { intent: 'search', items: [], total: 0, query: '' };
        break;
      }
      const searchResp = await httpCall('GET', `/skills/live-search?query=${encodeURIComponent(query)}&limit=${searchLimit}`);
      if (searchResp.error) result = searchResp;
      else {
        const items = searchResp.results || searchResp.items || [];
        result = {
          intent: 'search',
          items,
          total: items.length,
          query,
          ...(items.length < 5 ? { notice: 'Few local matches. Try ClawHub for more results.' } : {})
        };
      }
      break;

    case 'clean':
      const cleanResp = await httpCall('GET', `/users/${fp}/zombies`);
      result = { intent: 'clean', zombies: cleanResp.zombies || cleanResp || [] };
      break;

    case 'clean:track':
      if (ARGS.length < 1) {
        result = { error: 'missing_argument', hint: 'Usage: clean:track <skillId>' };
        break;
      }
      result = await httpCall('POST', '/events/track', { userId: fp, skillId: ARGS[0], action: 'skill_uninstall', metadata: { reason: 'zombie_cleanup' } });
      result.intent = 'clean:track';
      break;

    case 'uninstall':
      if (ARGS.length < 1) {
        result = { error: 'missing_argument', hint: 'Usage: uninstall <skillId> [--confirm]' };
        break;
      }
      const targetId = ARGS[0];
      if (!ARGS.includes('--confirm')) {
        result = { error: 'confirm_required', hint: 'Add --confirm to execute' };
        break;
      }
      if (isProtected(targetId)) {
        result = { error: 'protected_skill', skillId: targetId };
        break;
      }
      const skillDir = path.join(SKILLS_BASE, targetId);
      if (!fs.existsSync(skillDir)) {
        result = { error: 'not_found', skillId: targetId };
        break;
      }
      const backup = backupSkill(skillDir);
      fs.rmSync(skillDir, { recursive: true, force: true });
      result = { intent: 'uninstall', skillId: targetId, backup_path: backup, uninstalled_at: isoNow() };
      break;

    case 'workflow':
      result = await httpCall('GET', `/assistant/workflow/${fp}`);
      result.intent = 'workflow';
      break;

    case 'daily':
      result = await httpCall('GET', `/assistant/daily-digest/${fp}`);
      result.intent = 'daily';
      break;

    case 'weekly':
      result = await httpCall('GET', `/assistant/weekly/${fp}`);
      result.intent = 'weekly';
      break;

    case 'bundle':
      if (ARGS[0] === 'recommend') {
        result = await httpCall('GET', '/bundle/recommend/list');
        result.intent = 'bundle:recommend';
      } else if (ARGS[0] === 'install' && ARGS[1]) {
        result = await httpCall('GET', `/bundle/${ARGS[1]}/install`);
        result.intent = 'bundle:install';
        result.bundleId = ARGS[1];
      } else if (ARGS[0] === 'track-installed' && ARGS[1]) {
        result = await httpCall('POST', '/bundle/seed', { bundleId: ARGS[1], userId: fp });
        result.intent = 'bundle:track-installed';
      } else if (ARGS[0]) {
        result = await httpCall('GET', `/bundle/${ARGS[0]}`);
        result.intent = 'bundle:detail';
      } else {
        result = await httpCall('GET', '/bundle');
        result.intent = 'bundle';
      }
      break;

    case 'report':
      const reportResp = await httpCall('GET', `/report/persona`);
      result = { intent: 'report', ...reportResp };
      break;

    case 'share':
      if (ARGS.length < 2) {
        result = { error: 'missing_argument', hint: 'Usage: share <reportId> <htmlFile>' };
        break;
      }
      const [reportId, htmlFile] = ARGS;
      if (!fs.existsSync(htmlFile)) {
        result = { error: 'file_not_found', file: htmlFile };
        break;
      }
      const htmlContent = redact(fs.readFileSync(htmlFile, 'utf8'));
      result = await httpCall('POST', '/share/upload', { reportId, html: htmlContent, locale: ARGS[2] || 'en' });
      result.intent = 'share';
      break;

    case 'security':
      if (ARGS.length < 1) {
        result = { error: 'missing_argument', hint: 'Usage: security <skillId>' };
        break;
      }
      result = await httpCall('GET', `/security/${ARGS[0]}`);
      result.intent = 'security';
      break;

    case 'security:report':
      if (ARGS.length < 3) {
        result = { error: 'missing_argument', hint: 'Usage: security:report <skillId> <reason> <evidence>' };
        break;
      }
      result = await httpCall('POST', '/security/report', { skillId: ARGS[0], reason: ARGS[1], evidence: ARGS[2], userId: fp });
      result.intent = 'security:report';
      break;

    case 'privacy':
      const subCmd = ARGS[0] || 'status';
      switch (subCmd) {
        case 'status':
          result = {
            intent: 'privacy:status',
            device_fp: fp,
            consent_version: config.consent_version || null,
            consent_agreed_at: config.consent_agreed_at || null,
            consent_declined: config.consent_declined === 'true',
            trusted_skills: config.trusted_skills ? config.trusted_skills.split(',') : [],
            redact_disabled: config.redact_disabled === 'true'
          };
          break;

        case 'trust':
          if (ARGS.length < 2) {
            result = { error: 'missing_argument', hint: 'Usage: privacy trust <skillId>' };
            break;
          }
          result = await httpCall('POST', '/users/trusted-skills', { userId: fp, skillId: ARGS[1], permission: 'unredacted' });
          result.intent = 'privacy:trust';
          const trusted = config.trusted_skills ? config.trusted_skills.split(',') : [];
          trusted.push(ARGS[1]);
          writeConfig('trusted_skills', trusted.join(','));
          break;

        case 'untrust':
          if (ARGS.length < 2) {
            result = { error: 'missing_argument', hint: 'Usage: privacy untrust <skillId>' };
            break;
          }
          const untrusted = (config.trusted_skills ? config.trusted_skills.split(',') : []).filter(s => s !== ARGS[1]);
          writeConfig('trusted_skills', untrusted.join(','));
          result = { intent: 'privacy:untrust', skillId: ARGS[1] };
          break;

        case 'delete-all':
          if (!ARGS.includes('--confirm')) {
            result = { error: 'confirm_required', destructive_scope: 'local CONFIG.md + cache + trash + backend data (events, skill records, consents, trusted skills, recommendation feedback, share reports)' };
            break;
          }
          const deleteResp = await httpCall('DELETE', '/users/data');
          fs.rmSync(CONFIG_FILE, { force: true });
          fs.rmSync(CACHE_DIR, { recursive: true, force: true });
          fs.rmSync(TRASH_DIR, { recursive: true, force: true });
          const preservedFp = config.device_fp;
          fs.writeFileSync(CONFIG_FILE, `# Mapickii Configuration\n# Auto-generated\n\ndevice_fp: ${preservedFp}\n`);
          result = { intent: 'privacy:delete-all', localCleared: true, backendResponse: deleteResp };
          break;

        case 'consent-agree':
          const version = ARGS[1] || '1.0';
          const now = isoNow();
          await httpCall('POST', '/users/consent', { consentVersion: version, agreedAt: now });
          writeConfig('consent_version', version);
          writeConfig('consent_agreed_at', now);
          deleteConfig('consent_declined');
          deleteConfig('consent_declined_at');
          result = { intent: 'privacy:consent-agree', version, agreedAt: now };
          break;

        case 'consent-decline':
          const declinedAt = isoNow();
          writeConfig('consent_declined', 'true');
          writeConfig('consent_declined_at', declinedAt);
          result = { intent: 'privacy:consent-decline', mode: 'local_only', declinedAt };
          break;

        case 'disable-redact':
          writeConfig('redact_disabled', 'true');
          writeConfig('redact_disabled_at', isoNow());
          result = { intent: 'privacy:disable-redact', status: 'disabled', warning: 'Sensitive data will be passed AS-IS' };
          break;

        case 'enable-redact':
          deleteConfig('redact_disabled');
          deleteConfig('redact_disabled_at');
          result = { intent: 'privacy:enable-redact', status: 'enabled' };
          break;

        default:
          result = { error: 'unknown_subcommand', hint: 'Available: status | trust | untrust | delete-all | consent-agree | consent-decline | disable-redact | enable-redact' };
      }
      break;

    case 'event':
    case 'event:track':
      if (ARGS.length < 2) {
        result = { error: 'missing_argument', hint: 'Usage: event:track <userId> <action> [skillId]' };
        break;
      }
      const [userId, actionType, metaSkillId] = ARGS;
      if (!VALID_EVENT_ACTIONS.includes(actionType)) {
        result = { error: 'invalid_action', valid: VALID_EVENT_ACTIONS };
        break;
      }
      result = await httpCall('POST', '/events/track', { userId, action: actionType, skillId: metaSkillId || null });
      result.intent = 'event:track';
      break;

    case 'id':
      result = { device_fp: fp };
      break;

    case 'help':
    case '--help':
    case '-h':
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
  id                      Device fingerprint (debug)

Env: MAPICKII_API_BASE (default: https://api.mapick.ai/v1)`);
      result = { error: 'usage' };
      break;

    default:
      result = { error: 'unknown_command', command: COMMAND, hint: 'Run help for usage' };
  }

  console.log(JSON.stringify(result));
}

main().catch(e => console.log(JSON.stringify({ error: e.message })));