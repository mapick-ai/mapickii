<p align="center">
  <img src="assets/mapick_banner.png" alt="Mapickii Banner" width="720" />
</p>

<h1 align="center">Mapickii</h1>

<p align="center">
  <strong>The Mapick Butler — Skill lifecycle management · smart recommendations · bundle suggestions</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-3.0-blue?style=flat-square" alt="Version" />
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License" />
  <img src="https://img.shields.io/badge/modules-M1%20%7C%20M2%20%7C%20M3-orange?style=flat-square" alt="Modules" />
  <img src="https://img.shields.io/badge/platform-OpenClaw-purple?style=flat-square" alt="Platform" />
</p>

<p align="center">
  <a href="https://mapick.ai">Website</a> &nbsp;|&nbsp;
  <a href="https://discord.gg/ju8rzvtm5">Discord</a> &nbsp;|&nbsp;
  <a href="#install">Install</a> &nbsp;|&nbsp;
  <a href="#commands">Commands</a> &nbsp;|&nbsp;
  <a href="README.zh-CN.md">中文</a>
</p>

---

## What is Mapickii?

Mapickii is the intelligent butler of the Mapick ecosystem. It bundles three modules — M1, M2, M3 — and manages the full Skill lifecycle inside your AI coding tool: installation, usage tracking, frequency analysis, zombie cleanup, and personalized recommendations for individual Skills or complete bundles.

**Core capabilities:**

- **M1 · Lifecycle** — Status overview, zombie detection & cleanup, workflow analysis, daily/weekly reports
- **M2 · Smart recommendations** — Returns a recommended Skill on every interaction, with 24h local cache (zero overhead)
- **M3 · Bundle suggestions** — Pre-defined scenario bundles, installed-coverage calculation, one-click completion
- **Identity management** — Register a Mapick ID, bind multiple devices, or stay fully local
- **Referral codes** — Auto-generated 6-digit codes, one-time binding
- **Push cadence** — Daily / weekly / muted, switchable via natural language

## Supported Platform

| Platform | Vendor   | Install directory              |
| -------- | -------- | ------------------------------ |
| OpenClaw | OpenClaw | `~/.openclaw/skills/mapickii/` |

Mapickii V1 targets OpenClaw — the open Skill marketplace. Other AI coding
CLIs run their own closed Skill directories and are out of scope for this
release.

## <a name="install"></a>Install

