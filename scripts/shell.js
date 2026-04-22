#!/usr/bin/env node
/**
 * Mapickii skill unified entry point (Node.js)
 * Usage: node shell.js <command> [args...]
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const http = require('https');

const CONFIG_DIR = path.dirname(__dirname);
const CONFIG_FILE = path.join(CONFIG_DIR, 'CONFIG.md');
const API_BASE = process.env.MAPICKII_API_BASE || 'https://api.mapick.ai/v1';
const SKILLS_BASE = process.env.SKILLS_BASE || path.join(process.env.HOME, '.openclaw', 'skills');

const DEVICE_FP = crypto.createHash('sha256')
  .update(`${require('os').hostname()}|${process.platform}|${process.env.HOME}`)
  .digest('hex')
  .slice(0, 16);

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
  const lines = ['# Mapickii Configuration', '# Auto-generated', ''];
  Object.entries(config).forEach(([k, v]) => lines.push(`${k}: ${v}`));
  fs.writeFileSync(CONFIG_FILE, lines.join('\n'));
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
      'x-device-fp': DEVICE_FP
    }
  };
  
  return new Promise((resolve, reject) => {
    const req = http.request(options, res => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch { resolve({ error: 'parse_error', raw: data }); }
      });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function scanSkills() {
  const skills = [];
  if (fs.existsSync(SKILLS_BASE)) {
    const dirs = fs.readdirSync(SKILLS_BASE);
    dirs.forEach(dir => {
      const skillPath = path.join(SKILLS_BASE, dir);
      const skillFile = path.join(skillPath, 'SKILL.md');
      if (fs.statSync(skillPath).isDirectory() && fs.existsSync(skillFile)) {
        const content = fs.readFileSync(skillFile, 'utf8');
        const nameMatch = content.match(/^---\nname:\s*(.+)\n/);
        skills.push({
          id: dir,
          name: nameMatch ? nameMatch[1].trim() : dir,
          path: skillPath,
          installed_at: new Date().toISOString(),
          enabled: true
        });
      }
    });
  }
  return skills;
}

const COMMAND = process.argv[2] || 'status';
const ARGS = process.argv.slice(3);

async function main() {
  const config = readConfig();
  let result;

  switch (COMMAND) {
    case 'init':
    case 'status':
      const skills = await scanSkills();
      if (!config.device_fp) {
        writeConfig('device_fp', DEVICE_FP);
        writeConfig('created_at', new Date().toISOString());
        result = {
          status: 'first_install',
          data: { deviceFingerprint: DEVICE_FP, skillsCount: skills.length, skillNames: skills.map(s => s.name) },
          privacy: 'Anonymous by design. No registration.'
        };
      } else {
        result = {
          intent: 'status',
          device_fp: config.device_fp,
          skills: skills,
          activation_rate: skills.length > 0 ? '100%' : '0%'
        };
      }
      break;

    case 'recommend':
      const limit = parseInt(ARGS[0]) || 5;
      result = await httpCall('GET', `/recommend/feed?limit=${limit}`);
      result.intent = 'recommend';
      break;

    case 'search':
      const query = ARGS[0] || '';
      const searchLimit = parseInt(ARGS[1]) || 10;
      result = await httpCall('GET', `/skills/live-search?query=${encodeURIComponent(query)}&limit=${searchLimit}`);
      result.intent = 'search';
      if (result.results) {
        result.items = result.results;
        delete result.results;
      }
      break;

    case 'clean':
      result = { intent: 'clean', zombies: [] };
      break;

    case 'workflow':
      result = { intent: 'workflow', sequences: [] };
      break;

    case 'daily':
      result = { intent: 'daily', events: [] };
      break;

    case 'weekly':
      result = { intent: 'weekly', summary: {} };
      break;

    case 'bundle':
      result = await httpCall('GET', '/bundle/list');
      result.intent = 'bundle';
      break;

    case 'id':
      result = { device_fp: DEVICE_FP };
      break;

    case 'help':
    case '--help':
    case '-h':
      console.error(`Mapickii - Node.js version

Usage: node shell.js <command> [args...]

Commands:
  init / status      Skill status overview
  recommend [limit]  Personalized recommendations
  search <query>     Search skills
  clean              Zombie skill list
  workflow           Workflow analysis
  daily              Daily digest
  weekly             Weekly report
  bundle             Bundle list
  id                 Device fingerprint (debug)

Env: MAPICKII_API_BASE (default: https://api.mapick.ai/v1)`);
      result = { error: 'usage' };
      break;

    default:
      result = { error: 'unknown_command', command: COMMAND };
  }

  console.log(JSON.stringify(result));
}

main().catch(e => console.log(JSON.stringify({ error: e.message })));