### One-line install (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/mapick-ai/mapickii/v1.0.1/install.sh | bash
```

Or with `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/mapick-ai/mapickii/v1.0.1/install.sh | bash
```

Pin a specific version:

```bash
MAPICKII_VERSION=v1.0.0 bash -c "$(curl -fsSL https://raw.githubusercontent.com/mapick-ai/mapickii/main/install.sh)"
```

### Manual install

```bash
git clone https://github.com/mapick-ai/mapickii.git
bash mapickii/install.sh
```

Both paths install to `~/.openclaw/skills/mapickii/` and require OpenClaw
(`claw` or `openclaw` CLI) to be on your `$PATH`.

## <a name="commands"></a>Commands

After install, use `/mapickii <command>` inside your AI tool:

### M1 · Lifecycle

| Command                | Description                                                       |
| ---------------------- | ----------------------------------------------------------------- |
| `/mapickii`            | Status overview                                                   |
| `/mapickii status`     | Detailed status (active / low-frequency / zombie / never-invoked) |
| `/mapickii clean`      | List zombie Skills and choose which to uninstall                  |
| `/mapickii workflow`   | High-frequency sequences and bundle matches                       |
| `/mapickii daily`      | Daily report (yesterday's output + today's picks)                 |
| `/mapickii weekly`     | Weekly report (summary + trends)                                  |
| `/mapickii scan`       | Rescan local Skills                                               |
| `/mapickii chat <msg>` | Natural-language fallback                                         |

### M3 · Bundles

| Command                         | Description                                      |
| ------------------------------- | ------------------------------------------------ |
| `/mapickii bundle`              | List all bundles                                 |
| `/mapickii bundle <id>`         | Bundle detail (installed / missing + match rate) |
| `/mapickii bundle recommend`    | Suggest bundles based on installed Skills        |
| `/mapickii bundle install <id>` | One-click install of missing Skills              |

### Identity & referrals

| Command                   | Description                                |
| ------------------------- | ------------------------------------------ |
| `/mapickii register`      | Register a new Mapick identity             |
| `/mapickii id`            | Show the current identity                  |
| `/mapickii login <MP-ID>` | Bind an existing Mapick ID                 |
| `/mapickii ref`           | Show your referral code and referral count |
| `/mapickii ref <code>`    | Bind a referral code (one-time, immutable) |

### Uninstall

| Command                                                               | Description                                       |
| --------------------------------------------------------------------- | ------------------------------------------------- |
| `/mapickii uninstall <skillId>`                                       | Dry-run — returns the paths that would be removed |
| `/mapickii uninstall <skillId> --confirm`                             | Confirm removal (backup + `rm -rf`)               |
| `/mapickii uninstall <skillId> --scope user\|project\|both --confirm` | Remove by scope                                   |

Protected Skills — `mapickii` / `mapick` / `tasa` — cannot be removed.

### Push cadence

| Command                 | Description |
| ----------------------- | ----------- |
| `/mapickii push daily`  | Daily push  |
| `/mapickii push weekly` | Weekly push |
| `/mapickii push off`    | Mute        |

## Natural-language triggers

You don't need the `/mapickii` prefix — these phrases are recognized directly:

- **"status", "how is it going", "my skill library"** → `status`
- **"clean up", "zombies", "unused"** → `clean`
- **"workflow", "common combos"** → `workflow`
- **"daily", "how's today"** → `daily`
- **"weekly", "this week"** → `weekly`
- **"bundle", "bundle recommendation"** → `bundle:recommend`
- **"stop pushing", "mute", "do not disturb"** → `push:off`
- **"switch to weekly", "push less"** → `push:weekly`
- **"turn on push", "resume push"** → `push:daily`

## Lifecycle model

```
Install ──→ First use ──→ Active use ──→ Declining ──→ Zombie ──→ Uninstall
   ↑            ↑            ↑              ↑            ↑           ↑
Mapickii    Mapickii     Mapickii       Mapickii     Mapickii    user
   scan       records      records        records      flags      triggers
```

| Stage              | Trigger                          | Behavior                            |
| ------------------ | -------------------------------- | ----------------------------------- |
| Install            | Skill directory exists           | Record install time and path        |
| First use          | First invocation                 | Measure activation delay            |
| Activation timeout | No call within 7 days of install | Flag `activation_timeout`           |
| Active use         | ≥ 2 calls in 7 days              | Compute frequency, detect sequences |
| Declining          | This week < 50% of last week     | Internal flag                       |
| Zombie             | No call in 30 days               | Flag `zombie`, add to cleanup list  |
| Uninstall          | User-triggered                   | Record reason, back up to `trash/`  |

## Privacy

- Conversations and code **never leave your device**
- Only anonymous behavior signals are collected: `skill_id`, `timestamp`, `task_classification`
- Identity config is stored locally (`CONFIG.md`)
- No cloud-side social-graph storage

## Directory layout

```
mapickii/
├── README.md          # this document (English)
├── README.zh-CN.md    # Chinese version
├── SKILL.md           # Skill instructions (read by the AI)
├── CONFIG.md          # User identity config (preserved across upgrades)
├── install.sh         # Remote one-line install script
├── scripts/
│   └── shell.sh       # Command execution script
├── v1/                # v1 backup
└── v2.1/              # v2.1 backup
```

## Version history

| Version | Date       | Changes                             |
| ------- | ---------- | ----------------------------------- |
| v3.0    | 2026-04-18 | Added M3 bundle recommendations     |
| v2.1    | 2026-04-18 | Smart recommendations + cache       |
| v2.0    | 2026-04-18 | Synced doc spec and lifecycle model |
| v1.0    | 2026-04-17 | Initial release                     |

## License

[MIT](LICENSE) © 2026 Mapick.AI
